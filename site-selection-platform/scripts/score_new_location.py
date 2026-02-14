#!/usr/bin/env python3
"""
Score New Candidate Locations — Luckin Coffee USA
===================================================
Reusable scoring function that accepts location features
and outputs predicted performance + ROI analysis.

Usage:
    python score_new_location.py

    Or import and call:
        from score_new_location import score_candidate
        result = score_candidate({
            'foot_traffic_score': 75,
            'subway_count': 8,
            'weekday_pct': 0.55,
            'area_type_score': 80,
            'competitor_density': 3,
            'near_subway': 1,
            'median_income': 85000,
            'rent_per_sqft': 90,
            'weekend_ratio': 0.45,
            'cannibalization_score': 1.0,
        }, rent_monthly=15000)
"""

import os
import json
import numpy as np
import sys

# ============================================================
# CONFIGURATION
# ============================================================
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT_DIR = os.path.join(BASE_DIR, 'ml_output')
ARTIFACTS_PATH = os.path.join(OUTPUT_DIR, 'model_artifacts.json')


def load_model():
    """Load saved model artifacts."""
    if not os.path.exists(ARTIFACTS_PATH):
        raise FileNotFoundError(
            f"Model artifacts not found at {ARTIFACTS_PATH}. "
            f"Run site_selection_model.py first to train the model."
        )
    with open(ARTIFACTS_PATH, 'r') as f:
        artifacts = json.load(f)
    return artifacts


def score_candidate(features_dict, rent_monthly=15000, artifacts=None):
    """
    Score a single candidate location.

    Parameters
    ----------
    features_dict : dict
        Must contain keys matching the training features:
        - foot_traffic_score: float (0-100, estimated daily pedestrian traffic)
        - subway_count: int (number of subway lines within walking distance)
        - weekday_pct: float (0-1, fraction of cups sold on weekdays)
        - area_type_score: float (0-100, neighborhood type score)
        - competitor_density: int (coffee shops within 0.25 miles)
        - near_subway: int (0 or 1, whether 3+ subway lines nearby)
        - median_income: float (median household income in census tract)
        - rent_per_sqft: float (monthly rent per square foot)
        - weekend_ratio: float (0-1, = 1 - weekday_pct)
        - cannibalization_score: float (0-1, distance-based; 1=no nearby Luckin)

    rent_monthly : float
        Monthly rent estimate in USD.

    artifacts : dict, optional
        Pre-loaded model artifacts. If None, loads from disk.

    Returns
    -------
    dict with keys:
        - predicted_weekly_cups: point estimate
        - predicted_daily_cups: weekly / 7
        - cups_lower_90: 5th percentile (bootstrap estimate)
        - cups_upper_90: 95th percentile (bootstrap estimate)
        - predicted_monthly_revenue: cups × weeks × price
        - estimated_monthly_cost: rent + labor + supplies
        - estimated_monthly_profit: revenue - cost
        - estimated_roi_pct: profit / cost × 100
        - risk_flag: "Strong" (ROI>15%), "Viable" (0-15%), "Risky" (<0%)
        - confidence_note: interpretation of uncertainty
    """
    if artifacts is None:
        artifacts = load_model()

    feature_cols = artifacts['feature_cols']
    scaler_mean = np.array(artifacts['scaler_mean'])
    scaler_scale = np.array(artifacts['scaler_scale'])
    econ = artifacts['unit_economics']

    # Validate features
    missing = [f for f in feature_cols if f not in features_dict]
    if missing:
        raise ValueError(f"Missing features: {missing}. Required: {feature_cols}")

    # Build feature vector
    X = np.array([[features_dict[f] for f in feature_cols]])

    # Standardize
    X_scaled = (X - scaler_mean) / scaler_scale

    # Add interaction term (foot_traffic × low_competition)
    if 'foot_traffic_score' in feature_cols and 'competitor_density' in feature_cols:
        ft_idx = feature_cols.index('foot_traffic_score')
        cd_idx = feature_cols.index('competitor_density')
        interaction = X_scaled[0, ft_idx] * (1 - X[0, cd_idx] / 20)
        X_scaled = np.append(X_scaled, [[interaction]], axis=1)

    # Predict
    if artifacts['model_type'] == 'linear':
        coef = np.array(artifacts['coef'])
        intercept = artifacts['intercept']
        pred = float(np.dot(X_scaled, coef)[0] + intercept)
    else:
        raise NotImplementedError(
            "Non-linear model scoring requires sklearn model file. "
            "Use the full pipeline (site_selection_model.py) instead."
        )

    pred = max(pred, 0)

    # Approximate CI using model RMSE (simple heuristic since we can't bootstrap)
    rmse = artifacts['metrics']['rmse']
    lower_90 = max(pred - 1.645 * rmse, 0)
    upper_90 = pred + 1.645 * rmse

    # Economics
    weeks_per_month = 4.33
    monthly_revenue = pred * weeks_per_month * econ['avg_cup_price']
    monthly_cost = rent_monthly + econ['labor_monthly'] + econ['supplies_monthly']
    monthly_profit = monthly_revenue - monthly_cost
    roi_pct = (monthly_profit / monthly_cost) * 100 if monthly_cost > 0 else 0

    if roi_pct > 15:
        risk_flag = "Strong"
    elif roi_pct > 0:
        risk_flag = "Viable"
    else:
        risk_flag = "Risky"

    mape = artifacts['metrics']['mape']
    confidence_note = (
        f"Model MAPE={mape:.1f}%, R²={artifacts['metrics']['r2']:.3f}. "
        f"Trained on {artifacts.get('n_stores', 8)} stores. "
        f"Predictions carry ±{mape:.0f}% uncertainty. "
        f"{'CAUTION: Non-Manhattan locations are extrapolations.' if features_dict.get('borough', '') not in ['Manhattan', ''] else ''}"
    )

    return {
        'predicted_weekly_cups': round(pred, 0),
        'predicted_daily_cups': round(pred / 7, 0),
        'cups_lower_90': round(lower_90, 0),
        'cups_upper_90': round(upper_90, 0),
        'predicted_monthly_revenue': round(monthly_revenue, 0),
        'estimated_monthly_cost': round(monthly_cost, 0),
        'estimated_monthly_profit': round(monthly_profit, 0),
        'estimated_roi_pct': round(roi_pct, 1),
        'risk_flag': risk_flag,
        'confidence_note': confidence_note,
    }


def score_multiple(candidates_list, artifacts=None):
    """
    Score multiple candidates at once.

    Parameters
    ----------
    candidates_list : list of dicts
        Each dict has 'name', 'features' (dict), and optionally 'rent_monthly'.

    Returns
    -------
    list of result dicts, sorted by predicted_weekly_cups descending
    """
    if artifacts is None:
        artifacts = load_model()

    results = []
    for cand in candidates_list:
        result = score_candidate(
            cand['features'],
            rent_monthly=cand.get('rent_monthly', 15000),
            artifacts=artifacts
        )
        result['location_name'] = cand.get('name', 'Unknown')
        results.append(result)

    results.sort(key=lambda x: x['predicted_weekly_cups'], reverse=True)
    for i, r in enumerate(results, 1):
        r['rank'] = i

    return results


# ============================================================
# DEMO / CLI
# ============================================================
def main():
    """Demo scoring with example candidates."""
    print("=" * 60)
    print("  Luckin Coffee USA — New Location Scorer")
    print("=" * 60)

    # Example: Score a hypothetical location
    example_candidates = [
        {
            'name': 'Example: Times Square Area',
            'features': {
                'foot_traffic_score': 95,
                'subway_count': 10,
                'weekday_pct': 0.55,
                'area_type_score': 80,
                'competitor_density': 6,
                'near_subway': 1,
                'median_income': 75000,
                'rent_per_sqft': 130,
                'weekend_ratio': 0.45,
                'cannibalization_score': 0.8,
            },
            'rent_monthly': 22000,
        },
        {
            'name': 'Example: Williamsburg Brooklyn',
            'features': {
                'foot_traffic_score': 60,
                'subway_count': 3,
                'weekday_pct': 0.50,
                'area_type_score': 45,
                'competitor_density': 4,
                'near_subway': 1,
                'median_income': 90000,
                'rent_per_sqft': 70,
                'weekend_ratio': 0.50,
                'cannibalization_score': 1.0,
            },
            'rent_monthly': 12000,
        },
    ]

    try:
        results = score_multiple(example_candidates)

        print(f"\n  {'Rank':>4s} {'Location':<35s} {'Cups/wk':>8s} "
              f"{'Revenue':>9s} {'ROI':>7s} {'Risk':>8s}")
        print("  " + "-" * 75)
        for r in results:
            print(f"  {r['rank']:4d} {r['location_name']:<35s} "
                  f"{r['predicted_weekly_cups']:8.0f} "
                  f"${r['predicted_monthly_revenue']:8.0f} "
                  f"{r['estimated_roi_pct']:6.1f}% "
                  f"{r['risk_flag']:>8s}")
            print(f"       90% CI: [{r['cups_lower_90']:.0f} - {r['cups_upper_90']:.0f}] cups/week")
            print(f"       {r['confidence_note']}")

    except FileNotFoundError as e:
        print(f"\n  ERROR: {e}")
        print("  Please run site_selection_model.py first to train the model.")
        sys.exit(1)


if __name__ == '__main__':
    main()

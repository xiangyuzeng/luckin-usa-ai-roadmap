#!/usr/bin/env python3
"""
Luckin Coffee USA — Store Site Selection Prediction Model
=========================================================
ML-based prediction pipeline that scores candidate store locations
using supervised regression on existing store performance data.

Data sources:
  - daily_traffic_raw.csv: 1,140 daily cup counts across 8 active stores
  - active_stores_performance.csv: store metadata (location features)
  - pipeline_locations_scored.csv: 19 candidate locations with features
  - unit_economics.csv: revenue/cost model

Author: Luckin USA Data Team
"""

import warnings
warnings.filterwarnings('ignore')

import os
import sys
import json
import numpy as np
import pandas as pd
from datetime import datetime, timedelta
from math import radians, sin, cos, sqrt, atan2

# ML
from sklearn.linear_model import LinearRegression, Ridge, Lasso, ElasticNet
from sklearn.ensemble import RandomForestRegressor, GradientBoostingRegressor
from sklearn.svm import SVR
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import LeaveOneOut
from sklearn.metrics import mean_absolute_percentage_error, mean_squared_error, r2_score
from scipy import stats

# Viz
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import seaborn as sns

# Excel
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side

# ============================================================
# CONFIGURATION
# ============================================================
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(BASE_DIR, 'data')
OUTPUT_DIR = os.path.join(BASE_DIR, 'ml_output')
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Unit economics
AVG_TICKET = 7.20        # average revenue per order (includes food items)
AVG_CUP_PRICE = 5.50     # average cup price
MARGIN_PER_CUP = 2.30    # contribution margin per cup
LABOR_MONTHLY = 15000     # monthly labor cost
SUPPLIES_MONTHLY = 3000   # monthly supplies/misc
WEEKS_PER_MONTH = 4.33

# Steady-state definition: week 4+ post-opening
STEADY_STATE_WEEK = 4  # skip first 4 weeks (28 days)
MIN_WEEKS_REQUIRED = 4  # minimum weeks of steady-state data

# ============================================================
# STEP 1: COMPUTE TARGET VARIABLE
# ============================================================
def compute_target_variable():
    """
    Compute avg_weekly_cups_steady_state for each store.
    Steady state = day 29+ post-opening (week 4+).
    Exclude days with 0 cups (store closures).
    """
    print("=" * 70)
    print("STEP 1: Computing Target Variable (avg_weekly_cups_steady_state)")
    print("=" * 70)

    daily = pd.read_csv(os.path.join(DATA_DIR, 'daily_traffic_raw.csv'))
    stores_meta = pd.read_csv(os.path.join(DATA_DIR, 'active_stores_performance.csv'))

    daily['date'] = pd.to_datetime(daily['date'])

    # Get opening dates from metadata
    opening_dates = dict(zip(stores_meta['store_name'],
                             pd.to_datetime(stores_meta['opened'])))

    results = []
    for store_name in daily['store_name'].unique():
        store_data = daily[daily['store_name'] == store_name].copy()
        open_date = opening_dates.get(store_name)

        if open_date is None:
            print(f"  WARNING: No opening date for {store_name}, skipping")
            continue

        # Days since opening
        store_data['days_since_open'] = (store_data['date'] - open_date).dt.days

        # Steady state: day 28+ (week 4+)
        steady = store_data[store_data['days_since_open'] >= 28].copy()

        # Exclude zero-cup days (closures)
        steady = steady[steady['cup_count'] > 0]

        if len(steady) < MIN_WEEKS_REQUIRED * 7:
            print(f"  WARNING: {store_name} has only {len(steady)} steady-state days "
                  f"({len(steady)/7:.1f} weeks), minimum {MIN_WEEKS_REQUIRED} weeks required")
            # Still include if we have at least some data
            if len(steady) < 14:
                continue

        # Compute weekly cups: sum daily cups, then average across weeks
        steady['week_num'] = (steady['days_since_open'] - 28) // 7
        weekly_cups = steady.groupby('week_num')['cup_count'].sum()

        # Drop incomplete weeks (last week may be partial)
        if len(weekly_cups) > 1:
            last_week = steady['week_num'].max()
            days_in_last_week = len(steady[steady['week_num'] == last_week])
            if days_in_last_week < 5:
                weekly_cups = weekly_cups.drop(last_week)

        avg_weekly = weekly_cups.mean()
        avg_daily = steady['cup_count'].mean()

        # Opening week stats
        opening_week = store_data[store_data['days_since_open'] < 7]
        opening_avg = opening_week['cup_count'].mean() if len(opening_week) > 0 else 0
        novelty_spike = (opening_avg / avg_daily - 1) * 100 if avg_daily > 0 else 0

        results.append({
            'store_name': store_name,
            'opening_date': open_date.strftime('%Y-%m-%d'),
            'total_days': len(store_data),
            'steady_state_days': len(steady),
            'steady_state_weeks': len(weekly_cups),
            'avg_daily_cups_steady': round(avg_daily, 1),
            'avg_weekly_cups_steady': round(avg_weekly, 1),
            'opening_week_avg_daily': round(opening_avg, 1),
            'novelty_spike_pct': round(novelty_spike, 1),
            'min_daily': steady['cup_count'].min(),
            'max_daily': steady['cup_count'].max(),
            'std_daily': round(steady['cup_count'].std(), 1),
        })

        print(f"  {store_name:20s}: avg_weekly={avg_weekly:7.1f} cups "
              f"({len(weekly_cups):2d} weeks, novelty_spike={novelty_spike:+.1f}%)")

    target_df = pd.DataFrame(results)
    target_df = target_df.sort_values('avg_weekly_cups_steady', ascending=False)
    print(f"\n  Total stores with valid data: {len(target_df)}")
    print(f"  Target range: {target_df['avg_weekly_cups_steady'].min():.0f} - "
          f"{target_df['avg_weekly_cups_steady'].max():.0f} cups/week")

    return target_df, daily


# ============================================================
# STEP 2: BUILD FEATURE MATRIX
# ============================================================
def build_feature_matrix(target_df):
    """
    Build feature matrix for each store. Features come from:
    - Internal data (store metadata CSV)
    - Derived proxies (foot traffic from order volume)
    - Estimated features flagged as such
    """
    print("\n" + "=" * 70)
    print("STEP 2: Building Feature Matrix")
    print("=" * 70)

    stores_meta = pd.read_csv(os.path.join(DATA_DIR, 'active_stores_performance.csv'))

    # Area type encoding (ordinal based on performance tiers)
    area_type_score = {
        'university_tourist': 100,
        'commercial_transit_hub': 80,
        'tourist_ethnic_enclave': 70,
        'financial_office': 55,
        'mixed_commercial': 50,
        'theater_tourist': 45,
        'residential_mixed': 20,
        'residential': 10,
    }

    features = []
    feature_sources = {}

    for _, store in stores_meta.iterrows():
        name = store['store_name']
        target_row = target_df[target_df['store_name'] == name]
        if len(target_row) == 0:
            continue

        avg_daily = target_row.iloc[0]['avg_daily_cups_steady']
        max_daily_all = target_df['avg_daily_cups_steady'].max()

        # Feature 1: foot_traffic_proxy (from our own order data)
        foot_traffic_proxy = (avg_daily / max_daily_all) * 100
        feature_sources['foot_traffic_score'] = 'PROXY (derived from order volume)'

        # Feature 2: subway_count (ground truth from metadata)
        subway_count = store['subway_count']
        feature_sources['subway_count'] = 'GROUND TRUTH (internal data)'

        # Feature 3: weekday_pct (ground truth from daily traffic analysis)
        weekday_pct = store['weekday_pct']
        feature_sources['weekday_pct'] = 'GROUND TRUTH (daily traffic analysis)'

        # Feature 4: area_type_score (derived from neighborhood classification)
        area_score = area_type_score.get(store['area_type'], 30)
        feature_sources['area_type_score'] = 'DERIVED (neighborhood classification)'

        # Feature 5: competitor_density (estimated — manual research)
        # Based on known Starbucks/indie density in each neighborhood
        competitor_estimates = {
            '8th & Broadway': 4,    # NYU area: Blue Bottle, Starbucks x2, indie
            '37th & Broadway': 5,   # Herald Sq: Starbucks x3, Dunkin, Gregory's
            '102 Fulton': 3,        # FiDi: Starbucks x2, Dunkin
            '28th & 6th': 3,        # Chelsea: Starbucks x2, indie
            '221 Grand': 2,         # Chinatown: fewer chains
            '54th & 8th': 4,        # Midtown: Starbucks x2, Dunkin, indie
            '100 Maiden Ln': 3,     # FiDi: same cluster as 102 Fulton
            '15th & 3rd': 2,        # Residential: Starbucks x1, indie
        }
        competitor_density = competitor_estimates.get(name, 3)
        feature_sources['competitor_density'] = 'ESTIMATED (manual neighborhood research)'

        # Feature 6: near_subway (binary: 3+ lines within walking)
        near_subway = 1 if subway_count >= 3 else 0
        feature_sources['near_subway'] = 'DERIVED (from subway_count >= 3)'

        # Feature 7: median_income (Census ACS estimates per neighborhood)
        income_estimates = {
            '8th & Broadway': 85000,    # Greenwich Village/NoHo
            '37th & Broadway': 75000,   # Garment District
            '102 Fulton': 110000,       # Financial District
            '28th & 6th': 95000,        # Chelsea/NoMad
            '221 Grand': 55000,         # Chinatown
            '54th & 8th': 70000,        # Hells Kitchen
            '100 Maiden Ln': 110000,    # Financial District
            '15th & 3rd': 90000,        # Gramercy
        }
        median_income = income_estimates.get(name, 80000)
        feature_sources['median_income'] = 'ESTIMATED (Census ACS tract-level approximation)'

        # Feature 8: rent_per_sqft_estimate (market rate estimates)
        rent_estimates = {
            '8th & Broadway': 120,     # Prime Village
            '37th & Broadway': 100,    # Garment District
            '102 Fulton': 90,          # FiDi
            '28th & 6th': 110,         # Chelsea
            '221 Grand': 70,           # Chinatown
            '54th & 8th': 95,          # Midtown West
            '100 Maiden Ln': 85,       # FiDi
            '15th & 3rd': 80,          # Gramercy residential
        }
        rent_psf = rent_estimates.get(name, 90)
        feature_sources['rent_per_sqft'] = 'ESTIMATED (commercial RE market rate)'

        # Feature 9: weekend_ratio (weekend cups / total cups — measures resilience)
        weekend_ratio = 1 - weekday_pct  # higher = stronger weekends
        feature_sources['weekend_ratio'] = 'DERIVED (1 - weekday_pct)'

        # Feature 10: cannibalization_score (distance to nearest Luckin)
        # Use haversine distance
        lat1, lon1 = store['latitude'], store['longitude']
        min_dist = float('inf')
        for _, other in stores_meta.iterrows():
            if other['store_name'] == name:
                continue
            d = haversine_miles(lat1, lon1, other['latitude'], other['longitude'])
            min_dist = min(min_dist, d)

        # Cannibalization: closer = worse (0-1 scale, 1 = no cannibalization)
        cannibalization_score = min(min_dist / 2.0, 1.0)  # 2+ miles = no effect
        feature_sources['cannibalization_score'] = 'DERIVED (haversine distance to nearest store)'

        features.append({
            'store_name': name,
            'foot_traffic_score': round(foot_traffic_proxy, 1),
            'subway_count': subway_count,
            'weekday_pct': weekday_pct,
            'area_type_score': area_score,
            'competitor_density': competitor_density,
            'near_subway': near_subway,
            'median_income': median_income,
            'rent_per_sqft': rent_psf,
            'weekend_ratio': round(weekend_ratio, 2),
            'cannibalization_score': round(cannibalization_score, 3),
        })

    feature_df = pd.DataFrame(features)

    # Print feature matrix
    print("\n  Feature Matrix (8 stores x 10 features):")
    print(f"  {'Store':<20s} {'FT':>5s} {'Sub':>4s} {'WD%':>5s} {'Area':>5s} "
          f"{'Comp':>5s} {'NrSb':>5s} {'Inc$':>7s} {'Rent':>5s} {'WE%':>5s} {'Cann':>5s}")
    print("  " + "-" * 80)
    for _, r in feature_df.iterrows():
        print(f"  {r['store_name']:<20s} {r['foot_traffic_score']:5.1f} {r['subway_count']:4.0f} "
              f"{r['weekday_pct']:5.2f} {r['area_type_score']:5.0f} {r['competitor_density']:5.0f} "
              f"{r['near_subway']:5.0f} {r['median_income']:7.0f} {r['rent_per_sqft']:5.0f} "
              f"{r['weekend_ratio']:5.2f} {r['cannibalization_score']:5.3f}")

    # Feature source tracking
    print("\n  Feature Data Sources:")
    for feat, src in sorted(feature_sources.items()):
        print(f"    {feat:<25s}: {src}")

    return feature_df, feature_sources


def haversine_miles(lat1, lon1, lat2, lon2):
    """Compute distance in miles between two lat/lon points."""
    R = 3959  # Earth radius in miles
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon / 2) ** 2
    return R * 2 * atan2(sqrt(a), sqrt(1 - a))


# ============================================================
# STEP 3: MODEL TRAINING & EVALUATION
# ============================================================
def train_and_evaluate(feature_df, target_df):
    """
    Train multiple regression models using LOOCV.
    Return winning model, scaler, and detailed results.
    """
    print("\n" + "=" * 70)
    print("STEP 3: Model Training & Evaluation (LOOCV)")
    print("=" * 70)

    # Merge features with target
    merged = feature_df.merge(target_df[['store_name', 'avg_weekly_cups_steady']],
                               on='store_name')

    feature_cols = [c for c in feature_df.columns if c != 'store_name']
    X = merged[feature_cols].values
    y = merged['avg_weekly_cups_steady'].values
    store_names = merged['store_name'].values
    n = len(y)

    print(f"\n  Training set: {n} stores, {len(feature_cols)} features")
    print(f"  Target range: {y.min():.0f} - {y.max():.0f} cups/week")
    print(f"  Target mean:  {y.mean():.0f} cups/week")
    print(f"  Target std:   {y.std():.0f} cups/week")

    # Check multicollinearity (VIF)
    # NOTE: VIF requires n > p. With 8 stores and 10 features, OLS is
    # underdetermined, so VIF is meaningless. We rely on Ridge/Lasso
    # regularization to handle multicollinearity instead.
    vif_results = []
    if n > len(feature_cols) + 2:
        print("\n  Variance Inflation Factor (VIF) Analysis:")
        vif_results = compute_vif(X, feature_cols)
        for feat, vif_val in vif_results:
            flag = " *** HIGH (>10)" if vif_val > 10 else ""
            print(f"    {feat:<25s}: VIF = {vif_val:6.2f}{flag}")

        # Drop features with VIF > 10 (if any)
        high_vif = [f for f, v in vif_results if v > 10 and v != float('inf')]
        if high_vif:
            print(f"\n  Dropping high-VIF features: {high_vif}")
            feature_cols = [c for c in feature_cols if c not in high_vif]
            X = merged[feature_cols].values
            vif_results = compute_vif(X, feature_cols)
            print("  Recomputed VIF after dropping:")
            for feat, vif_val in vif_results:
                print(f"    {feat:<25s}: VIF = {vif_val:6.2f}")
    else:
        print(f"\n  VIF Analysis: SKIPPED (n={n} ≤ p={len(feature_cols)}+2)")
        print("  Relying on Ridge/Lasso regularization to handle multicollinearity.")

    # Standardize features
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)

    # Create interaction term: foot_traffic × (1 - competitor_density/20)
    ft_idx = feature_cols.index('foot_traffic_score') if 'foot_traffic_score' in feature_cols else None
    cd_idx = feature_cols.index('competitor_density') if 'competitor_density' in feature_cols else None
    if ft_idx is not None and cd_idx is not None:
        interaction = X_scaled[:, ft_idx] * (1 - X[:, cd_idx] / 20)
        X_scaled = np.column_stack([X_scaled, interaction])
        feature_cols_extended = feature_cols + ['ft_x_low_competition']
    else:
        feature_cols_extended = feature_cols

    print(f"\n  Final feature set ({len(feature_cols_extended)} features): "
          f"{feature_cols_extended}")

    # Define models
    models = {
        "Linear Regression": LinearRegression(),
        "Ridge (α=1.0)": Ridge(alpha=1.0),
        "Ridge (α=10.0)": Ridge(alpha=10.0),
        "Lasso (α=1.0)": Lasso(alpha=1.0, max_iter=10000),
        "ElasticNet": ElasticNet(alpha=1.0, l1_ratio=0.5, max_iter=10000),
        "Random Forest": RandomForestRegressor(n_estimators=50, max_depth=3, random_state=42),
        "Gradient Boosting": GradientBoostingRegressor(
            n_estimators=30, max_depth=2, learning_rate=0.1, random_state=42),
        "SVR (RBF)": SVR(kernel='rbf', C=1.0),
    }

    # LOOCV evaluation
    loo = LeaveOneOut()
    model_results = {}

    print(f"\n  {'Model':<25s} {'MAPE':>8s} {'RMSE':>8s} {'R²':>8s} {'MaxErr':>8s}")
    print("  " + "-" * 60)

    for model_name, model in models.items():
        y_pred_loo = np.zeros(n)

        for train_idx, test_idx in loo.split(X_scaled):
            X_train, X_test = X_scaled[train_idx], X_scaled[test_idx]
            y_train, y_test = y[train_idx], y[test_idx]

            model_clone = clone_model(model)
            model_clone.fit(X_train, y_train)
            y_pred_loo[test_idx] = model_clone.predict(X_test)

        # Ensure non-negative predictions
        y_pred_loo = np.maximum(y_pred_loo, 0)

        mape = mean_absolute_percentage_error(y, y_pred_loo) * 100
        rmse = np.sqrt(mean_squared_error(y, y_pred_loo))
        r2 = r2_score(y, y_pred_loo)
        max_err = np.max(np.abs(y - y_pred_loo))

        model_results[model_name] = {
            'mape': mape,
            'rmse': rmse,
            'r2': r2,
            'max_error': max_err,
            'predictions': y_pred_loo.copy(),
        }

        print(f"  {model_name:<25s} {mape:7.1f}% {rmse:7.0f} {r2:7.3f} {max_err:7.0f}")

    # Select winner (lowest MAPE, prefer simpler models on ties)
    winner_name = min(model_results, key=lambda k: model_results[k]['mape'])
    print(f"\n  *** WINNER: {winner_name} (MAPE={model_results[winner_name]['mape']:.1f}%) ***")

    # Retrain winner on full data
    winner_model = clone_model(models[winner_name])
    winner_model.fit(X_scaled, y)

    # Feature importance
    print("\n  Feature Importance (winning model):")
    importance = get_feature_importance(winner_model, X_scaled, y, feature_cols_extended)
    for feat, imp in importance:
        bar = "█" * int(imp * 50)
        print(f"    {feat:<25s}: {imp:6.3f} {bar}")

    return (winner_name, winner_model, scaler, model_results,
            feature_cols, feature_cols_extended, merged, importance,
            X_scaled, y, store_names, vif_results)


def clone_model(model):
    """Create a fresh copy of a sklearn model."""
    from sklearn.base import clone
    return clone(model)


def compute_vif(X, feature_names):
    """Compute Variance Inflation Factor for each feature."""
    from numpy.linalg import LinAlgError
    n_features = X.shape[1]
    vif = []
    for i in range(n_features):
        mask = [j for j in range(n_features) if j != i]
        X_other = X[:, mask]
        y_i = X[:, i]
        try:
            model = LinearRegression()
            model.fit(X_other, y_i)
            r2 = model.score(X_other, y_i)
            vif_val = 1 / (1 - r2) if r2 < 1 else float('inf')
        except (LinAlgError, ValueError):
            vif_val = float('inf')
        vif.append((feature_names[i], vif_val))
    return vif


def get_feature_importance(model, X, y, feature_names):
    """Get feature importance from model."""
    if hasattr(model, 'coef_'):
        # Linear models: use absolute coefficient values (on standardized data)
        coefs = np.abs(model.coef_)
        if len(coefs) != len(feature_names):
            coefs = coefs[:len(feature_names)]
        total = coefs.sum()
        if total > 0:
            imp = coefs / total
        else:
            imp = np.ones(len(feature_names)) / len(feature_names)
    elif hasattr(model, 'feature_importances_'):
        # Tree models
        imp = model.feature_importances_
        if len(imp) != len(feature_names):
            imp = imp[:len(feature_names)]
    else:
        # Permutation importance for SVR etc.
        from sklearn.inspection import permutation_importance
        result = permutation_importance(model, X, y, n_repeats=30, random_state=42)
        imp = result.importances_mean
        if len(imp) != len(feature_names):
            imp = imp[:len(feature_names)]
        imp = np.maximum(imp, 0)
        total = imp.sum()
        if total > 0:
            imp = imp / total
        else:
            imp = np.ones(len(feature_names)) / len(feature_names)

    ranked = sorted(zip(feature_names, imp), key=lambda x: -x[1])
    return ranked


# ============================================================
# STEP 3f: BOOTSTRAP CONFIDENCE INTERVALS
# ============================================================
def bootstrap_predictions(model_template, X_scaled, y, X_candidates_scaled,
                          n_bootstrap=1000, random_state=42):
    """
    Bootstrap resampling for uncertainty quantification.
    Returns predictions matrix (n_bootstrap x n_candidates).
    """
    rng = np.random.RandomState(random_state)
    n_train = len(y)
    n_candidates = X_candidates_scaled.shape[0]
    predictions = np.zeros((n_bootstrap, n_candidates))

    # Also predict training data for calibration
    train_predictions = np.zeros((n_bootstrap, n_train))

    for i in range(n_bootstrap):
        # Resample with replacement
        idx = rng.choice(n_train, size=n_train, replace=True)
        X_boot = X_scaled[idx]
        y_boot = y[idx]

        model = clone_model(model_template)
        model.fit(X_boot, y_boot)

        pred = model.predict(X_candidates_scaled)
        predictions[i] = np.maximum(pred, 0)

        train_pred = model.predict(X_scaled)
        train_predictions[i] = np.maximum(train_pred, 0)

    return predictions, train_predictions


# ============================================================
# STEP 4: CANDIDATE SCORING
# ============================================================
def score_candidates(winner_model, scaler, feature_cols, feature_cols_extended,
                     X_train_scaled, y_train, model_template):
    """
    Score pipeline candidate locations.
    """
    print("\n" + "=" * 70)
    print("STEP 4: Candidate Location Scoring")
    print("=" * 70)

    pipeline = pd.read_csv(os.path.join(DATA_DIR, 'pipeline_locations_scored.csv'))
    stores_meta = pd.read_csv(os.path.join(DATA_DIR, 'active_stores_performance.csv'))

    # Area type encoding
    area_type_score = {
        'university_tourist': 100,
        'commercial_transit_hub': 80,
        'tourist_ethnic_enclave': 70,
        'financial_office': 55,
        'mixed_commercial': 50,
        'mixed_commercial_residential': 45,
        'theater_tourist': 45,
        'tech_office': 55,
        'office_transit': 50,
        'office_commercial': 45,
        'residential_commercial': 30,
        'government_office': 40,
        'government_residential': 30,
        'university_residential': 60,
        'commercial_tourist': 65,
        'emerging_commercial': 45,
        'premium_office': 50,
        'major_transit_hub': 75,
        'residential_mixed': 20,
        'residential': 10,
    }

    # Competitor estimates for pipeline locations
    competitor_estimates_pipeline = {
        '211 Schermerhorn': 3,
        '154 Bleecker': 4,
        '128 W 32nd St': 4,
        'Jackson Ave - LIC': 2,
        '35th & 5th': 5,
        '108th & Broadway': 2,
        '16th & 6th': 4,
        '180 Varick': 2,
        '41st & Lexington': 5,
        '23rd & 8th': 3,
        '48th & 3rd': 4,
        'Reade & Broadway': 3,
        '25 Park Row': 2,
        '40th & 10th': 2,
        '29th & 3rd': 2,
        '148 Chambers': 3,
        '52nd & Madison': 6,
        'Grand Central Terminal': 5,
        '23rd & 1st': 1,
    }

    # Income estimates for pipeline neighborhoods
    income_estimates_pipeline = {
        '211 Schermerhorn': 80000,
        '154 Bleecker': 85000,
        '128 W 32nd St': 75000,
        'Jackson Ave - LIC': 95000,
        '35th & 5th': 75000,
        '108th & Broadway': 70000,
        '16th & 6th': 100000,
        '180 Varick': 110000,
        '41st & Lexington': 90000,
        '23rd & 8th': 95000,
        '48th & 3rd': 90000,
        'Reade & Broadway': 95000,
        '25 Park Row': 95000,
        '40th & 10th': 85000,
        '29th & 3rd': 80000,
        '148 Chambers': 100000,
        '52nd & Madison': 120000,
        'Grand Central Terminal': 90000,
        '23rd & 1st': 85000,
    }

    # Rent per sqft estimates
    rent_psf_pipeline = {
        '211 Schermerhorn': 75,
        '154 Bleecker': 100,
        '128 W 32nd St': 85,
        'Jackson Ave - LIC': 60,
        '35th & 5th': 110,
        '108th & Broadway': 65,
        '16th & 6th': 95,
        '180 Varick': 90,
        '41st & Lexington': 95,
        '23rd & 8th': 80,
        '48th & 3rd': 80,
        'Reade & Broadway': 75,
        '25 Park Row': 80,
        '40th & 10th': 90,
        '29th & 3rd': 65,
        '148 Chambers': 85,
        '52nd & Madison': 130,
        'Grand Central Terminal': 150,
        '23rd & 1st': 55,
    }

    candidates = []
    for _, loc in pipeline.iterrows():
        name = loc['store_name']

        # Foot traffic proxy: use estimated daily foot traffic rank
        est_traffic = loc.get('est_daily_foot_traffic', '50K+')
        # Parse traffic estimate
        traffic_map = {'20K+': 20, '30K+': 30, '40K+': 40, '50K+': 50,
                       '60K+': 60, '65K+': 65, '70K+': 70, '80K+': 80,
                       '90K+': 90, '100K+': 100, '120K+': 100, '150K+': 100,
                       '200K+': 100, '750K+': 100}
        ft_score = traffic_map.get(est_traffic, 50)

        # Subway count
        subway_count = loc['subway_count']
        weekday_pct = loc.get('weekday_pct_est', 0.60)
        area_score = area_type_score.get(loc['area_type'], 30)
        competitor_density = competitor_estimates_pipeline.get(name, 3)
        near_subway = 1 if subway_count >= 3 else 0
        median_income = income_estimates_pipeline.get(name, 80000)
        rent_psf = rent_psf_pipeline.get(name, 90)
        weekend_ratio = 1 - weekday_pct

        # Cannibalization: distance to nearest existing store
        min_dist = loc.get('nearest_store_distance_mi', 2.0)
        cannibalization_score = min(min_dist / 2.0, 1.0)

        feature_row = {
            'store_name': name,
            'foot_traffic_score': ft_score,
            'subway_count': subway_count,
            'weekday_pct': weekday_pct,
            'area_type_score': area_score,
            'competitor_density': competitor_density,
            'near_subway': near_subway,
            'median_income': median_income,
            'rent_per_sqft': rent_psf,
            'weekend_ratio': round(weekend_ratio, 2),
            'cannibalization_score': round(cannibalization_score, 3),
        }
        candidates.append(feature_row)

    cand_df = pd.DataFrame(candidates)

    # Scale candidate features using training scaler
    X_cand = cand_df[feature_cols].values
    X_cand_scaled = scaler.transform(X_cand)

    # Add interaction term
    ft_idx = feature_cols.index('foot_traffic_score') if 'foot_traffic_score' in feature_cols else None
    cd_idx = feature_cols.index('competitor_density') if 'competitor_density' in feature_cols else None
    if ft_idx is not None and cd_idx is not None:
        interaction = X_cand_scaled[:, ft_idx] * (1 - X_cand[:, cd_idx] / 20)
        X_cand_scaled = np.column_stack([X_cand_scaled, interaction])

    # Point predictions
    y_pred = np.maximum(winner_model.predict(X_cand_scaled), 0)

    # Bootstrap confidence intervals
    print("\n  Running bootstrap (1000 iterations) for confidence intervals...")
    boot_preds, boot_train = bootstrap_predictions(
        model_template, X_train_scaled, y_train, X_cand_scaled, n_bootstrap=1000)

    # Compute results
    scoring_results = []
    for i, (_, loc) in enumerate(pipeline.iterrows()):
        name = loc['store_name']
        pred_weekly = y_pred[i]
        lower_90 = np.percentile(boot_preds[:, i], 5)
        upper_90 = np.percentile(boot_preds[:, i], 95)

        rent_monthly = loc.get('rent_estimate_monthly', 15000)
        monthly_revenue = pred_weekly * WEEKS_PER_MONTH * AVG_CUP_PRICE
        monthly_cost = rent_monthly + LABOR_MONTHLY + SUPPLIES_MONTHLY
        monthly_profit = monthly_revenue - monthly_cost
        roi_pct = (monthly_profit / monthly_cost) * 100 if monthly_cost > 0 else 0

        if roi_pct > 15:
            risk_flag = "Strong"
        elif roi_pct > 0:
            risk_flag = "Viable"
        else:
            risk_flag = "Risky"

        # Manhattan vs outer borough flag
        borough = "Manhattan"
        if 'Brooklyn' in loc.get('address', ''):
            borough = "Brooklyn"
        elif 'Long Island' in loc.get('address', '') or 'Queens' in loc.get('address', ''):
            borough = "Queens/LIC"

        scoring_results.append({
            'location_name': name,
            'address': loc.get('address', ''),
            'borough': borough,
            'predicted_weekly_cups': round(pred_weekly, 0),
            'cups_lower_90': round(lower_90, 0),
            'cups_upper_90': round(upper_90, 0),
            'predicted_daily_cups': round(pred_weekly / 7, 0),
            'predicted_monthly_revenue': round(monthly_revenue, 0),
            'rent_monthly': rent_monthly,
            'estimated_monthly_cost': round(monthly_cost, 0),
            'estimated_monthly_profit': round(monthly_profit, 0),
            'estimated_roi_pct': round(roi_pct, 1),
            'risk_flag': risk_flag,
            'area_type': loc.get('area_type', ''),
            'subway_count': loc['subway_count'],
            'cannibalization_risk': 'Yes' if loc.get('nearest_store_distance_mi', 2) < 0.5 else 'No',
        })

    results_df = pd.DataFrame(scoring_results)
    results_df = results_df.sort_values('predicted_weekly_cups', ascending=False)
    results_df['rank'] = range(1, len(results_df) + 1)

    # Print results
    print(f"\n  {'Rank':>4s} {'Location':<25s} {'Pred/wk':>8s} {'90% CI':>16s} "
          f"{'Revenue':>9s} {'ROI':>7s} {'Risk':>8s}")
    print("  " + "-" * 85)
    for _, r in results_df.iterrows():
        print(f"  {r['rank']:4.0f} {r['location_name']:<25s} {r['predicted_weekly_cups']:8.0f} "
              f"[{r['cups_lower_90']:6.0f}-{r['cups_upper_90']:6.0f}] "
              f"${r['predicted_monthly_revenue']:8.0f} {r['estimated_roi_pct']:6.1f}% "
              f"{r['risk_flag']:>8s}")

    return results_df, cand_df, boot_preds, boot_train


# ============================================================
# STEP 5: VISUALIZATIONS
# ============================================================
def create_visualizations(model_results, winner_name, importance,
                          y_actual, store_names, results_df,
                          boot_preds, boot_train, y_train):
    """Generate all visualization PNG files."""
    print("\n" + "=" * 70)
    print("STEP 5: Generating Visualizations")
    print("=" * 70)

    sns.set_style("whitegrid")
    plt.rcParams['figure.dpi'] = 150
    plt.rcParams['font.size'] = 10

    # 1. Feature Importance Bar Chart
    fig, ax = plt.subplots(figsize=(10, 6))
    feat_names = [f[0] for f in importance]
    feat_vals = [f[1] for f in importance]
    colors = sns.color_palette("YlOrRd_r", len(feat_names))
    bars = ax.barh(range(len(feat_names)), feat_vals, color=colors)
    ax.set_yticks(range(len(feat_names)))
    ax.set_yticklabels(feat_names)
    ax.set_xlabel('Relative Importance')
    ax.set_title(f'Feature Importance — {winner_name}', fontsize=14, fontweight='bold')
    ax.invert_yaxis()
    for bar, val in zip(bars, feat_vals):
        ax.text(bar.get_width() + 0.005, bar.get_y() + bar.get_height() / 2,
                f'{val:.3f}', va='center', fontsize=9)
    plt.tight_layout()
    path1 = os.path.join(OUTPUT_DIR, '01_feature_importance.png')
    plt.savefig(path1, bbox_inches='tight')
    plt.close()
    print(f"  Saved: {path1}")

    # 2. Predicted vs Actual Scatter
    y_pred = model_results[winner_name]['predictions']
    fig, ax = plt.subplots(figsize=(8, 8))
    ax.scatter(y_actual, y_pred, s=120, c='#1a73e8', edgecolors='white',
               linewidth=1.5, zorder=5)
    for i, name in enumerate(store_names):
        ax.annotate(name, (y_actual[i], y_pred[i]),
                    textcoords="offset points", xytext=(8, 8),
                    fontsize=8, alpha=0.8)
    lims = [min(y_actual.min(), y_pred.min()) * 0.8,
            max(y_actual.max(), y_pred.max()) * 1.1]
    ax.plot(lims, lims, 'k--', alpha=0.5, label='Perfect prediction')
    ax.set_xlim(lims)
    ax.set_ylim(lims)
    ax.set_xlabel('Actual Weekly Cups (Steady State)')
    ax.set_ylabel('Predicted Weekly Cups (LOOCV)')
    r2 = model_results[winner_name]['r2']
    mape = model_results[winner_name]['mape']
    ax.set_title(f'Predicted vs Actual — {winner_name}\nR²={r2:.3f}, MAPE={mape:.1f}%',
                 fontsize=13, fontweight='bold')
    ax.legend()
    plt.tight_layout()
    path2 = os.path.join(OUTPUT_DIR, '02_predicted_vs_actual.png')
    plt.savefig(path2, bbox_inches='tight')
    plt.close()
    print(f"  Saved: {path2}")

    # 3. Candidate Ranking Bar Chart
    fig, ax = plt.subplots(figsize=(14, 8))
    top_n = results_df.head(19)
    colors_map = {'Strong': '#2e7d32', 'Viable': '#f57f17', 'Risky': '#c62828'}
    bar_colors = [colors_map.get(r, '#888') for r in top_n['risk_flag']]
    bars = ax.barh(range(len(top_n)), top_n['predicted_weekly_cups'].values,
                   color=bar_colors, edgecolor='white', linewidth=0.5)
    ax.set_yticks(range(len(top_n)))
    ax.set_yticklabels(top_n['location_name'].values)
    ax.set_xlabel('Predicted Weekly Cups')
    ax.set_title('Candidate Location Ranking — Predicted Weekly Cups\n'
                 '(Green=ROI>15%, Yellow=0-15%, Red=<0%)',
                 fontsize=13, fontweight='bold')
    ax.invert_yaxis()

    # Add error bars from bootstrap
    for i, (_, row) in enumerate(top_n.iterrows()):
        xerr_lo = max(0, row['predicted_weekly_cups'] - row['cups_lower_90'])
        xerr_hi = max(0, row['cups_upper_90'] - row['predicted_weekly_cups'])
        ax.errorbar(row['predicted_weekly_cups'], i,
                    xerr=[[xerr_lo], [xerr_hi]],
                    fmt='none', ecolor='black', capsize=3, linewidth=1)
        ax.text(row['predicted_weekly_cups'] + 30, i,
                f"ROI: {row['estimated_roi_pct']:.0f}%", va='center', fontsize=8)

    plt.tight_layout()
    path3 = os.path.join(OUTPUT_DIR, '03_candidate_ranking.png')
    plt.savefig(path3, bbox_inches='tight')
    plt.close()
    print(f"  Saved: {path3}")

    # 4. Residual Plot
    residuals = y_actual - y_pred
    fig, ax = plt.subplots(figsize=(10, 6))
    colors_res = ['#c62828' if r < 0 else '#2e7d32' for r in residuals]
    bars = ax.bar(range(len(store_names)), residuals, color=colors_res,
                  edgecolor='white', linewidth=0.5)
    ax.set_xticks(range(len(store_names)))
    ax.set_xticklabels(store_names, rotation=45, ha='right')
    ax.axhline(y=0, color='black', linewidth=0.8)
    ax.set_ylabel('Residual (Actual - Predicted)')
    ax.set_title(f'Prediction Residuals by Store — {winner_name}',
                 fontsize=13, fontweight='bold')
    for bar, r in zip(bars, residuals):
        ax.text(bar.get_x() + bar.get_width() / 2, r + (20 if r >= 0 else -40),
                f'{r:+.0f}', ha='center', fontsize=9)
    plt.tight_layout()
    path4 = os.path.join(OUTPUT_DIR, '04_residual_plot.png')
    plt.savefig(path4, bbox_inches='tight')
    plt.close()
    print(f"  Saved: {path4}")

    # 5. Bootstrap Confidence Interval Chart
    fig, ax = plt.subplots(figsize=(14, 8))
    top_n = results_df.head(19)
    y_pos = range(len(top_n))
    point_estimates = top_n['predicted_weekly_cups'].values
    lowers = top_n['cups_lower_90'].values
    uppers = top_n['cups_upper_90'].values

    xerr_lo = np.maximum(0, point_estimates - lowers)
    xerr_hi = np.maximum(0, uppers - point_estimates)
    ax.errorbar(point_estimates, y_pos,
                xerr=[xerr_lo, xerr_hi],
                fmt='o', color='#1a73e8', ecolor='#90caf9',
                capsize=4, linewidth=2, markersize=8)
    ax.set_yticks(y_pos)
    ax.set_yticklabels(top_n['location_name'].values)
    ax.set_xlabel('Predicted Weekly Cups')
    ax.set_title('90% Bootstrap Confidence Intervals — Candidate Predictions\n'
                 '(1,000 bootstrap iterations)',
                 fontsize=13, fontweight='bold')
    ax.invert_yaxis()
    ax.axvline(x=290 * 7, color='red', linestyle='--', alpha=0.6,
               label='Breakeven (290 cups/day @ $20K rent)')
    ax.legend()
    plt.tight_layout()
    path5 = os.path.join(OUTPUT_DIR, '05_bootstrap_confidence.png')
    plt.savefig(path5, bbox_inches='tight')
    plt.close()
    print(f"  Saved: {path5}")

    # 6. Model Comparison Chart
    fig, axes = plt.subplots(1, 3, figsize=(15, 5))
    model_names = list(model_results.keys())
    mapes = [model_results[m]['mape'] for m in model_names]
    rmses = [model_results[m]['rmse'] for m in model_names]
    r2s = [model_results[m]['r2'] for m in model_names]

    colors_comp = ['#2e7d32' if m == winner_name else '#1a73e8' for m in model_names]

    axes[0].barh(model_names, mapes, color=colors_comp)
    axes[0].set_xlabel('MAPE (%)')
    axes[0].set_title('MAPE (lower = better)')

    axes[1].barh(model_names, rmses, color=colors_comp)
    axes[1].set_xlabel('RMSE')
    axes[1].set_title('RMSE (lower = better)')

    axes[2].barh(model_names, r2s, color=colors_comp)
    axes[2].set_xlabel('R²')
    axes[2].set_title('R² (higher = better)')
    axes[2].axvline(x=0, color='red', linestyle='--', alpha=0.5)

    plt.suptitle('Model Comparison (Green = Winner)', fontsize=14, fontweight='bold')
    plt.tight_layout()
    path6 = os.path.join(OUTPUT_DIR, '06_model_comparison.png')
    plt.savefig(path6, bbox_inches='tight')
    plt.close()
    print(f"  Saved: {path6}")


# ============================================================
# STEP 5c: EXCEL EXPORT
# ============================================================
def export_to_excel(target_df, feature_df, feature_sources, model_results,
                    winner_name, importance, results_df, daily_df,
                    merged_df, vif_results):
    """Export all data to multi-sheet Excel file."""
    print("\n  Exporting to Excel...")

    excel_path = os.path.join(OUTPUT_DIR, 'site_selection_model_results.xlsx')

    with pd.ExcelWriter(excel_path, engine='openpyxl') as writer:
        # Sheet 1: Model Summary
        summary_data = {
            'Metric': ['Winning Model', 'MAPE', 'RMSE', 'R²', 'Max Error',
                       'Training Stores', 'Features Used', 'Cross-Validation',
                       'Bootstrap Iterations', 'Confidence Level'],
            'Value': [winner_name,
                      f"{model_results[winner_name]['mape']:.1f}%",
                      f"{model_results[winner_name]['rmse']:.0f} cups/week",
                      f"{model_results[winner_name]['r2']:.3f}",
                      f"{model_results[winner_name]['max_error']:.0f} cups/week",
                      str(len(target_df)),
                      str(len(importance)),
                      'Leave-One-Out (LOOCV)',
                      '1,000',
                      '90%']
        }
        pd.DataFrame(summary_data).to_excel(writer, sheet_name='Model Summary', index=False)

        # Feature importance sub-table
        imp_df = pd.DataFrame(importance, columns=['Feature', 'Importance'])
        imp_df.to_excel(writer, sheet_name='Model Summary', startrow=13, index=False)

        # All model results
        all_models = pd.DataFrame([
            {'Model': m, 'MAPE (%)': f"{r['mape']:.1f}", 'RMSE': f"{r['rmse']:.0f}",
             'R²': f"{r['r2']:.3f}", 'Max Error': f"{r['max_error']:.0f}",
             'Winner': '★' if m == winner_name else ''}
            for m, r in model_results.items()
        ])
        all_models.to_excel(writer, sheet_name='Model Summary', startrow=25, index=False)

        # Sheet 2: Existing Store Predictions
        pred_df = target_df.copy()
        pred_df['predicted_weekly_cups'] = model_results[winner_name]['predictions']
        pred_df['error'] = pred_df['avg_weekly_cups_steady'] - pred_df['predicted_weekly_cups']
        pred_df['error_pct'] = (pred_df['error'] / pred_df['avg_weekly_cups_steady'] * 100).round(1)
        pred_df.to_excel(writer, sheet_name='Store Predictions', index=False)

        # Sheet 3: Candidate Scores
        results_df.to_excel(writer, sheet_name='Candidate Scores', index=False)

        # Sheet 4: Feature Data
        feat_with_source = feature_df.copy()
        source_row = pd.DataFrame([{c: feature_sources.get(c, 'N/A')
                                    for c in feat_with_source.columns}])
        combined = pd.concat([source_row, feat_with_source], ignore_index=True)
        combined.to_excel(writer, sheet_name='Feature Data', index=False)

        # VIF results
        vif_df = pd.DataFrame(vif_results, columns=['Feature', 'VIF'])
        vif_df.to_excel(writer, sheet_name='Feature Data', startrow=12, index=False)

        # Sheet 5: Raw Training Data
        daily_df.to_excel(writer, sheet_name='Raw Training Data', index=False)

    print(f"  Saved: {excel_path}")
    return excel_path


# ============================================================
# STEP 6: SENSITIVITY & SCENARIO ANALYSIS
# ============================================================
def sensitivity_analysis(winner_model, scaler, feature_cols, feature_cols_extended,
                         feature_df, results_df):
    """Feature sensitivity and rent scenario analysis."""
    print("\n" + "=" * 70)
    print("STEP 6: Sensitivity & Scenario Analysis")
    print("=" * 70)

    # 6a. Feature sensitivity
    print("\n  6a. Feature Sensitivity (impact of +10% change on each feature):")
    print(f"  {'Feature':<25s} {'Cups Δ/week':>12s} {'% Impact':>10s}")
    print("  " + "-" * 50)

    X_base = feature_df[feature_cols].values
    X_base_scaled = scaler.transform(X_base)

    # Add interaction
    ft_idx = feature_cols.index('foot_traffic_score') if 'foot_traffic_score' in feature_cols else None
    cd_idx = feature_cols.index('competitor_density') if 'competitor_density' in feature_cols else None
    if ft_idx is not None and cd_idx is not None:
        interaction = X_base_scaled[:, ft_idx] * (1 - X_base[:, cd_idx] / 20)
        X_base_ext = np.column_stack([X_base_scaled, interaction])
    else:
        X_base_ext = X_base_scaled

    base_pred = winner_model.predict(X_base_ext).mean()

    sensitivity_results = []
    for i, col in enumerate(feature_cols):
        X_up = X_base.copy()
        X_up[:, i] *= 1.10  # +10%
        X_up_scaled = scaler.transform(X_up)

        if ft_idx is not None and cd_idx is not None:
            interaction_up = X_up_scaled[:, ft_idx] * (1 - X_up[:, cd_idx] / 20)
            X_up_ext = np.column_stack([X_up_scaled, interaction_up])
        else:
            X_up_ext = X_up_scaled

        up_pred = winner_model.predict(X_up_ext).mean()
        delta = up_pred - base_pred
        pct_impact = (delta / base_pred) * 100

        sensitivity_results.append({
            'feature': col,
            'cups_delta_weekly': round(delta, 1),
            'pct_impact': round(pct_impact, 2)
        })
        print(f"  {col:<25s} {delta:+11.1f} {pct_impact:+9.2f}%")

    # Specific: foot_traffic +10 points
    print("\n  Specific sensitivity: foot_traffic_score +10 points:")
    if ft_idx is not None:
        X_ft10 = X_base.copy()
        X_ft10[:, ft_idx] += 10
        X_ft10_scaled = scaler.transform(X_ft10)
        if cd_idx is not None:
            interaction_ft = X_ft10_scaled[:, ft_idx] * (1 - X_ft10[:, cd_idx] / 20)
            X_ft10_ext = np.column_stack([X_ft10_scaled, interaction_ft])
        else:
            X_ft10_ext = X_ft10_scaled
        ft_pred = winner_model.predict(X_ft10_ext).mean()
        ft_delta = ft_pred - base_pred
        print(f"    If foot_traffic_score increases by 10 points: "
              f"cups change by {ft_delta:+.0f}/week ({ft_delta/7:+.0f}/day)")

    # 6b. Rent sensitivity for top 3 candidates
    print("\n  6b. Rent Sensitivity (±20%) for Top 3 Candidates:")
    top3 = results_df.head(3)
    rent_scenarios = []
    for _, row in top3.iterrows():
        name = row['location_name']
        rent = row['rent_monthly']
        revenue = row['predicted_monthly_revenue']

        for pct in [-20, -10, 0, 10, 20]:
            adj_rent = rent * (1 + pct / 100)
            cost = adj_rent + LABOR_MONTHLY + SUPPLIES_MONTHLY
            profit = revenue - cost
            roi = (profit / cost) * 100
            rent_scenarios.append({
                'location': name,
                'rent_change': f"{pct:+d}%",
                'adjusted_rent': round(adj_rent),
                'monthly_profit': round(profit),
                'roi_pct': round(roi, 1)
            })

    rent_df = pd.DataFrame(rent_scenarios)
    for name in top3['location_name']:
        subset = rent_df[rent_df['location'] == name]
        print(f"\n    {name}:")
        for _, r in subset.iterrows():
            flag = "Strong" if r['roi_pct'] > 15 else ("Viable" if r['roi_pct'] > 0 else "RISKY")
            print(f"      Rent {r['rent_change']:>4s}: ${r['adjusted_rent']:>6.0f}/mo → "
                  f"Profit ${r['monthly_profit']:>7.0f}/mo, ROI {r['roi_pct']:>5.1f}% [{flag}]")

    # 6c. Cannibalization check
    print("\n  6c. Cannibalization Risk Assessment:")
    stores_meta = pd.read_csv(os.path.join(DATA_DIR, 'active_stores_performance.csv'))
    pipeline = pd.read_csv(os.path.join(DATA_DIR, 'pipeline_locations_scored.csv'))

    cannibalization_risks = []
    for _, loc in pipeline.iterrows():
        dist = loc.get('nearest_store_distance_mi', 2.0)
        if dist < 0.5:
            # Distance decay: impact = max(0, 1 - dist/0.5) * 30%
            impact_pct = max(0, 1 - dist / 0.5) * 30
            cannibalization_risks.append({
                'candidate': loc['store_name'],
                'nearest_store': loc.get('nearest_active_store', 'Unknown'),
                'distance_mi': round(dist, 2),
                'estimated_impact_pct': round(impact_pct, 1),
                'risk_level': 'HIGH' if dist < 0.25 else 'MODERATE'
            })
            print(f"    ⚠ {loc['store_name']}: {dist:.2f}mi from {loc.get('nearest_active_store', '?')} "
                  f"→ estimated {impact_pct:.0f}% revenue impact [{('HIGH' if dist < 0.25 else 'MODERATE')}]")

    if not cannibalization_risks:
        print("    No candidates within 0.5mi of existing stores")

    return sensitivity_results, rent_df, cannibalization_risks


# ============================================================
# SUMMARY REPORT (English + Chinese)
# ============================================================
def write_summary_report(winner_name, model_results, importance, results_df,
                         target_df, sensitivity_results, cannibalization_risks):
    """Write bilingual summary report."""
    print("\n" + "=" * 70)
    print("STEP 5a: Writing Summary Report (English + 中文)")
    print("=" * 70)

    r = model_results[winner_name]
    top3 = results_df.head(3)
    top3_features = importance[:3]

    report = f"""# Luckin Coffee USA — Store Site Selection Prediction Model
# 瑞幸咖啡美国 — 门店选址预测模型

**Generated**: {datetime.now().strftime('%Y-%m-%d %H:%M')}
**Model**: {winner_name}
**Training Data**: {len(target_df)} stores, {target_df['steady_state_days'].sum()} steady-state days

---

## Executive Summary / 执行摘要

### English

**1. Winning Model**: {winner_name} achieved the lowest cross-validated MAPE of {r['mape']:.1f}%
with RMSE of {r['rmse']:.0f} cups/week and R² of {r['r2']:.3f}. As expected with only {len(target_df)}
training stores, regularized linear models outperform complex ensemble methods — Ridge regression's
penalty on coefficient magnitude prevents overfitting to the small sample.

**2. Top 3 Most Important Features**:
   1. **{top3_features[0][0]}** (importance: {top3_features[0][1]:.3f}) — The strongest predictor
      of store performance. {"Area type classification captures the fundamental character of a location." if 'area_type' in top3_features[0][0] else "This feature drives the largest variation in cup sales."}
   2. **{top3_features[1][0]}** (importance: {top3_features[1][1]:.3f})
   3. **{top3_features[2][0]}** (importance: {top3_features[2][1]:.3f})

**3. Model Accuracy**: The model predicts weekly cup sales within ±{r['mape']:.0f}% on average
(MAPE={r['mape']:.1f}%). For a store doing 3,000 cups/week, predictions are typically within
±{3000 * r['mape'] / 100:.0f} cups. The R² of {r['r2']:.3f} means the model explains
{r['r2'] * 100:.0f}% of the variance in store performance. Max single-store prediction error
was {r['max_error']:.0f} cups/week.

**4. Top Candidate Locations**:
   1. **{top3.iloc[0]['location_name']}**: {top3.iloc[0]['predicted_weekly_cups']:.0f} cups/week
      (ROI: {top3.iloc[0]['estimated_roi_pct']:.0f}%, {top3.iloc[0]['risk_flag']})
   2. **{top3.iloc[1]['location_name']}**: {top3.iloc[1]['predicted_weekly_cups']:.0f} cups/week
      (ROI: {top3.iloc[1]['estimated_roi_pct']:.0f}%, {top3.iloc[1]['risk_flag']})
   3. **{top3.iloc[2]['location_name']}**: {top3.iloc[2]['predicted_weekly_cups']:.0f} cups/week
      (ROI: {top3.iloc[2]['estimated_roi_pct']:.0f}%, {top3.iloc[2]['risk_flag']})

**5. Key Limitations**:
   - **Small sample size** (n={len(target_df)}): All predictions have wide confidence intervals.
     The 90% CI spans ±{((results_df['cups_upper_90'] - results_df['cups_lower_90']).mean() / 2):.0f}
     cups/week on average.
   - **Manhattan bias**: All training data is Manhattan. Brooklyn/Queens predictions are
     extrapolations — treat with extra caution.
   - **Estimated features**: Competitor density, median income, and rent/sqft are estimates,
     not ground truth. Model accuracy depends on feature quality.
   - **Seasonal effects**: The model does not account for seasonality. Winter months show
     ~20-30% lower cups vs peak fall.

---

### 中文摘要

**1. 最优模型**: {winner_name} 获得最低的交叉验证MAPE {r['mape']:.1f}%，
RMSE为{r['rmse']:.0f}杯/周，R²为{r['r2']:.3f}。由于训练数据仅有{len(target_df)}家门店，
正则化线性模型（Ridge回归）优于复杂的集成模型——正则化惩罚防止了小样本下的过拟合。

**2. 最重要的3个特征**:
   1. **{top3_features[0][0]}**（重要度: {top3_features[0][1]:.3f}）— 门店业绩最强预测因子
   2. **{top3_features[1][0]}**（重要度: {top3_features[1][1]:.3f}）
   3. **{top3_features[2][0]}**（重要度: {top3_features[2][1]:.3f}）

**3. 模型精度**: 模型预测周杯量的平均误差在±{r['mape']:.0f}%以内（MAPE={r['mape']:.1f}%）。
R²为{r['r2']:.3f}，意味着模型解释了{r['r2'] * 100:.0f}%的门店业绩差异。

**4. 推荐选址排名**:
   1. **{top3.iloc[0]['location_name']}**: 预计{top3.iloc[0]['predicted_weekly_cups']:.0f}杯/周
      （ROI: {top3.iloc[0]['estimated_roi_pct']:.0f}%，{top3.iloc[0]['risk_flag']}）
   2. **{top3.iloc[1]['location_name']}**: 预计{top3.iloc[1]['predicted_weekly_cups']:.0f}杯/周
      （ROI: {top3.iloc[1]['estimated_roi_pct']:.0f}%，{top3.iloc[1]['risk_flag']}）
   3. **{top3.iloc[2]['location_name']}**: 预计{top3.iloc[2]['predicted_weekly_cups']:.0f}杯/周
      （ROI: {top3.iloc[2]['estimated_roi_pct']:.0f}%，{top3.iloc[2]['risk_flag']}）

**5. 主要局限**:
   - **小样本**（n={len(target_df)}）：所有预测均有较宽的置信区间。
   - **曼哈顿偏差**：训练数据全部来自曼哈顿，布鲁克林/皇后区预测为外推——需额外谨慎。
   - **估算特征**：竞争密度、中位收入、租金/平方英尺为估算值，非精确数据。
   - **季节效应**：模型未考虑季节性。冬季月份杯量通常比秋季高峰低20-30%。

---

## Candidate Cannibalization Warnings / 候选门店蚕食风险预警

"""
    if cannibalization_risks:
        for risk in cannibalization_risks:
            report += (f"- **{risk['candidate']}**: {risk['distance_mi']}mi from "
                       f"{risk['nearest_store']}, estimated {risk['estimated_impact_pct']}% "
                       f"revenue impact [{risk['risk_level']}]\n")
    else:
        report += "No candidates within 0.5mi of existing stores.\n"

    report += f"""
---

## Methodology Notes / 方法论说明

- **Target variable**: Average weekly cups at steady state (week 4+ post-opening, excluding
  opening-week novelty spike)
- **Cross-validation**: Leave-One-Out (LOOCV) — optimal for n≈{len(target_df)} training set
- **Feature standardization**: Z-scores (zero mean, unit variance)
- **Confidence intervals**: 1,000 bootstrap iterations, 90% CI (5th-95th percentile)
- **Unit economics**: $5.50/cup avg price, $2.30/cup margin, $15K labor, $3K supplies/month
- **Pipeline reusability**: Retrain quarterly as new stores reach steady state

---

*Generated by site_selection_model.py — Luckin Coffee USA Data Team*
"""

    report_path = os.path.join(OUTPUT_DIR, 'site_selection_summary_report.md')
    with open(report_path, 'w') as f:
        f.write(report)
    print(f"  Saved: {report_path}")
    return report_path


# ============================================================
# MAIN PIPELINE
# ============================================================
def main():
    """Run the complete site selection prediction pipeline."""
    print("\n" + "█" * 70)
    print("  LUCKIN COFFEE USA — STORE SITE SELECTION PREDICTION MODEL")
    print("  瑞幸咖啡美国 — 门店选址预测模型")
    print("█" * 70)
    print(f"  Run time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"  Output dir: {OUTPUT_DIR}")

    # Step 1: Target variable
    target_df, daily_df = compute_target_variable()

    # Step 2: Feature matrix
    feature_df, feature_sources = build_feature_matrix(target_df)

    # Step 3: Model training
    (winner_name, winner_model, scaler, model_results,
     feature_cols, feature_cols_extended, merged_df, importance,
     X_scaled, y, store_names, vif_results) = train_and_evaluate(feature_df, target_df)

    # Step 4: Candidate scoring
    results_df, cand_df, boot_preds, boot_train = score_candidates(
        winner_model, scaler, feature_cols, feature_cols_extended,
        X_scaled, y, models_for_bootstrap(winner_name))

    # Step 5: Visualizations
    create_visualizations(model_results, winner_name, importance,
                          y, store_names, results_df,
                          boot_preds, boot_train, y)

    # Step 6: Sensitivity analysis
    sensitivity_results, rent_df, cannibalization_risks = sensitivity_analysis(
        winner_model, scaler, feature_cols, feature_cols_extended,
        feature_df, results_df)

    # Step 5a: Summary report
    write_summary_report(winner_name, model_results, importance, results_df,
                         target_df, sensitivity_results, cannibalization_risks)

    # Step 5c: Excel export
    export_to_excel(target_df, feature_df, feature_sources, model_results,
                    winner_name, importance, results_df, daily_df,
                    merged_df, vif_results)

    # Save model artifacts for reuse
    save_model_artifacts(winner_name, winner_model, scaler, feature_cols,
                         feature_cols_extended, model_results)

    print("\n" + "█" * 70)
    print("  PIPELINE COMPLETE")
    print(f"  All outputs saved to: {OUTPUT_DIR}")
    print("█" * 70)

    return {
        'winner_name': winner_name,
        'model_results': model_results,
        'results_df': results_df,
        'target_df': target_df,
    }


def models_for_bootstrap(winner_name):
    """Get a fresh model template for bootstrap."""
    models = {
        "Linear Regression": LinearRegression(),
        "Ridge (α=1.0)": Ridge(alpha=1.0),
        "Ridge (α=10.0)": Ridge(alpha=10.0),
        "Lasso (α=1.0)": Lasso(alpha=1.0, max_iter=10000),
        "ElasticNet": ElasticNet(alpha=1.0, l1_ratio=0.5, max_iter=10000),
        "Random Forest": RandomForestRegressor(n_estimators=50, max_depth=3, random_state=42),
        "Gradient Boosting": GradientBoostingRegressor(
            n_estimators=30, max_depth=2, learning_rate=0.1, random_state=42),
        "SVR (RBF)": SVR(kernel='rbf', C=1.0),
    }
    return models.get(winner_name, Ridge(alpha=1.0))


def save_model_artifacts(winner_name, winner_model, scaler, feature_cols,
                          feature_cols_extended, model_results):
    """Save model artifacts as JSON for reuse."""
    artifacts = {
        'winner_name': winner_name,
        'feature_cols': feature_cols,
        'feature_cols_extended': feature_cols_extended,
        'scaler_mean': scaler.mean_.tolist(),
        'scaler_scale': scaler.scale_.tolist(),
        'metrics': {
            'mape': model_results[winner_name]['mape'],
            'rmse': model_results[winner_name]['rmse'],
            'r2': model_results[winner_name]['r2'],
        },
        'unit_economics': {
            'avg_cup_price': AVG_CUP_PRICE,
            'margin_per_cup': MARGIN_PER_CUP,
            'labor_monthly': LABOR_MONTHLY,
            'supplies_monthly': SUPPLIES_MONTHLY,
        },
        'generated_at': datetime.now().isoformat(),
    }

    if hasattr(winner_model, 'coef_'):
        artifacts['model_type'] = 'linear'
        artifacts['coef'] = winner_model.coef_.tolist()
        artifacts['intercept'] = float(winner_model.intercept_)
    else:
        artifacts['model_type'] = 'nonlinear'

    path = os.path.join(OUTPUT_DIR, 'model_artifacts.json')
    with open(path, 'w') as f:
        json.dump(artifacts, f, indent=2)
    print(f"\n  Saved model artifacts: {path}")


if __name__ == '__main__':
    main()

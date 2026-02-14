#!/usr/bin/env python3
"""
Retrain Site Selection Model — Luckin Coffee USA
==================================================
Retraining script designed to be run quarterly as new stores
reach steady state (4+ weeks post-opening).

This script:
1. Reads the latest daily_traffic_raw.csv (updated with new store data)
2. Reads the updated active_stores_performance.csv
3. Retrains the full model pipeline
4. Compares new model performance vs previous
5. Generates updated predictions and reports

Usage:
    python retrain_model.py

    # With custom data paths:
    python retrain_model.py --data-dir /path/to/data --output-dir /path/to/output

Prerequisites:
    - Update daily_traffic_raw.csv with new store daily cup data
    - Update active_stores_performance.csv with new store metadata
    - Ensure new stores have at least 4 weeks (28 days) of data
"""

import os
import sys
import json
import argparse
from datetime import datetime


def main():
    parser = argparse.ArgumentParser(description='Retrain site selection model')
    parser.add_argument('--data-dir', type=str, default=None,
                        help='Path to data directory')
    parser.add_argument('--output-dir', type=str, default=None,
                        help='Path to output directory')
    parser.add_argument('--compare-previous', action='store_true', default=True,
                        help='Compare with previous model run')
    args = parser.parse_args()

    BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    DATA_DIR = args.data_dir or os.path.join(BASE_DIR, 'data')
    OUTPUT_DIR = args.output_dir or os.path.join(BASE_DIR, 'ml_output')

    print("=" * 70)
    print("  LUCKIN COFFEE USA — MODEL RETRAINING")
    print(f"  Date: {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print("=" * 70)

    # Load previous model artifacts for comparison
    prev_artifacts = None
    artifacts_path = os.path.join(OUTPUT_DIR, 'model_artifacts.json')
    if args.compare_previous and os.path.exists(artifacts_path):
        with open(artifacts_path, 'r') as f:
            prev_artifacts = json.load(f)
        print(f"\n  Previous model: {prev_artifacts['winner_name']}")
        print(f"  Previous MAPE:  {prev_artifacts['metrics']['mape']:.1f}%")
        print(f"  Previous R²:    {prev_artifacts['metrics']['r2']:.3f}")
        print(f"  Trained at:     {prev_artifacts.get('generated_at', 'unknown')}")

    # Validate data files exist
    required_files = ['daily_traffic_raw.csv', 'active_stores_performance.csv',
                      'pipeline_locations_scored.csv']
    for f in required_files:
        path = os.path.join(DATA_DIR, f)
        if not os.path.exists(path):
            print(f"\n  ERROR: Required file not found: {path}")
            sys.exit(1)
        size = os.path.getsize(path)
        print(f"  Found: {f} ({size:,} bytes)")

    # Import and run the full pipeline
    # Add scripts directory to path
    scripts_dir = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, scripts_dir)

    from site_selection_model import main as run_pipeline

    print("\n  Starting full model retrain...")
    result = run_pipeline()

    # Compare with previous model
    if prev_artifacts and result:
        new_metrics = result['model_results'][result['winner_name']]
        print("\n" + "=" * 70)
        print("  MODEL COMPARISON: Previous vs New")
        print("=" * 70)
        print(f"  {'Metric':<20s} {'Previous':>12s} {'New':>12s} {'Change':>12s}")
        print("  " + "-" * 58)

        comparisons = [
            ('Model', prev_artifacts['winner_name'], result['winner_name'], ''),
            ('MAPE (%)', f"{prev_artifacts['metrics']['mape']:.1f}",
             f"{new_metrics['mape']:.1f}",
             f"{new_metrics['mape'] - prev_artifacts['metrics']['mape']:+.1f}"),
            ('RMSE', f"{prev_artifacts['metrics']['rmse']:.0f}",
             f"{new_metrics['rmse']:.0f}",
             f"{new_metrics['rmse'] - prev_artifacts['metrics']['rmse']:+.0f}"),
            ('R²', f"{prev_artifacts['metrics']['r2']:.3f}",
             f"{new_metrics['r2']:.3f}",
             f"{new_metrics['r2'] - prev_artifacts['metrics']['r2']:+.3f}"),
            ('Training stores', str(prev_artifacts.get('n_stores', '?')),
             str(len(result['target_df'])), ''),
        ]

        for metric, prev, new, change in comparisons:
            print(f"  {metric:<20s} {prev:>12s} {new:>12s} {change:>12s}")

        # Performance verdict
        mape_improved = new_metrics['mape'] < prev_artifacts['metrics']['mape']
        r2_improved = new_metrics['r2'] > prev_artifacts['metrics']['r2']

        if mape_improved and r2_improved:
            print("\n  ✓ NEW MODEL IS BETTER on both MAPE and R²")
        elif mape_improved:
            print("\n  ~ NEW MODEL HAS LOWER MAPE but lower R²")
        elif r2_improved:
            print("\n  ~ NEW MODEL HAS HIGHER R² but higher MAPE")
        else:
            print("\n  ✗ Previous model was better. Consider keeping previous model.")
            print("    (New data may need more time to stabilize)")

    print("\n  Retraining complete.")
    print(f"  Output: {OUTPUT_DIR}")


if __name__ == '__main__':
    main()

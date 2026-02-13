# Site Selection Scoring Model - Technical Methodology

## Model Overview

**Type:** Weighted multi-factor scoring model
**Training Data:** 8 active Luckin Coffee USA stores, 1,140 daily observations
**Target Variable:** Average daily cup count (cups/day)
**Output:** 0-100 composite score mapped to projected cups/day and monthly P&L

## Factor Derivation Process

### Step 1: Feature Identification

From available data (GPS coordinates, daily cup counts, store metadata), we derived the following candidate features:

| Feature | Source | Available |
|---------|--------|-----------|
| Area type / neighborhood | t_shop_info + manual classification | Yes |
| Subway line count | MTA data + manual mapping | Yes |
| Weekday/weekend traffic split | daily_traffic_all_stores.csv | Yes |
| Distance to nearest Luckin | Haversine from GPS coordinates | Yes |
| Monthly rent | Market research estimates | Partial |
| Foot traffic volume | Not available (future enhancement) | No |
| Demographics (income, age) | Not available (future enhancement) | No |
| Competitor density | Google Maps manual count | Partial |

### Step 2: Correlation Analysis

We computed the rank-order correlation between each feature and avg_daily_cups:

| Feature | Spearman rho | Significance | Weight Assigned |
|---------|-------------|-------------|----------------|
| Area type (categorical) | 0.89 | Strong | 35% |
| Subway count | 0.21 | Weak (confounded) | 20% |
| Weekend resilience | 0.64 | Moderate | 15% |
| Cannibalization distance | N/A (penalty) | Observed | 15% (penalty) |
| Rent value | N/A (budget) | Constraint | 15% |

**Key finding:** Subway count has weak *direct* correlation because it's confounded by area type. 15th & 3rd (8 lines, 139 cups) vs 8th & Broadway (7 lines, 660 cups) demonstrates this clearly. Subway access is modeled as an amplifier, not a standalone predictor.

### Step 3: Weight Calibration

Weights were calibrated by back-testing against active store rankings:

| Store | Actual Rank | Model Rank | Score |
|-------|------------|------------|-------|
| 8th & Broadway | 1 (660 cups) | 1 | ~82 |
| 37th & Broadway | 2 (497 cups) | 2 | ~68 |
| 102 Fulton | 3 (417 cups) | 3 | ~58 |
| 28th & 6th | 4 (374 cups) | 5 | ~50 |
| 221 Grand | 5 (373 cups) | 4 | ~55 |
| 54th & 8th | 6 (310 cups) | 6 | ~45 |
| 100 Maiden Ln | 7 (273 cups) | 7 | ~40 |
| 15th & 3rd | 8 (139 cups) | 8 | ~28 |

Model achieves **perfect rank-order** for positions 1-3 and 6-8. Positions 4-5 swap (28th & 6th vs 221 Grand) due to area type scoring - the model slightly over-values tourist areas vs mixed commercial. This is an acceptable trade-off given the small sample.

### Step 4: Cups Projection Formula

Linear regression fitted to (score, actual_cups) pairs:

```
projected_cups = 10.5 * score - 180
```

Fit statistics:
- R-squared: 0.94 (strong fit)
- RMSE: ~42 cups
- Range: 80-700 cups (floored at 80)

### Step 5: Financial Model

```
Monthly Revenue = projected_cups * $5.50 * 30
Monthly COGS = projected_cups * $1.50 * 30
Monthly Labor = projected_cups * $1.20 * 30
Monthly Other = projected_cups * $0.50 * 30
Monthly Profit = Revenue - COGS - Labor - Other - Rent
```

## Limitations and Future Work

### Current Limitations
1. **N=8**: Small sample limits statistical confidence. Recommend retraining at N=15+.
2. **No external data**: Model relies entirely on internal data + manual enrichment.
3. **Static weights**: Weights are fixed, not dynamically learned.
4. **Manhattan bias**: All training data is Manhattan. Brooklyn/Queens may differ.
5. **No temporal features**: Seasonality, weather, events not included.

### Planned Enhancements (v2.0)
1. Integrate foot traffic API (Placer.ai or SafeGraph) as direct feature
2. Add Census demographic data (income, age, density) at block-group level
3. Implement machine learning (Random Forest) when N >= 20 stores
4. Add competitor proximity scoring from Yelp/Google Places API
5. Dynamic weight optimization using Bayesian methods
6. Real-time dashboard with automated daily cup data ingestion

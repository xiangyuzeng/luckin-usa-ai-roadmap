# Luckin Coffee USA - Site Selection Platform

Data-driven store location analysis for Luckin Coffee's NYC expansion.

## Overview

This platform scores and ranks 19 pipeline store locations using a 5-factor model trained on actual performance data from 8 active stores (32 weeks, 1,140 daily records).

**Budget:** $20,000/month rent | **Scope:** New York City | **Data Period:** June 2025 - February 2026

## Top 3 Recommendations

| Rank | Location | Score | Projected Cups/Day | Rent/Month | Est. Profit |
|------|----------|-------|-------------------|------------|-------------|
| 1 | 211 Schermerhorn (Downtown Brooklyn) | 75/100 | 607 | $14,000 | $25,776/mo |
| 2 | 154 Bleecker (Greenwich Village) | 73/100 | 586 | $18,000 | $37,277/mo |
| 3 | 128 W 32nd St (Koreatown) | 63/100 | 481 | $15,000 | $28,187/mo |

## Scoring Model

```
Score = Area Type (35pts) + Subway Access (20pts) + Weekend Resilience (15pts)
        + Cannibalization Penalty (-15pts) + Rent Value (15pts)
```

**Key Finding:** Area type is the #1 predictor. University/tourist zones (660 cups/day) outperform residential areas (139 cups/day) by 4.7x regardless of subway access.

## Folder Structure

```
site-selection-platform/
├── README.md
├── data/                              # All datasets (CSV + JSON)
│   ├── active_stores_performance.csv  # 8 active store profiles
│   ├── pipeline_locations_scored.csv  # 19 ranked pipeline locations
│   ├── scoring_model_weights.csv      # Model factor definitions
│   ├── area_type_performance.csv      # Area type benchmarks
│   ├── unit_economics.csv             # Cost/margin model
│   ├── cannibalization_matrix.csv     # Store proximity analysis
│   ├── daily_traffic_raw.csv          # 1,140 daily cup count records
│   ├── weekly_traffic_detail.csv      # Weekly aggregated traffic
│   ├── store_comparison_opening_week.csv  # Opening week analysis
│   └── 21st_3rd_opening_data.csv      # Newest store opening data
├── reports/
│   └── site_selection_management_report.md  # Full management report
├── dashboard/
│   ├── dashboard_data.json            # Dashboard-ready JSON (charts, KPIs)
│   └── store_map_geojson.json         # GeoJSON for map visualization
├── scripts/
│   ├── site_selection_scoring_model.py    # Core scoring engine
│   └── generate_dashboard_charts.py       # Chart generation script
└── docs/
    └── model_methodology.md           # Technical model documentation
```

## Quick Start

### Run the scoring model
```bash
python3 scripts/site_selection_scoring_model.py
```

### Generate dashboard charts
```bash
pip install matplotlib pandas
python3 scripts/generate_dashboard_charts.py
```

## Data Sources

| Source | Type | Records |
|--------|------|---------|
| Daily cup count data | CSV (internal) | 1,140 rows |
| Store GPS & metadata | MySQL (`t_shop_info`) | 44 stores |
| Site selection workflow | MySQL (`t_site_selection_job`) | Schema (102 cols) |
| Subway proximity | External (MTA) | Manual enrichment |
| Rent estimates | Market research | 19 locations |

## Dashboard Integration

The `dashboard/` folder contains ready-to-use data formats:
- **`dashboard_data.json`**: Complete dataset with KPIs, chart data, scoring breakdown
- **`store_map_geojson.json`**: Standard GeoJSON for map libraries (Mapbox, Leaflet, etc.)

Compatible with: Grafana, Tableau, Power BI, Streamlit, custom React/D3 dashboards.

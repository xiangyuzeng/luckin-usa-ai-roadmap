# UC-PR-01: Phase 6 — Interactive Dashboard

**Date**: 2026-02-16
**Status**: COMPLETE

---

## 1. Deliverable Summary

| Item | Detail |
|------|--------|
| Output file | `dashboard.html` (57 KB, 754 lines) |
| Technology | Self-contained HTML + Chart.js 4.4 (CDN) |
| Server required | None — opens in any modern browser |
| Data freshness | All data embedded at build time from Phase 1-5 CSVs |
| Tabs | 6 interactive views |

## 2. Dashboard Architecture

### 2.1 Data Embedding Strategy

All data is embedded directly in the HTML as JavaScript objects to eliminate external dependencies:

| Source File | Embedded As | Records | Strategy |
|-------------|------------|---------|----------|
| `cost_model_output.csv` | `products[]` array | 58 SPUs | Full dataset |
| `trend_summary.csv` | `trends[]` array | 57 SPUs | Full dataset (excl. unmatched) |
| `monthly_sales.csv` | `monthlySales{}` object | ~40 SPUs × 8 months | Pipe-delimited string, parsed at runtime; filtered to Jun 2025+ with significant volume |
| `affinity_pairs.csv` | `affinityPairs[]` array | 28 pairs | Top pairs curated by lift and co-occurrence |

### 2.2 Tab Structure

| # | Tab | Key Visualizations | Interactive Features |
|---|-----|-------------------|---------------------|
| 1 | **Overview** | 4 KPI cards, classification doughnut, revenue by class bar, trend direction doughnut, trend×class stacked bar, monthly order volume | — |
| 2 | **BCG Matrix** | Scatter plot (CM% vs Mix%, bubble size = revenue) | Category filter (All/Hot/Iced/Food), hover tooltips |
| 3 | **Product Explorer** | Sortable data table (10 columns) | Search box, classification dropdown, column sort |
| 4 | **Trends** | Individual product monthly chart (qty bars + share line), top-10 share trends, momentum bar chart | Product selector dropdown |
| 5 | **Affinity** | 4 KPI cards, top-15 lift bars, cross-category bars, full pairs table | — |
| 6 | **Strategic Actions** | Watch List, Promotion Candidates, Bundle Recommendations, Volatile Items, Emerging Dogs | Classification-coded badges |

## 3. Key Metrics Displayed

### 3.1 Overview KPIs
- **$1.86M** cumulative revenue (560K units)
- **56.8%** revenue-weighted contribution margin
- **48%** average discount depth
- **+18.0%** monthly order CMGR (9-month period)

### 3.2 BCG Classification Distribution
| Class | Count | Revenue Share |
|-------|-------|--------------|
| Star | 14 | 46% |
| Plow Horse | 11 | 28% |
| Puzzle | 16 | 18% |
| Dog | 17 | 8% |

### 3.3 Trend Directions
| Direction | Count | % |
|-----------|-------|---|
| Growing (↑) | 27 | 41% |
| Stable (→) | 10 | 15% |
| Declining (↓) | 29 | 44% |

## 4. Design Decisions

### 4.1 Self-Contained Architecture
- **No backend required**: All data embedded in HTML, runs from file:// or any web server
- **CDN dependency**: Chart.js loaded from cdn.jsdelivr.net (requires internet on first load, cached thereafter)
- **No build tools**: Pure HTML/CSS/JS — no React, no bundler, no npm

### 4.2 Color System
| Element | Color | Hex |
|---------|-------|-----|
| Star | Red | `#e74c3c` |
| Plow Horse | Blue | `#3498db` |
| Puzzle | Orange | `#f39c12` |
| Dog | Gray | `#95a5a6` |
| Growing | Green | `#27ae60` |
| Stable | Blue | `#3498db` |
| Declining | Red | `#e74c3c` |

### 4.3 Responsive Layout
- CSS Grid with `auto-fit` columns for KPI cards
- Flexbox tab navigation
- Tables with horizontal scroll on small screens

## 5. Visualization Inventory

| Chart | Type | Library | Data Points |
|-------|------|---------|-------------|
| Classification Distribution | Doughnut | Chart.js | 4 classes |
| Revenue by Classification | Horizontal Bar | Chart.js | 4 classes |
| Trend Directions | Doughnut | Chart.js | 3 directions |
| Trend × Classification | Stacked Bar | Chart.js | 4×3 matrix |
| Monthly Order Volume | Bar | Chart.js | 8 months |
| BCG Scatter Plot | Scatter (bubble) | Chart.js | 58 products |
| Product Monthly Detail | Combo (bar + line) | Chart.js | 8 months per product |
| Top-10 Share Trends | Multi-line | Chart.js | 10 series × 8 months |
| Momentum Chart | Horizontal Bar | Chart.js | 20 products (top 10 + bottom 10) |
| Top-15 Affinity Lift | Horizontal Bar | Chart.js | 15 pairs |
| Cross-Category Lift | Horizontal Bar | Chart.js | 10 pairs |

**Total**: 11 interactive charts across 6 tabs

## 6. Strategic Actions Summary

### 6.1 Watch List — Declining Stars (5 items)
Items requiring investigation: Drip Coffee (-52%/mo), Iced Caramel Popcorn Latte (-35%/mo), Toffee Hazelnut Latte (-29%/mo), Iced Coconut Latte (-8%/mo), Vital Kale (-8%/mo)

### 6.2 Promotion Candidates — Growing Puzzles (7 items)
High-margin items gaining share that could be promoted to Star: Hot Chocolate, Almond Croissant, Chocolate Chip Cookies, Chocolate Croissant, Caramel Popcorn Latte, Double Chocolate Muffin, Creme Brulee Latte

### 6.3 Bundle Recommendations (6 bundles)
Cross-category pairings with lift > 1.5, estimated CM $4-5 per bundle

### 6.4 Volatile / Seasonal Items (5 items)
High coefficient of variation suggesting seasonal or promotional patterns

### 6.5 Emerging Dogs (1 item)
Coconut Velvet Latte (Hot) — gaining share at +25%/mo, may be too new to classify accurately

## 7. Limitations & Future Enhancements

| Limitation | Impact | Phase 7 Resolution |
|------------|--------|-------------------|
| Static data snapshot | Dashboard shows Feb 16, 2026 data only | Automated ETL refresh pipeline |
| CDN dependency | Requires internet for Chart.js | Could bundle locally |
| No drill-down by store | All data aggregated across stores | Add store dimension to ETL |
| No date range selector | Fixed 9-month analysis window | Add dynamic date filtering |
| 25 uncosted SPUs | Cannot classify without COGS | Expand cost model coverage |

---

*Generated by Claude Code — UC-PR-01 Menu Engineering Matrix*

# UC-PR-01: Phase 6 — Interactive Dashboard

**Date:** 2026-02-16
**Status:** COMPLETE

---

## 1. Deliverable Summary

| Item | Detail |
|------|--------|
| Output file | `data/dashboard.html` (57 KB, 754 lines) |
| Technology | Self-contained HTML + Chart.js 4.4 (CDN) |
| Server required | None — opens in any modern browser |
| Data freshness | All data embedded at build time from Phase 1–5 CSVs |
| Tabs | 6 interactive views |
| Charts | 11 interactive visualizations |

**Script:** `scripts/refresh_pipeline.py` (automated data refresh)

---

## 2. Dashboard Architecture

### 2.1 Data Embedding Strategy

All data is embedded directly in the HTML as JavaScript objects — no external file dependencies:

| Source File | Embedded As | Records | Strategy |
|-------------|------------|---------|----------|
| `cost_model_output.csv` | `products[]` array | 58 SPUs | Full dataset |
| `trend_summary.csv` | `trends[]` array | 57 SPUs | Full dataset (excl. unmatched) |
| `monthly_sales.csv` | `monthlySales{}` object | ~40 SPUs × 8 months | Pipe-delimited, parsed at runtime |
| `affinity_pairs.csv` | `affinityPairs[]` array | 28 pairs | Top pairs by lift and co-occurrence |

### 2.2 Self-Contained Design

- **No backend required:** Runs from `file://` or any web server
- **CDN dependency:** Chart.js loaded from cdn.jsdelivr.net (requires internet on first load, cached thereafter)
- **No build tools:** Pure HTML/CSS/JS — no React, no bundler, no npm

---

## 3. Tab Structure

| # | Tab | Visualizations | Interactive Features |
|---|-----|---------------|---------------------|
| 1 | **Overview** | 4 KPI cards, classification doughnut, revenue by class bar, trend direction doughnut, trend×class stacked bar, monthly order volume | — |
| 2 | **BCG Matrix** | Scatter plot (CM% vs Mix%, bubble size = revenue) | Category filter (All/Hot/Iced/Food), hover tooltips |
| 3 | **Product Explorer** | Sortable data table (10 columns) | Search box, classification dropdown, column sort |
| 4 | **Trends** | Product monthly chart (qty bars + share line), top-10 share trends, momentum bar | Product selector dropdown |
| 5 | **Affinity** | 4 KPI cards, top-15 lift bars, cross-category bars, full pairs table | — |
| 6 | **Strategic Actions** | Watch List, Promotion Candidates, Bundle Recommendations, Volatile Items, Emerging Dogs | Classification-coded badges |

---

## 4. Overview KPIs

| KPI | Value |
|-----|-------|
| Cumulative Revenue | **$1.86M** (560K units) |
| Revenue-Weighted CM% | **56.8%** |
| Average Discount Depth | **48%** |
| Monthly Order CMGR | **+18.0%** (9-month period) |

---

## 5. Visualization Inventory

| Chart | Type | Library | Data Points |
|-------|------|---------|-------------|
| Classification Distribution | Doughnut | Chart.js | 4 classes |
| Revenue by Classification | Horizontal Bar | Chart.js | 4 classes |
| Trend Directions | Doughnut | Chart.js | 3 directions |
| Trend × Classification | Stacked Bar | Chart.js | 4×3 matrix |
| Monthly Order Volume | Bar | Chart.js | 8 months |
| BCG Scatter Plot | Scatter (bubble) | Chart.js | 58 products |
| Product Monthly Detail | Combo (bar + line) | Chart.js | 8 months/product |
| Top-10 Share Trends | Multi-line | Chart.js | 10 series × 8 months |
| Momentum Chart | Horizontal Bar | Chart.js | 20 products (top 10 + bottom 10) |
| Top-15 Affinity Lift | Horizontal Bar | Chart.js | 15 pairs |
| Cross-Category Lift | Horizontal Bar | Chart.js | 10 pairs |

---

## 6. Color System

| Element | Color | Hex |
|---------|-------|-----|
| Star | Red | `#e74c3c` |
| Plow Horse | Blue | `#3498db` |
| Puzzle | Orange | `#f39c12` |
| Dog | Gray | `#95a5a6` |
| Growing | Green | `#27ae60` |
| Stable | Blue | `#3498db` |
| Declining | Red | `#e74c3c` |

---

## 7. Strategic Actions (Tab 6)

### 7.1 Watch List — Declining Stars (5 items)
Drip Coffee (-52%/mo), Iced Caramel Popcorn Latte (-35%/mo), Toffee Hazelnut Latte (-29%/mo), Iced Coconut Latte (-8%/mo), Vital Kale (-8%/mo)

### 7.2 Promotion Candidates — Growing Puzzles (7 items)
Hot Chocolate, Almond Croissant, Chocolate Chip Cookies, Chocolate Croissant, Caramel Popcorn Latte, Double Chocolate Muffin, Creme Brulee Latte

### 7.3 Bundle Recommendations (6 bundles)
Cross-category pairings with lift > 1.5, estimated CM $4–5 per bundle

### 7.4 Volatile / Seasonal Items (5 items)
High coefficient of variation suggesting seasonal or promotional patterns

### 7.5 Emerging Dogs (1 item)
Coconut Velvet Latte (Hot) — gaining share at +25%/mo, may be too new to classify accurately

---

## 8. Responsive Design

- **CSS Grid** with `auto-fit` columns for KPI cards
- **Flexbox** tab navigation
- **Horizontal scroll** on tables for small screens

---

## 9. Limitations & Future Enhancements

| Limitation | Impact | Resolution |
|------------|--------|------------|
| Static data snapshot | Dashboard shows Feb 16, 2026 data only | Automated ETL refresh pipeline (`refresh_pipeline.py`) |
| CDN dependency | Requires internet for Chart.js | Could bundle Chart.js locally |
| No drill-down by store | All data aggregated across 10 stores | Add store dimension to ETL |
| No date range selector | Fixed 9-month analysis window | Add dynamic date filtering |
| 25 uncosted SPUs | Cannot classify without COGS | Expand cost model coverage |

---

*Generated by Claude Code — UC-PR-01 Menu Engineering Matrix*

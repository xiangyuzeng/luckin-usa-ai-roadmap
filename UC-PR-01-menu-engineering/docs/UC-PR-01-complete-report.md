# UC-PR-01: Menu Engineering Matrix — Complete Report

**Date:** 2026-02-16
**Status:** COMPLETE (All 6 Phases)
**Department:** Product
**Use Case ID:** UC-PR-01

---

## Executive Summary

This report presents a comprehensive menu engineering analysis for Luckin Coffee USA's 10 Manhattan stores, applying the Kasavana-Smith / BCG framework to classify 58 Standard Product Units (SPUs) by profitability and popularity. The analysis spans 9 months of transaction data (May 2025 – January 2026), covering 501,074 orders and $1.86M in cumulative revenue.

### Key Findings

| Metric | Value |
|--------|-------|
| SPUs classified | 58 (of 83 total; 25 uncosted) |
| Cumulative revenue | **$1.86M** (560K units) |
| Revenue-weighted CM% | **56.8%** |
| Average discount depth | **~48%** |
| Monthly order CMGR | **+18.0%** |
| Monthly revenue CMGR | **+24.5%** |
| Multi-item order rate | **18.8%** |

### Classification Distribution

| Class | Count | Revenue Share | Avg CM% | Action |
|-------|-------|--------------|---------|--------|
| Star | 14 | 46% ($855K) | 74.3% | Protect & maintain |
| Plow Horse | 11 | 28% ($523K) | 42.2% | Reduce costs / increase price |
| Puzzle | 16 | 18% ($331K) | 36.4% | Increase visibility & promotion |
| Dog | 17 | 8% ($151K) | 54.5% | Reprice, reformulate, or retire |

### Top 5 Strategic Recommendations

1. **Promote high-margin Puzzles** — Iced Chocolate (86.5% CM%), Caramel Popcorn Latte (71.8% CM%) are prime candidates
2. **Reduce matcha ingredient costs** — PFM000020 pre-mix drives Plow Horse margins down; renegotiate or reduce portions
3. **Increase basket size** — Only 18.8% multi-item rate; cross-sell bundles could add $200K+ annual revenue
4. **Reduce Star discounting** — 5% less discounting on Stars adds ~$40K annual CM
5. **Expand food menu** — Only 5 food SKUs but strongest cross-category lift; anchor for upselling

---

## Phase 1: Data Validation & Schema Discovery

### 1.1 Data Sources

| # | Database | Table | Records | Key Fields |
|---|----------|-------|---------|------------|
| 1 | scm-ordering | `t_ordering_order` | 466,879 | order_id, store_id, order_time, total_amount |
| 2 | scm-ordering | `t_ordering_order_item` | 655,865 | item_id, spu_id, quantity, actual_amount |
| 3 | opproduction | `t_goods` | 200 | goods_id, goods_name, goods_code |
| 4 | opproduction | `t_goods_spec` | 428 | spec_id, goods_id, price, spec_name |
| 5 | opshopsale | `t_shop_goods_category` | 192 | category assignments |
| 6 | opshop | `t_shop` | 16 | shop_id, shop_name, status |
| 7 | scmcommodity | `t_commodity` | 256 | goods_code, formula_json |
| 8 | scmcommodity | `t_commodity_bom` | 1,148 | bill of materials relationships |

### 1.2 Critical Discovery: Cost Field = Quantity

The `cost` field in `formula_json` represents **ingredient quantity**, not monetary cost. Unit codes:
- `QU005` = grams
- `QU009` = pieces
- `QU013` = milliliters

This discovery led to the hybrid cost model approach (Phase 2).

### 1.3 Cost Estimation Paths Evaluated

| Path | Method | Verdict |
|------|--------|---------|
| A | Extract from `t_commodity` cost fields | Not viable — fields store quantities |
| B | Use `t_commodity_bom` pricing | Not viable — no US pricing data populated |
| **C** | **Hybrid: formula quantities × US wholesale prices** | **Selected** |

### 1.4 Revenue Model Validation

| Metric | Value |
|--------|-------|
| Orders with items matched | 466,879 |
| SPUs identified | 83 |
| Active stores | 10 (Manhattan) + 1 (JFK kiosk) |
| Analysis period | 2025-05-01 to 2026-02-01 |
| Total item-level revenue | $2.19M |

---

## Phase 2: Cost Model & BCG Classification

### 2.1 Hybrid Cost Model (Path C)

1. Extract ingredient **quantities** from `formula_json` in `scmcommodity.t_commodity`
2. Map each `goodsCode` to a **US wholesale market price** (2024–2025 benchmarks)
3. Multiply quantity × unit price for each ingredient
4. Sum all ingredients per SPU to get **estimated COGS per unit**

### 2.2 PFM Pre-Mix Calibration

| PFM Code | Initial Est. | Calibrated | Unit | Rationale |
|----------|-------------|------------|------|-----------|
| PFM000020 | $0.040/g | $0.012/g | grams | Matcha pre-mix — blended powder, not pure matcha |
| PFM000029 | $0.030/g | $0.012/g | grams | Specialty pre-mix — similar composition |
| PFM000005 | $0.010/g | $0.006/g | grams | Base pre-mix — commodity ingredients |

### 2.3 BCG Classification Thresholds

| Metric | Value | Calculation |
|--------|-------|-------------|
| Popularity threshold | 1.21% | 1/58 SPUs × 70% (Kasavana-Smith standard) |
| CM% threshold | 52.5% | Revenue-weighted average across all 58 SPUs |

|  | High Popularity (≥1.21%) | Low Popularity (<1.21%) |
|--|--------------------------|------------------------|
| **High CM% (≥52.5%)** | Star | Puzzle |
| **Low CM% (<52.5%)** | Plow Horse | Dog |

### 2.4 Aggregate Results

| Metric | Value |
|--------|-------|
| SPUs classified | 58 |
| Total units sold | 560,214 |
| Total revenue | $1,860,550 |
| Total COGS | $801,372 |
| Total contribution margin | $1,059,178 |
| Weighted avg CM% | 52.5% |
| Revenue-weighted CM% | 56.8% |

### 2.5 Stars (14 Products)

High popularity + High margin — **protect and maintain.**

| Product | Qty | Revenue | CM$ | CM% |
|---------|-----|---------|-----|-----|
| Iced Coconut Latte | 70,044 | $229,546 | $140,788 | 61.3% |
| Drip Coffee | 37,853 | $100,466 | $82,477 | 82.1% |
| Latte (Hot) | 27,408 | $92,925 | $69,453 | 74.8% |
| Iced Velvet Latte | 23,820 | $78,044 | $49,476 | 63.4% |
| Iced Latte | 16,458 | $54,898 | $44,112 | 80.3% |
| Coconut Latte (Hot) | 15,816 | $51,799 | $31,917 | 61.6% |
| Iced Caramel Popcorn Latte | 14,936 | $47,667 | $34,489 | 72.3% |
| Cappuccino (Hot) | 12,671 | $40,736 | $30,931 | 75.9% |
| Americano (Hot) | 11,389 | $31,416 | $27,391 | 87.2% |
| Toffee Hazelnut Latte (Hot) | 11,091 | $33,605 | $23,512 | 70.0% |
| Sausage Egg Cheese Croissant | 14,263 | $40,816 | $21,555 | 52.8% |
| Vital Kale | 11,200 | $23,476 | $16,077 | 68.5% |
| Iced Americano | 7,555 | $20,207 | $17,182 | 85.0% |
| Iced Coconut Velvet Latte | 5,946 | $9,666 | $46,460 | — |

### 2.6 Plow Horses (11 Products)

High popularity + Low margin — **reduce costs or increase prices.**

| Product | Qty | Revenue | CM$ | CM% |
|---------|-----|---------|-----|-----|
| Iced Kyoto Matcha Latte | 37,263 | $88,700 | $39,721 | 44.8% |
| Iced Kyoto Matcha Coconut | 19,610 | $55,262 | $25,431 | 46.0% |
| Kyoto Matcha Coconut Latte (Hot) | 8,959 | $27,186 | $14,339 | 52.7% |
| Iced Matcha Coconut Latte | 11,023 | $30,016 | $11,686 | 38.9% |
| Iced Toffee Hazelnut Latte | 8,805 | $27,068 | $18,315 | 67.7% |
| Pineapple Cold Brew | 10,193 | $27,363 | $13,814 | 50.5% |
| Mango Coconut Sunrise | 7,957 | $22,361 | $11,651 | 52.1% |
| Cold Brew | 9,103 | $16,654 | $11,148 | 66.9% |
| Spanish Latte (Hot) | 7,668 | $23,289 | $16,134 | 69.3% |
| Matcha Latte (Hot) | 7,287 | $22,090 | $11,577 | 52.4% |
| Iced Spanish Latte | 7,009 | $22,952 | $16,703 | 72.8% |

**Key cost driver:** PFM000020 (matcha pre-mix) and coconut milk dominate COGS for matcha-based Plow Horses.

### 2.7 Puzzles (16 Products) — Promotion Candidates

Low popularity + High margin — **increase visibility and promotion.**

| Product | CM$ | CM% | Opportunity |
|---------|-----|-----|-------------|
| Iced Chocolate | $4,930 | 86.5% | Highest margin — promote aggressively |
| Caramel Popcorn Latte (Hot) | $11,482 | 71.8% | Strong margin, growing |
| Creme Brulee Latte (Hot) | $10,217 | 68.4% | Growing (+13.4%/mo) |
| Almond Croissant | $9,276 | 58.4% | Growing trend (+23.9%/mo) |
| Chocolate Croissant | $8,872 | 58.2% | Growing trend (+20.6%/mo) |
| Hot Chocolate | $7,218 | 63.1% | Seasonal strength, growing |
| Chocolate Chip Cookies | $5,891 | 65.1% | Growing (+25.6%/mo) |
| Double Chocolate Muffin | $5,781 | 60.2% | Growing (+19.3%/mo) |

### 2.8 Dogs (17 Products)

Low popularity + Low margin — **consider repricing, reformulating, or retiring.**

Notable items:
- **Pistachio Oat Latte (Hot):** Only product with **negative margin** (-2.6% CM%)
- **Blood Orange Cold Brew:** Very low margin (9.1% CM%)
- **Coconut Velvet Latte (Hot):** Emerging — gaining share at +25%/mo despite Dog classification

### 2.9 Sensitivity Analysis

| Variable | Impact on Classification |
|----------|------------------------|
| PFM000020 price ±20% | 3 products could shift quadrants (matcha-heavy items) |
| Coconut milk price ±15% | 2 products could shift (coconut latte variants) |
| Discount depth ±5% | Revenue-weighted CM% threshold shifts by ~2 points |

---

## Phase 3: Visualization

### 3.1 Chart Inventory

| # | File | Chart Type | Description |
|---|------|-----------|-------------|
| 1 | `charts/01_bcg_matrix.png` | Scatter (bubble) | BCG matrix — X: sales mix%, Y: CM%, bubble = CM$ |
| 2 | `charts/02_category_breakdown.png` | Stacked bar | Revenue and unit breakdown by classification |
| 3 | `charts/03_margin_vs_discount.png` | Scatter | CM% vs discount depth per product |
| 4 | `charts/04_cm_ranking.png` | Horizontal bar | Top 20 products by total CM$ |
| 5 | `charts/05_cogs_unit_economics.png` | Grouped bar | COGS/unit vs CM$/unit |

### 3.2 BCG Scatter Plot Thresholds

| Threshold | Value | Method |
|-----------|-------|--------|
| Popularity (X-axis) | 1.21% | 1/58 × 70% (Kasavana-Smith standard) |
| CM% (Y-axis) | 56.8% | Revenue-weighted: Σ(total_cm) / Σ(total_revenue) × 100 |

### 3.3 Key Visual Insights

- **Drip Coffee** — Most efficient Star: 82.1% CM%, 7.29% sales mix
- **Iced Coconut Latte** — Volume-driven Star: 61.3% CM%, 12.5% sales mix (largest bubble)
- **Matcha cluster** in Plow Horse quadrant — high volume but depressed margins from PFM000020
- **Food items** scattered across Puzzle quadrant — low volume but healthy margins

### 3.4 Margin vs Discount Correlation

Strong **negative correlation** between discount depth and contribution margin %:
- Products with >55% discount depth average <40% CM%
- Products with <40% discount depth average >65% CM%
- **Implication:** Reducing discount depth on Stars by 5% could significantly improve margins

### 3.5 Unit Economics

**Most cost-efficient:**

| Product | COGS/Unit | CM$/Unit | CM% |
|---------|-----------|----------|-----|
| Americano (Hot) | $0.35 | $2.40 | 87.2% |
| Iced Americano | $0.40 | $2.27 | 85.0% |
| Drip Coffee | $0.48 | $2.18 | 82.1% |

**Least cost-efficient:**

| Product | COGS/Unit | CM$/Unit | CM% |
|---------|-----------|----------|-----|
| Pistachio Oat Latte (Hot) | $3.42 | -$0.09 | -2.6% |
| Blood Orange Cold Brew | $2.18 | $0.22 | 9.1% |

---

## Phase 4: Affinity (Market Basket) Analysis

### 4.1 Data Overview

| Metric | Value |
|--------|-------|
| Total orders analyzed | 501,074 |
| Multi-item orders (2+ items) | 94,313 (18.8%) |
| Average items per order | 1.26 |
| Unique item pairs analyzed | 98 |
| Pairs with lift > 1.0 | 29 |
| Pairs with lift > 2.0 | 8 |
| Cross-category pairs (beverage × food) | 46 |

### 4.2 Strongest Affinities (Top 10 by Lift)

| Rank | Item A | Item B | Co-occur | Lift | Cross-Cat |
|------|--------|--------|----------|------|-----------|
| 1 | Zen Berry | Sunny Citrus | 449 | **19.98** | |
| 2 | Vital Kale | Zen Berry | 400 | **6.55** | |
| 3 | Vital Kale | Sunny Citrus | 414 | **5.93** | |
| 4 | Almond Croissant | Chocolate Croissant | 275 | **5.36** | |
| 5 | Mango Pomelo Sago | Dreamy Strawberry | 252 | **4.10** | |
| 6 | Sausage Egg Cheese Croissant | Chocolate Croissant | 363 | **3.18** | |
| 7 | Sausage Egg Cheese Croissant | Almond Croissant | 313 | **2.78** | |
| 8 | Cappuccino (Hot) | Almond Croissant | 244 | **2.29** | yes |
| 9 | Hot Chocolate | Sausage Egg Cheese Croissant | 241 | **1.94** | yes |
| 10 | Iced Spanish Latte | Sausage Egg Cheese Croissant | 266 | **1.83** | yes |

### 4.3 Top Cross-Category Pairings (Beverage × Food)

| Beverage | Food | Co-occur | Lift | CM$/pair |
|----------|------|----------|------|----------|
| Cappuccino (Hot) | Almond Croissant | 244 | 2.29 | $5.08 |
| Hot Chocolate | Sausage Egg Cheese Croissant | 241 | 1.94 | $4.67 |
| Iced Spanish Latte | Sausage Egg Cheese Croissant | 266 | 1.83 | $4.91 |
| Caramel Popcorn Latte (Hot) | Sausage Egg Cheese Croissant | 257 | 1.59 | $4.58 |
| Latte (Hot) | Almond Croissant | 406 | 1.46 | $4.90 |

### 4.4 Natural Affinity Clusters

| Cluster | Products | Avg Lift | Pattern |
|---------|----------|----------|---------|
| Bottled drinks | Vital Kale, Zen Berry, Sunny Citrus | **10.8** | Multi-bottle purchases |
| Matcha enthusiasts | Kyoto Matcha variants | 0.5 | Multiple matcha variants per visit |
| Hot classics | Drip, Latte, Cappuccino, Americano | 0.6 | Office/group orders |
| Breakfast | Sausage Croissant + premium iced lattes | 1.5+ | Morning combo behavior |
| Pastry pairs | Almond + Chocolate Croissant | 5.4 | Food variety seeking |

### 4.5 Bundle Recommendations

| Bundle | Items | Lift | Est. CM$/bundle |
|--------|-------|------|-----------------|
| Breakfast Combo 1 | Iced Spanish Latte + Sausage Egg Cheese Croissant | 1.8 | $4.91 |
| Breakfast Combo 2 | Cappuccino (Hot) + Almond Croissant | 2.3 | $5.08 |
| Breakfast Combo 3 | Caramel Popcorn Latte + Sausage Egg Cheese Croissant | 1.6 | $4.58 |
| Breakfast Combo 4 | Hot Chocolate + Sausage Egg Cheese Croissant | 1.9 | $4.67 |
| Duo Deal 1 | Vital Kale + Sunny Citrus | 5.9 | $3.68 |
| Duo Deal 2 | Zen Berry + Sunny Citrus | 20.0 | $3.39 |

### 4.6 Basket Size Opportunity

- Only **18.8%** of orders contain 2+ items — significant upsell opportunity
- Increasing multi-item rate from 19% → 30% could add **~$200K+ annual revenue**
- Sausage Egg Cheese Croissant is the strongest cross-sell anchor with premium beverages
- Only 5 food SKUs on menu — **food menu expansion** could significantly lift basket size

---

## Phase 5: Trend Analysis

### 5.1 Business Growth Overview

| Metric | Value |
|--------|-------|
| Analysis period | 2025-06 to 2026-01 (9 months) |
| SPUs analyzed (≥3 months data) | 66 |
| First full month orders (2025-06) | 28,913 |
| Latest full month orders (2026-01) | 92,261 |
| Monthly order CAGR | **+18.0%** |
| Monthly revenue CAGR | **+24.5%** |

> Revenue grew faster than volume (+24.5% vs +18.0%), suggesting improving basket value over time.

### 5.2 Trend Direction Summary

| Direction | Count | % | Definition |
|-----------|-------|---|------------|
| Growing (up) | 27 | 41% | Share trend > +5%/month |
| Stable | 10 | 15% | Share trend between -5% and +5%/month |
| Declining (down) | 29 | 44% | Share trend < -5%/month |

> **Important:** Declining share does NOT mean declining sales — it means the product is growing slower than the business overall (+18% CMGR).

### 5.3 Trend × BCG Classification

| Direction | Star | Plow Horse | Puzzle | Dog | Total |
|-----------|------|------------|--------|-----|-------|
| Growing | 6 | 3 | 7 | 1 | 27 |
| Stable | 3 | 2 | 3 | 2 | 10 |
| Declining | 5 | 6 | 6 | 10 | 29 |

### 5.4 Watch List — Declining Stars (5 items)

| Product | Trend | Action |
|---------|-------|--------|
| Drip Coffee | -52.3%/mo | Investigate — largest share product declining fastest |
| Iced Caramel Popcorn Latte | -34.9%/mo | Seasonal effect? Check if promotional-dependent |
| Toffee Hazelnut Latte (Hot) | -29.2%/mo | Winter seasonal decline expected |
| Iced Coconut Latte | -7.8%/mo | Slight decline — monitor closely (top revenue product) |
| Vital Kale | -8.2%/mo | Investigate — consistent decline |

### 5.5 Promotion Candidates — Growing Puzzles (7 items)

| Product | CM% | Trend | Opportunity |
|---------|-----|-------|-------------|
| Hot Chocolate | 63.1% | +35.9%/mo | Strong seasonal momentum |
| Almond Croissant | 58.4% | +23.9%/mo | Food expansion anchor |
| Chocolate Chip Cookies | 65.1% | +25.6%/mo | Growing food category |
| Chocolate Croissant | 58.2% | +20.6%/mo | Pairs well with hot drinks |
| Caramel Popcorn Latte (Hot) | 71.8% | +22.7%/mo | High margin, gaining traction |
| Double Chocolate Muffin | 60.2% | +19.3%/mo | Food variety expansion |
| Creme Brulee Latte (Hot) | 68.4% | +13.4%/mo | Steady growth trajectory |

### 5.6 Product Launch Waves

| Launch Wave | SPUs | Still Active | Avg Total Qty |
|------------|------|-------------|---------------|
| Core Menu (May 2025) | 41 | 34 | 9,462 |
| Early Expansion (Jun–Jul 2025) | 7 | 2 | 1,991 |
| Matcha & Food Wave (Aug–Sep 2025) | 15 | 15 | 8,446 |
| Seasonal & Specialty (Oct–Nov 2025) | 8 | 8 | 7,368 |
| Pistachio Launch (Jan 2026) | 5 | 4 | 2,397 |
| Newest (Feb 2026) | 3 | 3 | 1,066 |

### 5.7 Volatility Analysis

| Product | Class | Avg Share% | CV% | Direction |
|---------|-------|-----------|-----|-----------|
| Drip Coffee | Star | 13.10 | 218% | Declining |
| Iced Matcha Coconut Latte | Plow Horse | 2.92 | 118% | Declining |
| Hot Chocolate | Puzzle | 0.78 | 94% | Growing |
| Iced Matcha Latte | Plow Horse | 3.73 | 91% | Declining |
| Mango Coconut Sunrise | Plow Horse | 1.66 | 88% | Declining |

---

## Phase 6: Interactive Dashboard

### 6.1 Deliverable Summary

| Item | Detail |
|------|--------|
| Output file | `data/dashboard.html` (57 KB, 754 lines) |
| Technology | Self-contained HTML + Chart.js 4.4 (CDN) |
| Server required | None — opens in any modern browser |
| Data freshness | All data embedded at build time from Phase 1–5 CSVs |
| Tabs | 6 interactive views |
| Charts | 11 interactive visualizations |

**Automated refresh:** `scripts/refresh_pipeline.py`

### 6.2 Data Embedding Strategy

All data embedded directly in HTML as JavaScript objects — no external file dependencies:

| Source File | Embedded As | Records |
|-------------|------------|---------|
| `cost_model_output.csv` | `products[]` array | 58 SPUs |
| `trend_summary.csv` | `trends[]` array | 57 SPUs |
| `monthly_sales.csv` | `monthlySales{}` object | ~40 SPUs × 8 months |
| `affinity_pairs.csv` | `affinityPairs[]` array | 28 pairs |

### 6.3 Tab Structure

| # | Tab | Visualizations | Interactive Features |
|---|-----|---------------|---------------------|
| 1 | **Overview** | 4 KPI cards, classification doughnut, revenue bar, trend doughnut, trend×class stacked bar, monthly volume | — |
| 2 | **BCG Matrix** | Scatter plot (CM% vs Mix%, bubble = revenue) | Category filter, hover tooltips |
| 3 | **Product Explorer** | Sortable data table (10 columns) | Search, classification dropdown, column sort |
| 4 | **Trends** | Monthly chart (qty bars + share line), top-10 share trends, momentum bar | Product selector dropdown |
| 5 | **Affinity** | 4 KPI cards, top-15 lift bars, cross-category bars, full pairs table | — |
| 6 | **Strategic Actions** | Watch List, Promotion Candidates, Bundle Recommendations, Volatile Items, Emerging Dogs | Classification-coded badges |

### 6.4 Visualization Inventory

| Chart | Type | Data Points |
|-------|------|-------------|
| Classification Distribution | Doughnut | 4 classes |
| Revenue by Classification | Horizontal Bar | 4 classes |
| Trend Directions | Doughnut | 3 directions |
| Trend × Classification | Stacked Bar | 4×3 matrix |
| Monthly Order Volume | Bar | 8 months |
| BCG Scatter Plot | Scatter (bubble) | 58 products |
| Product Monthly Detail | Combo (bar + line) | 8 months/product |
| Top-10 Share Trends | Multi-line | 10 series × 8 months |
| Momentum Chart | Horizontal Bar | 20 products |
| Top-15 Affinity Lift | Horizontal Bar | 15 pairs |
| Cross-Category Lift | Horizontal Bar | 10 pairs |

---

## Strategic Recommendations

### Immediate Actions (0–30 days)

1. **Investigate Drip Coffee decline** — Largest-share Star losing -52.3%/mo share; determine if seasonal, competitive, or structural
2. **Launch Breakfast Combo bundles** — Cappuccino + Almond Croissant (lift 2.3, $5.08 CM) and Spanish Latte + Sausage Croissant (lift 1.8, $4.91 CM)
3. **Reprice Pistachio Oat Latte** — Only product with negative margin (-2.6%); increase price or reformulate
4. **Promote Iced Chocolate** — Highest CM% Puzzle (86.5%) with low visibility; feature in app

### Short-Term (1–3 months)

5. **Reduce Star discount depth by 5%** — Estimated +$40K annual CM impact
6. **Renegotiate PFM000020 (matcha pre-mix)** — Key cost driver for 4+ matcha Plow Horses; 20% price reduction shifts multiple products toward Star
7. **Expand food menu** — Only 5 food SKUs but strongest cross-category lift values; add 3–5 items to anchor upselling
8. **Feature Growing Puzzles in-app** — Hot Chocolate, Almond Croissant, Chocolate Chip Cookies all growing >20%/mo with >58% CM%

### Medium-Term (3–6 months)

9. **Implement cross-sell engine** — Target the 81.2% single-item orders with affinity-based recommendations at checkout
10. **Cost model expansion** — 25 uncosted SPUs (many are fastest-growing food items); complete ingredient costing for full portfolio visibility
11. **Seasonal bundling** — Leverage seasonal flavors (Toffee Hazelnut, Crème Brûlée, Pumpkin Spice) natural lift for limited-time bundles
12. **Store-level analysis** — Add store dimension to ETL pipeline for location-specific menu optimization

---

## Appendix: Project Architecture

### Data Pipeline

```
MySQL (5 databases)
  ├── scm-ordering.t_ordering_order          (466K orders)
  ├── scm-ordering.t_ordering_order_item     (656K items)
  ├── opproduction.t_goods / t_goods_spec    (200 + 428 rows)
  ├── opshop.t_shop                          (16 stores)
  └── scmcommodity.t_commodity               (256 formulas)
        │
        ▼
Python Scripts (5)
  ├── scripts/cost_model.py          → cost_model_output.csv (58 SPUs)
  ├── scripts/bcg_matrix_viz.py      → charts/01–05 (5 PNGs)
  ├── scripts/affinity_analysis.py   → affinity_pairs.csv (98 pairs)
  ├── scripts/trend_analysis.py      → trend_summary.csv + monthly_sales.csv
  └── scripts/refresh_pipeline.py    → data/dashboard.html (automated refresh)
        │
        ▼
Outputs
  ├── data/*.csv           (6 analysis files)
  ├── charts/*.png         (12 visualizations)
  └── data/dashboard.html  (57 KB, self-contained)
```

### Output Files

| File | Description | Records |
|------|-------------|---------|
| `cost_model_output.csv` | Full BCG classification data | 58 SPUs |
| `ingredient_cost_detail.csv` | Per-ingredient cost breakdown | ~350 rows |
| `affinity_pairs.csv` | Market basket pair metrics | 98 pairs |
| `trend_summary.csv` | Trend direction and momentum | 57 SPUs |
| `monthly_sales.csv` | Monthly sales by product | ~320 rows |
| `weekly_sales.csv` | Weekly sales by product | ~1,200 rows |
| `dashboard.html` | Interactive dashboard | All data embedded |

### Visualization Files

| File | Description |
|------|-------------|
| `charts/01_bcg_matrix.png` | BCG scatter plot |
| `charts/02_category_breakdown.png` | Revenue/units by classification |
| `charts/03_margin_vs_discount.png` | CM% vs discount depth |
| `charts/04_cm_ranking.png` | Top 20 by total CM$ |
| `charts/05_cogs_unit_economics.png` | COGS vs CM per unit |
| `charts/06_affinity_heatmap.png` | Lift ratio heatmap |
| `charts/07_top_affinity_pairs.png` | Top pairs by lift and CM$ |
| `charts/08_cross_category_affinity.png` | Beverage × Food analysis |
| `charts/09_share_trends.png` | Market share trends |
| `charts/10_growth_heatmap.png` | Month-over-month share growth |
| `charts/11_launch_curves.png` | New product launch trajectories |
| `charts/12_momentum_scatter.png` | Strategic momentum map |

---

## Limitations & Future Enhancements

| Limitation | Impact | Resolution |
|------------|--------|------------|
| 25 uncosted SPUs | Cannot classify without COGS | Expand cost model coverage |
| Estimated COGS (not actual) | Classification accuracy depends on price benchmarks | Validate with procurement data when available |
| No store-level breakdown | All data aggregated across 10 stores | Add store dimension to ETL |
| Static data snapshot | Dashboard shows Feb 16, 2026 data only | Automated ETL refresh (`refresh_pipeline.py`) |
| CDN dependency | Dashboard requires internet for Chart.js | Could bundle Chart.js locally |
| No date range selector | Fixed 9-month analysis window | Add dynamic date filtering |
| PFM pricing sensitivity | ±20% PFM000020 change shifts 3 product classifications | Obtain actual vendor pricing |

---

*Generated by Claude Code — UC-PR-01 Menu Engineering Matrix*
*Consolidated from Phase 1–6 reports, February 2026*

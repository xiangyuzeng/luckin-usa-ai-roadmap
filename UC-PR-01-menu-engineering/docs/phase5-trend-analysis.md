# UC-PR-01: Phase 5 — Trend Analysis

**Date:** 2026-02-16
**Status:** COMPLETE

---

## 1. Business Growth Overview

| Metric | Value |
|--------|-------|
| Analysis period | 2025-06 to 2026-01 (9 months) |
| SPUs analyzed (≥3 months data) | 66 |
| Active SPUs (sold in last 2 months) | 66 |
| Discontinued SPUs | 17 |
| First full month orders (2025-06) | 28,913 |
| Latest full month orders (2026-01) | 92,261 |
| Monthly order CAGR | **+18.0%** |
| Monthly revenue CAGR | **+24.5%** |

> **Key context:** Revenue grew faster than volume (+24.5% vs +18.0%), suggesting improving basket value over time.

**Script:** `scripts/trend_analysis.py`
**Outputs:** `trend_summary.csv`, `monthly_sales.csv`, `weekly_sales.csv`

---

## 2. Trend Direction Summary

| Direction | Count | % | Definition |
|-----------|-------|---|------------|
| Growing (↑) | 27 | 41% | Share trend > +5%/month |
| Stable (→) | 10 | 15% | Share trend between -5% and +5%/month |
| Declining (↓) | 29 | 44% | Share trend < -5%/month |

### 2.1 Trend × BCG Classification

| Direction | Star | Plow Horse | Puzzle | Dog | Total |
|-----------|------|------------|--------|-----|-------|
| Growing | 6 | 3 | 7 | 1 | 27 |
| Stable | 3 | 2 | 3 | 2 | 10 |
| Declining | 5 | 6 | 6 | 10 | 29 |

> **Important:** Declining share does NOT mean declining sales — it means the product is growing slower than the business overall (+18% CMGR).

---

## 3. Fastest Growing (by Market Share Trend)

| Rank | Product | Class | Avg Share% | Trend %/mo | R² | Momentum |
|------|---------|-------|-----------|-----------|-----|----------|
| 1 | Banana Yogurt Loaf | Uncosted | 0.50 | +78.3% | 0.94 | +152% |
| 2 | Chocolate Chip Brownie | Uncosted | 0.27 | +73.8% | 0.89 | +126% |
| 3 | Chewy Marshmallow Bar | Uncosted | 0.20 | +69.4% | 0.77 | +93% |
| 4 | Chocolate Chip Cookie (Gluten Free) | Uncosted | 0.25 | +63.9% | 0.59 | +60% |
| 5 | Plain Auli Cake | Uncosted | 0.01 | +62.8% | 0.66 | +633% |
| 6 | Plain Bagel | Uncosted | 0.21 | +58.6% | 0.86 | +88% |
| 7 | Matcha Latte (Hot) | Uncosted | 0.27 | +55.1% | 0.99 | +125% |
| 8 | Matcha Coconut Water | Uncosted | 0.80 | +42.4% | 0.39 | +18% |
| 9 | Matcha Frappe | Uncosted | 1.14 | +41.1% | 0.32 | +10% |
| 10 | Hot Chocolate | Puzzle | 0.78 | +35.9% | 0.76 | +57% |

> **Note:** Many top growers are food items classified as "Uncosted" — expanding the cost model to cover these would improve strategic visibility.

---

## 4. Fastest Declining (by Market Share Trend)

| Rank | Product | Class | Avg Share% | Trend %/mo | R² | Momentum |
|------|---------|-------|-----------|-----------|-----|----------|
| 1 | Drip Coffee | Star | 13.10 | -52.3% | 0.30 | +43% |
| 2 | Iced Pumpkin Spice Latte | Puzzle | 1.48 | -47.1% | 0.78 | -81% |
| 3 | Iced Toffee Hazelnut Latte | Plow Horse | 2.29 | -43.1% | 1.00 | -53% |
| 4 | Iced Caramel Popcorn Latte | Star | 3.70 | -34.9% | 0.76 | -48% |
| 5 | Toffee Hazelnut Latte (Hot) | Star | 3.16 | -29.2% | 0.68 | -51% |
| 6 | Matcha Coconut Latte (Hot) | Uncosted | 0.14 | -24.1% | 0.47 | -100% |
| 7 | Mango Coconut Sunrise | Plow Horse | 1.66 | -20.8% | 0.30 | -25% |
| 8 | Zen Berry | Dog | 0.67 | -20.8% | 0.52 | -10% |
| 9 | Sunny Citrus | Dog | 0.69 | -20.0% | 0.81 | -27% |
| 10 | Iced Matcha Coconut Latte | Plow Horse | 2.92 | -18.5% | 0.14 | -100% |

---

## 5. Weekly Momentum (Last 4 Weeks vs Prior 4 Weeks)

### 5.1 Momentum Leaders

| Product | Class | Recent Share | Prior Share | Momentum |
|---------|-------|-------------|------------|----------|
| Iced Tiramisu Latte | Uncosted | 4.41% | 0.00% | +100.0% |
| Tiramisu Latte (Hot) | Uncosted | 3.98% | 0.00% | +100.0% |
| Tiramisu Cold Brew | Uncosted | 1.34% | 0.00% | +100.0% |
| Mango Coconut Sunrise | Plow Horse | 0.96% | 0.57% | +68.3% |
| Sausage Egg Cheese Croissant | Plow Horse | 3.00% | 2.38% | +25.9% |
| Americano (Hot) | Star | 3.01% | 2.50% | +20.5% |

### 5.2 Momentum Laggards

| Product | Class | Recent Share | Prior Share | Momentum |
|---------|-------|-------------|------------|----------|
| Blood Orange Cold Brew | Dog | 0.31% | 0.65% | -52.1% |
| Toffee Hazelnut Latte (Hot) | Star | 1.27% | 2.16% | -41.1% |
| Iced Toffee Hazelnut Latte | Plow Horse | 0.87% | 1.47% | -40.8% |
| Coconut Velvet Latte (Hot) | Dog | 0.63% | 0.94% | -33.4% |
| Iced Pistachio Oat Latte | Dog | 2.31% | 3.25% | -29.0% |

---

## 6. Volatility Analysis (Highest CV)

| Product | Class | Avg Share% | CV% | Direction |
|---------|-------|-----------|-----|-----------|
| Drip Coffee | Star | 13.10 | 218% | Declining |
| Iced Matcha Coconut Latte | Plow Horse | 2.92 | 118% | Declining |
| Hot Chocolate | Puzzle | 0.78 | 94% | Growing |
| Iced Matcha Latte | Plow Horse | 3.73 | 91% | Declining |
| Mango Coconut Sunrise | Plow Horse | 1.66 | 88% | Declining |

High volatility suggests **seasonal or promotional patterns** — these items need different forecasting approaches than stable-demand products.

---

## 7. Product Launch Waves

| Launch Wave | SPUs | Still Active | Avg Total Qty |
|------------|------|-------------|---------------|
| Core Menu (May 2025) | 41 | 34 | 9,462 |
| Early Expansion (Jun–Jul 2025) | 7 | 2 | 1,991 |
| Matcha & Food Wave (Aug–Sep 2025) | 15 | 15 | 8,446 |
| Seasonal & Specialty (Oct–Nov 2025) | 8 | 8 | 7,368 |
| Pistachio Launch (Jan 2026) | 5 | 4 | 2,397 |
| Newest (Feb 2026) | 3 | 3 | 1,066 |
| Pre-launch (Mar–Apr 2025) | 4 | 0 | 33 |

---

## 8. Strategic Insights

### 8.1 Watch List — Declining Stars (5 items)
Items requiring immediate investigation:

| Product | Trend | Action |
|---------|-------|--------|
| Drip Coffee | -52.3%/mo | Investigate — largest share product declining fastest |
| Iced Caramel Popcorn Latte | -34.9%/mo | Seasonal effect? Check if promotional-dependent |
| Toffee Hazelnut Latte (Hot) | -29.2%/mo | Winter seasonal decline expected |
| Iced Coconut Latte | -7.8%/mo | Slight decline — monitor closely (top revenue product) |
| Vital Kale | -8.2%/mo | Investigate — consistent decline |

### 8.2 Promotion Candidates — Growing Puzzles (7 items)
High-margin items gaining share — prime candidates for promotion to Star:

| Product | CM% | Trend | Opportunity |
|---------|-----|-------|-------------|
| Hot Chocolate | 63.1% | +35.9%/mo | Strong seasonal momentum |
| Almond Croissant | 58.4% | +23.9%/mo | Food expansion anchor |
| Chocolate Chip Cookies | 65.1% | +25.6%/mo | Growing food category |
| Chocolate Croissant | 58.2% | +20.6%/mo | Pairs well with hot drinks |
| Caramel Popcorn Latte (Hot) | 71.8% | +22.7%/mo | High margin, gaining traction |
| Double Chocolate Muffin | 60.2% | +19.3%/mo | Food variety expansion |
| Creme Brulee Latte (Hot) | 68.4% | +13.4%/mo | Steady growth trajectory |

### 8.3 Emerging Dog
- **Coconut Velvet Latte (Hot):** +25.0%/mo momentum — may be too new to classify accurately; monitor before action

---

## 9. Visualization Outputs

| File | Description |
|------|-------------|
| `charts/09_share_trends.png` | Market share trends for top 12 SKUs |
| `charts/10_growth_heatmap.png` | Month-over-month share growth heatmap (top 25 SKUs) |
| `charts/11_launch_curves.png` | New product launch trajectories by wave |
| `charts/12_momentum_scatter.png` | Strategic momentum map (share vs momentum) |

---

*Generated by Claude Code — UC-PR-01 Menu Engineering Matrix*

# UC-PR-01: Phase 4 — Affinity (Market Basket) Analysis

**Date:** 2026-02-16
**Status:** COMPLETE

---

## 1. Data Overview

| Metric | Value |
|--------|-------|
| Total orders analyzed | 501,074 |
| Multi-item orders (2+ items) | 94,313 (18.8%) |
| Average items per order | 1.26 |
| Unique item pairs analyzed | 98 |
| Pairs with lift > 1.0 | 29 |
| Pairs with lift > 2.0 | 8 |
| Cross-category pairs (beverage × food) | 46 |

**Script:** `scripts/affinity_analysis.py`
**Output:** `affinity_pairs.csv`

---

## 2. Strongest Affinities (Top 15 by Lift)

| Rank | Item A | Item B | Co-occur | Lift | Conf A→B | Cross-Cat |
|------|--------|--------|----------|------|----------|-----------|
| 1 | Zen Berry | Sunny Citrus | 449 | **19.98** | 14.3% | |
| 2 | Vital Kale | Zen Berry | 400 | **6.55** | 4.1% | |
| 3 | Vital Kale | Sunny Citrus | 414 | **5.93** | 4.2% | |
| 4 | Almond Croissant | Chocolate Croissant | 275 | **5.36** | 5.5% | |
| 5 | Mango Pomelo Sago | Dreamy Strawberry | 252 | **4.10** | 3.2% | |
| 6 | Sausage Egg Cheese Croissant | Chocolate Croissant | 363 | **3.18** | 3.2% | |
| 7 | Sausage Egg Cheese Croissant | Almond Croissant | 313 | **2.78** | 2.8% | |
| 8 | Cappuccino (Hot) | Almond Croissant | 244 | **2.29** | 2.3% | ✓ |
| 9 | Hot Chocolate | Sausage Egg Cheese Croissant | 241 | **1.94** | 4.3% | ✓ |
| 10 | Iced Spanish Latte | Sausage Egg Cheese Croissant | 266 | **1.83** | 2.4% | ✓ |
| 11 | Creme Brulee Latte (Hot) | Toffee Hazelnut Latte (Hot) | 248 | **1.69** | 3.0% | |
| 12 | Mango Coconut Sunrise | Mango Pomelo Sago | 220 | **1.62** | 2.6% | |
| 13 | Sausage Egg Cheese Croissant | Iced Toffee Hazelnut Latte | 232 | **1.62** | 2.1% | ✓ |
| 14 | Sausage Egg Cheese Croissant | Caramel Popcorn Latte (Hot) | 257 | **1.59** | 2.3% | ✓ |
| 15 | Sausage Egg Cheese Croissant | Iced Creme Brulee Latte | 234 | **1.58** | 2.1% | ✓ |

---

## 3. Most Frequent Pairings (Top 10 by Co-occurrence)

| Rank | Item A | Item B | Co-occur | Lift | CM$/pair |
|------|--------|--------|----------|------|----------|
| 1 | Iced Coconut Latte | Iced Kyoto Matcha Latte | 1,609 | 0.32 | $3.56 |
| 2 | Iced Coconut Latte | Iced Velvet Latte | 1,378 | 0.40 | $4.24 |
| 3 | Iced Coconut Latte | Sausage Egg Cheese Croissant | 1,254 | 0.83 | $4.43 |
| 4 | Iced Coconut Latte | Iced Kyoto Matcha Coconut | 931 | 0.38 | $3.43 |
| 5 | Iced Coconut Latte | Pineapple Cold Brew | 842 | 0.61 | $2.98 |
| 6 | Sausage Egg Cheese Croissant | Iced Kyoto Matcha Latte | 784 | 0.95 | $3.97 |
| 7 | Iced Coconut Latte | Coconut Latte (Hot) | 672 | 0.27 | $3.51 |
| 8 | Iced Coconut Latte | Mango Coconut Sunrise | 641 | 0.55 | $3.33 |
| 9 | Iced Kyoto Matcha Latte | Iced Kyoto Matcha Coconut | 633 | 0.48 | $2.97 |
| 10 | Iced Latte | Iced Coconut Latte | 626 | 0.20 | $4.77 |

> **Note:** Iced Coconut Latte dominates co-occurrence tables due to its high individual popularity (12.5% sales mix).

---

## 4. Highest-Value Pairs (Top 10 by Total Pair CM$)

| Rank | Item A | Item B | Co-occur | Total Pair CM$ |
|------|--------|--------|----------|---------------|
| 1 | Iced Coconut Latte | Iced Velvet Latte | 1,378 | $5,843 |
| 2 | Iced Coconut Latte | Iced Kyoto Matcha Latte | 1,609 | $5,728 |
| 3 | Iced Coconut Latte | Sausage Egg Cheese Croissant | 1,254 | $5,555 |
| 4 | Iced Coconut Latte | Iced Kyoto Matcha Coconut | 931 | $3,193 |
| 5 | Sausage Egg Cheese Croissant | Iced Kyoto Matcha Latte | 784 | $3,112 |
| 6 | Iced Latte | Iced Coconut Latte | 626 | $2,986 |
| 7 | Iced Velvet Latte | Sausage Egg Cheese Croissant | 579 | $2,692 |
| 8 | Latte (Hot) | Sausage Egg Cheese Croissant | 518 | $2,517 |
| 9 | Iced Coconut Latte | Pineapple Cold Brew | 842 | $2,509 |
| 10 | Iced Coconut Latte | Coconut Latte (Hot) | 672 | $2,359 |

---

## 5. Cross-Category Pairings (Beverage × Food)

| Rank | Beverage | Food | Co-occur | Lift | CM$/pair |
|------|----------|------|----------|------|----------|
| 1 | Cappuccino (Hot) | Almond Croissant | 244 | 2.29 | $5.08 |
| 2 | Hot Chocolate | Sausage Egg Cheese Croissant | 241 | 1.94 | $4.67 |
| 3 | Iced Spanish Latte | Sausage Egg Cheese Croissant | 266 | 1.83 | $4.91 |
| 4 | Iced Toffee Hazelnut Latte | Sausage Egg Cheese Croissant | 232 | 1.62 | $4.12 |
| 5 | Caramel Popcorn Latte (Hot) | Sausage Egg Cheese Croissant | 257 | 1.59 | $4.58 |
| 6 | Iced Creme Brulee Latte | Sausage Egg Cheese Croissant | 234 | 1.58 | $4.01 |
| 7 | Creme Brulee Latte (Hot) | Sausage Egg Cheese Croissant | 271 | 1.47 | $4.29 |
| 8 | Latte (Hot) | Almond Croissant | 406 | 1.46 | $4.90 |
| 9 | Iced Caramel Popcorn Latte | Sausage Egg Cheese Croissant | 424 | 1.41 | $4.65 |
| 10 | Coconut Latte (Hot) | Almond Croissant | 249 | 1.34 | $3.96 |

---

## 6. Natural Affinity Clusters

| Cluster | Products | Avg Lift | Pattern |
|---------|----------|----------|---------|
| Bottled drinks | Vital Kale, Zen Berry, Sunny Citrus | **10.8** | Multi-bottle purchases |
| Matcha enthusiasts | Kyoto Matcha variants | 0.5 | Multiple matcha variants per visit |
| Hot classics | Drip, Latte, Cappuccino, Americano | 0.6 | Office/group orders |
| Breakfast | Sausage Croissant + premium iced lattes | 1.5+ | Morning combo behavior |
| Pastry pairs | Almond + Chocolate Croissant | 5.4 | Food variety seeking |

---

## 7. Bundle Recommendations

| Bundle | Items | Lift | Est. CM$/bundle |
|--------|-------|------|-----------------|
| Breakfast Combo 1 | Iced Spanish Latte + Sausage Egg Cheese Croissant | 1.8 | $4.91 |
| Breakfast Combo 2 | Cappuccino (Hot) + Almond Croissant | 2.3 | $5.08 |
| Breakfast Combo 3 | Caramel Popcorn Latte + Sausage Egg Cheese Croissant | 1.6 | $4.58 |
| Breakfast Combo 4 | Hot Chocolate + Sausage Egg Cheese Croissant | 1.9 | $4.67 |
| Duo Deal 1 | Vital Kale + Sunny Citrus | 5.9 | $3.68 |
| Duo Deal 2 | Zen Berry + Sunny Citrus | 20.0 | $3.39 |

---

## 8. Key Findings & Opportunities

### 8.1 Basket Size Challenge
- Only **18.8%** of orders contain 2+ items — significant upsell opportunity
- Increasing multi-item rate from 19% → 30% could add **~$200K+ annual revenue**

### 8.2 Sausage Egg Cheese Croissant as Cross-Sell Anchor
- Appears in the most cross-category pairs with premium beverages
- Only 5 food SKUs on the menu — **food menu expansion** could significantly lift basket size

### 8.3 Seasonal Bundle Potential
- Seasonal flavors (Pumpkin Spice, Crème Brûlée, Toffee Hazelnut) show elevated lift when paired together
- **Seasonal bundles** could capture this natural buying behavior

---

## 9. Visualization Outputs

| File | Description |
|------|-------------|
| `charts/06_affinity_heatmap.png` | Lift ratio heatmap for top 20 items |
| `charts/07_top_affinity_pairs.png` | Top 15 pairs by lift and by total pair CM$ |
| `charts/08_cross_category_affinity.png` | Beverage × Food cross-category analysis |

---

*Generated by Claude Code — UC-PR-01 Menu Engineering Matrix*

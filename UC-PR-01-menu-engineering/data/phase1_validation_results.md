# UC-PR-01: Phase 1.5 Validation Results

**Date**: 2026-02-16
**Status**: COMPLETE

---

## 1. formula_json Completeness

- **Total rows in t_commodity**: 656,229
- **Rows with non-null formula_json**: 656,229 (100%)
- **Min ingredients per record**: 1
- **Max ingredients per record**: 12
- **Database**: opproduction (`aws-luckyus-opproduction-rw`), schema `luckyus_opproduction`
- **Note**: No `is_deleted` column exists in t_commodity — all rows are active

## 2. CRITICAL FINDING: `cost` Field = QUANTITY, Not Monetary Cost

The `cost` field in `formula_json` represents **ingredient quantities in their respective units**, NOT monetary cost values.

### Evidence

| Product | Ingredient | goodsCode | cost value | unitMid | Interpretation |
|---------|-----------|-----------|------------|---------|---------------|
| Iced Latte | Medium Roast Espresso | GS07465 | 14 | QU005 (grams) | 14g = standard double-shot espresso |
| Iced Latte | Tuscan Whole Milk | GS07566 | 637.5 | QU013 (ml) | 637.5ml for 16oz iced drink |
| Drip Coffee | Drip Coffee Blend | GS07470 | 20 | QU005 (grams) | 20g = standard drip coffee dose |
| All drinks | Straw | GS07437 | 1 | QU009 (pieces) | 1 piece per drink |
| All drinks | Cup | GS07441/51 | 1 | QU009 (pieces) | 1 piece per drink |
| All drinks | Lid | GS07443/44/48 | 1 | QU009 (pieces) | 1 piece per drink |
| Matcha Latte | Matcha Sweet Blend | GS07509 | 33.7 | QU005 (grams) | 33.7g matcha mix |
| Matcha Latte | Cane Sugar Syrup | GS07494 | 7.5 | QU013 (ml) | 7.5ml syrup |

### Unit Code Reference

| unitMid | Unit | Typical Use |
|---------|------|-------------|
| QU005 | grams | Coffee beans, powders, matcha |
| QU009 | pieces/each | Packaging (cups, lids, straws) |
| QU013 | milliliters | Milk, syrups, liquid ingredients |
| QU012 | equipment unit | Equipment items |
| QU042 | equipment | Equipment items |

### Impact on Plan

- **Path A (direct cost extraction from formula_json): INVALIDATED** — cost values are quantities, not monetary
- **Path B (quantity × procurement unit cost): NO PROCUREMENT DATA FOUND** — searched all 4 databases
- **Path C (industry COGS ratios) or HYBRID approach: NOW PRIMARY PATH**

## 3. No Procurement/Pricing Data Found

Exhaustive search across 4 databases confirmed NO purchase/procurement unit pricing exists:

| Table | Database | Finding |
|-------|----------|---------|
| t_commodity_sale_info_item | scmcommodity | SALE PRICE table (customer-facing), not procurement costs |
| t_formula_average | scmcommodity | Average usage/quantity table, NO cost columns |
| t_formula_spu | scmcommodity | Recipe/BOM quantities only, NO cost columns |
| t_mdm_goods | pubdm | Material master data (name, class), NO cost columns |

## 4. Revenue Model Fields Validated

### t_order_item (salesorder) — 48 columns

| Column | Type | Meaning | Sample Values |
|--------|------|---------|---------------|
| origin_price | decimal | Menu/list price | $5.77 - $6.76 |
| sale_price | decimal | Sale price after base adjustments | Similar to origin_price |
| payable_money | decimal | Amount due before payment | Varies |
| pay_money | decimal | Actual amount paid | $3.09 - $3.42 avg |
| refund_money | decimal | Refund amount | 0 for most |
| voucher_share_money | decimal | Coffee voucher allocation | Discount component |
| coupon_share_money | decimal | Coupon allocation | Discount component |
| gift_flag | tinyint | 0=paid, 1=gift | Filter out gifts |
| tax_rate | decimal | Tax rate | 0.08875 (NYC 8.875%) |
| delete_flag | tinyint | 0=active, 1=deleted | Use delete_flag, NOT is_deleted |
| spu_type | tinyint | 1=product, 2=combo | Filter spu_type=1 for products |

### Key Pricing Observations

| SPU | Product | Avg Origin Price | Avg Pay Price | Discount Depth | Orders |
|-----|---------|-----------------|---------------|----------------|--------|
| PR000021 | Iced Coconut Latte | $6.47 | $3.29 | ~49% | 70,385 |
| PR000015 | Iced Latte | $5.77 | $3.42 | ~41% | 28,439 |
| PR000043 | Pink Sunrise | $6.25 | $3.09 | ~51% | 8,412 |
| PR000027 | Iced Matcha Latte | $6.45 | $3.12 | ~52% | 6,941 |
| PR000074 | Kyoto Matcha Coconut Latte | $6.76 | $3.42 | ~49% | 6,350 |

**Finding**: Heavy discounting across the board — average discount depth ~50% for all products.

### t_order (salesorder) — 46 columns

| Column | Meaning | Filter Values |
|--------|---------|--------------|
| shop_id / shop_name / shop_number | Store identification | Join for per-store analysis |
| create_time / pay_time / finish_time | Order timestamps | For time-series analysis |
| status | Order status | 20 = paid/completed |
| display_flag | Visibility | 3 = normal/active |
| channel | Order channel | App pickup vs delivery |

## 5. Ingredient Mapping (Confirmed)

### Coffee Beans (SC0006/TC0040, QU005/grams)
| goodsCode | Name |
|-----------|------|
| GS07465 | Medium Roast Espresso |
| GS07466 | Dark Roast Espresso |
| GS07467 | Single Origin |
| GS07468 | Decaf |
| GS07470 | Drip Coffee Blend |

### Milk/Dairy (QU013/ml)
| goodsCode | Name |
|-----------|------|
| GS07506 | Barista Coconut Milk |
| GS07566 | Tuscan Whole Milk |
| GS07571 | Tuscan 2% Reduced Fat Milk |
| GS07786 | Cream-O-Land Whole Milk |
| GS06091 | SGP Skimmed Milk |

### Syrups (SC0006/TC0043, QU013/ml)
| goodsCode | Name |
|-----------|------|
| GS07494 | DVG PL Cane Sugar Syrup |
| GS07495 | DVG PL Vanilla Syrup |
| GS01474 | Original Flavor Syrup |

### Matcha/Tea (SC0006)
| goodsCode | Name | Unit |
|-----------|------|------|
| GS07505 | Jasmine Tea Powder | QU005/grams |
| GS07509 | Matcha Sweet Blend | QU005/grams |
| PFM000005 | Matcha powder | QU005/grams (PFM prefix — not in t_mdm_goods) |

### Packaging (SC0004/TC0099, QU009/pieces)
| goodsCode | Name |
|-----------|------|
| GS07437 | Straw |
| GS07441 | 16oz Hot Cup |
| GS07443 | 16oz Hot Cup Lid |
| GS07444 | 16oz Iced Cup Dome Lid |
| GS07448 | 16oz Iced Cup Sipper Lid |
| GS07451 | 16oz Iced Cup |

## 6. Cross-Database Join Paths (Confirmed)

```
t_order_item.spu_code ──────────► t_commodity_base_info.spu_code (product metadata)
t_order_item.spu_code ──────────► t_formula_spu.spu_code (BOM/recipe quantities)
t_order_item.id ────────────────► t_commodity.order_commodity_id (production + ingredient data)
t_order_item.order_id ──────────► t_order.order_id (order header: store, time, channel)
formula_json[].goodsCode ──────► t_mdm_goods.mid (material master name/class)
```

## 7. JSON Parsing Notes

- `JSON_TABLE` syntax fails on this MySQL version — use `JSON_EXTRACT` with index-based access
- Pattern: `JSON_EXTRACT(formula_json, '$[0].cost')` through `$[11].cost` (max 12 ingredients)
- Must cast: `CAST(JSON_EXTRACT(...) AS DECIMAL(10,2))`

---

## Decisions Required (for David)

1. **Cost Unit Confirmation**: The `cost` field is quantity, not monetary. No procurement pricing exists in the databases. Should we:
   - Use **hybrid approach**: formula_json quantities × estimated US market unit prices? (Recommended)
   - Use **Path C**: Industry-standard COGS ratios (25-35% beverages, 40-50% food)?
   - Does the team have an **external cost/procurement spreadsheet** we should incorporate?

2. **Non-ingredient cost components**: What packaging, payment processing, and delivery commission rates to include?

---

*Generated by Claude Code — UC-PR-01 Menu Engineering Matrix*

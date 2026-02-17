# Luckin Coffee USA - Database Infrastructure & AI Transformation Report

**Report:** Data Landscape Map
**Date:** February 13, 2026
**Prepared for:** Luckin Coffee USA Leadership Team

---

## 2. Data Landscape Map

### 2.1 Database Server Inventory

#### MySQL Servers (62 Total) — Key Business Databases

| Server | Database | Primary Tables | Row Count | Purpose |
|--------|----------|---------------|-----------|---------|
| `aws-luckyus-salesorder-rw` | `luckyus_sales_order` | t_order (516K), t_order_item (602K), t_order_amount (484K), t_order_oper_history (2.5M) | ~5M+ | **Order Management** — all customer orders, items, pricing, tax breakdowns |
| `aws-luckyus-salespayment-rw` | `luckyus_sales_payment` | t_trade (518K), t_channel_fee (502K), t_user_channel (157K), t_user (10K) | ~1.2M | **Payment Processing** — Stripe transactions, fees, channel management |
| `aws-luckyus-opshop-rw` | `luckyus_opshop` | t_shop_info (517), t_shop_opening_time (135K) | ~136K | **Store Management** — locations, hours, GPS coordinates, operating modes |
| `aws-luckyus-scmcommodity-rw` | `luckyus_scm_commodity` | t_commodity_base_info (141), t_formula_spu (32K), t_mdm_goods (1448) | ~35K | **Product Catalog** — drinks, food, formulas, nutrition/allergen data |
| `aws-luckyus-salescrm-rw` | `luckyus_sales_crm` | t_user (275K), t_user_profile (193K), t_user_history (498K) | ~970K | **CRM** — user profiles, registration, behavior history |
| `aws-luckyus-isalescdp-rw` | `luckyus_isales_cdp` | t_realtime_user_group_log (2.3M), t_user_state (980K), t_user_event_track (168K) | ~3.5M | **Customer Data Platform** — real-time segmentation, behavioral states |
| `aws-luckyus-salesmarketing-rw` | `luckyus_sales_marketing` | t_coupon_record_expired (37M), t_coupon_record (2.6M), t_user_group_label (3.9M) | ~44M | **Marketing Engine** — coupons, campaigns, user targeting |
| `aws-luckyus-ifiaccounting-rw` | `luckyus_ifiaccounting` | t_acc_income_bill (136K), t_pre_voucher_entry_assist (179K), t_acc_cost_bill (5649) | ~320K | **Accounting** — income bills, vouchers, cost tracking |
| `aws-luckyus-scm-shopstock-rw` | `luckyus_scm_shopstock` | t_shop_goods_stock (150K), stock_change_mon-sun (1M+ each) | ~8M+ | **Inventory** — real-time stock levels, daily consumption tracking |
| `aws-luckyus-opproduction-rw` | `luckyus_opproduction` | t_production (502K), t_commodity (567K), t_print_receipt (2M) | ~3M | **Production** — drink/food preparation tracking, accept→done timing |
| `aws-luckyus-iotplatform-rw` | `luckyus_iot_platform` | t_cup_order_info (587K), t_device (216), t_coffee_formula (217) | ~590K | **IoT Platform** — machine telemetry, cup tracking, formula management |
| `aws-luckyus-ireplenishment-rw` | `luckyus_ireplenishment` | wh_goods_daily_demand_pred (2.5M), t_order_predict_alg_v2 (124K) | ~2.6M | **AI Demand Forecasting** — ML-based demand prediction per shop/SKU |
| `aws-luckyus-isalesdatamarketing-rw` | `luckyus_isalesdatamarketing` | t_user_hit_experiment_record (6.4M), t_user_traffic_distribution (2.3M) | ~8.7M | **A/B Testing** — experiment assignment, traffic splitting |
| `aws-luckyus-scm-purchase-rw` | `luckyus_scm_purchase` | t_ship_order (1670), t_purchase_order (694), t_supplier_settlement (1363) | ~4K | **Procurement** — purchase orders, shipping, supplier settlements |
| `aws-luckyus-fitax-rw` | `luckyus_fi_tax` | All tables | **0 rows** | **Tax (NOT IMPLEMENTED)** — schema exists but completely empty |
| `aws-luckyus-isalesmembermarketing-rw` | `luckyus_isalesmembermarketing` | All tables | **~0 rows** | **Loyalty Program (NOT LAUNCHED)** — schema ready, no data |
| `aws-luckyus-iunifiedreconcile-rw` | `luckyus_iunifiedreconcile` | Reconciliation config tables | ~small | **Financial Reconciliation** — rule definitions |
| `aws-luckyus-opshopsale-rw` | `luckyus_opshopsale` | t_shop_sale_remark (820K) | ~820K | **Sale Configuration** — remarks, display rules |

#### PostgreSQL Servers (3 Total)

| Server | Database | Purpose |
|--------|----------|---------|
| `aws-luckyus-dify-rw` | `luckyus_dify_api` | Dify AI assistant platform (chatbot/LLM infrastructure) |
| `aws-luckyus-difynew-rw` | (new Dify instance) | Updated Dify AI platform |
| `aws-luckyus-pgilkmap-rw` | `luckyus_ilkmap` | Lucky Map / geolocation services |

#### Redis Instances (78 Total) — Key Clusters

| Instance | Purpose |
|----------|---------|
| `luckyus-isales-order` | Order session caching (41 active keys with TTL) |
| `luckyus-isales-crm` | CRM data caching |
| `luckyus-isales-market` | Marketing campaign state |
| `luckyus-production` | Production queue management |
| `luckyus-iotplatform` | IoT real-time device state |
| `luckyus-session` | User session management |
| `luckyus-auth` / `luckyus-authservice` | Authentication tokens |
| `luckyus-redis-dify` | AI assistant caching |
| `luckyus-scm-shopstock` | Inventory cache |
| `luckyus-apigateway` | API rate limiting & routing |

### 2.2 Store Network

| # | Store Name | Address | Opened | Orders | Revenue | AOV |
|---|-----------|---------|--------|--------|---------|-----|
| 1 | 8th & Broadway | 755 Broadway, NY 10003 | 2025-06-30 | 137,638 | $612,844 | $4.45 |
| 2 | 28th & 6th | 800 6th Ave, NY 10001 | 2025-06-30 | 92,226 | $438,277 | $4.75 |
| 3 | 54th & 8th | 901 8th Ave, NY 10019 | 2025-08-24 | 56,303 | $292,664 | $5.20 |
| 4 | 102 Fulton | 102 Fulton St, NY 10038 | 2025-08-28 | 61,636 | $298,627 | $4.85 |
| 5 | 100 Maiden Ln | 100 Maiden Ln, NY 10038 | 2025-09-09 | 35,449 | $168,070 | $4.74 |
| 6 | 37th & Broadway | 1375 Broadway, NY 10018 | 2025-11-20 | 26,841 | $124,688 | $4.65 |
| 7 | 33rd & 10th | 410 10th Ave, NY 10001 | 2025-12-01 | 16,058 | $76,063 | $4.74 |
| 8 | 15th & 3rd | 147 3rd Ave, NY 10003 | 2025-12-14 | 10,057 | $47,607 | $4.73 |
| 9 | 221 Grand | 221 Grand St, NY 10013 | 2025-12-15 | 23,805 | $117,403 | $4.93 |
| 10 | 21st & 3rd | 261 3rd Ave, NY 10010 | 2026-02-06 | 1,887 | $8,518 | $4.51 |
| — | 180 Varick | 180 Varick St, NY 10014 | Not opened | — | — | — |

### 2.3 Top 15 Products by Order Volume

| Rank | Product | Category | Orders | Revenue | Avg Price |
|------|---------|----------|--------|---------|-----------|
| 1 | Iced Coconut Latte | Fresh Ground Coffee | 70,162 | $226,090 | $3.22 |
| 2 | Iced Kyoto Matcha Latte | Matcha | 37,246 | $125,785 | $3.38 |
| 3 | Drip Coffee | Classic Drinks | 34,420 | $84,593 | $2.46 |
| 4 | Latte | Classic Drinks | 30,802 | $99,886 | $3.24 |
| 5 | Iced Latte | Classic Drinks | 27,934 | $94,922 | $3.40 |
| 6 | Iced Velvet Latte | Fresh Ground Coffee | 25,598 | $89,126 | $3.48 |
| 7 | Sausage Egg & Cheese Croissant | Food | 25,415 | $97,681 | $3.84 |
| 8 | Cold Brew | Cold Brew | 21,516 | $65,903 | $3.06 |
| 9 | Coconut Latte | Fresh Ground Coffee | 18,606 | $60,702 | $3.26 |
| 10 | Iced Kyoto Matcha Coconut Latte | Fresh Ground Coffee | 18,219 | $63,099 | $3.46 |
| 11 | Kyoto Matcha Latte | Matcha | 14,743 | $48,631 | $3.30 |
| 12 | Iced Caramel Popcorn Latte | Fresh Ground Coffee | 13,666 | $49,298 | $3.61 |
| 13 | Iced Americano | Classic Drinks | 12,928 | $43,274 | $3.35 |
| 14 | Cappuccino | Classic Drinks | 11,261 | $37,196 | $3.30 |
| 15 | Americano | Classic Drinks | 10,775 | $30,196 | $2.80 |

### 2.4 Data Quality Issues Identified

| Issue | Severity | Database | Details |
|-------|----------|----------|---------|
| Tax tables completely empty | **CRITICAL** | `luckyus_fi_tax` | Zero rows in all tax invoice tables — US sales tax compliance gap |
| Geographic fields NULL | HIGH | `luckyus_opshop` | country_name, administrative_area_name, locality_name all NULL despite addresses populated |
| NZD test orders mixed in | MEDIUM | `luckyus_sales_order` | 21,245 NZD-denominated orders from Cook Islands test stores mixed with production data |
| Loyalty tables empty | MEDIUM | `luckyus_isalesmembermarketing` | Member marketing schema exists but program not launched |
| Delivery addresses missing | MEDIUM | `luckyus_sales_order` | No delivery address storage found despite ~5% delivery orders |
| Production time outliers | LOW | `luckyus_opproduction` | Max production time 9,839 seconds (2.7 hours) — data quality issue |
| Duplicate commodity records | LOW | `luckyus_scm_commodity` | Same spu_code appearing with status 4 and 5 (online/offline versions) |

### 2.5 Entity Relationship Summary

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│   t_user     │────▶│   t_order     │────▶│ t_order_item │
│  (CRM 275K)  │     │  (516K)       │     │   (602K)     │
└──────┬───────┘     └──────┬───────┘     └──────────────┘
       │                    │
       │              ┌─────┴──────┐
       │              │            │
       ▼              ▼            ▼
┌──────────────┐ ┌──────────┐ ┌──────────────┐
│ t_user_state │ │ t_trade  │ │t_order_amount│
│  (CDP 980K)  │ │ (518K)   │ │   (484K)     │
└──────┬───────┘ └──────────┘ └──────────────┘
       │              │
       ▼              ▼
┌──────────────┐ ┌──────────────┐     ┌──────────────┐
│t_coupon_rec  │ │t_channel_fee │     │ t_production  │
│   (2.6M)     │ │   (502K)     │     │   (502K)     │
└──────────────┘ └──────────────┘     └──────┬───────┘
                                             │
                                             ▼
                                      ┌──────────────┐
                                      │t_cup_order   │
                                      │  (IoT 587K)  │
                                      └──────────────┘
```

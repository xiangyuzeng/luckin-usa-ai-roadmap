# Luckin Coffee USA: Comprehensive Database Infrastructure Analysis & Technology Transformation Roadmap

**Prepared:** February 14, 2026
**Scope:** All production database systems (MySQL, PostgreSQL, Redis) powering Luckin Coffee USA operations
**Access Level:** READ-ONLY database exploration
**Classification:** Internal — Confidential

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Data Landscape Map](#2-data-landscape-map)
3. [Department Tool Catalog](#3-department-tool-catalog)
   - 3.1 IT / DevOps
   - 3.2 Marketing
   - 3.3 Accounting & Finance
   - 3.4 Product
   - 3.5 Operations
   - 3.6 Supply Chain
4. [Cross-Departmental AI Transformation Tools](#4-cross-departmental-ai-transformation-tools)
5. [Implementation Roadmap](#5-implementation-roadmap)
6. [Technology Architecture Recommendations](#6-technology-architecture-recommendations)
7. [Appendix](#7-appendix)

---

## 1. Executive Summary

### Business Context

Luckin Coffee USA operates **10 active stores across Manhattan, NYC** (with 1 newest store opened Feb 6, 2026) serving customers through a **mobile-app-only ordering model** (iOS ~80%, Android ~14%, delivery platforms ~5%). Since launching in June 2025, the operation has processed **466,252 completed USD orders** generating **$2.19M in tracked revenue** with an average order value of **$4.71**.

### Infrastructure Overview

The technology stack is a **multi-tenant microservices architecture on AWS** comprising:

| Component | Count | Purpose |
|-----------|-------|---------|
| MySQL Servers | 62 | Core transactional & business data |
| Redis Instances | 78 | Caching, sessions, real-time state |
| PostgreSQL Servers | 3 | AI platform (Dify), mapping |

### Key Findings

**Strengths:**
- Mature, well-structured microservices architecture inherited from Luckin China's proven platform
- AI-powered demand forecasting already operational (2.5M prediction records in `ireplenishment`)
- Sophisticated A/B testing infrastructure (6.4M experiment records in `isalesdatamarketing`)
- Comprehensive CDP (Customer Data Platform) with real-time behavioral tracking (980K user states)
- IoT integration for all 216 coffee machines (Schaerer) with real-time monitoring
- Full payment processing audit trail through Stripe with fee tracking

**Critical Gaps:**
- **Tax system (`fi_tax`) is completely empty** — all invoice tables have 0 rows; US tax compliance risk
- **Loyalty/member program (`isalesmembermarketing`) not launched** — tables exist but empty
- **Delivery address data empty** — despite ~5% delivery orders, no address storage found
- **No centralized analytics/BI layer** — data scattered across 62 MySQL servers with no warehouse
- **Geographic data fields unpopulated** — `country_name`, `administrative_area_name`, etc. are NULL across stores

**Critical Business Metrics Discovered:**

| Metric | Value |
|--------|-------|
| Total USD Revenue | $2,194,799 |
| Average Order Value (USD) | $4.71 |
| Completed Orders (USD) | 466,252 |
| Registered Users | 277,537 |
| Active Products | ~80+ drinks + food items |
| #1 Product | Iced Coconut Latte (70,162 orders) |
| Avg Production Time | 217.9 seconds (~3.6 min) |
| Weekday Peak Orders | ~3,700/day |
| Weekend Orders | ~1,400-1,700/day |
| Active Coupons | 2.4M records from 1,262 templates |
| Stores (Active) | 10 Manhattan locations |
| IoT Devices | 216 machines |

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

---

## 3. Department Tool Catalog

### 3.1 IT / DevOps Department

#### Tool 1: Database Health Monitor Dashboard

**Problem Statement:** With 62 MySQL servers, 78 Redis instances, and 3 PostgreSQL servers, IT has no unified view of database health, query performance, or capacity trends. Identifying which of 140+ database instances is experiencing issues requires manually checking each one.

**Data Sources:**
- `information_schema.TABLES` across all 62 MySQL servers (table sizes, row counts, auto_increment values)
- `information_schema.PROCESSLIST` (active queries, connection counts)
- Redis `INFO` commands across 78 instances (memory usage, keyspace, hit rates)
- PostgreSQL `pg_stat_activity` on 3 servers
- CloudWatch metrics (CPU, IOPS, connections)

**Technical Approach:**
- Scheduled collector service (Python/Go) polling all database instances every 60 seconds
- Store metrics in a time-series database (Amazon Timestream or InfluxDB)
- Grafana dashboards with pre-built panels per server type
- Alert rules for: table growth >20% week-over-week, connection count >80% capacity, Redis memory >85%, slow query count >threshold
- Auto-discovery of new tables/databases

**UI Description:**
Three-tier dashboard: (1) Fleet overview heatmap showing all 143 instances color-coded by health, (2) Server detail view with key metrics trends, (3) Alert timeline. Non-technical users see traffic-light status; engineers drill into query-level detail.

**Business Impact:**
- Reduce MTTR (mean time to resolution) for database issues from hours to minutes
- Prevent outages from silent failures (e.g., table growth causing disk full)
- Capacity planning with 30/60/90-day projections

**Complexity:** Medium-High
**Estimated Monthly Cost:** $800-1,200 (Timestream: ~$200, Grafana Cloud: ~$300, collector compute: ~$150, alerting: ~$150)

---

#### Tool 2: Multi-Tenant Data Isolation Auditor

**Problem Statement:** Every table uses a `tenant` field for multi-tenancy. Data leakage between tenants (e.g., NZD test data mixed with USD production data, as discovered during this analysis) could cause financial reporting errors or compliance issues.

**Data Sources:**
- All MySQL databases — sampling `tenant` values across core tables
- `luckyus_sales_order.t_order` — 21,245 NZD records mixed with 466,252 USD records
- Cross-referencing tenant values against `luckyus_opshop.t_shop_info`

**Technical Approach:**
- Automated weekly audit scanning all core tables for tenant distribution
- Cross-validation: every `tenant` value must map to a known configuration
- Currency mismatch detection: flag orders where `currency_code` doesn't match the store's expected currency
- Report showing potential data contamination points

**UI Description:**
Weekly email report with pass/fail checklist per database. Red flags for any unexpected tenant values or currency mismatches. Drill-down link to affected records.

**Business Impact:**
- Ensure financial reports exclude test data (currently NZD orders inflate counts by ~4.4%)
- Compliance readiness for multi-market operations
- Early detection of configuration errors

**Complexity:** Medium
**Estimated Monthly Cost:** $200-400 (Lambda: ~$50, SNS alerts: ~$10, S3 report storage: ~$10, engineering maintenance: ~$200)

---

#### Tool 3: Redis Cluster Intelligence Console

**Problem Statement:** 78 Redis instances serve different microservices but there's no centralized visibility into memory utilization patterns, key TTL policies, or which instances are over/under-provisioned.

**Data Sources:**
- Redis `INFO` across all 78 instances (memory, keyspace, connections, hit/miss ratios)
- Redis `DBSIZE` and key sampling
- Instance configuration metadata

**Technical Approach:**
- Redis Sentinel/cluster monitoring agent deployed per instance
- Memory utilization trend tracking with anomaly detection
- Key namespace analysis (categorize keys by service domain)
- TTL compliance checking — identify keys without TTL that should expire
- Hot-key detection to prevent thundering herd issues

**UI Description:**
Dashboard with 78-instance overview grid, sorted by memory utilization. Click any instance to see: memory breakdown by key prefix, hit/miss ratio trend, connection count, TTL distribution histogram. Alerting panel for instances exceeding 85% memory.

**Business Impact:**
- Right-size Redis instances (potential 20-30% cost savings on over-provisioned instances)
- Prevent cache-related outages during peak hours
- Identify unused Redis instances for decommissioning

**Complexity:** Medium
**Estimated Monthly Cost:** $400-600 (monitoring agent compute: ~$200, Grafana: included, alerting: ~$50, S3: ~$20)

---

### 3.2 Marketing Department

#### Tool 4: Customer 360 Intelligence Platform

**Problem Statement:** Marketing data is fragmented across CRM (275K users), CDP (980K behavioral states), coupon records (2.4M active), and A/B testing (6.4M experiment records). Marketers cannot get a unified view of any individual customer's journey, preferences, and responsiveness to campaigns.

**Data Sources:**
- `luckyus_sales_crm.t_user` (275K users) — registration, origin, phone
- `luckyus_sales_crm.t_user_profile` (193K) — demographics
- `luckyus_sales_crm.t_user_history` (498K) — engagement timeline
- `luckyus_isales_cdp.t_user_state` (980K) — real-time behavioral segments
- `luckyus_isales_cdp.t_realtime_user_group_log` (2.3M) — segment transitions
- `luckyus_sales_marketing.t_coupon_record` (2.6M) — coupon usage
- `luckyus_sales_marketing.t_user_group_label` (3.9M) — user tags
- `luckyus_sales_order.t_order` (516K) — purchase history

**Technical Approach:**
- ETL pipeline aggregating user data from 4 databases into a unified customer profile in a read-replica or analytics DB
- Customer scoring model: RFM (Recency, Frequency, Monetary) computed from order history
- Cohort analysis engine: segment users by registration month, first purchase, preferred store, preferred product
- Churn prediction: flag users whose order frequency is declining vs. their historical pattern
- Integration with CDP's existing behavioral states for real-time segment membership

**UI Description:**
Search bar to find any customer (by masked ID). Customer profile card shows: registration date, lifetime value, orders count, favorite store, top 3 products, active coupons, current CDP segment, A/B test exposure history. Cohort comparison charts. Exportable segment lists for campaign targeting.

**Business Impact:**
- Enable personalized marketing at scale (currently 275K users, growing)
- Reduce coupon waste (37M expired coupons suggest over-distribution)
- Increase repeat purchase rate through targeted re-engagement
- Expected 10-15% improvement in coupon redemption rates

**Complexity:** High
**Estimated Monthly Cost:** $1,500-2,500 (Analytics DB: ~$600, ETL compute: ~$300, ML inference: ~$200, UI hosting: ~$200, maintenance: ~$500)

---

#### Tool 5: Campaign Performance Analyzer

**Problem Statement:** The marketing database contains 37M expired coupon records and 2.4M active coupons from 1,262 templates, but there's no easy way to measure which campaigns drive incremental revenue vs. cannibalize full-price sales.

**Data Sources:**
- `luckyus_sales_marketing.t_coupon_record` + `t_coupon_record_expired` — full coupon lifecycle
- `luckyus_sales_marketing.t_market_activity_partake` (514K) — campaign participation
- `luckyus_sales_order.t_order_amount` — coupon_deduct breakdowns per order
- `luckyus_isalesdatamarketing.t_user_hit_experiment_record` (6.4M) — A/B test results

**Technical Approach:**
- Join coupon usage with order amounts to calculate: redemption rate, average discount depth, incremental revenue per campaign
- A/B test result aggregation: compare conversion rates between experiment groups
- Attribution modeling: last-touch coupon attribution to revenue
- Cost-per-acquisition calculation per campaign template
- Automated weekly campaign scorecard

**UI Description:**
Campaign leaderboard ranking all 1,262 coupon templates by ROI (revenue generated / marketing_cost). Drill into any campaign to see: distribution count, redemption rate, average discount, incremental vs. baseline revenue. Time-series chart of daily campaign performance. A/B test result visualization with statistical significance indicators.

**Business Impact:**
- Quantify marketing ROI for each of 1,262 coupon templates
- Identify and sunset low-performing campaigns (saving potentially $10K+/month in wasted discounts)
- Optimize A/B test-driven decisions with clear statistical readouts

**Complexity:** Medium-High
**Estimated Monthly Cost:** $800-1,200 (Analytics compute: ~$300, dashboard hosting: ~$200, data pipeline: ~$200, maintenance: ~$300)

---

#### Tool 6: Customer Acquisition Channel Tracker

**Problem Statement:** Users arrive through different channels (iOS app channel=2 at 80%, Android channel=1 at 14%, delivery platforms channel=3 at 5%) but there's no visibility into which channels have the best customer lifetime value.

**Data Sources:**
- `luckyus_sales_order.t_order` — `channel` field (2=iOS, 1=Android, 3=delivery, 10/8/9=others)
- `luckyus_sales_crm.t_user` — `origin` field for registration source
- `luckyus_sales_payment.t_trade` — `channel_id` for payment method preferences
- `luckyus_isales_cdp.t_user_event_track` (168K) — first-touch events

**Technical Approach:**
- Aggregate per-channel metrics: CAC (cost per acquisition), LTV (lifetime value), retention rate, AOV
- Track channel mix shifts over time
- Cross-reference marketing spend per channel with resulting customer quality
- Funnel analysis: app download → registration → first order → repeat order → loyal customer

**UI Description:**
Channel comparison dashboard with side-by-side metrics for iOS, Android, Delivery, and Other channels. Funnel visualization per channel. Trend lines showing channel mix evolution since launch. Weekly email summary of channel health metrics.

**Business Impact:**
- Optimize app store marketing spend between iOS/Android
- Identify highest-value acquisition channels for expansion
- Track delivery platform dependency and margin impact

**Complexity:** Medium
**Estimated Monthly Cost:** $500-800 (ETL: ~$150, analytics: ~$200, dashboard: ~$150, maintenance: ~$200)

---

### 3.3 Accounting & Finance Department

#### Tool 7: Daily Revenue Reconciliation Dashboard

**Problem Statement:** Revenue data exists in three separate systems — orders (`t_order.pay_money`), payments (`t_trade.amount` in cents), and accounting (`t_acc_income_bill`). Reconciling these daily requires manual cross-referencing across databases with different data formats and currencies (USD vs. NZD contamination).

**Data Sources:**
- `luckyus_sales_order.t_order` — order amounts (decimal, by currency_code)
- `luckyus_sales_payment.t_trade` — payment amounts (cents, by channel_id)
- `luckyus_sales_payment.t_channel_fee` — processing fees (transaction_fee, merchant_service_fee)
- `luckyus_ifiaccounting.t_acc_income_bill` (136K) — booked income
- `luckyus_ifiaccounting.t_acc_cost_bill` (5,649) — cost entries

**Technical Approach:**
- Automated daily reconciliation job comparing: Order revenue (filtered USD-only) vs. Payment totals (converted from cents) vs. Accounting income bills
- Three-way match with tolerance thresholds (flag discrepancies >$0.01)
- Payment channel fee tracking: sum `t_channel_fee.total_fee` per channel per day
- Stripe fee analysis: calculate effective processing rate per channel
- Currency isolation: strictly separate USD and NZD reporting

**UI Description:**
Daily summary showing three columns: Orders Total, Payments Total, Accounting Total — with match/mismatch indicators. Expandable discrepancy list. Payment fee breakdown by channel. Monthly trend of effective Stripe processing rate. Export to CSV for accounting systems.

**Business Impact:**
- Reduce daily reconciliation time from ~2 hours manual work to 5-minute review
- Catch revenue leakage immediately (currently ~$2.27M processed through Stripe)
- Track payment processing costs (~$50K-80K/year in Stripe fees estimated)
- Ensure NZD test data never contaminates USD financial reports

**Complexity:** Medium
**Estimated Monthly Cost:** $600-900 (Lambda functions: ~$100, RDS read replica: ~$200, dashboard: ~$150, S3: ~$50, maintenance: ~$200)

---

#### Tool 8: Payment Channel Cost Optimizer

**Problem Statement:** Stripe processes payments through 11 different channel_ids, each with different fee structures. Total payment volume is $2.27M but the effective processing rate per channel is unknown.

**Data Sources:**
- `luckyus_sales_payment.t_trade` — transactions by channel_id (11 channels)
- `luckyus_sales_payment.t_channel_fee` — per-transaction fees (transaction_fee, merchant_service_fee, total_fee)
- `luckyus_sales_payment.t_user_channel` — user payment method preferences

**Payment Channel Revenue Breakdown:**

| Channel ID | Transactions | Revenue | Likely Method |
|-----------|-------------|---------|---------------|
| 53 | 205,988 | $917,232 | Apple Pay |
| 6 | 168,286 | $753,165 | Credit Card |
| 51 | 30,901 | $153,927 | Google Pay |
| 3 | 27,301 | $136,363 | Debit Card |
| 1 | 29,163 | $100,710 | Other Card |
| 52 | 17,829 | $82,992 | Alt Payment |
| 5 | 12,232 | $57,078 | — |
| 91 | 12,682 | $56,875 | — |
| 54 | 1,737 | $11,688 | — |
| 55 | 198 | $892 | — |
| 92 | 5 | $188 | — |

**Technical Approach:**
- Calculate effective fee rate per channel_id: `SUM(total_fee) / SUM(amount)` from `t_channel_fee`
- Identify highest-cost payment methods and model savings from steering customers
- Track fee rate trends over time (Stripe may adjust rates)
- Model impact of payment method incentives (e.g., 5-cent discount for debit)

**UI Description:**
Cost comparison table showing each payment channel's: volume, revenue, total fees, effective rate, and cost rank. "What-if" simulator: "If we shift 10% of Apple Pay to debit, savings = $X/year." Monthly fee trend chart.

**Business Impact:**
- Quantify exact payment processing costs per channel (estimated $50-80K/year total)
- Identify opportunities to reduce processing costs by 15-25% through payment method steering
- Negotiate better Stripe rates with volume data

**Complexity:** Low-Medium
**Estimated Monthly Cost:** $300-500 (Lambda: ~$50, analytics: ~$100, dashboard: ~$100, maintenance: ~$150)

---

#### Tool 9: Tax Compliance Gap Tracker

**Problem Statement:** The `luckyus_fi_tax` database is completely empty — all tax invoice tables have zero rows. Meanwhile, orders in `t_order_item` include `tax_rate`, `tax`, and `tax_info` JSON fields, and `t_order_amount` has GST/VAT breakdown fields. Tax data is being captured at order level but not flowing to the tax system.

**Data Sources:**
- `luckyus_fi_tax` — all tables (currently 0 rows — the gap itself)
- `luckyus_sales_order.t_order_item` — tax_rate, tax, tax_info fields per item
- `luckyus_sales_order.t_order_amount` — tax breakdown at order level
- `luckyus_ifiaccounting.t_acc_income_bill` — for cross-referencing

**Technical Approach:**
- Audit order-level tax calculations: extract and validate `tax_rate` and `tax` from all completed USD orders
- Calculate total sales tax collected vs. expected (based on NY state + NYC rates)
- Flag orders with missing or zero tax where tax should apply
- Generate synthetic tax ledger from order data for compliance review
- Monitor `fi_tax` tables for when the integration goes live

**UI Description:**
Tax compliance dashboard showing: total tax collected (from orders), expected tax (based on rates), gap analysis. Monthly tax summary suitable for filing preparation. Alert when fi_tax tables begin populating (integration goes live).

**Business Impact:**
- **Critical compliance issue**: ensures Luckin USA has accurate tax collection records
- Supports NY State + NYC sales tax filing requirements
- Prevents potential penalties from inaccurate tax reporting
- Bridges the gap until the fi_tax system integration is completed

**Complexity:** Medium
**Estimated Monthly Cost:** $400-600 (Lambda: ~$100, analytics: ~$100, legal/compliance review: ~$200, maintenance: ~$200)

---

### 3.4 Product Department

#### Tool 10: Product Performance & Menu Analytics Engine

**Problem Statement:** With ~80+ active products across categories (Fresh Ground Coffee, Classic Drinks, Matcha, Cold Brew, Refreshers, Exfreezo, Super Drink, Food), the product team needs data-driven insights on what to promote, modify, or retire — but data is split across commodity catalog, order items, and production systems.

**Data Sources:**
- `luckyus_sales_order.t_order_item` (602K) — per-item sales: spu_name, category, origin_price, sale_price, pay_money
- `luckyus_scm_commodity.t_commodity_base_info` — product attributes, nutrition grade, sugar level
- `luckyus_opproduction.t_production` — production complexity (time to make)
- `luckyus_scm_commodity.t_formula_spu` (32K) — recipe/formula details
- `luckyus_iot_platform.t_coffee_formula` (217) — machine formula assignments

**Technical Approach:**
- Product scorecard: combine sales velocity, revenue contribution, profit margin (origin vs. sale price), and production time
- Category heat maps: which categories are growing vs. declining
- Price elasticity analysis: correlate price changes with volume changes
- Menu engineering matrix (BCG-style): Stars (high volume, high margin), Puzzles (low volume, high margin), Plow Horses (high volume, low margin), Dogs (low both)
- Seasonal trend detection: 30-day rolling averages by product

**UI Description:**
Product leaderboard sorted by any metric (volume, revenue, margin, production speed). BCG-style quadrant chart plotting products by volume vs. margin. Category breakdown with sparkline trends. Product detail page showing: daily sales curve, store-by-store performance, pricing history, production time distribution.

**Business Impact:**
- Data-driven menu optimization (which items to promote in app)
- Identify under-performing products for retirement (save ingredient costs)
- Optimize pricing: Iced Coconut Latte is #1 by volume but has the lowest avg price ($3.22) — pricing power exists
- Production time insights: some products are significantly slower to make, impacting throughput

**Complexity:** Medium
**Estimated Monthly Cost:** $600-1,000 (ETL pipeline: ~$200, analytics DB: ~$200, dashboard: ~$200, maintenance: ~$200)

---

#### Tool 11: Customer Taste Profile & Recommendation Engine

**Problem Statement:** With 277K users and order history, there's an opportunity to build recommendation algorithms, but no personalization exists beyond the A/B tested layouts.

**Data Sources:**
- `luckyus_sales_order.t_order_item` — what each user_no orders
- `luckyus_sales_crm.t_user_profile` — demographics
- `luckyus_isales_cdp.t_user_state` — behavioral segments
- `luckyus_scm_commodity.t_commodity_base_info` — product attributes (sugar_level, category, nutrition)

**Technical Approach:**
- Build user-item interaction matrix from order history
- Collaborative filtering: "Users who ordered X also ordered Y"
- Content-based filtering: recommend products with similar attributes (same sugar_level, same category)
- Time-aware recommendations: suggest iced drinks in summer, hot in winter
- New store opening recommendation: which menu items to highlight based on neighborhood demographic similarity

**UI Description:**
Internal tool showing: per-user taste profile (preferred categories, sugar preference, avg spend), recommended products for next push notification, lookalike segments. Dashboard showing recommendation performance metrics. Feed into app's product ranking algorithm.

**Business Impact:**
- Increase basket size through personalized upsell suggestions
- Improve new product launch success by targeting receptive segments
- Expected 5-10% increase in order value from relevant recommendations

**Complexity:** High
**Estimated Monthly Cost:** $1,200-1,800 (ML training: ~$400, SageMaker inference: ~$300, data pipeline: ~$200, API: ~$100, maintenance: ~$300)

---

#### Tool 12: Production Time Optimizer

**Problem Statement:** Average production time is 217.9 seconds (3.6 min) with extreme outliers up to 2.7 hours. Product teams need to understand which drinks take longest and why, to optimize recipes and equipment utilization.

**Data Sources:**
- `luckyus_opproduction.t_production` (502K) — accept_time to done_time per order
- `luckyus_opproduction.t_commodity` (567K) — product in production context
- `luckyus_iot_platform.t_cup_order_info` (587K) — machine-level timing
- `luckyus_iot_platform.t_device` (216) — machine type and status
- `luckyus_scm_commodity.t_formula_spu` (32K) — recipe complexity

**Technical Approach:**
- Production time analysis by: product, store, time-of-day, day-of-week, machine type
- Outlier detection and removal (>30 min = data error or operational issue)
- Peak-hour bottleneck identification: when does production time spike?
- Machine efficiency comparison: same product across different machine types
- Recipe complexity scoring based on formula step count

**UI Description:**
Production time distribution chart per product (violin plots). Store comparison showing avg/p50/p95 production times. Time-of-day heatmap showing when bottlenecks occur. Machine utilization dashboard with efficiency scores.

**Business Impact:**
- Identify production bottlenecks costing throughput during peak hours
- Optimize recipe/machine assignments to reduce average wait time
- Support capacity planning for new store openings
- Target: reduce avg production time from 3.6 min to under 3 min

**Complexity:** Medium
**Estimated Monthly Cost:** $500-800 (analytics: ~$200, dashboard: ~$200, maintenance: ~$200)

---

### 3.5 Operations Department

#### Tool 13: Store Performance Command Center

**Problem Statement:** With 10 stores at different maturity stages (oldest: June 2025, newest: Feb 2026), operations needs a real-time view of each store's performance against KPIs. Currently, no unified operational dashboard exists.

**Data Sources:**
- `luckyus_sales_order.t_order` — orders per store per hour
- `luckyus_opproduction.t_production` — production throughput per store
- `luckyus_iot_platform.t_device` — machine status per store
- `luckyus_scm_shopstock.t_shop_goods_stock` (150K) — inventory levels per store
- `luckyus_opshop.t_shop_opening_time` (135K) — operating hours compliance

**Technical Approach:**
- Real-time store scorecard updated every 15 minutes during operating hours
- KPIs per store: orders/hour, revenue/hour, avg production time, machine uptime %, items out-of-stock
- Store ranking with peer comparison (normalize for age/location)
- Trend analysis: is each store's trajectory improving or declining?
- Alert system: notify ops if any store drops below threshold on any KPI

**UI Description:**
10-store grid with real-time traffic lights (green/yellow/red) per KPI. Click any store for detailed view: hourly order chart, production queue depth, machine status, stock-out list. Daily summary email to operations leadership. Weekly store ranking leaderboard.

**Business Impact:**
- Enable proactive management (catch issues before customer impact)
- Fair store-to-store comparison accounting for different opening dates
- Support staffing decisions with demand pattern visibility
- Quantify impact of new store openings on nearby stores (cannibalization analysis)

**Complexity:** Medium-High
**Estimated Monthly Cost:** $1,000-1,500 (real-time pipeline: ~$300, compute: ~$300, dashboard: ~$200, alerting: ~$100, maintenance: ~$300)

---

#### Tool 14: IoT Machine Fleet Manager

**Problem Statement:** 216 IoT-connected Schaerer machines across stores have mixed online/offline status. There's no predictive maintenance system, and machine downtime directly impacts revenue (a single machine down = 50%+ capacity loss for small stores).

**Data Sources:**
- `luckyus_iot_platform.t_device` (216 devices) — machine_type, status, online/offline
- `luckyus_iot_platform.t_cup_order_info` (587K) — production per device
- `luckyus_iot_platform.t_coffee_formula` (217) — formula assignments
- `luckyus_iot_platform.t_device_event` — machine events/errors (if available)
- `luckyus_opproduction.t_production` — correlated production data

**Technical Approach:**
- Real-time machine status dashboard showing all 216 devices
- Production velocity per machine: cups/hour trending
- Anomaly detection: flag machines whose production velocity drops >20% vs. baseline
- Maintenance prediction: track days since last maintenance event, production count since maintenance
- Machine type comparison: 14 machine_types identified — compare reliability/throughput
- Formula utilization tracking per machine

**UI Description:**
Floor plan-style map showing all machines per store, color-coded by status (green=online, red=offline, yellow=degraded). Click machine for: production history, error log, last maintenance date, utilization rate. Fleet summary: machines by type, avg uptime %, maintenance schedule. Alert panel for offline machines.

**Business Impact:**
- Reduce unplanned downtime (each hour of downtime ≈ $50-100 lost revenue per store)
- Extend machine lifespan through preventive maintenance
- Optimize machine placement and type selection for new stores

**Complexity:** Medium
**Estimated Monthly Cost:** $600-900 (IoT data pipeline: ~$200, analytics: ~$200, dashboard: ~$200, maintenance: ~$200)

---

#### Tool 15: Dynamic Staffing Optimizer

**Problem Statement:** Order volume varies dramatically — weekday peaks at ~3,700/day vs. weekend lows at ~1,400/day, with significant hourly variation. Staffing isn't currently data-driven.

**Data Sources:**
- `luckyus_sales_order.t_order` — hourly order volumes by store and day-of-week
- `luckyus_opproduction.t_production` — production time patterns (avg 3.6 min)
- `luckyus_ireplenishment.t_order_predict_alg_v2` (124K) — AI demand predictions (already available!)
- Historical daily patterns (Feb 2026 data: Mon 3,156 → Tue 3,316 → Wed 3,048 → Sat 1,349)

**Technical Approach:**
- Leverage existing AI demand prediction from `ireplenishment` system
- Convert predicted order volumes to required staff-hours using production time benchmarks
- Generate weekly staffing schedule recommendations per store
- Account for: store-specific demand patterns, product mix (some products need more labor), historical no-show rates
- What-if modeling: "If we expect 20% more orders due to a promotion, how many extra hours do we need?"

**UI Description:**
Weekly schedule grid per store showing: predicted hourly demand (bar chart), recommended staff count (line overlay), actual staff (input field). Color-coded: green (well-staffed), yellow (tight), red (under-staffed). Push notification for same-day demand spikes. Weekly scheduling summary PDF for store managers.

**Business Impact:**
- Reduce labor costs by 10-15% through data-driven scheduling
- Improve customer experience by matching staffing to demand
- Reduce employee burnout from over-scheduling during quiet periods
- Leverage existing AI predictions (no new ML needed)

**Complexity:** Medium
**Estimated Monthly Cost:** $500-800 (leveraging existing AI predictions, Lambda: ~$100, scheduling engine: ~$200, UI: ~$100, maintenance: ~$200)

---

### 3.6 Supply Chain Department

#### Tool 16: Intelligent Inventory Command Center

**Problem Statement:** Inventory data is spread across 7+ day-specific stock change tables (1M+ records each) plus a 150K-row stock positions table. Supply chain managers have no real-time visibility into stock levels, consumption rates, or replenishment triggers across stores.

**Data Sources:**
- `luckyus_scm_shopstock.t_shop_goods_stock` (150K) — current stock positions
- `luckyus_scm_shopstock.t_shop_goods_stock_change_*` (Mon-Sun, 1M+ each) — daily consumption
- `luckyus_ireplenishment.wh_goods_daily_demand_pred` (2.5M) — AI demand predictions
- `luckyus_scm_commodity.t_mdm_goods` (1,448) — goods master data

**Technical Approach:**
- Real-time stock dashboard showing all SKUs across all stores
- Days-of-supply calculation: current stock / avg daily consumption rate
- Automated reorder alerts when days-of-supply < threshold (configurable per SKU)
- Waste tracking: items expiring or written off
- Integration with AI demand predictions for forward-looking stock planning
- Consumption anomaly detection: flag unusual usage patterns (potential theft, waste, or data entry errors)

**UI Description:**
Store-level inventory grid: rows=SKUs, columns=stores, cells=days-of-supply (color-coded). Drill down per store-SKU: stock level chart, consumption rate trend, pending deliveries, predicted demand. Auto-generated daily replenishment order suggestions. Exception dashboard highlighting items at risk of stock-out or overstock.

**Business Impact:**
- Reduce stock-outs (each stock-out = lost sales + customer dissatisfaction)
- Reduce waste from overstocking perishable ingredients
- Optimize order quantities using AI predictions (system already exists)
- Target: reduce waste by 15-20%, reduce stock-outs by 50%

**Complexity:** High
**Estimated Monthly Cost:** $1,200-1,800 (real-time data pipeline: ~$400, analytics: ~$300, dashboard: ~$200, integration: ~$200, maintenance: ~$300)

---

#### Tool 17: Supplier Performance Tracker

**Problem Statement:** With 694 purchase orders, 1,670 shipping orders, and 1,363 supplier settlements in the procurement database, there's no visibility into supplier reliability, lead times, or cost trends.

**Data Sources:**
- `luckyus_scm_purchase.t_purchase_order` (694) — order placement dates, quantities, amounts
- `luckyus_scm_purchase.t_ship_order` (1,670) — shipping dates, delivery tracking
- `luckyus_scm_purchase.t_supplier_settlement` (1,363) — payment terms, amounts
- `luckyus_scm_purchase.t_purchase_order_item` — line-item details

**Technical Approach:**
- Supplier scorecard: on-time delivery rate, order accuracy, price consistency, settlement speed
- Lead time tracking: order date to delivery date per supplier
- Price trend analysis: track unit costs over time per SKU per supplier
- Spend analysis: category-level and supplier-level spend breakdown
- Compare supplier performance for shared SKUs

**UI Description:**
Supplier ranking table with performance scores. Drill into any supplier: delivery history timeline, price trend charts, open orders. Monthly spend breakdown pie chart by category. Alert panel for overdue deliveries or price increases.

**Business Impact:**
- Improve supplier negotiation with data-backed performance reviews
- Identify reliability issues before they cause stock-outs
- Optimize supplier mix based on total cost of ownership

**Complexity:** Low-Medium
**Estimated Monthly Cost:** $300-500 (ETL: ~$100, analytics: ~$100, dashboard: ~$100, maintenance: ~$150)

---

#### Tool 18: Demand Forecasting Accuracy Monitor

**Problem Statement:** Luckin already has an AI demand forecasting system (`ireplenishment`) generating 2.5M daily predictions and 124K order-level predictions. But there's no feedback loop measuring whether these predictions are actually accurate.

**Data Sources:**
- `luckyus_ireplenishment.wh_goods_daily_demand_pred` (2.5M) — predicted demand per shop/SKU/day
- `luckyus_ireplenishment.t_order_predict_alg_v2` (124K) — order-level predictions
- `luckyus_sales_order.t_order` — actual order counts (ground truth)
- `luckyus_scm_shopstock.t_shop_goods_stock_change_*` — actual consumption (ground truth)

**Technical Approach:**
- Automated accuracy calculation: compare predicted vs. actual demand per shop/SKU/day
- Metrics: MAPE (Mean Absolute Percentage Error), bias (systematic over/under-prediction), hit rate (within ±20%)
- Segmented accuracy: by store, by SKU category, by day-of-week, by lead time
- Trend analysis: is prediction accuracy improving over time?
- Identify products/stores where predictions are consistently poor (need model retraining)
- Benchmark against naive baselines (last week's actuals, trailing average)

**UI Description:**
Forecast accuracy dashboard showing: overall MAPE score, accuracy by store (bar chart), accuracy by category (heatmap), worst-performing predictions list. Time-series showing accuracy trend. Store-level drill-down showing predicted vs. actual charts. Weekly accuracy report emailed to supply chain team.

**Business Impact:**
- Close the feedback loop on the existing $2.5M-row AI system
- Identify where predictions fail to trigger model improvements
- Reduce inventory waste by improving forecast accuracy by even 5-10%
- Build confidence in AI-driven ordering decisions

**Complexity:** Medium
**Estimated Monthly Cost:** $500-800 (analytics: ~$200, compute: ~$200, dashboard: ~$200, maintenance: ~$200)

---

## 4. Cross-Departmental AI Transformation Tools

### Tool 19: Natural Language Data Query Interface ("Ask Lucky")

**Problem Statement:** Non-technical staff across all departments need to answer data questions without SQL knowledge. Currently, every data request requires engineering support.

**Data Sources:** All 18 core databases (read-only access)

**Technical Approach:**
- Leverage existing Dify AI platform (already deployed on PostgreSQL `luckyus_dify_api`)
- Build a text-to-SQL layer using GPT-4/Claude with schema metadata
- Pre-approved query templates for common questions with parameterized inputs
- Guardrails: restrict to SELECT-only, limit result sizes, mask PII (phone numbers already partially masked)
- Query caching for repeated questions
- Natural language → SQL → Results → Natural language summary pipeline

**Example Queries:**
- "How many orders did 8th & Broadway do yesterday?"
- "What's our best selling drink this week?"
- "Show me the top 10 users by order count"
- "Compare revenue between weekdays and weekends this month"

**UI Description:**
Chat interface (integrated into internal tools or Slack). Type a question, get a formatted answer with supporting chart. History of previous queries. Ability to save and share queries. "Explain this data" button for context.

**Business Impact:**
- Democratize data access across all departments
- Reduce engineering time spent on ad-hoc data requests (estimated 20+ hours/week saved)
- Enable faster decision-making at all levels
- Leverage existing Dify infrastructure investment

**Complexity:** High
**Estimated Monthly Cost:** $1,500-2,500 (Dify hosting: already exists, LLM API: ~$500, compute: ~$300, read replicas: ~$400, development: ~$500)

---

### Tool 20: Executive Daily Briefing AI

**Problem Statement:** Leadership needs a daily digest of key business metrics without logging into multiple dashboards or waiting for manual reports.

**Data Sources:**
- `luckyus_sales_order.t_order` — yesterday's orders, revenue, AOV
- `luckyus_sales_payment.t_trade` — payment volumes
- `luckyus_opproduction.t_production` — production metrics
- `luckyus_iot_platform.t_device` — machine fleet status
- `luckyus_scm_shopstock.t_shop_goods_stock` — inventory alerts
- `luckyus_sales_marketing.t_coupon_record` — campaign activity

**Technical Approach:**
- Automated daily pipeline running at 7 AM ET
- Aggregates key metrics from all core systems
- AI-generated narrative summary highlighting: notable changes, anomalies, records, warnings
- Trend comparison: today vs. same day last week, vs. trailing 30-day average
- Automatic anomaly flagging (>2 standard deviations from norm)

**Content Sections:**
1. Revenue & Orders (total, by store, vs. benchmarks)
2. Operational Health (production times, machine status, stock-outs)
3. Customer Metrics (new registrations, active users, coupon usage)
4. Alerts & Exceptions (anything requiring attention)
5. 7-Day Outlook (based on AI demand predictions)

**UI Description:**
Formatted email/Slack message delivered at 7 AM. Clean, mobile-optimized layout with key numbers, mini-charts, and color-coded trend indicators. "Deep dive" links to relevant dashboards. Approximately 2-minute read.

**Business Impact:**
- Give leadership a data-driven start to every day
- Surface issues proactively (don't wait for complaints)
- Create accountability culture around metrics

**Complexity:** Medium
**Estimated Monthly Cost:** $400-700 (Lambda: ~$100, LLM API: ~$200, SES: ~$20, compute: ~$100, maintenance: ~$200)

---

### Tool 21: Expansion Site Scoring Simulator

**Problem Statement:** With 10 stores in Manhattan and plans to grow, selecting optimal new locations requires combining internal data (store performance patterns, customer density) with external data (foot traffic, demographics, competition, rent).

**Data Sources:**
- `luckyus_opshop.t_shop_info` — existing store GPS coordinates and performance
- `luckyus_sales_order.t_order` — revenue ramp curves by store age
- `luckyus_sales_crm.t_user` — customer geographic distribution (timezone data)
- `luckyus_isales_cdp.t_user_state` — customer density patterns
- External APIs: Census data, foot traffic (Placer.ai), Yelp/Google competitors, commercial rent indices

**Technical Approach:**
- Build performance model from existing 10 stores: what predicts high vs. low performance?
- Factors: proximity to subway, office density, residential density, competitor presence, rent level
- Gravity model: predict cannibalization effect on existing stores
- Revenue ramp model: estimate time-to-profitability based on location characteristics
- Score potential locations on a 0-100 scale with confidence intervals

**UI Description:**
Interactive NYC map showing: existing stores (with performance badges), heatmap of customer density, scored potential locations (color = score). Click any potential site to see: predicted monthly revenue, ramp curve, cannibalization risk, comparable existing stores, key factors driving the score. Scenario modeling: "What if we open stores at both Location A and Location B?"

**Business Impact:**
- Reduce new store failure risk (each failed store costs $200K+ in build-out)
- Optimize expansion sequence (open highest-probability stores first)
- Quantify cannibalization risk before committing to leases

**Complexity:** High
**Estimated Monthly Cost:** $1,500-2,500 (external data APIs: ~$500, ML compute: ~$400, mapping UI: ~$300, development: ~$500)

---

### Tool 22: Unified Compliance & Audit Platform

**Problem Statement:** Multiple compliance requirements intersect: tax compliance (fi_tax gap), payment card data security (PCI-DSS), food safety tracking, labor laws. No unified compliance view exists.

**Data Sources:**
- `luckyus_fi_tax` — tax compliance (EMPTY — critical gap)
- `luckyus_sales_payment.t_trade` — payment audit trail
- `luckyus_sales_payment.t_channel_fee` — fee compliance
- `luckyus_opproduction.t_production` — food production timestamps (HACCP-relevant)
- `luckyus_iot_platform.t_device` — equipment maintenance records
- `luckyus_ifiaccounting.t_acc_income_bill` — financial audit trail

**Technical Approach:**
- Compliance checklist engine with automated data validation
- Tax compliance: track daily tax collection, flag gaps, generate filing summaries
- Payment compliance: verify all transactions have matching fee records, no orphaned payments
- Food safety: flag production time outliers (>30 min = temperature risk for fresh drinks)
- Financial controls: three-way match (order→payment→accounting) with automated exception reporting
- Audit trail: immutable log of all compliance checks with timestamps

**UI Description:**
Compliance dashboard with category tabs: Tax, Payment, Food Safety, Financial Controls. Each tab shows: pass/fail checklist, open issues count, trend chart. Monthly compliance score. Exportable audit reports for external auditors. Alert system for new compliance failures.

**Business Impact:**
- Address critical tax compliance gap before regulatory issues arise
- Maintain PCI-DSS readiness for payment processing
- Support health department inspections with production data
- Reduce audit preparation time from weeks to days

**Complexity:** High
**Estimated Monthly Cost:** $1,200-1,800 (compute: ~$300, compliance engine: ~$300, dashboard: ~$200, legal review: ~$300, maintenance: ~$300)

---

### Tool 23: Cross-Timezone Operations Hub

**Problem Statement:** The technology stack serves both US (NYC, America/New_York) and NZ/Cook Islands (Pacific/Rarotonga) timezones. Data timestamps, reporting periods, and operational schedules must account for 17-18 hour timezone differences.

**Data Sources:**
- `luckyus_opshop.t_shop_info` — `time_zone` field per store
- All transactional tables — `create_time` timestamps (server timezone vs. local store timezone)
- `luckyus_sales_order.t_order` — order timestamps for timezone-aware reporting

**Technical Approach:**
- Timezone normalization layer: convert all timestamps to both UTC and local store timezone
- Daily close calculation per timezone (end-of-day differs by 17-18 hours)
- Cross-timezone KPI comparison accounting for business hour alignment
- Automated reporting that generates separate reports per timezone market
- Holiday calendar per market (US holidays ≠ NZ holidays)

**UI Description:**
Dual-timezone dashboard showing side-by-side: NYC stores (live during ET hours) and Cook Islands stores (live during CKT hours). World clock showing which markets are currently open. Combined view with timezone-normalized metrics. Scheduled reports aligned to each market's business hours.

**Business Impact:**
- Accurate financial reporting across timezones
- Prevent data analysis errors from timezone confusion (currently a real risk with NZD/USD mixing)
- Support future expansion to additional US timezones

**Complexity:** Medium
**Estimated Monthly Cost:** $300-500 (timezone conversion layer: ~$100, reporting: ~$100, dashboard: ~$100, maintenance: ~$150)

---

### Tool 24: AI-Powered Anomaly Detection System

**Problem Statement:** With $2.19M in revenue, 466K orders, 216 IoT devices, and 277K users, manual monitoring for fraud, waste, and operational anomalies is impossible.

**Data Sources:**
- All core transactional databases (orders, payments, production, IoT, inventory)

**Technical Approach:**
- Statistical anomaly detection across key metrics:
  - Orders: unusual volumes, amounts, or patterns per store/user
  - Payments: refund rate spikes, fee anomalies, channel distribution shifts
  - Production: impossible production times, unusual waste patterns
  - IoT: machine behavior deviations
  - Inventory: consumption rates that don't match sales
- Severity scoring: Critical / Warning / Info
- Root cause suggestions based on correlated anomalies
- Learning system: false positive feedback to reduce noise

**UI Description:**
Anomaly feed (like a social media timeline) showing detected anomalies sorted by severity. Each anomaly card shows: what was detected, when, which system, severity score, suggested investigation steps. Daily summary email. Acknowledge/dismiss controls for ops team.

**Business Impact:**
- Early fraud detection (payment anomalies)
- Waste reduction (inventory anomalies)
- Revenue protection (order/production anomalies)
- Equipment failure prevention (IoT anomalies)

**Complexity:** High
**Estimated Monthly Cost:** $1,500-2,000 (ML compute: ~$500, data pipeline: ~$300, alerting: ~$200, dashboard: ~$200, maintenance: ~$400)

---

## 5. Implementation Roadmap

### Phase 1: Foundation (Months 1-2) — Quick Wins & Critical Fixes

**Priority:** Address compliance gaps and establish monitoring baseline

| Tool | Dept | Priority | Est. Cost/mo |
|------|------|----------|-------------|
| Tool 9: Tax Compliance Gap Tracker | Finance | **CRITICAL** | $400-600 |
| Tool 7: Daily Revenue Reconciliation | Finance | HIGH | $600-900 |
| Tool 2: Multi-Tenant Data Auditor | IT | HIGH | $200-400 |
| Tool 20: Executive Daily Briefing | Cross-Dept | HIGH | $400-700 |

**Phase 1 Total:** $1,600-2,600/month
**Key Outcomes:** Tax compliance visibility, clean financial data, daily executive insight

### Phase 2: Operational Intelligence (Months 3-4)

**Priority:** Real-time operational visibility for store managers

| Tool | Dept | Priority | Est. Cost/mo |
|------|------|----------|-------------|
| Tool 13: Store Performance Command Center | Operations | HIGH | $1,000-1,500 |
| Tool 14: IoT Machine Fleet Manager | Operations | HIGH | $600-900 |
| Tool 1: Database Health Monitor | IT | MEDIUM | $800-1,200 |
| Tool 15: Dynamic Staffing Optimizer | Operations | MEDIUM | $500-800 |

**Phase 2 Total:** $2,900-4,400/month
**Key Outcomes:** Real-time store dashboards, machine monitoring, data-driven staffing

### Phase 3: Growth Engine (Months 5-7)

**Priority:** Marketing effectiveness and product optimization

| Tool | Dept | Priority | Est. Cost/mo |
|------|------|----------|-------------|
| Tool 4: Customer 360 Platform | Marketing | HIGH | $1,500-2,500 |
| Tool 5: Campaign Performance Analyzer | Marketing | HIGH | $800-1,200 |
| Tool 10: Product Performance Engine | Product | MEDIUM | $600-1,000 |
| Tool 16: Inventory Command Center | Supply Chain | MEDIUM | $1,200-1,800 |
| Tool 18: Forecast Accuracy Monitor | Supply Chain | MEDIUM | $500-800 |

**Phase 3 Total:** $4,600-7,300/month
**Key Outcomes:** Unified customer view, campaign ROI tracking, product analytics, smart inventory

### Phase 4: AI Transformation (Months 8-12)

**Priority:** Advanced AI-powered capabilities

| Tool | Dept | Priority | Est. Cost/mo |
|------|------|----------|-------------|
| Tool 19: "Ask Lucky" NL Query | Cross-Dept | HIGH | $1,500-2,500 |
| Tool 21: Expansion Simulator | Cross-Dept | HIGH | $1,500-2,500 |
| Tool 11: Recommendation Engine | Product | MEDIUM | $1,200-1,800 |
| Tool 24: Anomaly Detection | Cross-Dept | MEDIUM | $1,500-2,000 |
| Tool 22: Compliance Platform | Cross-Dept | MEDIUM | $1,200-1,800 |
| Tool 12: Production Time Optimizer | Product | LOW | $500-800 |

**Phase 4 Total:** $7,400-11,400/month
**Key Outcomes:** Democratized data access, data-driven expansion, AI-powered operations

### Remaining Tools (Ongoing)

| Tool | Dept | Est. Cost/mo |
|------|------|-------------|
| Tool 3: Redis Intelligence | IT | $400-600 |
| Tool 6: Channel Tracker | Marketing | $500-800 |
| Tool 8: Payment Cost Optimizer | Finance | $300-500 |
| Tool 17: Supplier Tracker | Supply Chain | $300-500 |
| Tool 23: Cross-Timezone Hub | Cross-Dept | $300-500 |

### Total Monthly Cost Projection

| Phase | Timeline | Monthly Cost Range |
|-------|----------|--------------------|
| Phase 1 | Months 1-2 | $1,600-2,600 |
| Phase 2 | Months 3-4 | $4,500-7,000 (cumulative) |
| Phase 3 | Months 5-7 | $9,100-14,300 (cumulative) |
| Phase 4 | Months 8-12 | $16,500-25,700 (cumulative) |
| Steady State | Month 12+ | ~$18,000-22,000 |

**Note:** At $20,000/store/month technology budget with 10 stores = $200,000/month total. The full tool catalog at steady state costs ~$18-22K/month, representing roughly 1 store's worth of technology budget — well within overall capacity.

---

## 6. Technology Architecture Recommendations

### 6.1 Platform Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     USER INTERFACE LAYER                      │
│  React/Next.js Dashboard  │  Slack Bot  │  Email Reports     │
└──────────────┬───────────────────────────┬───────────────────┘
               │                           │
┌──────────────▼───────────────────────────▼───────────────────┐
│                      API GATEWAY (AWS API Gateway)            │
│              Authentication (AWS Cognito / SSO)               │
└──────────────┬───────────────────────────┬───────────────────┘
               │                           │
┌──────────────▼──────────┐  ┌─────────────▼──────────────────┐
│   APPLICATION SERVICES  │  │      AI/ML SERVICES             │
│  (AWS Lambda / ECS)     │  │  (Dify + SageMaker)             │
│  - Analytics Engine     │  │  - NL Query (GPT-4/Claude)      │
│  - Alerting Service     │  │  - Anomaly Detection            │
│  - Reconciliation       │  │  - Recommendation Engine        │
│  - Compliance Checker   │  │  - Demand Forecasting (exists)  │
└──────────────┬──────────┘  └─────────────┬──────────────────┘
               │                           │
┌──────────────▼───────────────────────────▼───────────────────┐
│                    DATA INTEGRATION LAYER                     │
│         AWS Glue / Step Functions / EventBridge               │
│    ETL Pipelines  │  Change Data Capture  │  Event Streams    │
└──────────────┬───────────────────────────┬───────────────────┘
               │                           │
┌──────────────▼──────────┐  ┌─────────────▼──────────────────┐
│   ANALYTICS DATA STORE  │  │     SOURCE DATABASES            │
│   (Amazon Redshift      │  │   (READ-ONLY REPLICAS)          │
│    Serverless or        │  │  62 MySQL servers               │
│    RDS PostgreSQL)      │  │  78 Redis instances             │
│                         │  │   3 PostgreSQL servers          │
│  - Unified data model   │  │                                 │
│  - Historical data      │  │  Connected via RDS Proxy /      │
│  - Pre-computed metrics │  │  read replicas                  │
└─────────────────────────┘  └────────────────────────────────┘
```

### 6.2 Key Architecture Decisions

| Decision | Recommendation | Rationale |
|----------|---------------|-----------|
| **Analytics Database** | Amazon Redshift Serverless | Pay-per-query pricing suits variable workloads; handles cross-database joins that are currently impossible |
| **ETL Pipeline** | AWS Glue + Step Functions | Serverless, managed; handles the 62-server complexity without provisioning |
| **AI Platform** | Extend existing Dify deployment | Already deployed and running on PostgreSQL; avoid duplicate infrastructure |
| **Dashboard** | Grafana Cloud or Apache Superset | Open source options with strong SQL support; team likely familiar with Grafana (already has AWS monitoring) |
| **Authentication** | AWS Cognito with SAML/SSO | Integrates with existing AWS infrastructure; supports role-based access per department |
| **Real-time Pipeline** | Amazon Kinesis Data Streams | For IoT, production, and order event streaming |
| **Alerting** | PagerDuty + Slack | Industry standard; supports escalation policies across timezones |
| **Secrets Management** | AWS Secrets Manager | Already in AWS ecosystem; rotate database credentials automatically |

### 6.3 Data Pipeline Strategy

**Recommended:** Change Data Capture (CDC) using AWS DMS

| Source | Target | Frequency | Method |
|--------|--------|-----------|--------|
| Sales Order DB | Redshift | Near real-time (5 min) | DMS CDC |
| Payment DB | Redshift | Near real-time (5 min) | DMS CDC |
| Production DB | Redshift | Near real-time (5 min) | DMS CDC |
| IoT Platform | Kinesis → Redshift | Real-time (streaming) | Kinesis |
| Inventory DB | Redshift | Hourly batch | Glue ETL |
| CRM/CDP | Redshift | Daily batch | Glue ETL |
| Marketing DB | Redshift | Daily batch | Glue ETL |
| Accounting DB | Redshift | Daily batch | Glue ETL |

### 6.4 Security & Access Control

| Layer | Mechanism | Details |
|-------|-----------|---------|
| Network | VPC + Security Groups | All tools within same VPC as databases |
| Database | Read-only replicas | Production databases never directly queried by tools |
| Application | Row-level security | Filter by store for store-manager role |
| API | OAuth 2.0 + API keys | Rate limiting per user/role |
| Data | Column-level masking | Phone numbers, emails masked for non-admin roles |
| Audit | CloudTrail + custom logging | All data access logged and retained 90 days |
| Compliance | SOC 2 Type II alignment | Design for eventual audit certification |

### 6.5 Budget Summary

| Category | Monthly Cost | Annual Cost |
|----------|-------------|-------------|
| Analytics infrastructure (Redshift, Glue) | $2,000-3,000 | $24,000-36,000 |
| Application compute (Lambda, ECS) | $1,500-2,500 | $18,000-30,000 |
| AI/ML (SageMaker, LLM APIs) | $1,500-2,500 | $18,000-30,000 |
| Dashboards & UI hosting | $500-800 | $6,000-9,600 |
| Monitoring & alerting | $300-500 | $3,600-6,000 |
| Data transfer & storage | $200-400 | $2,400-4,800 |
| **Total Infrastructure** | **$6,000-9,700** | **$72,000-116,400** |
| Engineering team (2-3 FTE) | $30,000-45,000 | $360,000-540,000 |
| **Total with team** | **$36,000-54,700** | **$432,000-656,400** |

At 10 stores with $20K/store technology budget = $200K/month total capacity. The tool catalog and infrastructure consume ~$36-55K/month of this, leaving ample room for core platform costs (POS, app, AWS infrastructure, Stripe fees, etc.).

---

## 7. Appendix

### 7.1 Key SQL Queries Used in Discovery

```sql
-- Revenue and AOV by currency
SELECT currency_code, COUNT(*) as cnt, ROUND(SUM(pay_money),2) as total,
       ROUND(AVG(pay_money),2) as aov
FROM luckyus_sales_order.t_order WHERE status = 90
GROUP BY currency_code;
-- Result: USD: 466,252 orders, $2,194,799, AOV $4.71
--         NZD: 21,245 orders, NZ$74,628, AOV NZ$3.51

-- Store performance ranking
SELECT shop_name, COUNT(*) as order_count,
       ROUND(SUM(pay_money),2) as total_revenue,
       ROUND(AVG(pay_money),2) as aov
FROM luckyus_sales_order.t_order WHERE status = 90
GROUP BY shop_name ORDER BY order_count DESC;

-- Top products by order count
SELECT oi.spu_name, oi.one_category_name, COUNT(*) as order_count,
       ROUND(SUM(oi.pay_money),2) as total_revenue
FROM luckyus_sales_order.t_order_item oi
INNER JOIN luckyus_sales_order.t_order o ON oi.order_id = o.id
WHERE o.status = 90
GROUP BY oi.spu_name, oi.one_category_name
ORDER BY order_count DESC LIMIT 25;

-- Daily order volume trend (Feb 2026)
SELECT DATE(create_time) as order_date, COUNT(*) as orders,
       ROUND(SUM(pay_money),2) as daily_revenue
FROM luckyus_sales_order.t_order
WHERE status = 90 AND create_time >= '2026-02-01'
GROUP BY DATE(create_time) ORDER BY order_date;

-- Payment channel breakdown
SELECT channel_id, COUNT(*) as txn_count,
       ROUND(SUM(amount)/100,2) as total_usd
FROM luckyus_sales_payment.t_trade
WHERE status IN (1,2,3) GROUP BY channel_id
ORDER BY total_usd DESC;

-- Production time statistics (Feb 2026)
SELECT ROUND(AVG(TIMESTAMPDIFF(SECOND, accept_time, done_time)),1) as avg_secs,
       COUNT(*) as total_productions
FROM luckyus_opproduction.t_production
WHERE accept_time IS NOT NULL AND done_time IS NOT NULL
  AND done_time > accept_time AND create_time >= '2026-02-01';
-- Result: avg 217.9 sec (3.6 min), 36,696 productions

-- Order channel distribution
-- channel 2 (iOS): 410K orders (79%)
-- channel 1 (Android): 72K orders (14%)
-- channel 3 (delivery): 25K orders (5%)
-- channels 8,9,10: ~8K orders (2%)

-- Tax gap verification
SELECT TABLE_NAME, TABLE_ROWS FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'luckyus_fi_tax';
-- Result: ALL tables show 0 rows
```

### 7.2 Database Server Complete List

**MySQL (62 servers):** aws-luckyus-cdpactivity-rw, aws-luckyus-dbatest-rw, aws-luckyus-devops-rw, aws-luckyus-fichargecontrol-rw, aws-luckyus-fitax-rw, aws-luckyus-framework01-rw, aws-luckyus-framework02-rw, aws-luckyus-iadmin-rw, aws-luckyus-ibillingcentersrv-rw, aws-luckyus-ibizconfigcenter-rw, aws-luckyus-icyberdata-rw, aws-luckyus-iehr-rw, aws-luckyus-ifiaccounting-rw, aws-luckyus-igers-rw, aws-luckyus-ijumpserver-jumpserver-rw, aws-luckyus-iluckyams-rw, aws-luckyus-iluckyauthapi-rw, aws-luckyus-iluckydorisops-rw, aws-luckyus-iluckyhealth-rw, aws-luckyus-iluckymedia-rw, aws-luckyus-iopenadmin-rw, aws-luckyus-iopenlinker-rw, aws-luckyus-iopenservice-rw, aws-luckyus-iopocp-rw, aws-luckyus-iopshopexpand-rw, aws-luckyus-iotplatform-rw, aws-luckyus-ipermission-rw, aws-luckyus-ireplenishment-rw, aws-luckyus-iriskcontrolservice-rw, aws-luckyus-isalescdp-rw, aws-luckyus-isalesdatamarketing-rw, aws-luckyus-isalesmembermarketing-rw, aws-luckyus-isalesprivatedomain-rw, aws-luckyus-iunifiedreconcile-rw, aws-luckyus-iworkflowmidlayer-rw, aws-luckyus-ldas-rw, aws-luckyus-ldas01-rw, aws-luckyus-mfranchise-rw, aws-luckyus-opempefficiency-rw, aws-luckyus-oplog-rw, aws-luckyus-opproduction-rw, aws-luckyus-opqualitycontrol-rw, aws-luckyus-opshop-rw, aws-luckyus-opshopsale-rw, aws-luckyus-pubdm-rw, aws-luckyus-salescrm-rw, aws-luckyus-salesmarketing-rw, aws-luckyus-salesorder-rw, aws-luckyus-salespayment-rw, aws-luckyus-scm-asset-rw, aws-luckyus-scm-openapi-rw, aws-luckyus-scm-ordering-rw, aws-luckyus-scm-plan-rw, aws-luckyus-scm-purchase-rw, aws-luckyus-scm-shopstock-rw, aws-luckyus-scm-wds-rw, aws-luckyus-scm-wmssimulate-rw, aws-luckyus-scmcommodity-rw, aws-luckyus-scmsrm-rw, aws-luckyus-upush-rw, recovery-dbatest

**Redis (78 instances):** luckyus-aapi-unionauth, luckyus-apigateway, luckyus-auth, luckyus-authservice, luckyus-bigdata-cyberdata, luckyus-bigdata-dataplatform, luckyus-billcenterservice, luckyus-chronus, luckyus-cmdb, luckyus-daq, luckyus-devops, luckyus-empefficiency, luckyus-franchise, luckyus-iadmin, luckyus-ibizconfigcenter, luckyus-iehr, luckyus-ifiaccounting, luckyus-ifichargecontrol, luckyus-ifitax, luckyus-igers, luckyus-ilkm, luckyus-ilopamanager, luckyus-imessageflow, luckyus-iopenadmin, luckyus-iopenauth, luckyus-iopenlinker, luckyus-iopenlinkeradmin, luckyus-iopenservice, luckyus-iotplatform, luckyus-ipermission, luckyus-ipushnet, luckyus-iriskcontrol, luckyus-isales-commodity, luckyus-isales-crm, luckyus-isales-datamarket, luckyus-isales-market, luckyus-isales-marketcapi, luckyus-isales-member, luckyus-isales-order, luckyus-isales-privatedomain, luckyus-isales-session, luckyus-isales-tradecapi, luckyus-iunifiedreconcile, luckyus-iupush, luckyus-iworkflowmidlayer, luckyus-jumpserver, luckyus-koala, luckyus-ldas, luckyus-lkmap, luckyus-mdm, luckyus-ocp, luckyus-onepiece, luckyus-open-unionauth, luckyus-production, luckyus-pub-dm, luckyus-qualitycontrol, luckyus-redis-dify, luckyus-sapi-unionauth, luckyus-scm-asset, luckyus-scm-commodity, luckyus-scm-commodityadmin, luckyus-scm-ordering, luckyus-scm-plan, luckyus-scm-purchase, luckyus-scm-shopstock, luckyus-scm-sims, luckyus-scm-srm, luckyus-scm-wds, luckyus-scmwmssimulate, luckyus-session, luckyus-shop, luckyus-shopexpand, luckyus-shopsale, luckyus-unionauth, luckyus-waf, luckyus-web

**PostgreSQL (3 servers):** aws-luckyus-dify-rw, aws-luckyus-difynew-rw, aws-luckyus-pgilkmap-rw

### 7.3 Data Volume Summary (as of Feb 14, 2026)

| Database | Largest Table | Row Count | Data Size |
|----------|--------------|-----------|-----------|
| luckyus_sales_marketing | t_coupon_record_expired | 37,000,000 | ~15 GB |
| luckyus_isalesdatamarketing | t_user_hit_experiment_record | 6,400,000 | ~3 GB |
| luckyus_sales_marketing | t_user_group_label | 3,900,000 | ~1.5 GB |
| luckyus_isales_cdp | t_realtime_user_group_log | 2,300,000 | ~1 GB |
| luckyus_sales_marketing | t_coupon_record | 2,600,000 | ~1 GB |
| luckyus_ireplenishment | wh_goods_daily_demand_pred | 2,500,000 | ~1 GB |
| luckyus_sales_order | t_order_oper_history | 2,500,000 | ~800 MB |
| luckyus_opproduction | t_print_receipt | 2,000,000 | ~700 MB |
| luckyus_isales_cdp | t_user_state | 980,000 | ~400 MB |
| luckyus_opshopsale | t_shop_sale_remark | 820,000 | ~300 MB |

### 7.4 Key Column Reference

**t_order (luckyus_sales_order):**
`id, tenant, channel (1=Android, 2=iOS, 3=delivery), order_type (1=pickup, 2=delivery), user_no, shop_id, shop_name, status (90=completed, 0=cancelled), total_money, payable_money, pay_money, pay_time, create_time, finish_time, currency_code (USD/NZD)`

**t_trade (luckyus_sales_payment):**
`trade_no, channel_id, amount (in cents), status, third_trade_no (Stripe ref), fee, user_no`

**t_shop_info (luckyus_opshop):**
`shop_no, shop_name, status, operation_mode, time_zone, address, location_longitude, location_latitude, set_up_time, internal, test_flag`

**t_order_item (luckyus_sales_order):**
`order_id, spu_code, spu_name, one_category_name, two_category_name, three_category_name, sku_code, sku_name, origin_price, sale_price, pay_money, tax_rate, tax, tax_mode`

**t_commodity_base_info (luckyus_scm_commodity):**
`spu_code, name, status (4=online, 5=offline), mode (0=fresh-made, 1=pre-packaged), commodity_level (1=S, 2=A, 3=B), sugar_level, nutrition_grade_code`

---

*Report generated by automated database infrastructure analysis. All data accessed in READ-ONLY mode. No production data was modified during this analysis.*

*© 2026 Luckin Coffee USA — Internal Use Only*

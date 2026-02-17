# Luckin Coffee USA - Database Infrastructure & AI Transformation Report

**Report:** Department Tool Catalog (18 Tools)
**Date:** February 13, 2026
**Prepared for:** Luckin Coffee USA Leadership Team

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

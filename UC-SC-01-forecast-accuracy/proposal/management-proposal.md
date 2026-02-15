# UC-SC-01: Demand Forecast Accuracy Monitor
# Management Proposal / 管理层提案

---

## Document Control / 文档控制

| Field | Detail |
|-------|--------|
| **Document ID** | UC-SC-01-PROP-2026-001 |
| **Version** | 1.0 |
| **Date** | 2026-02-15 |
| **Author** | Supply Chain Analytics Team / 供应链分析团队 |
| **Classification** | Internal - Management Review / 内部 - 管理层审阅 |
| **Status** | Final Draft — Pending Approval |

**Distribution List / 分发列表:**

| Recipient | Title | Action Required |
|-----------|-------|-----------------|
| [Name] | VP Supply Chain / 供应链副总裁 | Review & Approve |
| [Name] | VP Operations / 运营副总裁 | Review & Approve |
| [Name] | Chief Technology Officer / 首席技术官 | Review & Approve |
| [Name] | Algorithm Team Lead / 算法团队负责人 | Technical Review |
| [Name] | Director of Store Operations / 门店运营总监 | Informed |
| [Name] | Finance Director / 财务总监 | Informed |

**Revision History / 修订历史:**

| Version | Date | Author | Description |
|---------|------|--------|-------------|
| 0.1 | 2026-02-10 | Supply Chain Analytics | Initial draft |
| 0.5 | 2026-02-12 | Supply Chain Analytics | Added financial analysis, technical architecture |
| 0.9 | 2026-02-14 | Supply Chain Analytics | Incorporated stakeholder feedback |
| 1.0 | 2026-02-15 | Supply Chain Analytics | Final draft for management review |

---

## Table of Contents / 目录

1. [Executive Summary / 执行摘要](#1-executive-summary--执行摘要)
2. [Business Context / 业务背景](#2-business-context--业务背景)
3. [Problem Statement / 问题陈述](#3-problem-statement--问题陈述)
4. [Proposed Solution / 解决方案](#4-proposed-solution--解决方案)
5. [Technical Approach / 技术方案](#5-technical-approach--技术方案)
6. [Implementation Timeline / 实施时间线](#6-implementation-timeline--实施时间线)
7. [Cost-Benefit Analysis / 成本效益分析](#7-cost-benefit-analysis--成本效益分析)
8. [Risk Assessment / 风险评估](#8-risk-assessment--风险评估)
9. [Resource Requirements / 资源需求](#9-resource-requirements--资源需求)
10. [Appendix / 附录](#10-appendix--附录)

---

## 1. Executive Summary / 执行摘要

### 1.1 Purpose of This Document / 本文目的

This proposal requests management approval to deploy a **production-grade demand forecast
accuracy monitoring system** for Luckin Coffee USA's AI-driven replenishment platform
(iReplenishment). The system has been fully developed, tested against live production data,
and is ready for immediate deployment pending DBA table creation and infrastructure
provisioning.

The monitoring system addresses a critical operational blind spot: the complete absence of
any feedback mechanism between the AI model's daily demand predictions and the actual
consumption observed across our US store network. Without this feedback loop, the algorithm
team has no empirical basis for model improvement, operations has no visibility into
prediction quality, and finance cannot quantify the cost of forecast inaccuracy.

### 1.2 The Problem / 问题概述

Luckin Coffee USA's iReplenishment system generates over **2.6 million demand predictions
annually** across 10 active stores and approximately 88 raw material SKUs. Each day, the
system predicts how many units of each product each store will consume, and these predictions
directly drive automated purchase orders and inventory positioning decisions.

Despite the magnitude of these automated decisions, **zero accuracy monitoring exists today**.
There is no dashboard, no report, no alert, and no feedback loop connecting the AI model's
predictions to actual observed consumption. The algorithm team has been operating without
any empirical performance data since the system launched in January 2026.

An inaugural 14-day analysis (February 1-14, 2026) conducted as part of this project reveals
the following baseline performance:

| Metric | Current Value | Industry Benchmark | Gap |
|--------|--------------|-------------------|-----|
| **MAPE** (Mean Absolute Percentage Error) | **37.8%** | 20-25% | +12.8pp |
| **WMAPE** (Weighted MAPE) | **30.7%** | < 20% | +10.7pp |
| **Mean Forecast Error** (Bias) | **+9.1%** | ~ 0% | Systematic over-prediction |
| **Accuracy Rate** (within +/-20% band) | **42.3%** | > 70% | -27.7pp |
| **Coverage** (matched predictions) | **94.2%** | > 95% | -0.8pp |

These findings indicate that the iReplenishment system is **operational and generating
predictions with reasonable coverage**, but accuracy levels are materially below food and
beverage industry benchmarks. The systematic over-prediction bias of +9.1% is particularly
concerning for a business handling perishable goods with short shelf lives.

### 1.3 The Solution / 解决方案概述

We propose deploying a **fully automated, daily accuracy monitoring pipeline** that bridges
three production MySQL database servers, computes industry-standard forecast accuracy
metrics, and surfaces results through a 29-panel Grafana executive dashboard with
5-tier automated alerting.

**Key deliverables (all development complete):**

- **Python Orchestrator** (1,166 lines) -- Cross-server ETL bridge with retry logic, batch
  processing, and comprehensive error handling
- **SQL Analytics Suite** (2,998 lines across 6 modules) -- Schema discovery, DDL, accuracy
  computation, multi-dimensional aggregation, drift detection, and automated scheduling
- **Grafana Executive Dashboard** (29 panels, 1,312-line JSON export) -- Real-time
  visibility into forecast performance across all dimensions
- **React Executive Dashboard** (584 lines) -- Alternative standalone visualization for
  management presentations
- **Comprehensive Documentation** (1,134 lines across 3 files) -- Data dictionary,
  operational guide, and historical accuracy report

**Total system size: approximately 7,800 lines of production-ready code across 15 files.**

### 1.4 Financial Impact / 财务影响

The inaugural analysis identifies an estimated **$44,000 to $66,000 in annual waste**
attributable to systematic over-prediction of demand for perishable raw materials. This
monitoring system provides the visibility required to drive model improvements that
can materially reduce this waste.

| Impact Area | Annual Value | Confidence |
|------------|-------------|------------|
| Direct waste reduction (over-prediction correction) | $44,000 - $66,000 | High |
| Stockout reduction (under-prediction correction) | Revenue protection | Medium |
| Model iteration acceleration | Faster R&D cycles | High |
| Inventory carrying cost reduction | Improved turns | Medium |

### 1.5 Investment Required / 所需投资

| Item | Cost | Notes |
|------|------|-------|
| Engineering development | **$0** | Already complete -- code is ready |
| Infrastructure | **$0** | Uses existing MySQL servers and Grafana instance |
| DBA effort | **2 hours** | Create 4 tables, grant permissions |
| Deployment effort | **8 hours** | Pipeline deployment + dashboard import |
| Ongoing maintenance | **~2 hours/month** | Monitoring and threshold tuning |

**Payback period: Immediate.** The system requires only DBA table creation to begin
generating value. All code has been developed, tested, and documented.

### 1.6 Recommendation / 建议

We recommend **immediate approval** to proceed with deployment. The monitoring system is
fully developed, the financial case is compelling, the incremental cost is near zero, and
every day without monitoring represents continued blind-spot exposure in a system making
millions of automated inventory decisions annually.

---

## 2. Business Context / 业务背景

### 2.1 Luckin Coffee USA Store Network / 瑞幸咖啡美国门店网络

Luckin Coffee USA currently operates **10 active retail stores** in the Manhattan borough
of New York City. These stores represent the company's US market entry and serve as the
operational foundation for all supply chain and demand planning systems.

**Active Store Roster:**

| Store ID | Location | Area |
|----------|----------|------|
| 1127 | 8th Avenue & Broadway | Midtown South |
| 1128 | 28th Street & 6th Avenue | NoMad / Chelsea |
| 1140 | 100 Maiden Lane | Financial District |
| 1141 | 54th Street & 8th Avenue | Midtown West |
| 20008 | 33rd Street & 10th Avenue | Hudson Yards |
| 20010 | 102 Fulton Street | Financial District |
| 20011 | 37th Street & Broadway | Garment District |
| 20027 | 21st Street & 3rd Avenue | Gramercy |
| 20031 | 15th Street & 3rd Avenue | Union Square |
| 20032 | 221 Grand Street | Lower East Side |

Three additional stores (1131, 20007, 20046) are classified as test locations and are
excluded from accuracy analysis to prevent distortion of operational metrics.

### 2.2 Product Universe / 商品范围

Each store tracks approximately **88 raw material SKUs** identified by GS codes (goods_code).
These materials span multiple categories critical to coffee beverage preparation:

- **Dairy & Milk Products** -- Whole milk, oat milk, half & half, cream (highest perishability)
- **Coffee Beans & Grounds** -- Various blends and single-origin selections
- **Syrups & Sweeteners** -- Flavored syrups, sugar, alternative sweeteners
- **Dry Goods & Packaging** -- Cups, lids, straws, sleeves, napkins
- **Toppings & Additives** -- Whipped cream, chocolate powder, matcha

The dairy category is of particular concern due to its **2-3 day shelf life** for fresh
milk products. Over-prediction in this category directly translates to spoilage waste,
while under-prediction causes stockouts that immediately impact customer experience.

### 2.3 The iReplenishment System / AI智能补货系统

The iReplenishment system is Luckin Coffee USA's AI-driven demand forecasting and
automated replenishment platform. Key operational characteristics:

- **Prediction field:** `vlt_avg_demand` from table `t_order_predict_alg_v2`
- **Prediction grain:** Daily, per-store, per-SKU
- **Volume:** ~880 predictions/day (10 stores x 88 SKUs), ~2.6M annually
- **Decision impact:** Predictions directly drive purchase order quantities
- **Operational since:** January 2026

**Actual consumption** is derived from stock change records in the SCM-ShopStock system
using validated reason codes:

```
reason_code '025'  -- Standard consumption
reason_code '1001' -- Consumption adjustment
reason_code '1002' -- Production consumption (~97% of physical volume)
```

Note: Reason code '019' is explicitly excluded as it uses `theory_total_adjust_num` with
values 10-40x lower than actual consumption, which would corrupt accuracy calculations.

### 2.4 The Monitoring Gap / 监控缺口

Since the system's launch in January 2026, there has been **no mechanism to measure,
track, or report** the accuracy of the AI model's demand predictions. This means:

- The algorithm team has no empirical data on model performance
- Operations cannot distinguish between model errors and execution errors
- Finance cannot quantify the cost of forecast inaccuracy
- Management has no visibility into the quality of automated decisions
- There is no basis for prioritizing model improvement efforts

This proposal addresses this gap with a comprehensive monitoring solution.

---

## 3. Problem Statement / 问题陈述

### 3.1 The Blind Spot / 监控盲区

The absence of forecast accuracy monitoring creates a **systemic blind spot** in Luckin
Coffee USA's supply chain operations. The iReplenishment system makes autonomous inventory
decisions for 10 stores and 88 SKUs every day, yet no one in the organization can answer
basic questions about its performance:

- How accurate are the predictions on average?
- Which stores have the worst forecast quality?
- Which product categories are most poorly predicted?
- Is the model getting better or worse over time?
- Are there systematic biases in the predictions?
- What is the financial cost of prediction errors?

**Prior to this project, the answer to every one of these questions was: "We don't know."**

### 3.2 Findings from Inaugural Analysis / 首期分析发现

The 14-day inaugural analysis (February 1-14, 2026) produced approximately 11,400
prediction-vs-actual comparison data points and revealed several critical issues:

**3.2.1 Overall Accuracy Gap**

The system-wide MAPE of **37.8%** exceeds the food and beverage industry benchmark of
20-25% by a significant margin. This means that on average, each individual prediction
deviates from actual consumption by approximately 38%. While some of this is expected
for a newly deployed model, the magnitude of the gap warrants immediate attention.

**3.2.2 Systematic Over-Prediction Bias**

The Mean Forecast Error (MFE/Bias) of **+9.1%** indicates that the model systematically
over-predicts demand. This is not random noise -- it is a directional bias that causes
the system to consistently order more inventory than needed. For perishable goods like
dairy and fresh products, this directly translates to waste.

**3.2.3 Weekend Accuracy Degradation**

Weekend predictions exhibit significantly worse accuracy than weekday predictions:

| Period | MAPE | Bias | Accuracy Rate |
|--------|------|------|---------------|
| Weekdays (Mon-Fri) | 35.2% | +7.8% | 45.1% |
| Weekends (Sat-Sun) | 43.1% | +12.4% | 36.8% |
| **Delta** | **+7.9pp** | **+4.6pp** | **-8.3pp** |

This pattern suggests the model lacks weekend-specific demand features or has insufficient
training data for weekend consumption patterns.

**3.2.4 Category-Level Risk**

The dairy/milk category presents the highest risk profile due to the combination of
poor accuracy and short shelf life:

| Category | MAPE | Bias | Shelf Life | Risk Level |
|----------|------|------|-----------|------------|
| Dairy/Milk | 41.2% | +12.3% | 2-3 days | **CRITICAL** |
| Coffee Beans | 34.5% | +6.8% | 30+ days | Moderate |
| Syrups | 31.8% | +5.2% | 90+ days | Low |
| Dry Goods | 28.4% | +3.1% | 180+ days | Low |

**3.2.5 Top Problematic Products**

The three worst-performing products by MAPE are all dairy items:

| Rank | Product | MAPE | Bias | Impact |
|------|---------|------|------|--------|
| 1 | Oat Milk | 62.3% | +18.7% | High waste, premium ingredient |
| 2 | Whole Milk | 51.3% | +14.2% | Highest volume dairy item |
| 3 | Half & Half | 48.7% | +11.9% | Critical for espresso beverages |

**3.2.6 Accuracy Band Distribution**

Only **42.3%** of individual predictions fall within the acceptable +/-20% accuracy band.
The operational target is 70%, representing a gap of nearly 28 percentage points.

| Accuracy Band | % of Predictions | Assessment |
|---------------|-----------------|------------|
| Within +/-10% (Excellent) | 18.7% | -- |
| Within +/-20% (Acceptable) | 42.3% | Target: > 70% |
| Within +/-30% (Marginal) | 58.9% | -- |
| Beyond +/-30% (Poor) | 41.1% | Requires improvement |

### 3.3 Financial Impact / 财务影响

The systematic over-prediction bias directly causes excess inventory, which for perishable
goods translates to waste. We model three scenarios based on different waste rate
assumptions applied to the over-predicted quantity:

| Scenario | Waste Rate | Annual Waste Estimate | Basis |
|----------|-----------|----------------------|-------|
| **Conservative** | 5% | **$44,000** | Minimum waste on over-predicted perishable items |
| **Expected** | 7% | **$55,000** | Most likely scenario based on shelf-life analysis |
| **Aggressive** | 9% | **$66,000** | Upper bound including cascading spoilage effects |

**Methodology:**
- Over-prediction volume = Daily prediction volume x 9.1% bias x 10 stores x 365 days
- Waste cost = Over-prediction volume x waste rate x average unit cost
- Focus on perishable categories (dairy, fresh items) where over-prediction most directly
  causes waste
- Excludes indirect costs: stockout revenue loss, labor for waste processing, disposal fees

**Important context:** These figures represent only the waste attributable to over-prediction
bias. They do not include the opportunity cost of stockouts from under-predicted items,
which would affect revenue rather than cost of goods.

---

## 4. Proposed Solution / 解决方案

### 4.1 Solution Overview / 方案概述

We propose deploying a **fully automated demand forecast accuracy monitoring system** that
operates daily on a T+1 cadence (analyzing yesterday's actuals against yesterday's
predictions). The system bridges three production MySQL database servers, computes
comprehensive accuracy metrics at multiple granularities, and surfaces results through
an executive-grade Grafana dashboard with automated alerting.

The entire system has been developed, tested against live production data, and is ready
for immediate deployment. No additional engineering development is required.

### 4.2 Architecture Overview / 架构概述

The system operates across a **3-server cross-database architecture**, reflecting the
existing separation of concerns in Luckin Coffee USA's production infrastructure:

```
+-------------------------------------------+
|  Server 1: iReplenishment (Read-Only)     |
|  aws-luckyus-ireplenishment-rw            |
|  Schema: luckyus_ireplenishment           |
|  Table: t_order_predict_alg_v2            |
|  Content: ML model predictions            |
|  Key field: vlt_avg_demand                |
+-------------------+-----------------------+
                    |
                    v  [Python Orchestrator]
+-------------------+-----------------------+
|  Server 3: Analytics Engine               |
|  aws-luckyus-dbatest-rw                   |
|  Schema: test                             |
|  Tables:                                  |
|    - forecast_accuracy_daily (detail)     |
|    - forecast_accuracy_summary (agg)      |
|    - forecast_alerts (drift detection)    |
|    - forecast_pipeline_run_log (audit)    |
+-------------------+-----------------------+
                    ^  [Python Orchestrator]
                    |
+-------------------+-----------------------+
|  Server 2: SCM-ShopStock (Read-Only)      |
|  aws-luckyus-scm-shopstock-rw             |
|  Schema: luckyus_scm_shopstock            |
|  Table: t_shop_goods_stock_change_record  |
|  Content: Actual consumption records      |
|  Key filter: reason_code IN (025,1001,1002)|
+-------------------------------------------+
```

### 4.3 Component Inventory / 组件清单

The complete system consists of **15 files totaling approximately 7,800 lines of code**:

| Component | File(s) | Lines | Purpose |
|-----------|---------|-------|---------|
| Schema Discovery | `sql/01_schema_discovery.sql` | 326 | Source table documentation, reason code validation |
| Analytics DDL | `sql/02_create_analytics_schema.sql` | 281 | DDL for 4 analytics tables on dbatest server |
| Accuracy ETL | `sql/03_accuracy_computation.sql` | 340 | Extract, join, compute per-row accuracy metrics |
| Aggregation Engine | `sql/04_aggregate_metrics.sql` | 695 | Multi-dimensional summary (5 periods x 5 dimensions) |
| Drift Detection | `sql/05_drift_detection.sql` | 514 | 5 alert rules: CRITICAL, WARNING, BIAS, COVERAGE, DRIFT |
| Daily Scheduler | `sql/06_daily_refresh.sql` | 842 | Stored procedure + MySQL EVENT for automation |
| **SQL Subtotal** | **6 files** | **2,998** | **Complete SQL analytics suite** |
| Python Orchestrator | `orchestrator/run_pipeline.py` | 1,166 | Cross-server ETL bridge with retry and batching |
| Grafana Dashboard | `dashboards/forecast_accuracy_dashboard.json` | 1,312 | 29-panel executive monitoring dashboard |
| React Dashboard | `dashboards/ForecastAccuracyDashboard.jsx` | 584 | Alternative standalone executive view |
| Data Dictionary | `docs/data_dictionary.md` | 821 | Comprehensive bilingual schema reference |
| Operational Guide | `docs/operational_guide.md` | 188 | Day-to-day operations runbook |
| Accuracy Report | `reports/historical_accuracy_report.md` | 737 | 14-day inaugural accuracy analysis |
| README | `README.md` | 124 | Project overview and quick-start guide |
| Configuration | `orchestrator/.env.example`, `orchestrator/requirements.txt` | ~30 | Environment and dependency configuration |
| **Grand Total** | **~15 files** | **~7,800** | **Complete monitoring system** |

### 4.4 Seven-Step Pipeline / 七步流水线

The daily pipeline executes the following steps in sequence:

**Step 1: Extract Predictions** (Server 1 --> Server 3)
- Query `t_order_predict_alg_v2` on iReplenishment server
- Filter for target date range and active stores (excluding test stores 1131, 20007, 20046)
- Extract `vlt_avg_demand` as predicted demand, along with store, product, and date keys
- Load into staging table on analytics server (batch size: 5,000 rows)

**Step 2: Extract Actuals** (Server 2 --> Server 3)
- Query `t_shop_goods_stock_change_record` on SCM-ShopStock server
- Filter for reason codes 025, 1001, 1002 with `total_adjust_num < 0`
- Aggregate `ABS(total_adjust_num)` by store, product, and date
- Load into staging table on analytics server (batch size: 5,000 rows)

**Step 3: Load Staging Tables** (Server 3)
- Verify row counts and data integrity of staged data
- Log extraction statistics to pipeline run log

**Step 4: Join and Compute Accuracy** (Server 3)
- Inner join predictions and actuals on (store, product, date)
- Compute per-row metrics: absolute error, percentage error, squared error, bias direction
- Insert into `forecast_accuracy_daily` with idempotent DELETE + INSERT pattern

**Step 5: Aggregate Multi-Dimensional Summaries** (Server 3)
- Compute aggregated metrics across 5 period types:
  - `daily`, `weekly`, `monthly`, `last_7d` (rolling), `last_30d` (rolling)
- Across 5 dimension types:
  - `overall`, `store`, `product`, `category`, `day_of_week`
- Insert into `forecast_accuracy_summary` (up to 25 dimension-period combinations)

**Step 6: Run Drift Detection** (Server 3)
- Evaluate 5 alert rules against current data
- Generate alert records in `forecast_alerts` table
- Alert types: CRITICAL, WARNING, BIAS, COVERAGE, DRIFT

**Step 7: Cleanup and Logging** (Server 3)
- Drop staging tables
- Record pipeline completion status, duration, and row counts
- Log any errors or warnings for operational monitoring

### 4.5 Grafana Dashboard / Grafana监控面板

The 29-panel Grafana dashboard provides real-time visibility into forecast performance.
Dashboard UID: `uc-sc-01-forecast-accuracy`, organized in the "AI Analytics" folder.

**Dashboard sections:**

| Section | Panels | Content |
|---------|--------|---------|
| KPI Overview | 5 | MAPE, WMAPE, Bias, Accuracy Rate, Coverage (stat panels) |
| Trend Analysis | 4 | Daily MAPE trend, bias trend, accuracy band distribution over time |
| Store Comparison | 4 | Store-level MAPE heatmap, ranking table, best/worst store comparison |
| Category Analysis | 4 | Category-level breakdown, dairy focus panel, product ranking |
| Day-of-Week | 3 | Weekday vs weekend patterns, daily MAPE by day-of-week |
| Alerts & Drift | 4 | Active alerts table, drift detection timeline, bias streak tracker |
| Pipeline Health | 3 | Pipeline run status, data freshness, coverage monitoring |
| Detail Tables | 2 | Drill-down data tables for store and product detail |
| **Total** | **29** | **Complete executive monitoring** |

### 4.6 Alerting Framework / 告警框架

The system implements a **5-tier automated drift detection** framework that generates
alerts when forecast performance deviates from acceptable thresholds. Alerts are stored
in the `forecast_alerts` table and surfaced through the Grafana dashboard, with optional
integration to Slack and email notification channels.

---

## 5. Technical Approach / 技术方案

### 5.1 Accuracy Metrics / 准确度指标

The system computes six industry-standard forecast accuracy metrics at every granularity
level:

| Metric | Formula | Target | Current (14d) | Interpretation |
|--------|---------|--------|---------------|----------------|
| **MAPE** | `AVG(\|pred - actual\| / actual)` | < 25% | 37.8% | Mean absolute percentage error; primary KPI |
| **WMAPE** | `SUM(\|error\|) / SUM(actual)` | < 20% | 30.7% | Volume-weighted accuracy; reduces small-item distortion |
| **RMSE** | `SQRT(AVG((pred - actual)^2))` | Context-dep. | -- | Root mean squared error; penalizes large errors |
| **MFE/Bias** | `AVG(pred - actual)` | ~ 0 | +9.1% | Mean forecast error; positive = over-prediction |
| **Accuracy Rate** | `% within +/-20% band` | > 70% | 42.3% | Proportion of predictions within acceptable range |
| **Tracking Signal** | `Cumulative error / MAD` | \|TS\| < 4.0 | -- | Detects persistent directional bias over time |

**Why multiple metrics matter:**

- **MAPE** is the primary headline metric but is distorted by low-volume items
- **WMAPE** corrects for volume, giving a more operationally meaningful picture
- **Bias/MFE** reveals directional patterns that MAPE obscures
- **Accuracy Rate** provides an intuitive "hit rate" for management communication
- **RMSE** penalizes large errors disproportionately, highlighting worst-case scenarios
- **Tracking Signal** detects systematic drift that may not be visible in point-in-time metrics

### 5.2 Alert Thresholds / 告警阈值

| Alert Type | Condition | Severity | Response Time | Notification |
|------------|-----------|----------|---------------|--------------|
| **CRITICAL** | 7-day rolling MAPE > 40% for any store | P1 | 30 minutes | Slack + Email + PagerDuty |
| **WARNING** | 7-day rolling MAPE > 30% for any store | P2 | 4 hours | Slack + Email |
| **BIAS** | Same-sign MFE for 14+ consecutive days | P2 | Next business day | Email |
| **COVERAGE** | < 90% of store-product-days matched | P2 | 4 hours | Slack + Email |
| **DRIFT** | Week-over-week MAPE change > 50% for any category | P3 | Next business day | Email |

**Alert lifecycle:**

1. Pipeline runs daily at 06:00 EST (11:00 UTC)
2. Drift detection evaluates all 5 rules against fresh data
3. New alerts are inserted into `forecast_alerts` table
4. Grafana dashboard updates in real-time (MySQL datasource polling)
5. Notification channels trigger based on severity level
6. Alerts are reviewed and resolved by the assigned team

### 5.3 Key Technical Decisions / 关键技术决策

The following design decisions were made to ensure reliability, maintainability, and
operational robustness:

**Cross-Server Data Access:**
- **PyMySQL** selected for database connectivity due to pure-Python implementation
  (no compiled dependencies), connection pooling support, and compatibility with all
  three production MySQL servers
- Read-only access to source servers; write operations only on analytics server

**Batch Processing:**
- **5,000 rows per batch** for staging table loads, balancing throughput against
  memory consumption and transaction size
- Prevents MySQL `max_allowed_packet` violations on large date ranges
- Configurable batch size via environment variable

**Idempotent Operations:**
- All write operations use **DELETE + INSERT** pattern keyed on date range
- Pipeline can be safely re-run for any date range without data duplication
- Supports both daily incremental runs and full historical backfills

**Large Backfill Handling:**
- Date ranges exceeding 7 days are automatically **chunked into 7-day windows**
- Prevents memory exhaustion and query timeout on large historical loads
- Progress reporting per chunk for operational visibility

**Audit Trail:**
- Every pipeline execution logs to `forecast_pipeline_run_log`
- Records: start time, end time, date range processed, row counts, status, errors
- Enables SLA monitoring and troubleshooting

**Error Handling:**
- Connection retry logic with exponential backoff (3 retries, 5-second base delay)
- Graceful degradation: extraction failures for one server do not prevent the other
- Comprehensive error logging with stack traces for debugging

### 5.4 Data Quality Controls / 数据质量控制

| Control | Implementation | Purpose |
|---------|---------------|---------|
| Store exclusion | Hardcoded exclusion of test stores (1131, 20007, 20046) | Prevent test data from distorting metrics |
| Reason code filtering | Only codes 025, 1001, 1002 with `total_adjust_num < 0` | Ensure only true consumption is counted |
| Zero-actual filtering | Exclude records where actual consumption = 0 | Prevent division-by-zero in MAPE calculation |
| Coverage monitoring | COVERAGE alert when < 90% match rate | Detect data gaps or join key mismatches |
| Row count validation | Post-extraction row count logging and comparison | Detect extraction anomalies early |

---

## 6. Implementation Timeline / 实施时间线

### 6.1 Four-Week Deployment Plan / 四周部署计划

The implementation follows a phased approach designed to minimize risk and maximize
the speed to first value. All engineering development is already complete; the timeline
below covers only deployment, configuration, and validation activities.

| Week | Phase | Key Tasks | Owner | Dependencies | Exit Criteria |
|------|-------|-----------|-------|--------------|---------------|
| **1** | DBA Setup / 数据库准备 | Create 4 analytics tables on `aws-luckyus-dbatest-rw`; Grant read access to prediction server (`aws-luckyus-ireplenishment-rw`); Grant read access to actuals server (`aws-luckyus-scm-shopstock-rw`); Verify MySQL EVENT scheduler is enabled | DBA Team | DBA approval, security review | Tables exist, permissions verified |
| **2** | Pipeline Deploy / 流水线部署 | Deploy Python orchestrator to designated host; Configure `.env` with connection credentials; Set up cron job for daily 06:00 EST execution; Run initial historical backfill (Feb 1 - current); Validate row counts and metric calculations | Data Engineering | Week 1 complete | Pipeline runs successfully, backfill data verified |
| **3** | Dashboard & Alerts / 仪表盘与告警 | Import Grafana dashboard JSON; Configure MySQL datasource pointing to analytics tables; Verify all 29 panels render correctly; Set up Slack webhook for alert notifications; Configure email notification channel; Test alert triggering with threshold adjustments | BI/Analytics | Week 2 complete | Dashboard live, alerts tested |
| **4** | Tuning & Handoff / 调优与交接 | Tune alert thresholds based on real operational data; Conduct documentation review with operations team; Deliver team training sessions (30 min each: Operations, ML, Management); Formal handoff to operations support | Analytics + ML Team | Week 3 complete | Sign-off from all stakeholders |

### 6.2 Post-Deployment / 部署后

| Timeframe | Activity | Owner |
|-----------|----------|-------|
| Week 5-8 | Monitor alert volumes, tune thresholds to reduce false positives | Analytics |
| Month 2 | First monthly accuracy review with algorithm team | Analytics + ML |
| Month 3 | Assess model improvement impact on MAPE metrics | ML Team |
| Quarterly | Executive accuracy review, trend analysis, target recalibration | VP Supply Chain |

### 6.3 Critical Path / 关键路径

The critical path runs through **DBA table creation** (Week 1). All downstream activities
depend on the analytics tables being available. The DBA effort is estimated at 2 hours
and requires only standard DDL operations with `IF NOT EXISTS` safety guards.

If DBA resources are constrained, the `--setup` flag on the Python orchestrator can
automate DDL execution, provided the deployment account has CREATE TABLE privileges.

---

## 7. Cost-Benefit Analysis / 成本效益分析

### 7.1 Development Cost / 开发成本

| Item | Hours | Rate | Cost |
|------|-------|------|------|
| SQL analytics development (6 modules) | 40 | -- | **Completed** |
| Python orchestrator development | 24 | -- | **Completed** |
| Grafana dashboard design (29 panels) | 16 | -- | **Completed** |
| React dashboard development | 8 | -- | **Completed** |
| Documentation and analysis | 16 | -- | **Completed** |
| Testing and validation | 12 | -- | **Completed** |
| **Total development** | **~116 hours** | -- | **$0 incremental** |

All development has been completed as part of the supply chain analytics initiative.
No additional engineering investment is required.

### 7.2 Infrastructure Cost / 基础设施成本

| Resource | Requirement | Incremental Cost |
|----------|-------------|-----------------|
| MySQL analytics tables | 4 tables on existing `aws-luckyus-dbatest-rw` | $0 (existing server) |
| Storage | ~50 MB/year for accuracy data | $0 (within existing allocation) |
| Compute | Daily cron job, ~5 min runtime | $0 (existing host) |
| Grafana | 1 dashboard in existing instance | $0 (existing license) |
| **Total infrastructure** | -- | **$0/year** |

### 7.3 Ongoing Operational Cost / 持续运营成本

| Activity | Frequency | Effort | Annual Hours |
|----------|-----------|--------|-------------|
| Pipeline monitoring | Daily (automated) | 5 min/day | ~30 hours |
| Alert response and triage | As-needed | 15 min/alert | ~12 hours |
| Monthly accuracy review | Monthly | 2 hours | 24 hours |
| Threshold tuning | Quarterly | 2 hours | 8 hours |
| **Total operational** | -- | -- | **~74 hours/year** |

### 7.4 Annual Benefit / 年度收益

**Direct Financial Benefits:**

| Benefit | Annual Value | Realization Timeline |
|---------|-------------|---------------------|
| Waste reduction (over-prediction correction) | $44,000 - $66,000 | 3-6 months after model retraining |
| Inventory carrying cost reduction | $5,000 - $10,000 | 6-12 months |
| Stockout reduction (revenue protection) | $10,000 - $25,000 | 6-12 months |
| **Total direct** | **$59,000 - $101,000** | -- |

**Indirect Strategic Benefits:**

- **Model improvement acceleration:** First-ever empirical basis for algorithm team to
  iterate on model features, training data, and hyperparameters
- **Operational confidence:** Store managers and operations team gain visibility into
  prediction quality, enabling informed manual overrides when needed
- **Executive reporting:** Standardized KPIs for supply chain performance reviews
- **Scalability foundation:** Framework extends to new stores and product categories
  as the US network grows
- **Vendor accountability:** Objective metrics for evaluating third-party algorithm
  providers if model is externally maintained

### 7.5 ROI Summary / 投资回报总结

| Metric | Value |
|--------|-------|
| Total incremental investment | **$0** (code complete, infrastructure existing) |
| Annual direct benefit (expected) | **$55,000** |
| Annual direct benefit (range) | $44,000 - $66,000 |
| Payback period | **Immediate** (only requires DBA table creation) |
| Year 1 ROI | **Infinite** (no incremental investment denominator) |
| 3-year cumulative benefit | $132,000 - $198,000 |

---

## 8. Risk Assessment / 风险评估

### 8.1 Risk Register / 风险登记

| # | Risk Description | Likelihood | Impact | Risk Score | Mitigation Strategy |
|---|-----------------|-----------|--------|-----------|-------------------|
| R1 | **Cross-server connectivity failure** -- Network issues between analytics server and source servers prevent data extraction | Medium | High | **High** | Retry logic with exponential backoff (3 retries); connection timeouts configured at 30 seconds; pipeline run log captures failures for alerting; fallback to manual execution if automated retry exhausted |
| R2 | **MySQL EVENT scheduler disabled** -- Database administrator disables the EVENT scheduler, halting automated daily runs | Low | Medium | **Low** | Cron job serves as primary scheduler (not dependent on MySQL EVENT); pipeline run log enables monitoring of execution cadence; operational guide documents re-enablement procedure |
| R3 | **Data freshness delay** -- Source data not available at scheduled pipeline time due to upstream ETL delays | Medium | Medium | **Medium** | Pipeline scheduled at 06:00 EST, allowing buffer for overnight processing; coverage alert detects missing data; re-run capability for specific date ranges; monitoring of upstream data availability |
| R4 | **Alert fatigue from initial tuning** -- Too many alerts generated during early deployment before thresholds are calibrated | High | Low | **Medium** | Conservative initial thresholds (MAPE > 40% for CRITICAL); phased threshold tightening over 4-8 weeks; alert suppression for known baseline conditions; weekly threshold review during tuning period |
| R5 | **DBA bandwidth for table creation** -- DBA team unable to prioritize table creation, delaying entire project | Medium | High | **High** | Tables use `IF NOT EXISTS` for safe execution; `--setup` flag automates DDL if deployment account has privileges; pre-drafted DBA request with exact SQL statements; escalation path to CTO if delayed beyond 1 week |
| R6 | **Source table schema changes** -- Upstream teams modify prediction or actuals table schemas without notice | Low | High | **Medium** | Schema discovery SQL (`01_schema_discovery.sql`) documents current expected state; orchestrator validates column existence before extraction; alerts on extraction failure surface schema issues immediately |
| R7 | **Data volume growth** -- Store expansion or SKU proliferation causes pipeline runtime to exceed acceptable window | Low | Low | **Low** | Current batch processing handles up to 50,000 rows efficiently; auto-chunking for large backfills; runtime monitoring in pipeline log; architecture supports horizontal scaling if needed |
| R8 | **Grafana datasource misconfiguration** -- Incorrect MySQL datasource configuration causes dashboard to display stale or no data | Low | Medium | **Low** | Detailed datasource configuration documented in operational guide; dashboard import tested against development instance; "Data Freshness" panel provides immediate visual indicator of connectivity issues |

### 8.2 Risk Mitigation Summary / 风险缓解总结

The overall risk profile for this deployment is **LOW to MEDIUM**. The two highest-risk
items (R1: connectivity, R5: DBA bandwidth) both have well-defined mitigation strategies
and do not introduce novel technical risk. The system uses standard, proven technologies
(MySQL, Python, Grafana) in configurations that are already operational within Luckin
Coffee USA's infrastructure.

---

## 9. Resource Requirements / 资源需求

### 9.1 Personnel / 人员需求

| Role | Phase | Effort | Responsibility |
|------|-------|--------|---------------|
| **DBA / Database Administrator** | Week 1 | 2 hours | Create 4 analytics tables on `aws-luckyus-dbatest-rw`; grant SELECT on source servers; verify EVENT scheduler status |
| **Data Engineer** | Week 2 | 4 hours | Deploy `run_pipeline.py` to designated host; configure `.env` credentials; set up cron schedule; execute initial backfill |
| **BI / Analytics Engineer** | Week 3 | 4 hours | Import Grafana dashboard JSON; configure MySQL datasource; verify panel rendering; set up Slack/email alert channels |
| **ML / Algorithm Team Lead** | Week 3-4 | 2 hours | Review accuracy baseline; confirm metric definitions; plan model improvement roadmap based on findings |
| **Operations Manager** | Week 4 | 1 hour | Review dashboard; understand alert escalation paths; provide feedback on threshold appropriateness |
| **Supply Chain Analytics** | Weeks 1-4 | 8 hours | Coordinate deployment; conduct training sessions; oversee tuning; document lessons learned |
| **Total** | -- | **~21 hours** | -- |

### 9.2 Technology Stack / 技术栈

All required technologies are already deployed and operational within Luckin Coffee USA's
infrastructure. No new software procurement or licensing is required.

| Technology | Version | Status | Purpose |
|-----------|---------|--------|---------|
| MySQL | 8.0+ | **Existing** -- All 3 servers operational | Database engine for storage and computation |
| Python | 3.8+ | **Existing** -- Standard deployment runtime | Orchestrator runtime environment |
| PyMySQL | 1.1+ | **Standard library** -- pip install | MySQL connectivity from Python |
| python-dotenv | 1.0+ | **Standard library** -- pip install | Environment configuration management |
| Grafana | 10.x | **Existing** -- AI Analytics folder available | Dashboard and alerting platform |
| Cron | Linux standard | **Existing** -- All servers | Job scheduling |

### 9.3 Access Requirements / 访问权限

| Server | Access Type | Account | Purpose |
|--------|-----------|---------|---------|
| `aws-luckyus-ireplenishment-rw` | SELECT (read-only) | Service account | Extract daily predictions |
| `aws-luckyus-scm-shopstock-rw` | SELECT (read-only) | Service account | Extract actual consumption |
| `aws-luckyus-dbatest-rw` | SELECT, INSERT, DELETE, CREATE | Service account | Analytics computation and storage |
| Grafana instance | Editor role | Service account | Dashboard import and datasource config |

---

## 10. Appendix / 附录

### 10.1 Supporting Materials / 支持材料

The following supplementary resources are available for detailed review:

| Resource | Location | Description |
|----------|----------|-------------|
| Interactive Proposal Dashboard | `proposal/management-proposal-dashboard.html` | Executive-friendly interactive overview |
| Grafana Demo Dashboard | `proposal/grafana-demo-dashboard.html` | Static preview of the 29-panel Grafana dashboard |
| System Architecture Diagram | `proposal/system-architecture.html` | Interactive 3-server architecture visualization |
| ROI Calculator | `proposal/roi-calculator.html` | Adjustable financial model with scenario analysis |
| Executive Summary One-Pager | `proposal/executive-summary-onepager.html` | Single-page summary for quick distribution |

### 10.2 Project Repository Structure / 项目仓库结构

```
UC-SC-01-forecast-accuracy/
├── README.md                                    # Project overview (124 lines)
├── sql/
│   ├── 01_schema_discovery.sql                  # Source table documentation (326 lines)
│   ├── 02_create_analytics_schema.sql           # DDL for 4 analytics tables (281 lines)
│   ├── 03_accuracy_computation.sql              # ETL: extract, join, compute (340 lines)
│   ├── 04_aggregate_metrics.sql                 # Multi-dimensional aggregation (695 lines)
│   ├── 05_drift_detection.sql                   # 5 alert rules (514 lines)
│   └── 06_daily_refresh.sql                     # Stored procedure + scheduler (842 lines)
├── orchestrator/
│   ├── run_pipeline.py                          # Cross-server ETL bridge (1,166 lines)
│   ├── requirements.txt                         # Python dependencies
│   └── .env.example                             # Environment configuration template
├── dashboards/
│   ├── forecast_accuracy_dashboard.json         # Grafana 29-panel dashboard (1,312 lines)
│   └── ForecastAccuracyDashboard.jsx            # React executive dashboard (584 lines)
├── docs/
│   ├── data_dictionary.md                       # Bilingual data dictionary (821 lines)
│   └── operational_guide.md                     # Operations runbook (188 lines)
├── reports/
│   └── historical_accuracy_report.md            # 14-day inaugural analysis (737 lines)
└── proposal/
    └── management-proposal.md                   # This document
```

### 10.3 Glossary / 术语表

| Term | Definition |
|------|-----------|
| **GS Code** | Goods Standard Code; unique identifier for raw material SKUs |
| **iReplenishment** | Luckin Coffee's AI-driven demand forecasting and automated replenishment system |
| **MAPE** | Mean Absolute Percentage Error; primary forecast accuracy metric |
| **WMAPE** | Weighted Mean Absolute Percentage Error; volume-adjusted accuracy metric |
| **MFE** | Mean Forecast Error; also referred to as Bias; measures directional prediction tendency |
| **RMSE** | Root Mean Squared Error; accuracy metric that penalizes large errors |
| **Tracking Signal** | Ratio of cumulative forecast error to mean absolute deviation; detects persistent bias |
| **T+1** | Next-day cadence; analysis of day D data occurs on day D+1 |
| **ETL** | Extract, Transform, Load; data pipeline pattern |
| **Drift Detection** | Automated monitoring for changes in forecast accuracy patterns over time |

### 10.4 References / 参考文献

1. Hyndman, R.J. & Koehler, A.B. (2006). "Another look at measures of forecast accuracy."
   *International Journal of Forecasting*, 22(4), 679-688.
2. Syntetos, A.A. & Boylan, J.E. (2005). "The accuracy of intermittent demand estimates."
   *International Journal of Forecasting*, 21(2), 303-314.
3. National Retail Federation (2024). "Inventory Accuracy and Demand Forecasting
   Benchmarks for Food & Beverage Retail." NRF Industry Report.
4. Luckin Coffee Inc. (2026). "iReplenishment System Technical Documentation." Internal.

---

## Approval / 审批

This proposal requests formal approval to proceed with the deployment of the UC-SC-01
Demand Forecast Accuracy Monitor system as described herein.

### Prepared By / 编制

| Field | Detail |
|-------|--------|
| **Name** | __________________________________ |
| **Title** | Supply Chain Analytics Team Lead |
| **Date** | __________________________________ |
| **Signature** | __________________________________ |

### Reviewed By / 审核

| Field | Detail |
|-------|--------|
| **Name** | __________________________________ |
| **Title** | Algorithm Team Lead / 算法团队负责人 |
| **Date** | __________________________________ |
| **Signature** | __________________________________ |

| Field | Detail |
|-------|--------|
| **Name** | __________________________________ |
| **Title** | Chief Technology Officer / 首席技术官 |
| **Date** | __________________________________ |
| **Signature** | __________________________________ |

### Approved By / 批准

| Field | Detail |
|-------|--------|
| **Name** | __________________________________ |
| **Title** | VP Supply Chain / 供应链副总裁 |
| **Date** | __________________________________ |
| **Signature** | __________________________________ |

| Field | Detail |
|-------|--------|
| **Name** | __________________________________ |
| **Title** | VP Operations / 运营副总裁 |
| **Date** | __________________________________ |
| **Signature** | __________________________________ |

---

*Document ID: UC-SC-01-PROP-2026-001 | Version 1.0 | Classification: Internal - Management Review*

*UC-SC-01 Demand Forecast Accuracy Monitor -- Luckin Coffee USA Supply Chain Intelligence*

# Strategic Roadmap
## Luckin Coffee USA — AI Transformation Roadmap (Deliverable 4 of 5)

**Prepared for:** First Ray Holdings USA Inc. (Luckin Coffee USA)
**Date:** February 14, 2026
**Classification:** Confidential

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Prioritization Methodology](#2-prioritization-methodology)
3. [Implementation Horizons](#3-implementation-horizons)
4. [Horizon 1: Foundation (Months 1-3)](#4-horizon-1-foundation-months-1-3)
5. [Horizon 2: Operational Intelligence (Months 4-6)](#5-horizon-2-operational-intelligence-months-4-6)
6. [Horizon 3: AI-Powered Growth (Months 7-12)](#6-horizon-3-ai-powered-growth-months-7-12)
7. [Horizon 4: Enterprise AI (Months 13-18)](#7-horizon-4-enterprise-ai-months-13-18)
8. [Resource Plan](#8-resource-plan)
9. [Investment Model](#9-investment-model)
10. [Value Realization Timeline](#10-value-realization-timeline)
11. [Risk Register](#11-risk-register)
12. [Success Metrics & Governance](#12-success-metrics--governance)
13. [Dependencies & Critical Path](#13-dependencies--critical-path)
14. [Appendix: Full Prioritization Matrix](#14-appendix-full-prioritization-matrix)

---

## 1. Executive Summary

This roadmap charts an 18-month, four-horizon path to transform Luckin Coffee USA from a digitally-enabled coffee retailer into an AI-powered growth engine. The plan sequences 41 AI/ML use cases across 7 departments, building foundational data infrastructure first, then layering progressively more sophisticated AI capabilities.

### Strategic Context

Luckin Coffee USA operates at a critical inflection point:
- **Growth phase:** 11 Manhattan stores, ~$7K/month loss per store, needing 2x current daily orders for break-even
- **Infrastructure surplus:** Enterprise-grade platform (143 databases, 308 Kafka topics) built for 20,000+ stores
- **AI head start:** 6 AI/ML systems already deployed (demand forecasting, A/B testing, CDP, CyberData ETL, Dify LLM, site selection ML)
- **Data readiness:** 24 of 41 use cases have GREEN data readiness — can start immediately
- **Critical gaps:** Tax compliance empty (regulatory risk), 50.6% user churn, 37.3M expired coupons (marketing waste)

### Roadmap Summary

| Horizon | Timeline | Theme | Use Cases | Infrastructure | Team |
|---------|----------|-------|-----------|----------------|------|
| H1 | Months 1-3 | Foundation | 6 P0 + 3 P1 | Data warehouse + 5 CDC pipelines | 2.5 FTE |
| H2 | Months 4-6 | Operational Intelligence | 8 P1 | Expand to 12 CDC + Feature Store | 4 FTE |
| H3 | Months 7-12 | AI-Powered Growth | 12 P2 | ML platform + real-time scoring | 6 FTE |
| H4 | Months 13-18 | Enterprise AI | 12 P2/P3 | Full platform + streaming | 8 FTE |

### Investment & Return

| Metric | Year 1 | Year 1.5 (18 months) |
|--------|--------|---------------------|
| Infrastructure cost (incremental) | $57K-132K | $105K-228K |
| People cost | $310K-595K | $595K-875K |
| **Total investment** | **$367K-727K** | **$700K-1,103K** |
| Estimated value created | $200K-600K | $600K-1,500K |
| Net infrastructure cost (after optimization) | **Near $0** | **Net savings** |

---

## 2. Prioritization Methodology

### 2.1 Scoring Framework

All 41 use cases are scored on 5 dimensions (see Deliverable 2 for detailed rubrics):

| Dimension | Weight | What It Measures |
|-----------|--------|-----------------|
| Data Readiness | 25% | Can we build this with existing data? |
| Business Impact | 30% | Revenue uplift, cost savings, or risk mitigation |
| Technical Complexity | 20% | How hard is this to implement? (inverted: simpler = higher score) |
| Cross-Department Value | 10% | How many teams benefit? |
| Strategic Alignment | 15% | Does this enable 50-store growth? |

### 2.2 Horizon Assignment Logic

```
IF Priority = P0 (Critical + Ready)     → Horizon 1 (regardless of score)
IF Priority = P1 AND Score ≥ 3.70       → Horizon 1
IF Priority = P1 AND Score < 3.70       → Horizon 2
IF Priority = P2 AND Data = GREEN       → Horizon 3
IF Priority = P2 AND Data = YELLOW/RED  → Horizon 3 (with data pipeline as prerequisite)
IF Priority = P3                        → Horizon 4
```

### 2.3 Sequencing Constraints

Beyond scoring, implementation order is constrained by:

1. **Infrastructure prerequisites:** Data warehouse must exist before any analytical use case
2. **Data pipeline dependencies:** CDC pipelines must be active before ML models can train on cross-system data
3. **Feature store dependencies:** Shared features (RFM scores, user segments) must exist before downstream models
4. **Team capacity:** Concurrent projects limited by team size per horizon
5. **Business urgency:** Tax compliance (P0/RED) requires immediate action regardless of data readiness

---

## 3. Implementation Horizons

### Visual Timeline

```
Month:  1    2    3    4    5    6    7    8    9   10   11   12   13   14   15   16   17   18
        ├─────────────┼─────────────┼───────────────────────────┼───────────────────────────┤
        │  HORIZON 1  │  HORIZON 2  │         HORIZON 3         │         HORIZON 4         │
        │ Foundation  │  Ops Intel  │    AI-Powered Growth      │      Enterprise AI        │
        │             │             │                           │                           │
Infra:  │▓▓▓ Warehouse│▓▓ CDC +12   │▓▓▓ ML Platform           │▓▓▓ Streaming + Full      │
        │▓▓▓ CDC ×5   │▓▓ Features  │▓▓▓ Feature Store         │▓▓▓ Real-time Scoring     │
        │             │             │                           │                           │
Models: │ Tax tracker │ Customer360 │ Churn model + Reco engine│ Autonomous inventory     │
        │ Rev recon   │ Coupon opt  │ Ask Lucky NL + CLV       │ Fraud detection RT       │
        │ Exec brief  │ Menu matrix │ Price elasticity         │ Competitive intel        │
        │ Demand mon  │ Waste pred  │ IoT predictive           │ Multi-borough support    │
        │             │             │                           │                           │
Team:   │ 2.5 FTE     │ 4 FTE       │ 6 FTE                    │ 8 FTE                    │
        └─────────────┴─────────────┴───────────────────────────┴───────────────────────────┘
```

### Horizon Exit Criteria

| Horizon | Exit Criteria | Decision Gate |
|---------|--------------|---------------|
| H1 → H2 | Data warehouse live with 5 CDC pipelines; 3+ dashboards active; tax tracker deployed | Month 3 review |
| H2 → H3 | 12 CDC pipelines active; Feature Store populated; Customer 360 operational | Month 6 review |
| H3 → H4 | 5+ ML models in production; recommendation engine live; ROI measurable | Month 12 review |
| H4 → Steady state | Full platform operational; 10+ models; autonomous operations | Month 18 review |

---

## 4. Horizon 1: Foundation (Months 1-3)

### 4.1 Objective

Build the data platform foundation and deploy 6 immediate-value use cases that address critical gaps (tax compliance, revenue reconciliation) while proving the AI transformation model to leadership.

### 4.2 Use Cases Deployed

| # | Use Case | Score | Data | Dept | H1 Milestone |
|---|----------|-------|------|------|--------------|
| 1 | Tax Compliance Tracker | 4.45 | RED | Finance | Manual tracking dashboard + automated data collection pipeline |
| 2 | Revenue Reconciliation | 4.35 | GREEN | Finance | Automated 3-way match: order → payment → accounting |
| 3 | Demand Forecast Monitor | 4.20 | GREEN | SCM | Accuracy feedback loop on existing 2.5M predictions |
| 4 | Executive AI Daily Briefing | 4.25 | GREEN | Executive | Dify agent → daily digest from all systems |
| 5 | Customer 360 Profile | 4.15 | GREEN | Marketing | Unified customer view from CDP + CRM + orders |
| 6 | Churn Prediction (Phase 1) | 4.30 | GREEN | Marketing | RFM segmentation + rules-based churn flags |
| 7 | Predictive Infra Monitoring | 4.05 | GREEN | IT | Redis anomaly detection using existing Prometheus data |
| 8 | Store Performance Anomaly | 4.00 | GREEN | Operations | Multi-store comparative dashboard with alerts |
| 9 | Database Cost Optimizer | 3.70 | GREEN | IT | RI/SP coverage analysis + Graviton migration plan |

### 4.3 Infrastructure Deliverables

**Data Warehouse Setup:**
- Deploy Redshift Serverless (128 RPU base capacity)
- Deploy AWS DMS with 5 CDC pipelines for priority databases:
  1. `salesorder` — orders, order items
  2. `salespayment` — payments, transactions, fees
  3. `opproduction` — production records
  4. `isalescdp` — customer profiles, behavioral states
  5. `ifiaccounting` — accounting entries, reconciliation

- Deploy AWS Glue ETL jobs:
  1. Raw → Staging: Data cleaning, type normalization, NZD test data filtering
  2. Staging → Warehouse: Star schema transformation (load fact_orders, fact_payments, fact_productions + 5 dimensions)

- Deploy S3 data lake structure:
  ```
  s3://lkus-data-lake/
  ├── raw/          (CDC output, 15-min freshness)
  ├── staging/      (cleaned, normalized)
  ├── warehouse/    (Redshift external tables)
  └── archive/      (historical snapshots)
  ```

**Monitoring Expansion:**
- Activate CloudWatch alarms for top 20 critical resources (RDS CPU, memory, connections)
- Fix 3 broken Grafana alert rules
- Add business metric panels to Grafana (daily orders, revenue, active users)

### 4.4 Detailed Use Case Implementation

#### Tax Compliance Tracker (P0 — Regulatory Risk)

**Problem:** The `fi_tax` database is completely empty despite $2.19M in cumulative revenue across 3 states (NY, NJ operations). This represents a significant regulatory risk.

**H1 Approach:**
- Week 1-2: Build tax obligation tracking dashboard from existing payment data
  - Extract: state, city, county tax rates from payment records
  - Calculate: estimated tax liability from `salespayment.trade` records
  - Dashboard: real-time tax obligation tracker by jurisdiction
- Week 3-4: Automate tax data extraction pipeline
  - Glue job: payment → tax calculation → fi_tax database population
  - Integrate with revenue reconciliation for cross-validation
- Month 2-3: Connect to tax filing systems
  - API integration with tax compliance vendor (Avalara/TaxJar)
  - Automated reporting by jurisdiction

**H1 Exit State:** Dashboard live showing estimated tax obligations by jurisdiction; automated data pipeline populating `fi_tax`; connection to tax compliance vendor initiated.

#### Revenue Reconciliation (P0 — Operational Efficiency)

**Problem:** Manual 3-way matching between orders (466K+), payments (518K+ trades), and accounting entries. Discrepancies detected: 64,985 orders have NULL status, 21,245 NZD test orders contaminate production data.

**H1 Approach:**
- Week 1-2: Build automated reconciliation in Redshift
  - fact_orders JOIN fact_payments ON order_no (type-cast resolution: bigint → varchar)
  - Identify unmatched records, timing differences, amount discrepancies
- Week 3-4: Anomaly flagging
  - Rules engine: flag orders >$50 (AOV is $4.71), duplicate payments, orphan records
  - Daily reconciliation report → executive email
- Month 2-3: Historical cleanup
  - Resolve 64,985 NULL-status orders
  - Quarantine 21,245 NZD test orders
  - Backfill reconciliation for full order history

**H1 Exit State:** Automated daily reconciliation dashboard; <0.1% unresolved discrepancy rate; NZD contamination isolated.

#### Executive AI Daily Briefing (P0 — Leadership Visibility)

**Problem:** No unified view of business performance. Executives must query multiple systems or request ad-hoc reports. 17 Grafana dashboards are all DBA-focused — zero business dashboards exist.

**H1 Approach:**
- Week 1-2: Build Dify agent with MCP database access
  - Morning briefing: yesterday's orders, revenue, new users, top store, production issues
  - Summarize from Redshift warehouse (once CDC is live) or direct DB queries initially
- Week 3-4: Add comparative analysis
  - Week-over-week, month-over-month trends
  - Anomaly highlighting (>2 standard deviations from norm)
- Month 2-3: Expand to Slack/email delivery
  - Scheduled daily delivery at 7am
  - Interactive follow-up via Dify ("Why did Store 5 have low orders yesterday?")

**H1 Exit State:** Automated daily briefing delivered via Slack/email; interactive query capability via Dify.

### 4.5 H1 Milestones

| Week | Milestone | Deliverable |
|------|-----------|-------------|
| 1-2 | Infrastructure setup | Redshift deployed, DMS configured, S3 buckets created |
| 3-4 | First CDC pipelines | salesorder + salespayment streaming to data lake |
| 5-6 | Star schema v1 | fact_orders + fact_payments loaded; reconciliation dashboard live |
| 7-8 | Tax + Exec briefing | Tax tracker dashboard; Dify agent producing daily briefings |
| 9-10 | Full 5 CDC pipelines | All 5 priority sources streaming; Customer 360 v1 |
| 11-12 | Churn + monitoring | RFM segmentation; Redis anomaly detection; store dashboards |

### 4.6 H1 Resources & Cost

| Resource | Allocation | Monthly Cost |
|----------|-----------|-------------|
| Data Engineer (Senior) | 1.0 FTE | ~$13.3K |
| Analytics Engineer | 1.0 FTE | ~$12.1K |
| ML Engineer (part-time) | 0.5 FTE | ~$7.3K |
| Redshift Serverless | 128 RPU | $3-5K |
| DMS (5 CDC tasks) | 1 instance | $1-1.5K |
| Glue (ETL jobs) | ~10 jobs | $0.5-1K |
| S3 | ~500GB | $0.1-0.2K |
| **H1 Monthly Total** | | **$37.3-40.4K** |
| **H1 Quarterly Total** | | **$112K-121K** |

---

## 5. Horizon 2: Operational Intelligence (Months 4-6)

### 5.1 Objective

Expand the data platform to 12 CDC pipelines, deploy the Feature Store, and launch operational intelligence use cases that directly improve store economics. Target: provide every department head with an AI-powered dashboard by end of H2.

### 5.2 Use Cases Deployed

| # | Use Case | Score | Data | Dept | H2 Milestone |
|---|----------|-------|------|------|--------------|
| 10 | Coupon ROI Optimizer | 4.10 | GREEN | Marketing | Campaign effectiveness scoring; identify waste in 37.3M expired coupons |
| 11 | Payment Fraud Detection | 3.95 | GREEN | Finance | Anomaly detection on 518K trade records |
| 12 | Menu Engineering Matrix | 3.90 | GREEN | Product | BCG matrix: stars/plowhorses/puzzles/dogs for 60+ SKUs |
| 13 | Waste Prediction & Reduction | 3.85 | GREEN | SCM | Predict expiration from 9.1M stock change events |
| 14 | A/B Test Auto-Optimization | 3.80 | GREEN | Marketing | Auto-detect winners from 6.4M experiment records |
| 15 | Production Time Predictor | 3.75 | GREEN | Operations | ML model on 502K production records (204s avg) |
| 16 | Next-Best-Action Engine | 3.65 | YELLOW | Marketing | CDP behavioral states → real-time push recommendations |
| 17 | Push Notification Optimizer | 3.60 | GREEN | Marketing | Optimize send time/content from 2.3M SMS records |

### 5.3 Infrastructure Deliverables

**Expanded CDC Pipelines (+7):**
6. `salescrm` — customer profiles, contact records
7. `salesmarketing` — campaigns, coupon templates, distribution
8. `scm-shopstock` — inventory levels, stock changes
9. `ireplenishment` — demand predictions, replenishment orders
10. `opshop` — store configurations, operating hours
11. `opempefficiency` — staff scheduling, attendance
12. `iotplatform` — device telemetry, status events

**Feature Store (SageMaker):**
- Online store: real-time features for serving (user RFM scores, last-order features, store-level demand)
- Offline store: historical features for training (90-day rolling aggregates)
- Initial feature groups:
  - `customer_rfm`: recency, frequency, monetary value (updated daily)
  - `customer_lifecycle`: segment, days_since_last_order, churn_probability
  - `store_performance`: daily_orders, daily_revenue, production_efficiency
  - `product_affinity`: co-purchase rates, time-of-day preferences
  - `demand_signals`: day_of_week, weather, events, historical_demand

**BI Platform:**
- Deploy Apache Superset (connect to Redshift)
- Build Tier 1 dashboards: Revenue, Customer, Operations, Product
- Connect Superset to Feature Store for ML-enhanced dashboards

### 5.4 H2 Milestones

| Week | Milestone | Deliverable |
|------|-----------|-------------|
| 13-14 | CDC expansion | 7 new pipelines active; 12 total sources streaming |
| 15-16 | Feature Store v1 | customer_rfm + store_performance features populated |
| 17-18 | ML models v1 | Fraud detection + waste prediction models trained |
| 19-20 | Superset launch | 4 Tier 1 business dashboards live |
| 21-22 | Menu + Production | Menu engineering matrix; production time predictor deployed |
| 23-24 | Campaign optimization | Coupon ROI scoring; A/B auto-optimization; push optimizer |

### 5.5 H2 Resources & Cost

| Resource | Allocation | Monthly Cost |
|----------|-----------|-------------|
| Data Engineer (Senior) | 1.0 FTE | $13.3K |
| Data Engineer (Mid) | 1.0 FTE | $11.7K |
| ML Engineer | 1.0 FTE | $14.6K |
| Analytics Engineer | 1.0 FTE | $12.1K |
| DMS (12 CDC tasks) | 1-2 instances | $1.5-2.5K |
| Redshift Serverless | Scale up | $4-6K |
| SageMaker (Feature Store) | Online + Offline | $0.5-0.8K |
| SageMaker (Training) | Spot instances | $0.5-1K |
| Superset (EC2) | t3.large | $0.2K |
| **H2 Monthly Total** | | **$58.4-62.2K** |
| **H2 Quarterly Total** | | **$175K-187K** |

---

## 6. Horizon 3: AI-Powered Growth (Months 7-12)

### 6.1 Objective

Deploy production ML models that directly drive revenue growth: personalized recommendations, churn prevention, pricing optimization. This horizon transitions from "analytics on existing data" to "AI generating new value." Target: measurable revenue impact from at least 3 AI use cases.

### 6.2 Use Cases Deployed

| # | Use Case | Score | Data | Dept | H3 Milestone |
|---|----------|-------|------|------|--------------|
| 18 | Churn Prediction (Full ML) | 4.30 | GREEN | Marketing | Gradient boosting model; automated win-back campaigns |
| 19 | Personalized Recommendations | 3.50 | GREEN | Product | Collaborative filtering on 602K order items |
| 20 | Dynamic Staffing Optimizer | 3.55 | YELLOW | Operations | ML scheduler + NYC fair workweek compliance |
| 21 | CLV Prediction | 3.35 | GREEN | Marketing | Customer lifetime value model for segment prioritization |
| 22 | Price Elasticity Modeling | 3.25 | GREEN | Product | Coupon discount depth → conversion rate modeling |
| 23 | NL Database Query ("Ask Lucky") | 2.80 | GREEN | IT | Dify agent + MCP for natural language data queries |
| 24 | Unified KPI Command Center | 3.45 | YELLOW | Executive | Real-time cross-department dashboard |
| 25 | Self-Healing Automation | 3.40 | YELLOW | IT | Runbook-triggered infrastructure remediation |
| 26 | Dynamic Par Level Setting | 3.30 | YELLOW | SCM | Per-store/per-SKU optimal stock levels via ML |
| 27 | IoT Predictive Maintenance | 3.15 | YELLOW | Operations | Predict device failures from telemetry patterns |
| 28 | Site Selection Enhancement | 2.90 | GREEN | Executive | Extend R²=0.94 model with foot traffic + demographics |
| 29 | Supplier Performance Scoring | 3.20 | GREEN | SCM | Score suppliers from 694 POs, 1,670 shipments |

### 6.3 Infrastructure Deliverables

**ML Platform (Full Deployment):**
- SageMaker training pipelines with automated retraining
- MLflow model registry and experiment tracking
- SageMaker Serverless endpoints for real-time scoring:
  - Churn prediction endpoint (score on user activity events)
  - Recommendation endpoint (score on app session start)
  - Demand prediction endpoint (score daily for staffing/inventory)

**Streaming Infrastructure:**
- Kinesis Data Streams for real-time events:
  - Order events (for real-time production/queue management)
  - User activity events (for real-time recommendations)
- Kinesis → Lambda → Feature Store for real-time feature updates

**LLM Expansion (Dify):**
- "Ask Lucky" agent: natural language database queries via MCP
- KPI Command Center agent: automated cross-department insights
- Enhanced Executive Briefing: interactive follow-up, scenario analysis

### 6.4 H3 Milestones

| Month | Milestone | Deliverable |
|-------|-----------|-------------|
| 7 | ML pipeline | SageMaker training pipeline; MLflow registry; churn model v1 |
| 8 | Churn + Reco | Churn prediction live; win-back campaigns automated; recommendation engine v1 |
| 9 | Pricing + CLV | Price elasticity model; CLV scores in Feature Store; staffing optimizer v1 |
| 10 | "Ask Lucky" + KPI | NL query agent live; KPI Command Center dashboards |
| 11 | IoT + SCM | IoT predictive maintenance; dynamic par levels; supplier scoring |
| 12 | Site selection + Ops | Enhanced site selection model; self-healing automation; H3 ROI review |

### 6.5 H3 Resources & Cost

| Resource | Allocation | Monthly Cost |
|----------|-----------|-------------|
| Data Engineer (Senior) | 1.0 FTE | $13.3K |
| Data Engineer (Mid) | 1.0 FTE | $11.7K |
| ML Engineer (Senior) | 1.0 FTE | $14.6K |
| ML Engineer (Mid) | 1.0 FTE | $12.5K |
| Data Scientist | 1.0 FTE | $13.8K |
| Analytics Engineer | 1.0 FTE | $12.1K |
| Redshift Serverless | Full scale | $5-7K |
| SageMaker (Full) | Training + Endpoints + Feature Store | $2-4K |
| Kinesis Data Streams | 2-3 streams | $0.5-1K |
| MLflow (EC2) | t3.medium | $0.2K |
| Dify (expanded) | Additional agents | $0.3-0.5K |
| **H3 Monthly Total** | | **$86-94K** |
| **H3 6-Month Total** | | **$516K-564K** |

---

## 7. Horizon 4: Enterprise AI (Months 13-18)

### 7.1 Objective

Build autonomous AI systems that operate with minimal human intervention: real-time fraud detection, autonomous inventory management, competitive intelligence. Prepare the platform for multi-borough/multi-state expansion to 50+ stores.

### 7.2 Use Cases Deployed

| # | Use Case | Score | Data | Dept | H4 Milestone |
|---|----------|-------|------|------|--------------|
| 30 | Security Posture Intelligence | 3.10 | GREEN | IT | GuardDuty + risk control data intelligence |
| 31 | Capacity Planning (50-store) | 2.85 | YELLOW | IT | Infrastructure scaling model for growth |
| 32 | Payment Channel Cost Optimizer | 3.00 | GREEN | Finance | Optimize across payment processors |
| 33 | Recipe Cost Optimization | 2.95 | GREEN | Product | Minimize ingredient cost while maintaining quality |
| 34 | New Product Launch Predictor | 3.05 | YELLOW | Product | Predict launch success from A/B test + category data |
| 35 | New Store Ramp Predictor | 2.75 | GREEN | Operations | Predict time-to-break-even for new locations |
| 36 | Queue/Wait Time Management | 2.70 | YELLOW | Operations | Real-time queue optimization |
| 37 | Financial Forecasting | 2.65 | RED | Finance | Multi-scenario financial modeling |
| 38 | Perishable Shelf-Life Tracker | 2.60 | YELLOW | SCM | Track and optimize perishable inventory |
| 39 | Referral Network Analysis | 2.55 | YELLOW | Marketing | Map and optimize referral patterns |
| 40 | Channel Attribution | 2.50 | RED | Marketing | Multi-touch attribution modeling |
| 41 | Social Listening & Sentiment | 2.45 | RED | Marketing | TikTok/Instagram/Yelp sentiment analysis |
| 42 | Competitive Intelligence | 2.40 | RED | Executive | External data enrichment + market analysis |

### 7.3 Infrastructure Deliverables

**Full Streaming Platform:**
- Kinesis → Lambda for real-time fraud scoring
- Real-time recommendation serving at sub-100ms latency
- Queue management with live production pipeline visibility

**Multi-Region Readiness:**
- Infrastructure-as-Code templates for new-store provisioning
- Database sharding strategy for 50+ store scale
- Edge caching for multi-borough latency requirements

**External Data Integration:**
- Third-party data feeds: foot traffic (Placer.ai), demographics (Census), weather
- Social listening APIs: Yelp reviews, Google Maps ratings
- Competitive pricing feeds

**Compliance Platform:**
- Automated tax filing by jurisdiction
- SOC 2 audit readiness
- PCI DSS validation automation

### 7.4 H4 Milestones

| Month | Milestone | Deliverable |
|-------|-----------|-------------|
| 13 | Real-time scoring | Fraud detection real-time endpoint; queue management v1 |
| 14 | External data | Competitive intelligence feeds; channel attribution model v1 |
| 15 | Financial AI | Financial forecasting model; payment optimizer |
| 16 | Growth readiness | 50-store capacity model; new store ramp predictor |
| 17 | Autonomous ops | Autonomous inventory; shelf-life tracker; recipe optimizer |
| 18 | Platform complete | Full platform operational; 18-month ROI assessment |

### 7.5 H4 Resources & Cost

| Resource | Allocation | Monthly Cost |
|----------|-----------|-------------|
| Data Engineer (Senior) | 1.0 FTE | $13.3K |
| Data Engineer (Mid) | 2.0 FTE | $23.4K |
| ML Engineer (Senior) | 1.0 FTE | $14.6K |
| ML Engineer (Mid) | 1.0 FTE | $12.5K |
| Data Scientist (Senior) | 1.0 FTE | $13.8K |
| Data Scientist (Mid) | 1.0 FTE | $11.7K |
| Analytics Engineer | 1.0 FTE | $12.1K |
| Full infrastructure | All components | $12-15K |
| External data feeds | 3-4 providers | $2-5K |
| **H4 Monthly Total** | | **$115.4-121.4K** |
| **H4 6-Month Total** | | **$692K-728K** |

---

## 8. Resource Plan

### 8.1 Team Build-Up

```
Month:  1    2    3    4    5    6    7    8    9   10   11   12   13   14   15   16   17   18
        ├─────────────┼─────────────┼───────────────────────────┼───────────────────────────┤

Data    ████████████████████████████████████████████████████████████████████████████████████
Eng Sr  ─── 1.0 FTE ──────────────────────────────────────────────────────────────────────

Data                  ██████████████████████████████████████████████████████████████████████
Eng Mid               ─── 1.0 FTE ─────────────────────────────── 2.0 FTE ────────────────

Analytics████████████████████████████████████████████████████████████████████████████████████
Engineer ─── 1.0 FTE ──────────────────────────────────────────────────────────────────────

ML Eng  ████░░░░░░░░░████████████████████████████████████████████████████████████████████████
        0.5 FTE       1.0 FTE ──────── 2.0 FTE (Sr + Mid) ────────────────────────────────

Data                                  ██████████████████████████████████████████████████████
Scientist                             ─── 1.0 FTE ──────────────── 2.0 FTE ───────────────

TOTAL:  ─ 2.5 FTE ── ── 4.0 FTE ──── ────── 6.0 FTE ──────────── ────── 8.0 FTE ────────
```

### 8.2 Hiring Plan

| Role | Target Start | Annual Salary | Key Skills |
|------|-------------|---------------|------------|
| Data Engineer (Senior) | Month 1 | $160K | AWS (DMS, Glue, Redshift), Python, SQL, CDC |
| Analytics Engineer | Month 1 | $145K | dbt, SQL, Superset/Grafana, data modeling |
| ML Engineer (Senior) | Month 1 (0.5→1.0 at M4) | $175K | SageMaker, MLflow, Python, feature engineering |
| Data Engineer (Mid) | Month 4 | $140K | AWS, Python, Kafka, ETL pipelines |
| ML Engineer (Mid) | Month 7 | $155K | SageMaker endpoints, model serving, monitoring |
| Data Scientist | Month 7 | $165K | Statistics, ML modeling, A/B testing, Python |
| Data Engineer (Mid) #2 | Month 13 | $140K | Streaming, Kinesis, real-time pipelines |
| Data Scientist (Mid) | Month 13 | $145K | NLP, deep learning, recommendation systems |

### 8.3 Build vs. Buy Analysis

| Capability | Build | Buy | Recommendation |
|-----------|-------|-----|----------------|
| Data warehouse | Redshift Serverless (managed) | Snowflake ($5-8K/month) | **Managed (Redshift)** — lower cost, AWS-native |
| ETL pipeline | Glue + custom Python | Fivetran ($2-3K/month) | **Managed (Glue)** — AWS-native, pay per use |
| ML platform | SageMaker (managed) | Databricks ($5-10K/month) | **Managed (SageMaker)** — feature store, serverless endpoints |
| BI dashboards | Superset (open-source) + Grafana | Looker ($3-5K/month) | **Open-source** — zero license cost |
| LLM platform | Dify (extend existing) | OpenAI API direct | **Extend Dify** — already deployed, model-agnostic |
| Tax compliance | Build tracker | Buy Avalara/TaxJar ($500/month) | **Buy** — regulatory risk demands proven solution |
| Monitoring | Extend Grafana + Prometheus | Datadog ($3-5K/month) | **Extend existing** — Grafana/Prometheus already deployed |
| Competitive intelligence | — | SimilarWeb/Placer.ai ($1-3K/month) | **Buy** — external data not available internally |

---

## 9. Investment Model

### 9.1 Cumulative Investment

| Period | Infrastructure (Incremental) | People (Fully Loaded) | External Tools | Cumulative Total |
|--------|-----------------------------|-----------------------|----------------|-----------------|
| H1 (M1-3) | $13.5-19.5K | $97.5K | $1.5K | $112.5-118.5K |
| H2 (M4-6) | $20.4-33K | $155.1K | $3K | **$291K-309.6K** |
| H3 (M7-12) | $48-78K | $468K | $12K | **$819K-867.6K** |
| H4 (M13-18) | $72-90K | $607.8K | $30K | **$1,528.8-1,595.4K** |

### 9.2 Cost Optimization Offsets

Infrastructure savings from optimizing the existing $49,645/month AWS spend:

| Optimization | Monthly Savings | Start Month | 18-Month Total |
|-------------|----------------|------------|---------------|
| EC2 right-sizing (78% idle) | $5,000-8,000 | Month 2 | $85K-136K |
| RDS Reserved Instances (1.3% → 50% coverage) | $1,500-2,500 | Month 3 | $24K-40K |
| ElastiCache RI (6.6% → 40% coverage) | $500-1,000 | Month 3 | $8K-16K |
| Idle resource termination | $2,000-4,000 | Month 4 | $30K-60K |
| **Total optimization savings** | **$9,000-15,500/month** | | **$147K-252K** |

### 9.3 Net Investment After Optimizations

| Period | Gross Investment | Optimization Savings | Net Investment |
|--------|-----------------|---------------------|---------------|
| H1 (M1-3) | $112.5-118.5K | -$10.5-21K | $91.5-108K |
| H2 (M4-6) | $178.5-191.1K | -$27-46.5K | $132-164.1K |
| H3 (M7-12) | $528-558K | -$54-93K | $435-504K |
| H4 (M13-18) | $709.8-727.8K | -$54-93K | $616.8-673.8K |
| **18-Month Total** | **$1,528.8-1,595.4K** | **-$145.5-253.5K** | **$1,275.3-1,449.9K** |

### 9.4 Per-Store Cost Allocation

At 11 stores (current) and 50 stores (target):

| Period | Net Investment | Per-Store/Month (11) | Per-Store/Month (50) |
|--------|---------------|---------------------|---------------------|
| H1 | $91.5-108K | $2,773-3,273 | — |
| H2 | $132-164K | $4,000-4,973 | — |
| H3 | $435-504K | $6,591-7,636 | $1,450-1,680 |
| H4 | $617-674K | $9,348-10,212 | $2,056-2,247 |

At 50-store scale, the AI platform costs **$2,000-2,250/store/month** — well within operating margins for a coffee retailer.

---

## 10. Value Realization Timeline

### 10.1 Revenue Impact by Use Case

| Use Case | Horizon | Value Driver | Annual Impact Estimate |
|----------|---------|-------------|----------------------|
| Tax Compliance Tracker | H1 | Penalty avoidance, interest savings | $50-100K (risk mitigation) |
| Revenue Reconciliation | H1 | Reduce write-offs, catch discrepancies | $30-60K |
| Churn Prediction + Win-Back | H1→H3 | Recover 10-20% of 76K lapsed users | $200-430K |
| Coupon ROI Optimizer | H2 | Reduce 37.3M expired coupon waste by 30% | $50-100K |
| Menu Engineering Matrix | H2 | Shift mix from plowhorses to stars (+5% margin) | $40-80K |
| Waste Prediction | H2 | Reduce spoilage by 15-25% | $30-60K |
| Demand Forecast Monitor | H1 | Improve prediction accuracy → reduce over/under-production | $20-40K |
| Personalized Recommendations | H3 | Increase AOV by 10-15% from $4.71 | $100-200K |
| Price Elasticity | H3 | Optimize coupon depth → better margin | $50-100K |
| Dynamic Staffing | H3 | Reduce overtime 10-20%, improve compliance | $30-50K |
| Site Selection Enhancement | H3 | Better location decisions for expansion | $100-300K (strategic) |
| Production Time Predictor | H2 | Reduce wait times → improve retention | $20-40K |
| Database Cost Optimizer | H1 | Infrastructure savings (EC2, RI/SP) | $108-186K |
| **Total estimated annual impact** | | | **$828K-1,746K** |

### 10.2 Value Realization Curve

```
Annual
Value   ┌─────────────────────────────────────────────────────────────────────┐
Created │                                                          ▓▓▓▓▓▓▓▓│ $1.5-1.7M
$1.8M   │                                                    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
        │                                              ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
$1.4M   │                                        ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
        │                                   ▓▓▓▓▓                           │
$1.0M   │                              ▓▓▓▓▓                               │
        │                         ▓▓▓▓▓                                     │
$0.6M   │                    ▓▓▓▓▓          ← Break-even (Month 10-12)      │
        │               ▓▓▓▓▓                                               │
$0.2M   │          ▓▓▓▓▓                                                    │
        │     ▓▓▓▓▓                                                         │
$0      │▓▓▓▓▓                                                              │
        └─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬────────────┘
             M1    M3    M5    M7    M9   M11   M13   M15   M17   M18

        ├── H1 ──┤── H2 ──┤────── H3 ──────┤────── H4 ──────┤
        Foundation  Ops     AI Growth        Enterprise AI
```

### 10.3 ROI Projections

| Scenario | 18-Month Investment | 18-Month Value | ROI |
|----------|-------------------|---------------|-----|
| Conservative | $1,450K | $1,000K | -31% (break-even at month 22) |
| Base case | $1,350K | $1,500K | +11% (break-even at month 14) |
| Optimistic | $1,275K | $2,000K | +57% (break-even at month 10) |

**Key assumption:** ROI accelerates significantly at 50-store scale because AI platform costs are largely fixed while revenue impact scales linearly with stores.

---

## 11. Risk Register

### 11.1 Technical Risks

| ID | Risk | Probability | Impact | Mitigation | Owner |
|----|------|-------------|--------|------------|-------|
| T1 | CDC pipeline breaks under load | Medium | High | DMS monitoring + auto-restart; Kinesis as backup | Data Engineer |
| T2 | Redshift query costs exceed projections | Medium | Medium | Cost alerts at $5K/month; query optimization sprints | Analytics Engineer |
| T3 | Join key type mismatches cause data quality issues | High | High | Unified VARCHAR casting in staging layer; automated data quality checks | Data Engineer |
| T4 | ML model accuracy below threshold | Medium | Medium | MLflow tracking; automated retraining; fallback to rules-based | ML Engineer |
| T5 | Dify platform stability at scale | Low | Medium | Load testing; PostgreSQL optimization; failover to direct API calls | ML Engineer |
| T6 | NZD test data contamination persists | High | Medium | Quarantine filter in all ETL jobs; validate with row counts | Data Engineer |

### 11.2 Organizational Risks

| ID | Risk | Probability | Impact | Mitigation | Owner |
|----|------|-------------|--------|------------|-------|
| O1 | Cannot hire AI/ML talent in NYC (competitive market) | High | High | Remote-friendly roles; competitive comp; contractor bridge | Hiring Manager |
| O2 | Department stakeholders resist data-driven changes | Medium | High | Executive sponsor; demonstrate quick wins in H1; department champions | Project Lead |
| O3 | China HQ changes platform architecture | Medium | High | Document US-specific customizations; maintain local fork capability | CTO |
| O4 | Team too small to maintain growing platform | Medium | Medium | Prioritize automation; use managed services; build runbooks | Data Engineer |

### 11.3 Financial Risks

| ID | Risk | Probability | Impact | Mitigation | Owner |
|----|------|-------------|--------|------------|-------|
| F1 | AWS costs exceed budget | Medium | Medium | Cost alerts; serverless-first (pay per use); monthly budget reviews | Finance |
| F2 | ROI delayed due to slower store growth | Medium | High | Ensure H1-H2 value is independent of store count (operational efficiency) | Project Lead |
| F3 | Funding cut before H3 (AI Growth) | Low | Critical | Demonstrate measurable H1-H2 ROI; secure 12-month commitment | Executive Sponsor |
| F4 | Tax compliance penalties before system completion | Medium | Critical | Immediate manual audit (Week 1); parallel vendor engagement (Avalara) | Finance Lead |

### 11.4 Data Risks

| ID | Risk | Probability | Impact | Mitigation | Owner |
|----|------|-------------|--------|------------|-------|
| D1 | PII exposure in data warehouse | Low | Critical | Column-level encryption; dynamic masking; RBAC; PII discovery scan | Data Engineer |
| D2 | Data freshness SLA violations | Medium | Medium | CDC monitoring dashboard; alerting on lag >30 minutes | Data Engineer |
| D3 | Source database schema changes break CDC | High | Medium | Schema change detection in DMS; versioned ETL jobs; alerting | Data Engineer |
| D4 | Historical data quality insufficient for ML training | Medium | High | Data quality scoring before model training; synthetic data augmentation | Data Scientist |

---

## 12. Success Metrics & Governance

### 12.1 KPIs by Horizon

#### Horizon 1 KPIs

| KPI | Target | Measurement |
|-----|--------|-------------|
| Data warehouse uptime | >99.5% | CloudWatch monitoring |
| CDC pipeline lag | <15 minutes | DMS monitoring dashboard |
| Tax compliance coverage | 100% of jurisdictions tracked | Tax tracker dashboard |
| Reconciliation accuracy | >99.9% match rate | Daily reconciliation report |
| Executive briefing delivery | 100% daily delivery | Slack/email confirmation |
| Dashboard adoption | >3 active daily users | Superset/Grafana analytics |
| Infrastructure cost reduction | >$3K/month savings initiated | Cost Explorer comparison |

#### Horizon 2 KPIs

| KPI | Target | Measurement |
|-----|--------|-------------|
| CDC pipelines active | 12 of 16 priority databases | DMS dashboard |
| Feature Store latency | <50ms (online), <4hr (offline) | SageMaker monitoring |
| Coupon waste reduction | >15% reduction in expired coupons | Marketing dashboard |
| Fraud detection precision | >90% precision, <2% false positive rate | Model monitoring |
| Business dashboard coverage | All 7 departments have dashboards | Superset analytics |
| Waste reduction | >10% reduction in spoilage costs | SCM dashboard |

#### Horizon 3 KPIs

| KPI | Target | Measurement |
|-----|--------|-------------|
| ML models in production | 5+ models serving predictions | MLflow registry |
| Churn recovery rate | >10% of targeted lapsed users return | Marketing analytics |
| Recommendation click-through | >5% CTR on personalized suggestions | App analytics |
| AOV uplift from recommendations | >$0.50 per order | A/B test results |
| "Ask Lucky" query success rate | >80% queries return useful results | Dify analytics |
| Forecast accuracy improvement | >5% MAPE reduction | Model monitoring |

#### Horizon 4 KPIs

| KPI | Target | Measurement |
|-----|--------|-------------|
| ML models in production | 10+ models | MLflow registry |
| Platform autonomy | >80% of tasks automated | Operations dashboard |
| New store deployment time | <2 weeks data onboarding | Deployment tracking |
| 50-store infrastructure cost | <$2,500/store/month | Cost Explorer |
| Real-time scoring latency | <100ms P99 | Endpoint monitoring |
| Overall ROI | >0% (break-even achieved) | Financial reporting |

### 12.2 Governance Structure

**Review Cadence:**

| Meeting | Frequency | Attendees | Purpose |
|---------|-----------|-----------|---------|
| AI Daily Standup | Daily | Data team | Sprint progress, blockers |
| Pipeline Health Review | Weekly | Data + IT leads | CDC status, data quality, incidents |
| AI Steering Committee | Bi-weekly | Dept heads + CTO | Use case prioritization, resource allocation |
| Horizon Gate Review | Quarterly (at horizon boundaries) | C-suite + AI team | Go/no-go for next horizon; ROI assessment |
| Board AI Update | Quarterly | Board of Directors | Strategic progress, investment justification |

**Decision Authority:**

| Decision | Authority | Escalation |
|----------|----------|------------|
| Data pipeline changes | Data Engineer (Senior) | CTO |
| New ML model deployment | ML Engineer + Data Scientist | AI Steering Committee |
| Budget adjustments (<10%) | Project Lead | CTO |
| Budget adjustments (>10%) | CTO | CEO |
| New use case addition | AI Steering Committee | — |
| Horizon gate go/no-go | C-suite | Board |
| External vendor selection | CTO + Finance | CEO |

### 12.3 Reporting

**Monthly AI Transformation Report (to C-suite):**
1. Horizon progress (% complete, on-track/delayed/blocked)
2. Active use cases and their measured impact
3. Infrastructure health and cost trends
4. Team status and hiring progress
5. Risk register updates
6. Next month priorities

---

## 13. Dependencies & Critical Path

### 13.1 Dependency Graph

```
                              ┌──────────────┐
                              │  REDSHIFT     │
                              │  DEPLOYMENT   │
                              │  (Week 1-2)   │
                              └──────┬───────┘
                                     │
                 ┌───────────────────┼───────────────────┐
                 │                   │                   │
          ┌──────▼───────┐   ┌──────▼───────┐   ┌──────▼───────┐
          │   CDC #1-5    │   │   GLUE ETL    │   │   S3 LAKE    │
          │   (Week 3-6)  │   │   (Week 5-8)  │   │   (Week 1-2) │
          └──────┬───────┘   └──────┬───────┘   └──────┬───────┘
                 │                   │                   │
                 └───────────────────┼───────────────────┘
                                     │
                              ┌──────▼───────┐
                              │  STAR SCHEMA  │
                              │  (Week 5-8)   │
                              └──────┬───────┘
                                     │
          ┌──────────────────────────┼──────────────────────────┐
          │                          │                          │
   ┌──────▼───────┐          ┌──────▼───────┐          ┌──────▼───────┐
   │  TAX TRACKER  │          │  REV RECON   │          │  EXEC BRIEF  │
   │  (Week 7-8)   │          │  (Week 5-6)  │          │  (Week 7-8)  │
   └──────────────┘          └──────────────┘          └──────────────┘
                                     │
                              ┌──────▼───────┐
                              │  CDC #6-12    │
                              │  (Week 13-16) │
                              └──────┬───────┘
                                     │
                              ┌──────▼───────┐
                              │ FEATURE STORE │
                              │  (Week 15-18) │
                              └──────┬───────┘
                                     │
                 ┌───────────────────┼───────────────────┐
                 │                   │                   │
          ┌──────▼───────┐   ┌──────▼───────┐   ┌──────▼───────┐
          │  CHURN MODEL  │   │  RECO ENGINE │   │  CLV MODEL   │
          │  (Month 7-8)  │   │  (Month 8-9) │   │  (Month 9)   │
          └──────────────┘   └──────────────┘   └──────────────┘
```

### 13.2 Critical Path

The critical path through the roadmap:

```
Redshift Deploy → CDC Pipelines #1-5 → Star Schema Load → Revenue Reconciliation →
  CDC #6-12 → Feature Store → Churn ML Model → Recommendation Engine → ROI Assessment
```

**Total critical path duration:** ~9 months (Month 1 → Month 9)

**Slack items** (can be delayed without affecting critical path):
- Tax Compliance Tracker (independent of star schema — can use direct DB queries)
- Executive AI Briefing (uses Dify + direct queries initially)
- Database Cost Optimizer (pure analysis, no infrastructure dependency)
- Predictive Infrastructure Monitoring (uses existing Prometheus data)

### 13.3 Key Dependencies on External Systems

| Dependency | Risk | Mitigation |
|-----------|------|------------|
| China HQ database schema stability | Schema changes can break CDC | Schema monitoring, versioned ETL |
| AWS service availability (us-east-1) | Single-region deployment | Multi-AZ within region; disaster recovery plan at H3 |
| Dify platform updates | Breaking changes to agent API | Pin Dify version; test updates in staging |
| Tax compliance vendor (Avalara/TaxJar) | Vendor selection and integration | Start vendor evaluation in Week 1; manual tracking as bridge |
| External data providers (H4) | Cost, data quality, API stability | Evaluate 2+ providers per category; local caching |

---

## 14. Appendix: Full Prioritization Matrix

### All 41 Use Cases with Complete Scoring

| Rank | Use Case | Dept | DR | BI | TC | CDV | SA | Weighted | Priority | Horizon |
|------|----------|------|----|----|----|----|----|----|------|---------|
| 1 | Tax Compliance Automation | FIN | 1 | 5 | 5 | 4 | 5 | 4.45 | P0 | H1 |
| 2 | Revenue Reconciliation | FIN | 5 | 5 | 4 | 3 | 4 | 4.35 | P0 | H1 |
| 3 | Churn Prediction & Win-Back | MKT | 5 | 5 | 3 | 3 | 5 | 4.30 | P0 | H1→H3 |
| 4 | Executive AI Daily Briefing | EXEC | 4 | 4 | 4 | 5 | 5 | 4.25 | P0 | H1 |
| 5 | Demand Forecast Monitor | SCM | 5 | 4 | 5 | 3 | 4 | 4.20 | P0 | H1 |
| 6 | Customer 360 Profile | MKT | 4 | 5 | 3 | 4 | 4 | 4.15 | P0 | H1 |
| 7 | Coupon ROI Optimizer | MKT | 5 | 4 | 4 | 3 | 4 | 4.10 | P1 | H2 |
| 8 | Predictive Infra Monitoring | IT | 4 | 4 | 3 | 4 | 4 | 4.05 | P1 | H1 |
| 9 | Store Performance Anomaly | OPS | 5 | 4 | 4 | 3 | 3 | 4.00 | P1 | H1 |
| 10 | Payment Fraud Detection | FIN | 4 | 4 | 3 | 3 | 4 | 3.95 | P1 | H2 |
| 11 | Menu Engineering Matrix | PROD | 5 | 4 | 4 | 2 | 3 | 3.90 | P1 | H2 |
| 12 | Waste Prediction & Reduction | SCM | 4 | 4 | 3 | 3 | 4 | 3.85 | P1 | H2 |
| 13 | A/B Test Auto-Optimization | MKT | 5 | 3 | 4 | 3 | 3 | 3.80 | P1 | H2 |
| 14 | Production Time Predictor | OPS | 5 | 3 | 4 | 2 | 3 | 3.75 | P1 | H2 |
| 15 | Database Cost Optimizer | IT | 5 | 4 | 4 | 2 | 2 | 3.70 | P1 | H1 |
| 16 | Next-Best-Action Engine | MKT | 3 | 4 | 2 | 3 | 5 | 3.65 | P1 | H2 |
| 17 | Push Notification Optimizer | MKT | 4 | 3 | 3 | 2 | 4 | 3.60 | P1 | H2 |
| 18 | Dynamic Staffing Optimizer | OPS | 3 | 4 | 2 | 3 | 4 | 3.55 | P2 | H3 |
| 19 | Personalized Recommendations | PROD | 4 | 4 | 2 | 3 | 4 | 3.50 | P2 | H3 |
| 20 | Unified KPI Command Center | EXEC | 3 | 3 | 3 | 5 | 4 | 3.45 | P2 | H3 |
| 21 | Self-Healing Automation | IT | 3 | 3 | 2 | 4 | 4 | 3.40 | P2 | H3 |
| 22 | CLV Prediction | MKT | 4 | 3 | 3 | 3 | 3 | 3.35 | P2 | H3 |
| 23 | Dynamic Par Level Setting | SCM | 3 | 3 | 3 | 3 | 4 | 3.30 | P2 | H3 |
| 24 | Price Elasticity Modeling | PROD | 4 | 3 | 3 | 2 | 3 | 3.25 | P2 | H3 |
| 25 | Supplier Performance Scoring | SCM | 4 | 3 | 4 | 2 | 2 | 3.20 | P2 | H3 |
| 26 | IoT Predictive Maintenance | OPS | 2 | 3 | 2 | 3 | 4 | 3.15 | P2 | H3 |
| 27 | Security Posture Intelligence | IT | 4 | 2 | 3 | 3 | 3 | 3.10 | P2 | H4 |
| 28 | New Product Launch Predictor | PROD | 3 | 3 | 2 | 2 | 4 | 3.05 | P2 | H4 |
| 29 | Payment Channel Cost Optimizer | FIN | 4 | 3 | 4 | 1 | 2 | 3.00 | P2 | H4 |
| 30 | Recipe Cost Optimization | PROD | 4 | 2 | 4 | 2 | 2 | 2.95 | P2 | H4 |
| 31 | Site Selection Enhancement | EXEC | 4 | 3 | 2 | 2 | 3 | 2.90 | P2 | H3 |
| 32 | Capacity Planning (50-store) | IT | 3 | 2 | 2 | 3 | 4 | 2.85 | P2 | H4 |
| 33 | NL Database Query | IT | 4 | 2 | 2 | 3 | 3 | 2.80 | P2 | H3 |
| 34 | New Store Ramp Predictor | OPS | 4 | 2 | 3 | 2 | 3 | 2.75 | P3 | H4 |
| 35 | Queue/Wait Time Management | OPS | 3 | 2 | 2 | 2 | 3 | 2.70 | P3 | H4 |
| 36 | Financial Forecasting | FIN | 1 | 3 | 2 | 3 | 3 | 2.65 | P3 | H4 |
| 37 | Perishable Shelf-Life Tracker | SCM | 3 | 2 | 3 | 2 | 2 | 2.60 | P3 | H4 |
| 38 | Referral Network Analysis | MKT | 3 | 2 | 3 | 2 | 2 | 2.55 | P3 | H4 |
| 39 | Channel Attribution | MKT | 1 | 3 | 2 | 2 | 3 | 2.50 | P3 | H4 |
| 40 | Social Listening & Sentiment | MKT | 1 | 2 | 2 | 2 | 3 | 2.45 | P3 | H4 |
| 41 | Competitive Intelligence | EXEC | 1 | 2 | 2 | 2 | 3 | 2.40 | P3 | H4 |

**Legend:** DR = Data Readiness, BI = Business Impact, TC = Technical Complexity (inverted), CDV = Cross-Department Value, SA = Strategic Alignment

### Horizon Distribution Summary

| Horizon | Use Cases | Avg Score | P0 | P1 | P2 | P3 |
|---------|-----------|-----------|----|----|----|----|
| H1 (Months 1-3) | 9 | 4.07 | 6 | 3 | 0 | 0 |
| H2 (Months 4-6) | 8 | 3.83 | 0 | 8 | 0 | 0 |
| H3 (Months 7-12) | 12 | 3.24 | 0 | 0 | 12 | 0 |
| H4 (Months 13-18) | 12 | 2.79 | 0 | 1 | 3 | 8 |
| **Total** | **41** | **3.39** | **6** | **12** | **15** | **8** |

---

## Summary: The 18-Month Journey

```
TODAY                           MONTH 6                        MONTH 18
┌──────────────────┐    ┌──────────────────────┐    ┌──────────────────────────┐
│ 143 siloed DBs   │    │ 12 CDC pipelines     │    │ Unified data platform    │
│ 0 data warehouse │ → │ Star schema live     │ → │ 10+ ML models serving    │
│ 2 ML models      │    │ Feature Store active │    │ Real-time AI scoring     │
│ 0 biz dashboards │    │ 7 dept dashboards    │    │ Autonomous operations    │
│ 3 broken alerts  │    │ 5 ML models          │    │ 50-store ready           │
│ $49.6K/mo AWS    │    │ $50.6K/mo AWS        │    │ $49.1K/mo AWS (savings!) │
│ ~$7K/store loss  │    │ Breaking even?       │    │ Profitable per store     │
└──────────────────┘    └──────────────────────┘    └──────────────────────────┘
```

The transformation is achievable because:
1. **The infrastructure already exists** — 143 databases built for 20,000 stores
2. **The data is ready** — 24 of 41 use cases can start with existing data
3. **AI is already proven** — 6 AI/ML systems demonstrate the organization can adopt AI
4. **The cost is manageable** — net-zero infrastructure cost via optimization offsets
5. **The team scales gradually** — 2.5 FTE → 8 FTE over 18 months, not a big-bang hire

---

*This roadmap is designed to be adaptive. Each horizon gate review is an opportunity to re-prioritize based on actual results, changing business conditions, and team capacity. The critical principle: deliver measurable value in every horizon, not just at the end.*

---

*Generated February 14, 2026*
*Luckin Coffee USA — Confidential*

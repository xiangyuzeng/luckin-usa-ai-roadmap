# AI Tool Use Case Catalog
## Luckin Coffee USA — AI Transformation Roadmap (Deliverable 2 of 5)

**Prepared for:** First Ray Holdings USA Inc. (Luckin Coffee USA)
**Date:** February 14, 2026
**Classification:** Confidential

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Prioritization Framework](#2-prioritization-framework)
3. [Prioritization Matrix](#3-prioritization-matrix)
4. [Department 1: IT Infrastructure & DevOps](#4-department-1-it-infrastructure--devops)
5. [Department 2: Marketing & Customer Analytics](#5-department-2-marketing--customer-analytics)
6. [Department 3: Accounting & Finance](#6-department-3-accounting--finance)
7. [Department 4: Product & Menu Innovation](#7-department-4-product--menu-innovation)
8. [Department 5: Store Operations](#8-department-5-store-operations)
9. [Department 6: Supply Chain & Inventory](#9-department-6-supply-chain--inventory)
10. [Department 7: Executive & Strategy](#10-department-7-executive--strategy)
11. [Data Readiness Summary](#11-data-readiness-summary)
12. [Cross-Department Dependency Map](#12-cross-department-dependency-map)
13. [Quick Win Identification](#13-quick-win-identification)
14. [Existing AI/ML Systems Audit](#14-existing-aiml-systems-audit)
15. [Implementation Prerequisites](#15-implementation-prerequisites)

---

## 1. Executive Summary

This catalog identifies **41 AI/ML use cases** across **7 departments** that Luckin Coffee USA can implement to transform from a digitally-enabled coffee retailer into an AI-powered growth engine. Each use case is evaluated for data readiness, business impact, technical complexity, and strategic alignment.

### Use Case Distribution

| Department | Use Cases | GREEN (Ready) | YELLOW (Gaps) | RED (Missing) |
|-----------|-----------|---------------|---------------|---------------|
| IT Infrastructure & DevOps | 6 | 4 | 2 | 0 |
| Marketing & Customer Analytics | 10 | 6 | 3 | 1 |
| Accounting & Finance | 5 | 2 | 1 | 2 |
| Product & Menu Innovation | 5 | 4 | 1 | 0 |
| Store Operations | 6 | 3 | 2 | 1 |
| Supply Chain & Inventory | 5 | 3 | 2 | 0 |
| Executive & Strategy | 4 | 2 | 1 | 1 |
| **Total** | **41** | **24 (59%)** | **12 (29%)** | **5 (12%)** |

### Key Findings

- **24 of 41 use cases (59%)** have GREEN data readiness — implementation can begin immediately with existing data
- **6 AI/ML systems already deployed**: Demand Forecasting, A/B Testing Platform, Customer Data Platform (CDP), CyberData ETL Pipeline, Dify LLM Platform, Site Selection ML Model
- **Highest-impact quick wins**: Churn Prediction ($200-400K/year recovery potential), Revenue Reconciliation (eliminate manual 3-way matching), Tax Compliance Tracker (regulatory risk mitigation)
- **Biggest data gap**: Tax compliance — `fi_tax` database is completely empty despite $2.19M in cumulative revenue

### Priority Distribution

| Priority | Count | Definition |
|----------|-------|------------|
| P0 — Critical + Ready | 6 | Regulatory risk or proven ROI, data ready now |
| P1 — High Value + Ready | 12 | High business impact, data available, moderate complexity |
| P2 — High Value + Needs Work | 14 | Strong business case but requires data pipeline work |
| P3 — Future | 9 | Strategic value but dependent on earlier phases or external data |

---

## 2. Prioritization Framework

Each use case is scored on five axes (1-5 scale):

| Axis | Weight | Description |
|------|--------|-------------|
| **Data Readiness** | 25% | Quality, completeness, and accessibility of required data |
| **Business Impact** | 30% | Revenue uplift, cost savings, or risk mitigation potential |
| **Technical Complexity** | 20% | Implementation difficulty (inverted: 5 = easy, 1 = very complex) |
| **Cross-Department Value** | 10% | Number of departments that benefit from this capability |
| **Strategic Alignment** | 15% | Alignment with 50-store expansion and AI-first strategy |

### Scoring Rubric

**Data Readiness:**
- 5 = All data exists in production tables, clean, accessible via MCP
- 4 = Data exists but needs minor quality fixes (NZD contamination, null handling)
- 3 = Core data exists but missing important dimensions or has significant gaps
- 2 = Partial data available, major ETL work required
- 1 = Data does not exist or requires new collection infrastructure

**Business Impact:**
- 5 = >$200K/year revenue impact or regulatory/compliance risk mitigation
- 4 = $100-200K/year revenue impact or significant operational efficiency
- 3 = $50-100K/year revenue impact or meaningful process improvement
- 2 = $20-50K/year revenue impact or incremental improvement
- 1 = <$20K/year revenue impact, primarily learning value

**Technical Complexity (inverted):**
- 5 = SQL queries + dashboards, no ML required
- 4 = Standard ML (classification, regression) with existing tools
- 3 = Custom ML pipeline, requires feature engineering
- 2 = Real-time ML, requires streaming infrastructure
- 1 = Advanced AI (deep learning, NLP, reinforcement learning)

**Cross-Department Value:**
- 5 = Benefits 5+ departments
- 4 = Benefits 3-4 departments
- 3 = Benefits 2 departments
- 2 = Benefits 1 department with external visibility
- 1 = Benefits 1 department, internal only

**Strategic Alignment:**
- 5 = Core to 50-store expansion strategy
- 4 = Directly supports growth or competitive advantage
- 3 = Improves operational readiness for scale
- 2 = Nice-to-have for current operations
- 1 = Exploratory, uncertain strategic value

---

## 3. Prioritization Matrix

### Visual Matrix: Business Impact vs. Data Readiness

```
                          DATA READINESS
                    LOW ◄─────────────────► HIGH

          HIGH  ┌──────────────┬──────────────┐
                │   P2 ZONE    │   P0/P1 ZONE │
                │              │              │
                │ • Tax Auto   │ • Churn Pred │
    B           │ • IoT Maint  │ • Rev Recon  │
    U           │ • Loyalty AI │ • Exec Brief │
    S           │ • Comp Intel │ • Campaign   │
    I           │ • Shelf Life │ • Coupon ROI │
    N           │              │ • Customer360│
    E           │              │ • Demand Mon │
    S           ├──────────────┼──────────────┤
    S           │   P3 ZONE    │   P2 ZONE    │
                │              │              │
    I           │ • Social     │ • NL Query   │
    M           │   Listening  │ • CLV Pred   │
    P           │ • Channel    │ • Prod Recom │
    A           │   Attribution│ • Price Elast│
    C           │ • Referral   │ • DB Cost Opt│
    T           │   Network    │ • Staff Opt  │
                │              │ • Queue Mgmt │
          LOW   └──────────────┴──────────────┘
```

### Ranked Use Case List (by Weighted Score)

| Rank | Use Case | Dept | Score | Priority | Data |
|------|----------|------|-------|----------|------|
| 1 | Tax Compliance Automation | Finance | 4.45 | P0 | 🔴 RED |
| 2 | Revenue Reconciliation | Finance | 4.35 | P0 | 🟢 GREEN |
| 3 | Churn Prediction & Win-Back | Marketing | 4.30 | P0 | 🟢 GREEN |
| 4 | Executive AI Daily Briefing | Executive | 4.25 | P0 | 🟢 GREEN |
| 5 | Demand Forecast Monitor | SCM | 4.20 | P0 | 🟢 GREEN |
| 6 | Customer 360 Profile | Marketing | 4.15 | P0 | 🟢 GREEN |
| 7 | Coupon ROI Optimizer | Marketing | 4.10 | P1 | 🟢 GREEN |
| 8 | Predictive Infra Monitoring | IT | 4.05 | P1 | 🟢 GREEN |
| 9 | Store Performance Anomaly | Operations | 4.00 | P1 | 🟢 GREEN |
| 10 | Payment Fraud Detection | Finance | 3.95 | P1 | 🟢 GREEN |
| 11 | Menu Engineering Matrix | Product | 3.90 | P1 | 🟢 GREEN |
| 12 | Waste Prediction & Reduction | SCM | 3.85 | P1 | 🟢 GREEN |
| 13 | A/B Test Auto-Optimization | Marketing | 3.80 | P1 | 🟢 GREEN |
| 14 | Production Time Predictor | Operations | 3.75 | P1 | 🟢 GREEN |
| 15 | Database Cost Optimizer | IT | 3.70 | P1 | 🟢 GREEN |
| 16 | Next-Best-Action Engine | Marketing | 3.65 | P1 | 🟡 YELLOW |
| 17 | Push Notification Optimizer | Marketing | 3.60 | P1 | 🟢 GREEN |
| 18 | Dynamic Staffing Optimizer | Operations | 3.55 | P2 | 🟡 YELLOW |
| 19 | Personalized Recommendations | Product | 3.50 | P2 | 🟢 GREEN |
| 20 | Unified KPI Command Center | Executive | 3.45 | P2 | 🟡 YELLOW |
| 21 | Self-Healing Automation | IT | 3.40 | P2 | 🟡 YELLOW |
| 22 | CLV Prediction | Marketing | 3.35 | P2 | 🟢 GREEN |
| 23 | Dynamic Par Level Setting | SCM | 3.30 | P2 | 🟡 YELLOW |
| 24 | Price Elasticity Modeling | Product | 3.25 | P2 | 🟢 GREEN |
| 25 | Supplier Performance Scoring | SCM | 3.20 | P2 | 🟢 GREEN |
| 26 | IoT Predictive Maintenance | Operations | 3.15 | P2 | 🟡 YELLOW |
| 27 | Security Posture Intelligence | IT | 3.10 | P2 | 🟢 GREEN |
| 28 | New Product Launch Predictor | Product | 3.05 | P2 | 🟡 YELLOW |
| 29 | Payment Channel Cost Optimizer | Finance | 3.00 | P2 | 🟢 GREEN |
| 30 | Recipe Cost Optimization | Product | 2.95 | P2 | 🟢 GREEN |
| 31 | Site Selection Enhancement | Executive | 2.90 | P2 | 🟢 GREEN |
| 32 | Capacity Planning (50-store) | IT | 2.85 | P2 | 🟡 YELLOW |
| 33 | NL Database Query ("Ask Lucky") | IT | 2.80 | P2 | 🟢 GREEN |
| 34 | New Store Ramp Predictor | Operations | 2.75 | P3 | 🟢 GREEN |
| 35 | Queue/Wait Time Management | Operations | 2.70 | P3 | 🟡 YELLOW |
| 36 | Financial Forecasting | Finance | 2.65 | P3 | 🔴 RED |
| 37 | Perishable Shelf-Life Tracker | SCM | 2.60 | P3 | 🟡 YELLOW |
| 38 | Referral Network Analysis | Marketing | 2.55 | P3 | 🟡 YELLOW |
| 39 | Channel Attribution | Marketing | 2.50 | P3 | 🔴 RED |
| 40 | Social Listening & Sentiment | Marketing | 2.45 | P3 | 🔴 RED |
| 41 | Competitive Intelligence | Executive | 2.40 | P3 | 🔴 RED |

---

## 4. Department 1: IT Infrastructure & DevOps

### Overview

Luckin Coffee USA operates 143 database instances, 233+ EC2 instances, 308 Kafka topics, and 124 CloudWatch log groups — infrastructure scaled for 20,000+ stores that currently serves 11. The IT department has the highest concentration of GREEN-ready use cases because infrastructure telemetry is already being collected via Prometheus (76 targets), Grafana (17 dashboards), and CloudWatch.

**Department Use Cases:** 6 | **GREEN:** 4 | **YELLOW:** 2 | **RED:** 0

---

### UC-IT-01: Predictive Infrastructure Monitoring

**Priority:** P1 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 4.05

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 4 | Prometheus collects Redis metrics (76 targets, 155 metric families); CloudWatch has 95 log groups; missing: MySQL/application metrics |
| Business Impact | 4 | Prevent downtime events like the Feb 2026 VM crash (P0 incident); $49.6K/month infrastructure at stake |
| Technical Complexity | 3 | Anomaly detection on time-series (Prophet/LSTM); need to integrate multiple metric sources |
| Cross-Department Value | 4 | All departments depend on infrastructure availability |
| Strategic Alignment | 4 | Critical for 50-store scale — cannot manually monitor 700+ instances |

**Business Problem:**
Current monitoring is reactive and fragmented. Only 3 Grafana alert rules exist and all have `health: error` status (non-functional). The February 2026 P0 incident (luckyuam01-prod-usb VM down) was detected by AWS system health checks, not by LKUS monitoring. With 233+ EC2 instances (78% idle), Prometheus only monitoring Redis, and 0 active CloudWatch alarms, the infrastructure lacks early warning capability.

**AI Approach:**
- **Method:** Time-series anomaly detection using Isolation Forest / Prophet on metric streams
- **Training Data:** 2+ months of Prometheus Redis metrics (memory usage, connection counts, cache hit rates), CloudWatch RDS metrics (CPU, IOPS, connections)
- **Features:** Rolling averages, seasonal decomposition, cross-metric correlation (e.g., Redis memory spike + MySQL connection drop = cascading failure pattern)
- **Output:** Anomaly scores with 15-minute prediction horizon, auto-escalation to Slack/PagerDuty

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Redis metrics | Prometheus | `redis_memory_used_bytes`, `redis_connected_clients`, `redis_keyspace_hits_total` | ~155 metric families | 🟢 Available |
| Redis exporter | Prometheus | 76 targets (75 up, 1 down) | Continuous | 🟢 Available |
| RDS metrics | CloudWatch | `CPUUtilization`, `DatabaseConnections`, `FreeableMemory` | 62 RDS instances | 🟢 Available |
| EC2 metrics | CloudWatch | `StatusCheckFailed`, `CPUUtilization` | 233 instances | 🟢 Available |
| Slow query logs | CloudWatch | `/aws/rds/instance/*/slowquery` | 52 log groups, 3.4GB largest | 🟢 Available |
| Application metrics | — | Not collected | — | 🟡 Gap |

**Cross-Department Impact:** Operations (store downtime prevention), Finance (cost avoidance), Executive (SLA reporting)

**Quick Win Potential:** HIGH — Start with Redis anomaly detection using existing Prometheus data within 2 weeks

---

### UC-IT-02: Database Cost Optimizer

**Priority:** P1 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 3.70

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 5 | Complete AWS Cost Explorer data, EC2 inventory, RI/SP coverage reports available |
| Business Impact | 4 | $176K/year EC2 savings + $41.5K/year RI/SP savings identified; RDS only 1.3% RI coverage |
| Technical Complexity | 4 | Rules-based optimization with ML for usage prediction; standard tooling |
| Cross-Department Value | 2 | Primarily IT benefit, frees budget for other departments |
| Strategic Alignment | 4 | Per-store tech cost must decrease 60-70% for 100+ store viability |

**Business Problem:**
AWS spend is $49,645/month ($595K annualized) for 11 stores — approximately $4,500/month per store. At the target of 100+ stores, this ratio would yield $5.4M/year in infrastructure costs, which is unsustainable. Specific optimization opportunities:
- **EC2:** 233 instances, 78% idle, $176K/year savings identified (Graviton migration, right-sizing, idle termination)
- **RI/SP Coverage:** 50.2% RI overall, but RDS at only 1.3% and ElastiCache at 6.6% — these are paying full on-demand pricing
- **RDS:** $5,527/month but could consolidate underutilized instances
- **ElastiCache:** 78 clusters for 11 stores — many with <1% cache hit rates (e.g., `shopsale` at 2.9%)

**AI Approach:**
- **Method:** Usage pattern analysis (time-series clustering) + cost optimization recommender
- **Training Data:** 3-month AWS Cost Explorer data (Nov 2025 - Jan 2026), CloudWatch utilization metrics
- **Model:** Gradient Boosted Trees for usage prediction → RI/SP purchase recommendations
- **Output:** Monthly optimization report with specific actions (terminate, right-size, purchase RI/SP)

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| AWS Cost Explorer | Cost Explorer API | Monthly spend by service | 3 months | 🟢 Available |
| EC2 inventory | CloudWatch / CSV | Instance types, utilization | 233 instances | 🟢 Available |
| RI/SP coverage | Cost Explorer API | Coverage ratios by service | Monthly | 🟢 Available |
| RDS utilization | CloudWatch | CPU, memory, IOPS per instance | 62 instances | 🟢 Available |
| Redis utilization | Prometheus | Memory, hit rate, connections | 78 clusters | 🟢 Available |

**Cross-Department Impact:** Finance (budget optimization), Executive (per-store cost reduction)

---

### UC-IT-03: Self-Healing Automation

**Priority:** P2 | **Data Readiness:** 🟡 YELLOW | **Weighted Score:** 3.40

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 3 | Incident history limited; runbooks not documented; CloudWatch logs available but no structured incident database |
| Business Impact | 3 | Reduce MTTR from hours to minutes; prevent repeat of Feb 2026 P0 incident pattern |
| Technical Complexity | 2 | Requires event-driven automation, AWS Lambda/SSM, safe rollback logic |
| Cross-Department Value | 3 | All departments benefit from faster incident resolution |
| Strategic Alignment | 4 | Essential at 50+ stores — cannot have manual remediation at scale |

**Business Problem:**
The February 2026 P0 incident (VM hardware failure) required manual intervention. With 3 broken Grafana alert rules and 0 CloudWatch alarms, there is no automated response capability. At 50+ stores, infrastructure incidents will increase proportionally, but the SRE team cannot scale linearly.

**AI Approach:**
- **Method:** Event-driven remediation with ML-classified incident types → automated runbook execution
- **Training Data:** CloudWatch logs, Prometheus alerts, historical incident tickets (if available)
- **Model:** Decision tree classifier for incident categorization → mapped to SSM Automation documents
- **Output:** Auto-remediation for common patterns (instance restart, connection pool reset, cache flush, DNS failover)

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| CloudWatch Logs | CloudWatch | 95 log groups | Continuous | 🟢 Available |
| Prometheus alerts | Grafana | 3 alert rules (all broken) | — | 🟡 Needs fix |
| Incident history | — | Not structured | — | 🟡 Gap |
| Runbook documentation | — | Not documented | — | 🟡 Gap |

---

### UC-IT-04: Capacity Planning for 50-Store Scale

**Priority:** P2 | **Data Readiness:** 🟡 YELLOW | **Weighted Score:** 2.85

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 3 | Current utilization data available; missing: per-store resource consumption mapping |
| Business Impact | 3 | Prevent over-provisioning or under-provisioning during expansion |
| Technical Complexity | 3 | Linear regression + simulation modeling |
| Cross-Department Value | 3 | IT, Finance, Executive |
| Strategic Alignment | 5 | Directly enables expansion strategy |

**Business Problem:**
With 143 database instances serving 11 stores (13:1 ratio), naive scaling would project 650+ instances for 50 stores. The current architecture was ported from China's 20,000-store platform, meaning many services are shared (not per-store). A capacity model is needed to project which resources scale linearly with store count vs. which are fixed overhead.

**AI Approach:**
- **Method:** Regression modeling: resource consumption = f(store_count, order_volume, user_count)
- **Training Data:** 8.5 months of growth data (2→11 stores), correlated with infrastructure metrics
- **Output:** Capacity projection dashboard showing infrastructure requirements at 25/50/100/200 store milestones

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Store opening dates | `opshop` | `luckyus_op_shop.sys_shop` | 11-16 stores | 🟢 Available |
| Monthly order volumes | `salesorder` | `luckyus_isales_order.t_sales_order_m` | 466K+ orders | 🟢 Available |
| AWS utilization metrics | CloudWatch | CPU, memory, IOPS over time | 8.5 months | 🟢 Available |
| Per-store resource mapping | — | Not mapped | — | 🟡 Gap |

---

### UC-IT-05: Natural Language Database Query ("Ask Lucky")

**Priority:** P2 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 2.80

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 5 | All 62 MySQL databases accessible via MCP DB Gateway; Dify LLM platform already deployed |
| Business Impact | 2 | Productivity tool — reduces analyst bottleneck for ad-hoc queries |
| Technical Complexity | 2 | NL-to-SQL via LLM (Dify already deployed), requires schema metadata, guardrails for read-only |
| Cross-Department Value | 5 | All departments can self-serve data queries |
| Strategic Alignment | 3 | Enables data democratization but not directly growth-linked |

**Business Problem:**
Data queries currently require SQL expertise and direct database access via MCP. Non-technical stakeholders (marketing, operations managers, executives) cannot self-serve analytical questions like "What was our best-selling product at the Grand Street store last week?" or "How many customers ordered more than 3 times in January?"

**AI Approach:**
- **Method:** LLM-powered NL-to-SQL using Dify (already deployed on PostgreSQL) + MCP DB Gateway
- **Architecture:** User query → Dify LLM → SQL generation → MCP DB Gateway → Results → Natural language response
- **Guardrails:** Read-only access, query timeout limits, PII masking (phone numbers already masked in some tables), query cost estimation
- **Output:** Slack bot or web interface for natural language database queries

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Dify LLM Platform | PostgreSQL (`aws-luckyus-dify-rw`) | All Dify tables | Active | 🟢 Available |
| MCP DB Gateway | All 62 MySQL databases | Schema metadata | 1,400+ tables | 🟢 Available |
| Schema documentation | `information_schema` | Column names, types, relationships | All databases | 🟢 Available |

---

### UC-IT-06: Security Posture Intelligence

**Priority:** P2 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 3.10

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 4 | Risk control service has 4.1M rule counts, 1,395 blacklist entries; WAF Redis active |
| Business Impact | 3 | Proactive security monitoring; prevent fraud/breach before it occurs |
| Technical Complexity | 3 | Anomaly detection on login/transaction patterns; integrate risk control data |
| Cross-Department Value | 3 | IT, Finance, Executive |
| Strategic Alignment | 3 | Regulatory compliance and brand protection |

**Business Problem:**
The `iriskcontrolservice` database contains 4.1M rule count records and 1,395 blacklist entries across 24+ sharded log tables, indicating an active but potentially overwhelming risk monitoring system. The WAF (Web Application Firewall) Redis cluster is active, but there's no unified security dashboard or anomaly detection across the attack surface.

**AI Approach:**
- **Method:** Graph-based anomaly detection on login/transaction patterns; ML-classified risk scoring
- **Training Data:** Risk control rules (4.1M records), blacklist (1,395 entries), WAF logs, login patterns
- **Output:** Security posture dashboard with anomaly alerts, automated blacklist updates

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Risk control rules | `iriskcontrolservice` | Rule count tables | 4.1M records | 🟢 Available |
| Blacklist | `iriskcontrolservice` | Blacklist tables | 1,395 entries | 🟢 Available |
| Risk logs | `iriskcontrolservice` | 24+ sharded log tables | TBD | 🟢 Available |
| WAF cache | Redis (`luckyus-waf`) | WAF state | Active | 🟢 Available |
| Login events | `salescrm` | Login/auth tables | — | 🟡 Needs verification |

---

## 5. Department 2: Marketing & Customer Analytics

### Overview

Marketing has the largest opportunity surface due to the combination of a large user base (277K registered users), significant engagement gaps (50.6% lapsed, 40% never-ordered), and rich behavioral data across the CDP (980K user state records), CRM (275K users), and campaign platforms (2.42M coupons, 6.4M A/B test records). The department also benefits from an already-deployed Customer Data Platform and A/B Testing infrastructure.

**Department Use Cases:** 10 | **GREEN:** 6 | **YELLOW:** 3 | **RED:** 1

---

### UC-MK-01: Customer 360 Unified Profile

**Priority:** P0 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 4.15

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 4 | CDP has 980K user states, CRM has 275K users, order history 466K+; join key `user_no` exists across systems |
| Business Impact | 5 | Foundation for all marketing AI — enables personalization, churn prediction, CLV |
| Technical Complexity | 3 | Entity resolution + feature store; moderate complexity |
| Cross-Department Value | 5 | Marketing, Sales, Operations, Executive, Product all benefit |
| Strategic Alignment | 5 | Core infrastructure for AI-powered customer experience |

**Business Problem:**
Customer data is siloed across 8+ databases: `salescrm` (CRM profiles), `isalescdp` (behavioral states), `salesorder` (purchase history), `salespayment` (payment data), `salesmarketing` (campaign exposure), `isalesdatamarketing` (segment assignments), `isalesmembermarketing` (member marketing), and `upush` (notification history). There is no unified view of a customer that spans acquisition channel → browse behavior → purchase history → campaign response → lifetime value.

The CDP contains 980K user state records and behavioral tracking, but it operates independently from the CRM's 275K user records and the order system's 466K+ orders. The `user_no` field (varchar) exists across most systems but has not been used to create a unified profile.

**AI Approach:**
- **Method:** Entity resolution using deterministic matching (`user_no`) + probabilistic matching (phone, device fingerprint) → Feature store (SageMaker Feature Store or custom on Redis)
- **Profile Schema:** Demographics, RFM scores (Recency/Frequency/Monetary), product preferences, channel preferences, campaign responsiveness, churn risk score, CLV prediction
- **Update Cadence:** Daily batch for historical features, near-real-time for behavioral signals
- **Output:** Customer 360 API accessible by all downstream AI use cases

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| CRM profiles | `salescrm` | Member tables | 275K users | 🟢 Available |
| CDP user states | `isalescdp` | User state/behavior tables | 980K records | 🟢 Available |
| Order history | `salesorder` | `t_sales_order_m` (sharded) | 466K+ orders | 🟢 Available |
| Payment data | `salespayment` | `t_sales_trade_m` (sharded) | 518K trades | 🟢 Available |
| Campaign exposure | `salesmarketing` | Campaign/coupon tables | 2.42M coupons | 🟢 Available |
| Push notifications | `upush` | SMS/push records | 2.3M records | 🟢 Available |
| Product preferences | `salesorder` | Order items table | 602K items | 🟢 Available |

**Cross-Department Impact:** Foundation for UC-MK-02 through UC-MK-10, UC-PR-02, UC-PR-03, UC-EX-01

---

### UC-MK-02: Churn Prediction & Win-Back

**Priority:** P0 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 4.30

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 5 | Order history with timestamps, user registration dates, purchase frequency — all available; 76,238 users already identified as 90+ days lapsed |
| Business Impact | 5 | 50.6% lapsed user base; recovering even 10% = ~7,600 reactivated users × $4.71 AOV × 12 orders/year = $430K/year |
| Technical Complexity | 4 | Standard binary classification (churn/no-churn); well-understood ML problem |
| Cross-Department Value | 3 | Marketing (campaigns), Product (retention features), Executive (growth metrics) |
| Strategic Alignment | 4 | Retention is cheaper than acquisition; critical for sustainable growth |

**Business Problem:**
The single most alarming metric in the customer dataset: **76,238 users (50.6% of all ordering customers) have not placed an order in 90+ days**. Only 12,285 users (8.2%) have ordered in the last 7 days. The repeat purchase distribution shows 84,341 users (55%+) have placed only a single order, indicating a severe "try once and leave" pattern.

Meanwhile, monthly new registrations have declined 53% from the Phase 2 baseline of ~25,000/month to a projected ~11,800 in February 2026. With acquisition slowing, retention becomes the critical growth lever.

**Churn Distribution (from live query):**

| Days Since Last Order | Users | % of Ordering Users |
|----------------------|-------|-------------------|
| 0-7 days (Active) | 12,285 | 8.2% |
| 8-30 days (At Risk) | 21,458 | 14.2% |
| 31-60 days (Cooling) | 19,836 | 13.2% |
| 61-90 days (Lapsing) | 20,575 | 13.7% |
| 90+ days (Lapsed) | 76,238 | 50.6% |

**AI Approach:**
- **Method:** Gradient Boosted Trees (XGBoost/LightGBM) for churn probability scoring
- **Features:** Days since last order, order frequency (orders/month), average order value, coupon usage rate, time between orders (variance), product diversity score, day-of-week pattern, store diversity
- **Target Variable:** Binary — churned (no order in 60+ days) vs. active
- **Output:** Daily churn risk scores (0-100) for all active/at-risk users → trigger win-back campaigns at score thresholds
- **Win-Back Actions:** Personalized coupon (based on past product preferences), push notification, SMS (2.3M records in upush), email

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Order timestamps | `salesorder` | `t_sales_order_m` | 466K+ orders | 🟢 Available |
| User registration | `salescrm` | Member tables | 275K users | 🟢 Available |
| Order items | `salesorder` | Order items table | 602K items | 🟢 Available |
| Coupon redemption | `salesmarketing` | Coupon usage tables | 2.42M coupons | 🟢 Available |
| Push/SMS history | `upush` | Push records | 2.3M records | 🟢 Available |

**Estimated ROI:** $200-430K/year (conservative: 5% win-back rate on 76K lapsed users × $4.71 AOV × 12 orders/year = $216K)

---

### UC-MK-03: Coupon ROI Optimizer

**Priority:** P1 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 4.10

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 5 | 2.42M coupons distributed, 37.3M expired (massive waste signal), 6.4M A/B test records |
| Business Impact | 4 | 37.3M expired coupons = massive promotional waste; optimize discount depth vs. conversion |
| Technical Complexity | 4 | Causal inference (uplift modeling) on existing A/B test data |
| Cross-Department Value | 3 | Marketing, Finance, Executive |
| Strategic Alignment | 4 | Unit economics improvement critical for profitability at scale |

**Business Problem:**
**37.3 million coupons have expired unused.** While the exact face value of this waste is not calculated, even at a conservative $1 average discount, this represents tens of millions of dollars in promotional budget that generated zero incremental revenue. The coupon system distributes aggressively (2.42M active coupons in circulation) but lacks intelligence on:
- Which users would have purchased anyway (deadweight loss)
- Optimal discount depth per user segment (some users convert at 10% off, others need 40%)
- Timing optimization (when is a user most likely to respond to a coupon?)
- Cannibalization effects (does a latte coupon steal from full-price cold brew purchases?)

The existing A/B testing platform (6.4M experiment records) provides the foundation for causal inference.

**AI Approach:**
- **Method:** Uplift modeling (causal ML) — predict incremental conversion lift per user per offer type
- **Training Data:** A/B test results (6.4M records) × coupon redemption data × order history
- **Model:** Two-model approach (T-learner): P(purchase|coupon) - P(purchase|no coupon) = uplift
- **Output:** Per-user optimal coupon recommendation (product, discount %, timing, channel)

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Coupon distribution | `salesmarketing` | Coupon tables | 2.42M active | 🟢 Available |
| Coupon expiration | `salesmarketing` | Expired coupons | 37.3M expired | 🟢 Available |
| A/B test results | `salesmarketing` | Experiment tables | 6.4M records | 🟢 Available |
| Order conversion | `salesorder` | Order tables | 466K+ orders | 🟢 Available |
| User segments | `isalescdp` | CDP user states | 980K states | 🟢 Available |

---

### UC-MK-04: Next-Best-Action Engine

**Priority:** P1 | **Data Readiness:** 🟡 YELLOW | **Weighted Score:** 3.65

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 3 | CDP behavioral states exist but real-time event stream not piped; action catalog not defined |
| Business Impact | 4 | Real-time personalization increases conversion 15-30% in industry benchmarks |
| Technical Complexity | 2 | Real-time scoring requires streaming infrastructure (Kinesis/MSK integration) |
| Cross-Department Value | 4 | Marketing, Product, Operations |
| Strategic Alignment | 4 | Differentiator in US coffee market — no competitor does real-time AI recommendations |

**Business Problem:**
The app-only ordering model creates a unique opportunity: every customer interaction happens through a digital channel, enabling real-time personalization. Currently, all users see the same menu, same promotions, same ordering experience. The CDP tracks behavioral states (980K records) but this data is not used to customize the user experience in real-time.

**AI Approach:**
- **Method:** Multi-armed bandit / contextual bandit for action selection
- **Actions:** Product recommendation, coupon offer, upsell suggestion, reorder prompt, loyalty nudge
- **Context:** Time of day, weather, user's past orders, days since last visit, active promotions
- **Output:** Real-time action selection API (response time <100ms) called during app session

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| CDP behavioral states | `isalescdp` | User state tables | 980K records | 🟢 Available |
| Order history | `salesorder` | Order tables | 466K+ | 🟢 Available |
| Real-time event stream | MSK/Kafka | 308 topics available | — | 🟡 Needs integration |
| Action catalog | — | Not defined | — | 🟡 Gap |

---

### UC-MK-05: Customer Lifetime Value (CLV) Prediction

**Priority:** P2 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 3.35

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 4 | Full order history with timestamps, user tenure, payment data; 8.5 months of behavioral data |
| Business Impact | 3 | Enables acquisition cost caps, retention budget allocation, VIP identification |
| Technical Complexity | 4 | BG/NBD + Gamma-Gamma model (standard CLV approach) |
| Cross-Department Value | 3 | Marketing, Finance, Executive |
| Strategic Alignment | 3 | Supports unit economics optimization |

**Business Problem:**
Without CLV prediction, marketing treats all customers equally. The top 3 "super users" have spent $141,000 collectively (one spent $82,203 — a delivery/corporate account), while 84,341 users have placed only a single order. Marketing needs to know which users are worth $5 to reactivate vs. $50.

**AI Approach:**
- **Method:** BG/NBD model (purchase frequency) + Gamma-Gamma model (monetary value) = predicted CLV
- **Features:** Recency, frequency, monetary value, tenure, product category mix
- **Output:** Predicted 12-month CLV per customer; segment into VIP/Growth/Maintain/Let-Go

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Order history | `salesorder` | `t_sales_order_m` | 466K+ orders | 🟢 Available |
| Payment amounts | `salespayment` | `t_sales_trade_m` | 518K trades | 🟢 Available |
| Registration dates | `salescrm` | Member tables | 275K users | 🟢 Available |
| Product preferences | `salesorder` | Order items | 602K items | 🟢 Available |

---

### UC-MK-06: Push Notification Optimizer

**Priority:** P1 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 3.60

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 4 | 2.3M push/SMS records in `upush`, delivery timestamps, open/conversion tracking |
| Business Impact | 3 | Optimize send timing and content; reduce notification fatigue and opt-outs |
| Technical Complexity | 4 | Multi-armed bandit for timing/content optimization; standard |
| Cross-Department Value | 2 | Primarily Marketing |
| Strategic Alignment | 3 | Supports retention strategy |

**Business Problem:**
The push notification system (`upush`) has sent 2.3M messages. Without optimization, notifications are sent at fixed times to all users, regardless of individual preferences. Industry benchmarks show optimized push timing can increase open rates by 40-60%.

**AI Approach:**
- **Method:** Per-user optimal send time prediction + content personalization
- **Training Data:** Push/SMS send timestamps, open events, subsequent orders within conversion window
- **Output:** Per-user send time preference, optimal notification frequency, content type ranking

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Push records | `upush` | SMS/push tables | 2.3M records | 🟢 Available |
| Conversion events | `salesorder` | Orders post-notification | 466K+ orders | 🟢 Available |
| User preferences | `isalescdp` | CDP states | 980K records | 🟢 Available |

---

### UC-MK-07: A/B Test Auto-Optimization

**Priority:** P1 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 3.80

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 5 | 6.4M A/B test experiment records already collected; platform is operational |
| Business Impact | 3 | Faster experiment conclusions, automatic winner selection, reduced manual analysis |
| Technical Complexity | 4 | Bayesian A/B testing with auto-stopping rules; builds on existing platform |
| Cross-Department Value | 4 | Marketing, Product, Operations can all run experiments |
| Strategic Alignment | 3 | Accelerates data-driven decision making |

**Business Problem:**
The A/B testing platform has generated 6.4M experiment records, proving it is actively used. However, experiment analysis and winner selection are manual processes. Tests may run too long (wasting traffic) or be stopped too early (insufficient statistical power).

**AI Approach:**
- **Method:** Bayesian A/B testing with Thompson Sampling for automatic traffic allocation
- **Auto-stopping:** Expected loss criterion — stop when P(wrong decision) < 1%
- **Output:** Real-time experiment dashboard with auto-winner declaration and traffic shifting

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Experiment records | `salesmarketing` | A/B test tables | 6.4M records | 🟢 Available |
| Conversion events | `salesorder` | Orders linked to experiments | 466K+ orders | 🟢 Available |
| User assignments | `isalescdp` | Experiment group assignments | — | 🟢 Available |

---

### UC-MK-08: Social Listening & Sentiment Analysis

**Priority:** P3 | **Data Readiness:** 🔴 RED | **Weighted Score:** 2.45

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 1 | No social media data collected; requires external API integration |
| Business Impact | 3 | Brand reputation monitoring; competitive intelligence |
| Technical Complexity | 2 | NLP sentiment analysis; external API costs |
| Cross-Department Value | 3 | Marketing, Product, Executive |
| Strategic Alignment | 3 | Important for brand management in US market |

**Business Problem:**
Luckin Coffee USA has no visibility into customer sentiment on social media (TikTok, Instagram, Yelp, Google Reviews, X/Twitter). In the US market, a single viral negative experience can significantly impact a new brand's trajectory.

**AI Approach:**
- **Method:** NLP sentiment analysis on scraped/API social media content
- **Sources:** Yelp reviews, Google Maps reviews, TikTok mentions, Instagram hashtags, X/Twitter mentions
- **Output:** Sentiment dashboard with trend tracking, alert on negative sentiment spikes

**Data Dependencies:** All external — requires new data collection infrastructure.

---

### UC-MK-09: Referral Network Analysis

**Priority:** P3 | **Data Readiness:** 🟡 YELLOW | **Weighted Score:** 2.55

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 3 | Some referral data in marketing tables; not confirmed as comprehensive |
| Business Impact | 2 | Identify influencer customers; optimize referral program |
| Technical Complexity | 3 | Graph analysis on referral chains |
| Cross-Department Value | 2 | Marketing |
| Strategic Alignment | 3 | Word-of-mouth acquisition is cheapest channel |

**Business Problem:**
In the Manhattan market, word-of-mouth and social referrals are critical acquisition channels. Understanding which customers drive referral chains and what motivates sharing can dramatically reduce customer acquisition costs.

**AI Approach:**
- **Method:** Graph analysis on referral chain data; identify super-connectors
- **Output:** Referral influence scores, optimal referral incentive structures

---

### UC-MK-10: Channel Attribution Modeling

**Priority:** P3 | **Data Readiness:** 🔴 RED | **Weighted Score:** 2.50

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 1 | No multi-touch attribution data; app installs not tracked by source |
| Business Impact | 3 | Optimize marketing spend across channels (organic, paid, referral, PR) |
| Technical Complexity | 2 | Multi-touch attribution with Shapley values |
| Cross-Department Value | 2 | Marketing, Finance |
| Strategic Alignment | 3 | Critical as marketing spend increases with expansion |

**Business Problem:**
Luckin Coffee USA cannot currently answer "which marketing channel drives the most valuable customers?" The app-only model means all orders flow through one channel, but user acquisition sources (organic search, social media, PR, walk-by, referral) are not tracked.

**AI Approach:**
- **Method:** Multi-touch attribution using Shapley values or data-driven attribution
- **Prerequisite:** Implement UTM tracking, app install attribution (AppsFlyer/Adjust), and referral source tracking

---

## 6. Department 3: Accounting & Finance

### Overview

Finance has the most critical regulatory gap in the entire organization: the `fi_tax` database is completely empty despite $2.19M in cumulative revenue across multiple US jurisdictions. This creates immediate compliance risk. On the positive side, the payment processing infrastructure is mature (518K trades, 502K fee records) and the multi-system reconciliation architecture exists but is largely manual.

**Department Use Cases:** 5 | **GREEN:** 2 | **YELLOW:** 1 | **RED:** 2

---

### UC-FN-01: Tax Compliance Automation

**Priority:** P0 | **Data Readiness:** 🔴 RED | **Weighted Score:** 4.45

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 1 | `fi_tax` database is COMPLETELY EMPTY — zero rows in all tables |
| Business Impact | 5 | REGULATORY RISK: $2.19M revenue across Manhattan (NYC + NY State tax), JFK (airport tax zone), potentially NJ delivery. Tax non-compliance penalties can include fines, interest, and business license revocation |
| Technical Complexity | 4 | Tax calculation rules are well-defined; integration with payment system straightforward |
| Cross-Department Value | 3 | Finance, Executive, Legal |
| Strategic Alignment | 5 | Expansion to new boroughs/states impossible without tax compliance infrastructure |

**Business Problem:**
**This is the highest-priority finding in the entire AI transformation assessment.** The `fi_tax` database contains zero data despite 8.5 months of operations and $2.19M in revenue. US tax compliance is jurisdictional and complex:
- **New York City:** NYC sales tax (4.5%) + NY State sales tax (4%) + Metropolitan Commuter Transportation District surcharge (0.375%) = **8.875% combined**
- **JFK Airport:** Potentially different tax zone within Queens County
- **Delivery:** May cross jurisdiction boundaries (Manhattan ↔ Brooklyn/Queens/NJ)
- **Prepared food exemptions:** Hot coffee may have different tax treatment than cold beverages and food items

The executive summary scorecard rates Tax & Regulatory Compliance as **F grade** — the only F in the entire assessment.

**AI Approach:**
- **Method:** Rules-based tax calculation engine + ML-powered audit/anomaly detection
- **Phase 1 (Immediate):** Implement tax calculation on all new transactions using existing order data (store location → tax zone → rate lookup → line-item tax calculation)
- **Phase 2 (AI):** Anomaly detection on tax calculations to catch miscategorizations, jurisdiction errors, exemption misapplication
- **Phase 3 (Predictive):** Tax liability forecasting for financial planning and cash management

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Tax tables | `fitax` | All tables | **0 rows** | 🔴 EMPTY |
| Order data | `salesorder` | Orders with location | 466K+ orders | 🟢 Available |
| Payment data | `salespayment` | Payment amounts | 518K trades | 🟢 Available |
| Store locations | `opshop` | Store addresses/zones | 11-16 stores | 🟢 Available |
| Tax rate tables | External | IRS/NY State/NYC rates | — | 🔴 Not collected |

**Estimated Risk:** Potential back-tax liability of $150-195K (8.875% × $2.19M) plus penalties and interest. State enforcement actions could include business license revocation.

---

### UC-FN-02: Automated Revenue Reconciliation

**Priority:** P0 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 4.35

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 5 | Order (466K+), payment (518K trades), and accounting (ifiaccounting) data all available; join key `order_no`/`trade_no` exists |
| Business Impact | 5 | Eliminate manual 3-way matching; detect revenue leakage; SOX-adjacent compliance |
| Technical Complexity | 4 | Rules-based matching with ML for exception handling; well-defined problem |
| Cross-Department Value | 3 | Finance, Executive |
| Strategic Alignment | 4 | Required for audit readiness as company scales |

**Business Problem:**
Revenue reconciliation requires matching across three systems:
1. **Orders** (`salesorder`): What was ordered and fulfilled
2. **Payments** (`salespayment`): What was charged and collected
3. **Accounting** (`ifiaccounting`): What was booked to the general ledger

Currently, this 3-way match is manual or semi-automated. With 466K+ orders and 518K trades, manual reconciliation is unsustainable. Key challenges include:
- **Type mismatch:** `order_id` is `bigint` in `salesorder` but `varchar` in `salespayment` — a data engineering issue that must be resolved
- **Timing differences:** Orders, payments, and accounting entries may post on different dates
- **Refund tracking:** Refund orders need to be matched back to original transactions
- **NZD contamination:** 21,245 Cook Islands test orders mixed with US production data

**AI Approach:**
- **Method:** Deterministic matching (order_no/trade_no) + ML for fuzzy matching of exceptions
- **Exception Types:** Amount mismatches, timing gaps, missing counterparts, duplicate entries
- **Model:** Gradient Boosted Trees for exception classification (true discrepancy vs. timing delay vs. data entry error)
- **Output:** Daily reconciliation report with exception drill-down, trend analysis

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Orders | `salesorder` | `t_sales_order_m` | 466K+ | 🟢 Available |
| Payments | `salespayment` | `t_sales_trade_m` | 518K trades | 🟢 Available |
| Fees | `salespayment` | Fee records | 502K records | 🟢 Available |
| Accounting | `ifiaccounting` | GL entries | TBD | 🟢 Available |
| Reconciliation | `iunifiedreconcile` | Recon records | TBD | 🟢 Available |

**Data Quality Notes:**
- `order_id` type mismatch between systems (bigint vs. varchar) requires type casting in joins
- 21,245 NZD test orders must be filtered out of reconciliation
- Payment fee records (502K) should reconcile against payment processor statements

---

### UC-FN-03: Payment Fraud Detection

**Priority:** P1 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 3.95

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 4 | 518K trades, risk control service (4.1M rules, 1,395 blacklist), payment fee data |
| Business Impact | 4 | Prevent chargebacks, detect promo abuse, protect payment processing |
| Technical Complexity | 3 | Anomaly detection on transaction patterns; real-time scoring preferred |
| Cross-Department Value | 3 | Finance, IT, Executive |
| Strategic Alignment | 3 | Essential for payment integrity at scale |

**Business Problem:**
With 518K payment trades processed and a risk control service that has accumulated 4.1M rule count records and 1,395 blacklist entries, there is clearly an existing fraud detection effort. However, the system appears rules-based rather than ML-powered, meaning it cannot adapt to evolving fraud patterns.

Specific risks:
- Promotional abuse (creating multiple accounts for new-user coupons)
- Payment method fraud (stolen credit cards)
- Refund fraud (ordering then disputing charges)
- Corporate account misuse (top user spent $82,203 — verify legitimacy)

**AI Approach:**
- **Method:** Isolation Forest for transaction anomaly detection + supervised classification for known fraud patterns
- **Features:** Transaction amount, frequency, time patterns, device fingerprint, payment method diversity, coupon usage rate, refund rate
- **Real-time:** Score each transaction at payment time; flag high-risk for review
- **Output:** Fraud risk score per transaction, automated blocks for high-confidence fraud

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Transactions | `salespayment` | `t_sales_trade_m` | 518K trades | 🟢 Available |
| Risk control rules | `iriskcontrolservice` | Rule tables | 4.1M records | 🟢 Available |
| Blacklist | `iriskcontrolservice` | Blacklist tables | 1,395 entries | 🟢 Available |
| Fee records | `salespayment` | Fee tables | 502K records | 🟢 Available |

---

### UC-FN-04: Payment Channel Cost Optimization

**Priority:** P2 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 3.00

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 4 | 502K payment fee records with processor details |
| Business Impact | 2 | Optimize payment processing costs; savings scale with volume |
| Technical Complexity | 4 | Analytics + optimization; well-defined problem |
| Cross-Department Value | 2 | Finance |
| Strategic Alignment | 3 | Unit economics improvement |

**Business Problem:**
With 502K payment fee records, there is granular data on processing costs by payment channel. As order volume scales to 50+ stores, even basis-point improvements in payment processing fees compound to significant savings.

**AI Approach:**
- **Method:** Cost analysis by payment method/processor + routing optimization
- **Output:** Recommended payment routing rules to minimize processing costs while maintaining user experience

---

### UC-FN-05: Financial Forecasting & Scenario Modeling

**Priority:** P3 | **Data Readiness:** 🔴 RED | **Weighted Score:** 2.65

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 2 | Revenue data available but tax data missing, P&L not in database, cost allocation incomplete |
| Business Impact | 3 | Budget planning, investor reporting, expansion financial modeling |
| Technical Complexity | 3 | Time-series forecasting + Monte Carlo simulation |
| Cross-Department Value | 3 | Finance, Executive |
| Strategic Alignment | 4 | Critical for fundraising and expansion planning |

**Business Problem:**
Financial forecasting requires complete P&L data: revenue (available), COGS (partially available via SCM), operating expenses (not in database), and taxes (empty). Without a complete financial picture in the data system, AI-powered forecasting cannot be accurate.

---

## 7. Department 4: Product & Menu Innovation

### Overview

Product analytics benefits from rich transactional data: 602K order items across the full menu, clear category breakdowns (Fresh Coffee 40%, Classic 18%, Matcha 10%, Food 9%, Cold Brew 7%), and the dominance of the Iced Coconut Latte as a signature product (70K orders, 15% of volume). The A/B testing platform (6.4M records) also supports product experimentation.

**Department Use Cases:** 5 | **GREEN:** 4 | **YELLOW:** 1 | **RED:** 0

---

### UC-PR-01: Menu Engineering Matrix (BCG Analysis)

**Priority:** P1 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 3.90

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 5 | 602K order items with product codes, revenue by category, SPU master data (1,448 goods in pubdm) |
| Business Impact | 4 | Identify Stars (high margin + high volume), eliminate Dogs, optimize menu for profitability |
| Technical Complexity | 5 | BCG matrix is analytics, not ML; standard calculation |
| Cross-Department Value | 3 | Product, Operations, Finance |
| Strategic Alignment | 4 | Menu optimization directly impacts unit economics |

**Business Problem:**
The menu contains products across 5+ categories with varying popularity and (presumed) profitability. The Iced Coconut Latte dominates with 70K orders (15% of volume), but this concentration creates risk. Menu engineering analysis would classify each product as:
- **Star:** High popularity + High margin → Promote aggressively
- **Plow Horse:** High popularity + Low margin → Re-engineer or price adjust
- **Puzzle:** Low popularity + High margin → Better positioning/marketing
- **Dog:** Low popularity + Low margin → Consider removal

**AI Approach:**
- **Method:** BCG matrix calculation: popularity (% of orders) × contribution margin (price - COGS)
- **Enhancement:** ML-powered product affinity analysis — which products are purchased together?
- **Output:** Menu engineering dashboard with quadrant classification, affinity pairs, seasonal trends

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Order items | `salesorder` | Order item details | 602K items | 🟢 Available |
| Product master | `pubdm` | `luckyus_pub_dm.goods` | 1,448 goods | 🟢 Available |
| Category data | `scmcommodity` | Product categories | TBD | 🟢 Available |
| Recipe costs | `opproduction` | Formula/recipe data | 32K formulas | 🟢 Available |

---

### UC-PR-02: Personalized Product Recommendations

**Priority:** P2 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 3.50

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 4 | 602K order items with user-product mappings; collaborative filtering viable |
| Business Impact | 3 | Increase AOV (+$0.50-1.00 per order from upsell/cross-sell); boost discovery of new products |
| Technical Complexity | 3 | Collaborative filtering + content-based hybrid; standard recommender system |
| Cross-Department Value | 3 | Product, Marketing, Operations |
| Strategic Alignment | 4 | Core to app-only experience differentiation |

**Business Problem:**
All users currently see the same menu order and product suggestions. With 602K order items and 1,448 products in the master catalog, there is sufficient data for collaborative filtering. The repeat purchase distribution (84,341 single-order users) suggests that product discovery failure may contribute to low retention — users who don't find products they love don't return.

**AI Approach:**
- **Method:** Hybrid recommender: collaborative filtering (users who bought X also bought Y) + content-based (product attributes: hot/cold, dairy/non-dairy, caffeine level) + contextual (time of day, weather, season)
- **Output:** Personalized product ranking in the app; "Recommended for you" section; "Frequently bought together" suggestions

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| User-product matrix | `salesorder` | Order items with user_no | 602K items | 🟢 Available |
| Product attributes | `pubdm` / `scmcommodity` | Product metadata | 1,448 goods | 🟢 Available |
| User profiles | `isalescdp` | CDP behavioral states | 980K states | 🟢 Available |

---

### UC-PR-03: Price Elasticity Modeling

**Priority:** P2 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 3.25

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 4 | Coupon discount depth variation provides natural price experiments; AOV growth from $1.77→$5.03 |
| Business Impact | 3 | Optimize pricing to maximize revenue; understand price sensitivity by segment |
| Technical Complexity | 3 | Instrumental variable regression using coupon randomization as natural experiment |
| Cross-Department Value | 3 | Product, Marketing, Finance |
| Strategic Alignment | 4 | Critical for sustainable pricing strategy (current AOV $5.03 vs. industry $6.50-8.00) |

**Business Problem:**
AOV has risen 181% from $1.77 at launch to $5.03, reflecting reduced discounting. However, $5.03 is still below the US specialty coffee benchmark of $6.50-$8.00. Understanding price elasticity per product category and per user segment is critical for optimizing the transition to sustainable pricing without losing price-sensitive customers.

**AI Approach:**
- **Method:** Causal inference using coupon discount variation as instrumental variable
- **Training Data:** Orders with coupon amounts, orders without coupons, A/B test data from pricing experiments
- **Output:** Price elasticity curves per product category; optimal price point recommendations; price sensitivity segmentation

---

### UC-PR-04: New Product Launch Predictor

**Priority:** P2 | **Data Readiness:** 🟡 YELLOW | **Weighted Score:** 3.05

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 3 | Limited launch history (only 8.5 months); menu changes not well-documented |
| Business Impact | 3 | Reduce new product failure rate; optimize launch marketing spend |
| Technical Complexity | 3 | Analogous product matching + early signal detection |
| Cross-Department Value | 3 | Product, Marketing, Operations |
| Strategic Alignment | 3 | Supports menu innovation strategy |

**Business Problem:**
New product launches are high-risk investments (marketing, ingredient sourcing, barista training). A predictor that estimates launch performance based on analogous product performance, user taste profiles, and market trends would reduce waste and accelerate successful launches.

**AI Approach:**
- **Method:** Analogous product matching (find existing products most similar to new launch) + early signal detection (predict 30-day performance from first 3 days of orders)
- **Training Data:** Historical product launch data (limited — 8.5 months only), product attribute similarities
- **Output:** Predicted first-month sales volume, optimal launch marketing budget

---

### UC-PR-05: Recipe Cost Optimization

**Priority:** P2 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 2.95

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 4 | 32K formula/recipe records in production system; ingredient cost data in SCM |
| Business Impact | 2 | Reduce COGS by optimizing ingredient ratios within quality constraints |
| Technical Complexity | 3 | Optimization under constraints; ingredient substitution modeling |
| Cross-Department Value | 3 | Product, Operations, SCM, Finance |
| Strategic Alignment | 3 | Unit economics improvement |

**Business Problem:**
With 32K formula/recipe records and ingredient cost data from the SCM system, there is an opportunity to optimize recipe formulations to reduce cost while maintaining taste quality. Even a 2-3% COGS reduction on $2.19M revenue = $44-66K/year savings.

**AI Approach:**
- **Method:** Constrained optimization — minimize ingredient cost subject to taste quality constraints (from customer satisfaction/rating data)
- **Output:** Optimized recipe formulations with cost comparison; ingredient substitution recommendations

---

## 8. Department 5: Store Operations

### Overview

Store operations has rich production data (502K production records, 204-second average production time) and scheduling data (47.5K clock-in records, 324 employees), but the critical IoT infrastructure is severely degraded (216 devices, only 43% operational — 57% offline). Operations AI use cases range from immediately actionable (production time prediction) to infrastructure-dependent (IoT predictive maintenance).

**Department Use Cases:** 6 | **GREEN:** 3 | **YELLOW:** 2 | **RED:** 1

---

### UC-OP-01: Dynamic Staffing Optimizer

**Priority:** P2 | **Data Readiness:** 🟡 YELLOW | **Weighted Score:** 3.55

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 3 | 47.5K clock-in records, 324 employees; demand forecasting exists (2.5M predictions); gap: shift preference data, skill matrix |
| Business Impact | 4 | NYC Fair Workweek Law compliance; labor is largest controllable cost; understaffing causes service delays, overstaffing wastes labor budget |
| Technical Complexity | 3 | Demand forecast → staff requirement model → schedule optimization |
| Cross-Department Value | 3 | Operations, Finance, HR |
| Strategic Alignment | 4 | Labor optimization critical at 50+ stores |

**Business Problem:**
With 324 employees across 11 stores, labor scheduling is complex. NYC's Fair Workweek Law requires predictable schedules for fast-food workers, with premium pay for schedule changes within 72 hours. Current scheduling appears manual, using 47.5K clock-in records for time tracking but no evidence of demand-driven scheduling.

The demand forecasting engine (2.5M predictions) already exists but is not connected to staffing decisions.

**AI Approach:**
- **Method:** Demand forecast (hourly, per store) → staffing requirements model (orders/hour → baristas needed) → schedule optimization (integer programming with Fair Workweek constraints)
- **Constraints:** NYC Fair Workweek Law (14-day advance notice, premium pay for changes), employee availability, skill requirements (trainee vs. experienced), overtime limits
- **Output:** Optimal weekly schedule per store; real-time adjustment recommendations

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Clock-in records | `opempefficiency` | Attendance tables | 47.5K records | 🟢 Available |
| Employee roster | `opempefficiency` | Employee tables | 324 employees | 🟢 Available |
| Demand forecasts | `ireplenishment` | Prediction tables | 2.5M predictions | 🟢 Available |
| Hourly order volume | `salesorder` | Orders with timestamps | 466K+ orders | 🟢 Available |
| Shift preferences | — | Not collected | — | 🟡 Gap |
| Skill matrix | — | Not documented | — | 🟡 Gap |

---

### UC-OP-02: Store Performance Anomaly Detection

**Priority:** P1 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 4.00

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 5 | Per-store revenue, order counts, production times, quality metrics — all available across 11 stores |
| Business Impact | 4 | Early detection of underperforming stores; identify operational issues before they compound |
| Technical Complexity | 4 | Comparative analytics + statistical process control; straightforward |
| Cross-Department Value | 4 | Operations, Executive, Finance |
| Strategic Alignment | 5 | Essential for managing growing store portfolio |

**Business Problem:**
With 11 stores generating $35,000-$50,000/month at maturity, performance variation is significant. The flagship 8th Avenue store declined from $106,000/month to $52,000/month — was this expected cannibalization or an operational issue? Without anomaly detection, store-level problems are discovered too late.

**AI Approach:**
- **Method:** Statistical process control (X-bar chart) on per-store KPIs; Z-score anomaly detection; peer comparison (normalize for store age, location type, foot traffic)
- **KPIs Monitored:** Daily revenue, order count, AOV, production time, order fulfillment rate, customer complaints, refund rate
- **Output:** Daily store health dashboard with anomaly flags; weekly comparative ranking

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Store orders | `salesorder` | Orders by store | 466K+ orders | 🟢 Available |
| Store revenue | `salespayment` | Revenue by store | 518K trades | 🟢 Available |
| Production times | `opproduction` | Production records | 502K records | 🟢 Available |
| Store master | `opshop` | Store details | 11-16 stores | 🟢 Available |
| Quality control | `opqualitycontrol` | QC records | 136K expiry logs, 100K task forms | 🟢 Available |

---

### UC-OP-03: Production Time Predictor

**Priority:** P1 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 3.75

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 5 | 502K production records with timestamps, product types, store IDs; 587.6K cup orders in IoT |
| Business Impact | 3 | Customer wait time management; production scheduling optimization |
| Technical Complexity | 4 | Regression on production time given order composition, queue depth, time of day |
| Cross-Department Value | 2 | Operations |
| Strategic Alignment | 3 | Customer experience improvement |

**Business Problem:**
Average production time is 204 seconds (3.4 minutes), with a 36% improvement since launch. However, production time varies significantly by product complexity, concurrent order volume, and time of day. Accurate production time prediction enables:
- Realistic wait time quotes in the app
- Better order throttling during peak hours
- Production sequence optimization (batch similar drinks)

**AI Approach:**
- **Method:** Regression model: production_time = f(product_type, queue_depth, time_of_day, store_id, barista_experience)
- **Training Data:** 502K production records with start/end timestamps, product codes
- **Output:** Per-order estimated production time displayed in app; production sequencing recommendations

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Production records | `opproduction` | Production tables | 502K records | 🟢 Available |
| Cup orders (IoT) | `iotplatform` | Cup order tables | 587.6K records | 🟢 Available |
| Product complexity | `pubdm` | Product attributes | 1,448 goods | 🟢 Available |
| Order queue | `salesorder` | Concurrent orders | 466K+ orders | 🟢 Available |

---

### UC-OP-04: IoT Predictive Maintenance

**Priority:** P2 | **Data Readiness:** 🟡 YELLOW | **Weighted Score:** 3.15

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 3 | 216 devices registered, 587.6K cup orders; but 57% of devices are OFFLINE — limited telemetry from down devices |
| Business Impact | 4 | 57% offline rate means machines are breaking faster than they're being repaired; each offline machine reduces store capacity |
| Technical Complexity | 2 | Time-series prediction on device health metrics; requires IoT data pipeline |
| Cross-Department Value | 3 | Operations, IT, Finance |
| Strategic Alignment | 4 | Equipment reliability critical at scale |

**Business Problem:**
**57% of IoT devices are offline** (only 43% operational). This is a critical operational issue — offline coffee machines, grinders, or dispensers directly reduce store throughput capacity. The `iotplatform` database contains 587.6K cup order records and device registration data, but the offline devices are not reporting telemetry, making predictive maintenance challenging.

**AI Approach:**
- **Method:** Survival analysis (time-to-failure prediction) on device operational data
- **Training Data:** Device registration dates, operational timestamps, cup order volumes per device, failure events (inferred from offline transitions)
- **Output:** Predicted failure date per device; maintenance scheduling recommendations; device replacement prioritization

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Device registry | `iotplatform` | Device tables | 216 devices | 🟢 Available |
| Cup orders | `iotplatform` | Cup order tables | 587.6K records | 🟢 Available |
| Device telemetry | `iotplatform` | Status/health data | Limited (57% offline) | 🟡 Degraded |
| Maintenance logs | — | Not structured | — | 🟡 Gap |

---

### UC-OP-05: Queue/Wait Time Management

**Priority:** P3 | **Data Readiness:** 🟡 YELLOW | **Weighted Score:** 2.70

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 3 | Order timestamps and production timestamps available; real-time queue depth not tracked separately |
| Business Impact | 3 | Customer experience optimization; dynamic throttling during peak |
| Technical Complexity | 2 | Real-time system requires streaming architecture |
| Cross-Department Value | 2 | Operations |
| Strategic Alignment | 3 | Customer experience at scale |

**Business Problem:**
During peak hours (9-10 AM, 1-2 PM), order queues may build up. Without real-time queue visibility, the app cannot provide accurate wait time estimates or dynamically throttle order acceptance.

**AI Approach:**
- **Method:** Queuing theory model (M/M/c) calibrated with actual production time data
- **Real-time:** Ingest order stream + production completion stream → calculate current queue depth → estimate wait time
- **Output:** Real-time wait time display in app; dynamic order throttling; staff alert for high-queue situations

---

### UC-OP-06: New Store Ramp Predictor

**Priority:** P3 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 2.75

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 4 | 11 store openings with daily revenue trajectories; maturity curve data available |
| Business Impact | 2 | Better planning for new store launches; resource allocation |
| Technical Complexity | 4 | Growth curve fitting with small sample (11 stores) |
| Cross-Department Value | 3 | Operations, Finance, Executive |
| Strategic Alignment | 4 | Directly supports expansion planning |

**Business Problem:**
Current data shows new stores reach steady-state performance within approximately 4 weeks. But the prediction needs more nuance: what determines whether a store reaches $35K/month vs. $50K/month at maturity? With only 11 store openings, the sample size is small, but the existing site selection ML model (R²=0.94) can provide features.

**AI Approach:**
- **Method:** Growth curve fitting (logistic/Gompertz) + site selection features for maturity level prediction
- **Output:** Predicted revenue trajectory (week 1-12) for each new store; resource planning recommendations

---

## 9. Department 6: Supply Chain & Inventory

### Overview

The SCM domain has the richest data infrastructure: 9 dedicated databases with 1,044 tables, 9.1M stock change events, 2.5M demand forecasting predictions, 694 purchase orders, and 1,670 shipment records. Critically, the demand forecasting engine is already deployed and operational — making SCM the department with the most mature AI foundation.

**Department Use Cases:** 5 | **GREEN:** 3 | **YELLOW:** 2 | **RED:** 0

---

### UC-SC-01: Demand Forecast Accuracy Monitor

**Priority:** P0 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 4.20

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 5 | 2.5M demand predictions in `ireplenishment`; actual sales data in `salesorder`; complete feedback loop possible |
| Business Impact | 5 | Demand forecasting drives inventory ($9.1M stock events), staffing (47.5K clock-ins), and purchasing (694 POs) — inaccuracy cascades through entire supply chain |
| Technical Complexity | 5 | Monitoring is analytics, not new ML; join predictions to actuals and compute MAPE/RMSE |
| Cross-Department Value | 4 | SCM, Operations, Finance |
| Strategic Alignment | 4 | Forecast accuracy is foundation for SCM AI |

**Business Problem:**
The demand forecasting engine has generated **2.5 million predictions** — a remarkable AI asset for an 11-store chain. However, there is no evidence of a systematic feedback loop that compares predictions to actual sales. Without accuracy monitoring:
- Over-predictions cause waste (perishable ingredients spoil)
- Under-predictions cause stockouts (lost sales, customer dissatisfaction)
- Model drift goes undetected (seasonal patterns change, new stores shift demand)

**AI Approach:**
- **Method:** Join demand predictions to actual sales by (date, store, product) → compute accuracy metrics
- **Metrics:** MAPE (Mean Absolute Percentage Error), RMSE, bias (systematic over/under-prediction), accuracy by product category, accuracy by store
- **Alerting:** Flag when accuracy drops below threshold (e.g., MAPE > 30%); trigger model retraining
- **Output:** Forecast accuracy dashboard; model drift alerts; retraining recommendations

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Demand predictions | `ireplenishment` | Prediction tables | 2.5M records | 🟢 Available |
| Actual sales | `salesorder` | Daily order aggregates | 466K+ orders | 🟢 Available |
| Product master | `pubdm` | Product catalog | 1,448 goods | 🟢 Available |
| Store master | `opshop` | Store catalog | 11-16 stores | 🟢 Available |

**Quick Win Potential:** HIGH — Forecast accuracy dashboard achievable in 1-2 weeks with SQL joins

---

### UC-SC-02: Waste Prediction & Reduction

**Priority:** P1 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 3.85

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 4 | 9.1M stock change events; quality control expiry logs (136K records); production records (502K) |
| Business Impact | 4 | Reduce ingredient waste; 2-3% COGS reduction on $2.19M = $44-66K/year |
| Technical Complexity | 3 | Time-series prediction on consumption patterns; waste event classification |
| Cross-Department Value | 3 | SCM, Operations, Finance |
| Strategic Alignment | 4 | Sustainability + cost reduction |

**Business Problem:**
With 9.1M stock change events and 136K quality control expiry log records, there is strong evidence of both inventory movement and waste tracking. Perishable ingredients (milk, syrups, food items) have limited shelf lives, and over-ordering creates waste while under-ordering causes stockouts.

**AI Approach:**
- **Method:** Consumption forecasting by ingredient × store × day → optimal order quantities
- **Training Data:** Stock change events (9.1M), expiry logs (136K), demand forecasts (2.5M), production records (502K)
- **Model:** Gradient Boosted Trees for daily consumption prediction; Poisson regression for spoilage probability
- **Output:** Optimal daily ingredient orders per store; waste risk alerts; spoilage trend reports

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Stock changes | `scm-shopstock` | Stock change events | 9.1M records | 🟢 Available |
| Expiry logs | `opqualitycontrol` | Expiry tracking | 136K records | 🟢 Available |
| Production records | `opproduction` | Ingredient consumption | 502K records | 🟢 Available |
| Demand forecasts | `ireplenishment` | Predictions | 2.5M records | 🟢 Available |

---

### UC-SC-03: Supplier Performance Scoring

**Priority:** P2 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 3.20

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 4 | 694 POs, 1,670 shipment records in SCM; SRM database active |
| Business Impact | 3 | Optimize supplier selection; negotiate better terms; reduce supply disruption risk |
| Technical Complexity | 4 | Scorecard calculation + trend analysis; standard analytics |
| Cross-Department Value | 2 | SCM, Finance |
| Strategic Alignment | 3 | Supply chain resilience for expansion |

**Business Problem:**
With 694 purchase orders and 1,670 shipment records across the SCM-SRM system, there is sufficient data to evaluate supplier performance on delivery timeliness, quality (rejection rates), pricing consistency, and order fulfillment accuracy.

**AI Approach:**
- **Method:** Multi-criteria scoring model (delivery lead time, quality incidents, price stability, fill rate)
- **Output:** Supplier performance scorecard; risk-ranked supplier list; recommendation for alternative suppliers

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Purchase orders | `scm-purchase` | PO tables | 694 POs | 🟢 Available |
| Shipments | `scm-purchase` | Shipment tables | 1,670 records | 🟢 Available |
| Supplier data | `scmsrm` | Supplier profiles | TBD | 🟢 Available |
| Quality issues | `opqualitycontrol` | QC task forms | 100K records | 🟢 Available |

---

### UC-SC-04: Dynamic Par Level Setting

**Priority:** P2 | **Data Readiness:** 🟡 YELLOW | **Weighted Score:** 3.30

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 3 | Stock data (9.1M events) and demand predictions (2.5M) available; par level definitions not found in database |
| Business Impact | 4 | Reduce carrying cost and stockout risk simultaneously; per-store optimization |
| Technical Complexity | 3 | Newsvendor model with dynamic parameters; well-studied OR problem |
| Cross-Department Value | 3 | SCM, Operations, Finance |
| Strategic Alignment | 4 | Essential for efficient multi-store inventory management |

**Business Problem:**
Par levels (minimum/maximum inventory levels per item per store) are likely static or manually set. With varying demand patterns by store, day of week, and season, static par levels guarantee either waste (too high) or stockouts (too low).

**AI Approach:**
- **Method:** Newsvendor model with ML-predicted demand distributions; per-store × per-SKU × per-day optimization
- **Training Data:** Demand forecasts (2.5M), stock change events (9.1M), consumption patterns
- **Output:** Dynamic par levels updated daily per store; exception alerts when actual inventory deviates from optimal

---

### UC-SC-05: Perishable Shelf-Life Tracker

**Priority:** P3 | **Data Readiness:** 🟡 YELLOW | **Weighted Score:** 2.60

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 3 | Premade material stock data exists in SCM; shelf-life metadata not confirmed in schema |
| Business Impact | 2 | Reduce waste from expired premade items; food safety compliance |
| Technical Complexity | 3 | FIFO tracking + expiry prediction; requires real-time inventory data |
| Cross-Department Value | 2 | SCM, Operations |
| Strategic Alignment | 2 | Operational hygiene rather than strategic |

**Business Problem:**
Premade materials (pre-mixed syrups, prepared food items) have limited shelf lives. Tracking batch-level expiry and ensuring FIFO usage is important for both waste reduction and food safety.

**AI Approach:**
- **Method:** Batch-level tracking with expiry prediction; FIFO enforcement; usage rate estimation to predict if batch will be consumed before expiry
- **Output:** Batch-level shelf-life dashboard; FIFO violation alerts; waste-risk early warnings

---

## 10. Department 7: Executive & Strategy

### Overview

Executive use cases focus on synthesizing data from across all departments into actionable intelligence for leadership. The existing site selection ML model (R²=0.94) is a standout asset, and the Dify LLM platform provides the foundation for AI-powered briefing generation.

**Department Use Cases:** 4 | **GREEN:** 2 | **YELLOW:** 1 | **RED:** 1

---

### UC-EX-01: Executive AI Daily Briefing

**Priority:** P0 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 4.25

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 4 | All operational data accessible via MCP; Dify LLM platform deployed; 7 BI reports as templates |
| Business Impact | 5 | Executive time savings; faster decision-making; comprehensive awareness without manual report compilation |
| Technical Complexity | 3 | LLM summarization + automated data pipeline; Dify provides orchestration layer |
| Cross-Department Value | 5 | All departments feed into executive briefing |
| Strategic Alignment | 5 | Positions leadership for AI-informed decision-making |

**Business Problem:**
Executives currently receive information through manual report compilation and ad-hoc database queries. The 7 BI reports generated for this assessment each required significant analyst time. An automated daily briefing that synthesizes yesterday's performance across all dimensions (revenue, orders, customer metrics, operational incidents, inventory alerts) would transform leadership decision-making.

**AI Approach:**
- **Method:** Scheduled data pipeline → key metric extraction → LLM summarization via Dify → formatted briefing delivery
- **Pipeline:**
  1. 6 AM: Query databases for yesterday's metrics (orders, revenue, production, inventory, incidents)
  2. 6:15 AM: Compare to historical baselines (7-day avg, 30-day avg, same day last month)
  3. 6:30 AM: Dify LLM generates natural language summary with highlights and anomalies
  4. 7:00 AM: Deliver via Slack/email before executive morning meeting
- **Output:** Daily briefing including: revenue summary, store-level performance, customer metrics, operational alerts, inventory status, notable anomalies

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Revenue data | `salesorder` / `salespayment` | Daily aggregates | 466K+ orders | 🟢 Available |
| Store performance | Multiple | Per-store KPIs | 11 stores | 🟢 Available |
| Dify LLM | PostgreSQL (`dify`) | LLM orchestration | Active | 🟢 Available |
| Customer metrics | `salescrm` / `isalescdp` | User activity | 277K users | 🟢 Available |
| Inventory alerts | `scm-shopstock` | Stock levels | 9.1M events | 🟢 Available |

**Quick Win Potential:** HIGH — MVP achievable in 2-3 weeks using Dify + scheduled SQL queries

---

### UC-EX-02: Site Selection Enhancement

**Priority:** P2 | **Data Readiness:** 🟢 GREEN | **Weighted Score:** 2.90

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 5 | Existing ML model (R²=0.94) operational; scoring API and retraining scripts exist |
| Business Impact | 3 | Support expansion beyond Manhattan; improve location selection accuracy |
| Technical Complexity | 3 | Extend existing model with external data (foot traffic, demographics, competition) |
| Cross-Department Value | 3 | Executive, Finance, Operations |
| Strategic Alignment | 5 | Core enabler of 50-store expansion |

**Business Problem:**
The site selection ML model is a standout success (R²=0.94), with operational scoring API (`score_new_location.py`) and retraining pipeline (`retrain_model.py`). However, it was trained on Manhattan data only and needs enhancement for:
- **Multi-borough expansion:** Brooklyn, Queens, Westchester — different demographics and foot traffic patterns
- **External data enrichment:** Foot traffic data (Placer.ai), demographic data (Census), competition density (Google Maps), public transit proximity
- **Cannibalization modeling:** Predict revenue impact on existing stores from new openings (already observed: 8th Ave flagship declined from $106K→$52K)

**AI Approach:**
- **Method:** Extend existing gradient boosted model with external features; add cannibalization prediction module
- **Output:** Enhanced location scoring with confidence intervals; cannibalization impact estimates; multi-borough candidate rankings

**Data Dependencies:**

| Source | Database/System | Table/Metric | Row Count | Status |
|--------|----------------|--------------|-----------|--------|
| Site selection model | `/app/site-selection-platform/` | ML model, scoring API | Active | 🟢 Available |
| Store performance | Multiple | Revenue by store × month | 11 stores | 🟢 Available |
| Geolocation data | PostgreSQL (`pgilkmap`) | Map/geo data | — | 🟡 Partially accessible |
| External foot traffic | External API | Foot traffic data | — | 🔴 Not collected |
| Census demographics | External API | Population, income, etc. | — | 🔴 Not collected |

---

### UC-EX-03: Unified KPI Command Center

**Priority:** P2 | **Data Readiness:** 🟡 YELLOW | **Weighted Score:** 3.45

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 3 | All data exists in source systems but not unified; 17 Grafana dashboards are DBA-focused, not business-focused |
| Business Impact | 4 | Single pane of glass for all business KPIs; enable data-driven culture |
| Technical Complexity | 3 | Dashboard development + data integration; moderate |
| Cross-Department Value | 5 | All departments |
| Strategic Alignment | 4 | Foundation for data-driven management |

**Business Problem:**
Current monitoring infrastructure (17 Grafana dashboards, 76 Prometheus targets) is focused exclusively on database operations (DBA perspective). There are no business-facing dashboards showing revenue trends, customer metrics, operational KPIs, or supply chain status. Executives must rely on periodic manual reports.

**AI Approach:**
- **Method:** Unified data mart (Redshift Serverless or PostgreSQL) + business intelligence layer (Grafana or Superset)
- **KPIs:** Revenue (daily, weekly, monthly), Orders (count, AOV, channel mix), Customers (active, new, churned), Operations (production time, quality, IoT status), SCM (stock levels, waste, demand accuracy), Finance (reconciliation status, payment processing)
- **Output:** Real-time executive dashboard with drill-down capability

---

### UC-EX-04: Competitive Intelligence Monitor

**Priority:** P3 | **Data Readiness:** 🔴 RED | **Weighted Score:** 2.40

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Data Readiness | 1 | No competitive data collected; requires external data sources |
| Business Impact | 3 | Market positioning, pricing strategy, expansion planning |
| Technical Complexity | 2 | Web scraping, NLP, market analysis |
| Cross-Department Value | 3 | Executive, Marketing, Product |
| Strategic Alignment | 3 | Market awareness for strategic planning |

**Business Problem:**
Luckin Coffee USA operates in the most competitive coffee market in the world (Manhattan). Understanding competitor pricing, new store openings, menu changes, and promotional strategies is critical for strategic planning but currently relies on informal observation.

**AI Approach:**
- **Method:** Automated web scraping of competitor menus/prices (Starbucks, Dunkin', Blue Bottle, etc.) + Yelp/Google review sentiment tracking + new store opening monitoring
- **Output:** Monthly competitive intelligence report; price comparison dashboard; competitive alert system

---

## 11. Data Readiness Summary

### By Data Readiness Level

#### GREEN — Ready to Start (24 use cases)

| # | Use Case | Department | Key Data Source | Row Count |
|---|----------|-----------|----------------|-----------|
| 1 | Revenue Reconciliation | Finance | salesorder + salespayment + ifiaccounting | 466K + 518K |
| 2 | Churn Prediction | Marketing | salesorder (timestamps + user_no) | 466K+ orders |
| 3 | Executive AI Briefing | Executive | All operational databases via MCP + Dify | All systems |
| 4 | Customer 360 | Marketing | salescrm + isalescdp + salesorder | 275K + 980K + 466K |
| 5 | Demand Forecast Monitor | SCM | ireplenishment + salesorder | 2.5M + 466K |
| 6 | Coupon ROI Optimizer | Marketing | salesmarketing + A/B test data | 2.42M + 6.4M |
| 7 | Predictive Infra Monitor | IT | Prometheus + CloudWatch | 76 targets + 95 logs |
| 8 | Store Performance Anomaly | Operations | salesorder + opproduction per store | 466K + 502K |
| 9 | Payment Fraud Detection | Finance | salespayment + iriskcontrolservice | 518K + 4.1M |
| 10 | Menu Engineering | Product | salesorder items + pubdm | 602K + 1,448 |
| 11 | Waste Prediction | SCM | scm-shopstock + opqualitycontrol | 9.1M + 136K |
| 12 | A/B Test Auto-Optimization | Marketing | salesmarketing experiments | 6.4M records |
| 13 | Production Time Predictor | Operations | opproduction + iotplatform | 502K + 587.6K |
| 14 | Database Cost Optimizer | IT | AWS Cost Explorer + CloudWatch | 3 months |
| 15 | Push Notification Optimizer | Marketing | upush + salesorder | 2.3M + 466K |
| 16 | CLV Prediction | Marketing | salesorder + salespayment | 466K + 518K |
| 17 | Personalized Recommendations | Product | salesorder items × user_no | 602K items |
| 18 | Price Elasticity | Product | salesorder + salesmarketing coupons | 466K + 2.42M |
| 19 | Supplier Performance | SCM | scm-purchase + scmsrm | 694 + 1,670 |
| 20 | Security Posture | IT | iriskcontrolservice + WAF Redis | 4.1M + active |
| 21 | Payment Channel Cost | Finance | salespayment fees | 502K records |
| 22 | Recipe Cost Optimization | Product | opproduction formulas | 32K formulas |
| 23 | NL Database Query | IT | All 62 MySQL via MCP + Dify | All databases |
| 24 | New Store Ramp Predictor | Operations | salesorder × store opening dates | 11 stores |
| 25 | Site Selection Enhancement | Executive | Existing ML model + store data | R²=0.94 |

#### YELLOW — Data Gaps to Address (12 use cases)

| # | Use Case | Department | Gap Description | Remediation |
|---|----------|-----------|-----------------|-------------|
| 1 | Next-Best-Action Engine | Marketing | Real-time event stream not piped from MSK/Kafka | Connect 308 Kafka topics to action engine |
| 2 | Dynamic Staffing | Operations | Missing shift preferences and skill matrix | Add fields to HR system |
| 3 | Self-Healing Automation | IT | No structured incident database; broken alerts | Fix 3 Grafana alert rules; create incident log |
| 4 | Capacity Planning | IT | Per-store resource mapping not done | Map infrastructure to store dependencies |
| 5 | Unified KPI Command Center | Executive | No business-facing data mart or dashboards | Build data warehouse layer |
| 6 | Dynamic Par Levels | SCM | Par level definitions not in database | Add par level tables to SCM schema |
| 7 | IoT Predictive Maintenance | Operations | 57% devices offline — limited telemetry | Fix device connectivity first |
| 8 | New Product Launch | Product | Limited launch history (8.5 months) | Accumulate more data over time |
| 9 | Queue/Wait Time | Operations | Real-time queue depth not tracked | Build streaming pipeline |
| 10 | Perishable Shelf-Life | SCM | Shelf-life metadata not confirmed | Validate SCM schema |
| 11 | Referral Network | Marketing | Referral chain data not confirmed | Validate marketing schema |
| 12 | Predictive Infra (partial) | IT | Application metrics not collected; only Redis monitored | Extend Prometheus to MySQL/app |

#### RED — Data Missing, Requires New Collection (5 use cases)

| # | Use Case | Department | Missing Data | Action Required |
|---|----------|-----------|-------------|----------------|
| 1 | Tax Compliance | Finance | `fi_tax` database completely empty | Implement tax calculation system |
| 2 | Social Listening | Marketing | No social media data | Implement external API integrations |
| 3 | Channel Attribution | Marketing | No source tracking on app installs | Implement attribution SDK |
| 4 | Competitive Intelligence | Executive | No competitor data | Build web scraping pipeline |
| 5 | Financial Forecasting | Finance | P&L data incomplete (COGS, OpEx) | Complete financial data model |

---

## 12. Cross-Department Dependency Map

### Shared Data Assets

```
                    ┌─────────────────────────────┐
                    │      CUSTOMER 360 PROFILE     │
                    │    (UC-MK-01 — Foundation)    │
                    └──────────┬──────────────────┘
                               │
            ┌──────────────────┼──────────────────┐
            ▼                  ▼                  ▼
    ┌───────────────┐  ┌───────────────┐  ┌───────────────┐
    │ Churn Predict  │  │ CLV Predict   │  │ Personalized  │
    │ (UC-MK-02)    │  │ (UC-MK-05)   │  │ Recs (UC-PR-02│
    └───────────────┘  └───────────────┘  └───────────────┘
            │                  │                  │
            ▼                  ▼                  ▼
    ┌───────────────┐  ┌───────────────┐  ┌───────────────┐
    │ Next-Best-Act │  │ Push Optimize │  │ Coupon ROI    │
    │ (UC-MK-04)   │  │ (UC-MK-06)   │  │ (UC-MK-03)   │
    └───────────────┘  └───────────────┘  └───────────────┘
```

### Cross-System Join Keys

| Join Key | Type | Systems Connected | Data Quality |
|----------|------|-------------------|-------------|
| `user_no` | varchar | salescrm ↔ isalescdp ↔ salesorder ↔ salesmarketing ↔ upush | 🟢 Clean |
| `order_no` / `order_id` | bigint/varchar | salesorder ↔ salespayment ↔ opproduction ↔ iotplatform | 🟡 Type mismatch (bigint vs varchar) |
| `shop_dept_id` / `shop_id` | bigint | opshop ↔ scm-shopstock ↔ salesorder ↔ opproduction | 🟢 Clean |
| `spu_code` / `goods_code` | varchar | pubdm ↔ scmcommodity ↔ salesorder items ↔ ireplenishment | 🟢 Clean |
| `trade_no` | varchar | salespayment ↔ ifiaccounting ↔ iunifiedreconcile | 🟢 Clean |

### Dependency Chains (Must Build in Order)

**Chain 1: Customer Intelligence**
```
Customer 360 (MK-01) → Churn Prediction (MK-02) → Next-Best-Action (MK-04)
                     → CLV Prediction (MK-05)  → Push Optimizer (MK-06)
                     → Personalized Recs (PR-02)
```

**Chain 2: Demand-to-Operations**
```
Demand Forecast Monitor (SC-01) → Dynamic Par Levels (SC-04) → Waste Prediction (SC-02)
                                → Staffing Optimizer (OP-01)
                                → Production Predictor (OP-03)
```

**Chain 3: Financial Integrity**
```
Revenue Reconciliation (FN-02) → Tax Compliance (FN-01) → Financial Forecasting (FN-05)
                               → Payment Fraud (FN-03)
```

**Chain 4: Infrastructure Foundation**
```
Predictive Monitoring (IT-01) → Self-Healing (IT-03) → Capacity Planning (IT-04)
Database Cost Optimizer (IT-02) → Capacity Planning (IT-04)
```

---

## 13. Quick Win Identification

Use cases achievable in **<30 days** with existing data and minimal infrastructure:

### Tier 1: Week 1-2 (SQL + Dashboards Only)

| Use Case | Effort | Approach | Expected Impact |
|----------|--------|----------|----------------|
| Demand Forecast Monitor (SC-01) | 1 week | SQL join: predictions vs. actuals → Grafana dashboard | Forecast MAPE visibility |
| Store Performance Anomaly (OP-02) | 1 week | Daily store metrics + Z-score alerting in Grafana | Early problem detection |
| Menu Engineering Matrix (PR-01) | 3 days | SQL query: product sales × category → BCG quadrant | Menu optimization insights |
| Database Cost Optimizer (IT-02) | 1 week | Cost Explorer analysis → right-sizing recommendations | $176K/year savings pipeline |

### Tier 2: Week 2-4 (ML Model Training)

| Use Case | Effort | Approach | Expected Impact |
|----------|--------|----------|----------------|
| Churn Prediction (MK-02) | 2 weeks | XGBoost on order history → daily churn scores | 5% win-back = $216K/year |
| Revenue Reconciliation (FN-02) | 2 weeks | Automated 3-way match + exception report | Eliminate manual reconciliation |
| Executive AI Briefing (EX-01) | 3 weeks | Dify pipeline → scheduled queries → LLM summary | Daily executive intelligence |
| Production Time Predictor (OP-03) | 2 weeks | Regression on 502K production records | Accurate wait time quotes |

### Tier 3: Week 3-4 (Infrastructure Setup)

| Use Case | Effort | Approach | Expected Impact |
|----------|--------|----------|----------------|
| Predictive Infra Monitoring (IT-01) | 3 weeks | Anomaly detection on Prometheus/CloudWatch streams | Prevent P0 incidents |
| Customer 360 Profile (MK-01) | 4 weeks | Entity resolution + feature store | Foundation for all marketing AI |

---

## 14. Existing AI/ML Systems Audit

Luckin Coffee USA already has **6 AI/ML systems** deployed or instrumented:

### System 1: Demand Forecasting Engine
- **Status:** ✅ Operational
- **Database:** `ireplenishment` (MySQL)
- **Scale:** 2.5 million predictions generated
- **Purpose:** Per-store, per-SKU demand forecasting for inventory ordering
- **Gap:** No accuracy monitoring or feedback loop (UC-SC-01 addresses this)

### System 2: A/B Testing Platform
- **Status:** ✅ Operational
- **Database:** `salesmarketing` (MySQL)
- **Scale:** 6.4 million experiment records
- **Purpose:** Marketing campaign experiments, coupon testing, UI experiments
- **Gap:** Manual winner selection (UC-MK-07 addresses this)

### System 3: Customer Data Platform (CDP)
- **Status:** ✅ Operational
- **Database:** `isalescdp` (MySQL)
- **Scale:** 980K user state records
- **Purpose:** Behavioral segmentation, user state tracking, marketing automation triggers
- **Gap:** Not connected to real-time personalization (UC-MK-04 addresses this)

### System 4: CyberData ETL Pipeline
- **Status:** ✅ Operational
- **Database:** `icyberdata` (MySQL)
- **Scale:** 17.3 million rows across data pipeline tables; 5.6M task records
- **Purpose:** Big data ETL, data pipeline orchestration, cross-system data movement
- **Gap:** Pipeline monitoring is limited

### System 5: Dify LLM Platform
- **Status:** ✅ Operational
- **Database:** PostgreSQL (`aws-luckyus-dify-rw`, `aws-luckyus-difynew-rw`)
- **Purpose:** LLM orchestration, AI agent development, natural language processing
- **Gap:** Not yet integrated with operational data for automated insights (UC-EX-01, UC-IT-05 address this)

### System 6: Site Selection ML Model
- **Status:** ✅ Operational
- **Location:** `/app/site-selection-platform/`
- **Performance:** R² = 0.94 (excellent predictive accuracy)
- **Components:** Training pipeline (`site_selection_model.py`), scoring API (`score_new_location.py`), retraining script (`retrain_model.py`)
- **Gap:** Trained on Manhattan data only; needs external data enrichment for multi-borough expansion (UC-EX-02 addresses this)

### AI Maturity Assessment

| Capability | Status | Gap |
|-----------|--------|-----|
| Data Collection | ✅ Mature (143 databases) | No unified warehouse |
| Feature Engineering | 🟡 Partial (CDP does some) | No feature store |
| Model Training | 🟡 Partial (site selection, demand) | No ML platform |
| Model Serving | 🟡 Partial (site selection API) | No standardized serving layer |
| Model Monitoring | 🔴 Missing | No MLOps pipeline |
| LLM/GenAI | ✅ Foundation (Dify deployed) | Not integrated with data |
| Experimentation | ✅ Mature (A/B testing) | Manual analysis |

---

## 15. Implementation Prerequisites

### Data Engineering Prerequisites

| Prerequisite | Required For | Effort | Priority |
|-------------|-------------|--------|----------|
| Fix `order_id` type mismatch (bigint↔varchar) | Revenue Reconciliation, all order-based analytics | 1 week | P0 |
| Remove/flag 21,245 NZD test orders | All revenue/order analytics | 2 days | P0 |
| Implement `fi_tax` data collection | Tax Compliance | 2-4 weeks | P0 |
| Build unified data warehouse (Redshift Serverless) | Customer 360, KPI Command Center, Financial Forecasting | 4-6 weeks | P1 |
| Create feature store (SageMaker Feature Store) | Churn Prediction, CLV, Recommendations, Next-Best-Action | 3-4 weeks | P1 |
| Fix Grafana alert rules (3 rules, all health=error) | Predictive Monitoring, Self-Healing | 1 week | P1 |
| Extend Prometheus beyond Redis | Full infrastructure monitoring | 2-3 weeks | P1 |
| Connect Kafka topics to analytics | Real-time use cases (Next-Best-Action, Queue Management) | 3-4 weeks | P2 |
| Fix IoT device connectivity (57% offline) | IoT Predictive Maintenance, Queue Management | 4-8 weeks | P2 |

### Team Requirements

| Role | Phase 1 (Mo 1-3) | Phase 2 (Mo 4-6) | Phase 3 (Mo 7-12) | Phase 4 (Mo 12-18) |
|------|-------------------|-------------------|--------------------|--------------------|
| Data Engineer | 1 | 2 | 2 | 3 |
| ML Engineer | 0.5 | 1 | 2 | 2 |
| Data Scientist | 0 | 0.5 | 1 | 2 |
| Analytics Engineer | 1 | 1 | 1 | 1 |
| **Total FTE** | **2.5** | **4.5** | **6** | **8** |

### Technology Stack

| Component | Recommended Tool | Purpose |
|-----------|-----------------|---------|
| Data Warehouse | Amazon Redshift Serverless | Centralized analytics layer |
| ETL/ELT | AWS Glue + DMS (CDC) | Data pipeline orchestration |
| Feature Store | Amazon SageMaker Feature Store | ML feature management |
| ML Platform | Amazon SageMaker | Model training, hosting, monitoring |
| LLM Platform | Dify (already deployed) | GenAI orchestration |
| BI/Dashboards | Grafana + Apache Superset | Operational + business dashboards |
| Streaming | Amazon MSK (already deployed) | Real-time event processing |
| Orchestration | Apache Airflow (MWAA) | Workflow scheduling |

---

*This catalog identifies 41 AI/ML use cases with a combined estimated annual value of $1-3M at maturity. The 24 GREEN-ready use cases can be initiated immediately, with the first 4-6 quick wins achievable within 30 days.*

---

*Generated February 14, 2026*
*Luckin Coffee USA — Confidential*

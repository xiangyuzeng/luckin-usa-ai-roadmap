# Architecture Blueprint
## Luckin Coffee USA — AI Transformation Roadmap (Deliverable 3 of 5)

**Prepared for:** First Ray Holdings USA Inc. (Luckin Coffee USA)
**Date:** February 14, 2026
**Classification:** Confidential

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Current State Assessment](#2-current-state-assessment)
3. [Target-State Architecture](#3-target-state-architecture)
4. [Data Warehouse Design](#4-data-warehouse-design)
5. [Data Integration Architecture](#5-data-integration-architecture)
6. [AI/ML Platform Design](#6-aiml-platform-design)
7. [Application Integration Layer](#7-application-integration-layer)
8. [Security & Data Governance](#8-security--data-governance)
9. [Technology Selection Rationale](#9-technology-selection-rationale)
10. [Cost Projections](#10-cost-projections)
11. [Migration Strategy](#11-migration-strategy)
12. [Architecture Decision Records](#12-architecture-decision-records)

---

## 1. Executive Summary

This blueprint designs the target-state data and AI architecture for Luckin Coffee USA, transforming 143 siloed database instances into a unified, AI-ready data platform. The architecture is designed to support the company's growth from 11 Manhattan stores to 50+ stores across multiple boroughs and states over 18 months.

### Design Principles

| Principle | Rationale |
|-----------|-----------|
| **Serverless-first** | Minimize operational overhead for a small team; pay per use scales with growth |
| **Extend, don't replace** | Build on existing investments (Dify, CDP, demand forecasting, MCP) rather than ripping and replacing |
| **Data warehouse as foundation** | Centralized analytics enables all 41 AI use cases; siloed databases are the root problem |
| **Real-time where it matters** | Most use cases work with daily batch; reserve streaming for production-critical paths (ordering, fraud detection) |
| **Security by design** | PII handling, RBAC, audit logging built in from day one |

### Architecture Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                    LAYER 4: APPLICATIONS                        │
│  Executive Briefing │ Customer App │ Ops Dashboard │ Slack Bot  │
├─────────────────────────────────────────────────────────────────┤
│                    LAYER 3: AI/ML PLATFORM                      │
│  SageMaker (ML) │ Dify (LLM) │ Feature Store │ MLflow Registry │
├─────────────────────────────────────────────────────────────────┤
│                    LAYER 2: DATA PLATFORM                       │
│  Redshift Serverless │ Glue ETL │ Kinesis │ S3 Data Lake       │
├─────────────────────────────────────────────────────────────────┤
│                    LAYER 1: SOURCE SYSTEMS                      │
│  62 MySQL │ 78 Redis │ 3 PostgreSQL │ MSK/Kafka │ CloudWatch   │
└─────────────────────────────────────────────────────────────────┘
```

### Key Metrics

| Metric | Current State | Target State | Timeline |
|--------|--------------|-------------|----------|
| Data sources unified | 0 | 16 priority databases | 6 months |
| Analytics query time | Minutes (direct DB) | Seconds (warehouse) | 3 months |
| ML models in production | 2 (demand, site selection) | 12+ | 18 months |
| Monitoring coverage | Redis only (52%) | Full stack (95%+) | 6 months |
| Data freshness | Unknown | <15 min (streaming), <4 hr (batch) | 6 months |
| Incremental infra cost | — | $12-18K/month | Phased |

---

## 2. Current State Assessment

### 2.1 Architecture Strengths

**Enterprise-grade foundation:** The infrastructure ported from Luckin Coffee China's 20,000-store platform provides capabilities far beyond what an 11-store chain would typically build:

| Capability | Asset | Value |
|-----------|-------|-------|
| Microservice architecture | 62 MySQL databases, one per service | Clean domain separation, independent scaling |
| Event-driven backbone | 308 Kafka topics (MSK) | Real-time event streaming infrastructure exists |
| Caching layer | 78 Redis clusters (ElastiCache) | Sub-millisecond response times for app |
| AI/ML foundation | 6 deployed systems | Proven AI capability (demand forecasting, A/B testing, CDP, Dify, CyberData, site selection) |
| Data pipeline | CyberData ETL (17.3M rows) | Cross-system data movement infrastructure |
| LLM platform | Dify on PostgreSQL | GenAI orchestration ready |

### 2.2 Architecture Weaknesses

| Weakness | Impact | Root Cause |
|----------|--------|------------|
| **No data warehouse** | Every analytical query hits production databases | Architecture optimized for OLTP, not analytics |
| **No feature store** | ML features recomputed for each model; no sharing | ML systems built independently |
| **No MLOps pipeline** | Models deployed manually; no monitoring, no automated retraining | AI systems are prototype-grade |
| **Monitoring gaps** | Prometheus only monitors Redis (76/143 instances); 3 broken alert rules; 0 CloudWatch alarms | Monitoring setup incomplete after China→US port |
| **Data silos** | 143 databases with no cross-system query capability except MCP | Microservice architecture creates data islands |
| **No business dashboards** | 17 Grafana dashboards all DBA-focused | Monitoring team focused on infrastructure, not business |
| **Join key inconsistencies** | `order_id` is bigint in salesorder, varchar in salespayment | Schema ported from different versions |
| **Data contamination** | 21,245 NZD test orders in production data | Testing data not isolated |
| **Critical data gaps** | fi_tax empty, loyalty not launched, 57% IoT offline | US-specific requirements not addressed |

### 2.3 Current Data Flow

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│ Customer │───►│ App      │───►│ API      │───►│ MySQL    │
│ (App)    │    │ Frontend │    │ Gateway  │    │ (62 DBs) │
└──────────┘    └──────────┘    └──────────┘    └────┬─────┘
                                                      │
                                                      ▼
                                               ┌──────────┐
                                               │ Kafka    │
                                               │ (308     │
                                               │ topics)  │
                                               └────┬─────┘
                                                    │
                                         ┌──────────┴──────────┐
                                         ▼                     ▼
                                  ┌──────────┐          ┌──────────┐
                                  │ CyberData│          │ Redis    │
                                  │ ETL      │          │ Cache    │
                                  │ (17.3M)  │          │ (78)     │
                                  └──────────┘          └──────────┘
                                         │
                                         ▼
                                  ┌──────────┐
                                  │ Demand   │
                                  │ Forecast │
                                  │ (2.5M)   │
                                  └──────────┘

    ⚠️ No centralized warehouse, no feature store, no MLOps
    ⚠️ Analytics = direct queries against production databases
    ⚠️ MCP DB Gateway is the only cross-database query mechanism
```

---

## 3. Target-State Architecture

### 3.1 Four-Layer Architecture

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                           LAYER 4: APPLICATIONS                               │
│                                                                               │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐  ┌──────────┐  ┌──────────────┐ │
│  │ Executive│  │ Customer │  │ Operations│  │"Ask Lucky"│  │ Grafana/     │ │
│  │ AI Brief │  │ App      │  │ Dashboard │  │ NL Query  │  │ Superset     │ │
│  │ (Daily)  │  │ (Real-   │  │ (Ops Cmd  │  │ (Slack    │  │ (Business    │ │
│  │          │  │  time)   │  │  Center)  │  │  Bot)     │  │  Dashboards) │ │
│  └────┬─────┘  └────┬─────┘  └────┬──────┘  └────┬─────┘  └──────┬───────┘ │
├───────┼──────────────┼────────────┼──────────────┼────────────────┼─────────┤
│       │         LAYER 3: AI/ML PLATFORM           │                │         │
│       │                                            │                │         │
│  ┌────▼─────┐  ┌──────────┐  ┌───────────┐  ┌────▼─────┐  ┌──────▼───────┐ │
│  │ Dify     │  │ SageMaker│  │ SageMaker │  │ Dify     │  │ MLflow       │ │
│  │ LLM      │  │ Training │  │ Feature   │  │ + MCP    │  │ Model        │ │
│  │ Pipeline │  │ & Hosting│  │ Store     │  │ Gateway  │  │ Registry     │ │
│  └────┬─────┘  └────┬─────┘  └─────┬─────┘  └────┬─────┘  └──────┬───────┘ │
│       │              │              │              │                │         │
│       │              │        ┌─────▼─────┐       │                │         │
│       │              │        │ Feature   │       │                │         │
│       │              │        │ Pipeline  │       │                │         │
│       │              │        │ (Glue)    │       │                │         │
│       │              │        └─────┬─────┘       │                │         │
├───────┼──────────────┼──────────────┼─────────────┼────────────────┼─────────┤
│       │         LAYER 2: DATA PLATFORM            │                │         │
│       │                                            │                │         │
│  ┌────▼───────────────▼──────────────▼─────────────▼────────────────▼───────┐ │
│  │                    AMAZON REDSHIFT SERVERLESS                            │ │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────────────┐    │ │
│  │  │ Fact:     │  │ Fact:     │  │ Fact:     │  │ Fact:             │    │ │
│  │  │ Orders    │  │ Payments  │  │ Production│  │ Stock Changes     │    │ │
│  │  └───────────┘  └───────────┘  └───────────┘  └───────────────────┘    │ │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────────────┐    │ │
│  │  │ Dim:      │  │ Dim:      │  │ Dim:      │  │ Dim:              │    │ │
│  │  │ Customer  │  │ Store     │  │ Product   │  │ Date/Time         │    │ │
│  │  └───────────┘  └───────────┘  └───────────┘  └───────────────────┘    │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────────────────┐ │
│  │ AWS Glue │  │ AWS DMS  │  │ Kinesis  │  │ S3 Data Lake               │ │
│  │ (ETL)    │  │ (CDC)    │  │ (Stream) │  │ (Raw/Processed/Curated)    │ │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──────────────────────────────┘ │
├───────┼──────────────┼─────────────┼────────────────────────────────────────┤
│       │         LAYER 1: SOURCE SYSTEMS             │                        │
│       │                                              │                        │
│  ┌────▼─────┐  ┌──────────┐  ┌──────────┐  ┌───────▼──────┐  ┌──────────┐ │
│  │ MySQL    │  │ Redis    │  │ Postgres │  │ MSK/Kafka    │  │ CloudWatch│ │
│  │ (62 DBs) │  │ (78)     │  │ (3)      │  │ (308 topics) │  │ (95 logs) │ │
│  └──────────┘  └──────────┘  └──────────┘  └──────────────┘  └──────────┘ │
└───────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Data Flow Patterns

**Pattern 1: Batch ETL (Daily)**
```
MySQL (source) → DMS (CDC capture) → S3 (raw zone) → Glue (transform) → Redshift (warehouse)
                                                                        → Feature Store (ML features)
```
- Used for: Historical analytics, CLV calculation, menu engineering, financial reporting
- Freshness: T+4 hours (6 AM processing for previous day)
- Volume: ~500K new records/day across all sources

**Pattern 2: Near-Real-Time CDC (15-minute)**
```
MySQL (source) → DMS (CDC continuous) → Kinesis Data Streams → Glue Streaming → Redshift
                                                              → Lambda (alerts)
```
- Used for: Revenue reconciliation, store anomaly detection, inventory alerts
- Freshness: 10-15 minutes
- Volume: ~5K events/hour during peak

**Pattern 3: Real-Time Streaming**
```
App Events → API Gateway → MSK/Kafka (existing 308 topics) → Kinesis → Lambda → Action
                                                                      → Redshift (log)
```
- Used for: Fraud detection (real-time scoring), production queue management, IoT telemetry
- Freshness: <5 seconds
- Volume: ~100 events/minute during peak

**Pattern 4: LLM Pipeline**
```
Scheduled Trigger → Glue (extract metrics) → S3 (daily snapshot) → Dify (LLM summarize) → Slack/Email
```
- Used for: Executive AI briefing, "Ask Lucky" NL queries
- Freshness: On-demand or scheduled (daily)

---

## 4. Data Warehouse Design

### 4.1 Star Schema Overview

The data warehouse follows a star schema design with **10 fact tables** and **10 dimension tables**, designed to support all 41 AI use cases identified in the Use Case Catalog.

### 4.2 Fact Tables

#### fact_orders
The central fact table connecting customer purchases across all dimensions.

| Column | Type | Source | Description |
|--------|------|--------|-------------|
| order_key | BIGINT (SK) | Generated | Surrogate key |
| order_id | VARCHAR | salesorder.t_sales_order_m | Natural key (cast from bigint) |
| order_no | VARCHAR | salesorder.t_sales_order_m | Business order number |
| customer_key | BIGINT (FK) | dim_customer | Customer dimension |
| store_key | BIGINT (FK) | dim_store | Store dimension |
| date_key | INT (FK) | dim_date | Order date YYYYMMDD |
| time_key | INT (FK) | dim_time | Order time HHMM |
| channel_key | BIGINT (FK) | dim_channel | Pickup/Delivery |
| order_status | INT | salesorder | Status code (90=completed) |
| item_count | INT | Calculated | Number of items in order |
| gross_amount | DECIMAL(12,2) | salesorder | Pre-discount amount |
| discount_amount | DECIMAL(12,2) | salesorder | Coupon/promo discount |
| net_amount | DECIMAL(12,2) | salesorder | Final charged amount |
| tax_amount | DECIMAL(12,2) | fi_tax (when populated) | Tax charged |
| is_nzd_test | BOOLEAN | Derived | Flag for NZD contamination |
| etl_loaded_at | TIMESTAMP | ETL | Load timestamp |

**Source:** `salesorder.t_sales_order_m` (466K+ rows, sharded by month)
**Grain:** One row per order

#### fact_order_items
Line-item detail for product-level analytics (menu engineering, recommendations).

| Column | Type | Source | Description |
|--------|------|--------|-------------|
| order_item_key | BIGINT (SK) | Generated | Surrogate key |
| order_key | BIGINT (FK) | fact_orders | Parent order |
| product_key | BIGINT (FK) | dim_product | Product dimension |
| quantity | INT | salesorder | Quantity ordered |
| unit_price | DECIMAL(10,2) | salesorder | Price per unit |
| item_amount | DECIMAL(10,2) | salesorder | Line total |

**Source:** `salesorder` order items tables (602K+ rows)
**Grain:** One row per order line item

#### fact_payments
Payment transaction detail for financial reconciliation and fraud detection.

| Column | Type | Source | Description |
|--------|------|--------|-------------|
| payment_key | BIGINT (SK) | Generated | Surrogate key |
| trade_no | VARCHAR | salespayment.t_sales_trade_m | Trade reference |
| order_key | BIGINT (FK) | fact_orders | Linked order |
| customer_key | BIGINT (FK) | dim_customer | Payer |
| payment_method | VARCHAR | salespayment | Payment type |
| payment_amount | DECIMAL(12,2) | salespayment | Amount paid |
| fee_amount | DECIMAL(10,2) | salespayment | Processing fee |
| payment_status | VARCHAR | salespayment | Success/failed/refund |
| payment_timestamp | TIMESTAMP | salespayment | Transaction time |

**Source:** `salespayment.t_sales_trade_m` (518K trades, 502K fee records)
**Grain:** One row per payment transaction

#### fact_productions
Production/fulfillment tracking for operational efficiency.

| Column | Type | Source | Description |
|--------|------|--------|-------------|
| production_key | BIGINT (SK) | Generated | Surrogate key |
| order_key | BIGINT (FK) | fact_orders | Source order |
| store_key | BIGINT (FK) | dim_store | Production store |
| product_key | BIGINT (FK) | dim_product | Product made |
| start_time | TIMESTAMP | opproduction | Production start |
| end_time | TIMESTAMP | opproduction | Production end |
| duration_seconds | INT | Calculated | Production time |
| barista_id | VARCHAR | opproduction | Employee (anonymized) |

**Source:** `opproduction` (502K records)
**Grain:** One row per production unit

#### fact_iot_events
IoT device telemetry and cup order tracking.

| Column | Type | Source | Description |
|--------|------|--------|-------------|
| iot_event_key | BIGINT (SK) | Generated | Surrogate key |
| device_key | BIGINT (FK) | dim_device | IoT device |
| store_key | BIGINT (FK) | dim_store | Device location |
| event_type | VARCHAR | iotplatform | Event classification |
| cup_order_id | VARCHAR | iotplatform | Cup order reference |
| event_timestamp | TIMESTAMP | iotplatform | Event time |
| device_status | VARCHAR | iotplatform | Online/offline/error |

**Source:** `iotplatform` (587.6K cup orders, 216 devices)
**Grain:** One row per IoT event

#### fact_stock_changes
Inventory movement tracking for waste prediction and par level optimization.

| Column | Type | Source | Description |
|--------|------|--------|-------------|
| stock_change_key | BIGINT (SK) | Generated | Surrogate key |
| store_key | BIGINT (FK) | dim_store | Store location |
| product_key | BIGINT (FK) | dim_product | Item |
| date_key | INT (FK) | dim_date | Change date |
| change_type | VARCHAR | scm-shopstock | Receipt/sale/waste/adjustment |
| quantity_change | DECIMAL(12,4) | scm-shopstock | Amount changed |
| running_balance | DECIMAL(12,4) | scm-shopstock | Post-change inventory |

**Source:** `scm-shopstock` (9.1M stock change events)
**Grain:** One row per stock movement

#### fact_coupon_usage
Coupon distribution and redemption for marketing ROI analysis.

| Column | Type | Source | Description |
|--------|------|--------|-------------|
| coupon_key | BIGINT (SK) | Generated | Surrogate key |
| coupon_template_key | BIGINT (FK) | dim_coupon_template | Template |
| customer_key | BIGINT (FK) | dim_customer | Recipient |
| order_key | BIGINT (FK) | fact_orders (nullable) | Redemption order |
| distributed_at | TIMESTAMP | salesmarketing | Distribution time |
| redeemed_at | TIMESTAMP | salesmarketing | Redemption time (null if unused) |
| expired_at | TIMESTAMP | salesmarketing | Expiry time |
| discount_amount | DECIMAL(10,2) | salesmarketing | Face value |
| status | VARCHAR | salesmarketing | Active/redeemed/expired |

**Source:** `salesmarketing` (2.42M active + 37.3M expired coupons)
**Grain:** One row per coupon instance

#### fact_user_events
Customer behavioral events for CDP and churn prediction.

| Column | Type | Source | Description |
|--------|------|--------|-------------|
| user_event_key | BIGINT (SK) | Generated | Surrogate key |
| customer_key | BIGINT (FK) | dim_customer | User |
| event_type | VARCHAR | isalescdp | Login/browse/order/coupon_view |
| event_timestamp | TIMESTAMP | isalescdp | Event time |
| event_properties | SUPER | isalescdp | JSON event metadata |

**Source:** `isalescdp` (980K user state records)
**Grain:** One row per behavioral event

#### fact_experiments
A/B test experiment tracking.

| Column | Type | Source | Description |
|--------|------|--------|-------------|
| experiment_key | BIGINT (SK) | Generated | Surrogate key |
| experiment_id | VARCHAR | salesmarketing | Experiment identifier |
| customer_key | BIGINT (FK) | dim_customer | Participant |
| variant | VARCHAR | salesmarketing | Control/treatment group |
| metric_name | VARCHAR | salesmarketing | Measured metric |
| metric_value | DECIMAL(12,4) | salesmarketing | Metric outcome |
| assigned_at | TIMESTAMP | salesmarketing | Assignment time |

**Source:** `salesmarketing` A/B test tables (6.4M records)
**Grain:** One row per experiment assignment

#### fact_demand_predictions
Demand forecast tracking for accuracy monitoring.

| Column | Type | Source | Description |
|--------|------|--------|-------------|
| prediction_key | BIGINT (SK) | Generated | Surrogate key |
| store_key | BIGINT (FK) | dim_store | Predicted store |
| product_key | BIGINT (FK) | dim_product | Predicted product |
| date_key | INT (FK) | dim_date | Prediction date |
| predicted_quantity | DECIMAL(12,2) | ireplenishment | Forecasted demand |
| actual_quantity | DECIMAL(12,2) | salesorder (joined) | Actual sales |
| prediction_error | DECIMAL(12,4) | Calculated | Prediction - Actual |
| model_version | VARCHAR | ireplenishment | Model identifier |

**Source:** `ireplenishment` (2.5M predictions) joined with `salesorder` actuals
**Grain:** One row per store × product × date prediction

### 4.3 Dimension Tables

#### dim_customer
| Column | Type | Source | Description |
|--------|------|--------|-------------|
| customer_key | BIGINT (SK) | Generated | Surrogate key |
| user_no | VARCHAR | salescrm | Natural key (universal) |
| registration_date | DATE | salescrm | First registration |
| first_order_date | DATE | salesorder | First purchase |
| last_order_date | DATE | salesorder | Most recent purchase |
| total_orders | INT | Calculated | Lifetime order count |
| total_spend | DECIMAL(12,2) | Calculated | Lifetime spend |
| rfm_recency_score | INT | Calculated | 1-5 recency score |
| rfm_frequency_score | INT | Calculated | 1-5 frequency score |
| rfm_monetary_score | INT | Calculated | 1-5 monetary score |
| churn_risk_score | DECIMAL(5,2) | ML model output | 0-100 churn probability |
| clv_predicted | DECIMAL(12,2) | ML model output | 12-month predicted CLV |
| segment | VARCHAR | Derived | VIP/Growth/Maintain/At-Risk/Lapsed |
| phone_hash | VARCHAR | salescrm | Hashed phone (PII protected) |

**SCD Type 2** for tracking segment changes over time.

#### dim_store
| Column | Type | Source |
|--------|------|--------|
| store_key | BIGINT (SK) | Generated |
| shop_dept_id | BIGINT | opshop |
| store_name | VARCHAR | opshop |
| address | VARCHAR | opshop |
| borough | VARCHAR | Derived |
| city | VARCHAR | opshop |
| state | VARCHAR | opshop |
| zip_code | VARCHAR | opshop |
| latitude | DECIMAL(10,7) | opshop/pgilkmap |
| longitude | DECIMAL(10,7) | opshop/pgilkmap |
| store_type | VARCHAR | opshop (retail/kiosk) |
| opening_date | DATE | opshop |
| maturity_stage | VARCHAR | Derived (ramp/mature/declining) |
| tax_zone | VARCHAR | Derived |

#### dim_product
| Column | Type | Source |
|--------|------|--------|
| product_key | BIGINT (SK) | Generated |
| spu_code | VARCHAR | pubdm |
| product_name | VARCHAR | pubdm |
| category | VARCHAR | pubdm/scmcommodity |
| subcategory | VARCHAR | pubdm/scmcommodity |
| is_hot | BOOLEAN | Derived |
| is_dairy | BOOLEAN | Derived |
| base_price | DECIMAL(10,2) | pubdm |
| recipe_cost | DECIMAL(10,2) | opproduction formulas |
| contribution_margin | DECIMAL(10,2) | Calculated |
| bcg_quadrant | VARCHAR | Calculated (star/plowhorse/puzzle/dog) |

#### dim_date
Standard date dimension (pre-populated for 2024-2030).

| Column | Type | Description |
|--------|------|-------------|
| date_key | INT | YYYYMMDD |
| full_date | DATE | Calendar date |
| day_of_week | VARCHAR | Monday-Sunday |
| is_weekend | BOOLEAN | Sat/Sun flag |
| is_holiday | BOOLEAN | US federal + NYC holidays |
| week_number | INT | ISO week |
| month | INT | 1-12 |
| quarter | INT | 1-4 |
| year | INT | Calendar year |
| fiscal_period | VARCHAR | Company fiscal period |

#### dim_time
Time-of-day dimension for hour/period analysis.

| Column | Type | Description |
|--------|------|-------------|
| time_key | INT | HHMM |
| hour | INT | 0-23 |
| minute | INT | 0-59 |
| period | VARCHAR | Morning/Lunch/Afternoon/Evening |
| is_peak | BOOLEAN | Peak ordering hours (9-10 AM, 1-2 PM) |

#### dim_device, dim_employee, dim_supplier, dim_coupon_template, dim_channel
Additional dimensions following standard patterns, sourced from their respective operational databases.

---

## 5. Data Integration Architecture

### 5.1 CDC Pipeline Design (AWS DMS)

**Phase 1 (Month 1-3): 5 Priority CDC Pipelines**

| Source Database | Target | Method | Priority | Rationale |
|----------------|--------|--------|----------|-----------|
| `salesorder` | Redshift | DMS CDC (continuous) | P0 | Core revenue data; feeds 20+ use cases |
| `salespayment` | Redshift | DMS CDC (continuous) | P0 | Financial reconciliation; fraud detection |
| `salescrm` | Redshift | DMS CDC (continuous) | P0 | Customer dimension; churn prediction |
| `opproduction` | Redshift | DMS CDC (continuous) | P1 | Production time prediction; store analytics |
| `isalescdp` | Redshift | DMS CDC (continuous) | P1 | Customer behavioral data; segmentation |

**Phase 2 (Month 4-6): Expand to 12 Pipelines**

| Source Database | Target | Method | Priority | Rationale |
|----------------|--------|--------|----------|-----------|
| `salesmarketing` | Redshift | DMS CDC | P1 | Coupon ROI, A/B testing |
| `scm-shopstock` | Redshift | DMS CDC | P1 | Inventory analytics, waste prediction |
| `ireplenishment` | Redshift | DMS CDC | P1 | Demand forecast monitoring |
| `opshop` | Redshift | DMS Full Load + CDC | P1 | Store dimension |
| `ifiaccounting` | Redshift | DMS CDC | P1 | Revenue reconciliation |
| `opqualitycontrol` | Redshift | DMS CDC | P2 | Quality tracking |
| `opempefficiency` | Redshift | DMS CDC | P2 | Staffing analytics |

**Phase 3 (Month 7-12): Full Coverage**

| Source Database | Target | Method | Priority |
|----------------|--------|--------|----------|
| `iotplatform` | Redshift | DMS CDC | P2 |
| `iriskcontrolservice` | Redshift | DMS CDC | P2 |
| `upush` | Redshift | DMS CDC | P2 |
| Remaining MySQL databases | S3 Data Lake | DMS Full Load (weekly) | P3 |

### 5.2 DMS Configuration

```yaml
# DMS Replication Instance
replication_instance:
  class: dms.r6i.large
  multi_az: true
  storage: 100 GB
  vpc: existing-lkus-vpc

# CDC Task Template
cdc_task:
  migration_type: cdc  # Change Data Capture only (after initial full load)
  table_mappings:
    selection_rules:
      - rule_type: include
        schema: "luckyus_%"
        table: "%"
    transformation_rules:
      - rule_type: add-column
        column_name: "dms_loaded_at"
        expression: "$AR_H_CHANGE_SEQ"
  task_settings:
    target_table_prep_mode: "DO_NOTHING"  # Preserve existing data
    stop_task_cached_changes_applied: false
    lob_max_size: 32  # KB
    parallel_load_threads: 4
```

### 5.3 ETL Pipeline Design (AWS Glue)

```
┌─────────────────────────────────────────────────────────────────────┐
│                      AWS GLUE ETL PIPELINE                          │
│                                                                     │
│  ┌───────────┐    ┌────────────┐    ┌────────────┐    ┌──────────┐│
│  │ S3 Raw    │───►│ Glue Job:  │───►│ S3         │───►│ Redshift ││
│  │ Zone      │    │ Transform  │    │ Processed  │    │ Tables   ││
│  │ (CDC logs)│    │ & Clean    │    │ Zone       │    │          ││
│  └───────────┘    └────────────┘    └────────────┘    └──────────┘│
│                         │                                          │
│                         ▼                                          │
│                   ┌────────────┐                                   │
│                   │ Data       │                                   │
│                   │ Quality    │                                   │
│                   │ Checks     │                                   │
│                   │ • NZD filter│                                  │
│                   │ • Type cast│                                   │
│                   │ • Null     │                                   │
│                   │   handling │                                   │
│                   └────────────┘                                   │
└─────────────────────────────────────────────────────────────────────┘
```

**Glue Job Categories:**

| Job | Schedule | Source | Target | Transforms |
|-----|----------|--------|--------|------------|
| `orders_etl` | Every 15 min | salesorder CDC → S3 | fact_orders + fact_order_items | Cast order_id to VARCHAR, filter NZD (currency_code != 'NZD'), standardize timestamps |
| `payments_etl` | Every 15 min | salespayment CDC → S3 | fact_payments | Cast order_id to VARCHAR, calculate fees |
| `customer_etl` | Daily (6 AM) | salescrm + isalescdp | dim_customer | SCD Type 2, RFM calculation, segment assignment |
| `production_etl` | Hourly | opproduction CDC → S3 | fact_productions | Calculate duration_seconds |
| `inventory_etl` | Hourly | scm-shopstock CDC → S3 | fact_stock_changes | Classify change types |
| `coupon_etl` | Daily (6 AM) | salesmarketing | fact_coupon_usage | Status classification |
| `feature_pipeline` | Daily (5 AM) | Redshift | Feature Store | RFM scores, churn features, CLV features |
| `forecast_monitor` | Daily (7 AM) | ireplenishment + salesorder | fact_demand_predictions | Join prediction vs. actual |

### 5.4 S3 Data Lake Structure

```
s3://luckyus-data-lake/
├── raw/                          # Raw CDC logs from DMS
│   ├── salesorder/
│   │   ├── 2026/02/14/
│   │   │   ├── 20260214-001.parquet
│   │   │   └── ...
│   ├── salespayment/
│   └── ...
├── processed/                    # Cleaned, transformed data
│   ├── fact_orders/
│   ├── dim_customer/
│   └── ...
├── curated/                      # Business-ready datasets
│   ├── customer_360/
│   ├── store_performance/
│   └── ...
├── ml/                           # ML training data and artifacts
│   ├── training/
│   │   ├── churn_model/
│   │   ├── clv_model/
│   │   └── ...
│   ├── models/
│   └── predictions/
└── archive/                      # Historical snapshots
```

---

## 6. AI/ML Platform Design

### 6.1 ML Platform Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    ML PLATFORM COMPONENTS                        │
│                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐ │
│  │ FEATURE STORE    │  │ MODEL TRAINING   │  │ MODEL SERVING│ │
│  │ (SageMaker)      │  │ (SageMaker)      │  │              │ │
│  │                  │  │                  │  │ Batch:       │ │
│  │ Online Store:    │  │ Algorithms:      │  │ SageMaker    │ │
│  │ • RFM scores     │  │ • XGBoost        │  │ Processing   │ │
│  │ • Churn risk     │  │ • LightGBM       │  │              │ │
│  │ • CLV predicted  │  │ • Prophet        │  │ Real-time:   │ │
│  │ • User segment   │  │ • Isolation      │  │ SageMaker    │ │
│  │ • Product affinity│ │   Forest         │  │ Endpoint     │ │
│  │                  │  │ • Linear Regr    │  │              │ │
│  │ Offline Store:   │  │ • Neural Nets    │  │ LLM:         │ │
│  │ • Training data  │  │                  │  │ Dify         │ │
│  │ • Feature history│  │ AutoML:          │  │ Platform     │ │
│  │ • Validation sets│  │ SageMaker        │  │              │ │
│  │                  │  │ Autopilot        │  │              │ │
│  └──────────────────┘  └──────────────────┘  └──────────────┘ │
│                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐ │
│  │ MODEL REGISTRY   │  │ EXPERIMENT       │  │ MONITORING   │ │
│  │ (MLflow)         │  │ TRACKING         │  │              │ │
│  │                  │  │ (MLflow)         │  │ SageMaker    │ │
│  │ • Version control│  │                  │  │ Model        │ │
│  │ • Stage promotion│  │ • Hyperparameters│  │ Monitor      │ │
│  │ • Lineage        │  │ • Metrics        │  │              │ │
│  │ • Approval gates │  │ • Artifacts      │  │ • Data drift │ │
│  │                  │  │ • Comparison     │  │ • Accuracy   │ │
│  └──────────────────┘  └──────────────────┘  └──────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Feature Store Design

**Online Features** (low-latency lookup for real-time scoring):

| Feature Group | Features | Update Frequency | Source |
|--------------|----------|-----------------|--------|
| customer_rfm | recency_days, frequency_30d, monetary_30d, rfm_segment | Hourly | fact_orders |
| customer_churn | days_since_last_order, order_velocity_trend, coupon_response_rate | Daily | fact_orders + fact_coupon_usage |
| customer_clv | predicted_12m_clv, clv_segment, lifetime_orders, lifetime_spend | Daily | ML model output |
| product_popularity | order_count_7d, order_count_30d, revenue_7d, bcg_quadrant | Daily | fact_order_items |
| store_performance | daily_revenue, daily_orders, avg_production_time, queue_depth | Hourly | fact_orders + fact_productions |

**Offline Features** (high-volume data for model training):

| Feature Group | Features | Granularity | Source |
|--------------|----------|-------------|--------|
| customer_history | Full order history, coupon history, push response | Per customer | All fact tables |
| product_features | Category, price, production time, waste rate, margin | Per product | dim_product + facts |
| store_features | Location, demographics, foot traffic proxy, maturity | Per store | dim_store + external |
| temporal_features | Day of week, hour, holiday, weather (external) | Per timestamp | dim_date + external |

### 6.3 Dify Integration Architecture

Dify (already deployed) serves as the LLM orchestration layer:

```
┌──────────────────────────────────────────────────────────────┐
│                    DIFY LLM PLATFORM                          │
│                                                              │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────────┐ │
│  │ Executive  │  │ "Ask Lucky"│  │ Customer Response      │ │
│  │ Briefing   │  │ NL Query   │  │ Generator              │ │
│  │ Agent      │  │ Agent      │  │ Agent                  │ │
│  │            │  │            │  │                        │ │
│  │ Trigger:   │  │ Trigger:   │  │ Trigger:               │ │
│  │ Cron (6AM) │  │ Slack/Web  │  │ API call               │ │
│  │            │  │            │  │                        │ │
│  │ Tools:     │  │ Tools:     │  │ Tools:                 │ │
│  │ • SQL via  │  │ • SQL via  │  │ • Customer 360 API     │ │
│  │   MCP      │  │   MCP      │  │ • Product catalog      │ │
│  │ • Redshift │  │ • Schema   │  │ • Win-back templates   │ │
│  │   queries  │  │   explorer │  │                        │ │
│  │ • Metric   │  │ • Read-only│  │                        │ │
│  │   formatters│ │   guardrail│  │                        │ │
│  └────────────┘  └────────────┘  └────────────────────────┘ │
│                                                              │
│  ┌──────────────────────────────────────────────────────────┐│
│  │                  DIFY BACKEND                            ││
│  │  PostgreSQL (aws-luckyus-dify-rw)                       ││
│  │  Redis (luckyus-redis-dify)                             ││
│  │  LLM API: Claude / GPT-4 (configurable)                ││
│  └──────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────┘
```

### 6.4 ML Model Catalog (Target State)

| # | Model | Algorithm | Training Frequency | Serving Mode | Dependency |
|---|-------|-----------|-------------------|-------------|------------|
| 1 | Churn Prediction | XGBoost | Weekly | Batch (daily scores) | Customer 360 |
| 2 | CLV Prediction | BG/NBD + Gamma-Gamma | Monthly | Batch | Customer 360 |
| 3 | Product Recommendation | Collaborative Filtering | Weekly | Real-time (API) | Feature Store |
| 4 | Coupon Uplift | T-Learner | Weekly | Batch | A/B test data |
| 5 | Demand Forecast | Existing model (enhanced) | Daily | Batch | Store + product features |
| 6 | Fraud Detection | Isolation Forest | Daily | Real-time (API) | Transaction stream |
| 7 | Production Time | Linear Regression | Weekly | Real-time (API) | Production features |
| 8 | Price Elasticity | Causal Inference | Monthly | Batch | Coupon + order data |
| 9 | Store Anomaly | Statistical Process Control | N/A (rules) | Streaming | Store features |
| 10 | Infrastructure Anomaly | Isolation Forest | Weekly | Streaming | Prometheus metrics |
| 11 | Site Selection | Gradient Boosted Trees (existing R²=0.94) | Quarterly | On-demand | External data |
| 12 | Staffing Optimizer | Integer Programming | Weekly | Batch | Demand forecast |

---

## 7. Application Integration Layer

### 7.1 API Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    API GATEWAY (EXISTING)                      │
│                                                              │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────────┐ │
│  │ /ml/churn  │  │ /ml/recom  │  │ /ml/fraud              │ │
│  │ (GET)      │  │ (GET)      │  │ (POST)                 │ │
│  │ Returns    │  │ Returns    │  │ Returns                │ │
│  │ churn_score│  │ product_ids│  │ risk_score             │ │
│  └─────┬──────┘  └─────┬──────┘  └──────────┬─────────────┘ │
│        │               │                     │               │
│        ▼               ▼                     ▼               │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────────┐ │
│  │ SageMaker  │  │ SageMaker  │  │ SageMaker              │ │
│  │ Endpoint   │  │ Endpoint   │  │ Endpoint               │ │
│  │ (Batch)    │  │ (Real-time)│  │ (Real-time)            │ │
│  └────────────┘  └────────────┘  └────────────────────────┘ │
│                                                              │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────────┐ │
│  │ /analytics │  │ /briefing  │  │ /query                 │ │
│  │ /dashboard │  │ (GET)      │  │ (POST)                 │ │
│  │ (GET)      │  │ Returns    │  │ NL query →             │ │
│  │ Redshift   │  │ AI summary │  │ SQL → results          │ │
│  └─────┬──────┘  └─────┬──────┘  └──────────┬─────────────┘ │
│        │               │                     │               │
│        ▼               ▼                     ▼               │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────────┐ │
│  │ Redshift   │  │ Dify       │  │ Dify + MCP             │ │
│  │ Data API   │  │ Agent      │  │ DB Gateway             │ │
│  └────────────┘  └────────────┘  └────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

### 7.2 Dashboard Architecture

**Tier 1: Executive Dashboards (Superset or Grafana)**
- Revenue Command Center: Daily/weekly/monthly revenue by store, channel, product
- Customer Health: Active users, churn rate, CLV distribution, acquisition funnel
- Financial Overview: Reconciliation status, P&L proxy, cash flow, tax liability

**Tier 2: Operational Dashboards (Grafana)**
- Store Operations: Real-time orders, production queue, wait times, staff utilization
- Supply Chain: Stock levels, demand vs. actual, waste tracking, supplier deliveries
- IoT Fleet: Device status (online/offline), cup order throughput, maintenance schedule

**Tier 3: Technical Dashboards (Grafana - extend existing)**
- Infrastructure Health: Full-stack monitoring (extend beyond current Redis-only)
- ML Model Performance: Model accuracy, drift detection, prediction volume
- Data Pipeline Health: ETL job status, data freshness, quality checks

---

## 8. Security & Data Governance

### 8.1 Data Classification

| Classification | Examples | Access Control | Encryption |
|---------------|----------|----------------|------------|
| **Public** | Store locations, menu, prices | Open | TLS in transit |
| **Internal** | Revenue metrics, operational KPIs | Role-based (employee) | TLS + at-rest |
| **Confidential** | Customer data, financial records | Role-based (department) | TLS + at-rest + column-level |
| **Restricted** | PII (phone, email), payment data, tax | Named individuals only | TLS + at-rest + column-level + masking |

### 8.2 PII Handling

Existing PII protections observed in the database:
- Phone numbers: Some tables already use hashing/masking
- Email addresses: Collected but access not restricted
- Payment tokens: Tokenized by payment processor

**Required enhancements:**
- Column-level encryption for PII fields in Redshift
- Dynamic data masking for analyst queries (show masked values unless authorized)
- PII discovery scan across all 62 MySQL databases
- Data retention policy (auto-archive data older than 24 months)

### 8.3 RBAC Design

| Role | Redshift Access | Feature Store | ML Platform | Dashboards |
|------|----------------|---------------|-------------|------------|
| Executive | Curated views only | Read | — | Tier 1 |
| Analyst | All non-PII tables | Read | — | Tier 1, 2 |
| Data Engineer | All tables | Read/Write | Deploy | All |
| ML Engineer | Training tables | Read/Write | Full | Tier 2, 3 |
| Operations Manager | Store-specific views | — | — | Tier 2 |
| DBA | System tables only | — | — | Tier 3 |

### 8.4 Audit & Compliance

| Requirement | Implementation |
|-------------|---------------|
| Query audit logging | Redshift audit logging → S3 → CloudTrail |
| Data access tracking | Column-level access logging in Redshift |
| Model decision audit | MLflow experiment tracking + prediction logging |
| Regulatory compliance | SOC 2 alignment, PCI DSS for payment data |
| Data lineage | AWS Glue Data Catalog + custom lineage tracking |

---

## 9. Technology Selection Rationale

### 9.1 Data Warehouse: Amazon Redshift Serverless

| Criterion | Redshift Serverless | Snowflake | BigQuery | Decision |
|-----------|-------------------|-----------|----------|----------|
| AWS integration | Native (DMS, Glue, SageMaker) | Connector needed | Cross-cloud | ✅ Redshift |
| Cost model | Per-RPU-hour (serverless) | Per-credit | Per-query | ✅ Redshift |
| Scaling | Auto-scale, pay per use | Auto-scale | Auto-scale | Tie |
| Existing skills | AWS team already in place | New vendor | New vendor | ✅ Redshift |
| ML integration | SageMaker native | External | Vertex AI | ✅ Redshift |
| Estimated cost | $3-5K/month (projected) | $5-8K/month | $4-6K/month | ✅ Redshift |

**Decision:** Redshift Serverless — native AWS integration minimizes friction, serverless model matches unpredictable query loads of a growing company, and SageMaker Feature Store integration is seamless.

### 9.2 ML Platform: Amazon SageMaker

| Criterion | SageMaker | Databricks ML | Self-managed | Decision |
|-----------|-----------|---------------|-------------|----------|
| Feature Store | Built-in | Feature Store (limited) | Build from scratch | ✅ SageMaker |
| AutoML | Autopilot | AutoML | — | ✅ SageMaker |
| Model hosting | Serverless endpoints | Endpoints | EC2 + containers | ✅ SageMaker |
| Cost | Pay per use | Fixed + compute | Fixed | ✅ SageMaker |
| AWS integration | Native | Connector | Manual | ✅ SageMaker |

**Decision:** SageMaker — end-to-end ML platform with Feature Store, training, hosting, and monitoring in a single service. Serverless endpoints ideal for variable inference loads.

### 9.3 LLM Platform: Dify (Extend Existing)

**Decision:** Extend Dify — already deployed on two PostgreSQL instances with Redis cache. Adding new agents (Executive Briefing, "Ask Lucky") requires configuration, not new infrastructure. Dify supports Claude, GPT-4, and open-source models, providing flexibility.

### 9.4 BI Platform: Grafana (Extend) + Apache Superset (Add)

**Decision:** Extend Grafana for operational/infrastructure dashboards (17 dashboards already exist). Add Apache Superset for business intelligence dashboards (SQL-native, chart builder, embedded analytics). Superset is open-source and can connect to Redshift natively.

---

## 10. Cost Projections

### 10.1 Infrastructure Cost Breakdown

| Component | Monthly Cost | Notes |
|-----------|-------------|-------|
| **Current AWS spend** | **$49,645** | Baseline (Jan 2026) |
| | | |
| **New Components (Incremental):** | | |
| Redshift Serverless | $3,000-5,000 | 128 RPU base, auto-scale |
| AWS DMS (CDC) | $1,000-1,500 | 1 replication instance + 16 tasks |
| AWS Glue | $500-1,000 | ~20 ETL jobs, serverless pricing |
| S3 Data Lake | $200-400 | ~2TB storage, infrequent access tier |
| SageMaker (Training) | $500-1,500 | Spot instances, periodic training |
| SageMaker (Endpoints) | $1,000-2,000 | 3-5 serverless endpoints |
| SageMaker Feature Store | $500-800 | Online + offline stores |
| MLflow (on EC2) | $200-400 | t3.medium instance |
| Apache Superset (on EC2) | $200-400 | t3.large instance |
| Kinesis Data Streams | $500-1,000 | 2-3 streams, real-time CDC |
| CloudWatch (expanded) | $200-500 | Additional metrics/alarms |
| **Incremental subtotal** | **$7,800-14,500** | |
| | | |
| **Total projected** | **$57,445-64,145** | +16-29% over baseline |

### 10.2 Cost Optimization Offsets

| Optimization | Monthly Savings | Notes |
|-------------|----------------|-------|
| EC2 right-sizing + Graviton | $5,000-8,000 | 78% idle instances |
| RDS RI purchases | $1,500-2,500 | Currently 1.3% RI coverage |
| ElastiCache RI purchases | $500-1,000 | Currently 6.6% RI coverage |
| Idle resource termination | $2,000-4,000 | Unused EC2/RDS instances |
| **Total optimization savings** | **$9,000-15,500** | |

**Net impact:** With optimizations, the AI platform can be built for **net $0 incremental cost** to **$5,000/month savings** compared to current spend.

### 10.3 18-Month Cost Trajectory

| Period | Current Infra | New Platform | Optimizations | Net Monthly |
|--------|-------------|-------------|---------------|-------------|
| Month 1-3 | $49,645 | +$4,000 | -$3,000 | $50,645 |
| Month 4-6 | $49,645 | +$8,000 | -$7,000 | $50,645 |
| Month 7-12 | $49,645 | +$12,000 | -$12,000 | $49,645 |
| Month 13-18 | $49,645 | +$15,000 | -$15,500 | $49,145 |

### 10.4 People Cost

| Role | Annual Cost | Phase 1 FTE | Phase 2 FTE | Phase 3 FTE | Phase 4 FTE |
|------|-----------|-------------|-------------|-------------|-------------|
| Data Engineer | $160K | 1 | 2 | 2 | 3 |
| ML Engineer | $175K | 0.5 | 1 | 2 | 2 |
| Data Scientist | $165K | 0 | 0.5 | 1 | 2 |
| Analytics Engineer | $145K | 1 | 1 | 1 | 1 |
| **Annual Team Cost** | | **$310K** | **$595K** | **$875K** | **$1,175K** |

---

## 11. Migration Strategy

### 11.1 Zero-Downtime Migration Approach

The architecture is designed for **additive deployment** — no existing systems are modified or replaced during migration. The data warehouse layer is built alongside existing databases using CDC replication.

```
Phase 1: OBSERVE
├── Deploy DMS CDC for 5 priority databases
├── Stream changes to S3 (raw zone) — no impact on source
├── Build Glue ETL jobs
├── Load Redshift with historical data
└── Validate: compare warehouse queries to source queries

Phase 2: EXTEND
├── Add 7 more CDC pipelines
├── Deploy Feature Store with initial features
├── Train first ML models (churn, CLV)
├── Deploy Superset dashboards
└── Validate: model accuracy, dashboard correctness

Phase 3: SHIFT
├── Redirect analytical queries from source DBs to Redshift
├── Deploy ML endpoints for real-time scoring
├── Integrate LLM agents (Executive Briefing, Ask Lucky)
├── Activate monitoring and alerting
└── Validate: end-to-end platform performance

Phase 4: OPTIMIZE
├── Complete remaining CDC pipelines
├── Implement advanced ML models
├── Add real-time streaming for fraud/queue management
├── Cost optimization (terminate idle resources)
└── Validate: ROI realization
```

### 11.2 Rollback Plan

Every phase includes a rollback strategy:

| Phase | Rollback Mechanism | Data Loss Risk |
|-------|-------------------|---------------|
| Phase 1 | Turn off DMS tasks; delete S3/Redshift data | Zero (source untouched) |
| Phase 2 | Remove feature store; delete models | Zero (source untouched) |
| Phase 3 | Redirect queries back to source DBs | Zero (CDC is read-only) |
| Phase 4 | Revert to Phase 3 state | Zero |

---

## 12. Architecture Decision Records

### ADR-001: Serverless-First Strategy
- **Context:** Small team (2-3 data engineers initially), unpredictable query loads
- **Decision:** Use serverless services (Redshift Serverless, Glue, SageMaker Serverless) wherever possible
- **Consequence:** Higher per-unit cost but zero idle cost; no capacity planning needed; team focuses on data, not infrastructure

### ADR-002: CDC over ETL for Primary Data Movement
- **Context:** Need near-real-time data freshness without impacting source databases
- **Decision:** Use DMS CDC (Change Data Capture) for primary data movement, Glue batch ETL for transformations
- **Consequence:** 10-15 minute data freshness for critical paths; source databases unaffected; CDC captures all changes (not just snapshots)

### ADR-003: Extend Dify Rather Than Build Custom LLM Layer
- **Context:** Dify already deployed on 2 PostgreSQL instances + Redis; proven operational
- **Decision:** Build new LLM use cases as Dify agents rather than custom code
- **Consequence:** Faster development (agent configuration vs. code); unified LLM management; model-agnostic (can switch between Claude, GPT-4, open-source)

### ADR-004: Star Schema over Data Vault
- **Context:** 41 AI use cases with well-defined analytical patterns; small team
- **Decision:** Star schema data warehouse (10 facts, 10 dimensions)
- **Consequence:** Simpler queries (fewer joins); better BI tool compatibility; faster development; trade-off: less flexible for unanticipated query patterns (acceptable at current scale)

### ADR-005: Unified Join Key Resolution
- **Context:** `order_id` type mismatch (bigint in salesorder, varchar in salespayment); multiple ID formats across systems
- **Decision:** Cast all IDs to VARCHAR in the warehouse; create mapping tables for ambiguous keys
- **Consequence:** Consistent join behavior; small storage overhead; eliminates type mismatch errors

### ADR-006: PII Handling via Column-Level Encryption + Dynamic Masking
- **Context:** Customer phone numbers, emails, and payment data in warehouse
- **Decision:** Encrypt PII columns at rest; use Redshift dynamic data masking for analyst access
- **Consequence:** PII protected from unauthorized access; authorized users see masked data unless explicitly granted; compliance-ready

---

*This architecture blueprint is designed for incremental deployment over 18 months, with each phase delivering measurable value while maintaining zero-downtime for existing operations.*

---

*Generated February 14, 2026*
*Luckin Coffee USA — Confidential*

# Luckin Coffee USA - Database Infrastructure & AI Transformation Report

**Report:** Architecture Recommendations
**Date:** February 13, 2026
**Prepared for:** Luckin Coffee USA Leadership Team

---

## 6. Architecture Recommendations

### 6.1 Current Architecture Assessment

#### Strengths of Current Architecture

| Aspect | Assessment | Details |
|--------|-----------|---------|
| Microservices Design | **Strong** | Clean domain separation across 62 MySQL databases (sales, SCM, finance, ops, marketing) |
| Data Volume Management | **Strong** | Appropriate sharding — marketing data (44M records) isolated from order processing (516K) |
| Caching Layer | **Strong** | 78 Redis instances with purpose-specific clusters (auth, session, IoT, production queues) |
| AI Infrastructure | **Strong** | Dify AI platform already deployed; demand forecasting operational with 2.5M predictions |
| IoT Integration | **Strong** | Real-time machine telemetry for all 216 devices with cup-level tracking |
| A/B Testing | **Strong** | Sophisticated experiment infrastructure (6.4M records, traffic splitting) |

#### Gaps Requiring Architecture Investment

| Gap | Risk Level | Recommended Solution |
|-----|-----------|---------------------|
| No centralized analytics layer | **HIGH** | Deploy data warehouse (Section 6.2) |
| No read replicas for analytics | **HIGH** | RDS Read Replicas per domain (Section 6.3) |
| Cross-database queries impossible | **HIGH** | ETL to unified warehouse (Section 6.4) |
| Tax system unimplemented | **CRITICAL** | Schema exists; implement application layer (Section 6.7) |
| No data quality monitoring | **MEDIUM** | Automated validation pipeline (Section 6.5) |
| NZD/USD data contamination | **MEDIUM** | Data partitioning and filtering layer (Section 6.6) |

---

### 6.2 Recommended Data Platform Architecture

#### Target: 4-Layer Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    LAYER 4: APPLICATIONS                            │
│  Grafana Dashboards │ "Ask Lucky" NL │ Executive Briefing │ Alerts │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
┌──────────────────────────┴──────────────────────────────────────────┐
│                    LAYER 3: AI / ML PLATFORM                        │
│  Dify (NL Query) │ SageMaker (ML Models) │ Bedrock (LLM APIs)     │
│  MLflow (Model Registry) │ Feature Store (shared features)         │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
┌──────────────────────────┴──────────────────────────────────────────┐
│                    LAYER 2: DATA PLATFORM                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │
│  │  S3 Data Lake │  │   Redshift   │  │  Glue ETL Pipelines     │  │
│  │  (Raw + Curated│  │  Serverless  │  │  (Transform & Load)     │  │
│  │   Parquet/JSON)│  │  (Analytics) │  │  Scheduled + Event-based│  │
│  └──────────────┘  └──────────────┘  └──────────────────────────┘  │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
┌──────────────────────────┴──────────────────────────────────────────┐
│                    LAYER 1: SOURCE SYSTEMS                          │
│  62 MySQL DBs │ 78 Redis Clusters │ 3 PostgreSQL │ IoT Streams     │
│  (Read Replicas for analytics isolation)                            │
└─────────────────────────────────────────────────────────────────────┘
```

#### Data Warehouse: Amazon Redshift Serverless

**Why Redshift Serverless (not provisioned):**

| Factor | Redshift Serverless | Redshift Provisioned |
|--------|-------------------|---------------------|
| 10-store scale | Pay-per-query, ideal for intermittent analytics | Over-provisioned for current volume |
| Cost at current volume | ~$200–500/month | ~$1,200+/month minimum |
| Scaling | Auto-scales with query load | Manual node management |
| Management overhead | Zero cluster management | Node sizing, vacuuming, resizing |
| Growth readiness | Scales to 100+ stores seamlessly | Requires manual capacity planning |

**Recommended Redshift Schema:**

```sql
-- Dimensional model for analytics
-- Fact tables (loaded via Glue ETL)
fact_orders          -- From luckyus_sales_order (daily incremental)
fact_payments        -- From luckyus_sales_payment (daily incremental)
fact_production      -- From luckyus_opproduction (daily incremental)
fact_inventory       -- From luckyus_scm_shopstock (daily snapshot)
fact_iot_events      -- From luckyus_iot_platform (hourly incremental)
fact_coupon_usage    -- From luckyus_sales_marketing (daily incremental)
fact_demand_forecast -- From luckyus_ireplenishment (daily incremental)

-- Dimension tables (full refresh nightly)
dim_store            -- From luckyus_opshop.t_shop_info
dim_product          -- From luckyus_scm_commodity.t_commodity_base_info
dim_customer         -- From luckyus_sales_crm.t_user (PII masked)
dim_date             -- Generated calendar table
dim_time             -- Generated time-of-day table
dim_channel          -- From luckyus_sales_payment.t_user_channel
```

---

### 6.3 Read Replica Strategy

**Problem:** Running analytical queries directly against production RW instances risks impacting order processing, payment transactions, and production workflows.

**Recommended Read Replica Deployment:**

| Priority | Source Instance | Replica Purpose | Tools Served |
|----------|---------------|-----------------|-------------|
| **P0** | `aws-luckyus-salesorder-rw` | Order analytics | Revenue Reconciliation, Store Performance, Executive Briefing |
| **P0** | `aws-luckyus-salespayment-rw` | Payment analytics | Payment Cost Optimizer, Revenue Reconciliation |
| **P1** | `aws-luckyus-opproduction-rw` | Production analytics | Production Time Optimizer, Store Performance |
| **P1** | `aws-luckyus-scm-shopstock-rw` | Inventory analytics | Inventory Command Center, Demand Forecast Monitor |
| **P2** | `aws-luckyus-salescrm-rw` | Customer analytics | Customer 360, Campaign Analyzer |
| **P2** | `aws-luckyus-salesmarketing-rw` | Marketing analytics | Campaign Analyzer, Customer Acquisition Tracker |

**Configuration:**

```
Instance Class:  db.r6g.large (2 vCPU, 16 GB) — sufficient for analytics
Replication:     Asynchronous (acceptable lag: <1 second)
Storage:         GP3 (matching source)
Cost per replica: ~$150–200/month
Total for 6 replicas: ~$900–1,200/month
```

**Replication Lag Monitoring:**
- Alert threshold: >5 seconds lag
- Critical threshold: >30 seconds lag
- Monitor via CloudWatch `ReplicaLag` metric

---

### 6.4 ETL Pipeline Architecture

#### AWS Glue ETL Design

```
Source MySQL (Read Replicas)
    │
    ▼
AWS Glue Crawler (schema discovery)
    │
    ▼
AWS Glue ETL Jobs (PySpark)
    │
    ├──► S3 Data Lake (s3://luckyus-data-lake/)
    │       ├── raw/           (JSON, as-is from source)
    │       ├── curated/       (Parquet, cleaned, partitioned)
    │       └── aggregated/    (Pre-computed KPIs)
    │
    └──► Redshift Serverless
            ├── raw_schema     (staging tables)
            ├── dwh_schema     (dimensional model)
            └── mart_schema    (department-specific views)
```

**ETL Schedule:**

| Pipeline | Frequency | Source → Target | SLA |
|----------|-----------|----------------|-----|
| Orders & Payments | Every 15 min | MySQL → S3 → Redshift | <20 min end-to-end |
| Production & IoT | Hourly | MySQL → S3 → Redshift | <30 min |
| Inventory Snapshots | Daily 2 AM ET | MySQL → S3 → Redshift | Before 5 AM ET |
| Customer & Marketing | Daily 3 AM ET | MySQL → S3 → Redshift | Before 6 AM ET |
| Full Dimension Refresh | Daily 1 AM ET | MySQL → S3 → Redshift | Before 2 AM ET |
| Demand Forecasts | Daily 4 AM ET | MySQL → S3 → Redshift | Before 5 AM ET |

**Data Quality Checks (embedded in each pipeline):**

| Check | Action on Failure |
|-------|------------------|
| Row count delta >50% from yesterday | Alert + pause pipeline |
| NULL rate >10% in required fields | Alert + continue with warning |
| Duplicate primary keys detected | Deduplicate + alert |
| Timestamp outside expected range | Filter + alert |
| Currency != 'USD' (NZD filtering) | Filter out non-USD records |

---

### 6.5 Data Quality Framework

#### Automated Validation Pipeline

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  Glue ETL    │───▶│ Great        │───▶│ CloudWatch   │
│  Pipeline    │    │ Expectations │    │ Alerts       │
│  (transform) │    │ (validate)   │    │ (notify)     │
└──────────────┘    └──────────────┘    └──────────────┘
```

**Validation Rules by Domain:**

| Domain | Rule | Threshold | Severity |
|--------|------|-----------|----------|
| Orders | `currency_code = 'USD'` | 100% of prod orders | CRITICAL |
| Orders | `total_amount > 0 AND < 500` | 99.9% | HIGH |
| Orders | `order_time` within business hours +/- 2h | 95% | MEDIUM |
| Payments | Every order has matching trade | 99.5% | CRITICAL |
| Payments | `channel_fee > 0` for all transactions | 99% | HIGH |
| Production | `production_time < 1800` seconds (30 min) | 99% | MEDIUM |
| IoT | Device count = 216 (known fleet) | 100% | HIGH |
| Inventory | `stock_quantity >= 0` | 100% | CRITICAL |
| Tax | Row count > 0 in `fi_tax` tables | Until implemented | CRITICAL |

---

### 6.6 Multi-Market Data Separation

**Problem:** NZD-denominated test orders from Cook Islands stores are mixed with USD production data.

**Recommended Approach:**

1. **Database-Level Filtering:**
   ```sql
   -- Add to ALL analytical queries:
   WHERE currency_code = 'USD'
     AND shop_id IN (SELECT id FROM t_shop_info WHERE country_code = 'US')
   ```

2. **ETL-Level Separation:**
   - Glue ETL pipelines filter by `currency_code` at extraction
   - Separate S3 paths: `s3://data-lake/market=US/` and `s3://data-lake/market=NZ/`
   - Redshift views automatically filter to US market

3. **Reporting-Level Guards:**
   - All Grafana dashboards include `currency_code = 'USD'` in base queries
   - Executive Briefing AI pipeline hard-codes USD market filter
   - "Ask Lucky" NL query system adds market filter to generated SQL

---

### 6.7 Critical System Implementations

#### Tax Compliance System (`fi_tax`)

**Current State:** Schema exists with proper table structure, but all tables contain 0 rows.

**Recommended Implementation:**

| Component | Approach |
|-----------|----------|
| Tax Calculation | Integrate with Avalara or TaxJar API for real-time NY state + NYC local tax |
| Tax Recording | Populate `fi_tax` tables from order pipeline (tax_amount already in `t_order_amount`) |
| Tax Filing | Automated monthly summary generation for NY state filing |
| Audit Trail | Immutable log of all tax calculations with rate sources |

**Priority:** Phase 1, Week 1 — regulatory risk is the highest-severity gap.

#### Loyalty Program (`isalesmembermarketing`)

**Current State:** Full schema deployed (points, tiers, rewards tables) but empty.

**Recommended Launch Approach:**

| Phase | Action |
|-------|--------|
| Pre-launch | Retroactively calculate points for existing 277K users based on order history |
| Soft launch | Enable points accrual for new orders (backend only, no UI) |
| Full launch | Mobile app integration with points balance, tier display, reward redemption |

---

### 6.8 Security Architecture

#### Data Access Security Model

```
┌─────────────────────────────────────────────────────┐
│                  ACCESS LAYERS                       │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌───────────────────┐  │
│  │  App Layer│  │ Analytics│  │  AI/ML Platform   │  │
│  │ (R/W)    │  │ (R/O)    │  │  (R/O + Model W)  │  │
│  └────┬─────┘  └────┬─────┘  └────────┬──────────┘  │
│       │              │                  │             │
│  ┌────┴─────┐  ┌────┴─────┐  ┌────────┴──────────┐  │
│  │Production │  │  Read    │  │  Data Warehouse   │  │
│  │  MySQL RW │  │ Replicas │  │  (Redshift)       │  │
│  └──────────┘  └──────────┘  └───────────────────┘  │
└─────────────────────────────────────────────────────┘
```

#### PII Protection Strategy

| Data Element | Current State | Recommendation |
|-------------|--------------|----------------|
| Phone numbers | Partially masked in some tables | Consistent masking: `***-***-1234` in all analytics |
| Email addresses | Stored in plaintext in `t_user` | Hash for analytics; plaintext only in CRM (encrypted at rest) |
| Payment tokens | Stripe tokens (not raw card data) | Maintain current approach; never store raw card numbers |
| Customer names | Stored in `t_user_profile` | Exclude from analytics warehouse; use anonymized IDs |
| Delivery addresses | Not currently stored | When implemented: encrypt at rest, separate storage |

#### PCI-DSS Considerations

| Requirement | Current Status | Action |
|------------|---------------|--------|
| Cardholder data | Not stored (Stripe tokenized) | **Compliant** — maintain Stripe-only approach |
| Network segmentation | VPC with security groups | Review security group rules for analytics layer |
| Access logging | MySQL audit logs available | Enable CloudTrail for all data access |
| Encryption at rest | RDS encryption enabled | Verify all instances; enable for any missing |
| Encryption in transit | SSL connections | Enforce SSL for all database connections |

#### IAM & Access Control Recommendations

| Role | Access Level | Databases | Purpose |
|------|-------------|-----------|---------|
| `luckyus-app-rw` | Read/Write | Production MySQL instances | Application services |
| `luckyus-analytics-ro` | Read-Only | Read replicas only | Analytics dashboards, ETL extraction |
| `luckyus-ml-ro` | Read-Only | Redshift + S3 data lake | ML model training and inference |
| `luckyus-admin` | Full access | All systems | DBA administration (MFA required) |
| `luckyus-exec-ro` | Read-Only | Redshift mart views only | Executive dashboards, "Ask Lucky" |

---

### 6.9 Monitoring & Observability Stack

#### Recommended Tooling

| Layer | Tool | Purpose |
|-------|------|---------|
| Infrastructure | **CloudWatch** | AWS resource metrics, RDS performance, Lambda execution |
| Application | **Grafana + Prometheus** | Custom dashboards, Redis monitoring, alerting |
| Logs | **CloudWatch Logs + Loki** | Centralized log aggregation, search |
| Database | **RDS Performance Insights** | Query-level performance analysis, wait events |
| ETL | **AWS Glue Job Metrics** | Pipeline success/failure, duration, data volume |
| Cost | **AWS Cost Explorer** | Daily spend tracking, anomaly detection |
| Uptime | **CloudWatch Synthetics** | API endpoint health checks |

#### Key Metrics to Monitor

| Category | Metric | Alert Threshold | Tool |
|----------|--------|----------------|------|
| Database | CPU utilization | >80% sustained 5 min | CloudWatch |
| Database | Free storage space | <20% remaining | CloudWatch |
| Database | Connections count | >80% of max | CloudWatch |
| Database | Read replica lag | >5 seconds | CloudWatch |
| Redis | Memory utilization | >85% | Prometheus/Grafana |
| Redis | Eviction rate | >0 evictions/sec | Prometheus/Grafana |
| Redis | Keys without TTL | >1000 keys | Custom monitor |
| ETL | Pipeline failure | Any failure | CloudWatch + SNS |
| ETL | Data freshness | >2x expected interval | Custom monitor |
| Application | Order processing latency | >5 seconds | CloudWatch |
| Application | Payment success rate | <99% | CloudWatch |
| Cost | Daily AWS spend | >120% of 30-day average | Cost Explorer |

---

### 6.10 Deployment & CI/CD Recommendations

#### Infrastructure as Code

| Component | Tool | Repository |
|-----------|------|-----------|
| AWS Resources | **Terraform** | `luckyus-infrastructure` |
| Glue ETL Jobs | **AWS CDK (Python)** | `luckyus-etl-pipelines` |
| Grafana Dashboards | **Grafana Provisioning (YAML)** | `luckyus-observability` |
| ML Models | **MLflow + SageMaker** | `luckyus-ml-platform` |
| Application Config | **AWS Systems Manager Parameter Store** | Managed via Terraform |

#### Environment Strategy

| Environment | Purpose | Data | Cost |
|------------|---------|------|------|
| `dev` | Development and testing | Synthetic data only | Minimal (shared instances) |
| `staging` | Pre-production validation | Anonymized production snapshot (weekly) | ~20% of production |
| `production` | Live operations | Real data | Full infrastructure |

#### Deployment Pipeline

```
Code Commit → Unit Tests → Integration Tests → Staging Deploy
    → Staging Validation → Production Deploy (Blue/Green) → Smoke Tests
```

- **Database migrations:** Flyway or Liquibase with automated rollback
- **ETL changes:** Version-controlled Glue job definitions; canary deployments
- **Dashboard changes:** Git-managed JSON/YAML with PR review
- **ML models:** MLflow registry with staged promotion (Staging → Production)

---

### 6.11 Cost Optimization Recommendations

#### Current vs. Recommended Infrastructure Costs

| Component | Current Monthly | Recommended Monthly | Savings |
|-----------|----------------|--------------------|---------|
| 62 MySQL RW instances | ~$8,000 | ~$8,000 (no change) | — |
| 78 Redis instances | ~$4,000 | ~$3,200 (consolidate underutilized clusters) | $800 |
| 6 Read Replicas (new) | — | +$1,200 | Investment |
| Redshift Serverless (new) | — | +$400 | Investment |
| Glue ETL (new) | — | +$300 | Investment |
| S3 Data Lake (new) | — | +$50 | Investment |
| EC2 instances | ~$15,000 | ~$12,000 (right-sizing per EC2 cost report) | $3,000 |
| **Total** | **~$27,000** | **~$25,150** | **Net: -$1,850** |

**Key Takeaway:** The analytics infrastructure investment (~$1,950/month) is largely offset by EC2 right-sizing and Redis consolidation savings.

#### Redis Consolidation Opportunities

| Current | Proposed | Rationale |
|---------|----------|-----------|
| 78 individual instances | ~60 instances | Merge low-traffic auth/session clusters; share instances for dev/staging workloads |
| Mixed instance sizes | Standardize on `cache.r6g.large` | Consistent sizing simplifies monitoring |
| No TTL on many keys | Enforce TTL policies | Prevent unbounded memory growth |

---

### 6.12 Disaster Recovery & Business Continuity

| Component | RPO | RTO | Mechanism |
|-----------|-----|-----|-----------|
| MySQL Production | 5 minutes | 1 hour | Automated RDS snapshots + Multi-AZ failover |
| Redis Cache | N/A (cache) | 15 minutes | Redis cluster mode with automatic failover |
| Redshift Data | 1 hour | 30 minutes | Continuous backup to S3; serverless auto-recovery |
| S3 Data Lake | 0 (durable) | Immediate | S3 cross-region replication for critical data |
| ETL Pipelines | N/A (idempotent) | 30 minutes | Re-run from last checkpoint |
| Grafana Dashboards | 24 hours | 1 hour | Git-managed provisioning; redeploy from repo |

**Backup Schedule:**

| Resource | Frequency | Retention | Storage |
|----------|-----------|-----------|---------|
| RDS Automated Snapshots | Daily | 14 days | RDS managed |
| RDS Manual Snapshots | Weekly | 90 days | RDS managed |
| S3 Data Lake | Versioning enabled | 30 days (noncurrent) | S3 Glacier after 90 days |
| Redshift Snapshots | Continuous | 7 days (auto), 30 days (manual) | Redshift managed |
| Configuration Backups | On every change | Indefinite | Git repository |

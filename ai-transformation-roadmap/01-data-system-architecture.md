# Deliverable 1: Data System Architecture Report

**Luckin Coffee USA — AI Transformation Roadmap**
**Prepared for:** First Ray Holdings USA Inc.
**Date:** February 14, 2026
**Classification:** Confidential
**Version:** 1.0

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Infrastructure Inventory](#2-infrastructure-inventory)
   - 2.1 MySQL Databases (62 Servers)
   - 2.2 Redis / ElastiCache (78 Instances)
   - 2.3 PostgreSQL Databases (3 Servers)
   - 2.4 Compute — EC2 & EKS
   - 2.5 Messaging — MSK / Kafka
   - 2.6 Storage — S3 & EBS
   - 2.7 Other Managed Services
3. [Entity-Relationship Map](#3-entity-relationship-map)
   - 3.1 Order Domain
   - 3.2 Customer Domain
   - 3.3 Supply Chain Domain
   - 3.4 Finance Domain
   - 3.5 HR / Operations Domain
   - 3.6 Cross-Domain Anchor Keys
4. [Data Flow Architecture](#4-data-flow-architecture)
   - 4.1 Order Lifecycle Flow
   - 4.2 Marketing Lifecycle Flow
   - 4.3 Supply Chain Lifecycle Flow
   - 4.4 Finance Reconciliation Flow
5. [Data Quality Assessment](#5-data-quality-assessment)
   - 5.1 Critical Issues
   - 5.2 High-Severity Issues
   - 5.3 Medium-Severity Issues
   - 5.4 Low-Severity Issues
   - 5.5 Data Freshness Summary
6. [Monitoring Coverage Map](#6-monitoring-coverage-map)
   - 6.1 Grafana Dashboards & Datasources
   - 6.2 Alert Rules
   - 6.3 Prometheus
   - 6.4 CloudWatch
   - 6.5 Monitoring Gaps
7. [Cost Breakdown](#7-cost-breakdown)
   - 7.1 Monthly Summary
   - 7.2 Service-Level Detail
   - 7.3 RDS Cost Breakdown
   - 7.4 3-Month Trend
   - 7.5 Per-Store Economics
   - 7.6 RI / Savings Plans Coverage
   - 7.7 Optimization Opportunities
8. [Appendix: Complete Server Catalog](#8-appendix-complete-server-catalog)
   - A.1 All 62 MySQL Servers by Domain
   - A.2 All 78 Redis Clusters
   - A.3 All 3 PostgreSQL Servers
   - A.4 Newly Explored Server Details

---

## 1. Executive Summary

### Scope

This report documents the complete data system architecture of Luckin Coffee USA (LKUS),
covering all 143 database instances, 233 compute instances, messaging infrastructure,
storage systems, monitoring coverage, and cost profile. The analysis is based on live
system queries, AWS Cost Explorer data, and monitoring platform audits conducted in
January-February 2026.

### Infrastructure Scale

| Resource Category      | Count   | Monthly Cost  | Notes                                    |
|------------------------|---------|---------------|------------------------------------------|
| MySQL Databases        | 62      | $5,527        | RDS Multi-AZ, 5 instance classes         |
| Redis (ElastiCache)    | 78      | $2,314        | 76 Prometheus-monitored, 1 down          |
| PostgreSQL Databases   | 3       | Incl. in RDS  | Dify AI (x2) + geolocation              |
| EC2 Instances          | 233     | $26,693       | 78% idle, 95% underutilized             |
| EKS Node Group         | 20      | $12,763       | m6i.8xlarge/4xlarge, <2% CPU             |
| MSK / Kafka            | --      | $2,306        | 308 topics across cluster                |
| OpenSearch             | --      | $2,647        | luckylfe-log + luckyur-log clusters      |
| S3 Storage             | --      | $348          | +43.9% growth trend                      |
| Other (DocumentDB, EMR, etc.) | -- | $1,557  | DocumentDB $843, EMR $565, EKS ctrl $149 |
| **TOTAL**              | **143 DBs, 233 EC2** | **$49,645/mo** | **$595K annualized**      |

### Maturity Assessment

```
DIMENSION                  SCORE   GRADE   NOTES
─────────────────────────  ──────  ──────  ──────────────────────────────────
Data Collection            8/10    A       Rich transactional data across all domains
Schema Design              6/10    B-      Type mismatches, naming inconsistencies
Data Quality               5/10    C       Empty tax tables, test data contamination
Integration / Join Keys    5/10    C       Cross-domain joins possible but fragile
Monitoring                 2/10    D       3 broken alert rules, massive gaps
Cost Efficiency            3/10    D+      78% idle EC2, 49.8% On-Demand spend
AI/ML Readiness            6/10    B-      6 ML systems deployed, rich feature data
Documentation              2/10    D       No data dictionary, no lineage tracking
```

### Key Findings

1. **Data richness exceeds expectations for a 10-store chain.** 143 database instances,
   487K completed orders, 275K registered users, 2.5M demand predictions, and 6.4M A/B
   test records provide a substantial foundation for AI/ML initiatives.

2. **Infrastructure is massively over-provisioned.** 78% of EC2 instances are idle (<2%
   CPU). The fleet was likely cloned from Luckin China's architecture and never right-sized
   for a 10-store US operation.

3. **Monitoring is nearly non-existent.** Only 3 alert rules exist (all broken). Zero
   CloudWatch alarms are active. No monitoring covers EC2, RDS performance, OpenSearch,
   Kafka, DocumentDB, EKS, application metrics, or business KPIs.

4. **Critical compliance gap: US tax system is empty.** The `fi_tax` database has 0 rows
   across all tables. US sales tax compliance is not implemented at the database level.

5. **Type mismatches create silent data quality risks.** The `order_id` column is `bigint`
   in salesorder but `varchar` in salespayment and iotplatform. Joins work but casting
   is implicit and fragile.

6. **50.2% of spend is already RI-covered, but RDS and ElastiCache are critically
   exposed.** EC2 has 90.4% RI coverage, but RDS is at 1.3% (most RIs expired) and
   ElastiCache at 6.6%.

---

## 2. Infrastructure Inventory

### 2.1 MySQL Databases (62 Servers)

LKUS operates 62 MySQL database servers on AWS RDS, organized across 7 business domains.
All databases are accessed via the MCP DB Gateway with read-write (`-rw`) connection
strings. The RDS fleet uses a mix of instance classes: db.r5.xlarge (1 Multi-AZ),
db.t4g.medium (multiple), db.t4g.micro (multiple), db.t4g.xlarge, db.t4g.large,
and db.m5.large.

#### 2.1.1 Sales Domain (12 servers)

| # | Server Name                              | Primary Use                    | Key Tables (sampled)              | Est. Rows   |
|---|------------------------------------------|--------------------------------|-----------------------------------|-------------|
| 1 | aws-luckyus-salesorder-rw                | Order management               | sales_order, order_detail         | 487K orders |
| 2 | aws-luckyus-salespayment-rw              | Payment processing             | sales_payment, trade_record       | 518K trades |
| 3 | aws-luckyus-salescrm-rw                  | CRM / user profiles            | crm_user, user_profile            | 275K users  |
| 4 | aws-luckyus-salesmarketing-rw            | Campaign management            | activity, coupon, ab_test         | 514K acts   |
| 5 | aws-luckyus-isalescdp-rw                 | Customer Data Platform         | user_state, user_tag              | 980K states |
| 6 | aws-luckyus-isalesdatamarketing-rw       | Data-driven marketing          | marketing_data, user_segment      | --          |
| 7 | aws-luckyus-isalesmembermarketing-rw     | Member marketing               | member_activity, loyalty          | EMPTY       |
| 8 | aws-luckyus-isalesprivatedomain-rw       | Private domain ops             | private_user, channel_group       | --          |
| 9 | aws-luckyus-cdpactivity-rw               | CDP activity tracking          | cdp_event, activity_log           | --          |
| 10| aws-luckyus-opshopsale-rw                | Shop sales operations          | shop_sale, daily_report           | --          |
| 11| aws-luckyus-upush-rw                     | Push notifications             | push_task, sms_record             | 2.3M SMS    |
| 12| aws-luckyus-iluckyams-rw                 | App messaging service          | message_template, send_log        | --          |

**Notable findings — Sales Domain:**
- salesorder: 487,251 completed orders (status=90), representing $2.19M cumulative revenue
- salespayment: 518,427 trade records with payment method and channel tracking
- salesmarketing: 2,424,506 coupon instances issued; 37.3M expired coupons (likely China migration bloat); 6,386,203 A/B test records
- isalescdp: 980,000+ user state records; powers the Customer Data Platform
- isalesmembermarketing: Loyalty/membership tables exist but are EMPTY — program not launched
- upush: 2.3M SMS messages sent, 8M+ push notifications delivered

#### 2.1.2 Operations Domain (6 servers)

| # | Server Name                              | Primary Use                    | Key Tables                        | Est. Rows   |
|---|------------------------------------------|--------------------------------|-----------------------------------|-------------|
| 1 | aws-luckyus-opproduction-rw              | Production/drink making        | production_order, machine_log     | 502K records|
| 2 | aws-luckyus-opempefficiency-rw           | Employee efficiency            | clock_in, schedule, employee      | 47.5K clocks|
| 3 | aws-luckyus-opshop-rw                    | Shop master data               | shop, shop_area, shop_config      | 11 shops    |
| 4 | aws-luckyus-opqualitycontrol-rw          | Quality control                | qc_record, inspection             | --          |
| 5 | aws-luckyus-iopshopexpand-rw             | Shop expansion planning        | expansion_plan, site_eval         | --          |
| 6 | aws-luckyus-iopocp-rw                    | OCP operations                 | ocp_config, operational_data      | --          |

**Notable findings — Operations Domain:**
- opproduction: 502,130 production records; average production time 204 seconds per drink
- opempefficiency: 324 employees tracked, 47,500 clock-in records, 15,700 schedule entries
- opshop: Master data for 11 active stores (10 Manhattan + 1 JFK kiosk)

#### 2.1.3 Supply Chain Management Domain (9 + 2 servers)

| # | Server Name                              | Primary Use                    | Key Tables                        | Est. Rows   |
|---|------------------------------------------|--------------------------------|-----------------------------------|-------------|
| 1 | aws-luckyus-scm-shopstock-rw             | Shop inventory                 | stock_change, stock_snapshot      | 9.1M changes|
| 2 | aws-luckyus-scm-ordering-rw              | Store ordering                 | order_plan, order_record          | --          |
| 3 | aws-luckyus-scm-purchase-rw              | Procurement                    | purchase_order, shipment          | 694 POs     |
| 4 | aws-luckyus-scm-plan-rw                  | Demand planning                | demand_prediction, plan_config    | 2.5M preds  |
| 5 | aws-luckyus-scm-wds-rw                   | Warehouse distribution         | warehouse, distribution_record    | --          |
| 6 | aws-luckyus-scm-wmssimulate-rw           | WMS simulation                 | simulation_run, sim_result        | --          |
| 7 | aws-luckyus-scm-asset-rw                 | Asset management               | asset, asset_category             | --          |
| 8 | aws-luckyus-scm-openapi-rw               | SCM API services               | api_config, api_log               | --          |
| 9 | aws-luckyus-scmcommodity-rw              | Commodity / product master     | commodity, category, sku          | --          |
| 10| aws-luckyus-scmsrm-rw                    | Supplier relationship mgmt     | supplier, contract                | --          |
| 11| aws-luckyus-ireplenishment-rw            | AI replenishment engine        | order_prediction, replenish_plan  | 124K preds  |

**Notable findings — SCM Domain:**
- scm-shopstock: 9,136,482 stock change records — highest-volume transactional table in the system
- scm-plan: 2,517,238 demand prediction records — proves active AI/ML demand forecasting
- scm-purchase: 694 purchase orders, 1,670 shipment records
- ireplenishment: 124,000 AI-generated order predictions — automated replenishment engine active

#### 2.1.4 Finance Domain (5 servers)

| # | Server Name                              | Primary Use                    | Key Tables                        | Est. Rows   |
|---|------------------------------------------|--------------------------------|-----------------------------------|-------------|
| 1 | aws-luckyus-ifiaccounting-rw             | Accounting                     | accounting_entry, bill, voucher   | --          |
| 2 | aws-luckyus-fitax-rw                     | Tax management                 | tax_record, tax_config            | **0 rows**  |
| 3 | aws-luckyus-fichargecontrol-rw           | Charge control                 | charge_rule, charge_record        | --          |
| 4 | aws-luckyus-ibillingcentersrv-rw         | Billing center                 | billing_record, invoice           | --          |
| 5 | aws-luckyus-iunifiedreconcile-rw         | Unified reconciliation         | reconcile_record, match_result    | --          |

**Notable findings — Finance Domain:**
- fitax: **CRITICAL** — ALL tables are empty (0 rows). US sales tax compliance is NOT
  implemented at the database level. This represents a significant regulatory risk.
- ifiaccounting: Active with 3-way matching via bill_no / trade_serial_no / order_serial
- iunifiedreconcile: Unified reconciliation service operational

#### 2.1.5 Platform / Infrastructure Domain (18 servers)

| # | Server Name                              | Primary Use                    |
|---|------------------------------------------|--------------------------------|
| 1 | aws-luckyus-framework01-rw               | Framework services (primary)   |
| 2 | aws-luckyus-framework02-rw               | Framework services (secondary) |
| 3 | aws-luckyus-iadmin-rw                    | Admin platform                 |
| 4 | aws-luckyus-ipermission-rw               | Permission management          |
| 5 | aws-luckyus-iluckyauthapi-rw             | Authentication API             |
| 6 | aws-luckyus-iworkflowmidlayer-rw         | Workflow middleware            |
| 7 | aws-luckyus-oplog-rw                     | Operations logging             |
| 8 | aws-luckyus-iopenadmin-rw                | Open platform admin            |
| 9 | aws-luckyus-iopenlinker-rw               | Open platform linker           |
| 10| aws-luckyus-iopenservice-rw              | Open platform services         |
| 11| aws-luckyus-ibizconfigcenter-rw          | Business config center         |
| 12| aws-luckyus-iluckyhealth-rw              | Health monitoring platform     |
| 13| aws-luckyus-iluckymedia-rw               | Media services                 |
| 14| aws-luckyus-iotplatform-rw               | IoT platform (coffee machines) |
| 15| aws-luckyus-devops-rw                    | DevOps operations              |
| 16| aws-luckyus-ijumpserver-jumpserver-rw    | Jump server access mgmt       |
| 17| aws-luckyus-iluckydorisops-rw            | Doris operations platform      |
| 18| aws-luckyus-mfranchise-rw                | Franchise management           |

**Notable findings — Platform Domain:**
- iotplatform: 587,143 cup/event records; device_mark used to link machines to orders; 57% of IoT devices offline per operational reports
- framework01/02: Core microservice framework tables, high slow-query log volume (263MB + 241MB)
- ipermission: High slow-query volume (206MB), suggests permission checks are a bottleneck

#### 2.1.6 Data / Analytics Domain (5 servers)

| # | Server Name                              | Primary Use                    |
|---|------------------------------------------|--------------------------------|
| 1 | aws-luckyus-ldas-rw                      | LDAS data services             |
| 2 | aws-luckyus-ldas01-rw                    | LDAS node 01 (high slow-query) |
| 3 | aws-luckyus-pubdm-rw                     | Public data mart               |
| 4 | aws-luckyus-icyberdata-rw                | CyberData ETL/analytics        |
| 5 | aws-luckyus-dbatest-rw                   | DBA testing                    |

**Notable findings — Data/Analytics Domain:**
- icyberdata: Highest slow-query log volume at 3.4 GB; CyberData performs ETL and archival
  operations; contains tables timestamped Sep 2025 (archival pipeline)
- ldas01: Second-highest slow-query volume at 1.4 GB
- recovery-dbatest: Recovery testing environment (195MB slow-query logs)

#### 2.1.7 HR / Other Domain (5 servers)

| # | Server Name                              | Primary Use                    |
|---|------------------------------------------|--------------------------------|
| 1 | aws-luckyus-iehr-rw                      | eHR (electronic HR) system     |
| 2 | aws-luckyus-igers-rw                     | GERS system                    |
| 3 | aws-luckyus-iriskcontrolservice-rw       | Risk control service           |
| 4 | aws-luckyus-dbatest-rw                   | DBA test environment           |
| 5 | recovery-dbatest                         | DBA recovery test              |

**Notable findings — HR/Other Domain:**
- iehr: 324 employee records linked to opempefficiency for workforce analytics
- iriskcontrolservice: Fraud and risk scoring; connected to Grafana as a datasource

#### 2.1.8 MySQL Fleet Summary

```
DOMAIN                  SERVERS   KEY METRIC                    STATUS
──────────────────────  ────────  ────────────────────────────  ──────
Sales                   12        487K orders, 275K users       Active
Operations              6         502K production records       Active
Supply Chain            11        9.1M stock changes, 2.5M AI  Active
Finance                 5         Tax tables EMPTY              WARNING
Platform/Infrastructure 18        587K IoT events               Active
Data/Analytics          5         3.4GB slow-query (CyberData)  Active
HR/Other                5         324 employees                 Active
──────────────────────  ────────  ────────────────────────────  ──────
TOTAL                   62
```

---

### 2.2 Redis / ElastiCache (78 Instances)

LKUS operates 78 ElastiCache Redis instances. 76 are monitored via a single Prometheus
scrape job (`aws-redis-job`). Of these, 75 are reporting as UP and 1 is DOWN
(luckyus-iopenlinkeradmin — hostname contains a trailing space causing connection failure).

#### 2.2.1 Memory & Key Distribution (10 Analyzed Clusters)

| Cluster                    | Memory Used | Total Keys | Evicted | Hit Rate  | TTL Status        |
|----------------------------|-------------|------------|---------|-----------|-------------------|
| luckyus-isales-market      | 1.28 GB     | 5,600,000  | 0       | 94.2%     | 2.69M keys NO TTL |
| luckyus-session            | 48.3 MB     | 150,000    | 0       | 99.6%     | TTL set (healthy) |
| luckyus-isales-order       | 22.1 MB     | 89,000     | 0       | 97.8%     | Mixed             |
| luckyus-auth               | 18.7 MB     | 72,000     | 0       | 98.1%     | TTL set           |
| luckyus-apigateway         | 12.4 MB     | 48,000     | 0       | 96.3%     | TTL set           |
| luckyus-scm-shopstock      | 8.2 MB      | 31,000     | 0       | 88.4%     | Mixed             |
| luckyus-shopsale           | 5.1 MB      | 19,000     | 0       | **2.9%**  | TTL set           |
| luckyus-production         | 4.8 MB      | 18,000     | 0       | 91.2%     | TTL set           |
| luckyus-iotplatform        | 3.9 MB      | 15,000     | 0       | 87.6%     | Mixed             |
| luckyus-empefficiency      | 2.1 MB      | 8,000      | 0       | 93.4%     | TTL set           |
| **TOTAL (sampled)**        | **~1.43 GB**| --         | **0**   | --        | --                |

**Critical finding: luckyus-shopsale has a 2.9% hit rate** — 47.3M cache misses vs. only
1.4M cache hits. This cluster is essentially non-functional as a cache layer and is
generating unnecessary database load. Every request falls through to MySQL.

**Growth risk: luckyus-isales-market** — The dominant cluster at 1.28 GB and 5.6M keys.
2.69M keys have NO TTL set, meaning they will never expire. This creates unbounded memory
growth. At current trajectory, this cluster will require a node upgrade within 6-8 months.

#### 2.2.2 Session Management

```
luckyus-session Cluster Profile:
├── Active Sessions:     ~150,000
├── Memory Footprint:    48.3 MB
├── Hit Rate:            99.6% (excellent)
├── Avg Session Size:    ~322 bytes
├── TTL Policy:          Set on all keys (healthy)
└── Evictions:           0 (no memory pressure)
```

The session cluster is well-tuned. 150K active sessions across 275K registered users
indicates a 54.5% session activity ratio, consistent with reported user engagement patterns.

#### 2.2.3 Redis Cluster Categories

| Category                 | Count | Examples                                              |
|--------------------------|-------|-------------------------------------------------------|
| Authentication & Session | 8     | auth, authservice, session, unionauth variants        |
| Sales & CRM              | 10    | isales-commodity, isales-crm, isales-market, etc.     |
| SCM / Supply Chain       | 11    | scm-asset, scm-commodity, scm-ordering, etc.          |
| DevOps & Infrastructure  | 6     | devops, cmdb, jumpserver, chronus, koala, daq          |
| Big Data & Analytics     | 5     | bigdata-cyberdata, bigdata-dataplatform, ldas, pub-dm  |
| Finance & Billing        | 6     | billcenterservice, ifiaccounting, ifitax, etc.        |
| Operations               | 9     | shop, shopsale, empefficiency, production, etc.       |
| Platform Services        | 18    | iadmin, iopenlinker, iotplatform, ipermission, etc.   |
| API Gateway & Network    | 3     | apigateway, waf, web                                  |
| AI Platform              | 1     | redis-dify                                            |
| Other                    | 1     | ilkm                                                  |
| **TOTAL**                | **78**|                                                       |

---

### 2.3 PostgreSQL Databases (3 Servers)

| # | Server Name                  | Engine     | Primary Use                | Key Tables / Notes                |
|---|------------------------------|------------|----------------------------|-----------------------------------|
| 1 | aws-luckyus-dify-rw          | PostgreSQL | Dify AI platform (primary) | workflows, apps, conversations    |
| 2 | aws-luckyus-difynew-rw       | PostgreSQL | Dify AI platform (new)     | Migration target for Dify upgrade |
| 3 | aws-luckyus-pgilkmap-rw      | PostgreSQL | LK Map geolocation         | PostGIS extensions, store coords  |

**Notable findings:**
- The Dify AI platform runs on PostgreSQL (not MySQL), indicating it was deployed as a
  standalone AI/LLM orchestration layer separate from the main MySQL-based application stack
- pgilkmap uses PostGIS for geospatial queries — powers the store locator and site selection
  model's geographic features
- Two Dify instances suggest an in-progress migration or version upgrade

---

### 2.4 Compute — EC2 & EKS

#### 2.4.1 EC2 Fleet Summary

| Metric                        | Value        |
|-------------------------------|--------------|
| Total Running Instances       | 233          |
| Monthly EC2 Cost (with EDP)   | $26,693      |
| Idle Instances (China std)    | 181 (78%)    |
| Underutilized (AWS std)       | 222 (95%)    |
| Platform: Linux               | 230 (98.7%)  |
| Platform: Windows             | 3 (1.3%)     |
| AZ: us-east-1a                | 212 (91.0%)  |
| AZ: us-east-1b                | 17 (7.3%)    |
| AZ: us-east-1c                | 4 (1.7%)     |

**WARNING:** 91% concentration in us-east-1a creates significant availability risk.

#### 2.4.2 Instance Type Distribution

| Instance Type  | Count | Monthly Cost  | % Fleet | % Cost | Avg CPU |
|----------------|-------|---------------|---------|--------|---------|
| c6i.large      | 144   | $4,286        | 61.8%   | 16.4%  | <1%     |
| c6i.xlarge     | 45    | $2,681        | 19.3%   | 10.3%  | <1%     |
| m6i.8xlarge    | 13    | $10,055       | 5.6%    | 38.5%  | 1.7%    |
| m6i.4xlarge    | 7     | $2,706        | 3.0%    | 10.4%  | 1.9%    |
| m5.xlarge      | 6     | $579          | 2.6%    | 2.2%   | <5%     |
| c6i.2xlarge    | 5     | $855          | 2.1%    | 3.3%   | <1%     |
| m6a.large      | 3     | $130          | 1.3%    | 0.5%   | <5%     |
| r6i.2xlarge    | 2     | $507          | 0.9%    | 1.9%   | <5%     |
| m6a.xlarge     | 2     | $174          | 0.9%    | 0.7%   | <5%     |
| r6i.4xlarge    | 1     | $507          | 0.4%    | 1.9%   | <5%     |
| c6i.4xlarge    | 1     | $343          | 0.4%    | 1.3%   | <1%     |
| t3.large       | 1     | $42           | 0.4%    | 0.2%   | Variable|
| m4.xlarge      | 1     | $101          | 0.4%    | 0.4%   | <5%     |
| m4.large       | 1     | $50           | 0.4%    | 0.2%   | <5%     |
| c5.large       | 1     | $43           | 0.4%    | 0.2%   | <5%     |
| **TOTAL**      | **233** | **$26,693** |         |        |         |

**Key observation:** The c6i fleet (144 c6i.large + 45 c6i.xlarge + 5 c6i.2xlarge +
1 c6i.4xlarge = 195 instances) accounts for 84% of the fleet but only 31.3% of cost.
The 20 EKS m6i nodes (13 m6i.8xlarge + 7 m6i.4xlarge) account for only 8.6% of the
fleet but 48.9% of cost, all running at <2% CPU utilization.

#### 2.4.3 EKS Node Group

| Instance Type | Count | Monthly Cost | Avg CPU | Role        |
|---------------|-------|--------------|---------|-------------|
| m6i.8xlarge   | 13    | $10,055      | 1.7%    | EKS worker  |
| m6i.4xlarge   | 7     | $2,706       | 1.9%    | EKS worker  |
| **TOTAL**     | **20**| **$12,763**  | **<2%** | --          |

EKS control plane cost: $149/month (separate line item).

The EKS node group represents the single largest cost optimization opportunity. These 20
instances consume $12,763/month ($153K/year) while running at <2% CPU utilization. However,
Kubernetes workload analysis is required before rightsizing, as pod resource requests may
prevent consolidation even with low actual utilization.

---

### 2.5 Messaging — MSK / Kafka

| Metric                | Value       |
|-----------------------|-------------|
| Monthly Cost          | $2,306      |
| Total Topics          | 308         |
| Broker Instance Type  | kafka.m5.large (est.) |
| Cluster Configuration | 3 brokers (est.)      |

The MSK cluster hosts 308 Kafka topics supporting event-driven communication between
microservices. Topic categories include:

```
CATEGORY                    ESTIMATED TOPICS   PURPOSE
────────────────────────    ────────────────   ─────────────────────
Order events                ~40                Order state transitions
Payment events              ~25                Payment confirmations
Production events           ~30                Drink production status
IoT device events           ~35                Machine telemetry
Marketing events            ~25                Campaign triggers
SCM events                  ~45                Inventory changes
Finance events              ~20                Accounting entries
Platform events             ~50                System-level events
Data pipeline events        ~38                ETL and sync triggers
────────────────────────    ────────────────   ─────────────────────
TOTAL                       ~308
```

---

### 2.6 Storage — S3 & EBS

#### 2.6.1 S3 Storage

| Metric                   | Value     |
|--------------------------|-----------|
| Monthly Cost             | $348      |
| Month-over-Month Growth  | +43.9%    |
| Primary Buckets          | Media assets, logs, backups, data lake |

The +43.9% growth rate is the highest of any service. If sustained, S3 costs will reach
~$500/month by mid-2026. This growth likely reflects increasing log archival, media asset
storage from marketing campaigns, and data lake accumulation.

#### 2.6.2 EBS Volumes

| Volume Type | Count      | % of Total | Notes                                    |
|-------------|------------|------------|------------------------------------------|
| gp3         | ~220       | 94%        | Current generation, optimized             |
| gp2         | 19         | 6%         | Legacy, should migrate to gp3             |

The gp2-to-gp3 migration is nearly complete. The remaining 19 gp2 volumes should be
migrated for an estimated $18.20/month savings and improved IOPS performance.

---

### 2.7 Other Managed Services

| Service       | Monthly Cost | Key Metrics                                        |
|---------------|--------------|-----------------------------------------------------|
| OpenSearch    | $2,647       | 2 domains (luckylfe-log, luckyur-log); 22% RI coverage |
| DocumentDB    | $843         | MongoDB-compatible; used for document-oriented data |
| EMR           | $565         | Elastic MapReduce; batch data processing            |
| EKS (ctrl)    | $149         | Kubernetes control plane                            |
| CloudFront    | Incl. other  | CDN for static assets and media                     |
| WAF           | Incl. other  | Web Application Firewall                            |
| Lambda        | <$50         | Image transformation, monitoring functions          |
| API Gateway   | <$50         | 3 API endpoints (prod, test, YangTao)               |

**OpenSearch detail:**
- luckylfe-log: Log aggregation and search. Experienced RED status incident on 2026-02-12
  due to 3 data node crashes (JVM OOM). Escalated from Yellow to Red.
- luckyur-log: Storage crisis identified on 2026-02-10 — approaching disk capacity limits.
- Combined: 22% RI coverage (3 of 4 RIs expired).

---

## 3. Entity-Relationship Map

This section documents the join keys and relationships between database systems, verified
through live SQL queries against production databases. Each relationship includes the
column names, data types, and any type mismatches or naming inconsistencies discovered.

### 3.1 Order Domain

```
┌─────────────────┐     order_id      ┌──────────────────┐     order_id      ┌──────────────────┐
│   salesorder     │────(bigint)──────▶│   salespayment   │────(bigint)──────▶│   opproduction   │
│                  │                   │                  │                   │                  │
│ order_id BIGINT  │   ⚠ TYPE MISMATCH│ order_id VARCHAR  │   ✅ CLEAN MATCH  │ order_id BIGINT  │
│ order_no VARCHAR │   order_id:       │ trade_no VARCHAR  │                   │ production_time  │
│ user_no VARCHAR  │   bigint↔varchar  │ user_no VARCHAR   │                   │ machine_id       │
│ shop_id BIGINT   │                   │ payment_method    │                   │                  │
│ status INT (=90) │                   │ amount DECIMAL    │                   │                  │
└─────────────────┘                   └──────────────────┘                   └──────────────────┘
        │                                      │                                      │
        │ user_no                               │ trade_no                              │ device_mark
        ▼                                      ▼                                      ▼
┌─────────────────┐                   ┌──────────────────┐                   ┌──────────────────┐
│   salescrm      │                   │  ifiaccounting   │                   │   iotplatform    │
│                  │                   │                  │                   │                  │
│ user_no VARCHAR  │                   │ trade_serial_no  │                   │ device_mark VCHAR│
│ phone VARCHAR    │                   │ ≈ trade_no       │                   │ order_id VARCHAR │
│ register_time    │                   │ (NAME MISMATCH)  │                   │ ⚠ TYPE MISMATCH │
└─────────────────┘                   └──────────────────┘                   │ bigint↔varchar   │
                                                                             └──────────────────┘
```

#### 3.1.1 Detailed Join Key Analysis — Order Domain

| Source Table     | Target Table     | Join Key(s)                    | Source Type | Target Type | Match Quality |
|------------------|------------------|--------------------------------|-------------|-------------|---------------|
| salesorder       | salespayment     | order_id                       | BIGINT      | VARCHAR     | **MISMATCH**  |
| salesorder       | salespayment     | user_no                        | VARCHAR     | VARCHAR     | Clean         |
| salesorder       | salespayment     | trade_no                       | VARCHAR     | VARCHAR     | Clean         |
| salesorder       | opproduction     | order_id                       | BIGINT      | BIGINT      | Clean         |
| salespayment     | ifiaccounting    | trade_no ↔ trade_serial_no     | VARCHAR     | VARCHAR     | **NAME MISMATCH** |
| opproduction     | iotplatform      | order_id                       | BIGINT      | VARCHAR     | **MISMATCH**  |
| iotplatform      | opproduction     | device_mark                    | VARCHAR     | VARCHAR     | Clean         |

**Risk Assessment:**
- The `order_id` type mismatch (bigint vs. varchar) affects 3 of 6 join paths in the order
  domain. While MySQL performs implicit casting, this creates:
  - Index bypass risk (varchar column cannot use numeric index efficiently)
  - Silent data truncation risk for very large order IDs
  - Query plan instability under load
- The `trade_no` ↔ `trade_serial_no` naming mismatch is a documentation issue but the
  underlying data represents the same concept (payment transaction identifier).

### 3.2 Customer Domain

```
┌─────────────────┐     user_no       ┌──────────────────┐     user_no       ┌──────────────────┐
│    salescrm     │────(varchar)─────▶│    isalescdp     │────(varchar)─────▶│ salesmarketing   │
│                  │                   │                  │                   │                  │
│ 275K users       │   ✅ CLEAN MATCH  │ 980K user states │   ✅ CLEAN MATCH  │ 514K activities  │
│ user_no VARCHAR  │                   │ user_no VARCHAR  │                   │ user_no VARCHAR  │
│ group_no VARCHAR │   group_no        │ group_no VARCHAR │                   │ activity_id      │
│ phone VARCHAR    │────(varchar)─────▶│ user_state INT   │                   │ coupon_id        │
│ register_time DT │                   │ tag_data JSON    │                   │ ab_test_id       │
└─────────────────┘                   └──────────────────┘                   └──────────────────┘
                                               │                                      │
                                               │ user_no                               │ user_no
                                               ▼                                      ▼
                                      ┌──────────────────┐                   ┌──────────────────┐
                                      │isalesdatamarketing│                  │     upush        │
                                      │                  │                   │                  │
                                      │ user_no VARCHAR  │                   │ 2.3M SMS sent    │
                                      │ segment_id       │                   │ 8M+ push notifs  │
                                      │ behavior_data    │                   │ user_no VARCHAR  │
                                      └──────────────────┘                   └──────────────────┘
```

#### 3.2.1 Detailed Join Key Analysis — Customer Domain

| Source Table         | Target Table          | Join Key(s)  | Source Type | Target Type | Match Quality |
|----------------------|-----------------------|--------------|-------------|-------------|---------------|
| salescrm             | isalescdp             | user_no      | VARCHAR     | VARCHAR     | Clean         |
| salescrm             | isalescdp             | group_no     | VARCHAR     | VARCHAR     | Clean         |
| isalescdp            | salesmarketing        | user_no      | VARCHAR     | VARCHAR     | Clean         |
| isalescdp            | isalesdatamarketing   | user_no      | VARCHAR     | VARCHAR     | Clean         |
| salesmarketing       | upush                 | user_no      | VARCHAR     | VARCHAR     | Clean         |

**Assessment:** The customer domain has the cleanest join architecture. `user_no` (VARCHAR)
is used consistently across all 5 systems as the primary customer identifier. No type
mismatches or naming inconsistencies detected.

**Data volume flow:**
```
salescrm (275K users)
  └──▶ isalescdp (980K user states)     ← 3.56x amplification (multiple states per user)
         └──▶ salesmarketing (514K activities, 2.42M coupons, 6.4M A/B tests)
                └──▶ upush (2.3M SMS, 8M push)    ← 10.3M total notifications
```

### 3.3 Supply Chain Domain

```
┌─────────────────┐  shop_dept_id +   ┌──────────────────┐   order_ref      ┌──────────────────┐
│ scm-shopstock   │──goods_mid───────▶│  ireplenishment  │──────────────────▶│  scm-ordering    │
│                  │                   │                  │                   │                  │
│ 9.1M stock chgs  │  ✅ CLEAN MATCH   │ 124K predictions │                   │ order_plan       │
│ shop_dept_id BIG │  shop_dept_id:    │ shop_dept_id BIG │                   │ order_record     │
│ goods_mid VCHAR  │  bigint↔bigint   │ goods_mid VCHAR  │                   │                  │
│ stock_qty INT    │  goods_mid:       │ predict_qty INT  │                   │                  │
│ change_time DT   │  varchar↔varchar │ confidence FLOAT │                   │                  │
└─────────────────┘                   └──────────────────┘                   └──────────────────┘
                                                                                     │
                                                                                     │ purchase_ref
                                                                                     ▼
┌─────────────────┐                                                         ┌──────────────────┐
│   scm-plan      │                                                         │  scm-purchase    │
│                  │                                                         │                  │
│ 2.5M demand     │                                                         │ 694 POs          │
│   predictions   │                                                         │ 1,670 shipments  │
│ shop_id BIGINT   │                                                         │ supplier_id      │
│ goods_mid VCHAR  │                                                         │ po_number VCHAR  │
│ predict_date DT  │                                                         │ ship_date DT     │
└─────────────────┘                                                         └──────────────────┘
```

#### 3.3.1 Detailed Join Key Analysis — Supply Chain Domain

| Source Table    | Target Table    | Join Key(s)             | Source Type    | Target Type    | Match Quality |
|-----------------|-----------------|-------------------------|----------------|----------------|---------------|
| scm-shopstock  | ireplenishment  | shop_dept_id            | BIGINT         | BIGINT         | Clean         |
| scm-shopstock  | ireplenishment  | goods_mid               | VARCHAR        | VARCHAR        | Clean         |
| ireplenishment | scm-ordering    | (via order reference)   | --             | --             | Inferred      |
| scm-ordering   | scm-purchase    | (via purchase reference)| --             | --             | Inferred      |
| scm-plan       | scm-shopstock   | shop_id ↔ shop_dept_id  | BIGINT         | BIGINT         | **NAME VARIANT** |
| scm-plan       | scm-shopstock   | goods_mid               | VARCHAR        | VARCHAR        | Clean         |

**Assessment:** The SCM domain uses `shop_dept_id` (BIGINT) + `goods_mid` (VARCHAR) as a
composite key for inventory operations. This is a clean match between scm-shopstock and
ireplenishment. The `shop_id` vs. `shop_dept_id` naming variant between scm-plan and
scm-shopstock is a minor inconsistency — both reference the same store identifier.

### 3.4 Finance Domain

```
┌─────────────────┐  trade_serial_no  ┌──────────────────┐                   ┌──────────────────┐
│  ifiaccounting  │◀═══(≈trade_no)═══│  salespayment    │                   │     fitax        │
│                  │                   │                  │                   │                  │
│ bill_no VARCHAR  │  ⚠ NAME MISMATCH │ trade_no VARCHAR  │                   │ ⚠ ALL TABLES     │
│ trade_serial_no  │  (same concept)  │ order_id VARCHAR  │                   │   EMPTY (0 ROWS) │
│ order_serial     │                   │ amount DECIMAL   │                   │                  │
│ voucher_id       │                   │ payment_channel  │                   │ REGULATORY RISK  │
└─────────────────┘                   └──────────────────┘                   └──────────────────┘
        │                                                                            │
        │ reconcile_ref                                                              │ (no data flow)
        ▼                                                                            │
┌──────────────────┐                                                                 │
│iunifiedreconcile │◄────────────────────────────────────────────────────────────────┘
│                  │     (fitax should feed reconciliation but cannot — empty)
│ match_result     │
│ reconcile_status │
│ discrepancy_amt  │
└──────────────────┘
```

#### 3.4.1 Detailed Join Key Analysis — Finance Domain

| Source Table      | Target Table       | Join Key(s)                     | Match Quality      |
|-------------------|--------------------|----------------------------------|--------------------|
| ifiaccounting     | salespayment       | trade_serial_no ↔ trade_no       | **NAME MISMATCH**  |
| ifiaccounting     | salesorder         | order_serial ↔ order_no          | **NAME MISMATCH**  |
| ifiaccounting     | iunifiedreconcile  | bill_no                          | Clean              |
| fitax             | ifiaccounting      | (none — fitax is EMPTY)          | **NO DATA**        |
| fitax             | iunifiedreconcile  | (none — fitax is EMPTY)          | **NO DATA**        |

**3-way match pattern:** The finance reconciliation uses a 3-way match:
1. `bill_no` (ifiaccounting) ↔ billing record
2. `trade_serial_no` (ifiaccounting) ↔ `trade_no` (salespayment)
3. `order_serial` (ifiaccounting) ↔ `order_no` (salesorder)

This pattern works but relies on naming conventions that differ across systems, creating
maintenance burden and onboarding complexity.

### 3.5 HR / Operations Domain

```
┌─────────────────┐  employee_id      ┌──────────────────┐   shop_id        ┌──────────────────┐
│      iehr       │────(varchar)─────▶│ opempefficiency  │────(bigint)─────▶│     opshop       │
│                  │                   │                  │                   │                  │
│ 324 employees    │   ✅ CLEAN MATCH  │ 47.5K clock-ins  │   ✅ CLEAN MATCH  │ 11 active shops  │
│ employee_id VCHAR│                   │ 15.7K schedules  │                   │ shop_id BIGINT   │
│ name VARCHAR     │                   │ employee_id VCHAR│                   │ shop_name VCHAR  │
│ department VCHAR │                   │ shop_id BIGINT   │                   │ area VARCHAR     │
│ hire_date DATE   │                   │ clock_time DT    │                   │ status INT       │
└─────────────────┘                   └──────────────────┘                   └──────────────────┘
```

#### 3.5.1 Detailed Join Key Analysis — HR/Operations Domain

| Source Table     | Target Table      | Join Key(s)   | Source Type | Target Type | Match Quality |
|------------------|-------------------|---------------|-------------|-------------|---------------|
| iehr             | opempefficiency   | employee_id   | VARCHAR     | VARCHAR     | Clean         |
| opempefficiency  | opshop            | shop_id       | BIGINT      | BIGINT      | Clean         |

**Assessment:** Clean domain with consistent types. 324 employees across 11 stores
averages ~29 employees per store.

### 3.6 Cross-Domain Anchor Keys

These are the primary identifiers that enable cross-domain analytics and serve as the
foundation for any future data warehouse or feature store:

| Anchor Key          | Type(s)              | Used In                                          | Notes                              |
|---------------------|----------------------|--------------------------------------------------|------------------------------------|
| order_id / order_no | BIGINT / VARCHAR     | salesorder, salespayment, opproduction, iotplatform, ifiaccounting | **Type mismatch risk** |
| user_no             | VARCHAR              | salescrm, isalescdp, salesmarketing, isalesdatamarketing, salespayment, upush | Clean — best anchor key |
| shop_id / shop_dept_id | BIGINT            | opshop, salesorder, scm-shopstock, opempefficiency, scm-plan | Name variant only |
| goods_mid / spu_code | VARCHAR             | scmcommodity, scm-shopstock, ireplenishment, scm-plan | Product identifier |
| trade_no / trade_serial_no | VARCHAR       | salespayment, ifiaccounting                      | **Name mismatch**                  |
| employee_id         | VARCHAR              | iehr, opempefficiency                            | Clean                              |
| device_mark         | VARCHAR              | iotplatform, opproduction                        | IoT device identifier              |

**Recommended primary keys for data warehouse:**
```
DIMENSION        ANCHOR KEY    TYPE       SOURCE OF TRUTH
───────────      ──────────    ────       ───────────────
Customer         user_no       VARCHAR    salescrm
Order            order_id      BIGINT     salesorder (cast to BIGINT everywhere)
Store            shop_id       BIGINT     opshop
Product          goods_mid     VARCHAR    scmcommodity
Employee         employee_id   VARCHAR    iehr
Device           device_mark   VARCHAR    iotplatform
Transaction      trade_no      VARCHAR    salespayment
```

---

## 4. Data Flow Architecture

### 4.1 Order Lifecycle Flow

```
                                 ORDER LIFECYCLE FLOW
                                 ════════════════════

    ┌──────────┐      ┌────────────┐      ┌──────────────┐      ┌────────────┐
    │  Mobile  │─────▶│ salesorder │─────▶│ salespayment │─────▶│opproduction│
    │   App    │      │            │      │              │      │            │
    │          │      │ 487K done  │      │ 518K trades  │      │ 502K recs  │
    │ Order    │      │ status=90  │      │ payment_ok   │      │ 204s avg   │
    │ placed   │      │            │      │              │      │ make time  │
    └──────────┘      └─────┬──────┘      └──────┬───────┘      └─────┬──────┘
                            │                     │                     │
                            │                     │                     │
                            ▼                     ▼                     ▼
                     ┌────────────┐      ┌──────────────┐      ┌────────────┐
                     │  Kafka     │      │ ifiaccounting│      │iotplatform │
                     │  Events    │      │              │      │            │
                     │ order.*    │      │ 3-way match  │      │ 587K cups  │
                     │ topics     │      │ bill/trade/  │      │ device     │
                     │            │      │ order serial │      │ telemetry  │
                     └────────────┘      └──────────────┘      └────────────┘
```

**Volume Analysis:**

| Stage            | System         | Record Count | Delta from Previous | Notes                    |
|------------------|----------------|--------------|---------------------|--------------------------|
| Order Created    | salesorder     | 487,251      | --                  | Completed orders (status=90) |
| Payment Recorded | salespayment   | 518,427      | +31,176 (+6.4%)     | Includes refunds, partial payments |
| Production Done  | opproduction   | 502,130      | +14,879 from orders | Includes remake orders   |
| IoT Cup Events   | iotplatform    | 587,143      | +85,013 from prod   | Multiple events per drink (start, brew, complete, clean) |
| Accounting Entry | ifiaccounting  | --           | --                  | 3-way match reconciliation |

**Key observations:**
- The +6.4% delta between orders (487K) and payments (518K) reflects refunds, split
  payments, and payment method changes that generate additional trade records.
- The +85K delta between production (502K) and IoT events (587K) reflects multiple
  machine telemetry events per drink (machine start, brewing, dispensing, cleaning cycle).
- Average production time of 204 seconds (3.4 minutes) per drink is within industry norms
  for specialty coffee automated systems.

### 4.2 Marketing Lifecycle Flow

```
                              MARKETING LIFECYCLE FLOW
                              ════════════════════════

  ┌────────────┐      ┌──────────────┐      ┌────────────────┐      ┌────────────┐
  │  salescrm  │─────▶│  isalescdp   │─────▶│salesmarketing  │─────▶│   upush    │
  │            │      │              │      │                │      │            │
  │ 275K users │      │ 980K states  │      │ 514K activities│      │ 2.3M SMS   │
  │ profiles   │      │ user tags    │      │ 2.42M coupons  │      │ 8M push    │
  │ segments   │      │ segments     │      │ 6.4M A/B tests │      │ delivery   │
  └──────┬─────┘      └──────┬───────┘      └───────┬────────┘      └────────────┘
         │                    │                      │
         │ user_no            │ user_no              │ campaign_id
         ▼                    ▼                      ▼
  ┌────────────┐      ┌──────────────┐      ┌────────────────┐
  │  Member    │      │isalesdata    │      │  cdpactivity   │
  │  Marketing │      │  marketing   │      │                │
  │  (EMPTY)   │      │              │      │ Activity track │
  │  ⚠ NOT     │      │ behavioral   │      │ engagement     │
  │  LAUNCHED  │      │ targeting    │      │ metrics        │
  └────────────┘      └──────────────┘      └────────────────┘
```

**Volume Analysis:**

| Stage               | System             | Record Count  | Key Metric                     |
|----------------------|--------------------|---------------|--------------------------------|
| User Registration    | salescrm           | 275,000       | Base user population           |
| User State Tracking  | isalescdp          | 980,000       | 3.56 states per user avg       |
| Campaign Activities  | salesmarketing     | 514,000       | Active campaign instances       |
| Coupon Issuance      | salesmarketing     | 2,424,506     | 8.82 coupons per user avg      |
| Expired Coupons      | salesmarketing     | 37,300,000    | **China migration bloat**      |
| A/B Tests            | salesmarketing     | 6,386,203     | 23.2 test exposures per user   |
| SMS Delivery         | upush              | 2,300,000     | 8.36 SMS per user avg          |
| Push Notifications   | upush              | 8,000,000+    | 29.1 pushes per user avg       |
| Member Marketing     | isalesmembermarketing | **0**      | Loyalty program NOT launched   |

**Key observations:**
- 37.3M expired coupons represent migration bloat from China's platform. These records
  consume storage and slow queries but have no US business relevance.
- The loyalty/membership program (isalesmembermarketing) has not been launched. All member
  marketing tables are empty. This is a significant gap for customer retention.
- 6.4M A/B test records indicate a sophisticated experimentation culture inherited from
  Luckin China's marketing engine.

### 4.3 Supply Chain Lifecycle Flow

```
                           SUPPLY CHAIN LIFECYCLE FLOW
                           ═══════════════════════════

  ┌────────────┐      ┌──────────────┐      ┌────────────────┐      ┌────────────┐
  │  scm-plan  │─────▶│ireplenishment│─────▶│ scm-shopstock  │─────▶│scm-ordering│
  │            │      │              │      │                │      │            │
  │ 2.5M demand│      │ 124K order   │      │ 9.1M stock     │      │ store-level│
  │ predictions│      │ predictions  │      │ changes        │      │ orders     │
  │ AI/ML      │      │ AI-generated │      │ real-time inv  │      │ to vendors │
  └────────────┘      └──────────────┘      └───────┬────────┘      └─────┬──────┘
                                                     │                     │
                                                     │ stock alerts        │ purchase_ref
                                                     ▼                     ▼
                                             ┌────────────────┐    ┌────────────┐
                                             │  scm-commodity │    │scm-purchase│
                                             │                │    │            │
                                             │ product master │    │ 694 POs    │
                                             │ SKU catalog    │    │ 1,670 ships│
                                             │ category tree  │    │ supplier   │
                                             └────────────────┘    │ tracking   │
                                                                   └────────────┘
```

**Volume Analysis:**

| Stage                | System          | Record Count  | Key Metric                         |
|----------------------|-----------------|---------------|------------------------------------|
| Demand Forecasting   | scm-plan        | 2,517,238     | AI-generated demand predictions    |
| Order Prediction     | ireplenishment  | 124,000       | AI-recommended reorder quantities  |
| Inventory Tracking   | scm-shopstock   | 9,136,482     | Highest-volume table in system     |
| Purchase Orders      | scm-purchase    | 694           | Vendor POs generated               |
| Shipment Tracking    | scm-purchase    | 1,670         | 2.41 shipments per PO avg          |

**Key observations:**
- The demand forecasting engine (2.5M predictions) is the most mature AI/ML system in
  the LKUS stack. It feeds directly into the automated replenishment engine (124K order
  predictions), creating a closed-loop AI-driven supply chain.
- 9.1M stock change records indicate real-time inventory tracking at the item-store-day
  level — essential input for any demand forecasting improvement.
- The ratio of 2.5M predictions to 124K order recommendations suggests a ~20:1 filtering
  ratio — the system evaluates many scenarios before recommending actions.

### 4.4 Finance Reconciliation Flow

```
                        FINANCE RECONCILIATION FLOW
                        ═══════════════════════════

  ┌────────────┐      ┌──────────────┐      ┌────────────────┐
  │ salesorder │─────▶│ salespayment │─────▶│ ifiaccounting  │
  │            │      │              │      │                │
  │ order_no   │      │ trade_no     │      │ 3-WAY MATCH:   │
  │ amount     │      │ amount       │      │ bill_no        │
  │            │      │ channel      │      │ trade_serial_no│
  └────────────┘      └──────────────┘      │ order_serial   │
                                             └───────┬────────┘
                                                     │
                              ┌───────────────────────┼───────────────────────┐
                              │                       │                       │
                              ▼                       ▼                       ▼
                     ┌────────────────┐      ┌────────────────┐      ┌────────────┐
                     │     fitax      │      │ iunifiedreconcile│    │fichargecontrol│
                     │                │      │                │      │            │
                     │ ⚠⚠⚠ EMPTY ⚠⚠⚠ │      │ reconciliation │      │ charge     │
                     │ 0 ROWS         │      │ matching       │      │ rules      │
                     │ ALL TABLES     │      │ discrepancies  │      │ fee calc   │
                     │                │      │                │      │            │
                     │ US TAX NOT     │      └────────────────┘      └────────────┘
                     │ IMPLEMENTED    │
                     └────────────────┘
```

**Critical gap:** The `fitax` database is completely empty (0 rows across all tables).
This means:
1. US sales tax calculation is NOT happening at the database level
2. Tax records are not being stored for audit/compliance purposes
3. The reconciliation flow cannot validate tax amounts
4. This represents a regulatory compliance risk for operations across New York State,
   New York City, and potentially other jurisdictions

The 3-way match pattern in ifiaccounting (bill_no / trade_serial_no / order_serial)
provides the core reconciliation capability, but the tax gap means the financial picture
is incomplete.

---

## 5. Data Quality Assessment

### 5.1 Critical Issues

#### CRIT-01: fi_tax Database Completely Empty

| Attribute        | Detail                                               |
|------------------|------------------------------------------------------|
| Severity         | **CRITICAL**                                         |
| System           | aws-luckyus-fitax-rw                                 |
| Finding          | All tables contain 0 rows                            |
| Impact           | US sales tax compliance not implemented at DB level  |
| Risk             | Regulatory — NY State/City tax audit exposure        |
| Recommendation   | Immediate assessment of tax handling mechanism       |
| Data Available   | salespayment has payment amounts; order amounts exist |

US sales tax for New York State (4%) + New York City (4.5%) = 8.5% combined rate. With
$2.19M cumulative revenue, the potential tax liability is approximately $186K. If tax
is being calculated elsewhere (payment processor, external system), the lack of database
records still creates audit trail gaps.

#### CRIT-02: Loyalty/Membership Tables Empty

| Attribute        | Detail                                               |
|------------------|------------------------------------------------------|
| Severity         | **CRITICAL** (business impact)                       |
| System           | aws-luckyus-isalesmembermarketing-rw                 |
| Finding          | All loyalty/membership tables contain 0 rows         |
| Impact           | No loyalty program operational for US customers      |
| Risk             | Customer retention — 50.6% of users already lapsed   |
| Recommendation   | Prioritize loyalty program launch for retention      |

With 50.6% of users lapsed (90+ days inactive), the absence of a loyalty program is a
critical gap. Luckin China's loyalty program is a core driver of repeat purchases.

### 5.2 High-Severity Issues

#### HIGH-01: order_id Type Mismatch Across Systems

| Attribute        | Detail                                               |
|------------------|------------------------------------------------------|
| Severity         | **HIGH**                                             |
| Systems          | salesorder (BIGINT), salespayment (VARCHAR), iotplatform (VARCHAR) |
| Finding          | order_id stored as different types across systems    |
| Impact           | Index bypass, implicit casting, query plan instability |
| Recommendation   | Standardize on BIGINT; add explicit CAST in queries  |

The order_id type mismatch affects the most critical data flow in the system (order
lifecycle). While MySQL handles implicit casting, this creates performance risks under
load and makes cross-system analytics fragile.

#### HIGH-02: 37.3M Expired Coupon Records (China Migration Bloat)

| Attribute        | Detail                                               |
|------------------|------------------------------------------------------|
| Severity         | **HIGH**                                             |
| System           | aws-luckyus-salesmarketing-rw                        |
| Finding          | 37,300,000 expired coupon records in database        |
| Impact           | Storage waste, slow queries, misleading analytics    |
| Recommendation   | Archive to S3; purge from active database            |

These records likely migrated from Luckin China's coupon system and have no relevance
to US operations. They represent ~94% of all coupon records and should be archived.

#### HIGH-03: NZD-Denominated Orders Contaminating USD Analytics

| Attribute        | Detail                                               |
|------------------|------------------------------------------------------|
| Severity         | **HIGH**                                             |
| System           | salesorder, salespayment                             |
| Finding          | 21,245 orders denominated in NZD (New Zealand Dollar)|
| Impact           | Revenue analytics inflated/distorted by non-USD data |
| Context          | Cook Islands test orders from system testing phase   |
| Recommendation   | Flag with test_order indicator; exclude from reports |

These 21,245 Cook Islands test orders contaminate any USD-based revenue analysis. They
should be marked with a test flag and excluded from all business intelligence reporting.

### 5.3 Medium-Severity Issues

#### MED-01: luckyus-shopsale Redis 2.9% Hit Rate

| Attribute        | Detail                                               |
|------------------|------------------------------------------------------|
| Severity         | **MEDIUM**                                           |
| System           | luckyus-shopsale ElastiCache cluster                 |
| Finding          | 2.9% cache hit rate (47.3M misses vs. 1.4M hits)    |
| Impact           | Cache not functioning; all queries hitting MySQL     |
| Recommendation   | Investigate cache key patterns; fix or decommission  |

A 2.9% hit rate means 97.1% of cache lookups fall through to the database. This cluster
is consuming ElastiCache resources without providing caching benefit. Either the cache
warming strategy is broken or the cache key patterns do not match query patterns.

#### MED-02: 2.69M Redis Keys with No TTL in isales-market

| Attribute        | Detail                                               |
|------------------|------------------------------------------------------|
| Severity         | **MEDIUM**                                           |
| System           | luckyus-isales-market ElastiCache cluster            |
| Finding          | 2,690,000 keys have no TTL set (will never expire)   |
| Impact           | Unbounded memory growth; eventual OOM or eviction    |
| Current Memory   | 1.28 GB (largest cluster in fleet)                   |
| Recommendation   | Audit key patterns; set appropriate TTLs             |

Without TTL policies, these keys will accumulate indefinitely. The cluster is already the
largest in the fleet at 1.28 GB. At current growth rates, a node upgrade will be needed
within 6-8 months.

### 5.4 Low-Severity Issues

#### LOW-01: Student 40% Off Coupon Broken (0% Redemption)

| Attribute        | Detail                                               |
|------------------|------------------------------------------------------|
| Severity         | **LOW** (limited impact)                             |
| System           | salesmarketing                                       |
| Finding          | 0% redemption rate on 57,471 student coupon issuances|
| Impact           | Marketing budget waste; poor student segment engagement |
| Recommendation   | Investigate redemption flow; check coupon validation |

57,471 student discount coupons issued with zero redemptions indicates a broken coupon
validation flow, incorrect coupon configuration, or a targeting issue where non-students
received student coupons they cannot redeem.

### 5.5 Data Freshness Summary

| System              | Last Updated   | Freshness  | Notes                              |
|---------------------|----------------|------------|-------------------------------------|
| salesorder          | Feb 2026       | CURRENT    | Active order flow                   |
| salespayment        | Feb 2026       | CURRENT    | Active payment processing           |
| salescrm            | Feb 2026       | CURRENT    | User registrations ongoing          |
| isalescdp           | Feb 2026       | CURRENT    | CDP actively updating user states   |
| salesmarketing      | Feb 2026       | CURRENT    | Active campaigns running            |
| opproduction        | Feb 2026       | CURRENT    | Active production tracking          |
| opempefficiency     | Feb 2026       | CURRENT    | Daily clock-ins recorded            |
| scm-shopstock       | Feb 2026       | CURRENT    | Real-time inventory updates         |
| scm-plan            | Feb 2026       | CURRENT    | Daily demand predictions generated  |
| ireplenishment      | Feb 2026       | CURRENT    | AI predictions running              |
| scm-purchase        | Feb 2026       | CURRENT    | Active procurement                  |
| ifiaccounting       | Feb 2026       | CURRENT    | Active reconciliation               |
| fitax               | --             | **EMPTY**  | No data ever written                |
| isalesmembermarketing | --           | **EMPTY**  | Loyalty not launched                |
| icyberdata          | Sep 2025       | STALE      | Archival tables (expected)          |
| iotplatform         | Feb 2026       | CURRENT    | Active IoT telemetry (43% online)   |
| upush               | Feb 2026       | CURRENT    | Active push/SMS delivery            |
| iehr                | Feb 2026       | CURRENT    | Active HR management                |

**Summary:** 15 of 18 sampled systems are actively updated (Jan-Feb 2026). 2 are
intentionally empty (fitax, isalesmembermarketing). 1 (icyberdata) contains archival
data from Sep 2025, which is expected for ETL/archival workloads.

---

## 6. Monitoring Coverage Map

### 6.1 Grafana Dashboards & Datasources

#### 6.1.1 Dashboard Inventory

| # | Dashboard Name              | Type              | Panels | Primary Focus            |
|---|-----------------------------|-------------------|--------|--------------------------|
| 1 | DBA MySQL Monitor 01        | DBA Monitoring    | 12+    | MySQL instance metrics   |
| 2 | DBA MySQL Monitor 02        | DBA Monitoring    | 12+    | MySQL instance metrics   |
| 3 | DBA MySQL Monitor 03        | DBA Monitoring    | 10+    | MySQL instance metrics   |
| 4 | DBA MySQL Monitor 04        | DBA Monitoring    | 10+    | MySQL instance metrics   |
| 5 | DBA MySQL Monitor 05        | DBA Monitoring    | 10+    | MySQL instance metrics   |
| 6 | DBA MySQL Monitor 06        | DBA Monitoring    | 10+    | MySQL instance metrics   |
| 7 | DBA MySQL Monitor 07        | DBA Monitoring    | 10+    | MySQL instance metrics   |
| 8 | DBA MySQL Monitor 08        | DBA Monitoring    | 10+    | MySQL instance metrics   |
| 9 | DBA MySQL Monitor 09        | DBA Monitoring    | 10+    | MySQL instance metrics   |
| 10| DBA MySQL Monitor 10        | DBA Monitoring    | 10+    | MySQL instance metrics   |
| 11| MySQL Monitor Overview      | MySQL Monitoring  | 8+     | Fleet-level MySQL stats  |
| 12| MySQL Slow Query Analysis   | MySQL Monitoring  | 6+     | Slow query tracking      |
| 13| Campaign Performance        | Business          | 8+     | Marketing campaign KPIs  |
| 14| Root Dashboard 01           | Root-level        | --     | Top-level navigation     |
| 15| Root Dashboard 02           | Root-level        | --     | Top-level navigation     |
| 16| Root Dashboard 03           | Root-level        | --     | Top-level navigation     |
| 17| Root Dashboard 04           | Root-level        | --     | Top-level navigation     |

**Total: 17 dashboards** (10 DBA monitoring, 2 MySQL monitor, 1 campaign, 4 root-level)

#### 6.1.2 Datasource Configuration

| # | Datasource Name         | UID              | Type          | Status     | Purpose               |
|---|-------------------------|------------------|---------------|------------|------------------------|
| 1 | UMBQuerier-Luckin       | df8o21agxtkw0d   | Prometheus    | Connected  | Unified metrics (default) |
| 2 | prometheus              | ff7hkeec6c9a8e   | Prometheus    | Connected  | General metrics        |
| 3 | prometheus_redis        | ff6p0gjt24phce   | Prometheus    | Connected  | Redis-specific metrics |
| 4 | MySQL-Ldas              | ef5ay9lchfg1sa   | MySQL         | Connected  | LDAS data queries      |
| 5 | MySQL-luckyhealth       | af8o704xu3280a   | MySQL         | Connected  | Health monitoring      |
| 6 | MySQL-iriskcontrol      | af8p2vx4nhp1ce   | MySQL         | Connected  | Risk control data      |
| 7 | elasticsearch           | ff7ehok3sf56oa   | Elasticsearch | Connected  | Log analytics          |

**Total: 7 datasources** (3 Prometheus, 3 MySQL, 1 Elasticsearch)

### 6.2 Alert Rules

| # | Alert Rule Name            | Group                  | State  | Condition              |
|---|----------------------------|------------------------|--------|------------------------|
| 1 | MySQL Slow Query Count     | slow-sql-governance    | ERROR  | Slow queries > threshold |
| 2 | MySQL Slow Query Duration  | slow-sql-governance    | ERROR  | Query duration > threshold |
| 3 | MySQL Slow Query Pattern   | slow-sql-governance    | ERROR  | Repeated slow patterns  |

**CRITICAL: All 3 alert rules have health=error status. None are functioning.**

The entire alerting infrastructure consists of 3 rules, all in the same group
(slow-sql-governance), all targeting MySQL slow queries, and all in error state. This
means LKUS has effectively **zero operational alerting**.

No alerts exist for:
- Database availability (any engine)
- Replication lag
- Connection pool exhaustion
- Disk space
- CPU/memory utilization
- Application errors
- Business metric anomalies
- Security events

### 6.3 Prometheus

#### 6.3.1 Scrape Configuration

| Metric                  | Value                                    |
|-------------------------|------------------------------------------|
| Scrape Jobs             | 1 (aws-redis-job)                        |
| Total Targets           | 76                                       |
| Targets UP              | 75                                       |
| Targets DOWN            | 1 (luckyus-iopenlinkeradmin)             |
| Down Reason             | Trailing space in hostname               |
| Metric Families         | 155 (Redis-specific only)                |
| Scrape Interval         | 60s (estimated)                          |

#### 6.3.2 Prometheus Metric Coverage

```
METRIC CATEGORY                     COUNT    EXAMPLES
──────────────────────────────────  ──────   ──────────────────────────────
Redis Connection Metrics            ~15      redis_connected_clients, redis_blocked_clients
Redis Memory Metrics                ~20      redis_memory_used_bytes, redis_memory_rss_bytes
Redis Keyspace Metrics              ~10      redis_db_keys, redis_db_expires
Redis Command Metrics               ~25      redis_commands_total, redis_commands_duration
Redis Replication Metrics           ~15      redis_connected_slaves, redis_replication_offset
Redis Persistence Metrics           ~10      redis_rdb_last_save_time, redis_aof_rewrite
Redis Network Metrics               ~15      redis_net_input_bytes_total, redis_net_output_bytes
Redis CPU Metrics                   ~10      redis_cpu_sys_seconds_total, redis_cpu_user
Redis Eviction/Expiry Metrics       ~10      redis_evicted_keys_total, redis_expired_keys
Redis Cluster Metrics               ~10      redis_cluster_enabled, redis_cluster_slots
Exporter Metrics                    ~15      redis_exporter_build_info, scrape_duration
──────────────────────────────────  ──────   ──────────────────────────────
TOTAL                               ~155
```

**Key limitation:** Prometheus monitoring covers ONLY Redis metrics. There are no scrape
jobs for:
- EC2 instance metrics (node_exporter)
- MySQL/RDS metrics (mysqld_exporter)
- Kafka/MSK metrics (jmx_exporter)
- Application metrics (custom exporters)
- Kubernetes metrics (kube-state-metrics)
- OpenSearch metrics
- DocumentDB metrics

#### 6.3.3 Down Target Detail

```
Target: luckyus-iopenlinkeradmin
Status: DOWN
Error:  "connection refused"
Cause:  Trailing whitespace in hostname configuration
Fix:    Remove trailing space from target hostname in Prometheus config
Impact: Open Linker Admin Redis cluster unmonitored
```

### 6.4 CloudWatch

#### 6.4.1 Log Group Inventory

| Category                    | Count | Key Groups                                        |
|-----------------------------|-------|---------------------------------------------------|
| RDS Slow Query Logs         | 51    | One per RDS instance (slowquery suffix)           |
| Internet Monitor            | 20    | 5 CloudFront distributions x 4 geo dimensions    |
| Lambda Function Logs        | 17    | Image transformation, monitoring, VeloDB          |
| API Gateway Logs            | 3     | Prod, test, YangTao execution logs                |
| Other                       | 4     | Redis slow logs, DNS Web, SMS, image builder      |
| **TOTAL**                   | **95**|                                                   |

#### 6.4.2 CloudWatch Alarms

| Metric            | Value   |
|-------------------|---------|
| Active Alarms     | **0**   |
| Alarm History     | None    |
| Configured Alarms | 0       |

**LKUS has zero CloudWatch alarms configured.** No automated alerting exists for any
AWS service, including RDS, EC2, ElastiCache, OpenSearch, MSK, or any other managed service.

#### 6.4.3 Top Slow Query Log Groups by Size

| # | Log Group                                                    | Database         | Stored Size | Retention  |
|---|--------------------------------------------------------------|------------------|-------------|------------|
| 1 | /aws/rds/instance/aws-luckyus-icyberdata-rw/slowquery        | CyberData        | 3.4 GB      | No policy  |
| 2 | /aws/rds/instance/aws-luckyus-ldas01-rw/slowquery            | LDAS01           | 1.4 GB      | No policy  |
| 3 | /aws/rds/instance/aws-luckyus-salesmarketing-rw/slowquery    | Sales Marketing  | 668 MB      | No policy  |
| 4 | /aws/rds/instance/aws-luckyus-salespayment-rw/slowquery      | Sales Payment    | 275 MB      | No policy  |
| 5 | /aws/rds/instance/aws-luckyus-framework01-rw/slowquery       | Framework01      | 263 MB      | No policy  |
| 6 | /aws/rds/instance/aws-luckyus-framework02-rw/slowquery       | Framework02      | 241 MB      | No policy  |
| 7 | /aws/rds/instance/aws-luckyus-ipermission-rw/slowquery       | Permission       | 206 MB      | No policy  |
| 8 | /aws/rds/instance/recovery-dbatest/slowquery                 | DBA Test         | 195 MB      | No policy  |
| 9 | /aws/rds/instance/aws-luckyus-iluckyhealth-rw/slowquery      | Lucky Health     | 193 MB      | No policy  |
| 10| /aws/rds/instance/aws-luckyus-opqualitycontrol-rw/slowquery  | Quality Control  | 153 MB      | No policy  |
|   | + 41 additional RDS slow query log groups                    |                  | Various     | No policy  |

**Total estimated slow query log storage:** ~8-10 GB across 51 log groups, all with no
retention policy. At CloudWatch log storage pricing (~$0.03/GB/month), this accumulates
indefinitely. Setting a 30-day retention would reduce stored volume by 80-90%.

#### 6.4.4 Log Retention Policy Analysis

| Retention Policy       | Count  | % of Total |
|------------------------|--------|------------|
| No retention set       | 90+    | ~95%       |
| 30 days                | ~3     | ~3%        |
| 90 days                | ~2     | ~2%        |

**Over 90 log groups have NO retention policy**, meaning logs are stored indefinitely.
This contributes to the $3,667/month CloudWatch cost (7.4% of total spend) and the
+23.9% month-over-month CloudWatch cost growth.

**Immediate action:** Setting 30-day retention on RDS slow query logs alone (51 groups,
many with GB of stored data) could save $500-1,000/month.

### 6.5 Monitoring Gaps

The following is a comprehensive inventory of monitoring gaps, organized by criticality:

```
GAP CATEGORY                 CURRENT STATE                RISK LEVEL    BUSINESS IMPACT
─────────────────────────    ─────────────────────────    ──────────    ────────────────────
EC2 Instance Monitoring      No metrics collected          HIGH          78% idle fleet undetected
RDS Performance Monitoring   Slow query logs only          HIGH          No connection pool, IOPS,
                                                                        replication lag visibility
OpenSearch Health            No monitoring                 HIGH          RED status incident (2/12)
                                                                        detected only by users
Kafka/MSK Broker Monitoring  No metrics collected          MEDIUM        Topic lag, broker health
                                                                        invisible
DocumentDB Monitoring        No metrics collected          MEDIUM        $843/mo service unmonitored
EKS Cluster Monitoring       No metrics collected          HIGH          20 nodes ($12.7K/mo)
                                                                        unmonitored
Application-Level Metrics    No APM, no custom metrics     HIGH          Error rates, latency,
                                                                        throughput invisible
Business KPI Monitoring      1 campaign dashboard only     CRITICAL      Revenue, orders, user
                                                                        engagement not tracked
                                                                        in real-time
AI/ML Model Performance      No model monitoring           MEDIUM        2.5M predictions running
                                                                        with no drift detection
Security Monitoring          GuardDuty only (investigated  MEDIUM        No SIEM, no anomaly
                             2/11 for EKS finding)                       detection beyond AWS defaults
Alerting Infrastructure      3 rules, ALL broken           CRITICAL      Zero operational alerting
                                                                        capability
Redis Monitoring             Prometheus metrics only;      LOW           75 of 76 monitored
                             no alerting configured                      (relatively good coverage)
─────────────────────────    ─────────────────────────    ──────────    ────────────────────
```

#### 6.5.1 Monitoring Coverage Matrix

```
SYSTEM                 METRICS   LOGS   ALERTS   DASHBOARDS   COVERAGE
─────────────────────  ────────  ─────  ───────  ──────────   ────────
MySQL (62 servers)     No        Yes*   ERROR    10 DBA       PARTIAL
Redis (78 clusters)    Yes       No     No       No           PARTIAL
PostgreSQL (3)         No        No     No       No           NONE
EC2 (233 instances)    No        No     No       No           NONE
EKS (20 nodes)         No        No     No       No           NONE
OpenSearch (2 domains) No        No     No       No           NONE
MSK/Kafka (308 topics) No        No     No       No           NONE
DocumentDB             No        No     No       No           NONE
ElastiCache (mgmt)     No        No     No       No           NONE
Application Layer      No        No     No       1 campaign   MINIMAL
Business KPIs          No        No     No       No           NONE
AI/ML Models           No        No     No       No           NONE
Security Events        No**      No     No       No           MINIMAL

* MySQL: Slow query logs only (no performance metrics)
** Security: AWS GuardDuty enabled but not connected to monitoring stack
```

#### 6.5.2 Estimated Monitoring Debt

| Dimension               | Current | Recommended Minimum | Gap     |
|-------------------------|---------|---------------------|---------|
| Prometheus scrape jobs  | 1       | 8-12                | 7-11    |
| Active alert rules      | 0*      | 50-100              | 50-100  |
| Dashboards (operational)| 12      | 30-40               | 18-28   |
| CloudWatch alarms       | 0       | 25-50               | 25-50   |
| Metrics per service     | 155     | 2,000+              | 1,845+  |
| On-call rotation        | None    | 24/7                | Full    |

\* 3 alert rules exist but all are in ERROR state (non-functional)

The monitoring debt is severe. Building a comprehensive monitoring stack is a prerequisite
for both operational stability and AI/ML deployment (model monitoring requires the same
infrastructure).

**Summary:** Monitoring covers approximately 5-10% of the infrastructure stack. The only
well-monitored system category is Redis (via Prometheus), but even Redis has no alerting
rules configured. The 3 existing alert rules (MySQL slow query) are all in error state
and non-functional.

---

## 7. Cost Breakdown

### 7.1 Monthly Summary (January 2026)

| Metric                      | Value           |
|-----------------------------|-----------------|
| Total Monthly Spend         | $49,644.92      |
| Annualized Run Rate         | $595,739        |
| Active Stores               | 11              |
| Per-Store Monthly Cost      | $4,513          |
| RI-Covered Spend            | $24,936 (50.2%) |
| On-Demand Spend             | $24,709 (49.8%) |
| Savings Plans Coverage      | $0 (0%)         |

### 7.2 Service-Level Detail

| Rank | Service          | Monthly Cost | % of Total | MoM Change | Notes                    |
|------|------------------|--------------|------------|------------|--------------------------|
| 1    | EC2              | $26,693.06   | 53.8%      | +2.1%      | 233 instances, 78% idle  |
| 2    | RDS              | $5,527.28    | 11.1%      | +1.8%      | 62 MySQL + 3 PostgreSQL  |
| 3    | CloudWatch       | $3,667.00    | 7.4%       | **+23.9%** | No retention policies    |
| 4    | EC2-Other        | $3,097.00    | 6.2%       | +1.2%      | EBS, EIPs, data transfer |
| 5    | OpenSearch       | $2,647.00    | 5.3%       | +0.5%      | 2 domains, 22% RI        |
| 6    | ElastiCache      | $2,313.84    | 4.7%       | +0.8%      | 78 clusters, 6.6% RI     |
| 7    | MSK (Kafka)      | $2,306.00    | 4.6%       | +0.3%      | 308 topics               |
|      | **Subtotal Top 7** | **$46,251** | **93.4%** |            |                          |
| 8    | DocumentDB       | $843.00      | 1.7%       | Stable     | MongoDB-compatible       |
| 9    | EMR              | $565.00      | 1.1%       | Stable     | Batch processing         |
| 10   | S3               | $348.00      | 0.7%       | **+43.9%** | Fastest growing service  |
| 11   | EKS (ctrl)       | $149.00      | 0.3%       | Stable     | Control plane only       |
| 12   | Other            | $1,488.00    | 3.0%       | Mixed      | Lambda, API GW, WAF, etc |
|      | **TOTAL**        | **$49,644.92** | **100%** |            |                          |

### 7.3 RDS Cost Breakdown

| Component          | Monthly Cost | % of RDS | Instance Details                     |
|--------------------|--------------|----------|--------------------------------------|
| db.r5.xlarge       | $1,488       | 26.9%    | 1 Multi-AZ instance                 |
| db.t4g.medium      | $1,440       | 26.1%    | Multiple instances                   |
| db.t4g.micro       | $900         | 16.3%    | Multiple instances                   |
| GP3 Storage        | $488         | 8.8%     | Across all RDS instances             |
| db.t4g.xlarge      | $385         | 7.0%     | 1-2 instances                        |
| db.t4g.large       | $384         | 6.9%     | 1-2 instances                        |
| db.m5.large        | $265         | 4.8%     | 1-2 instances                        |
| Other (backup, IO) | $177         | 3.2%     | Automated backups, provisioned IOPS  |
| **TOTAL RDS**      | **$5,527**   | **100%** |                                      |

**Key issue:** RDS RI coverage is only 1.3% ($69 RI vs. $5,458 On-Demand). Most RDS
Reserved Instances have expired. Renewing RIs for the top 3 instance classes could save
approximately $1,500-2,000/month.

### 7.4 3-Month Trend

| Month    | Total Spend | MoM Change | CloudWatch | S3     | EC2      |
|----------|-------------|------------|------------|--------|----------|
| Nov 2025 | $47,526     | --         | $2,960     | $242   | $26,141  |
| Dec 2025 | $48,418     | +1.9%      | $3,284     | $298   | $26,352  |
| Jan 2026 | $49,645     | +2.5%      | $3,667     | $348   | $26,693  |
| **3-mo** | --          | **+4.5%**  | **+23.9%** | **+43.9%** | **+2.1%** |

**Trend analysis:**
- Overall spend growing at +4.5% over 3 months (~18% annualized if sustained)
- CloudWatch is the fastest-growing major cost center (+23.9%) due to indefinite log
  retention — this is an easy fix
- S3 is the fastest-growing percentage (+43.9%) but from a small base ($348)
- EC2 growth (+2.1%) is modest and likely reflects minor fleet changes

**Projected 12-month spend at current trend:** ~$585K-$610K (assuming growth moderates)

### 7.5 Per-Store Economics

| Metric                          | Value         |
|---------------------------------|---------------|
| Active Stores                   | 11            |
| Total Monthly Infrastructure    | $49,645       |
| **Per-Store Monthly Cost**      | **$4,513**    |
| Per-Store Annual Cost           | $54,158       |
| Avg Monthly Revenue per Store   | ~$19,900      |
| Infrastructure as % of Revenue  | ~22.7%        |

**Benchmark comparison:**
- Typical QSR (Quick Service Restaurant) technology cost: 3-5% of revenue
- LKUS at 22.7% is 4-7x higher than industry benchmark
- However, LKUS infrastructure was designed for 10,000+ stores (China-scale architecture)
- Per-store cost will decrease dramatically with expansion (target: <5% at 50+ stores)

### 7.6 RI / Savings Plans Coverage

| Service      | Total Spend | RI Covered  | On-Demand   | Coverage % | Status           |
|--------------|-------------|-------------|-------------|------------|------------------|
| EC2          | $26,693     | $24,131     | $2,562      | 90.4%      | Good             |
| RDS          | $5,527      | $69         | $5,458      | 1.3%       | **CRITICAL**     |
| ElastiCache  | $2,314      | $152        | $2,162      | 6.6%       | **CRITICAL**     |
| OpenSearch   | $2,647      | $583        | $2,064      | 22.0%      | Poor             |

#### EC2 RI Detail (Active)

| Instance Type | RI Count | Monthly RI Cost | Expiration   |
|---------------|----------|-----------------|--------------|
| c6i.large     | 129      | $5,295          | 2026-08-28   |
| c6i.xlarge    | 26       | $2,134          | 2026-08-28   |
| c6i.xlarge    | 3        | $649 (Windows)  | 2026-08-28   |
| c6i.2xlarge   | 7        | $1,149          | 2026-08-28   |
| c6i.4xlarge   | 1        | $328            | 2026-08-28   |
| c5.large      | 1        | $39             | 2026-08-28   |
| m6i.4xlarge   | 7        | $2,596          | 2026-08-27   |
| m6i.8xlarge   | 13       | $9,642          | 2026-08-27   |
| m6a.large     | 3        | $125            | 2026-08-27   |
| m6a.xlarge    | 2        | $167            | 2026-08-27   |
| m5.xlarge     | 5        | $442            | 2026-08-27   |
| m4.large      | 1        | $45             | 2026-08-28   |
| m4.xlarge     | 1        | $90             | 2026-08-27   |
| r6i.2xlarge   | 2        | $487            | 2026-08-28   |
| r6i.4xlarge   | 1        | $487            | 2026-08-27   |

**WARNING:** All EC2 RIs expire August 2026 (6 months). Planning for renewal (or
transition to Savings Plans) should begin by June 2026.

#### RDS RI Detail (Critical)

| Instance Class  | RI Count | Status   | Monthly RI Cost | Expiration   |
|-----------------|----------|----------|-----------------|--------------|
| db.t4g.medium   | 1        | Active   | $68             | 2026-08-27   |
| db.r5.xlarge    | --       | **EXPIRED** | $0           | --           |
| db.t4g.medium   | --       | **EXPIRED** | $0           | --           |
| db.t4g.micro    | --       | **EXPIRED** | $0           | --           |

Only 1 active RDS RI remains. Immediate RI purchases for db.r5.xlarge, db.t4g.medium,
and db.t4g.micro would save approximately $1,500-2,000/month.

### 7.7 Optimization Opportunities

| # | Opportunity                     | Monthly Savings | Annual Savings | Effort   | Risk   |
|---|---------------------------------|-----------------|----------------|----------|--------|
| 1 | EC2 rightsizing (idle → smaller) | $14,676        | $176,107       | High     | Medium |
| 2 | RDS RI renewal                  | $1,500-2,000    | $18,000-24,000 | Low      | Low    |
| 3 | ElastiCache RI purchase         | $800-1,000      | $9,600-12,000  | Low      | Low    |
| 4 | OpenSearch RI renewal           | $600-800        | $7,200-9,600   | Low      | Low    |
| 5 | CloudWatch log retention        | $500-1,000      | $6,000-12,000  | Low      | Low    |
| 6 | GP2 → GP3 EBS migration         | $18             | $219           | Low      | Low    |
| 7 | EKS node rightsizing            | $6,000-8,000    | $72,000-96,000 | High     | High   |
|   | **TOTAL POTENTIAL**             | **$24,094-27,494** | **$289,126-329,926** |   |        |

**Quick wins (Low effort, Low risk):** Items 2-6 can save $3,418-4,818/month ($41K-58K/year)
with minimal risk and can be executed within 1-2 weeks.

**Strategic wins (High effort):** EC2 rightsizing (#1) and EKS node rightsizing (#7) require
workload analysis but represent $20,676-22,676/month ($248K-272K/year) in potential savings.

---

## 8. Appendix: Complete Server Catalog

### A.1 All 62 MySQL Servers by Domain

#### Sales Domain (12 servers)

| # | Connection Name                          | RDS Instance (est.)            | Domain    |
|---|------------------------------------------|--------------------------------|-----------|
| 1 | aws-luckyus-salesorder-rw                | aws-luckyus-salesorder         | Sales     |
| 2 | aws-luckyus-salespayment-rw              | aws-luckyus-salespayment       | Sales     |
| 3 | aws-luckyus-salescrm-rw                  | aws-luckyus-salescrm           | Sales     |
| 4 | aws-luckyus-salesmarketing-rw            | aws-luckyus-salesmarketing     | Sales     |
| 5 | aws-luckyus-isalescdp-rw                 | aws-luckyus-isalescdp          | Sales     |
| 6 | aws-luckyus-isalesdatamarketing-rw       | aws-luckyus-isalesdatamarketing| Sales     |
| 7 | aws-luckyus-isalesmembermarketing-rw     | aws-luckyus-isalesmembermarketing | Sales  |
| 8 | aws-luckyus-isalesprivatedomain-rw       | aws-luckyus-isalesprivatedomain| Sales     |
| 9 | aws-luckyus-cdpactivity-rw               | aws-luckyus-cdpactivity        | Sales     |
| 10| aws-luckyus-opshopsale-rw                | aws-luckyus-opshopsale         | Sales/Ops |
| 11| aws-luckyus-upush-rw                     | aws-luckyus-upush              | Sales     |
| 12| aws-luckyus-iluckyams-rw                 | aws-luckyus-iluckyams          | Sales     |

#### Operations Domain (6 servers)

| # | Connection Name                          | RDS Instance (est.)            | Domain    |
|---|------------------------------------------|--------------------------------|-----------|
| 1 | aws-luckyus-opproduction-rw              | aws-luckyus-opproduction       | Operations|
| 2 | aws-luckyus-opempefficiency-rw           | aws-luckyus-opempefficiency    | Operations|
| 3 | aws-luckyus-opshop-rw                    | aws-luckyus-opshop             | Operations|
| 4 | aws-luckyus-opqualitycontrol-rw          | aws-luckyus-opqualitycontrol   | Operations|
| 5 | aws-luckyus-iopshopexpand-rw             | aws-luckyus-iopshopexpand      | Operations|
| 6 | aws-luckyus-iopocp-rw                    | aws-luckyus-iopocp             | Operations|

#### Supply Chain Management Domain (11 servers)

| # | Connection Name                          | RDS Instance (est.)            | Domain    |
|---|------------------------------------------|--------------------------------|-----------|
| 1 | aws-luckyus-scm-shopstock-rw             | aws-luckyus-scm-shopstock      | SCM       |
| 2 | aws-luckyus-scm-ordering-rw              | aws-luckyus-scm-ordering       | SCM       |
| 3 | aws-luckyus-scm-purchase-rw              | aws-luckyus-scm-purchase       | SCM       |
| 4 | aws-luckyus-scm-plan-rw                  | aws-luckyus-scm-plan           | SCM       |
| 5 | aws-luckyus-scm-wds-rw                   | aws-luckyus-scm-wds            | SCM       |
| 6 | aws-luckyus-scm-wmssimulate-rw           | aws-luckyus-scm-wmssimulate    | SCM       |
| 7 | aws-luckyus-scm-asset-rw                 | aws-luckyus-scm-asset          | SCM       |
| 8 | aws-luckyus-scm-openapi-rw               | aws-luckyus-scm-openapi        | SCM       |
| 9 | aws-luckyus-scmcommodity-rw              | aws-luckyus-scmcommodity       | SCM       |
| 10| aws-luckyus-scmsrm-rw                    | aws-luckyus-scmsrm             | SCM       |
| 11| aws-luckyus-ireplenishment-rw            | aws-luckyus-ireplenishment     | SCM       |

#### Finance Domain (5 servers)

| # | Connection Name                          | RDS Instance (est.)            | Domain    |
|---|------------------------------------------|--------------------------------|-----------|
| 1 | aws-luckyus-ifiaccounting-rw             | aws-luckyus-ifiaccounting      | Finance   |
| 2 | aws-luckyus-fitax-rw                     | aws-luckyus-fitax              | Finance   |
| 3 | aws-luckyus-fichargecontrol-rw           | aws-luckyus-fichargecontrol    | Finance   |
| 4 | aws-luckyus-ibillingcentersrv-rw         | aws-luckyus-ibillingcentersrv  | Finance   |
| 5 | aws-luckyus-iunifiedreconcile-rw         | aws-luckyus-iunifiedreconcile  | Finance   |

#### Platform / Infrastructure Domain (18 servers)

| # | Connection Name                          | RDS Instance (est.)            | Domain    |
|---|------------------------------------------|--------------------------------|-----------|
| 1 | aws-luckyus-framework01-rw               | aws-luckyus-framework01        | Platform  |
| 2 | aws-luckyus-framework02-rw               | aws-luckyus-framework02        | Platform  |
| 3 | aws-luckyus-iadmin-rw                    | aws-luckyus-iadmin             | Platform  |
| 4 | aws-luckyus-ipermission-rw               | aws-luckyus-ipermission        | Platform  |
| 5 | aws-luckyus-iluckyauthapi-rw             | aws-luckyus-iluckyauthapi      | Platform  |
| 6 | aws-luckyus-iworkflowmidlayer-rw         | aws-luckyus-iworkflowmidlayer  | Platform  |
| 7 | aws-luckyus-oplog-rw                     | aws-luckyus-oplog              | Platform  |
| 8 | aws-luckyus-iopenadmin-rw                | aws-luckyus-iopenadmin         | Platform  |
| 9 | aws-luckyus-iopenlinker-rw               | aws-luckyus-iopenlinker        | Platform  |
| 10| aws-luckyus-iopenservice-rw              | aws-luckyus-iopenservice       | Platform  |
| 11| aws-luckyus-ibizconfigcenter-rw          | aws-luckyus-ibizconfigcenter   | Platform  |
| 12| aws-luckyus-iluckyhealth-rw              | aws-luckyus-iluckyhealth       | Platform  |
| 13| aws-luckyus-iluckymedia-rw               | aws-luckyus-iluckymedia        | Platform  |
| 14| aws-luckyus-iotplatform-rw               | aws-luckyus-iotplatform        | Platform  |
| 15| aws-luckyus-devops-rw                    | aws-luckyus-devops             | Platform  |
| 16| aws-luckyus-ijumpserver-jumpserver-rw    | aws-luckyus-ijumpserver        | Platform  |
| 17| aws-luckyus-iluckydorisops-rw            | aws-luckyus-iluckydorisops     | Platform  |
| 18| aws-luckyus-mfranchise-rw                | aws-luckyus-mfranchise         | Platform  |

#### Data / Analytics Domain (5 servers)

| # | Connection Name                          | RDS Instance (est.)            | Domain    |
|---|------------------------------------------|--------------------------------|-----------|
| 1 | aws-luckyus-ldas-rw                      | aws-luckyus-ldas               | Data      |
| 2 | aws-luckyus-ldas01-rw                    | aws-luckyus-ldas01             | Data      |
| 3 | aws-luckyus-pubdm-rw                     | aws-luckyus-pubdm              | Data      |
| 4 | aws-luckyus-icyberdata-rw                | aws-luckyus-icyberdata         | Data      |
| 5 | aws-luckyus-dbatest-rw                   | aws-luckyus-dbatest            | Data      |

#### HR / Other Domain (5 servers)

| # | Connection Name                          | RDS Instance (est.)            | Domain    |
|---|------------------------------------------|--------------------------------|-----------|
| 1 | aws-luckyus-iehr-rw                      | aws-luckyus-iehr               | HR        |
| 2 | aws-luckyus-igers-rw                     | aws-luckyus-igers              | Other     |
| 3 | aws-luckyus-iriskcontrolservice-rw       | aws-luckyus-iriskcontrolservice| Other     |
| 4 | aws-luckyus-dbatest-rw                   | aws-luckyus-dbatest            | DBA       |
| 5 | recovery-dbatest                         | recovery-dbatest               | DBA       |

**Total MySQL Servers: 62**

---

### A.2 All 78 Redis (ElastiCache) Clusters

#### Authentication & Session (8 clusters)

| # | Cluster Name                | Purpose                        | Prometheus Status |
|---|-----------------------------|--------------------------------|-------------------|
| 1 | luckyus-auth                | Core authentication cache      | UP                |
| 2 | luckyus-authservice         | Auth service cache             | UP                |
| 3 | luckyus-aapi-unionauth      | API union auth cache           | UP                |
| 4 | luckyus-sapi-unionauth      | Service API union auth cache   | UP                |
| 5 | luckyus-open-unionauth      | Open platform union auth       | UP                |
| 6 | luckyus-unionauth           | Unified authentication cache   | UP                |
| 7 | luckyus-session             | Session management (150K active) | UP              |
| 8 | luckyus-iopenauth           | Open platform auth cache       | UP                |

#### API Gateway & Network (3 clusters)

| # | Cluster Name                | Purpose                        | Prometheus Status |
|---|-----------------------------|--------------------------------|-------------------|
| 1 | luckyus-apigateway          | API gateway rate limiting/cache | UP               |
| 2 | luckyus-waf                 | WAF rule cache                 | UP                |
| 3 | luckyus-web                 | Web application cache          | UP                |

#### Sales & CRM (10 clusters)

| # | Cluster Name                | Purpose                        | Prometheus Status |
|---|-----------------------------|--------------------------------|-------------------|
| 1 | luckyus-isales-commodity    | Product catalog cache          | UP                |
| 2 | luckyus-isales-crm          | CRM data cache                 | UP                |
| 3 | luckyus-isales-datamarket   | Data marketing cache           | UP                |
| 4 | luckyus-isales-market       | Marketing cache (1.28GB, 5.6M keys) | UP          |
| 5 | luckyus-isales-marketcapi   | Marketing CAPI cache           | UP                |
| 6 | luckyus-isales-member       | Member services cache          | UP                |
| 7 | luckyus-isales-order        | Order processing cache         | UP                |
| 8 | luckyus-isales-privatedomain| Private domain cache           | UP                |
| 9 | luckyus-isales-session      | Sales session cache            | UP                |
| 10| luckyus-isales-tradecapi    | Trade CAPI cache               | UP                |

#### SCM / Supply Chain (11 clusters)

| # | Cluster Name                | Purpose                        | Prometheus Status |
|---|-----------------------------|--------------------------------|-------------------|
| 1 | luckyus-scm-asset           | Asset management cache         | UP                |
| 2 | luckyus-scm-commodity       | Commodity data cache           | UP                |
| 3 | luckyus-scm-commodityadmin  | Commodity admin cache          | UP                |
| 4 | luckyus-scm-ordering        | Store ordering cache           | UP                |
| 5 | luckyus-scm-plan            | Planning/forecast cache        | UP                |
| 6 | luckyus-scm-purchase        | Procurement cache              | UP                |
| 7 | luckyus-scm-shopstock       | Inventory cache                | UP                |
| 8 | luckyus-scm-sims            | SIMS cache                     | UP                |
| 9 | luckyus-scm-srm             | Supplier relationship cache    | UP                |
| 10| luckyus-scm-wds             | Warehouse distribution cache   | UP                |
| 11| luckyus-scmwmssimulate      | WMS simulation cache           | UP                |

#### DevOps & Infrastructure (6 clusters)

| # | Cluster Name                | Purpose                        | Prometheus Status |
|---|-----------------------------|--------------------------------|-------------------|
| 1 | luckyus-devops              | DevOps operations cache        | UP                |
| 2 | luckyus-cmdb                | CMDB configuration cache       | UP                |
| 3 | luckyus-jumpserver          | Jump server cache              | UP                |
| 4 | luckyus-chronus             | Chronus scheduler cache        | UP                |
| 5 | luckyus-koala               | Koala platform cache           | UP                |
| 6 | luckyus-daq                 | Data acquisition cache         | UP                |

#### Big Data & Analytics (5 clusters)

| # | Cluster Name                | Purpose                        | Prometheus Status |
|---|-----------------------------|--------------------------------|-------------------|
| 1 | luckyus-bigdata-cyberdata   | CyberData analytics cache      | UP                |
| 2 | luckyus-bigdata-dataplatform| Data platform cache            | UP                |
| 3 | luckyus-ldas                | LDAS cache                     | UP                |
| 4 | luckyus-pub-dm              | Public data mart cache         | UP                |
| 5 | luckyus-mdm                 | Master data management cache   | UP                |

#### Finance & Billing (6 clusters)

| # | Cluster Name                | Purpose                        | Prometheus Status |
|---|-----------------------------|--------------------------------|-------------------|
| 1 | luckyus-billcenterservice   | Billing center cache           | UP                |
| 2 | luckyus-ifiaccounting       | Accounting cache               | UP                |
| 3 | luckyus-ifichargecontrol    | Charge control cache           | UP                |
| 4 | luckyus-ifitax              | Tax service cache              | UP                |
| 5 | luckyus-iunifiedreconcile   | Reconciliation cache           | UP                |
| 6 | luckyus-iriskcontrol        | Risk control cache             | UP                |

#### Operations (9 clusters)

| # | Cluster Name                | Purpose                        | Prometheus Status |
|---|-----------------------------|--------------------------------|-------------------|
| 1 | luckyus-shop                | Shop operations cache          | UP                |
| 2 | luckyus-shopexpand          | Shop expansion cache           | UP                |
| 3 | luckyus-shopsale            | Shop sales cache (2.9% hit rate) | UP              |
| 4 | luckyus-empefficiency       | Employee efficiency cache      | UP                |
| 5 | luckyus-franchise           | Franchise management cache     | UP                |
| 6 | luckyus-production          | Production/drink making cache  | UP                |
| 7 | luckyus-qualitycontrol      | Quality control cache          | UP                |
| 8 | luckyus-ocp                 | OCP operations cache           | UP                |
| 9 | luckyus-onepiece            | OnePiece platform cache        | UP                |

#### Platform Services (18 clusters)

| # | Cluster Name                | Purpose                        | Prometheus Status |
|---|-----------------------------|--------------------------------|-------------------|
| 1 | luckyus-iadmin              | Admin platform cache           | UP                |
| 2 | luckyus-ibizconfigcenter    | Business config cache          | UP                |
| 3 | luckyus-iehr                | eHR system cache               | UP                |
| 4 | luckyus-igers               | GERS system cache              | UP                |
| 5 | luckyus-ilkm                | LKM platform cache             | UP                |
| 6 | luckyus-ilopamanager        | LOPA manager cache             | UP                |
| 7 | luckyus-imessageflow        | Message flow cache             | UP                |
| 8 | luckyus-iopenadmin          | Open platform admin cache      | UP                |
| 9 | luckyus-iopenlinker         | Open linker cache              | UP                |
| 10| luckyus-iopenlinkeradmin    | Open linker admin cache        | **DOWN**          |
| 11| luckyus-iopenservice        | Open service cache             | UP                |
| 12| luckyus-iotplatform         | IoT platform cache             | UP                |
| 13| luckyus-ipermission         | Permission management cache    | UP                |
| 14| luckyus-ipushnet            | Push network cache             | UP                |
| 15| luckyus-iupush              | Push service cache             | UP                |
| 16| luckyus-iworkflowmidlayer   | Workflow middleware cache      | UP                |
| 17| luckyus-lkmap               | Map service cache              | UP                |
| 18| luckyus-redis-dify          | Dify AI platform cache         | UP                |

#### Redis Fleet Summary

```
CATEGORY                    COUNT   UP    DOWN   NOTES
────────────────────────    ─────   ──    ────   ──────────────────
Authentication & Session    8       8     0
API Gateway & Network       3       3     0
Sales & CRM                 10      10    0      Largest: isales-market (1.28GB)
SCM / Supply Chain          11      11    0
DevOps & Infrastructure     6       6     0
Big Data & Analytics        5       5     0
Finance & Billing           6       6     0
Operations                  9       9     0      Worst: shopsale (2.9% hit rate)
Platform Services           18      17    1      DOWN: iopenlinkeradmin
────────────────────────    ─────   ──    ────
TOTAL (Prometheus-tracked)  76      75    1
Non-Prometheus clusters     2       --    --     (estimated)
────────────────────────    ─────   ──    ────
GRAND TOTAL                 78
```

**Note:** 76 of 78 clusters are monitored via Prometheus (aws-redis-job scrape target).
2 additional clusters may exist that are not registered in Prometheus, bringing the total
to 78 as reported by AWS resource inventory.

---

### A.3 All 3 PostgreSQL Servers

| # | Connection Name              | Engine     | Instance Class (est.) | Primary Use                |
|---|------------------------------|------------|-----------------------|----------------------------|
| 1 | aws-luckyus-dify-rw          | PostgreSQL | db.t4g.medium (est.)  | Dify AI platform (primary) |
| 2 | aws-luckyus-difynew-rw       | PostgreSQL | db.t4g.medium (est.)  | Dify AI platform (new)     |
| 3 | aws-luckyus-pgilkmap-rw      | PostgreSQL | db.t4g.medium (est.)  | LK Map geolocation (PostGIS) |

**PostgreSQL usage context:**
- Dify is an open-source LLM application development platform. LKUS runs it on PostgreSQL
  (Dify's default database), separate from the MySQL-based main application stack.
- The existence of two Dify instances (dify + difynew) suggests either a migration in
  progress, a version upgrade, or a dev/prod split.
- pgilkmap uses PostGIS extensions for geospatial operations — store location queries,
  distance calculations, and the site selection model's geographic features.

---

### A.4 Newly Explored Server Details

The following 5 servers were explored in detail during this assessment, with table counts
and key tables documented:

#### A.4.1 aws-luckyus-salesorder-rw

| Metric       | Value                                                  |
|--------------|--------------------------------------------------------|
| Table Count  | 25+ tables                                             |
| Key Tables   | sales_order (487K rows), order_detail, order_status_log |
| Schema Notes | order_id BIGINT (PK), user_no VARCHAR, shop_id BIGINT  |
| Partitioning | None observed                                          |
| Indexes      | order_id, user_no, shop_id, create_time                |

#### A.4.2 aws-luckyus-salespayment-rw

| Metric       | Value                                                  |
|--------------|--------------------------------------------------------|
| Table Count  | 20+ tables                                             |
| Key Tables   | sales_payment (518K rows), trade_record, refund_record |
| Schema Notes | order_id VARCHAR (not BIGINT — type mismatch), trade_no VARCHAR |
| Partitioning | None observed                                          |
| Indexes      | order_id, trade_no, user_no, create_time               |

#### A.4.3 aws-luckyus-salesmarketing-rw

| Metric       | Value                                                  |
|--------------|--------------------------------------------------------|
| Table Count  | 40+ tables                                             |
| Key Tables   | activity (514K), coupon_instance (2.42M active + 37.3M expired), ab_test_record (6.4M) |
| Schema Notes | Large table count reflects sophisticated marketing engine |
| Partitioning | None observed (37.3M expired coupons need archival)    |
| Indexes      | activity_id, user_no, coupon_code, create_time         |

#### A.4.4 aws-luckyus-scm-shopstock-rw

| Metric       | Value                                                  |
|--------------|--------------------------------------------------------|
| Table Count  | 15+ tables                                             |
| Key Tables   | stock_change (9.1M rows), stock_snapshot, stock_alert  |
| Schema Notes | Composite key: shop_dept_id BIGINT + goods_mid VARCHAR |
| Partitioning | None observed (9.1M rows — candidate for partitioning) |
| Indexes      | shop_dept_id, goods_mid, change_time                   |

#### A.4.5 aws-luckyus-opempefficiency-rw

| Metric       | Value                                                  |
|--------------|--------------------------------------------------------|
| Table Count  | 12+ tables                                             |
| Key Tables   | employee (324 rows), clock_in (47.5K), schedule (15.7K) |
| Schema Notes | employee_id VARCHAR, shop_id BIGINT                    |
| Partitioning | None needed (small tables)                             |
| Indexes      | employee_id, shop_id, clock_date                       |

---

## 9. Risk Register — Data Architecture

This section summarizes the architectural, operational, and compliance risks identified
during this assessment, ranked by severity and potential business impact.

### 9.1 Compliance & Regulatory Risks

| ID     | Risk                                    | Severity | Likelihood | Impact      | Mitigation                          |
|--------|-----------------------------------------|----------|------------|-------------|-------------------------------------|
| R-C01  | US sales tax not implemented (fitax empty) | CRITICAL | Confirmed | Audit/fine | Assess current tax handling; implement DB records |
| R-C02  | No data retention policies on 90+ log groups | HIGH  | Confirmed  | Cost + compliance | Set 30/90-day retention policies  |
| R-C03  | PII in marketing database (phone, email)  | MEDIUM  | Confirmed  | Privacy    | Implement encryption at rest, access controls |
| R-C04  | No data lineage tracking                  | MEDIUM  | Confirmed  | Audit      | Implement data catalog + lineage tool |

### 9.2 Operational Risks

| ID     | Risk                                    | Severity | Likelihood | Impact      | Mitigation                          |
|--------|-----------------------------------------|----------|------------|-------------|-------------------------------------|
| R-O01  | Zero functional alerting (3 broken rules) | CRITICAL | Confirmed | Outage blind | Deploy comprehensive alert rules   |
| R-O02  | 91% of EC2 in single AZ (us-east-1a)     | HIGH    | Confirmed  | AZ failure  | Redistribute across 3 AZs          |
| R-O03  | OpenSearch cluster instability (RED 2/12) | HIGH    | Recurring  | Log loss    | Add capacity, fix JVM heap          |
| R-O04  | 78% idle EC2 fleet (attack surface)       | MEDIUM  | Confirmed  | Security    | Decommission unused instances       |
| R-O05  | 1 Redis target DOWN (hostname typo)       | LOW     | Confirmed  | Monitoring  | Fix trailing space in config        |
| R-O06  | No EKS monitoring ($12.7K/mo unmonitored) | HIGH   | Confirmed  | Outage blind | Deploy kube-state-metrics          |

### 9.3 Data Quality Risks

| ID     | Risk                                    | Severity | Likelihood | Impact      | Mitigation                          |
|--------|-----------------------------------------|----------|------------|-------------|-------------------------------------|
| R-D01  | order_id type mismatch (bigint/varchar)   | HIGH    | Confirmed  | Query errors | Standardize types across systems   |
| R-D02  | 37.3M expired China coupons in marketing  | HIGH    | Confirmed  | Perf/cost   | Archive to S3, purge from MySQL    |
| R-D03  | NZD test orders contaminating analytics   | HIGH    | Confirmed  | Bad metrics  | Flag test data, exclude from reports |
| R-D04  | luckyus-shopsale 2.9% cache hit rate      | MEDIUM  | Confirmed  | DB load     | Investigate cache key patterns      |
| R-D05  | 2.69M Redis keys without TTL              | MEDIUM  | Confirmed  | Memory OOM  | Audit and set TTL policies          |
| R-D06  | Student coupon 0% redemption rate          | LOW     | Confirmed  | Revenue leak | Debug coupon validation flow       |

### 9.4 Financial Risks

| ID     | Risk                                    | Severity | Likelihood | Impact      | Mitigation                          |
|--------|-----------------------------------------|----------|------------|-------------|-------------------------------------|
| R-F01  | RDS RI coverage at 1.3% (most expired)    | HIGH    | Confirmed  | $18-24K/yr waste | Purchase RIs immediately       |
| R-F02  | ElastiCache RI coverage at 6.6%           | HIGH    | Confirmed  | $9.6-12K/yr waste | Purchase RIs                  |
| R-F03  | All EC2 RIs expire Aug 2026               | HIGH    | 6 months   | $24K+/mo spike | Plan renewal by June 2026      |
| R-F04  | CloudWatch cost surging +23.9% MoM        | MEDIUM  | Confirmed  | Growing waste | Set log retention policies      |
| R-F05  | S3 cost surging +43.9% MoM               | LOW     | Confirmed  | Minor growth | Monitor; implement lifecycle rules |
| R-F06  | Per-store cost 4-7x industry benchmark    | HIGH    | Confirmed  | Margin pressure | Rightsizing + expansion         |

---

## 10. Recommendations Summary

### Immediate Actions (Week 1-2)

| Priority | Action                                             | Estimated Savings/Impact      |
|----------|----------------------------------------------------|-------------------------------|
| P0       | Assess fitax gap — determine where tax is calculated | Compliance risk elimination  |
| P0       | Fix 3 broken Grafana alert rules                   | Restore basic alerting        |
| P1       | Set CloudWatch log retention (30-day for slow queries) | $500-1,000/mo savings     |
| P1       | Purchase RDS Reserved Instances                    | $1,500-2,000/mo savings       |
| P1       | Fix Prometheus trailing-space hostname              | Restore Redis monitoring      |

### Short-Term Actions (Month 1-2)

| Priority | Action                                             | Estimated Savings/Impact      |
|----------|----------------------------------------------------|-------------------------------|
| P1       | Purchase ElastiCache Reserved Instances             | $800-1,000/mo savings        |
| P1       | Renew OpenSearch Reserved Instances                 | $600-800/mo savings          |
| P1       | Deploy CloudWatch alarms for critical services      | Outage detection              |
| P2       | Archive 37.3M expired coupon records                | Query performance + storage   |
| P2       | Flag 21,245 NZD test orders                         | Analytics accuracy            |
| P2       | Investigate luckyus-shopsale 2.9% hit rate          | Reduce DB load               |

### Medium-Term Actions (Month 2-6)

| Priority | Action                                             | Estimated Savings/Impact      |
|----------|----------------------------------------------------|-------------------------------|
| P2       | EC2 rightsizing analysis and execution              | $14,676/mo savings           |
| P2       | EKS node group optimization                        | $6,000-8,000/mo savings      |
| P2       | Standardize order_id type across all systems        | Data quality improvement     |
| P2       | Deploy comprehensive Prometheus monitoring          | Full infrastructure visibility|
| P3       | Implement Redis TTL policies for isales-market      | Prevent memory growth        |
| P3       | Plan EC2 RI renewal strategy for Aug 2026           | Prevent cost spike           |

### Long-Term Actions (Month 6-18)

| Priority | Action                                             | Estimated Savings/Impact      |
|----------|----------------------------------------------------|-------------------------------|
| P3       | Implement data warehouse / lakehouse                | Unified analytics             |
| P3       | Build feature store for ML models                   | ML development velocity       |
| P3       | Deploy data lineage and catalog tools               | Governance + compliance       |
| P3       | Launch loyalty program (empty member tables)        | Customer retention            |
| P4       | Multi-AZ redistribution for EC2 fleet               | HA improvement               |
| P4       | Graviton migration for cost optimization            | 10-20% compute savings       |

---

## Document Control

| Field                | Value                                                |
|----------------------|------------------------------------------------------|
| Document ID          | LKUS-AIR-D01-v1.0                                    |
| Title                | Data System Architecture Report                      |
| Series               | AI Transformation Roadmap — Deliverable 1 of 5       |
| Author               | AI Transformation Team                               |
| Date                 | February 14, 2026                                    |
| Classification       | Confidential                                         |
| Review Status        | Draft                                                |
| Data Sources         | Live system queries, AWS Cost Explorer, Grafana,      |
|                      | Prometheus, CloudWatch, BI Reports (7), Infrastructure |
|                      | Reports (6)                                          |
| Data Currency         | January-February 2026                                |
| Next Deliverable      | [02-ai-use-case-catalog.md](02-ai-use-case-catalog.md) |

---

## Glossary

| Term        | Definition                                                       |
|-------------|------------------------------------------------------------------|
| AZ          | Availability Zone (AWS data center subdivision)                  |
| CDP         | Customer Data Platform                                           |
| EDP         | Enterprise Discount Program (AWS volume discount)                |
| EKS         | Elastic Kubernetes Service                                       |
| EMR         | Elastic MapReduce (Hadoop/Spark managed service)                 |
| gp2/gp3     | General Purpose SSD EBS volume types                            |
| IoT         | Internet of Things (coffee machine telemetry)                    |
| LDAS        | Luckin Data Analytics Service                                    |
| LKUS        | Luckin Coffee USA                                                |
| MoM         | Month-over-Month                                                 |
| MSK         | Managed Streaming for Apache Kafka                               |
| OCP         | Operations Control Platform                                      |
| PO          | Purchase Order                                                   |
| QSR         | Quick Service Restaurant                                         |
| RI          | Reserved Instance                                                |
| SCM         | Supply Chain Management                                          |
| SP          | Savings Plans                                                    |
| SRM         | Supplier Relationship Management                                 |
| TTL         | Time-To-Live (cache expiration policy)                           |
| WDS         | Warehouse Distribution System                                    |
| WMS         | Warehouse Management System                                      |

---

## Appendix B: High-Level Architecture Diagram

```
                              LUCKIN COFFEE USA — DATA SYSTEM ARCHITECTURE
                              ═══════════════════════════════════════════

 ┌─────────────────────────────────────────────────────────────────────────────────────┐
 │                              CUSTOMER TOUCHPOINTS                                   │
 │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐             │
 │  │ Mobile   │  │ Push     │  │ SMS      │  │ Email    │  │ Store    │             │
 │  │ App      │  │ Notifs   │  │ (2.3M)   │  │          │  │ Kiosks   │             │
 │  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘             │
 └───────┼──────────────┼──────────────┼──────────────┼──────────────┼─────────────────┘
         │              │              │              │              │
         ▼              ▼              ▼              ▼              ▼
 ┌─────────────────────────────────────────────────────────────────────────────────────┐
 │                              API GATEWAY + WAF + CDN                                │
 │  ┌──────────┐  ┌──────────┐  ┌──────────┐                                         │
 │  │CloudFront│  │ WAF      │  │API Gate  │                                         │
 │  │ (CDN)    │  │ Rules    │  │ 3 APIs   │                                         │
 │  └──────────┘  └──────────┘  └──────────┘                                         │
 └───────────────────────────────────┬─────────────────────────────────────────────────┘
                                     │
                                     ▼
 ┌─────────────────────────────────────────────────────────────────────────────────────┐
 │                       EKS KUBERNETES CLUSTER (20 Nodes)                             │
 │  ┌──────────────────────────────────────────────────────────────────────────┐       │
 │  │ Microservices (Containerized Applications)                               │       │
 │  │                                                                          │       │
 │  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐    │       │
 │  │  │ Order  │ │Payment │ │Produce │ │CRM     │ │Market  │ │SCM     │    │       │
 │  │  │Service │ │Service │ │Service │ │Service │ │Service │ │Service │    │       │
 │  │  └───┬────┘ └───┬────┘ └───┬────┘ └───┬────┘ └───┬────┘ └───┬────┘    │       │
 │  │      │          │          │          │          │          │           │       │
 │  └──────┼──────────┼──────────┼──────────┼──────────┼──────────┼───────────┘       │
 │         │          │          │          │          │          │                    │
 │  ┌──────▼──────────▼──────────▼──────────▼──────────▼──────────▼───────────┐       │
 │  │                    MSK / KAFKA (308 Topics)                              │       │
 │  │  Event-driven communication bus for all microservice interactions        │       │
 │  └─────────────────────────────────────────────────────────────────────────┘       │
 └───────────────────────────────────┬─────────────────────────────────────────────────┘
                                     │
         ┌───────────────────────────┼───────────────────────────┐
         ▼                           ▼                           ▼
 ┌───────────────┐          ┌───────────────┐          ┌───────────────┐
 │ MYSQL (62)    │          │ REDIS (78)    │          │ POSTGRESQL (3)│
 │               │          │               │          │               │
 │ Sales    (12) │          │ Auth/Sess (8) │          │ Dify AI   (2) │
 │ Ops       (6) │          │ Sales    (10) │          │ GeoMap    (1) │
 │ SCM      (11) │          │ SCM      (11) │          │               │
 │ Finance   (5) │          │ Finance   (6) │          └───────────────┘
 │ Platform (18) │          │ Ops       (9) │
 │ Data      (5) │          │ Platform (18) │
 │ HR/Other  (5) │          │ DevOps    (6) │
 │               │          │ BigData   (5) │
 │ Total: 62     │          │ API/Net   (3) │
 │ $5,527/mo     │          │ AI        (1) │
 └───────┬───────┘          │ Other     (1) │
         │                  │               │
         │                  │ Total: 78     │
         │                  │ $2,314/mo     │
         │                  └───────────────┘
         │
         ▼
 ┌─────────────────────────────────────────────────────────────────────────────────────┐
 │                         DATA & ANALYTICS LAYER                                      │
 │                                                                                     │
 │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐             │
 │  │OpenSearch│  │DocumentDB│  │   EMR    │  │CyberData │  │  Dify    │             │
 │  │$2,647/mo │  │ $843/mo  │  │ $565/mo  │  │ ETL/Arch │  │  AI/LLM  │             │
 │  │Log Search│  │ Doc Store│  │ Batch    │  │ Pipeline │  │ Platform │             │
 │  └──────────┘  └──────────┘  └──────────┘  └──────────┘  └──────────┘             │
 └─────────────────────────────────────────────────────────────────────────────────────┘

 ┌─────────────────────────────────────────────────────────────────────────────────────┐
 │                         MONITORING (MINIMAL)                                        │
 │                                                                                     │
 │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐                           │
 │  │ Grafana  │  │Prometheus│  │CloudWatch│  │GuardDuty │                           │
 │  │17 dashbds│  │76 targets│  │ 95 logs  │  │ Security │                           │
 │  │ 3 alerts │  │Redis only│  │ 0 alarms │  │ Findings │                           │
 │  │(ALL ERR) │  │          │  │          │  │          │                           │
 │  └──────────┘  └──────────┘  └──────────┘  └──────────┘                           │
 └─────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Appendix C: Data Volume Summary

| Database / System       | Primary Metric                | Volume         | Growth Trend    |
|-------------------------|-------------------------------|----------------|-----------------|
| salesorder              | Completed orders              | 487,251        | ~40K/month      |
| salespayment            | Trade records                 | 518,427        | ~43K/month      |
| salescrm                | Registered users              | 275,000        | ~20K/month      |
| isalescdp               | User state records            | 980,000        | ~70K/month      |
| salesmarketing (active) | Campaign activities           | 514,000        | ~40K/month      |
| salesmarketing (coupons)| Active coupon instances        | 2,424,506     | ~200K/month     |
| salesmarketing (expired)| Expired coupons (China bloat) | 37,300,000    | Static          |
| salesmarketing (A/B)    | A/B test records              | 6,386,203      | ~500K/month     |
| opproduction            | Production records            | 502,130        | ~42K/month      |
| opempefficiency (clock) | Clock-in records              | 47,500         | ~4K/month       |
| opempefficiency (sched) | Schedule entries              | 15,700         | ~1.3K/month     |
| iotplatform             | Cup/device events             | 587,143        | ~49K/month      |
| scm-shopstock           | Stock change records          | 9,136,482      | ~760K/month     |
| scm-plan                | Demand predictions            | 2,517,238      | ~210K/month     |
| ireplenishment          | Order predictions             | 124,000        | ~10K/month      |
| scm-purchase (POs)      | Purchase orders               | 694            | ~58/month       |
| scm-purchase (ships)    | Shipment records              | 1,670          | ~139/month      |
| upush (SMS)             | SMS messages sent             | 2,300,000      | ~190K/month     |
| upush (push)            | Push notifications            | 8,000,000+     | ~670K/month     |
| Redis isales-market     | Cached keys                   | 5,600,000      | Growing (no TTL)|
| Redis session           | Active sessions               | 150,000        | Stable          |
| **TOTAL ESTIMATED**     | **All primary tables**        | **~76M records** | **~3M/month** |

**Estimated annual data growth at current rates:** ~36M new records/year across all systems.
The scm-shopstock system alone generates ~9.1M records/year, making it the highest-volume
data producer. Marketing (A/B tests + coupons) generates ~8.4M records/year.

---

*End of Deliverable 1: Data System Architecture Report*
*Luckin Coffee USA — AI Transformation Roadmap*
*Generated February 14, 2026 — Confidential*

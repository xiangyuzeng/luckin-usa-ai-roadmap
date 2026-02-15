# UC-OP-02: Store Performance Anomaly Detection / 门店绩效异常检测

## Overview / 概述

Statistical Process Control (SPC) system for detecting performance anomalies across Luckin Coffee USA's 10 active stores. Combines Z-score analysis with Western Electric rules to flag revenue, order volume, and operational KPI deviations at the daily store grain.

**Why this matters:** The 8th Avenue flagship store experienced a 51% revenue decline (Oct 2025 $106K to Jan 2026 $52K) that was discovered reactively. This system detects such degradations within 3-5 days using control chart methods proven in manufacturing quality management.

统计过程控制 (SPC) 系统，用于检测瑞幸咖啡美国 10 家活跃门店的绩效异常。结合 Z 分数分析和西部电气规则，在每日门店粒度上标记收入、订单量和运营 KPI 偏差。

## Problem Statement: The 8th Avenue Case / 问题陈述

```
Store:     US00001 "8th & Broadway" (dept_id=1127, flagship)
Period:    October 2025 --> January 2026
Revenue:   $106,000/month --> $52,000/month  (-51%)
Detection: Reactive (weeks-late discovery)
Root cause analysis required:
  - Seasonal decline vs. structural issue?
  - Cannibalization from US00004 "37th & Broadway"?
  - Operational degradation (production time, quality)?
```

This use case builds the monitoring infrastructure so that a decline of this magnitude triggers an automated alert within the first week -- not after two months of compounding losses.

## Architecture / 架构

```
  Source Databases (6 servers, read-only)        Analytics Server
  ┌──────────────────────────────────────┐      ┌──────────────────────────┐
  │ opshop          - Store master data  │      │ aws-luckyus-dbatest-rw   │
  │ salesorder      - Orders & revenue   │─────>│ Schema: test             │
  │ opproduction    - Production times   │      │                          │
  │ opqualitycontrol- QC & expiry logs   │      │ 5 analytics tables       │
  │ opempefficiency - Staff & attendance │      │ Python orchestrator      │
  │ dbatest         - Analytics output   │      │ Grafana dashboard        │
  └──────────────────────────────────────┘      └──────────────────────────┘
                                                          │
                  ┌───────────────────────────────────────┘
                  v
  ┌──────────────────────────────────────────────────────────────┐
  │  Presentation Layer                                          │
  │  - 3 HTML dashboards (executive, store detail, SPC charts)   │
  │  - Grafana dashboard (UID: uc-op-02-store-anomaly)           │
  └──────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **Extract** -- Pull daily store metrics from 5 source databases via Python orchestrator
2. **Transform** -- Compute rolling means, standard deviations, Z-scores, Western Electric rule violations
3. **Load** -- Write results to 5 analytics tables on `test` schema
4. **Alert** -- Flag anomalies by severity (CRITICAL / WARNING / INFO)
5. **Visualize** -- Render control charts and store rankings in Grafana + HTML dashboards

## Data Sources / 数据源

| Server | Schema | Key Tables | Purpose | Records |
|--------|--------|------------|---------|---------|
| aws-luckyus-opshop-rw | luckyus_opshop | t_shop, t_shop_dept | Store master, dept mapping | 10 stores |
| aws-luckyus-salesorder-rw | luckyus_salesorder | t_trade, t_trade_item | Orders, revenue (pay_money) | ~520K orders |
| aws-luckyus-opproduction-rw | luckyus_opproduction | t_production_order | Production times per item | ~502K records |
| aws-luckyus-opqualitycontrol-rw | luckyus_opqualitycontrol | t_expiry_management, t_task_form | QC logs, expiry tracking | ~236K records |
| aws-luckyus-opempefficiency-rw | luckyus_opempefficiency | t_attendance | Staff clock-in/out | ~47K records |
| aws-luckyus-dbatest-rw | test | (analytics tables below) | Analytics output | -- |

### Store Reference / 门店参考

| shop_no | Name | dept_id | Status | Notes |
|---------|------|---------|--------|-------|
| US00000 | NJ Test Kitchen | -- | Active | Test/R&D facility |
| US00001 | 8th & Broadway | 1127 | Active | Flagship; 51% revenue decline case |
| US00002 | 28th & 6th | 1128 | Active | |
| US00003 | 100 Maiden Ln | 1140 | Active | Financial District |
| US00004 | 37th & Broadway | 1141 | Active | Potential cannibalization source |
| US00005 | 54th & 8th | 20008 | Active | Midtown |
| US00006 | 102 Fulton | 20010 | Active | |
| US00007 | 108th & Broadway | 20011 | status=2 | Not yet open |
| US00008 | 33rd & 10th | 20027 | Active | |
| US99998 | Shanghai Test Kitchen | -- | Active | Overseas test facility |

**Order data range:** 2025-03-24 to 2026-02-15 (~11 months)
**Revenue field:** `pay_money DECIMAL(12,4)` in USD

## Analytics Schema (test database) / 分析表结构

Five tables on `aws-luckyus-dbatest-rw`, schema `test`:

| # | Table | Purpose | Grain |
|---|-------|---------|-------|
| 1 | `store_daily_metrics` | Daily KPIs per store (revenue, orders, AOV, production time) | store x day |
| 2 | `store_spc_control_limits` | Rolling mean, sigma, UCL/LCL per metric per store | store x metric |
| 3 | `store_anomaly_flags` | Detected anomalies with rule type, severity, Z-score | store x day x metric |
| 4 | `store_peer_comparison` | Cross-store ranking and percentile scores | store x week |
| 5 | `store_anomaly_run_log` | Pipeline execution audit trail | run_id |

## SPC Methods / 统计过程控制方法

### Z-Score Anomaly Detection

```
Z = (X - mu) / sigma

Where:
  X     = observed daily metric value
  mu    = rolling 28-day mean (excluding current day)
  sigma = rolling 28-day standard deviation
```

| Threshold | Severity | Action |
|-----------|----------|--------|
| \|Z\| > 3.0 | CRITICAL | Immediate investigation; page on-call ops lead |
| \|Z\| > 2.0 | WARNING | Next-day review; add to weekly ops meeting agenda |
| \|Z\| > 1.5 | INFO | Log for trend analysis; no immediate action |

### Western Electric Rules

Applied to sequential daily observations on X-bar charts:

| Rule | Pattern | Interpretation |
|------|---------|----------------|
| Rule 1 | 1 point beyond 3-sigma | Single extreme outlier |
| Rule 2 | 2 of 3 consecutive points beyond 2-sigma (same side) | Emerging shift |
| Rule 3 | 4 of 5 consecutive points beyond 1-sigma (same side) | Sustained drift |
| Rule 4 | 8 consecutive points on same side of center line | Process mean shift |

These rules detect the 8th Avenue pattern: Rule 4 would have flagged the sustained decline within 8 business days of the trend starting.

## File Structure / 文件结构

```
UC-OP-02-store-anomaly/
├── README.md                              # This file
├── sql/
│   ├── 01_schema_discovery.sql            # Source table exploration & column inventory
│   ├── 02_store_master_analysis.sql       # Store reference data, dept_id mapping
│   ├── 03_revenue_timeseries.sql          # Daily revenue extraction per store
│   ├── 04_create_analytics_schema.sql     # DDL for 5 analytics tables
│   ├── 05_daily_metrics_etl.sql           # ETL: compute daily KPIs from source tables
│   ├── 06_spc_control_limits.sql          # Rolling stats, Z-scores, Western Electric rules
│   ├── 07_peer_comparison.sql             # Cross-store ranking and percentile computation
│   └── 08_anomaly_alerting.sql            # Alert rule evaluation and severity assignment
├── orchestrator/
│   └── run_pipeline.py                    # Python orchestrator (cross-server ETL bridge)
├── dashboards/
│   ├── store_anomaly_executive.html       # Executive summary dashboard (HTML/JS)
│   ├── store_anomaly_detail.html          # Per-store deep-dive with SPC charts
│   ├── store_anomaly_spc.html             # Control chart visualization
│   └── store_anomaly_dashboard.json       # Grafana dashboard export
├── docs/
│   └── (data dictionary, operational guide)
├── reports/
│   └── (historical analysis outputs)
└── proposal/
    └── (management proposal package)
```

## Quick Start / 快速开始

### Prerequisites

- Python 3.9+ with `pymysql`, `python-dotenv`
- MySQL 8.0+ read access to 5 source servers
- MySQL 8.0+ write access to `test` schema on `aws-luckyus-dbatest-rw`
- Grafana instance with MySQL datasource

### Setup Steps

```bash
# 1. Clone and configure
cd UC-OP-02-store-anomaly
cp orchestrator/.env.example orchestrator/.env
# Edit .env with database credentials for all 6 servers

# 2. Create analytics tables (run by DBA on dbatest)
mysql -h aws-luckyus-dbatest-rw -u <user> -p test < sql/04_create_analytics_schema.sql

# 3. Initial backfill (full history)
cd orchestrator
python run_pipeline.py --setup
python run_pipeline.py --start-date 2025-03-24 --end-date 2026-02-15

# 4. Daily operation (T+1, scheduled via cron at 07:00 EST)
python run_pipeline.py  # defaults to yesterday

# 5. Import Grafana dashboard
# Upload dashboards/store_anomaly_dashboard.json via Grafana UI
```

### Important Notes / 重要说明

- SQL files target different database servers -- check the server comment header in each file
- The MCP DB gateway (`mcp-db-gateway`) is **read-only** for DDL; analytics table creation requires DBA execution
- All analytics tables use `IF NOT EXISTS` for idempotent re-runs
- The orchestrator uses DELETE + INSERT pattern (safe for re-processing any date)
- Design patterns follow UC-SC-01 (Demand Forecast Accuracy Monitor) conventions

## Dependencies / 依赖

| Component | Version | Purpose |
|-----------|---------|---------|
| Python | >= 3.9 | Pipeline orchestrator |
| PyMySQL | >= 1.1.0 | MySQL connectivity |
| python-dotenv | >= 1.0.0 | Environment configuration |
| MySQL | >= 8.0 | Source and analytics databases |
| Grafana | >= 10.0 | Dashboard visualization |

## Related Use Cases / 相关用例

- **UC-SC-01** Demand Forecast Accuracy Monitor -- same architecture, same analytics server
- **UC-OP-01** Smart Staffing Optimizer -- shares opempefficiency data source
- **UC-OP-03** Production Efficiency Analytics -- shares opproduction data source

## Change Log / 变更日志

| Date | Version | Change |
|------|---------|--------|
| 2026-02-15 | 0.1.0 | Initial scaffold -- data discovery complete, schema designed |

---
*UC-OP-02 Store Performance Anomaly Detection -- Luckin Coffee USA Operations Intelligence*

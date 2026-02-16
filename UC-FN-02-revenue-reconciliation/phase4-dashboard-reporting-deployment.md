# UC-FN-02 Phase 4: Dashboard, Reporting & Deployment Guide

> **Project**: Revenue Reconciliation Automation
> **Phase**: 4 of 4 — Dashboard, Reporting & Deployment Guide
> **Status**: DRAFT
> **Created**: 2026-02-16
> **Depends on**: Phase 3 Anomaly Detection Rules & Engine Design
> **Final Deliverable**: Complete operational system ready for production

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Dashboard Architecture](#2-dashboard-architecture)
3. [Redshift Reporting Views](#3-redshift-reporting-views)
4. [Executive Reconciliation Dashboard](#4-executive-reconciliation-dashboard)
5. [Operational Monitoring Dashboard](#5-operational-monitoring-dashboard)
6. [Anomaly Investigation Dashboard](#6-anomaly-investigation-dashboard)
7. [Scheduled Reports](#7-scheduled-reports)
8. [Grafana Dashboard Definitions](#8-grafana-dashboard-definitions)
9. [Infrastructure Deployment Guide](#9-infrastructure-deployment-guide)
10. [IAM Roles & Permissions](#10-iam-roles--permissions)
11. [Glue Job Deployment](#11-glue-job-deployment)
12. [Redshift Schema Deployment](#12-redshift-schema-deployment)
13. [CloudWatch Monitoring Setup](#13-cloudwatch-monitoring-setup)
14. [Operational Runbook](#14-operational-runbook)
15. [Go-Live Checklist](#15-go-live-checklist)
16. [Rollback Procedures](#16-rollback-procedures)
17. [Appendix A — Complete Table Inventory](#appendix-a--complete-table-inventory)
18. [Appendix B — Parameter Store Reference](#appendix-b--parameter-store-reference)
19. [Appendix C — Cost Estimate](#appendix-c--cost-estimate)

---

## 1. Executive Summary

Phase 4 delivers the presentation, reporting, and operational layers that make the revenue reconciliation pipeline consumable by three distinct audiences:

| Audience | Need | Deliverable |
|----------|------|-------------|
| **Finance Leadership** | Daily confidence that revenue is accurate | Executive Dashboard — match rates, anomaly counts, trend lines |
| **Finance Ops Team** | Investigate and resolve anomalies | Anomaly Investigation Dashboard — drill-down, assignment, resolution tracking |
| **DBA / Infrastructure** | Pipeline health and SLA compliance | Operational Monitoring Dashboard — job status, latency, error rates |

This document also provides the complete deployment guide: every IAM role, every Glue job, every Redshift table, every CloudWatch alarm — in the order they must be provisioned.

### System Topology (End-to-End)

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        SOURCE LAYER (MySQL)                             │
│  salesorder-rw  │  salespayment-rw  │  ifiaccounting-rw  │  iunified…  │
└────────┬────────┴─────────┬─────────┴──────────┬─────────┴──────┬──────┘
         │    AWS Glue ETL (PySpark) — 6-Phase Workflow           │
         ▼                                                        ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                   STAGING LAYER (S3 Parquet)                             │
│  s3://luckyus-data-lake/staging/reconciliation/                         │
│  ├── stg_recon_orders/       ├── stg_recon_trades/                      │
│  ├── stg_recon_payments/     ├── stg_recon_receipts/                    │
│  ├── stg_recon_income_bills/ └── stg_recon_vouchers/                    │
└────────────────────────────┬─────────────────────────────────────────────┘
                             ▼
┌──────────────────────────────────────────────────────────────────────────┐
│               DATA WAREHOUSE (Redshift Serverless)                      │
│  Staging Tables (6) → Match Results (3) → DW Facts (2)                  │
│  Anomaly Tables (3): dwd_recon_anomalies, _summary, _metrics            │
│  Reporting Views (6): see Section 3                                     │
└────────┬───────────────────┬────────────────────┬────────────────────────┘
         │                   │                    │
         ▼                   ▼                    ▼
┌─────────────────┐ ┌────────────────┐ ┌──────────────────────┐
│ Executive       │ │ Operational    │ │ Anomaly              │
│ Dashboard       │ │ Monitoring     │ │ Investigation        │
│ (Grafana)       │ │ (Grafana +     │ │ Dashboard (Grafana)  │
│                 │ │  CloudWatch)   │ │                      │
└─────────────────┘ └────────────────┘ └──────────────────────┘
         │                   │                    │
         └───────────────────┼────────────────────┘
                             ▼
                   WeCom Alerts + Email Reports
```

---

## 2. Dashboard Architecture

### 2.1 Technology Stack

| Component | Technology | Justification |
|-----------|------------|---------------|
| BI / Dashboards | **Grafana** (existing) | Already deployed for infrastructure monitoring; Redshift plugin available; avoids QuickSight cost |
| Data Source | **Redshift Serverless** | Materialized views refresh on schedule; sub-second dashboard queries |
| Alerting | **Grafana Alerting** → WeCom | Unified alert pipeline; existing `wecom-warning` / `wecom-critical` channels |
| Scheduled Reports | **AWS Lambda** + SES/WeCom | Daily PDF/CSV delivery to stakeholders |
| Pipeline Monitoring | **CloudWatch** + Grafana | Glue job metrics natively in CloudWatch |

### 2.2 Data Refresh Cadence

| Layer | Refresh | Trigger |
|-------|---------|---------|
| Staging tables | Daily 06:00 UTC | Glue Workflow `recon-daily-pipeline` |
| Match result tables | Daily ~06:30 UTC | Phase 4/5 of Glue Workflow |
| Anomaly tables | Daily ~06:40 UTC | Phase 6 of Glue Workflow |
| Materialized views | Daily 07:00 UTC | Redshift scheduled refresh |
| Dashboards | Real-time on MV data | Grafana auto-refresh 5 min |
| Scheduled reports | Daily 08:00 UTC (03:00 ET) | Lambda cron |

### 2.3 Grafana Folder Structure

```
Grafana/
└── Revenue Reconciliation/
    ├── Executive Overview          (folder_uid: recon-exec)
    │   └── Daily Reconciliation Health
    ├── Anomaly Investigation       (folder_uid: recon-anomaly)
    │   ├── Active Anomalies
    │   └── Anomaly Trends
    ├── Operational Monitoring      (folder_uid: recon-ops)
    │   ├── Pipeline Health
    │   └── Data Quality Scorecard
    └── Reports                     (folder_uid: recon-reports)
        └── Monthly Reconciliation Summary
```

---

## 3. Redshift Reporting Views

All views live in schema `recon` alongside the tables defined in Phases 2–3.

### 3.1 MV: Daily Reconciliation Summary

```sql
-- mv_recon_daily_summary
-- Refreshed daily at 07:00 UTC via Redshift scheduled query
CREATE MATERIALIZED VIEW recon.mv_recon_daily_summary AS
SELECT
    r.recon_date,
    -- Level 1: Order ↔ Payment
    COUNT(CASE WHEN l1.match_status IS NOT NULL THEN 1 END) AS l1_total,
    COUNT(CASE WHEN l1.match_status = 'MATCHED' THEN 1 END) AS l1_matched,
    COUNT(CASE WHEN l1.match_status = 'UNMATCHED' THEN 1 END) AS l1_unmatched,
    ROUND(100.0 * COUNT(CASE WHEN l1.match_status = 'MATCHED' THEN 1 END)
        / NULLIF(COUNT(CASE WHEN l1.match_status IS NOT NULL THEN 1 END), 0), 2)
        AS l1_match_rate_pct,
    COALESCE(SUM(CASE WHEN l1.match_status = 'MATCHED' THEN l1.order_amount END), 0)
        AS l1_matched_amount,
    COALESCE(SUM(CASE WHEN l1.match_status = 'UNMATCHED' THEN l1.order_amount END), 0)
        AS l1_unmatched_amount,
    -- Level 2: Order ↔ Receipt (with Stripe fee)
    COUNT(CASE WHEN l2.match_status IS NOT NULL THEN 1 END) AS l2_total,
    COUNT(CASE WHEN l2.match_status = 'MATCHED' THEN 1 END) AS l2_matched,
    ROUND(100.0 * COUNT(CASE WHEN l2.match_status = 'MATCHED' THEN 1 END)
        / NULLIF(COUNT(CASE WHEN l2.match_status IS NOT NULL THEN 1 END), 0), 2)
        AS l2_match_rate_pct,
    -- Level 3: Receipt ↔ Income Bill (aggregated)
    l3.l3_total_shops,
    l3.l3_matched_shops,
    l3.l3_match_rate_pct,
    l3.l3_total_variance,
    -- Anomalies
    a.anomaly_count,
    a.critical_count,
    a.high_count,
    a.medium_count,
    a.low_count,
    a.open_count,
    a.resolved_count
FROM (
    SELECT DISTINCT recon_date
    FROM recon.stg_recon_level1_results
    WHERE recon_date >= CURRENT_DATE - 90
) r
LEFT JOIN recon.stg_recon_level1_results l1
    ON l1.recon_date = r.recon_date
LEFT JOIN recon.stg_recon_level2_results l2
    ON l2.recon_date = r.recon_date AND l2.order_id = l1.order_id
LEFT JOIN (
    SELECT
        recon_date,
        COUNT(*) AS l3_total_shops,
        COUNT(CASE WHEN match_status = 'MATCHED' THEN 1 END) AS l3_matched_shops,
        ROUND(100.0 * COUNT(CASE WHEN match_status = 'MATCHED' THEN 1 END)
            / NULLIF(COUNT(*), 0), 2) AS l3_match_rate_pct,
        SUM(ABS(variance_amount)) AS l3_total_variance
    FROM recon.stg_recon_level3_results
    WHERE recon_date >= CURRENT_DATE - 90
    GROUP BY recon_date
) l3 ON l3.recon_date = r.recon_date
LEFT JOIN (
    SELECT
        detected_date AS recon_date,
        COUNT(*) AS anomaly_count,
        COUNT(CASE WHEN severity = 'CRITICAL' THEN 1 END) AS critical_count,
        COUNT(CASE WHEN severity = 'HIGH' THEN 1 END) AS high_count,
        COUNT(CASE WHEN severity = 'MEDIUM' THEN 1 END) AS medium_count,
        COUNT(CASE WHEN severity = 'LOW' THEN 1 END) AS low_count,
        COUNT(CASE WHEN status IN ('OPEN', 'INVESTIGATING') THEN 1 END) AS open_count,
        COUNT(CASE WHEN status = 'RESOLVED' THEN 1 END) AS resolved_count
    FROM recon.dwd_recon_anomalies
    WHERE detected_date >= CURRENT_DATE - 90
    GROUP BY detected_date
) a ON a.recon_date = r.recon_date
GROUP BY r.recon_date,
    l3.l3_total_shops, l3.l3_matched_shops, l3.l3_match_rate_pct, l3.l3_total_variance,
    a.anomaly_count, a.critical_count, a.high_count, a.medium_count, a.low_count,
    a.open_count, a.resolved_count;
```

### 3.2 MV: Anomaly Breakdown by Type

```sql
CREATE MATERIALIZED VIEW recon.mv_recon_anomaly_by_type AS
SELECT
    detected_date,
    anomaly_type,
    severity,
    COUNT(*) AS anomaly_count,
    SUM(CASE WHEN status IN ('OPEN', 'INVESTIGATING') THEN 1 ELSE 0 END) AS open_count,
    SUM(CASE WHEN status = 'RESOLVED' THEN 1 ELSE 0 END) AS resolved_count,
    SUM(CASE WHEN status = 'FALSE_POSITIVE' THEN 1 ELSE 0 END) AS false_positive_count,
    COALESCE(SUM(affected_amount), 0) AS total_affected_amount,
    AVG(confidence_score) AS avg_confidence_score
FROM recon.dwd_recon_anomalies
WHERE detected_date >= CURRENT_DATE - 90
GROUP BY detected_date, anomaly_type, severity;
```

### 3.3 MV: Shop-Level Reconciliation Health

```sql
CREATE MATERIALIZED VIEW recon.mv_recon_shop_health AS
SELECT
    o.shop_id,
    o.recon_date,
    COUNT(DISTINCT o.order_id) AS total_orders,
    SUM(o.order_amount_dollars) AS total_order_amount,
    -- L1 match rate for this shop
    ROUND(100.0 * COUNT(CASE WHEN l1.match_status = 'MATCHED' THEN 1 END)
        / NULLIF(COUNT(*), 0), 2) AS l1_match_rate_pct,
    -- L3 variance for this shop
    l3.variance_amount AS l3_variance,
    l3.match_status AS l3_status,
    -- Anomaly count for this shop
    COALESCE(a.anomaly_count, 0) AS anomaly_count,
    COALESCE(a.critical_count, 0) AS critical_count
FROM recon.stg_recon_orders o
LEFT JOIN recon.stg_recon_level1_results l1
    ON l1.order_id = o.order_id AND l1.recon_date = o.recon_date
LEFT JOIN recon.stg_recon_level3_results l3
    ON l3.shop_id = o.shop_id AND l3.recon_date = o.recon_date
LEFT JOIN (
    SELECT
        shop_id, detected_date,
        COUNT(*) AS anomaly_count,
        COUNT(CASE WHEN severity = 'CRITICAL' THEN 1 END) AS critical_count
    FROM recon.dwd_recon_anomalies
    WHERE detected_date >= CURRENT_DATE - 90
    GROUP BY shop_id, detected_date
) a ON a.shop_id = o.shop_id AND a.detected_date = o.recon_date
WHERE o.recon_date >= CURRENT_DATE - 90
GROUP BY o.shop_id, o.recon_date,
    l3.variance_amount, l3.match_status,
    a.anomaly_count, a.critical_count;
```

### 3.4 View: Open Anomaly Detail (for investigation drill-down)

```sql
CREATE OR REPLACE VIEW recon.v_recon_open_anomalies AS
SELECT
    a.anomaly_id,
    a.anomaly_type,
    a.severity,
    a.status,
    a.detected_date,
    a.order_id,
    a.shop_id,
    a.affected_amount,
    a.expected_value,
    a.actual_value,
    a.confidence_score,
    a.description,
    a.assigned_to,
    a.resolution_notes,
    a.created_at,
    a.updated_at,
    DATEDIFF(day, a.created_at, CURRENT_TIMESTAMP) AS age_days,
    CASE
        WHEN a.severity = 'CRITICAL' AND DATEDIFF(minute, a.created_at, CURRENT_TIMESTAMP) > 30
            THEN 'SLA_BREACHED'
        WHEN a.severity = 'HIGH' AND DATEDIFF(hour, a.created_at, CURRENT_TIMESTAMP) > 4
            THEN 'SLA_BREACHED'
        WHEN a.severity = 'MEDIUM' AND DATEDIFF(hour, a.created_at, CURRENT_TIMESTAMP) > 24
            THEN 'SLA_BREACHED'
        WHEN a.severity = 'LOW' AND DATEDIFF(day, a.created_at, CURRENT_TIMESTAMP) > 1
            THEN 'SLA_BREACHED'
        ELSE 'WITHIN_SLA'
    END AS sla_status
FROM recon.dwd_recon_anomalies a
WHERE a.status IN ('OPEN', 'INVESTIGATING')
ORDER BY
    CASE a.severity
        WHEN 'CRITICAL' THEN 1
        WHEN 'HIGH' THEN 2
        WHEN 'MEDIUM' THEN 3
        WHEN 'LOW' THEN 4
    END,
    a.created_at ASC;
```

### 3.5 View: Pipeline Execution History

```sql
CREATE OR REPLACE VIEW recon.v_recon_pipeline_runs AS
SELECT
    m.recon_date,
    m.pipeline_run_id,
    m.pipeline_start_time,
    m.pipeline_end_time,
    DATEDIFF(second, m.pipeline_start_time, m.pipeline_end_time) AS duration_seconds,
    m.l1_match_rate,
    m.l2_match_rate,
    m.l3_match_rate,
    m.total_orders_processed,
    m.total_anomalies_detected,
    m.dq_checks_passed,
    m.dq_checks_failed,
    CASE
        WHEN DATEDIFF(second, m.pipeline_start_time, m.pipeline_end_time) > 5400
            THEN 'SLA_BREACHED'   -- > 90 min
        WHEN DATEDIFF(second, m.pipeline_start_time, m.pipeline_end_time) > 4200
            THEN 'SLA_WARNING'    -- > 70 min
        ELSE 'WITHIN_SLA'
    END AS pipeline_sla_status,
    m.status AS pipeline_status
FROM recon.dwd_recon_anomaly_metrics m
ORDER BY m.recon_date DESC;
```

### 3.6 View: Weekly / Monthly Aggregates

```sql
CREATE OR REPLACE VIEW recon.v_recon_weekly_summary AS
SELECT
    DATE_TRUNC('week', recon_date)::DATE AS week_start,
    AVG(l1_match_rate_pct) AS avg_l1_match_rate,
    AVG(l2_match_rate_pct) AS avg_l2_match_rate,
    AVG(l3_match_rate_pct) AS avg_l3_match_rate,
    SUM(l1_matched_amount) AS total_matched_revenue,
    SUM(l1_unmatched_amount) AS total_unmatched_revenue,
    SUM(anomaly_count) AS total_anomalies,
    SUM(critical_count) AS total_critical,
    SUM(resolved_count) AS total_resolved,
    ROUND(100.0 * SUM(resolved_count) / NULLIF(SUM(anomaly_count), 0), 2)
        AS resolution_rate_pct
FROM recon.mv_recon_daily_summary
GROUP BY DATE_TRUNC('week', recon_date)::DATE;

CREATE OR REPLACE VIEW recon.v_recon_monthly_summary AS
SELECT
    DATE_TRUNC('month', recon_date)::DATE AS month_start,
    AVG(l1_match_rate_pct) AS avg_l1_match_rate,
    AVG(l2_match_rate_pct) AS avg_l2_match_rate,
    AVG(l3_match_rate_pct) AS avg_l3_match_rate,
    SUM(l1_matched_amount) AS total_matched_revenue,
    SUM(l1_unmatched_amount) AS total_unmatched_revenue,
    SUM(anomaly_count) AS total_anomalies,
    SUM(critical_count) AS total_critical,
    SUM(resolved_count) AS total_resolved,
    ROUND(100.0 * SUM(resolved_count) / NULLIF(SUM(anomaly_count), 0), 2)
        AS resolution_rate_pct
FROM recon.mv_recon_daily_summary
GROUP BY DATE_TRUNC('month', recon_date)::DATE;
```

### 3.7 Materialized View Refresh Schedule

```sql
-- Redshift scheduled query: runs daily at 07:00 UTC
-- Create via Redshift console or AWS CLI
-- Schedule name: recon-mv-refresh

-- Refresh order matters (dependencies):
REFRESH MATERIALIZED VIEW recon.mv_recon_daily_summary;
REFRESH MATERIALIZED VIEW recon.mv_recon_anomaly_by_type;
REFRESH MATERIALIZED VIEW recon.mv_recon_shop_health;
```

---

## 4. Executive Reconciliation Dashboard

### 4.1 Dashboard Layout

```
┌──────────────────────────────────────────────────────────────────────┐
│  Revenue Reconciliation — Executive Overview        [Date Picker]   │
├──────────────────────────────────────────────────────────────────────┤
│                         STAT PANELS (Row 1)                         │
│ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │
│ │ L1 Match │ │ L2 Match │ │ L3 Match │ │  Open    │ │ Revenue  │  │
│ │  Rate    │ │  Rate    │ │  Rate    │ │ Anomalies│ │ at Risk  │  │
│ │  92.3%   │ │  98.1%   │ │  10.2%   │ │    7     │ │ $1,234   │  │
│ │  ▲ +0.4% │ │  ▲ +0.2% │ │  ▼ -1.1% │ │  ▼ -3   │ │  ▼ -$500 │  │
│ └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘  │
├──────────────────────────────────────────────────────────────────────┤
│                     TREND CHARTS (Row 2)                            │
│ ┌────────────────────────────────┐ ┌────────────────────────────┐  │
│ │  Match Rate Trend (30d)        │ │  Anomaly Count Trend (30d) │  │
│ │  ── L1  ── L2  ── L3          │ │  ■ CRIT ■ HIGH ■ MED ■ LOW│  │
│ │                                │ │                            │  │
│ │  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~  │ │  ▁▂▃▄▅▆▇█▇▆▅▄▃▂▁▂▃▄▅▆▇█ │  │
│ └────────────────────────────────┘ └────────────────────────────┘  │
├──────────────────────────────────────────────────────────────────────┤
│                     DETAIL PANELS (Row 3)                           │
│ ┌────────────────────────────────┐ ┌────────────────────────────┐  │
│ │  Revenue by Match Status       │ │  Shop Health Heatmap       │  │
│ │  ■ Matched  ■ Unmatched       │ │  Stores × Days → color by  │  │
│ │  [stacked bar]                 │ │  match rate                │  │
│ └────────────────────────────────┘ └────────────────────────────┘  │
├──────────────────────────────────────────────────────────────────────┤
│                     ANOMALY TABLE (Row 4)                           │
│ ┌────────────────────────────────────────────────────────────────┐  │
│ │ Severity │ Type        │ Shop │ Amount │ Status │ Age │ SLA    │  │
│ │ CRITICAL │ ANO-01 Miss │ S003 │ $89.50 │ OPEN   │ 2h  │ ⚠ WARN│  │
│ │ HIGH     │ ANO-02 Amt  │ S007 │ $12.30 │ INVEST │ 6h  │ ✓ OK  │  │
│ └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

### 4.2 Panel Queries

**Panel: L1 Match Rate (Stat)**
```sql
SELECT l1_match_rate_pct AS "L1 Match Rate"
FROM recon.mv_recon_daily_summary
WHERE recon_date = CURRENT_DATE - 1
ORDER BY recon_date DESC LIMIT 1;
```

**Panel: Revenue at Risk (Stat)**
```sql
SELECT COALESCE(SUM(affected_amount), 0) AS "Revenue at Risk"
FROM recon.dwd_recon_anomalies
WHERE status IN ('OPEN', 'INVESTIGATING')
  AND severity IN ('CRITICAL', 'HIGH');
```

**Panel: Match Rate Trend (Time Series)**
```sql
SELECT
    recon_date AS time,
    l1_match_rate_pct AS "L1 Order↔Payment",
    l2_match_rate_pct AS "L2 Order↔Receipt",
    l3_match_rate_pct AS "L3 Receipt↔Income"
FROM recon.mv_recon_daily_summary
WHERE recon_date >= $__timeFrom()::DATE
  AND recon_date <= $__timeTo()::DATE
ORDER BY recon_date;
```

**Panel: Anomaly Count Trend (Stacked Bar)**
```sql
SELECT
    detected_date AS time,
    SUM(CASE WHEN severity = 'CRITICAL' THEN anomaly_count ELSE 0 END) AS "Critical",
    SUM(CASE WHEN severity = 'HIGH' THEN anomaly_count ELSE 0 END) AS "High",
    SUM(CASE WHEN severity = 'MEDIUM' THEN anomaly_count ELSE 0 END) AS "Medium",
    SUM(CASE WHEN severity = 'LOW' THEN anomaly_count ELSE 0 END) AS "Low"
FROM recon.mv_recon_anomaly_by_type
WHERE detected_date >= $__timeFrom()::DATE
  AND detected_date <= $__timeTo()::DATE
GROUP BY detected_date
ORDER BY detected_date;
```

**Panel: Shop Health Heatmap**
```sql
SELECT
    shop_id,
    recon_date AS time,
    l1_match_rate_pct AS value
FROM recon.mv_recon_shop_health
WHERE recon_date >= $__timeFrom()::DATE
  AND recon_date <= $__timeTo()::DATE
ORDER BY shop_id, recon_date;
```

**Panel: Open Anomalies Table**
```sql
SELECT
    severity,
    anomaly_type AS "Type",
    shop_id AS "Shop",
    affected_amount AS "Amount",
    status AS "Status",
    age_days || 'd' AS "Age",
    sla_status AS "SLA"
FROM recon.v_recon_open_anomalies
LIMIT 20;
```

---

## 5. Operational Monitoring Dashboard

### 5.1 Dashboard Layout

```
┌──────────────────────────────────────────────────────────────────────┐
│  Reconciliation Pipeline — Operational Monitor      [Date Picker]   │
├──────────────────────────────────────────────────────────────────────┤
│ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │
│ │ Pipeline │ │ Duration │ │ Records  │ │ DQ Checks│ │ Dead Ltrs│  │
│ │ Status   │ │ (min)    │ │ Processed│ │ Pass Rate│ │ Count    │  │
│ │ ✓ OK     │ │ 42       │ │ 5,847    │ │ 100%     │ │ 0        │  │
│ └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘  │
├──────────────────────────────────────────────────────────────────────┤
│ ┌────────────────────────────────┐ ┌────────────────────────────┐  │
│ │  Pipeline Duration Trend (30d) │ │  DQ Check Results (7d)     │  │
│ │  ── Duration  ── SLA (70min)  │ │  ■ Pass  ■ Fail            │  │
│ └────────────────────────────────┘ └────────────────────────────┘  │
├──────────────────────────────────────────────────────────────────────┤
│ ┌──────────────────────────────────────────────────────────────┐    │
│ │  Glue Job Phase Breakdown (Gantt-style)                     │    │
│ │  PHASE 1 ████░░░░░░░░░░░░░░░░░░░░░░░░░░  8 min            │    │
│ │  PHASE 2 ░░░░████░░░░░░░░░░░░░░░░░░░░░░  7 min            │    │
│ │  PHASE 3 ░░░░░░░░██████░░░░░░░░░░░░░░░░ 12 min            │    │
│ │  PHASE 4 ░░░░░░░░░░░░░░████░░░░░░░░░░░░  5 min            │    │
│ │  PHASE 5 ░░░░░░░░░░░░░░░░░░██░░░░░░░░░░  3 min            │    │
│ │  PHASE 6 ░░░░░░░░░░░░░░░░░░░░████░░░░░░  7 min            │    │
│ └──────────────────────────────────────────────────────────────┘    │
├──────────────────────────────────────────────────────────────────────┤
│ ┌──────────────────────────────────────────────────────────────┐    │
│ │  Source Extraction Row Counts (per run)                      │    │
│ │  orders | payments | trades | receipts | income_bills | vch  │    │
│ └──────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────┘
```

### 5.2 CloudWatch Metric Queries

**Pipeline Duration (from CloudWatch Glue metrics)**
```
Namespace: Glue
MetricName: glue.driver.aggregate.elapsedTime
Dimensions: JobName = recon-anomaly-scan, Type = gauge
```

**Glue Job Status**
```
Namespace: Glue
MetricName: glue.driver.aggregate.numCompletedStages
Dimensions: JobName = recon-*, Type = gauge
```

### 5.3 Redshift Queries for Ops Dashboard

**Pipeline Run History**
```sql
SELECT
    recon_date,
    pipeline_status,
    duration_seconds / 60.0 AS duration_min,
    total_orders_processed,
    total_anomalies_detected,
    dq_checks_passed,
    dq_checks_failed,
    pipeline_sla_status
FROM recon.v_recon_pipeline_runs
WHERE recon_date >= $__timeFrom()::DATE
ORDER BY recon_date DESC;
```

**Dead Letter Queue Count**
```sql
-- Proxy: count anomalies with status = 'ERROR'
SELECT
    detected_date AS time,
    COUNT(*) AS dead_letter_count
FROM recon.dwd_recon_anomalies
WHERE status = 'ERROR'
  AND detected_date >= $__timeFrom()::DATE
GROUP BY detected_date
ORDER BY detected_date;
```

---

## 6. Anomaly Investigation Dashboard

### 6.1 Dashboard Layout

```
┌──────────────────────────────────────────────────────────────────────┐
│  Anomaly Investigation Workbench                    [Date Picker]   │
│  Filters: [Severity ▼] [Type ▼] [Shop ▼] [Status ▼] [SLA ▼]      │
├──────────────────────────────────────────────────────────────────────┤
│ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌────────────┐  │
│ │ Total Open   │ │ SLA Breached │ │ Avg Age (d)  │ │ False Pos  │  │
│ │     12       │ │      3       │ │    1.4       │ │ Rate: 8%   │  │
│ └──────────────┘ └──────────────┘ └──────────────┘ └────────────┘  │
├──────────────────────────────────────────────────────────────────────┤
│ ┌────────────────────────────────┐ ┌────────────────────────────┐  │
│ │  Anomalies by Type (Pie)       │ │  Resolution Time Dist.     │  │
│ │  ■ ANO-01 Missing Payment 34%  │ │  (histogram, hours)        │  │
│ │  ■ ANO-02 Amount Mismatch 28%  │ │                            │  │
│ │  ■ ANO-03 Fee Anomaly    15%   │ │  ▁▃▇████▇▅▃▂▁             │  │
│ │  ■ Other                 23%   │ │                            │  │
│ └────────────────────────────────┘ └────────────────────────────┘  │
├──────────────────────────────────────────────────────────────────────┤
│ ┌──────────────────────────────────────────────────────────────┐    │
│ │ ANOMALY DETAIL TABLE (sortable, filterable)                 │    │
│ │ ID    │ Type  │ Sev  │ Shop │ Order ID      │ Amt    │ ...  │    │
│ │ A-001 │ ANO-01│ CRIT │ S003 │ 123456789     │ $89.50 │ ...  │    │
│ │ A-002 │ ANO-02│ HIGH │ S007 │ 123456790     │ $12.30 │ ...  │    │
│ │ [Click row for full detail + source data comparison]        │    │
│ └──────────────────────────────────────────────────────────────┘    │
├──────────────────────────────────────────────────────────────────────┤
│ ┌──────────────────────────────────────────────────────────────┐    │
│ │ SELECTED ANOMALY DETAIL (on row click)                      │    │
│ │ ┌──────────────────┐  ┌──────────────────┐                  │    │
│ │ │ Source: Orders    │  │ Source: Payments  │                  │    │
│ │ │ order_id: 123..   │  │ trade_no: TXN..   │                  │    │
│ │ │ amount: $89.50    │  │ amount: (missing)  │                  │    │
│ │ │ pay_time: 14:32   │  │ pay_time: N/A      │                  │    │
│ │ └──────────────────┘  └──────────────────┘                  │    │
│ │ Description: Payment record missing for order 123456789.    │    │
│ │ Recommendation: Check Stripe dashboard for TXN status.      │    │
│ └──────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────┘
```

### 6.2 Key Investigation Queries

**Anomalies by Type (Pie Chart)**
```sql
SELECT
    anomaly_type AS "Type",
    COUNT(*) AS "Count"
FROM recon.dwd_recon_anomalies
WHERE status IN ('OPEN', 'INVESTIGATING')
GROUP BY anomaly_type
ORDER BY "Count" DESC;
```

**SLA Breached Count**
```sql
SELECT COUNT(*) AS sla_breached
FROM recon.v_recon_open_anomalies
WHERE sla_status = 'SLA_BREACHED';
```

**False Positive Rate (30-day rolling)**
```sql
SELECT
    ROUND(100.0 * COUNT(CASE WHEN status = 'FALSE_POSITIVE' THEN 1 END)
        / NULLIF(COUNT(*), 0), 1) AS false_positive_rate_pct
FROM recon.dwd_recon_anomalies
WHERE detected_date >= CURRENT_DATE - 30;
```

**Resolution Time Distribution**
```sql
SELECT
    CASE
        WHEN DATEDIFF(hour, created_at, updated_at) < 1 THEN '< 1h'
        WHEN DATEDIFF(hour, created_at, updated_at) < 4 THEN '1-4h'
        WHEN DATEDIFF(hour, created_at, updated_at) < 24 THEN '4-24h'
        WHEN DATEDIFF(hour, created_at, updated_at) < 72 THEN '1-3d'
        ELSE '> 3d'
    END AS resolution_bucket,
    COUNT(*) AS count
FROM recon.dwd_recon_anomalies
WHERE status IN ('RESOLVED', 'FALSE_POSITIVE')
  AND detected_date >= CURRENT_DATE - 30
GROUP BY 1
ORDER BY
    CASE resolution_bucket
        WHEN '< 1h' THEN 1
        WHEN '1-4h' THEN 2
        WHEN '4-24h' THEN 3
        WHEN '1-3d' THEN 4
        ELSE 5
    END;
```

---

## 7. Scheduled Reports

### 7.1 Daily Reconciliation Report

**Delivery**: 08:00 UTC (03:00 ET) via WeCom + email to finance-ops@luckincoffeeusa.com
**Trigger**: Lambda function `recon-daily-report` on EventBridge cron

**Content Template (WeCom Markdown)**:
```
📊 Daily Revenue Reconciliation Report — {date}

▸ Pipeline Status: {status} ({duration} min)
▸ Orders Processed: {total_orders}

Match Rates:
  L1 Order↔Payment:  {l1_rate}%  ({l1_delta})
  L2 Order↔Receipt:  {l2_rate}%  ({l2_delta})
  L3 Receipt↔Income: {l3_rate}%  ({l3_delta})

Revenue Summary:
  Matched:   ${matched_amount}
  Unmatched: ${unmatched_amount}
  At Risk:   ${risk_amount}

Anomalies:
  New Today:  {new_count} (CRIT: {crit}, HIGH: {high})
  Open Total: {open_count}
  Resolved:   {resolved_count}

{critical_anomaly_list}

Dashboard: https://grafana.luckyus.internal/d/recon-exec
```

**Lambda Function Skeleton**:
```python
# recon-daily-report/lambda_function.py
import boto3
import json
import requests
from datetime import date, timedelta

redshift_client = boto3.client('redshift-data')
WORKGROUP = 'luckyus-recon'
DATABASE = 'analytics'
WECOM_WEBHOOK_WARNING = 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=<WARNING_KEY>'

def lambda_handler(event, context):
    report_date = (date.today() - timedelta(days=1)).isoformat()

    # Query daily summary
    result = execute_redshift_query(f"""
        SELECT * FROM recon.mv_recon_daily_summary
        WHERE recon_date = '{report_date}'
    """)

    # Query critical anomalies
    critical = execute_redshift_query(f"""
        SELECT anomaly_type, shop_id, affected_amount, description
        FROM recon.dwd_recon_anomalies
        WHERE detected_date = '{report_date}'
          AND severity = 'CRITICAL'
          AND status IN ('OPEN', 'INVESTIGATING')
        ORDER BY affected_amount DESC
        LIMIT 5
    """)

    # Format and send
    message = format_report(result, critical, report_date)
    send_wecom(message)
    return {'statusCode': 200}

def execute_redshift_query(sql):
    response = redshift_client.execute_statement(
        WorkgroupName=WORKGROUP,
        Database=DATABASE,
        Sql=sql
    )
    stmt_id = response['Id']
    waiter = redshift_client.get_waiter('statement_finished')
    waiter.wait(Id=stmt_id)
    return redshift_client.get_statement_result(Id=stmt_id)

def send_wecom(message):
    payload = {
        "msgtype": "markdown",
        "markdown": {"content": message}
    }
    requests.post(WECOM_WEBHOOK_WARNING, json=payload)

def format_report(summary, critical, report_date):
    # ... format using template above ...
    pass
```

### 7.2 Weekly Finance Summary

**Delivery**: Monday 09:00 UTC via email (CSV + summary)
**Content**: `recon.v_recon_weekly_summary` for past 4 weeks + trend comparison

### 7.3 Monthly Reconciliation Report

**Delivery**: 2nd business day of month, 09:00 UTC via email (PDF)
**Content**:
- `recon.v_recon_monthly_summary` for the completed month
- Month-over-month trend analysis
- Top 10 anomaly categories with resolution stats
- Shop-level match rate ranking
- Stripe fee analysis (average, outliers)
- Recommendations for process improvement

---

## 8. Grafana Dashboard Definitions

### 8.1 Datasource Configuration

Add Redshift as a Grafana datasource:

| Setting | Value |
|---------|-------|
| Name | `Redshift-Recon` |
| Type | Amazon Redshift |
| Workgroup | `luckyus-recon` |
| Database | `analytics` |
| Schema | `recon` |
| Auth | IAM Role (attached to Grafana EC2/EKS) |
| Default Region | `us-east-1` |

### 8.2 Dashboard Provisioning

Dashboards are provisioned via Grafana API or Terraform. Key settings:

```json
{
  "dashboard": {
    "title": "Revenue Reconciliation — Executive Overview",
    "uid": "recon-exec-overview",
    "tags": ["revenue", "reconciliation", "finance", "UC-FN-02"],
    "timezone": "America/New_York",
    "refresh": "5m",
    "time": {
      "from": "now-7d",
      "to": "now"
    }
  },
  "folderId": 0,
  "folderUid": "recon-exec",
  "overwrite": true
}
```

### 8.3 Alert Rules (Grafana Alerting)

| Alert | Condition | Channel | Severity |
|-------|-----------|---------|----------|
| L1 Match Rate Critical | `l1_match_rate_pct < 90` | `wecom-critical` | CRITICAL |
| L1 Match Rate Warning | `l1_match_rate_pct < 95` | `wecom-warning` | HIGH |
| Pipeline SLA Breach | `duration_seconds > 5400` (90 min) | `wecom-critical` | CRITICAL |
| Pipeline SLA Warning | `duration_seconds > 4200` (70 min) | `wecom-warning` | HIGH |
| Anomaly Spike | `anomaly_count > 2× 30d_avg` | `wecom-warning` | HIGH |
| Critical Anomaly Detected | `critical_count > 0` | `wecom-critical` | CRITICAL |
| Dead Letter Queue Non-Empty | `dead_letter_count > 0` | `wecom-warning` | MEDIUM |
| MV Refresh Failure | CloudWatch alarm on Lambda error | `wecom-critical` | HIGH |

---

## 9. Infrastructure Deployment Guide

### 9.1 Deployment Order (Critical Path)

```
Step 1:  IAM Roles & Policies           (Section 10)
Step 2:  S3 Bucket & Folder Structure   (Section 9.2)
Step 3:  DynamoDB Watermark Table        (Section 9.3)
Step 4:  SSM Parameter Store Entries     (Appendix B)
Step 5:  Redshift Schema & Tables        (Section 12)
Step 6:  Redshift Views & MVs            (Section 3)
Step 7:  Glue Connections                (Section 11.1)
Step 8:  Glue Jobs (6 phases)            (Section 11.2)
Step 9:  Glue Workflow & Triggers        (Section 11.3)
Step 10: Grafana Datasource              (Section 8.1)
Step 11: Grafana Dashboards              (Section 8.2)
Step 12: Grafana Alert Rules             (Section 8.3)
Step 13: Lambda Report Function          (Section 7.1)
Step 14: CloudWatch Alarms               (Section 13)
Step 15: Validation & Smoke Test         (Section 15)
```

### 9.2 S3 Bucket Structure

```
s3://luckyus-data-lake/
├── staging/
│   └── reconciliation/
│       ├── stg_recon_orders/dt=YYYY-MM-DD/
│       ├── stg_recon_payments/dt=YYYY-MM-DD/
│       ├── stg_recon_trades/dt=YYYY-MM-DD/
│       ├── stg_recon_receipts/dt=YYYY-MM-DD/
│       ├── stg_recon_income_bills/dt=YYYY-MM-DD/
│       ├── stg_recon_vouchers/dt=YYYY-MM-DD/
│       ├── dead-letter/dt=YYYY-MM-DD/
│       └── checkpoints/
├── scripts/
│   └── glue/
│       └── recon/
│           ├── recon_extract.py
│           ├── recon_standardize.py
│           ├── recon_match_l1.py
│           ├── recon_match_l2.py
│           ├── recon_match_l3.py
│           └── recon_anomaly_scan.py
└── logs/
    └── glue/
        └── recon/
```

### 9.3 DynamoDB Watermark Table

```
Table Name: recon-etl-watermarks
Partition Key: source_name (String)
Sort Key: table_name (String)

Items:
| source_name    | table_name        | last_extracted_at       | last_id    | row_count |
|----------------|-------------------|-------------------------|------------|-----------|
| salesorder     | t_order           | 2026-02-15T06:00:00Z    | 12345678   | 466000    |
| salespayment   | t_order_pay       | 2026-02-15T06:00:00Z    | 9876543    | 460000    |
| salespayment   | t_trade           | 2026-02-15T06:00:00Z    | 8765432    | 455000    |
| ifiaccounting  | t_receipt          | 2026-02-15T06:00:00Z    | 7654321    | 450000    |
| ifiaccounting  | t_income_bill      | 2026-02-15T06:00:00Z    | 6543210    | 12000     |
| iunifiedreconcile | t_reconcile_voucher | 2026-02-15T06:00:00Z | 5432109    | 440000    |
```

### 9.4 Network Configuration

| Resource | VPC | Subnets | Security Groups |
|----------|-----|---------|-----------------|
| Glue Jobs | `vpc-luckyus-prod` | Private subnets (AZ a, b) | `sg-glue-recon` (outbound to RDS, S3, Redshift) |
| Redshift Serverless | `vpc-luckyus-prod` | Private subnets (AZ a, b) | `sg-redshift-recon` (inbound from Glue, Grafana, Lambda) |
| Lambda Reports | `vpc-luckyus-prod` | Private subnets (AZ a, b) | `sg-lambda-recon` (outbound to Redshift, WeCom) |
| Grafana | Existing deployment | Existing | Add inbound from `sg-redshift-recon` |

---

## 10. IAM Roles & Permissions

### 10.1 Glue Execution Role

```json
{
  "RoleName": "role-glue-recon-pipeline",
  "AssumeRolePolicyDocument": {
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "glue.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  },
  "Policies": [
    {
      "PolicyName": "recon-glue-s3-access",
      "PolicyDocument": {
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
            "Resource": [
              "arn:aws:s3:::luckyus-data-lake",
              "arn:aws:s3:::luckyus-data-lake/staging/reconciliation/*",
              "arn:aws:s3:::luckyus-data-lake/scripts/glue/recon/*",
              "arn:aws:s3:::luckyus-data-lake/logs/glue/recon/*"
            ]
          }
        ]
      }
    },
    {
      "PolicyName": "recon-glue-redshift-access",
      "PolicyDocument": {
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Action": [
              "redshift-serverless:GetCredentials",
              "redshift-data:ExecuteStatement",
              "redshift-data:DescribeStatement",
              "redshift-data:GetStatementResult",
              "redshift-data:BatchExecuteStatement"
            ],
            "Resource": "*"
          }
        ]
      }
    },
    {
      "PolicyName": "recon-glue-dynamodb-watermarks",
      "PolicyDocument": {
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Action": ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:Query"],
            "Resource": "arn:aws:dynamodb:us-east-1:*:table/recon-etl-watermarks"
          }
        ]
      }
    },
    {
      "PolicyName": "recon-glue-ssm-params",
      "PolicyDocument": {
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Action": ["ssm:GetParameter", "ssm:GetParametersByPath"],
            "Resource": "arn:aws:ssm:us-east-1:*:parameter/recon/*"
          }
        ]
      }
    },
    {
      "PolicyName": "recon-glue-secrets",
      "PolicyDocument": {
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Action": ["secretsmanager:GetSecretValue"],
            "Resource": [
              "arn:aws:secretsmanager:us-east-1:*:secret:rds/salesorder/*",
              "arn:aws:secretsmanager:us-east-1:*:secret:rds/salespayment/*",
              "arn:aws:secretsmanager:us-east-1:*:secret:rds/ifiaccounting/*",
              "arn:aws:secretsmanager:us-east-1:*:secret:rds/iunifiedreconcile/*"
            ]
          }
        ]
      }
    },
    {
      "PolicyName": "recon-glue-logging",
      "PolicyDocument": {
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Action": [
              "logs:CreateLogGroup",
              "logs:CreateLogStream",
              "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:us-east-1:*:log-group:/aws-glue/recon-*"
          },
          {
            "Effect": "Allow",
            "Action": [
              "cloudwatch:PutMetricData"
            ],
            "Resource": "*",
            "Condition": {
              "StringEquals": {
                "cloudwatch:namespace": "Recon/Pipeline"
              }
            }
          }
        ]
      }
    }
  ],
  "ManagedPolicies": [
    "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
  ]
}
```

### 10.2 Lambda Report Role

```json
{
  "RoleName": "role-lambda-recon-reports",
  "AssumeRolePolicyDocument": {
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "lambda.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  },
  "Policies": [
    {
      "PolicyName": "recon-lambda-redshift",
      "PolicyDocument": {
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Action": [
              "redshift-serverless:GetCredentials",
              "redshift-data:ExecuteStatement",
              "redshift-data:DescribeStatement",
              "redshift-data:GetStatementResult"
            ],
            "Resource": "*"
          }
        ]
      }
    },
    {
      "PolicyName": "recon-lambda-ses",
      "PolicyDocument": {
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Action": ["ses:SendEmail", "ses:SendRawEmail"],
            "Resource": "*"
          }
        ]
      }
    }
  ],
  "ManagedPolicies": [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  ]
}
```

### 10.3 Redshift Serverless Namespace Role

```json
{
  "RoleName": "role-redshift-recon-namespace",
  "AssumeRolePolicyDocument": {
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "redshift.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  },
  "Policies": [
    {
      "PolicyName": "recon-redshift-s3-read",
      "PolicyDocument": {
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Action": ["s3:GetObject", "s3:ListBucket"],
            "Resource": [
              "arn:aws:s3:::luckyus-data-lake",
              "arn:aws:s3:::luckyus-data-lake/staging/reconciliation/*"
            ]
          }
        ]
      }
    }
  ]
}
```

---

## 11. Glue Job Deployment

### 11.1 Glue Connections

Create JDBC connections for each MySQL source:

| Connection Name | JDBC URL | Secret |
|----------------|----------|--------|
| `recon-conn-salesorder` | `jdbc:mysql://aws-luckyus-salesorder-rw:3306/salesorder` | `rds/salesorder/recon` |
| `recon-conn-salespayment` | `jdbc:mysql://aws-luckyus-salespayment-rw:3306/salespayment` | `rds/salespayment/recon` |
| `recon-conn-ifiaccounting` | `jdbc:mysql://aws-luckyus-ifiaccounting-rw:3306/ifiaccounting` | `rds/ifiaccounting/recon` |
| `recon-conn-iunifiedreconcile` | `jdbc:mysql://aws-luckyus-iunifiedreconcile-rw:3306/iunifiedreconcile` | `rds/iunifiedreconcile/recon` |

### 11.2 Glue Job Definitions

| Job Name | Phase | Script | Workers | Timeout (min) | Connections |
|----------|-------|--------|---------|---------------|-------------|
| `recon-extract-orders` | 1 | `recon_extract.py` | 2 G.1X | 15 | `recon-conn-salesorder` |
| `recon-extract-payments` | 1 | `recon_extract.py` | 2 G.1X | 15 | `recon-conn-salespayment` |
| `recon-extract-accounting` | 1 | `recon_extract.py` | 2 G.1X | 15 | `recon-conn-ifiaccounting` |
| `recon-extract-reconcile` | 1 | `recon_extract.py` | 2 G.1X | 15 | `recon-conn-iunifiedreconcile` |
| `recon-standardize` | 2 | `recon_standardize.py` | 2 G.1X | 10 | — |
| `recon-match-l1` | 3 | `recon_match_l1.py` | 2 G.1X | 10 | — |
| `recon-match-l2` | 4 | `recon_match_l2.py` | 2 G.1X | 10 | — |
| `recon-match-l3` | 5 | `recon_match_l3.py` | 2 G.1X | 10 | — |
| `recon-anomaly-scan` | 6 | `recon_anomaly_scan.py` | 2 G.1X | 15 | — |

Common job parameters:
```json
{
  "--job-language": "python",
  "--TempDir": "s3://luckyus-data-lake/logs/glue/recon/temp/",
  "--enable-metrics": "true",
  "--enable-continuous-cloudwatch-log": "true",
  "--enable-spark-ui": "true",
  "--spark-event-logs-path": "s3://luckyus-data-lake/logs/glue/recon/spark-ui/",
  "--additional-python-modules": "boto3>=1.28.0",
  "--conf": "spark.sql.parquet.writeLegacyFormat=true",
  "--RECON_DATE": "",
  "--S3_STAGING_PATH": "s3://luckyus-data-lake/staging/reconciliation/",
  "--WATERMARK_TABLE": "recon-etl-watermarks"
}
```

### 11.3 Glue Workflow Definition

```
Workflow: recon-daily-pipeline
Schedule: cron(0 6 * * ? *)   -- Daily 06:00 UTC (01:00 ET)

Trigger: recon-trigger-start (SCHEDULED)
  └─► Jobs: recon-extract-orders
            recon-extract-payments      (parallel)
            recon-extract-accounting
            recon-extract-reconcile

Trigger: recon-trigger-after-extract (CONDITIONAL: all 4 extracts SUCCEEDED)
  └─► Job:  recon-standardize

Trigger: recon-trigger-after-standardize (CONDITIONAL: standardize SUCCEEDED)
  └─► Job:  recon-match-l1

Trigger: recon-trigger-after-l1 (CONDITIONAL: match-l1 SUCCEEDED)
  └─► Job:  recon-match-l2

Trigger: recon-trigger-after-l2 (CONDITIONAL: match-l2 SUCCEEDED)
  └─► Job:  recon-match-l3

Trigger: recon-trigger-after-l3 (CONDITIONAL: match-l3 SUCCEEDED)
  └─► Job:  recon-anomaly-scan
```

---

## 12. Redshift Schema Deployment

### 12.1 Deployment Script Order

Execute these SQL scripts in order on Redshift Serverless (`analytics` database):

```sql
-- Step 1: Create schema
CREATE SCHEMA IF NOT EXISTS recon;

-- Step 2: Staging tables (from Phase 2)
-- stg_recon_orders, stg_recon_payments, stg_recon_trades,
-- stg_recon_receipts, stg_recon_income_bills
-- (DDL defined in Phase 2, Section 4)

-- Step 3: Voucher staging table (from Phase 3)
-- stg_recon_vouchers
-- (DDL defined in Phase 3, Section 3.6)

-- Step 4: Match result tables (from Phase 2)
-- stg_recon_level1_results, stg_recon_level2_results, stg_recon_level3_results
-- (DDL defined in Phase 2, Sections 5-7)

-- Step 5: DW fact tables (from Phase 2)
-- dwd_two_way_reconciliation, dwd_two_way_reconciliation_detail
-- (DDL defined in Phase 2)

-- Step 6: Anomaly tables (from Phase 3)
-- dwd_recon_anomalies, dwd_recon_anomaly_summary, dwd_recon_anomaly_metrics
-- (DDL defined in Phase 3, Section 3)

-- Step 7: Reporting views (this document, Section 3)
-- mv_recon_daily_summary, mv_recon_anomaly_by_type, mv_recon_shop_health
-- v_recon_open_anomalies, v_recon_pipeline_runs
-- v_recon_weekly_summary, v_recon_monthly_summary
```

### 12.2 Redshift Scheduled Query for MV Refresh

```sql
-- Create via Redshift console: Query Scheduler
-- Schedule name: recon-mv-refresh
-- Schedule: cron(0 7 * * ? *)    -- Daily 07:00 UTC

REFRESH MATERIALIZED VIEW recon.mv_recon_daily_summary;
REFRESH MATERIALIZED VIEW recon.mv_recon_anomaly_by_type;
REFRESH MATERIALIZED VIEW recon.mv_recon_shop_health;
```

### 12.3 Redshift User & Grants

```sql
-- Create a service user for Grafana read-only access
CREATE USER grafana_recon PASSWORD DISABLE;
GRANT USAGE ON SCHEMA recon TO grafana_recon;
GRANT SELECT ON ALL TABLES IN SCHEMA recon TO grafana_recon;
ALTER DEFAULT PRIVILEGES IN SCHEMA recon GRANT SELECT ON TABLES TO grafana_recon;

-- Create a service user for Glue ETL write access
CREATE USER glue_recon PASSWORD DISABLE;
GRANT USAGE ON SCHEMA recon TO glue_recon;
GRANT ALL ON ALL TABLES IN SCHEMA recon TO glue_recon;
ALTER DEFAULT PRIVILEGES IN SCHEMA recon GRANT ALL ON TABLES TO glue_recon;

-- Create a service user for Lambda reports
CREATE USER lambda_recon PASSWORD DISABLE;
GRANT USAGE ON SCHEMA recon TO lambda_recon;
GRANT SELECT ON ALL TABLES IN SCHEMA recon TO lambda_recon;
ALTER DEFAULT PRIVILEGES IN SCHEMA recon GRANT SELECT ON TABLES TO lambda_recon;
```

---

## 13. CloudWatch Monitoring Setup

### 13.1 Custom Metrics (Published by Glue Jobs)

| Namespace | Metric | Dimensions | Unit | Description |
|-----------|--------|------------|------|-------------|
| `Recon/Pipeline` | `PipelineDuration` | `Stage=FULL` | Seconds | Total pipeline runtime |
| `Recon/Pipeline` | `PhaseDuration` | `Phase=1..6` | Seconds | Per-phase runtime |
| `Recon/Pipeline` | `RecordsExtracted` | `Source=orders\|payments\|...` | Count | Rows extracted per source |
| `Recon/Pipeline` | `MatchRate` | `Level=L1\|L2\|L3` | Percent | Match rate per level |
| `Recon/Pipeline` | `AnomalyCount` | `Severity=CRITICAL\|HIGH\|...` | Count | Anomalies detected |
| `Recon/Pipeline` | `DeadLetterCount` | — | Count | Records sent to dead letter |
| `Recon/Pipeline` | `DQChecksFailed` | — | Count | Data quality check failures |

### 13.2 CloudWatch Alarms

```yaml
# alarm-recon-pipeline-duration.yaml
AlarmName: recon-pipeline-duration-critical
Namespace: Recon/Pipeline
MetricName: PipelineDuration
Dimensions:
  - Name: Stage
    Value: FULL
Statistic: Maximum
Period: 86400        # 1 day
EvaluationPeriods: 1
Threshold: 5400      # 90 min in seconds
ComparisonOperator: GreaterThanThreshold
AlarmActions:
  - arn:aws:sns:us-east-1:ACCOUNT:recon-alerts-critical
TreatMissingData: breaching

---
AlarmName: recon-pipeline-duration-warning
Namespace: Recon/Pipeline
MetricName: PipelineDuration
Dimensions:
  - Name: Stage
    Value: FULL
Statistic: Maximum
Period: 86400
EvaluationPeriods: 1
Threshold: 4200      # 70 min
ComparisonOperator: GreaterThanThreshold
AlarmActions:
  - arn:aws:sns:us-east-1:ACCOUNT:recon-alerts-warning
TreatMissingData: breaching

---
AlarmName: recon-l1-match-rate-critical
Namespace: Recon/Pipeline
MetricName: MatchRate
Dimensions:
  - Name: Level
    Value: L1
Statistic: Minimum
Period: 86400
EvaluationPeriods: 1
Threshold: 90
ComparisonOperator: LessThanThreshold
AlarmActions:
  - arn:aws:sns:us-east-1:ACCOUNT:recon-alerts-critical
TreatMissingData: breaching

---
AlarmName: recon-anomaly-critical-detected
Namespace: Recon/Pipeline
MetricName: AnomalyCount
Dimensions:
  - Name: Severity
    Value: CRITICAL
Statistic: Sum
Period: 86400
EvaluationPeriods: 1
Threshold: 0
ComparisonOperator: GreaterThanThreshold
AlarmActions:
  - arn:aws:sns:us-east-1:ACCOUNT:recon-alerts-critical

---
AlarmName: recon-glue-job-failure
Namespace: AWS/Glue
MetricName: glue.driver.aggregate.numFailedTasks
Dimensions:
  - Name: JobName
    Value: recon-*
Statistic: Sum
Period: 3600
EvaluationPeriods: 1
Threshold: 0
ComparisonOperator: GreaterThanThreshold
AlarmActions:
  - arn:aws:sns:us-east-1:ACCOUNT:recon-alerts-critical
```

### 13.3 SNS Topics for Alert Routing

| Topic | Subscriptions |
|-------|--------------|
| `recon-alerts-critical` | WeCom webhook (`wecom-critical`), PagerDuty, email: dba-team@luckincoffeeusa.com |
| `recon-alerts-warning` | WeCom webhook (`wecom-warning`), email: finance-ops@luckincoffeeusa.com |
| `recon-alerts-info` | Email: finance-ops@luckincoffeeusa.com |

---

## 14. Operational Runbook

### 14.1 Daily Operations Checklist (08:00 ET)

```
□  1. Check pipeline status in Grafana (Operational Monitoring dashboard)
       → Pipeline completed? Duration within SLA?
□  2. Review daily WeCom report (sent at 03:00 ET)
       → Match rates within normal range?
       → Any CRITICAL anomalies?
□  3. Check open anomalies (Anomaly Investigation dashboard)
       → Any SLA-breached anomalies? Escalate if so.
□  4. Verify MV refresh completed (Redshift query editor)
       → SELECT MAX(recon_date) FROM recon.mv_recon_daily_summary;
       → Should equal yesterday's date
□  5. Check dead letter queue
       → S3: s3://luckyus-data-lake/staging/reconciliation/dead-letter/
       → Any files for today's date? Investigate if so.
```

### 14.2 Pipeline Failure Troubleshooting

```
SYMPTOM: Pipeline did not run (no data for today)
─────────────────────────────────────────────────
1. Check Glue Workflow status:
   AWS Console → Glue → Workflows → recon-daily-pipeline
   - Was the trigger fired? Check CloudWatch Events
   - Is any job stuck in RUNNING state?

2. Check for Glue service issues:
   AWS Health Dashboard → Glue in us-east-1

3. Manual trigger:
   aws glue start-workflow-run --name recon-daily-pipeline

SYMPTOM: Extraction job failed
─────────────────────────────────────────────────
1. Check CloudWatch Logs:
   /aws-glue/recon-extract-{source}
   Look for: connection errors, timeout, authentication

2. Verify MySQL source availability:
   SELECT 1 FROM dual;  -- on aws-luckyus-{source}-rw

3. Check DynamoDB watermark:
   aws dynamodb get-item --table-name recon-etl-watermarks \
     --key '{"source_name":{"S":"{source}"},"table_name":{"S":"{table}"}}'

4. Re-run individual extraction:
   aws glue start-job-run --job-name recon-extract-{source} \
     --arguments '{"--RECON_DATE":"YYYY-MM-DD"}'

SYMPTOM: Match rate below threshold
─────────────────────────────────────────────────
1. Check staging table row counts:
   SELECT COUNT(*) FROM recon.stg_recon_orders WHERE recon_date = 'YYYY-MM-DD';
   SELECT COUNT(*) FROM recon.stg_recon_payments WHERE recon_date = 'YYYY-MM-DD';
   → Significant difference? Extraction may have missed records.

2. Check for currency contamination:
   SELECT currency, COUNT(*) FROM recon.stg_recon_orders
   WHERE recon_date = 'YYYY-MM-DD' GROUP BY currency;
   → NZD records should be 0 (filtered in extraction)

3. Check for duplicate order IDs:
   SELECT order_id, COUNT(*) FROM recon.stg_recon_orders
   WHERE recon_date = 'YYYY-MM-DD' GROUP BY order_id HAVING COUNT(*) > 1;

4. Compare with source directly:
   SELECT COUNT(*) FROM salesorder.t_order
   WHERE DATE(create_time) = 'YYYY-MM-DD' AND currency = 'USD';

SYMPTOM: Anomaly scan job timed out (>15 min)
─────────────────────────────────────────────────
1. Check Spark UI for the job run (link in Glue console)
   → Which stage is slow? Data skew?

2. Check data volume:
   SELECT COUNT(*) FROM recon.stg_recon_level1_results WHERE recon_date = 'YYYY-MM-DD';
   → Unusual spike in records?

3. Consider scaling:
   Increase worker count from 2 to 4 G.1X for anomaly scan job

4. Check for DynamoDB throttling:
   CloudWatch → DynamoDB → recon-etl-watermarks → ThrottledRequests
```

### 14.3 Anomaly Resolution Workflow

```
1. TRIAGE (Finance Ops)
   └─► Open Anomaly Investigation dashboard
   └─► Filter by severity (CRITICAL first)
   └─► For each anomaly:
       a. Review source data comparison panel
       b. Determine: real issue or false positive?

2. INVESTIGATE (if real issue)
   └─► Check Stripe dashboard for payment status
   └─► Check source MySQL tables for data consistency
   └─► Query: SELECT * FROM salespayment.t_trade
               WHERE order_id = '{order_id}';
   └─► Document findings in resolution_notes

3. RESOLVE
   └─► Update anomaly status in Redshift:
       UPDATE recon.dwd_recon_anomalies
       SET status = 'RESOLVED',
           resolution_notes = '{notes}',
           assigned_to = '{name}',
           updated_at = CURRENT_TIMESTAMP
       WHERE anomaly_id = '{id}';

4. FALSE POSITIVE
   └─► Update status to FALSE_POSITIVE with explanation
   └─► If recurring pattern, add to threshold tuning backlog
```

### 14.4 Backfill Procedure

```bash
# Re-run pipeline for a specific historical date
# This will overwrite existing data for that date

# Step 1: Set the target date
RECON_DATE="2026-02-10"

# Step 2: Clear existing staging data for that date
aws s3 rm s3://luckyus-data-lake/staging/reconciliation/stg_recon_orders/dt=${RECON_DATE}/ --recursive
aws s3 rm s3://luckyus-data-lake/staging/reconciliation/stg_recon_payments/dt=${RECON_DATE}/ --recursive
aws s3 rm s3://luckyus-data-lake/staging/reconciliation/stg_recon_trades/dt=${RECON_DATE}/ --recursive
aws s3 rm s3://luckyus-data-lake/staging/reconciliation/stg_recon_receipts/dt=${RECON_DATE}/ --recursive
aws s3 rm s3://luckyus-data-lake/staging/reconciliation/stg_recon_income_bills/dt=${RECON_DATE}/ --recursive
aws s3 rm s3://luckyus-data-lake/staging/reconciliation/stg_recon_vouchers/dt=${RECON_DATE}/ --recursive

# Step 3: Clear Redshift data for that date
# (Run via Redshift query editor)
# DELETE FROM recon.stg_recon_orders WHERE recon_date = '2026-02-10';
# DELETE FROM recon.stg_recon_payments WHERE recon_date = '2026-02-10';
# ... (all staging, result, and anomaly tables)

# Step 4: Trigger workflow with date override
aws glue start-workflow-run --name recon-daily-pipeline \
  --run-properties '{"--RECON_DATE":"2026-02-10"}'

# Step 5: Monitor progress
aws glue get-workflow-run --name recon-daily-pipeline --run-id <RUN_ID>

# Step 6: After completion, refresh MVs
# REFRESH MATERIALIZED VIEW recon.mv_recon_daily_summary;
# REFRESH MATERIALIZED VIEW recon.mv_recon_anomaly_by_type;
# REFRESH MATERIALIZED VIEW recon.mv_recon_shop_health;
```

### 14.5 Threshold Tuning

After 30 days of operation, review and tune detection thresholds:

```sql
-- Check false positive rate by anomaly type
SELECT
    anomaly_type,
    COUNT(*) AS total,
    COUNT(CASE WHEN status = 'FALSE_POSITIVE' THEN 1 END) AS false_positives,
    ROUND(100.0 * COUNT(CASE WHEN status = 'FALSE_POSITIVE' THEN 1 END) / COUNT(*), 1)
        AS fp_rate_pct
FROM recon.dwd_recon_anomalies
WHERE detected_date >= CURRENT_DATE - 30
GROUP BY anomaly_type
ORDER BY fp_rate_pct DESC;

-- Target: < 10% false positive rate per type
-- If FP rate > 20%: widen tolerance thresholds
-- If FP rate < 2% and volume low: tighten thresholds to catch more
```

Threshold adjustment via SSM Parameter Store:
```bash
# Example: widen L1 amount tolerance from 0.01 to 0.05
aws ssm put-parameter \
  --name "/recon/thresholds/l1_amount_tolerance" \
  --value "0.05" \
  --type String \
  --overwrite

# Changes take effect on next pipeline run (no restart needed)
```

---

## 15. Go-Live Checklist

### Phase A: Infrastructure Provisioning

```
□ A.1  IAM roles created (Section 10)
       □ role-glue-recon-pipeline
       □ role-lambda-recon-reports
       □ role-redshift-recon-namespace
□ A.2  S3 bucket structure created (Section 9.2)
       □ staging/reconciliation/ with all 7 subfolders
       □ scripts/glue/recon/ with all 6 PySpark scripts
       □ logs/glue/recon/
□ A.3  DynamoDB table created (Section 9.3)
       □ recon-etl-watermarks with initial items
□ A.4  SSM parameters populated (Appendix B)
       □ All 30+ threshold parameters
□ A.5  Secrets Manager entries created
       □ 4 RDS connection secrets (read-only credentials)
□ A.6  Security groups configured (Section 9.4)
       □ sg-glue-recon
       □ sg-redshift-recon
       □ sg-lambda-recon
```

### Phase B: Data Platform

```
□ B.1  Redshift schema created
       □ CREATE SCHEMA recon;
□ B.2  All 6 staging tables created (Phase 2 DDL)
□ B.3  All 3 match result tables created (Phase 2 DDL)
□ B.4  All 2 DW fact tables created (Phase 2 DDL)
□ B.5  All 3 anomaly tables created (Phase 3 DDL)
□ B.6  All 3 materialized views created (Section 3)
□ B.7  All 4 views created (Section 3)
□ B.8  Redshift users and grants applied (Section 12.3)
□ B.9  MV refresh scheduled query created (Section 12.2)
```

### Phase C: ETL Pipeline

```
□ C.1  Glue connections created and tested (Section 11.1)
       □ recon-conn-salesorder — connection test passed
       □ recon-conn-salespayment — connection test passed
       □ recon-conn-ifiaccounting — connection test passed
       □ recon-conn-iunifiedreconcile — connection test passed
□ C.2  Glue jobs created (Section 11.2)
       □ All 9 jobs created with correct parameters
       □ Scripts uploaded to S3
□ C.3  Glue workflow created (Section 11.3)
       □ recon-daily-pipeline workflow
       □ All 6 triggers configured
       □ Schedule set to cron(0 6 * * ? *)
```

### Phase D: Monitoring & Alerting

```
□ D.1  SNS topics created (Section 13.3)
       □ recon-alerts-critical with subscriptions
       □ recon-alerts-warning with subscriptions
       □ recon-alerts-info with subscriptions
□ D.2  CloudWatch alarms created (Section 13.2)
       □ Pipeline duration (critical + warning)
       □ L1 match rate critical
       □ Anomaly critical detected
       □ Glue job failure
□ D.3  Grafana datasource configured (Section 8.1)
       □ Redshift-Recon datasource — test passed
□ D.4  Grafana dashboards deployed (Section 8.2)
       □ Executive Overview
       □ Operational Monitoring
       □ Anomaly Investigation
□ D.5  Grafana alert rules created (Section 8.3)
□ D.6  Lambda report function deployed (Section 7.1)
       □ EventBridge cron rule created
       □ Test invocation successful
```

### Phase E: Validation

```
□ E.1  Smoke Test — Manual Pipeline Run
       □ Trigger: aws glue start-workflow-run --name recon-daily-pipeline
       □ All 6 phases complete within SLA
       □ Staging tables populated with correct row counts
       □ Match rates within expected ranges
       □ Anomaly detection produces results (even if zero anomalies)
       □ MVs refreshed successfully
       □ Dashboards display data correctly
□ E.2  Backfill Test
       □ Run backfill for T-7 through T-1 (7 days)
       □ Verify trend charts populate correctly
□ E.3  Alert Test
       □ Trigger test CRITICAL anomaly → verify WeCom notification
       □ Trigger pipeline over SLA → verify CloudWatch alarm
□ E.4  Report Test
       □ Manual Lambda invocation → verify WeCom report delivery
       □ Verify report content accuracy against dashboard
□ E.5  Failover Test
       □ Simulate extraction failure → verify dead letter queue
       □ Simulate Redshift unavailability → verify Glue error handling
□ E.6  Documentation Review
       □ Runbook walkthrough with DBA team
       □ Anomaly resolution workflow walkthrough with Finance Ops
```

### Phase F: Go-Live

```
□ F.1  Enable Glue Workflow schedule (currently paused)
□ F.2  Confirm first automated run completes (next 06:00 UTC)
□ F.3  Verify daily report received at 08:00 UTC
□ F.4  Monitor for 5 consecutive successful runs
□ F.5  Sign-off from Finance Ops lead
□ F.6  Sign-off from DBA team lead
□ F.7  Update project status: UC-FN-02 → PRODUCTION
```

---

## 16. Rollback Procedures

### 16.1 Full Rollback (Decommission Pipeline)

```bash
# Step 1: Disable workflow schedule
aws glue stop-trigger --name recon-trigger-start

# Step 2: Stop any running workflow
aws glue stop-workflow-run --name recon-daily-pipeline --run-id <RUN_ID>

# Step 3: Disable CloudWatch alarms
aws cloudwatch disable-alarm-actions \
  --alarm-names recon-pipeline-duration-critical \
                recon-pipeline-duration-warning \
                recon-l1-match-rate-critical \
                recon-anomaly-critical-detected \
                recon-glue-job-failure

# Step 4: Disable Lambda report schedule
aws events disable-rule --name recon-daily-report-schedule

# Step 5: (Optional) Delete Grafana dashboards
# Only if fully decommissioning — keep for post-mortem analysis

# Data is preserved in S3 and Redshift for audit purposes.
# Do NOT delete S3 data or Redshift tables during rollback.
```

### 16.2 Partial Rollback (Disable Specific Phase)

```bash
# Disable only anomaly detection (Phase 6)
# Edit trigger to remove recon-anomaly-scan from workflow

# Disable only alerting
aws cloudwatch disable-alarm-actions \
  --alarm-names recon-anomaly-critical-detected

# Disable only reports
aws events disable-rule --name recon-daily-report-schedule
```

### 16.3 Data Rollback (Revert to Previous Day)

```sql
-- Revert anomaly data for a specific date
DELETE FROM recon.dwd_recon_anomalies WHERE detected_date = '2026-02-16';
DELETE FROM recon.dwd_recon_anomaly_summary WHERE summary_date = '2026-02-16';

-- Revert match results
DELETE FROM recon.stg_recon_level1_results WHERE recon_date = '2026-02-16';
DELETE FROM recon.stg_recon_level2_results WHERE recon_date = '2026-02-16';
DELETE FROM recon.stg_recon_level3_results WHERE recon_date = '2026-02-16';

-- Refresh MVs
REFRESH MATERIALIZED VIEW recon.mv_recon_daily_summary;
REFRESH MATERIALIZED VIEW recon.mv_recon_anomaly_by_type;
REFRESH MATERIALIZED VIEW recon.mv_recon_shop_health;
```

---

## Appendix A — Complete Table Inventory

### All Redshift Tables & Views (UC-FN-02)

| # | Object Name | Type | Defined In | Purpose |
|---|-------------|------|------------|---------|
| 1 | `stg_recon_orders` | Table | Phase 2 §4 | Standardized orders (salesorder.t_order) |
| 2 | `stg_recon_payments` | Table | Phase 2 §4 | Standardized payments (salespayment.t_order_pay) |
| 3 | `stg_recon_trades` | Table | Phase 2 §4 | Standardized trades (salespayment.t_trade) |
| 4 | `stg_recon_receipts` | Table | Phase 2 §4 | Standardized receipts (ifiaccounting.t_receipt) |
| 5 | `stg_recon_income_bills` | Table | Phase 2 §4 | Standardized income bills (ifiaccounting.t_income_bill) |
| 6 | `stg_recon_vouchers` | Table | Phase 3 §3.6 | Standardized vouchers (iunifiedreconcile.t_reconcile_voucher) |
| 7 | `stg_recon_level1_results` | Table | Phase 2 §5 | L1 Order↔Payment match results |
| 8 | `stg_recon_level2_results` | Table | Phase 2 §6 | L2 Order↔Receipt match results |
| 9 | `stg_recon_level3_results` | Table | Phase 2 §7 | L3 Receipt↔Income Bill match results |
| 10 | `dwd_two_way_reconciliation` | Table | Phase 2 §7 | DW fact: two-way reconciliation summary |
| 11 | `dwd_two_way_reconciliation_detail` | Table | Phase 2 §7 | DW fact: two-way reconciliation detail |
| 12 | `dwd_recon_anomalies` | Table | Phase 3 §3 | Anomaly records (all 7 types) |
| 13 | `dwd_recon_anomaly_summary` | Table | Phase 3 §3 | Daily anomaly aggregates |
| 14 | `dwd_recon_anomaly_metrics` | Table | Phase 3 §3 | Pipeline run metrics |
| 15 | `mv_recon_daily_summary` | MV | Phase 4 §3.1 | Dashboard: daily reconciliation KPIs |
| 16 | `mv_recon_anomaly_by_type` | MV | Phase 4 §3.2 | Dashboard: anomaly breakdown |
| 17 | `mv_recon_shop_health` | MV | Phase 4 §3.3 | Dashboard: per-shop health |
| 18 | `v_recon_open_anomalies` | View | Phase 4 §3.4 | Investigation: open anomaly detail |
| 19 | `v_recon_pipeline_runs` | View | Phase 4 §3.5 | Ops: pipeline execution history |
| 20 | `v_recon_weekly_summary` | View | Phase 4 §3.6 | Report: weekly aggregates |
| 21 | `v_recon_monthly_summary` | View | Phase 4 §3.6 | Report: monthly aggregates |

**Total: 14 tables + 3 materialized views + 4 views = 21 Redshift objects**

---

## Appendix B — Parameter Store Reference

All parameters under `/recon/` prefix in AWS Systems Manager Parameter Store.

| Parameter Path | Type | Default | Description |
|----------------|------|---------|-------------|
| `/recon/thresholds/l1_amount_tolerance` | String | `0.01` | L1 match: max dollar difference |
| `/recon/thresholds/l1_match_rate_critical` | String | `90` | L1 match rate % → CRITICAL |
| `/recon/thresholds/l1_match_rate_warning` | String | `95` | L1 match rate % → WARNING |
| `/recon/thresholds/l2_amount_tolerance` | String | `0.05` | L2 match: max dollar difference (after fee) |
| `/recon/thresholds/l2_match_rate_critical` | String | `95` | L2 match rate % → CRITICAL |
| `/recon/thresholds/l3_variance_tolerance_pct` | String | `2.0` | L3 match: max shop/day variance % |
| `/recon/thresholds/l3_match_rate_warning` | String | `50` | L3 match rate % → WARNING |
| `/recon/thresholds/stripe_fee_min` | String | `2.00` | Normal Stripe fee floor ($) |
| `/recon/thresholds/stripe_fee_max` | String | `8.00` | Normal Stripe fee ceiling ($) |
| `/recon/thresholds/stripe_fee_avg` | String | `4.66` | Expected average Stripe fee ($) |
| `/recon/thresholds/payment_delay_warning_hours` | String | `2` | Missing payment → HIGH after N hours |
| `/recon/thresholds/payment_delay_critical_hours` | String | `24` | Missing payment → CRITICAL after N hours |
| `/recon/thresholds/refund_stuck_threshold_hours` | String | `72` | Refund pending → CRITICAL after N hours |
| `/recon/thresholds/anomaly_spike_multiplier` | String | `2.0` | Anomaly count > N× 30d avg → alert |
| `/recon/thresholds/dq_null_rate_max_pct` | String | `1.0` | Max null % before DQ failure |
| `/recon/thresholds/dq_duplicate_rate_max_pct` | String | `0.1` | Max duplicate % before DQ failure |
| `/recon/thresholds/orphan_trade_age_hours` | String | `4` | Trade without order → anomaly after N hours |
| `/recon/thresholds/sync_delay_warning_hours` | String | `6` | Sync failure → MEDIUM after N hours |
| `/recon/thresholds/sync_delay_critical_hours` | String | `24` | Sync failure → HIGH after N hours |
| `/recon/thresholds/accounting_gap_tolerance` | String | `0.50` | Max $ gap between receipt sum and income bill |
| `/recon/config/pipeline_sla_warning_min` | String | `70` | Pipeline SLA warning threshold (minutes) |
| `/recon/config/pipeline_sla_critical_min` | String | `90` | Pipeline SLA critical threshold (minutes) |
| `/recon/config/anomaly_scan_sla_min` | String | `15` | Anomaly scan SLA (minutes) |
| `/recon/config/extraction_lookback_days` | String | `3` | Days of lookback for incremental extraction |
| `/recon/config/dead_letter_retention_days` | String | `30` | Dead letter queue retention |
| `/recon/config/mv_refresh_schedule` | String | `cron(0 7 * * ? *)` | MV refresh cron |
| `/recon/config/report_schedule` | String | `cron(0 8 * * ? *)` | Daily report cron (UTC) |
| `/recon/config/backfill_max_days` | String | `90` | Max days for backfill operation |
| `/recon/alerting/wecom_warning_webhook` | SecureString | `(webhook URL)` | WeCom warning channel webhook |
| `/recon/alerting/wecom_critical_webhook` | SecureString | `(webhook URL)` | WeCom critical channel webhook |
| `/recon/alerting/email_recipients` | String | `finance-ops@luckincoffeeusa.com` | Email recipients for reports |
| `/recon/ai/enable_ml_scoring` | String | `false` | Enable AI anomaly scoring (after 90d) |
| `/recon/ai/model_endpoint` | String | `` | SageMaker endpoint for ML scoring |
| `/recon/ai/confidence_threshold` | String | `0.7` | Min AI confidence to auto-classify |

**Total: 33 parameters (31 String + 2 SecureString)**

---

## Appendix C — Cost Estimate

### Monthly Cost Breakdown (Steady State)

| Service | Resource | Configuration | Est. Monthly Cost |
|---------|----------|---------------|-------------------|
| **AWS Glue** | 9 ETL jobs | 2 × G.1X workers × ~10 min/day each | ~$30 |
| **S3** | Staging data | ~5 GB Parquet/month (90-day retention) | ~$1 |
| **Redshift Serverless** | Analytics | 8 RPU base, ~1 hour active/day | ~$50 |
| **DynamoDB** | Watermark table | On-demand, ~100 writes/day | ~$1 |
| **Lambda** | Report function | 1 invocation/day, 512 MB, 30 sec | ~$0.01 |
| **CloudWatch** | Logs + Metrics + Alarms | 5 alarms, custom metrics, Glue logs | ~$10 |
| **SSM Parameter Store** | 33 parameters | Standard tier (free for first 10K) | $0 |
| **SNS** | 3 topics | ~30 notifications/day | ~$0.05 |
| **Secrets Manager** | 4 secrets | $0.40/secret/month | ~$2 |
| **EventBridge** | 2 rules | Free tier | $0 |
| | | | |
| **Total** | | | **~$94/month** |

### Cost Optimization Notes

1. **Redshift Serverless** is the largest cost driver. Monitor RPU usage; if consistently <4 RPU, consider reducing base capacity.
2. **Glue Jobs** use the minimum viable worker count (2 × G.1X). Scale only if SLA is breached.
3. **S3 lifecycle policy**: Transition staging data to Glacier after 90 days, delete after 365 days.
4. **No additional Grafana cost** — uses existing deployment.

---

*End of Phase 4: Dashboard, Reporting & Deployment Guide*

*This completes the UC-FN-02 Revenue Reconciliation Automation design — all 4 phases are now documented.*

| Phase | Document | Lines | Status |
|-------|----------|-------|--------|
| 1 | Schema Discovery & Data Profiling Report | 517 | ✅ COMPLETE |
| 2 | ETL Pipeline & Reconciliation Design | 1,250 | ✅ COMPLETE |
| 3 | Anomaly Detection Rules & Engine Design | 1,567 | ✅ COMPLETE |
| 4 | Dashboard, Reporting & Deployment Guide | — | ✅ COMPLETE |

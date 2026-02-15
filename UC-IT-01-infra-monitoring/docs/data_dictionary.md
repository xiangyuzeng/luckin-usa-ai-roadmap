# Data Dictionary / 数据字典
## UC-IT-01: Predictive Infrastructure Monitoring / 基础设施预测性监控

**Database:** `test`
**Server:** `aws-luckyus-dbatest-rw`
**Schema Owner:** Data Engineering / BI Team
**Last Updated:** 2026-02-15
**Version:** 1.0

---

## Table of Contents

1. [Schema Overview](#1-schema-overview)
2. [Table 1: infra_metric_daily](#2-table-1-infra_metric_daily)
3. [Table 2: infra_anomaly_scores](#3-table-2-infra_anomaly_scores)
4. [Table 3: infra_health_scores](#4-table-3-infra_health_scores)
5. [Table 4: infra_anomaly_alerts](#5-table-4-infra_anomaly_alerts)
6. [Table 5: infra_fleet_inventory](#6-table-5-infra_fleet_inventory)
7. [Table 6: infra_monitoring_pipeline_log](#7-table-6-infra_monitoring_pipeline_log)
8. [Views](#8-views)
9. [Reference Data](#9-reference-data)
10. [Data Lineage & Source Mapping](#10-data-lineage--source-mapping)
11. [Data Retention Policy](#11-data-retention-policy)

---

## 1. Schema Overview

All six analytics tables reside in the `test` database on `aws-luckyus-dbatest-rw`, the
shared analytics server also used by UC-SC-01 (Demand Forecast Accuracy) and UC-OP-02
(Store Performance Anomaly Detection).

所有六张分析表位于 `aws-luckyus-dbatest-rw` 服务器的 `test` 数据库中，该服务器同时被
UC-SC-01（需求预测准确度监控）和 UC-OP-02（门店绩效异常检测）共享使用。

```
┌─────────────────────────┐     ┌─────────────────────────┐
│  infra_fleet_inventory  │     │ infra_monitoring_       │
│  (resource registry)    │     │   pipeline_log          │
│  基础设施注册表          │     │  (pipeline audit)       │
└────────────┬────────────┘     │  管道执行日志            │
             │                  └─────────────────────────┘
             │ instance_id
             ▼
┌─────────────────────────┐     ┌─────────────────────────┐
│  infra_metric_daily     │────>│  infra_anomaly_scores   │
│  (raw daily metrics)    │     │  (SPC computations)     │
│  每日指标原始数据        │     │  SPC统计过程控制计算     │
└────────────┬────────────┘     └────────────┬────────────┘
             │                               │
             ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────┐
│  infra_health_scores    │     │  infra_anomaly_alerts   │
│  (composite scores)     │     │  (triggered alerts)     │
│  综合健康评分            │     │  触发的异常告警          │
└─────────────────────────┘     └─────────────────────────┘
```

### Table Summary

| # | Table Name                       | Grain                           | Rows/Day (est.) | Retention     |
|---|----------------------------------|---------------------------------|-----------------|---------------|
| 1 | `infra_metric_daily`            | service + instance + metric + date | ~1,400-1,900 | Unlimited     |
| 2 | `infra_anomaly_scores`          | service + instance + metric + date | ~1,400-1,900 | Unlimited     |
| 3 | `infra_health_scores`           | service + instance + date       | ~138            | Unlimited     |
| 4 | `infra_anomaly_alerts`          | service + instance + event      | ~10-50          | Unlimited     |
| 5 | `infra_fleet_inventory`         | service + instance              | N/A (upsert)    | Unlimited     |
| 6 | `infra_monitoring_pipeline_log` | run + step                      | ~14-28          | 90 days       |

---

## 2. Table 1: infra_metric_daily

**Full Name:** `test.infra_metric_daily`
**Purpose:** Core metrics fact table -- stores daily aggregated infrastructure metrics
collected from Prometheus, CloudWatch, and other monitoring sources.

**中文说明:** 核心指标事实表 -- 存储从 Prometheus、CloudWatch 等监控源采集的每日聚合基础设施指标。

**Grain:** One row per (service_type, instance_id, metric_date, metric_name).
Daily aggregates are computed from raw time-series data.

### Column Definitions

| # | Column Name    | Data Type        | Nullable | Default             | Description (EN)                                                                                | 描述 (CN)                                      | Example Value                              |
|---|----------------|------------------|----------|---------------------|-------------------------------------------------------------------------------------------------|------------------------------------------------|--------------------------------------------|
| 1 | id             | BIGINT           | NO       | AUTO_INCREMENT      | Primary key, auto-incremented surrogate key                                                     | 主键，自增代理键                                | 1042857                                    |
| 2 | service_type   | VARCHAR(20)      | NO       | --                  | AWS service category of the monitored resource                                                  | 被监控资源的AWS服务类别                          | 'REDIS'                                    |
| 3 | instance_id    | VARCHAR(200)     | NO       | --                  | Unique identifier for the resource instance (ARN, endpoint, or cluster ID)                      | 资源实例唯一标识符（ARN、端点或集群ID）           | 'redis-store-001.abc123.use1.cache.amazonaws.com:6379' |
| 4 | instance_name  | VARCHAR(100)     | YES      | NULL                | Human-readable display name for the instance                                                    | 实例的可读显示名称                               | 'redis-store-001'                          |
| 5 | metric_date    | DATE             | NO       | --                  | Calendar date for the aggregated metric value (UTC)                                             | 聚合指标值的日历日期（UTC时区）                   | '2026-02-14'                               |
| 6 | metric_name    | VARCHAR(80)      | NO       | --                  | Canonical metric identifier (see Metric Name Reference)                                        | 规范指标标识符（参见指标名称参考表）              | 'memory_usage_pct'                         |
| 7 | metric_value   | DOUBLE           | YES      | NULL                | Daily aggregated metric value (avg unless otherwise noted)                                      | 每日聚合指标值（默认为平均值，特殊情况除外）       | 72.35                                      |
| 8 | metric_unit    | VARCHAR(30)      | YES      | NULL                | Unit of measurement for the metric value                                                        | 指标值的度量单位                                 | 'percent'                                  |
| 9 | source         | VARCHAR(30)      | NO       | 'PROMETHEUS'        | Data collection source system                                                                   | 数据采集来源系统                                 | 'PROMETHEUS'                               |
| 10| day_of_week    | TINYINT          | YES      | NULL                | ISO day of week (1=Monday, 7=Sunday), derived from metric_date                                  | ISO星期几（1=周一，7=周日），由metric_date推导     | 5                                          |
| 11| is_weekend     | BOOLEAN          | YES      | FALSE               | Whether metric_date falls on Saturday or Sunday                                                 | metric_date是否为周六或周日                      | FALSE                                      |
| 12| created_at     | DATETIME         | YES      | CURRENT_TIMESTAMP   | Row insertion timestamp                                                                         | 行插入时间戳                                    | '2026-02-15 06:05:23'                      |

### Keys & Indexes

| Type        | Name / Columns                                               | Purpose                                        |
|-------------|--------------------------------------------------------------|------------------------------------------------|
| PRIMARY KEY | `id`                                                        | Surrogate primary key                          |
| UNIQUE      | `(service_type, instance_id, metric_date, metric_name)`     | Prevents duplicate metric rows; enables upsert |
| INDEX       | `idx_date (metric_date)`                                    | Fast date-range queries                        |
| INDEX       | `idx_service (service_type)`                                | Fast service-type filtering                    |
| INDEX       | `idx_instance (instance_id)`                                | Fast per-instance lookups                      |

### Notes

- `metric_value` is NULL when the source did not return data for that date (gap).
- `day_of_week` and `is_weekend` are denormalized for convenience in weekly-pattern queries.
- `source` valid values: `'PROMETHEUS'`, `'CLOUDWATCH'`, `'MCP_DB_GATEWAY'`, `'MANUAL'`.

---

## 3. Table 2: infra_anomaly_scores

**Full Name:** `test.infra_anomaly_scores`
**Purpose:** SPC computation results -- Z-scores, control limits, Western Electric rule
evaluations, and rate-of-change calculations for each metric observation.

**中文说明:** SPC计算结果表 -- 存储每个指标观测值的Z分数、控制限、Western Electric规则评估及变化率计算结果。

**Grain:** One row per (service_type, instance_id, metric_date, metric_name).
Computed from `infra_metric_daily` using a 14-day rolling window.

### Column Definitions

| # | Column Name        | Data Type      | Nullable | Default           | Description (EN)                                                                                  | 描述 (CN)                                              | Example Value       |
|---|--------------------|----------------|----------|-------------------|---------------------------------------------------------------------------------------------------|---------------------------------------------------------|---------------------|
| 1 | id                 | BIGINT         | NO       | AUTO_INCREMENT    | Primary key, auto-incremented surrogate key                                                       | 主键，自增代理键                                         | 5283901             |
| 2 | service_type       | VARCHAR(20)    | NO       | --                | AWS service category                                                                              | AWS服务类别                                              | 'RDS'               |
| 3 | instance_id        | VARCHAR(200)   | NO       | --                | Resource instance identifier                                                                      | 资源实例标识符                                           | 'db-cluster-prod-01'|
| 4 | metric_date        | DATE           | NO       | --                | Date of the observation (UTC)                                                                     | 观测日期（UTC时区）                                      | '2026-02-14'        |
| 5 | metric_name        | VARCHAR(80)    | NO       | --                | Canonical metric identifier                                                                       | 规范指标标识符                                           | 'cpu_utilization'   |
| 6 | metric_value       | DOUBLE         | YES      | NULL              | Observed metric value on this date                                                                | 当日观测指标值                                           | 85.2                |
| 7 | rolling_mean_14d   | DOUBLE         | YES      | NULL              | 14-day rolling arithmetic mean of the metric                                                      | 指标的14天滚动算术平均值                                  | 45.6                |
| 8 | rolling_std_14d    | DOUBLE         | YES      | NULL              | 14-day rolling standard deviation of the metric                                                   | 指标的14天滚动标准差                                      | 8.3                 |
| 9 | z_score            | DOUBLE         | YES      | NULL              | Standard score: (value - mean) / std_dev                                                          | 标准分数：(值 - 均值) / 标准差                            | 4.77                |
| 10| ucl_2sigma         | DOUBLE         | YES      | NULL              | Upper control limit at 2 sigma (mean + 2*std)                                                     | 2-sigma上控制限（均值 + 2*标准差）                         | 62.2                |
| 11| ucl_3sigma         | DOUBLE         | YES      | NULL              | Upper control limit at 3 sigma (mean + 3*std)                                                     | 3-sigma上控制限（均值 + 3*标准差）                         | 70.5                |
| 12| lcl_2sigma         | DOUBLE         | YES      | NULL              | Lower control limit at 2 sigma (mean - 2*std)                                                     | 2-sigma下控制限（均值 - 2*标准差）                         | 29.0                |
| 13| lcl_3sigma         | DOUBLE         | YES      | NULL              | Lower control limit at 3 sigma (mean - 3*std)                                                     | 3-sigma下控制限（均值 - 3*标准差）                         | 20.7                |
| 14| rate_of_change_1d  | DECIMAL(8,2)   | YES      | NULL              | 1-day percentage change: (today - yesterday) / yesterday * 100                                    | 1天变化率：(今日值 - 昨日值) / 昨日值 * 100               | 12.50               |
| 15| rate_of_change_7d  | DECIMAL(8,2)   | YES      | NULL              | 7-day percentage change: (today - 7_days_ago) / 7_days_ago * 100                                  | 7天变化率：(今日值 - 7天前值) / 7天前值 * 100              | -5.30               |
| 16| we_rule1           | BOOLEAN        | YES      | FALSE             | WE Rule 1: 1 point beyond 3-sigma (sudden spike/crash)                                           | WE规则1：1个点超出3-sigma（突发尖峰/暴跌）                 | TRUE                |
| 17| we_rule2           | BOOLEAN        | YES      | FALSE             | WE Rule 2: 2 of 3 consecutive points beyond 2-sigma (emerging instability)                       | WE规则2：连续3点中2点超出2-sigma（新出现的不稳定性）        | FALSE               |
| 18| we_rule3           | BOOLEAN        | YES      | FALSE             | WE Rule 3: 4 of 5 consecutive points beyond 1-sigma (persistent drift)                           | WE规则3：连续5点中4点超出1-sigma（持续漂移）               | FALSE               |
| 19| we_rule4           | BOOLEAN        | YES      | FALSE             | WE Rule 4: 8 consecutive points on same side of centerline (sustained shift)                     | WE规则4：连续8点在中心线同一侧（持续偏移）                  | TRUE                |
| 20| we_rule5           | BOOLEAN        | YES      | FALSE             | WE Rule 5: 6 consecutive points trending in one direction (monotonic trend)                      | WE规则5：连续6点向同一方向变化（单调趋势）                  | FALSE               |
| 21| anomaly_severity   | ENUM           | YES      | 'NONE'            | Computed anomaly severity: NONE, INFO, WARNING, CRITICAL, EMERGENCY                              | 计算的异常严重程度：无/信息/警告/严重/紧急                  | 'CRITICAL'          |
| 22| created_at         | DATETIME       | YES      | CURRENT_TIMESTAMP | Row insertion timestamp                                                                           | 行插入时间戳                                             | '2026-02-15 06:07:11'|

### Keys & Indexes

| Type        | Name / Columns                                               | Purpose                                            |
|-------------|--------------------------------------------------------------|----------------------------------------------------|
| PRIMARY KEY | `id`                                                        | Surrogate primary key                              |
| UNIQUE      | `(service_type, instance_id, metric_date, metric_name)`     | Prevents duplicate scoring rows; enables upsert    |
| INDEX       | `idx_severity (anomaly_severity)`                           | Fast filtering by severity level                   |
| INDEX       | `idx_date (metric_date)`                                    | Fast date-range queries                            |
| INDEX       | `idx_zscore (z_score)`                                      | Fast identification of extreme values              |

### Notes

- `rolling_mean_14d` and `rolling_std_14d` are NULL for the first 13 days of an instance's history (insufficient baseline).
- `z_score` is NULL when `rolling_std_14d` is zero (constant metric) or NULL (insufficient data).
- `anomaly_severity` is computed as: NONE (|Z| < 1.5), INFO (1.5 <= |Z| < 2), WARNING (2 <= |Z| < 3), CRITICAL (|Z| >= 3), EMERGENCY (|Z| >= 3 AND WE rules triggered).
- `rate_of_change_1d` and `rate_of_change_7d` are NULL when the prior value is zero or missing.

---

## 4. Table 3: infra_health_scores

**Full Name:** `test.infra_health_scores`
**Purpose:** Composite health scores aggregated per instance per day. Combines multiple
metric dimensions (availability, performance, capacity, error rate, latency) into a single
0-100 score with a letter grade.

**中文说明:** 每日每实例综合健康评分。将多个指标维度（可用性、性能、容量、错误率、延迟）组合为单一的0-100分数及字母等级。

**Grain:** One row per (service_type, instance_id, metric_date).

### Column Definitions

| # | Column Name          | Data Type      | Nullable | Default           | Description (EN)                                                                                  | 描述 (CN)                                          | Example Value   |
|---|----------------------|----------------|----------|-------------------|---------------------------------------------------------------------------------------------------|----------------------------------------------------|-----------------|
| 1 | id                   | BIGINT         | NO       | AUTO_INCREMENT    | Primary key, auto-incremented surrogate key                                                       | 主键，自增代理键                                     | 782301          |
| 2 | service_type         | VARCHAR(20)    | NO       | --                | AWS service category                                                                              | AWS服务类别                                          | 'REDIS'         |
| 3 | instance_id          | VARCHAR(200)   | NO       | --                | Resource instance identifier                                                                      | 资源实例标识符                                       | 'redis-store-042.abc.use1.cache.amazonaws.com:6379' |
| 4 | instance_name        | VARCHAR(100)   | YES      | NULL              | Human-readable display name                                                                       | 可读显示名称                                         | 'redis-store-042' |
| 5 | metric_date          | DATE           | NO       | --                | Calendar date of the health score (UTC)                                                           | 健康评分的日历日期（UTC时区）                         | '2026-02-14'    |
| 6 | availability_score   | DECIMAL(5,1)   | YES      | NULL              | Availability dimension score (0-100). Based on uptime and reachability.                           | 可用性维度评分（0-100）。基于在线时间和可达性。         | 100.0           |
| 7 | performance_score    | DECIMAL(5,1)   | YES      | NULL              | Performance dimension score (0-100). Based on ops/sec, throughput, response times.                | 性能维度评分（0-100）。基于每秒操作数、吞吐量、响应时间。| 82.5            |
| 8 | capacity_score       | DECIMAL(5,1)   | YES      | NULL              | Capacity dimension score (0-100). Based on memory/CPU/disk usage vs. limits.                      | 容量维度评分（0-100）。基于内存/CPU/磁盘使用率。       | 65.0            |
| 9 | error_rate_score     | DECIMAL(5,1)   | YES      | NULL              | Error rate dimension score (0-100). Based on error counts, rejected connections.                  | 错误率维度评分（0-100）。基于错误计数、拒绝连接数。     | 95.0            |
| 10| latency_score        | DECIMAL(5,1)   | YES      | NULL              | Latency dimension score (0-100). Based on read/write latency measurements.                        | 延迟维度评分（0-100）。基于读/写延迟测量值。           | 88.0            |
| 11| composite_score      | DECIMAL(5,1)   | YES      | NULL              | Weighted composite health score (0-100). See weighting formula below.                             | 加权综合健康评分（0-100）。详见下方权重公式。           | 86.1            |
| 12| health_grade         | CHAR(1)        | YES      | NULL              | Letter grade derived from composite_score (A/B/C/D/F)                                            | 由综合评分推导的字母等级（A/B/C/D/F）                  | 'B'             |
| 13| trend_direction      | VARCHAR(10)    | YES      | NULL              | Score trend over the past 7 days: IMPROVING, STABLE, or DEGRADING                                | 过去7天评分趋势：改善中/稳定/退化中                    | 'STABLE'        |
| 14| week_over_week_change| DECIMAL(5,2)   | YES      | NULL              | Change in composite_score vs. 7 days ago (positive = improvement)                                | 与7天前综合评分的变化值（正值=改善）                    | -2.30           |
| 15| created_at           | DATETIME       | YES      | CURRENT_TIMESTAMP | Row insertion timestamp                                                                           | 行插入时间戳                                         | '2026-02-15 06:08:45' |

### Keys & Indexes

| Type        | Name / Columns                                           | Purpose                                     |
|-------------|----------------------------------------------------------|---------------------------------------------|
| PRIMARY KEY | `id`                                                    | Surrogate primary key                       |
| UNIQUE      | `(service_type, instance_id, metric_date)`              | One health score per instance per day       |
| INDEX       | `idx_grade (health_grade)`                              | Fast filtering by grade                     |
| INDEX       | `idx_composite (composite_score)`                       | Fast sorting by score                       |
| INDEX       | `idx_date (metric_date)`                                | Fast date-range queries                     |

### Composite Score Formula

```
composite_score = (
    availability_score  * 0.30 +
    performance_score   * 0.25 +
    capacity_score      * 0.20 +
    error_rate_score    * 0.15 +
    latency_score       * 0.10
)
```

Weights are configurable in `config/metrics_config.yaml`.

---

## 5. Table 4: infra_anomaly_alerts

**Full Name:** `test.infra_anomaly_alerts`
**Purpose:** Alert records generated by the anomaly detection engine. Each row represents
a triggered alert with severity, context, and recommended action.

**中文说明:** 异常检测引擎生成的告警记录。每行代表一个已触发的告警，包含严重程度、上下文和建议操作。

**Grain:** One row per alert event (service_type, instance_id, alert_date, metric_name, alert_type).

### Column Definitions

| # | Column Name              | Data Type      | Nullable | Default           | Description (EN)                                                                          | 描述 (CN)                                       | Example Value                                      |
|---|--------------------------|----------------|----------|-------------------|-------------------------------------------------------------------------------------------|-------------------------------------------------|----------------------------------------------------|
| 1 | id                       | BIGINT         | NO       | AUTO_INCREMENT    | Primary key, auto-incremented surrogate key                                               | 主键，自增代理键                                  | 12045                                              |
| 2 | service_type             | VARCHAR(20)    | NO       | --                | AWS service category                                                                      | AWS服务类别                                       | 'REDIS'                                            |
| 3 | instance_id              | VARCHAR(200)   | NO       | --                | Resource instance identifier                                                              | 资源实例标识符                                    | 'redis-store-007.abc.use1.cache.amazonaws.com:6379'|
| 4 | alert_date               | DATE           | NO       | --                | Date the alert was generated (UTC)                                                        | 告警生成日期（UTC时区）                            | '2026-02-14'                                       |
| 5 | alert_type               | VARCHAR(30)    | NO       | --                | Classification of the alert trigger mechanism                                             | 告警触发机制分类                                   | 'Z_SCORE_BREACH'                                   |
| 6 | severity                 | ENUM           | NO       | --                | Alert severity level: INFO, WARNING, CRITICAL, EMERGENCY                                  | 告警严重等级：信息/警告/严重/紧急                   | 'CRITICAL'                                         |
| 7 | metric_name              | VARCHAR(80)    | NO       | --                | Metric that triggered the alert                                                           | 触发告警的指标                                    | 'memory_usage_pct'                                 |
| 8 | current_value            | DOUBLE         | YES      | NULL              | Observed metric value at time of alert                                                    | 告警时的观测指标值                                 | 92.8                                               |
| 9 | threshold_value          | DOUBLE         | YES      | NULL              | Threshold that was breached                                                               | 被突破的阈值                                      | 80.0                                               |
| 10| z_score                  | DOUBLE         | YES      | NULL              | Z-score at time of alert                                                                  | 告警时的Z分数                                     | 4.77                                               |
| 11| consecutive_anomaly_days | INT            | YES      | 0                 | Number of consecutive days this metric has been anomalous                                 | 该指标连续异常的天数                               | 3                                                  |
| 12| predicted_breach_hours   | INT            | YES      | NULL              | Estimated hours until critical threshold breach (linear extrapolation)                    | 预估距临界阈值突破的小时数（线性外推）              | 48                                                 |
| 13| description_en           | TEXT           | YES      | NULL              | Human-readable alert description in English                                               | 英文可读告警描述                                   | 'Redis memory at 92.8%, Z=4.77 (3-sigma breach)'  |
| 14| description_cn           | TEXT           | YES      | NULL              | Human-readable alert description in Chinese                                               | 中文可读告警描述                                   | 'Redis内存使用率92.8%，Z=4.77（突破3-sigma限）'      |
| 15| recommended_action       | TEXT           | YES      | NULL              | Suggested remediation action                                                              | 建议的修复操作                                    | 'Scale up Redis instance or review eviction policy'|
| 16| acknowledged             | BOOLEAN        | YES      | FALSE             | Whether a human has acknowledged this alert                                               | 人工是否已确认此告警                               | FALSE                                              |
| 17| acknowledged_by          | VARCHAR(50)    | YES      | NULL              | Username of the person who acknowledged the alert                                         | 确认告警的用户名                                   | 'ops-john'                                         |
| 18| acknowledged_at          | DATETIME       | YES      | NULL              | Timestamp when the alert was acknowledged                                                 | 告警被确认的时间戳                                 | '2026-02-14 14:30:00'                              |
| 19| created_at               | DATETIME       | YES      | CURRENT_TIMESTAMP | Row insertion timestamp                                                                   | 行插入时间戳                                      | '2026-02-15 06:09:02'                              |

### Keys & Indexes

| Type        | Name / Columns                                                           | Purpose                                     |
|-------------|--------------------------------------------------------------------------|---------------------------------------------|
| PRIMARY KEY | `id`                                                                    | Surrogate primary key                       |
| INDEX       | `idx_severity (severity)`                                               | Fast filtering by severity                  |
| INDEX       | `idx_alert_date (alert_date)`                                           | Fast date-range queries                     |
| INDEX       | `idx_acknowledged (acknowledged)`                                       | Quick retrieval of unacknowledged alerts    |
| INDEX       | `idx_instance_alert (service_type, instance_id, alert_date)`            | Per-instance alert history                  |

### Alert Type Values

| alert_type             | Description                                                            |
|------------------------|------------------------------------------------------------------------|
| `Z_SCORE_BREACH`       | Metric Z-score exceeded 2-sigma or 3-sigma threshold                  |
| `WE_RULE_VIOLATION`    | Western Electric rule triggered (any of rules 1-5)                    |
| `RATE_OF_CHANGE`       | Day-over-day or week-over-week change exceeded threshold              |
| `THRESHOLD_BREACH`     | Absolute metric value crossed a static threshold                      |
| `HEALTH_SCORE_DROP`    | Composite health score dropped below grade threshold                  |
| `CONSECUTIVE_ANOMALY`  | Metric has been anomalous for N+ consecutive days                     |
| `PREDICTIVE_BREACH`    | Linear extrapolation predicts critical threshold breach within N hours |

---

## 6. Table 5: infra_fleet_inventory

**Full Name:** `test.infra_fleet_inventory`
**Purpose:** Infrastructure registry -- canonical mapping of all monitored instances across
services, regions, and availability zones. Auto-populated by the fleet discovery step.

**中文说明:** 基础设施注册表 -- 所有被监控实例的规范映射，覆盖各服务、区域和可用区。由资产发现步骤自动填充。

**Grain:** One row per (service_type, instance_id).

### Column Definitions

| # | Column Name         | Data Type      | Nullable | Default             | Description (EN)                                                                            | 描述 (CN)                                        | Example Value                                  |
|---|---------------------|----------------|----------|---------------------|---------------------------------------------------------------------------------------------|--------------------------------------------------|-------------------------------------------------|
| 1 | id                  | BIGINT         | NO       | AUTO_INCREMENT      | Primary key, auto-incremented surrogate key                                                 | 主键，自增代理键                                   | 301                                            |
| 2 | service_type        | VARCHAR(20)    | NO       | --                  | AWS service category                                                                        | AWS服务类别                                        | 'REDIS'                                        |
| 3 | instance_id         | VARCHAR(200)   | NO       | --                  | Unique identifier for the resource instance                                                 | 资源实例唯一标识符                                  | 'redis-store-001.abc.use1.cache.amazonaws.com:6379' |
| 4 | instance_name       | VARCHAR(100)   | YES      | NULL                | Human-readable display name                                                                 | 可读显示名称                                       | 'redis-store-001'                              |
| 5 | region              | VARCHAR(20)    | YES      | 'us-east-1'         | AWS region where the instance is deployed                                                   | 实例部署的AWS区域                                   | 'us-east-1'                                    |
| 6 | availability_zone   | VARCHAR(20)    | YES      | NULL                | AWS availability zone within the region                                                     | 区域内的AWS可用区                                   | 'us-east-1a'                                   |
| 7 | instance_class      | VARCHAR(50)    | YES      | NULL                | Instance type/class (e.g., cache.r6g.large, db.r5.xlarge)                                   | 实例类型/规格                                      | 'cache.r6g.large'                              |
| 8 | engine_version      | VARCHAR(30)    | YES      | NULL                | Engine or runtime version                                                                   | 引擎或运行时版本                                    | '7.0.7'                                        |
| 9 | monitoring_source   | VARCHAR(30)    | YES      | NULL                | Primary monitoring data source for this instance                                            | 此实例的主要监控数据源                               | 'PROMETHEUS'                                   |
| 10| scrape_interval_sec | INT            | YES      | NULL                | Monitoring scrape/polling interval in seconds                                               | 监控抓取/轮询间隔（秒）                              | 30                                             |
| 11| first_seen_date     | DATE           | YES      | NULL                | Date when the instance was first discovered                                                 | 实例首次被发现的日期                                 | '2025-06-15'                                   |
| 12| last_seen_date      | DATE           | YES      | NULL                | Date when the instance was last confirmed active                                            | 实例最后一次确认活跃的日期                            | '2026-02-15'                                   |
| 13| status              | VARCHAR(20)    | YES      | 'ACTIVE'            | Current instance status: ACTIVE, INACTIVE, DECOMMISSIONED                                   | 当前实例状态：活跃/不活跃/已退役                      | 'ACTIVE'                                       |
| 14| tags                | JSON           | YES      | NULL                | Arbitrary key-value tags (AWS tags, custom labels)                                          | 任意键值标签（AWS标签、自定义标签）                    | '{"env":"prod","team":"backend"}'              |
| 15| created_at          | DATETIME       | YES      | CURRENT_TIMESTAMP   | Row insertion timestamp                                                                     | 行插入时间戳                                       | '2026-02-15 06:03:00'                          |
| 16| updated_at          | DATETIME       | YES      | CURRENT_TIMESTAMP   | Row last update timestamp (on update current_timestamp)                                     | 行最后更新时间戳                                    | '2026-02-15 06:03:00'                          |

### Keys & Indexes

| Type        | Name / Columns                                   | Purpose                                         |
|-------------|--------------------------------------------------|-------------------------------------------------|
| PRIMARY KEY | `id`                                            | Surrogate primary key                           |
| UNIQUE      | `(service_type, instance_id)`                   | One registry entry per instance                 |
| INDEX       | `idx_status (status)`                           | Fast filtering of active instances              |
| INDEX       | `idx_service_type (service_type)`               | Fast service-level queries                      |
| INDEX       | `idx_last_seen (last_seen_date)`                | Identify stale/missing instances                |

---

## 7. Table 6: infra_monitoring_pipeline_log

**Full Name:** `test.infra_monitoring_pipeline_log`
**Purpose:** Pipeline execution audit trail. Records each step of the ETL pipeline with
status, duration, row counts, and error messages.

**中文说明:** 管道执行审计日志。记录ETL管道每个步骤的状态、耗时、行数和错误信息。

**Grain:** One row per (run_id, step_num).

### Column Definitions

| # | Column Name       | Data Type      | Nullable | Default           | Description (EN)                                                                    | 描述 (CN)                                   | Example Value                   |
|---|-------------------|----------------|----------|-------------------|-------------------------------------------------------------------------------------|---------------------------------------------|---------------------------------|
| 1 | id                | BIGINT         | NO       | AUTO_INCREMENT    | Primary key, auto-incremented surrogate key                                         | 主键，自增代理键                              | 50892                           |
| 2 | run_id            | VARCHAR(50)    | NO       | --                | Unique identifier for the pipeline execution run (UUID or timestamp-based)          | 管道执行运行的唯一标识符（UUID或基于时间戳）    | 'run-20260215-060000-abc1'      |
| 3 | step_num          | INT            | NO       | --                | Sequential step number within the pipeline (1-14)                                   | 管道内的顺序步骤编号（1-14）                   | 8                               |
| 4 | step_name         | VARCHAR(80)    | NO       | --                | Descriptive name of the pipeline step                                               | 管道步骤的描述性名称                           | 'persist_raw_metrics'           |
| 5 | description       | TEXT           | YES      | NULL              | Detailed description of what the step does                                          | 步骤功能的详细描述                             | 'Insert daily metrics into infra_metric_daily' |
| 6 | status            | ENUM           | NO       | 'RUNNING'         | Execution status: RUNNING, SUCCESS, FAILED, SKIPPED                                 | 执行状态：运行中/成功/失败/已跳过              | 'SUCCESS'                       |
| 7 | rows_affected     | INT            | YES      | 0                 | Number of database rows inserted/updated/deleted                                    | 数据库行插入/更新/删除数量                      | 1432                            |
| 8 | duration_seconds  | DECIMAL(8,2)   | YES      | NULL              | Step execution duration in seconds                                                  | 步骤执行时长（秒）                             | 23.45                           |
| 9 | error_message     | TEXT           | YES      | NULL              | Error details if status = FAILED                                                    | 如果状态为FAILED的错误详情                      | NULL                            |
| 10| server_source     | VARCHAR(30)    | YES      | NULL              | Server or API that this step interacted with                                        | 此步骤交互的服务器或API                         | 'PROMETHEUS'                    |
| 11| created_at        | DATETIME       | YES      | CURRENT_TIMESTAMP | Row insertion timestamp                                                             | 行插入时间戳                                   | '2026-02-15 06:05:23'           |

### Keys & Indexes

| Type        | Name / Columns                   | Purpose                                          |
|-------------|----------------------------------|--------------------------------------------------|
| PRIMARY KEY | `id`                            | Surrogate primary key                            |
| INDEX       | `idx_run_id (run_id)`           | Group all steps of a single run                  |
| INDEX       | `idx_status (status)`           | Fast filtering of failed steps                   |
| INDEX       | `idx_created (created_at)`      | Chronological querying and retention cleanup     |

---

## 8. Views

### 8.1 v_infra_fleet_summary

**Purpose:** Aggregated fleet overview showing instance counts, average health scores, and
active alert counts per service type.

**中文说明:** 聚合的资产概览，展示每种服务类型的实例数量、平均健康评分和活跃告警数量。

```sql
CREATE OR REPLACE VIEW v_infra_fleet_summary AS
SELECT
    fi.service_type,
    COUNT(DISTINCT fi.instance_id)            AS total_instances,
    SUM(CASE WHEN fi.status = 'ACTIVE' THEN 1 ELSE 0 END) AS active_instances,
    ROUND(AVG(hs.composite_score), 1)         AS avg_health_score,
    COUNT(DISTINCT aa.id)                     AS active_alert_count,
    MAX(hs.metric_date)                       AS latest_health_date
FROM test.infra_fleet_inventory fi
LEFT JOIN test.infra_health_scores hs
    ON fi.service_type = hs.service_type
    AND fi.instance_id = hs.instance_id
    AND hs.metric_date = CURDATE() - INTERVAL 1 DAY
LEFT JOIN test.infra_anomaly_alerts aa
    ON fi.service_type = aa.service_type
    AND fi.instance_id = aa.instance_id
    AND aa.acknowledged = FALSE
    AND aa.alert_date >= CURDATE() - INTERVAL 7 DAY
WHERE fi.status = 'ACTIVE'
GROUP BY fi.service_type;
```

| Column              | Type         | Description                                        |
|---------------------|--------------|----------------------------------------------------|
| service_type        | VARCHAR(20)  | AWS service category                               |
| total_instances     | INT          | Total registered instances                         |
| active_instances    | INT          | Currently active instances                         |
| avg_health_score    | DECIMAL(5,1) | Average composite health score (yesterday)         |
| active_alert_count  | INT          | Unacknowledged alerts in past 7 days               |
| latest_health_date  | DATE         | Most recent health score date                      |

### 8.2 v_infra_latest_health

**Purpose:** Latest health score for each active instance. Used by Grafana dashboards
for the fleet health heatmap.

**中文说明:** 每个活跃实例的最新健康评分。用于Grafana仪表板的资产健康热力图。

```sql
CREATE OR REPLACE VIEW v_infra_latest_health AS
SELECT
    hs.service_type,
    hs.instance_id,
    hs.instance_name,
    hs.metric_date,
    hs.composite_score,
    hs.health_grade,
    hs.trend_direction,
    hs.availability_score,
    hs.performance_score,
    hs.capacity_score,
    hs.error_rate_score,
    hs.latency_score
FROM test.infra_health_scores hs
INNER JOIN (
    SELECT service_type, instance_id, MAX(metric_date) AS max_date
    FROM test.infra_health_scores
    GROUP BY service_type, instance_id
) latest
    ON hs.service_type = latest.service_type
    AND hs.instance_id = latest.instance_id
    AND hs.metric_date = latest.max_date;
```

### 8.3 v_active_anomaly_alerts

**Purpose:** All unacknowledged anomaly alerts from the past 30 days, ordered by severity
and recency. Used by Grafana alert panels.

**中文说明:** 过去30天所有未确认的异常告警，按严重程度和时间排序。用于Grafana告警面板。

```sql
CREATE OR REPLACE VIEW v_active_anomaly_alerts AS
SELECT
    aa.id,
    aa.service_type,
    aa.instance_id,
    aa.alert_date,
    aa.alert_type,
    aa.severity,
    aa.metric_name,
    aa.current_value,
    aa.threshold_value,
    aa.z_score,
    aa.consecutive_anomaly_days,
    aa.predicted_breach_hours,
    aa.description_en,
    aa.description_cn,
    aa.recommended_action
FROM test.infra_anomaly_alerts aa
WHERE aa.acknowledged = FALSE
    AND aa.alert_date >= CURDATE() - INTERVAL 30 DAY
ORDER BY
    FIELD(aa.severity, 'EMERGENCY', 'CRITICAL', 'WARNING', 'INFO'),
    aa.alert_date DESC;
```

---

## 9. Reference Data

### 9.1 Service Type Reference / 服务类型参考

| Code         | AWS Service                  | Instance Count (current) | Primary Data Source | Metrics Count |
|--------------|------------------------------|--------------------------|---------------------|---------------|
| `REDIS`      | Amazon ElastiCache (Redis)   | 76                       | Prometheus          | 10            |
| `RDS`        | Amazon RDS / Aurora          | 62                       | CloudWatch          | 14            |
| `EC2`        | Amazon EC2                   | ~233                     | CloudWatch          | 8             |
| `EKS`        | Amazon EKS                   | 3+                       | CloudWatch / CW CI  | 12            |
| `MSK`        | Amazon MSK (Kafka)           | 2                        | CloudWatch          | 10            |
| `DOCDB`      | Amazon DocumentDB            | 4                        | CloudWatch          | 10            |
| `OPENSEARCH` | Amazon OpenSearch Service    | 2                        | CloudWatch          | 10            |
| `EMR`        | Amazon EMR                   | 1+                       | CloudWatch          | 6             |

### 9.2 Metric Name Reference / 指标名称参考

#### Redis Metrics (source: Prometheus)

| metric_name              | PromQL Source                                     | Unit         | Description (EN)                           | 描述 (CN)                    |
|--------------------------|---------------------------------------------------|--------------|--------------------------------------------|------------------------------|
| `memory_usage_pct`       | `redis_memory_used_bytes / redis_memory_max_bytes * 100` | percent | Memory usage as percentage of max          | 内存使用率（占最大值百分比）    |
| `memory_used_bytes`      | `redis_memory_used_bytes`                         | bytes        | Absolute memory used                       | 已用内存绝对值                |
| `connected_clients`      | `redis_connected_clients`                         | count        | Number of connected clients                | 已连接客户端数                |
| `ops_per_sec`            | `rate(redis_commands_processed_total[5m])`         | ops_per_sec  | Commands processed per second              | 每秒处理命令数                |
| `cpu_usage_pct`          | `rate(redis_cpu_user_seconds_total[5m]) * 100`     | percent      | CPU usage percentage                       | CPU使用率                     |
| `cache_hit_rate`         | `redis_keyspace_hits / (hits + misses) * 100`      | percent      | Cache hit ratio                            | 缓存命中率                    |
| `evicted_keys_per_sec`   | `rate(redis_evicted_keys_total[5m])`               | ops_per_sec  | Keys evicted per second due to memory      | 因内存不足每秒被驱逐的键数     |
| `keyspace_size`          | `redis_db_keys`                                   | count        | Total number of keys in database           | 数据库中的键总数              |
| `replication_lag`        | `redis_replication_delay`                          | seconds      | Replication lag behind master              | 复制延迟（落后主节点）         |
| `blocked_clients`        | `redis_blocked_clients`                            | count        | Number of clients blocked on BLPOP etc.    | 在BLPOP等命令上阻塞的客户端数  |

#### RDS Metrics (source: CloudWatch)

| metric_name              | CloudWatch Metric Name        | Unit        | Description (EN)                             | 描述 (CN)                    |
|--------------------------|-------------------------------|-------------|----------------------------------------------|------------------------------|
| `cpu_utilization`        | `CPUUtilization`              | percent     | CPU utilization percentage                   | CPU利用率                     |
| `freeable_memory`        | `FreeableMemory`              | bytes       | Available RAM                                | 可用内存                      |
| `freeable_memory_pct`    | Derived (freeable / total)    | percent     | Freeable memory as percentage                | 可用内存百分比                 |
| `database_connections`   | `DatabaseConnections`         | count       | Number of active database connections        | 活跃数据库连接数              |
| `read_latency`           | `ReadLatency`                 | seconds     | Average read I/O latency                     | 平均读I/O延迟                  |
| `write_latency`          | `WriteLatency`                | seconds     | Average write I/O latency                    | 平均写I/O延迟                  |
| `read_iops`              | `ReadIOPS`                    | ops_per_sec | Read I/O operations per second               | 每秒读I/O操作数               |
| `write_iops`             | `WriteIOPS`                   | ops_per_sec | Write I/O operations per second              | 每秒写I/O操作数               |
| `network_receive_throughput` | `NetworkReceiveThroughput` | bytes       | Incoming network bytes per second            | 每秒接收网络字节数            |
| `network_transmit_throughput`| `NetworkTransmitThroughput`| bytes       | Outgoing network bytes per second            | 每秒发送网络字节数            |
| `disk_queue_depth`       | `DiskQueueDepth`              | count       | Pending I/O requests                         | 待处理I/O请求数               |
| `swap_usage`             | `SwapUsage`                   | bytes       | Swap space used                              | 已用交换空间                  |
| `replica_lag`            | `ReplicaLag`                  | seconds     | Replication lag for read replicas            | 只读副本复制延迟              |
| `burst_balance`          | `BurstBalance`                | percent     | Remaining I/O burst credits (gp2/gp3)       | 剩余I/O突发额度               |

### 9.3 Anomaly Severity Levels / 异常严重等级

| Level      | Code | Trigger Criteria                                                         | Response SLA   | Description (EN)                                        | 描述 (CN)                     |
|------------|------|--------------------------------------------------------------------------|----------------|---------------------------------------------------------|-------------------------------|
| NONE       | 0    | |Z| < 1.5, no WE violations, normal ROC                                 | --             | Normal operation, no anomaly detected                   | 正常运行，未检测到异常         |
| INFO       | 1    | 1.5 <= |Z| < 2.0, or single mild WE flag                                | 24h review     | Minor deviation, logged for tracking                    | 轻微偏差，记录追踪            |
| WARNING    | 2    | 2.0 <= |Z| < 3.0, or ROC > 50%, or WE Rule 2/3/4                        | 8h review      | Significant deviation, investigation recommended        | 显著偏差，建议调查             |
| CRITICAL   | 3    | |Z| >= 3.0, or ROC > 100%, or WE Rule 1, or composite score < 50       | 2h response    | Severe anomaly, immediate attention required            | 严重异常，需立即关注           |
| EMERGENCY  | 4    | |Z| >= 3.0 AND multiple WE rules, or consecutive anomaly > 5 days       | 30min response | Multi-signal emergency, potential imminent failure       | 多信号紧急情况，可能即将故障   |

### 9.4 Health Grade Definitions / 健康等级定义

| Grade | Score Range | Color  | Description (EN)                                               | 描述 (CN)                      |
|-------|-------------|--------|----------------------------------------------------------------|--------------------------------|
| A     | 90 - 100    | Green  | Excellent health. All metrics within normal ranges.            | 健康状况优秀。所有指标在正常范围内。|
| B     | 75 - 89     | Blue   | Good health. Minor deviations, no action needed.               | 健康状况良好。轻微偏差，无需操作。 |
| C     | 60 - 74     | Yellow | Fair health. Some metrics outside normal. Review recommended.  | 健康状况一般。部分指标异常，建议检查。|
| D     | 40 - 59     | Orange | Poor health. Multiple degraded metrics. Action required.       | 健康状况差。多个指标退化，需采取措施。|
| F     | 0 - 39      | Red    | Critical health. Immediate intervention needed.                | 健康状况危急。需立即干预。        |

### 9.5 Western Electric Rules / Western Electric 规则

| Rule  | Pattern                                            | Detection Target                         | Severity when Triggered |
|-------|----------------------------------------------------|------------------------------------------|-------------------------|
| WE-1  | 1 point beyond 3-sigma                            | Sudden spike or crash                    | CRITICAL                |
| WE-2  | 2 of 3 consecutive points beyond 2-sigma          | Emerging instability                     | WARNING                 |
| WE-3  | 4 of 5 consecutive points beyond 1-sigma          | Persistent drift from baseline           | WARNING                 |
| WE-4  | 8 consecutive points on same side of centerline   | Sustained shift (possible new baseline)  | WARNING                 |
| WE-5  | 6 consecutive points trending in one direction    | Monotonic trend (gradual degradation)    | INFO                    |

**Combined rule evaluation:** When multiple WE rules fire simultaneously, severity is
escalated. For example, WE-1 + WE-4 together escalates from CRITICAL to EMERGENCY.

多规则联合评估：当多条WE规则同时触发时，严重等级升级。例如，WE-1 + WE-4 同时触发将从 CRITICAL 升级为 EMERGENCY。

---

## 10. Data Lineage & Source Mapping

### Source-to-Table Data Flow / 数据源到表的数据流

```
┌─────────────────┐    Step 3     ┌──────────────────────┐
│ Prometheus API  │ ────────────> │                      │
│ (Redis metrics) │               │  infra_metric_daily  │  Steps 9-11   ┌──────────────────────┐
└─────────────────┘               │  (raw daily facts)   │ ────────────> │  infra_anomaly_      │
                                  │                      │               │    scores             │
┌─────────────────┐    Steps 4-5  │                      │               └──────────┬───────────┘
│ CloudWatch API  │ ────────────> │                      │                          │
│ (RDS, EC2, etc) │               └──────────────────────┘                Step 13   │
└─────────────────┘                        │                                        ▼
                                  Step 12  │                          ┌──────────────────────┐
                                           ▼                          │  infra_anomaly_      │
                                  ┌──────────────────────┐            │    alerts             │
                                  │  infra_health_scores │            └──────────────────────┘
                                  └──────────────────────┘

┌─────────────────┐    Step 1     ┌──────────────────────┐
│ AWS APIs        │ ────────────> │  infra_fleet_        │
│ (boto3 describe)│               │    inventory          │
└─────────────────┘               └──────────────────────┘

(All steps log to)  ────────────> ┌──────────────────────┐
                                  │  infra_monitoring_   │
                                  │    pipeline_log       │
                                  └──────────────────────┘
```

### Metric Source Mapping / 指标数据源映射

| Service Type  | Data Source        | API / Protocol              | Collection Step | Metrics Count |
|---------------|--------------------|-----------------------------|-----------------|---------------|
| REDIS         | Prometheus         | HTTP REST (`/api/v1/query`) | Step 3          | 10            |
| RDS           | AWS CloudWatch     | boto3 `get_metric_data()`   | Step 4          | 14            |
| EC2           | AWS CloudWatch     | boto3 `get_metric_data()`   | Step 5          | 8             |
| EKS           | AWS CloudWatch CI  | boto3 `get_metric_data()`   | Step 5          | 12            |
| MSK           | AWS CloudWatch     | boto3 `get_metric_data()`   | Step 5          | 10            |
| DOCDB         | AWS CloudWatch     | boto3 `get_metric_data()`   | Step 5          | 10            |
| OPENSEARCH    | AWS CloudWatch     | boto3 `get_metric_data()`   | Step 5          | 10            |
| EMR           | AWS CloudWatch     | boto3 `get_metric_data()`   | Step 5          | 6             |

---

## 11. Data Retention Policy

### Retention Schedule / 数据保留策略

| Table                          | Retention Period | Cleanup Method                                      | Rationale                                  |
|--------------------------------|------------------|-----------------------------------------------------|--------------------------------------------|
| `infra_metric_daily`          | Unlimited        | Manual archival if needed                           | Core analytical data; needed for trending  |
| `infra_anomaly_scores`        | Unlimited        | Manual archival if needed                           | Historical anomaly context                 |
| `infra_health_scores`         | Unlimited        | Manual archival if needed                           | Health trend analysis                      |
| `infra_anomaly_alerts`        | Unlimited        | Manual archival if needed                           | Audit trail for alerts                     |
| `infra_fleet_inventory`       | Unlimited        | Status set to DECOMMISSIONED for removed instances  | Registry; no growth pressure               |
| `infra_monitoring_pipeline_log`| 90 days         | Automated cleanup via MySQL EVENT                   | Operational log; high volume not needed    |

### Cleanup Event / 清理事件

```sql
-- Automated cleanup of old pipeline logs (runs daily)
CREATE EVENT IF NOT EXISTS evt_cleanup_pipeline_log
ON SCHEDULE EVERY 1 DAY
STARTS '2026-02-16 05:00:00'
DO
    DELETE FROM test.infra_monitoring_pipeline_log
    WHERE created_at < NOW() - INTERVAL 90 DAY;
```

### Storage Estimates / 存储估算

| Table                          | Rows/Day | Avg Row Size | Daily Growth | 1-Year Estimate |
|--------------------------------|----------|--------------|--------------|-----------------|
| `infra_metric_daily`          | ~1,900   | ~250 bytes   | ~475 KB      | ~170 MB         |
| `infra_anomaly_scores`        | ~1,900   | ~350 bytes   | ~665 KB      | ~240 MB         |
| `infra_health_scores`         | ~138     | ~200 bytes   | ~28 KB       | ~10 MB          |
| `infra_anomaly_alerts`        | ~30      | ~500 bytes   | ~15 KB       | ~5 MB           |
| `infra_fleet_inventory`       | N/A      | ~400 bytes   | Negligible   | < 1 MB          |
| `infra_monitoring_pipeline_log`| ~20     | ~300 bytes   | ~6 KB        | ~600 KB (90d)   |
| **Total**                      |          |              | **~1.2 MB**  | **~426 MB**     |

---

*Generated for Luckin Coffee USA Data Engineering / BI Team.*
*Contact: IT Operations / IT 运维团队*
*Document Version: 1.0 | Last Updated: 2026-02-15*

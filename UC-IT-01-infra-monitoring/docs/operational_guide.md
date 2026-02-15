# Operational Guide / 运维指南
## UC-IT-01: Predictive Infrastructure Monitoring / 基础设施预测性监控

**Owner:** Data Engineering / BI Team
**Last Updated:** 2026-02-15
**Version:** 1.0

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Daily Operations](#3-daily-operations)
4. [Monitoring the Monitor](#4-monitoring-the-monitor)
5. [Common Issues & Troubleshooting](#5-common-issues--troubleshooting)
6. [Manual Operations](#6-manual-operations)
7. [Configuration](#7-configuration)
8. [Scaling Considerations](#8-scaling-considerations)
9. [SPC Parameter Tuning](#9-spc-parameter-tuning)
10. [Alert Response Procedures](#10-alert-response-procedures)
11. [Data Retention & Cleanup](#11-data-retention--cleanup)
12. [Contact & Escalation](#12-contact--escalation)

---

## 1. Overview

### What This System Does / 系统功能

UC-IT-01 is an automated infrastructure anomaly detection system that monitors AWS
resources across Luckin Coffee USA's cloud estate. It applies Statistical Process Control
(SPC) methods -- Z-score analysis, Western Electric rules, and rate-of-change detection --
to infrastructure metrics collected from Prometheus and AWS CloudWatch.

UC-IT-01 是一个自动化基础设施异常检测系统，监控瑞幸咖啡美国的AWS云资源。
该系统将统计过程控制（SPC）方法——Z分数分析、Western Electric规则和变化率检测——
应用于从Prometheus和AWS CloudWatch采集的基础设施指标。

### Who Uses It / 使用者

| Role                       | Usage                                                        |
|----------------------------|--------------------------------------------------------------|
| IT Operations / SRE        | Daily alert triage, health dashboard review                  |
| Database Administrators    | RDS/Redis performance anomaly review                         |
| Infrastructure Team        | Fleet health overview, capacity planning                     |
| Engineering Managers       | Weekly health reports, trend analysis                        |
| Data Engineering / BI Team | Pipeline monitoring, system maintenance                      |

### When It Runs / 运行时间

- **Primary schedule:** Daily at 06:00 UTC via MySQL EVENT scheduler
- **Backup trigger:** Python orchestrator can be invoked manually at any time
- **Data latency:** Metrics are aggregated for the previous complete UTC day (T-1)
- **Dashboard refresh:** Grafana auto-refreshes every 5 minutes from MySQL tables

---

## 2. Architecture

### System Architecture Diagram / 系统架构图

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        DATA SOURCES / 数据源                             │
│                                                                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────┐  │
│  │   Prometheus     │  │  AWS CloudWatch │  │  AWS APIs (boto3)       │  │
│  │   v2.43.0        │  │                 │  │  describe-instances     │  │
│  │                  │  │  RDS, EC2, EKS  │  │  describe-cache-        │  │
│  │  76 Redis        │  │  MSK, DocDB     │  │    clusters             │  │
│  │  targets         │  │  OpenSearch,EMR │  │  describe-db-instances  │  │
│  └────────┬─────── ┘  └────────┬────────┘  └────────────┬────────────┘  │
│           │ REST API           │ boto3 API               │ boto3 API     │
└───────────┼────────────────────┼────────────────────────┼───────────────┘
            │                    │                         │
            ▼                    ▼                         ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                    PYTHON ORCHESTRATOR / Python编排器                     │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │  infra_monitoring_pipeline.py                                      │  │
│  │                                                                    │  │
│  │  Step 1:  Fleet Inventory Refresh (boto3 describe)                │  │
│  │  Step 2:  Prometheus Health Check                                  │  │
│  │  Step 3:  Redis Metric Collection (Prometheus API)                │  │
│  │  Steps 4-5: CloudWatch Metric Collection (boto3)                  │  │
│  │  Steps 6-7: Normalize & Aggregate daily metrics                   │  │
│  │  Step 8:  Persist to infra_metric_daily                           │  │
│  │  Steps 9-11: SPC Engine (Z-scores, WE rules, anomaly scores)     │  │
│  │  Step 12: Health Score Aggregation                                 │  │
│  │  Step 13: Alert Evaluation                                         │  │
│  │  Step 14: Pipeline Logging                                         │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  Supporting modules:                                                     │
│  ├── prometheus_collector.py    (Prometheus REST API client)             │
│  ├── cloudwatch_collector.py    (CloudWatch boto3 client)               │
│  └── spc_engine.py              (SPC anomaly detection engine)          │
└──────────────────────────────────┬───────────────────────────────────────┘
                                   │ PyMySQL INSERT/UPDATE
                                   ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                    MYSQL ANALYTICS DB / MySQL分析数据库                   │
│                    Server: aws-luckyus-dbatest-rw                         │
│                    Database: test                                         │
│                                                                          │
│  ┌──────────────────┐  ┌───────────────────┐  ┌──────────────────────┐  │
│  │ infra_metric_    │  │ infra_anomaly_    │  │ infra_health_        │  │
│  │   daily          │  │   scores          │  │   scores             │  │
│  └──────────────────┘  └───────────────────┘  └──────────────────────┘  │
│  ┌──────────────────┐  ┌───────────────────┐  ┌──────────────────────┐  │
│  │ infra_anomaly_   │  │ infra_fleet_      │  │ infra_monitoring_    │  │
│  │   alerts         │  │   inventory       │  │   pipeline_log       │  │
│  └──────────────────┘  └───────────────────┘  └──────────────────────┘  │
└──────────────────────────────────┬───────────────────────────────────────┘
                                   │ MySQL queries
                                   ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                    GRAFANA DASHBOARDS / Grafana仪表板                     │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐    │
│  │  infra_anomaly_dashboard.json       infra_health_heatmap.json   │    │
│  │  - Anomaly timeline                 - Fleet health heatmap      │    │
│  │  - Z-score trend charts             - Grade distribution        │    │
│  │  - Alert severity breakdown         - Service-level overview    │    │
│  │  - WE rule violation log            - Trend direction indicators│    │
│  └──────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────┘
```

### Technology Stack / 技术栈

| Component          | Technology                | Version     | Purpose                              |
|--------------------|---------------------------|-------------|--------------------------------------|
| Metric Collection  | Prometheus                | v2.43.0     | Redis time-series metrics            |
| Metric Collection  | AWS CloudWatch + boto3    | boto3 1.26+ | RDS, EC2, EKS, MSK metrics          |
| Orchestration      | Python                    | 3.8+        | 14-step ETL pipeline                 |
| SPC Engine         | Python (numpy, scipy)     | --          | Z-scores, WE rules, anomaly scoring |
| Storage            | MySQL                     | 8.0+        | Analytics tables (6 tables)          |
| Visualization      | Grafana                   | 10.x        | Dashboards and alerting panels       |
| Scheduling         | MySQL EVENT               | --          | Daily pipeline trigger at 06:00 UTC  |

---

## 3. Daily Operations

### Automated Pipeline Schedule / 自动管道调度

The pipeline runs automatically every day at **06:00 UTC** via a MySQL EVENT. This timing
ensures that the previous full UTC day's data is available from all sources.

管道每天 **UTC 06:00** 通过MySQL EVENT自动运行。此时间确保前一个完整UTC日的数据已从所有源可用。

### Typical Pipeline Execution / 典型管道执行

| Step | Name                      | Duration (typical) | Rows Affected     | Notes                           |
|------|---------------------------|--------------------:|-------------------|---------------------------------|
| 1    | Inventory Refresh         | 15-30s              | ~5-10 upserts     | boto3 describe calls            |
| 2    | Prometheus Health Check   | 2-5s                | 0                 | HTTP GET to /api/v1/targets     |
| 3    | Redis Metric Collection   | 30-60s              | ~760              | 76 instances x 10 metrics       |
| 4    | CloudWatch RDS Collection | 60-120s             | ~868              | 62 clusters x 14 metrics        |
| 5    | CloudWatch EC2 Collection | 30-60s              | ~200-400          | Sampled EC2 instances           |
| 6    | Metric Normalization      | 5-10s               | In-memory         | Unit conversion, gap filling    |
| 7    | Daily Aggregation         | 5-10s               | In-memory         | Compute daily avg/min/max/p95   |
| 8    | Persist Raw Metrics       | 10-20s              | ~1,400-1,900      | INSERT INTO infra_metric_daily  |
| 9    | SPC Baseline Computation  | 10-20s              | In-memory         | 14-day rolling stats            |
| 10   | Anomaly Scoring           | 10-20s              | In-memory         | Z-scores, WE rules              |
| 11   | Persist Anomaly Scores    | 10-20s              | ~1,400-1,900      | INSERT INTO infra_anomaly_scores|
| 12   | Health Score Aggregation  | 5-10s               | ~138              | One per active instance         |
| 13   | Alert Evaluation          | 5-10s               | ~10-50            | Variable based on anomalies     |
| 14   | Pipeline Logging          | 2-5s                | 14                | One row per step                |
| **Total** |                      | **5-10 minutes**    | **~4,000-5,000**  |                                 |

### Expected Daily Row Counts / 预期每日行数

| Table                          | Expected Rows/Day | Validation Query                                                |
|--------------------------------|-------------------:|-----------------------------------------------------------------|
| `infra_metric_daily`          | 1,400 - 1,900      | `SELECT COUNT(*) FROM infra_metric_daily WHERE metric_date = CURDATE()-1` |
| `infra_anomaly_scores`        | 1,400 - 1,900      | `SELECT COUNT(*) FROM infra_anomaly_scores WHERE metric_date = CURDATE()-1` |
| `infra_health_scores`         | 130 - 150           | `SELECT COUNT(*) FROM infra_health_scores WHERE metric_date = CURDATE()-1` |
| `infra_anomaly_alerts`        | 10 - 50             | `SELECT COUNT(*) FROM infra_anomaly_alerts WHERE alert_date = CURDATE()-1` |
| `infra_monitoring_pipeline_log`| 14 - 28            | `SELECT COUNT(*) FROM infra_monitoring_pipeline_log WHERE DATE(created_at) = CURDATE()` |

---

## 4. Monitoring the Monitor

### Health Checks / 健康检查

The monitoring system itself needs to be monitored. Use these checks to ensure the pipeline
is running correctly.

监控系统本身也需要被监控。使用以下检查确保管道正常运行。

#### 4.1 Pipeline Execution Status

```sql
-- Check the latest pipeline run status / 检查最近管道运行状态
SELECT
    run_id,
    MIN(created_at) AS started_at,
    MAX(created_at) AS finished_at,
    TIMESTAMPDIFF(SECOND, MIN(created_at), MAX(created_at)) AS total_seconds,
    SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) AS success_steps,
    SUM(CASE WHEN status = 'FAILED' THEN 1 ELSE 0 END) AS failed_steps,
    SUM(rows_affected) AS total_rows
FROM test.infra_monitoring_pipeline_log
WHERE created_at >= CURDATE()
GROUP BY run_id
ORDER BY started_at DESC
LIMIT 5;
```

#### 4.2 Pipeline Freshness Alert

**Alert condition:** No successful pipeline run in the past 24 hours.

```sql
-- Alert if pipeline hasn't run in 24 hours / 如果管道24小时未运行则告警
SELECT
    CASE
        WHEN MAX(created_at) < NOW() - INTERVAL 24 HOUR THEN 'STALE - INVESTIGATE'
        WHEN MAX(created_at) < NOW() - INTERVAL 12 HOUR THEN 'WARNING - CHECK SCHEDULER'
        ELSE 'OK'
    END AS pipeline_status,
    MAX(created_at) AS last_run,
    TIMESTAMPDIFF(HOUR, MAX(created_at), NOW()) AS hours_since_last_run
FROM test.infra_monitoring_pipeline_log
WHERE status = 'SUCCESS';
```

#### 4.3 Data Freshness Check

```sql
-- Check data freshness across all tables / 检查所有表的数据新鲜度
SELECT 'infra_metric_daily' AS table_name,
       MAX(metric_date) AS latest_date,
       DATEDIFF(CURDATE(), MAX(metric_date)) AS days_behind
FROM test.infra_metric_daily
UNION ALL
SELECT 'infra_anomaly_scores', MAX(metric_date), DATEDIFF(CURDATE(), MAX(metric_date))
FROM test.infra_anomaly_scores
UNION ALL
SELECT 'infra_health_scores', MAX(metric_date), DATEDIFF(CURDATE(), MAX(metric_date))
FROM test.infra_health_scores
UNION ALL
SELECT 'infra_anomaly_alerts', MAX(alert_date), DATEDIFF(CURDATE(), MAX(alert_date))
FROM test.infra_anomaly_alerts;
```

**Expected:** `days_behind` should be 1 (yesterday's data processed today). A value of 2+
indicates a missed pipeline run.

#### 4.4 Failed Step Investigation

```sql
-- Find recent pipeline failures / 查找最近的管道失败
SELECT
    run_id,
    step_num,
    step_name,
    status,
    error_message,
    duration_seconds,
    created_at
FROM test.infra_monitoring_pipeline_log
WHERE status = 'FAILED'
    AND created_at >= NOW() - INTERVAL 7 DAY
ORDER BY created_at DESC;
```

---

## 5. Common Issues & Troubleshooting

### 5.1 Prometheus API Unreachable / Prometheus API不可达

**Symptoms:**
- Step 2 (Prometheus Health Check) fails with connection error
- Step 3 (Redis Metric Collection) fails or returns zero rows
- Pipeline log shows: `ConnectionError: Failed to connect to Prometheus`

**Root Causes:**
1. Prometheus service is down or restarting
2. Network firewall blocking port 9090
3. Prometheus URL changed in infrastructure update

**Resolution:**
```bash
# 1. Test Prometheus connectivity / 测试Prometheus连通性
curl -s http://<PROMETHEUS_URL>:9090/api/v1/targets | head -20

# 2. Check Prometheus service status / 检查Prometheus服务状态
# (via EKS kubectl or EC2 systemctl, depending on deployment)

# 3. Verify PROMETHEUS_URL in .env file / 验证.env文件中的PROMETHEUS_URL
cat config/.env | grep PROMETHEUS

# 4. Check firewall / security group rules / 检查防火墙/安全组规则
aws ec2 describe-security-groups --filters "Name=group-name,Values=*prometheus*"
```

### 5.2 CloudWatch API Throttling / CloudWatch API限流

**Symptoms:**
- Steps 4-5 take much longer than expected (> 5 minutes)
- Pipeline log shows: `ClientError: Rate exceeded` or `ThrottlingException`
- Partial data: some instances have metrics, others are missing

**Root Causes:**
1. Too many `GetMetricData` calls in rapid succession
2. Other systems also calling CloudWatch API concurrently
3. Batch size too large

**Resolution:**
```bash
# 1. Reduce batch size in configuration / 减少配置中的批量大小
# In config/pipeline_config.yaml:
#   cloudwatch:
#     batch_size: 10    # Reduce from default 50
#     delay_between_batches: 2.0  # Add 2-second delay

# 2. Add exponential backoff (already built in, but verify)
# Check cloudwatch_collector.py for retry logic

# 3. Verify AWS credentials have CloudWatch read permissions / 验证AWS凭证
aws sts get-caller-identity
aws cloudwatch get-metric-data --help  # Test access
```

### 5.3 MySQL Connection Timeout / MySQL连接超时

**Symptoms:**
- Step 8 (Persist Raw Metrics) fails with connection error
- Pipeline log shows: `OperationalError: (2003) Can't connect to MySQL server`
- Or: `OperationalError: (2013) Lost connection to MySQL server during query`

**Root Causes:**
1. MySQL server is down or overloaded
2. Network connectivity issue between pipeline host and MySQL
3. Credentials expired or changed
4. Connection pool exhausted

**Resolution:**
```bash
# 1. Test MySQL connectivity / 测试MySQL连通性
mysql -h aws-luckyus-dbatest-rw -u test -p -e "SELECT 1;"

# 2. Check connection count / 检查连接数
mysql -h aws-luckyus-dbatest-rw -u test -p -e \
  "SHOW STATUS LIKE 'Threads_connected';"

# 3. Verify credentials in .env / 验证.env中的凭证
cat config/.env | grep DB_

# 4. If timeout during large INSERT, increase timeout:
# In pipeline_config.yaml:
#   mysql:
#     connect_timeout: 30
#     read_timeout: 120
```

### 5.4 Missing Metrics for Specific Instances / 特定实例缺少指标

**Symptoms:**
- Row count for `infra_metric_daily` is lower than expected
- Specific instances have NULL values or missing rows
- Health scores show NULL for some dimension scores

**Root Causes:**
1. New instance not yet in fleet inventory (first run hasn't discovered it)
2. Instance was just launched and Prometheus hasn't scraped it yet
3. CloudWatch metric publishing delay (5-10 minute lag)
4. Instance is in a different AWS account or region

**Resolution:**
```sql
-- 1. Check if instance is in fleet inventory / 检查实例是否在资产清单中
SELECT * FROM test.infra_fleet_inventory
WHERE instance_id LIKE '%<partial_instance_name>%';

-- 2. Check Prometheus targets for the instance / 检查Prometheus目标
-- curl http://PROMETHEUS_URL:9090/api/v1/targets | grep <instance_id>

-- 3. Manually add to fleet inventory if auto-discovery missed it
-- INSERT INTO test.infra_fleet_inventory (service_type, instance_id, instance_name, ...)
-- The next pipeline run will collect metrics for it automatically.
```

### 5.5 SPC Anomalies on New Instances / 新实例的SPC异常

**Symptoms:**
- New instances generate many false-positive alerts in the first 2 weeks
- `rolling_mean_14d` and `rolling_std_14d` are NULL
- Z-scores are wildly high or low

**Root Cause:**
SPC requires a 14-day baseline to compute meaningful rolling statistics. During the first
13 days, there is insufficient data for reliable Z-score calculations.

**Resolution:**
- **Automatic:** The SPC engine skips anomaly scoring for instances with fewer than 14 days of data. Alerts are suppressed during the baseline period.
- **Manual override:** If you need to monitor a new critical instance immediately, you can seed historical data using the backfill command (see Section 6.1).
- **Expected timeline:** New instances begin producing valid anomaly scores on day 15.

---

## 6. Manual Operations

### 6.1 Backfill Historical Data / 回填历史数据

Useful when adding new metrics, recovering from outages, or onboarding new instances.

```bash
# Backfill the last 30 days of data / 回填过去30天数据
python orchestrator/infra_monitoring_pipeline.py --backfill 30

# Backfill a specific date range / 回填指定日期范围
python orchestrator/infra_monitoring_pipeline.py \
    --start-date 2026-01-15 \
    --end-date 2026-02-14

# Backfill only Redis metrics / 仅回填Redis指标
python orchestrator/infra_monitoring_pipeline.py \
    --backfill 30 \
    --service-type REDIS
```

**Note:** Backfill respects the UNIQUE constraints. Existing rows are updated via
`INSERT ... ON DUPLICATE KEY UPDATE`, so it is safe to run repeatedly.

### 6.2 Recompute Anomaly Scores / 重新计算异常分数

If you change SPC parameters or fix data quality issues, recompute scores without
re-collecting raw metrics.

```bash
# Recompute SPC scores, health scores, and alerts (Steps 9-13)
# 重新计算SPC分数、健康分数和告警（步骤9-13）
python orchestrator/infra_monitoring_pipeline.py --steps 9,10,11,12,13

# Recompute only for a specific date / 仅重新计算特定日期
python orchestrator/infra_monitoring_pipeline.py \
    --steps 9,10,11,12,13 \
    --target-date 2026-02-14
```

### 6.3 Acknowledge Alerts / 确认告警

Alerts should be acknowledged by operations staff after review.

```sql
-- Acknowledge a specific alert / 确认特定告警
UPDATE test.infra_anomaly_alerts
SET acknowledged = TRUE,
    acknowledged_by = 'ops-john',
    acknowledged_at = NOW()
WHERE id = 12045;

-- Bulk acknowledge all INFO-level alerts older than 7 days / 批量确认7天前的INFO级别告警
UPDATE test.infra_anomaly_alerts
SET acknowledged = TRUE,
    acknowledged_by = 'auto-cleanup',
    acknowledged_at = NOW()
WHERE severity = 'INFO'
    AND acknowledged = FALSE
    AND alert_date < CURDATE() - INTERVAL 7 DAY;

-- Acknowledge all alerts for a decommissioned instance / 确认已退役实例的所有告警
UPDATE test.infra_anomaly_alerts
SET acknowledged = TRUE,
    acknowledged_by = 'ops-decommission',
    acknowledged_at = NOW()
WHERE instance_id = 'redis-old-instance.abc.use1.cache.amazonaws.com:6379'
    AND acknowledged = FALSE;
```

### 6.4 Add New Instances to Monitoring / 添加新实例到监控

New instances are **auto-detected** by the fleet inventory step (Step 1). When a new
ElastiCache, RDS, or EC2 instance appears in the AWS API response, it is automatically
added to `infra_fleet_inventory` and metrics begin collecting on the next pipeline run.

**For Prometheus-monitored instances (Redis):**
1. Ensure the Redis exporter target is added to Prometheus config
2. Verify the target appears in Prometheus targets: `http://PROMETHEUS:9090/targets`
3. The next pipeline run will auto-discover and collect metrics

**For CloudWatch-monitored instances (RDS, EC2, etc.):**
1. The instance just needs to exist in the AWS account
2. CloudWatch metrics are automatically published by AWS
3. Step 1 (Inventory Refresh) will discover it via `boto3 describe_*` calls

---

## 7. Configuration

### 7.1 Environment Variables / 环境变量

All configuration is managed via a `.env` file in the `config/` directory.

| Variable            | Required | Default         | Description                                         |
|---------------------|----------|-----------------|-----------------------------------------------------|
| `PROMETHEUS_URL`    | Yes      | --              | Prometheus server URL (e.g., `http://prom:9090`)    |
| `AWS_REGION`        | Yes      | `us-east-1`     | AWS region for CloudWatch API calls                 |
| `AWS_ACCESS_KEY_ID` | No       | IAM role        | AWS access key (prefer IAM role instead)            |
| `AWS_SECRET_ACCESS_KEY` | No   | IAM role        | AWS secret key (prefer IAM role instead)            |
| `DB_HOST`           | Yes      | --              | MySQL server hostname                               |
| `DB_PORT`           | No       | `3306`          | MySQL server port                                   |
| `DB_USER`           | Yes      | --              | MySQL username                                      |
| `DB_PASSWORD`       | Yes      | --              | MySQL password                                      |
| `DB_NAME`           | No       | `test`          | MySQL database name                                 |
| `BATCH_SIZE`        | No       | `50`            | Number of instances per CloudWatch API batch         |
| `LOG_LEVEL`         | No       | `INFO`          | Python logging level (DEBUG, INFO, WARNING, ERROR)  |
| `ENABLE_ALERTS`     | No       | `true`          | Feature flag: generate anomaly alerts               |
| `ENABLE_HEALTH`     | No       | `true`          | Feature flag: compute health scores                 |
| `ENABLE_EC2`        | No       | `false`         | Feature flag: collect EC2 metrics (experimental)    |
| `DRY_RUN`           | No       | `false`         | If true, collect but do not persist to MySQL        |

### 7.2 Pipeline Configuration (YAML) / 管道配置

`config/pipeline_config.yaml` controls scheduling and collection parameters.

```yaml
pipeline:
  schedule_cron: "0 6 * * *"    # 06:00 UTC daily
  timezone: "UTC"
  max_retries: 3
  retry_delay_seconds: 60

prometheus:
  url: "${PROMETHEUS_URL}"
  timeout_seconds: 30
  scrape_interval: "5m"
  metrics:
    - redis_memory_used_bytes
    - redis_memory_max_bytes
    - redis_connected_clients
    - redis_commands_processed_total
    - redis_cpu_user_seconds_total
    - redis_keyspace_hits
    - redis_keyspace_misses
    - redis_evicted_keys_total
    - redis_db_keys
    - redis_blocked_clients

cloudwatch:
  region: "${AWS_REGION}"
  batch_size: 50
  delay_between_batches: 1.0
  period_seconds: 86400          # Daily aggregation
  statistics: ["Average", "Maximum", "Minimum"]

mysql:
  host: "${DB_HOST}"
  port: 3306
  database: "${DB_NAME}"
  connect_timeout: 30
  read_timeout: 120
  charset: "utf8mb4"

spc:
  rolling_window_days: 14
  sigma_warning: 2.0
  sigma_critical: 3.0
  roc_warning_pct: 50.0
  roc_critical_pct: 100.0
  min_baseline_days: 14
  we_rules_enabled: [1, 2, 3, 4, 5]
```

---

## 8. Scaling Considerations

### Current Scale (38 stores) / 当前规模（38家门店）

| Resource       | Instances | Metrics/Instance | Rows/Day | Storage/Day |
|----------------|-----------|------------------|----------|-------------|
| Redis          | 76        | 10               | 760      | ~190 KB     |
| RDS            | 62        | 14               | 868      | ~217 KB     |
| EC2 (sampled)  | ~20       | 8                | 160      | ~40 KB      |
| **Subtotal**   | **158**   |                  | **1,788**| **~447 KB** |

### Projected Scale (50 stores) / 预计规模（50家门店）

| Resource       | Instances | Metrics/Instance | Rows/Day | Storage/Day |
|----------------|-----------|------------------|----------|-------------|
| Redis          | 200       | 10               | 2,000    | ~500 KB     |
| RDS            | 100       | 14               | 1,400    | ~350 KB     |
| EC2            | 100       | 8                | 800      | ~200 KB     |
| EKS / MSK / Other | 50    | 10               | 500      | ~125 KB     |
| **Subtotal**   | **450**   |                  | **4,700**| **~1.2 MB** |

### Projected Scale (100 stores) / 预计规模（100家门店）

| Resource       | Instances | Metrics/Instance | Rows/Day | Storage/Day |
|----------------|-----------|------------------|----------|-------------|
| Redis          | 400       | 10               | 4,000    | ~1.0 MB     |
| RDS            | 200       | 14               | 2,800    | ~700 KB     |
| EC2            | 300       | 8                | 2,400    | ~600 KB     |
| EKS / MSK / Other | 100   | 10               | 1,000    | ~250 KB     |
| **Subtotal**   | **1,000** |                  | **10,200**| **~2.6 MB**|

### Scaling Recommendations / 扩展建议

1. **MySQL can handle the current and near-term load easily.** Even at 100 stores,
   the daily write volume (~10K rows) and annual storage (~950 MB) are trivial for MySQL.

2. **Partition by metric_date** when any single table exceeds 1 million rows (~2 years at
   current scale, or ~6 months at 100-store scale). This improves query performance for
   date-range queries and simplifies old-data purging.

   ```sql
   -- Example partition strategy / 分区策略示例
   ALTER TABLE infra_metric_daily
   PARTITION BY RANGE (TO_DAYS(metric_date)) (
       PARTITION p202601 VALUES LESS THAN (TO_DAYS('2026-02-01')),
       PARTITION p202602 VALUES LESS THAN (TO_DAYS('2026-03-01')),
       PARTITION p_future VALUES LESS THAN MAXVALUE
   );
   ```

3. **CloudWatch API costs** scale linearly. At 1,000 instances with daily polls,
   estimate ~$5-10/month for `GetMetricData` calls. Monitor with AWS Cost Explorer.

4. **Pipeline runtime** scales roughly linearly with instance count. At 1,000 instances,
   expect 15-25 minute total runtime (primarily CloudWatch API latency).

---

## 9. SPC Parameter Tuning

### Current Default Parameters / 当前默认参数

| Parameter                | Default Value | Range         | Impact                                           |
|--------------------------|---------------|---------------|--------------------------------------------------|
| Rolling window (days)    | 14            | 7-30          | Shorter = more reactive; longer = more stable    |
| Sigma WARNING threshold  | 2.0           | 1.5-2.5       | Lower = more sensitive (more alerts)             |
| Sigma CRITICAL threshold | 3.0           | 2.5-4.0       | Lower = more sensitive (more alerts)             |
| ROC WARNING (%)          | 50.0          | 20-80         | Lower = more sensitive to daily changes          |
| ROC CRITICAL (%)         | 100.0         | 50-200        | Lower = more sensitive to daily changes          |
| Min baseline days        | 14            | 7-30          | Fewer = earlier scoring; more = better accuracy  |
| WE rules enabled         | 1,2,3,4,5     | Any subset    | Disable specific rules to reduce noise           |

### Tuning Guidelines / 调参指南

**If too many false positives (over-alerting):**
- Increase sigma thresholds (e.g., WARNING from 2.0 to 2.5)
- Increase rolling window from 14 to 21 days (smoother baseline)
- Increase ROC thresholds (e.g., WARNING from 50% to 80%)
- Disable WE rules 3 and 5 (they catch subtle patterns that may not be actionable)

**If too few alerts (under-alerting):**
- Decrease sigma thresholds (e.g., CRITICAL from 3.0 to 2.5)
- Shorten rolling window to 7 days (more responsive to recent changes)
- Decrease ROC thresholds
- Ensure all WE rules are enabled

**Per-metric tuning:** Some metrics are naturally more volatile (e.g., `ops_per_sec` varies
with traffic patterns). Consider wider thresholds for high-variance metrics and tighter
thresholds for stability-critical metrics like `memory_usage_pct`.

---

## 10. Alert Response Procedures

### Response by Severity Level / 按严重等级响应

#### EMERGENCY (30-minute SLA)

1. **Notify:** Page on-call engineer immediately (Slack #infra-alerts + PagerDuty)
2. **Assess:** Check the affected instance's current state via Grafana dashboard
3. **Verify:** Confirm the anomaly is real (not a data collection artifact)
4. **Act:** Follow the `recommended_action` in the alert record
5. **Escalate:** If not resolved in 30 minutes, escalate to team lead
6. **Document:** Add notes to the alert record and create an incident ticket

#### CRITICAL (2-hour SLA)

1. **Review:** Check the alert details in `v_active_anomaly_alerts` view
2. **Correlate:** Look for related alerts on the same or connected instances
3. **Investigate:** Review the Z-score trend and WE rule history for context
4. **Act:** Apply remediation if needed (scale up, restart, config change)
5. **Acknowledge:** Update the alert record with your findings

#### WARNING (8-hour SLA)

1. **Review:** Include in daily operations check
2. **Trend:** Check whether the metric is trending toward CRITICAL
3. **Plan:** If trending negatively, prepare a remediation plan
4. **Acknowledge:** Acknowledge after review with brief notes

#### INFO (24-hour SLA)

1. **Log:** Note in daily operations summary
2. **Batch review:** Review all INFO alerts weekly for patterns
3. **Auto-acknowledge:** INFO alerts older than 7 days are auto-acknowledged

### Common Remediation Actions / 常见修复操作

| Alert Scenario                    | Recommended Action                                           |
|-----------------------------------|--------------------------------------------------------------|
| Redis memory > 90%               | Scale up instance class or review eviction policy            |
| Redis evicted keys sustained      | Increase `maxmemory` or add cache sharding                  |
| RDS CPU > 80% sustained          | Identify slow queries, add read replicas, or scale up        |
| RDS connections spike             | Check application connection pool settings                   |
| RDS read/write latency high       | Check disk IOPS, upgrade to io1/io2, or optimize queries    |
| Health score drop below D         | Multi-dimensional problem; review all sub-scores             |
| Consecutive anomaly > 5 days      | Likely a new baseline; review if intentional change          |

---

## 11. Data Retention & Cleanup

### Retention Policy Summary / 保留策略摘要

| Data Category             | Retention | Cleanup Mechanism                 |
|---------------------------|-----------|-----------------------------------|
| Raw daily metrics         | Unlimited | Manual archival if > 2 years      |
| Anomaly scores            | Unlimited | Manual archival if > 2 years      |
| Health scores             | Unlimited | Manual archival if > 2 years      |
| Anomaly alerts            | Unlimited | Manual archival if > 2 years      |
| Fleet inventory           | Unlimited | Status-based (DECOMMISSIONED)     |
| Pipeline execution logs   | 90 days   | Automated MySQL EVENT (daily)     |

### Automated Cleanup / 自动清理

Pipeline logs are cleaned automatically by a MySQL EVENT that runs daily at 05:00 UTC:

```sql
-- This event is created by 02_create_analytics_schema.sql
-- Deletes pipeline_log entries older than 90 days
-- 删除90天前的管道日志条目

CREATE EVENT IF NOT EXISTS evt_cleanup_pipeline_log
ON SCHEDULE EVERY 1 DAY
STARTS '2026-02-16 05:00:00'
DO
    DELETE FROM test.infra_monitoring_pipeline_log
    WHERE created_at < NOW() - INTERVAL 90 DAY;
```

### Manual Archival (when needed) / 手动归档

If tables grow large (> 1M rows / > 500 MB), archive old data:

```sql
-- Archive metrics older than 1 year to a backup table / 将1年前的指标归档到备份表
CREATE TABLE test.infra_metric_daily_archive_2025 AS
SELECT * FROM test.infra_metric_daily
WHERE metric_date < '2026-01-01';

-- Then delete archived rows from the active table / 从活跃表中删除已归档行
DELETE FROM test.infra_metric_daily
WHERE metric_date < '2026-01-01';

-- Repeat for infra_anomaly_scores, infra_health_scores, infra_anomaly_alerts
```

---

## 12. Contact & Escalation

### Team Contacts / 团队联系人

| Role                      | Team / Channel                      | Responsibility                          |
|---------------------------|-------------------------------------|-----------------------------------------|
| Pipeline Owner            | Data Engineering / BI Team          | Pipeline code, SPC engine, schema       |
| Infrastructure Operations | IT Ops / SRE (#infra-ops Slack)     | Alert triage, instance management       |
| Database Administration   | DBA Team (#dba-support Slack)       | MySQL server, RDS fleet management      |
| Cloud Infrastructure      | Cloud Team (#cloud-infra Slack)     | AWS account access, CloudWatch config   |
| Engineering Management    | Engineering Leads                   | Escalation, budget approvals            |

### Escalation Path / 升级路径

```
Level 1:  On-call Engineer (IT Ops / SRE)
          - First responder for EMERGENCY and CRITICAL alerts
          - Acknowledges alerts, performs initial investigation
          ▼ (if unresolved in 30 min for EMERGENCY / 2 hr for CRITICAL)
Level 2:  Team Lead (IT Ops Manager)
          - Reviews complex or multi-system issues
          - Coordinates cross-team response
          ▼ (if unresolved in 2 hours or business impact confirmed)
Level 3:  Engineering Manager / Director
          - Executive escalation
          - Budget approval for emergency scaling
          ▼ (if customer-impacting incident)
Level 4:  VP Engineering / CTO
          - Major incident management
          - External communication coordination
```

### Useful Links / 有用链接

| Resource                   | URL / Location                                               |
|----------------------------|--------------------------------------------------------------|
| Grafana Dashboards         | `http://<grafana-host>:3000/d/infra-anomaly/`               |
| Prometheus UI              | `http://<prometheus-host>:9090/`                             |
| Pipeline Source Code       | `/app/UC-IT-01-infra-monitoring/orchestrator/`               |
| SQL Schema                 | `/app/UC-IT-01-infra-monitoring/sql/`                        |
| Data Dictionary            | `/app/UC-IT-01-infra-monitoring/docs/data_dictionary.md`     |
| SPC Methodology            | `/app/UC-IT-01-infra-monitoring/docs/spc_methodology.md`     |
| AWS Console (CloudWatch)   | `https://console.aws.amazon.com/cloudwatch/`                 |
| Project README             | `/app/UC-IT-01-infra-monitoring/README.md`                   |

---

*Generated for Luckin Coffee USA IT Operations Team.*
*Contact: Data Engineering / BI Team & IT Ops / SRE Team*
*Document Version: 1.0 | Last Updated: 2026-02-15*

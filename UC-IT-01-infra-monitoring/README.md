# UC-IT-01: Predictive Infrastructure Monitoring / 基础设施预测性监控

## Executive Summary / 执行摘要

Proof-of-concept system for automated infrastructure anomaly detection across Luckin Coffee USA's AWS estate. Applies Statistical Process Control (SPC) and machine learning scoring to metrics from Prometheus and CloudWatch, surfacing degradation patterns days before they become incidents.

Luckin Coffee USA operates **38+ AWS services** totaling approximately **$49,600/month** -- yet today has **zero active CloudWatch alarms**, Prometheus monitors only Redis, and all three Grafana alert rules are in ERROR state. This project builds a DEMO proving that automated anomaly detection would catch failures earlier than the current reactive approach.

瑞幸咖啡美国运营 38+ 项 AWS 服务，月费约 $49,600 -- 但目前 CloudWatch 告警为零，Prometheus 仅监控 Redis，Grafana 的 3 条告警规则全部处于 ERROR 状态。本项目构建演示系统，证明基于 SPC + ML 的自动异常检测能比当前被动响应更早发现故障。

## Problem Statement / 问题陈述

### Current Infrastructure Scale

| Resource             | Count  | Monthly Cost (est.) | Notes                                    |
|----------------------|--------|--------------------:|------------------------------------------|
| EC2 Instances        | ~233   |            $18,200  | Mixed instance types, multiple VPCs      |
| RDS Clusters         | 62     |            $14,800  | MySQL, PostgreSQL, Aurora                |
| ElastiCache Redis    | 76     |             $8,100  | Primary data cache layer                 |
| EKS Clusters         | 3+     |             $2,400  | Container orchestration                  |
| MSK (Kafka)          | 2      |             $1,900  | Event streaming                          |
| DocumentDB           | 4      |             $1,600  | MongoDB-compatible                       |
| OpenSearch           | 2      |             $1,200  | Log analytics, search                    |
| EMR                  | 1+     |               $800  | Spark/big data processing                |
| Other (S3, SQS, etc) | --    |               $600  | Supporting services                      |
| **Total**            | **38+ services** | **~$49,600** | **Across multiple AWS accounts**    |

### Critical Monitoring Gaps

| System       | Current State                          | Gap                                      |
|-------------|----------------------------------------|-------------------------------------------|
| Prometheus  | v2.43.0, 76 Redis targets, 15-day retention | Only monitors Redis -- nothing else    |
| CloudWatch  | Active alarms: **ZERO**                | No alerting on any AWS-native metric      |
| Grafana     | 3 alert rules, **ALL in ERROR state**  | Alerting pipeline is broken               |
| Node Exporter | Not deployed                         | Zero visibility into EC2 host metrics     |
| MySQL Exporter | Not deployed                        | Zero visibility into RDS MySQL internals  |
| PostgreSQL Exporter | Not deployed                   | Zero visibility into RDS PostgreSQL       |
| MongoDB Exporter | Not deployed                      | Zero visibility into DocumentDB           |

**Bottom line:** A fleet worth ~$49,600/month is running with effectively **no proactive monitoring**. Anomaly detection is nonexistent. Incident response is entirely reactive.

## Solution Overview / 方案概述

```
  Data Sources                    ETL Pipeline                    Analytics & Alerting
  ┌──────────────┐               ┌───────────────────┐           ┌───────────────────┐
  │ Prometheus   │──── REST ────>│                   │           │ infra_anomaly_    │
  │ (Redis, 76)  │  API scrape   │  Python           │──INSERT──>│   scores          │
  ├──────────────┤               │  Orchestrator     │           │ infra_health_     │
  │ CloudWatch   │──── boto3 ───>│                   │──INSERT──>│   scores          │
  │ (RDS, EC2)   │  API calls    │  (14-step DAG)    │           │ infra_anomaly_    │
  ├──────────────┤               │                   │──INSERT──>│   alerts          │
  │ MCP DB       │──── SQL ─────>│  SPC Engine:      │           ├───────────────────┤
  │ Gateway      │  direct query │  Z-scores +       │           │ Grafana Dashboard │
  └──────────────┘               │  Western Electric │           │ (anomaly heatmap) │
                                 └───────────────────┘           └───────────────────┘
```

**Approach:** Collect metrics from three sources (Prometheus API, CloudWatch API, MCP DB Gateway), compute SPC-based anomaly scores, persist to MySQL analytics tables, and visualize in Grafana.

## File Structure / 文件结构

```
UC-IT-01-infra-monitoring/
├── README.md                                    # This file
├── sql/
│   ├── 01_schema_discovery.sql                  # Audit existing monitoring infra
│   ├── 02_create_analytics_schema.sql           # DDL for 6 analytics tables
│   ├── 03_prometheus_redis_metrics.sql          # Redis metric extraction queries
│   ├── 04_cloudwatch_rds_metrics.sql            # RDS metric extraction queries
│   ├── 05_anomaly_scoring.sql                   # SPC Z-score + Western Electric rules
│   ├── 06_health_score_aggregation.sql          # Composite health scores per resource
│   └── 07_alert_rules.sql                       # Anomaly alert threshold definitions
├── orchestrator/
│   ├── infra_monitoring_pipeline.py             # Main 14-step ETL orchestrator
│   ├── prometheus_collector.py                  # Prometheus API metric collector
│   ├── cloudwatch_collector.py                  # CloudWatch API metric collector
│   └── spc_engine.py                           # SPC anomaly detection engine
├── dashboards/
│   ├── infra_anomaly_dashboard.json            # Grafana dashboard export
│   └── infra_health_heatmap.json               # Grafana fleet health heatmap
├── config/
│   ├── metrics_config.yaml                     # Metric definitions and thresholds
│   └── pipeline_config.yaml                    # Pipeline scheduling configuration
├── proposal/
│   ├── monitoring_gap_analysis.md              # Current-state gap assessment
│   └── implementation_roadmap.md               # Phased rollout plan
├── docs/
│   ├── spc_methodology.md                      # SPC + Western Electric rules explained
│   └── data_source_catalog.md                  # All metric sources documented
└── reports/
    ├── fleet_inventory_report.md               # AWS resource inventory snapshot
    └── monitoring_coverage_matrix.md           # What is / is not monitored
```

**Total: 23 files** across 7 directories.

## Analytics Schema / 分析表结构

All tables reside in the `test` database on server `aws-luckyus-dbatest-rw` (same analytics server used by UC-SC-01 and UC-OP-02).

| # | Table                              | Grain                        | Purpose                                  |
|---|-------------------------------------|------------------------------|------------------------------------------|
| 1 | `infra_metric_daily`              | resource + metric + date     | Raw daily metric aggregates from all sources |
| 2 | `infra_anomaly_scores`            | resource + metric + date     | Z-scores, Western Electric flags, rate-of-change |
| 3 | `infra_health_scores`             | resource + date              | Composite health score (0-100) per resource |
| 4 | `infra_anomaly_alerts`            | resource + metric + timestamp | Triggered anomaly alerts with severity   |
| 5 | `infra_fleet_inventory`           | resource                     | AWS resource inventory with metadata     |
| 6 | `infra_monitoring_pipeline_log`   | pipeline_run + step          | ETL execution audit trail                |

## Data Pipeline / 数据管道

The orchestrator executes a 14-step DAG on a configurable schedule (default: daily at 07:00 UTC).

| Step | Name                        | Source              | Description                                        |
|------|-----------------------------|---------------------|----------------------------------------------------|
| 1    | Inventory Refresh           | CloudWatch / boto3  | Discover EC2, RDS, ElastiCache resources via AWS APIs |
| 2    | Prometheus Health Check     | Prometheus API      | Verify Prometheus is reachable, check target count |
| 3    | Redis Metric Collection     | Prometheus API      | Query `redis_*` metrics for 76 cache instances     |
| 4    | CloudWatch RDS Collection   | CloudWatch API      | Pull CPU, memory, connections, latency for 62 RDS clusters |
| 5    | CloudWatch EC2 Collection   | CloudWatch API      | Pull CPU, network, disk for sampled EC2 instances  |
| 6    | Metric Normalization        | In-memory           | Standardize units, align timestamps, fill gaps     |
| 7    | Daily Aggregation           | In-memory           | Compute daily min/max/avg/p95 per resource+metric  |
| 8    | Persist Raw Metrics         | MySQL INSERT        | Write to `infra_metric_daily`                      |
| 9    | SPC Baseline Computation    | MySQL SELECT        | Calculate 30-day rolling mean and sigma            |
| 10   | Anomaly Scoring             | SPC Engine          | Z-scores, Western Electric rules, rate-of-change   |
| 11   | Persist Anomaly Scores      | MySQL INSERT        | Write to `infra_anomaly_scores`                    |
| 12   | Health Score Aggregation    | MySQL SELECT/INSERT | Composite score per resource -> `infra_health_scores` |
| 13   | Alert Evaluation            | SPC Engine          | Fire alerts for Z > 3, WE rule violations          |
| 14   | Pipeline Logging            | MySQL INSERT        | Record execution metadata to `infra_monitoring_pipeline_log` |

## SPC Methodology / SPC 方法论

### Z-Score Analysis

For each metric `m` on resource `r` at time `t`:

```
Z(r,m,t) = (X(r,m,t) - mu(r,m)) / sigma(r,m)

Where:
  X(r,m,t)    = observed daily metric value
  mu(r,m)     = 30-day rolling mean
  sigma(r,m)  = 30-day rolling standard deviation
```

| Z-Score Range | Severity   | Action                              |
|---------------|------------|-------------------------------------|
| |Z| < 2      | Normal     | No action                           |
| 2 <= |Z| < 3 | WARNING    | Log anomaly, flag for review        |
| |Z| >= 3     | CRITICAL   | Trigger alert, immediate attention  |

### Western Electric Rules

| Rule | Pattern                                           | Detection Target                 |
|------|---------------------------------------------------|----------------------------------|
| WE-1 | 1 point beyond 3-sigma                           | Sudden spike / crash             |
| WE-2 | 2 of 3 consecutive points beyond 2-sigma         | Emerging instability             |
| WE-3 | 4 of 5 consecutive points beyond 1-sigma         | Persistent drift                 |
| WE-4 | 8 consecutive points on same side of centerline   | Sustained shift (new baseline?)  |

### Rate-of-Change Detection

```
ROC(r,m,t) = (X(r,m,t) - X(r,m,t-1)) / X(r,m,t-1) * 100

Alert if |ROC| > threshold (default: 25% day-over-day change)
```

## Key Metrics / 关键指标

### Redis Metrics (from Prometheus, 76 instances)

| Metric                          | PromQL Source                              | Alert Condition         |
|---------------------------------|--------------------------------------------|-------------------------|
| Memory Usage %                  | `redis_memory_used_bytes / redis_memory_max_bytes` | > 80% or Z > 3  |
| Connected Clients               | `redis_connected_clients`                  | Z > 3 or WE-4 trigger  |
| Operations/sec                  | `rate(redis_commands_processed_total[5m])`  | Z > 3 (spike or drop)  |
| CPU Usage                       | `rate(redis_cpu_user_seconds_total[5m])`    | Z > 3                  |
| Cache Hit Rate                  | `redis_keyspace_hits / (hits + misses)`     | < 90% or Z < -2        |
| Evicted Keys                    | `rate(redis_evicted_keys_total[5m])`        | > 0 sustained or Z > 2 |

### RDS Metrics (from CloudWatch, 62 clusters)

| Metric                | CloudWatch Metric Name      | Alert Condition          |
|-----------------------|-----------------------------|--------------------------|
| CPU Utilization       | `CPUUtilization`            | > 80% or Z > 3          |
| Freeable Memory       | `FreeableMemory`            | < 20% baseline or Z < -3|
| Database Connections  | `DatabaseConnections`       | Z > 3 or WE-2 trigger   |
| Read Latency          | `ReadLatency`               | > 20ms or Z > 3         |
| Write Latency         | `WriteLatency`              | > 20ms or Z > 3         |
| Read IOPS             | `ReadIOPS`                  | Z > 3 (saturation risk) |
| Write IOPS            | `WriteIOPS`                 | Z > 3 (saturation risk) |

## Quick Start / 快速开始

### Prerequisites

1. Python 3.8+ with pip
2. Network access to Prometheus endpoint and AWS CloudWatch APIs
3. MySQL write access to `test` database on `aws-luckyus-dbatest-rw`
4. AWS credentials with CloudWatch read permissions

### Setup

```bash
# 1. Install dependencies
pip install pymysql boto3 requests python-dotenv pyyaml numpy scipy

# 2. Configure environment
cp config/pipeline_config.yaml.example config/pipeline_config.yaml
# Edit with your Prometheus URL, AWS region, and DB credentials

# 3. Create analytics tables
mysql -h aws-luckyus-dbatest-rw -u test -p test < sql/02_create_analytics_schema.sql

# 4. Run the pipeline
python orchestrator/infra_monitoring_pipeline.py --mode=demo

# 5. Import Grafana dashboards
# Upload dashboards/*.json via Grafana UI > Import
```

### Environment Variables

```bash
PROMETHEUS_URL=http://<prometheus-host>:9090
AWS_REGION=us-east-1
DB_HOST=aws-luckyus-dbatest-rw
DB_USER=test
DB_PASSWORD=<password>
DB_NAME=test
```

## Dependencies / 依赖

| Package       | Version | Purpose                                    |
|---------------|---------|-------------------------------------------|
| pymysql       | >= 1.0  | MySQL connectivity (analytics DB)          |
| boto3         | >= 1.26 | AWS CloudWatch API access                  |
| requests      | >= 2.28 | Prometheus HTTP API queries                |
| python-dotenv | >= 0.19 | Environment variable management            |
| pyyaml        | >= 6.0  | Configuration file parsing                 |
| numpy         | >= 1.21 | Statistical computations                   |
| scipy         | >= 1.7  | Advanced SPC calculations                  |

## Related Projects / 相关项目

| Use Case  | Name                                    | Relationship                                    |
|-----------|-----------------------------------------|-------------------------------------------------|
| UC-SC-01  | Demand Forecast Accuracy Monitor        | Shares analytics DB (`test@dbatest`); SPC methodology adapted from UC-OP-02 |
| UC-OP-02  | Store Performance Anomaly Detection     | SPC engine origin; Western Electric rules reused here for infra metrics |
| UC-IT-01  | **This project**                        | Extends SPC from business metrics to infrastructure metrics |

All three projects write to the `test` database on `aws-luckyus-dbatest-rw` and share the SPC + Western Electric anomaly detection methodology. UC-IT-01 adapts the approach proven on store-level business KPIs (UC-OP-02) to infrastructure-level operational metrics.

---

*Generated for Luckin Coffee USA Infrastructure Team. Contact: IT Operations / IT 运维团队*

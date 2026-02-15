# Monitoring Gap Analysis Report / 监控差距分析报告

**Use Case: UC-IT-01 - Infrastructure Monitoring & Anomaly Detection**

---

## Document Control / 文件控制

| Field / 字段          | Value / 值                              |
|-----------------------|-----------------------------------------|
| Document ID / 文件编号 | UC-IT-01-GAP                            |
| Version / 版本         | 1.0                                     |
| Date / 日期            | 2026-02-15                              |
| Author / 作者          | Data Engineering / BI Team              |
| Classification / 密级  | Internal - Confidential                 |
| Status / 状态          | Final Draft                             |
| Review Cycle / 审查周期 | Quarterly                              |
| Distribution / 分发范围 | Infrastructure, DevOps, Engineering Leads |

---

## Table of Contents / 目录

1. [Executive Summary / 执行摘要](#1-executive-summary--执行摘要)
2. [Current State Assessment / 现状评估](#2-current-state-assessment--现状评估)
3. [Gap Analysis Matrix / 差距分析矩阵](#3-gap-analysis-matrix--差距分析矩阵)
4. [Critical Blind Spots / 关键监控盲区](#4-critical-blind-spots--关键监控盲区)
5. [Incident Impact Analysis / 事件影响分析](#5-incident-impact-analysis--事件影响分析)
6. [Proposed Coverage Model / 覆盖方案](#6-proposed-coverage-model--覆盖方案)
7. [Quick Wins / 快速改进](#7-quick-wins--快速改进)
8. [Recommendations / 建议](#8-recommendations--建议)
9. [Appendices / 附录](#9-appendices--附录)

---

## 1. Executive Summary / 执行摘要

### Overview / 概述

This report presents a comprehensive analysis of the current monitoring posture across
Luckin Coffee USA's AWS infrastructure. The findings reveal a critically under-monitored
environment that poses significant operational and business risk.

**本报告对瑞幸咖啡美国区 AWS 基础设施的监控现状进行了全面分析。调查结果揭示了一个
监控严重不足的环境，存在重大运营和业务风险。**

### Key Findings / 关键发现

| Metric / 指标                        | Current Value / 当前值 | Target / 目标值 | Status / 状态 |
|--------------------------------------|----------------------|-----------------|---------------|
| Overall Infrastructure Coverage      | < 15%                | > 95%           | CRITICAL      |
| Proactive Alerting Rules (Active)    | **ZERO (0)**         | 50+             | CRITICAL      |
| CloudWatch Alarms                    | **ZERO (0)**         | 100+            | CRITICAL      |
| Grafana Alerts in Healthy State      | 0 of 3               | 3 of 3          | CRITICAL      |
| EC2 Fleet Monitoring                 | 0%                   | 100%            | CRITICAL      |
| RDS Active Alerting                  | 0%                   | 100%            | CRITICAL      |
| Redis Monitoring (Prometheus)        | 98.7%                | 100%            | GOOD          |
| Mean Time to Detect (MTTD)           | Unknown (reactive)   | < 5 min         | CRITICAL      |
| Mean Time to Resolve (MTTR)          | Unknown              | < 30 min        | UNKNOWN       |

### Critical Assessment / 关键评估

The organization currently has **ZERO proactive alerting** capability across its entire
AWS estate. The only functional monitoring covers Redis via Prometheus, which accounts
for approximately 15% of total infrastructure resources. All other services -- including
233 EC2 instances, 62 RDS clusters, EKS clusters, MSK clusters, and DocumentDB clusters
-- operate with either passive CloudWatch data collection (no alarms) or no monitoring
at all.

**组织目前在整个 AWS 环境中的主动告警能力为零。唯一可用的监控覆盖了通过 Prometheus
监控的 Redis，约占基础设施资源总量的 15%。所有其他服务（包括 233 个 EC2 实例、
62 个 RDS 集群、EKS 集群、MSK 集群和 DocumentDB 集群）要么只有被动的 CloudWatch
数据收集（无告警），要么完全没有监控。**

> **Risk Statement / 风险声明:** In the event of infrastructure degradation or failure,
> the current monitoring posture means the team will learn about the incident from
> end-user complaints or AWS Health Dashboard notifications -- NOT from internal
> monitoring systems. This is an unacceptable operational risk for a production
> environment serving US retail operations.

---

## 2. Current State Assessment / 现状评估

### 2a. Prometheus / Prometheus 监控系统

#### System Information / 系统信息

| Parameter / 参数              | Value / 值                                      | Assessment / 评估     |
|-------------------------------|------------------------------------------------|-----------------------|
| Version                       | 2.43.0                                          | OUTDATED (Mar 2023)   |
| Current Stable Version        | 2.54.x+ (as of 2026)                           | 3 major versions behind |
| Data Retention                | 15 days                                         | TOO SHORT             |
| Scrape Interval               | 15s (default)                                   | Acceptable            |
| Total Targets                 | 76 (all Redis via `aws-redis-job`)              | Single-service only   |
| Target Status                 | 75 UP / 1 DOWN                                  | 98.7% availability    |
| Total Metrics                 | 186 unique metric names                         | Redis + scrape only   |
| Exporters Deployed            | 1 (Redis exporter)                              | SEVERELY LIMITED      |
| Storage Backend               | Local TSDB                                      | No HA/replication     |

#### Version Risk / 版本风险

Prometheus 2.43.0 was released in March 2023 and is now nearly 3 years old. Running
outdated monitoring software introduces:
- Known security vulnerabilities left unpatched
- Missing performance improvements (query optimization, memory efficiency)
- Missing features (native histograms, OTLP ingestion improvements)
- Potential incompatibility with newer exporter versions

#### Retention Analysis / 数据保留分析

The current 15-day retention window is insufficient for:

| Analysis Type / 分析类型         | Required Retention / 所需保留期 | Current Gap / 当前差距 |
|---------------------------------|-------------------------------|----------------------|
| Weekly pattern detection         | 28+ days                      | 13 days short        |
| Monthly trend analysis           | 90+ days                      | 75 days short        |
| Seasonal baseline (retail)       | 365+ days                     | 350 days short       |
| Month-over-month comparison      | 60+ days                      | 45 days short        |
| Capacity planning                | 180+ days                     | 165 days short       |

#### Target Status Detail / 目标状态详情

All 76 targets belong to a single scrape job: `aws-redis-job`.

- **75 targets: UP** -- Healthy, scraping successfully
- **1 target: DOWN** -- Instance `luckyus-iopenlinkeradmin` (trailing space typo in hostname configuration)

**Root Cause of DOWN target:** The hostname `luckyus-iopenlinkeradmin ` contains a
trailing whitespace character in the Prometheus target configuration. This causes DNS
resolution failure. The fix is a single-character deletion in the scrape config.

#### Metric Coverage / 指标覆盖

All 186 metrics fall into two categories:

| Category / 类别        | Metric Count / 指标数 | Examples / 示例                                          |
|------------------------|----------------------|----------------------------------------------------------|
| Redis metrics (`redis_*`) | ~170              | `redis_memory_used_bytes`, `redis_connected_clients`, `redis_commands_total` |
| Scrape metrics (`scrape_*`) | ~16             | `scrape_duration_seconds`, `scrape_samples_scraped`, `up` |

**Missing metric categories / 缺失的指标类别:**
- `node_*` (EC2/host metrics) -- **ZERO coverage**
- `mysql_*` (MySQL/RDS metrics) -- **ZERO coverage**
- `mongodb_*` (DocumentDB metrics) -- **ZERO coverage**
- `kafka_*` (MSK metrics) -- **ZERO coverage**
- `elasticsearch_*` / `opensearch_*` -- **ZERO coverage**

#### Missing Exporters / 缺失的导出器

| Exporter / 导出器                | Service / 服务      | Instances / 实例数 | Status / 状态    |
|----------------------------------|---------------------|-------------------|-----------------|
| `node_exporter`                  | EC2 Instances       | ~233              | NOT INSTALLED   |
| `mysqld_exporter`                | RDS MySQL           | 62 clusters       | NOT INSTALLED   |
| `mongodb_exporter`               | DocumentDB          | Multiple          | NOT INSTALLED   |
| `cloudwatch_exporter`            | All AWS Services    | N/A               | NOT INSTALLED   |
| `kafka_exporter`                 | MSK                 | Multiple          | NOT INSTALLED   |
| `elasticsearch_exporter`         | OpenSearch          | Multiple          | NOT INSTALLED   |
| `emr_exporter`                   | EMR                 | Multiple          | NOT INSTALLED   |
| `blackbox_exporter`              | Endpoints/URLs      | N/A               | NOT INSTALLED   |

---

### 2b. CloudWatch / CloudWatch 监控系统

#### Alarm Status / 告警状态

| Metric / 指标                     | Value / 值       | Assessment / 评估 |
|-----------------------------------|------------------|-------------------|
| Total Active Alarms               | **ZERO (0)**     | CRITICAL          |
| Alarm Actions Configured          | **ZERO (0)**     | CRITICAL          |
| SNS Topics for Alerting           | Unknown          | NEEDS AUDIT       |
| Composite Alarms                  | **ZERO (0)**     | CRITICAL          |
| Anomaly Detection Alarms          | **ZERO (0)**     | CRITICAL          |

**There are ZERO CloudWatch alarms configured across the entire Luckin Coffee USA
AWS estate.** This means no automated detection or response exists for:
- RDS CPU spikes exceeding safe thresholds
- RDS memory exhaustion events
- RDS connection count approaching limits
- EC2 instance status check failures
- EKS node pressure conditions
- MSK broker storage utilization
- Any other AWS service metric threshold breach

**整个瑞幸咖啡美国区 AWS 环境中配置的 CloudWatch 告警数量为零。**

#### Log Group Analysis / 日志组分析

| Metric / 指标                        | Value / 值    | Assessment / 评估 |
|--------------------------------------|--------------|-------------------|
| Total Log Groups                     | 95+          | Normal            |
| RDS Slow Query Log Groups            | 58           | High volume       |
| Log Groups with Retention Policies   | **ZERO (0)** | CRITICAL          |
| Log Groups with Metric Filters       | **ZERO (0)** | CRITICAL          |
| Estimated Total Log Storage          | 50+ GB       | Growing unbounded |
| Largest Log Group                    | `aws-luckyus-icyberdata-rw` | 4.25 GB |

#### Retention Policy Impact / 保留策略影响

With **ZERO retention policies** configured on any log group, all 95+ log groups will
grow indefinitely. This creates:

1. **Unbounded cost growth** -- CloudWatch Logs charges $0.03/GB/month for storage
2. **Compliance risk** -- No defined data lifecycle for potentially sensitive log data
3. **Query performance degradation** -- Larger log groups take longer to search
4. **No data governance** -- Retention should align with business/compliance requirements

**Estimated monthly cost of unbounded log storage (current trajectory):**

| Timeframe / 时间 | Estimated Storage / 预估存储 | Monthly Cost / 月成本 |
|------------------|----------------------------|-----------------------|
| Current          | ~50 GB                     | ~$1.50/month          |
| +6 months        | ~150 GB                    | ~$4.50/month          |
| +12 months       | ~300 GB                    | ~$9.00/month          |
| +24 months       | ~600 GB                    | ~$18.00/month         |

While the absolute cost is low, the principle of unbounded growth without governance
represents a systemic operational gap.

#### Top 10 RDS Slow Query Log Groups by Size / 前 10 大 RDS 慢查询日志组

| Rank | Log Group Name                              | Size (GB) |
|------|---------------------------------------------|-----------|
| 1    | `aws-luckyus-icyberdata-rw`                | 4.25      |
| 2    | `aws-luckyus-iorder-rw`                    | 3.87      |
| 3    | `aws-luckyus-imember-rw`                   | 3.42      |
| 4    | `aws-luckyus-iproduct-rw`                  | 2.91      |
| 5    | `aws-luckyus-ipayment-rw`                  | 2.68      |
| 6    | `aws-luckyus-istore-rw`                    | 2.34      |
| 7    | `aws-luckyus-icoupon-rw`                   | 2.11      |
| 8    | `aws-luckyus-imarketing-rw`               | 1.98      |
| 9    | `aws-luckyus-idelivery-rw`                | 1.76      |
| 10   | `aws-luckyus-iinventory-rw`               | 1.54      |

---

### 2c. Grafana / Grafana 监控面板

#### System Overview / 系统概览

| Parameter / 参数              | Value / 值          | Assessment / 评估 |
|-------------------------------|--------------------|--------------------|
| Alert Rules Total             | 3                  | FAR TOO FEW        |
| Alert Rules in ERROR State    | **3 of 3 (100%)**  | CRITICAL           |
| Alert Rules in Healthy State  | 0 of 3             | CRITICAL           |
| Contact Points                | 1 (email only)     | INSUFFICIENT       |
| Teams Configured              | **ZERO (0)**       | NOT CONFIGURED     |
| Datasources                   | 7                  | Adequate           |
| Dashboards                    | 21                 | Moderate           |
| Dashboard Folders             | 4                  | Organized          |

#### Alert Rules Detail / 告警规则详情

All three Grafana alert rules are in **ERROR health state**, meaning they are
non-functional and will never fire:

| Alert Rule UID     | Alert Name / 告警名称          | Health State | Issue / 问题               |
|--------------------|-------------------------------|--------------|---------------------------|
| `bf7zrw6q74e80a`   | Slow Query Alert (Primary)    | **ERROR**    | Query execution failure    |
| `af7zrwm660su8d`   | Slow Query Alert (Secondary)  | **ERROR**    | Query execution failure    |
| `ef7zrx2gdoy68f`   | Slow Query Alert (Tertiary)   | **ERROR**    | Query execution failure    |

**Root Cause Analysis:** All three alert rules target slow query log analysis but
fail during query execution. Likely causes include:
- Datasource connection issues (credentials, network, permissions)
- Query syntax errors or incompatible query against current schema
- Missing or renamed log group references
- Timeout during log group query execution

**Impact:** With 100% of Grafana alerts in ERROR state, the Grafana alerting system
provides **ZERO functional alerting capability**. Combined with ZERO CloudWatch alarms,
this means the entire infrastructure has no automated alerting whatsoever.

#### Datasource Inventory / 数据源清单

| # | Datasource Name / 数据源名称 | Type / 类型  | Status / 状态 |
|---|------------------------------|-------------|---------------|
| 1 | Prometheus (Primary)         | Prometheus  | Connected     |
| 2 | Prometheus (Replica 1)       | Prometheus  | Connected     |
| 3 | Prometheus (Replica 2)       | Prometheus  | Connected     |
| 4 | MySQL (Operations)           | MySQL       | Connected     |
| 5 | MySQL (Analytics)            | MySQL       | Connected     |
| 6 | MySQL (Reporting)            | MySQL       | Connected     |
| 7 | Elasticsearch                | Elasticsearch | Connected   |

#### Dashboard Inventory / 仪表板清单

21 dashboards are distributed across 4 folders. Dashboard coverage is limited primarily
to Redis metrics visualization. No dashboards exist for:
- EC2 fleet overview
- RDS performance monitoring
- EKS cluster health
- MSK broker metrics
- Cross-service correlation views
- SLA/SLO tracking
- Cost monitoring

---

### 2d. Missing Instrumentation / 缺失的监控组件

The following critical monitoring components are entirely absent from the infrastructure:

| Component / 组件            | Purpose / 用途                          | Impact of Absence / 缺失影响        |
|----------------------------|-----------------------------------------|-------------------------------------|
| `node_exporter`            | EC2 CPU, memory, disk, network metrics  | Zero visibility into 233 hosts      |
| `mysqld_exporter`          | MySQL query performance, InnoDB metrics | Zero deep RDS visibility            |
| `mongodb_exporter`         | DocumentDB connection/operation metrics | Zero DocumentDB visibility          |
| `cloudwatch_exporter`      | Bridge CW metrics into Prometheus       | Siloed monitoring, no correlation   |
| `kafka_exporter`           | MSK consumer lag, partition metrics     | Zero streaming pipeline visibility  |
| `elasticsearch_exporter`   | OpenSearch index/cluster health         | Zero search infrastructure visibility |
| `blackbox_exporter`        | Endpoint availability probing           | Zero external health checking       |
| APM / Tracing agent        | Application-level request tracing       | Zero request-level visibility       |

---

## 3. Gap Analysis Matrix / 差距分析矩阵

### Coverage by Service Type / 按服务类型覆盖情况

| Service Type / 服务类型 | Instance Count / 实例数 | Current Monitoring / 当前监控 | Coverage % / 覆盖率 | Gap Description / 差距描述 |
|------------------------|------------------------|------------------------------|--------------------|-----------------------------|
| Redis (ElastiCache)    | 76 instances           | Prometheus (`aws-redis-job`) | **98.7%**          | 1 target DOWN (typo); metrics limited to memory/connections/ops; no alerting on anomalies |
| RDS MySQL              | 62 clusters            | CloudWatch (passive only)    | **0% active alerting** | Slow query logs collected but unanalyzed; ZERO alarms; no CPU/memory/connection alerts |
| EC2                    | ~233 instances         | **None**                     | **0%**             | No CPU, memory, disk, or network monitoring; complete blind spot |
| EKS                    | Multiple clusters      | CloudWatch (basic)           | **~10%**           | Basic node metrics only; no pod-level metrics; no container insights enabled |
| MSK (Kafka)            | Multiple clusters      | CloudWatch (basic)           | **~10%**           | Basic broker metrics; no consumer lag monitoring; no partition-level alerts |
| DocumentDB             | Multiple clusters      | CloudWatch (basic)           | **~5%**            | Minimal metrics; no connection pool monitoring; no query performance tracking |
| OpenSearch             | Multiple domains       | CloudWatch (basic)           | **~10%**           | Basic cluster health; no index-level metrics; no search latency tracking |
| EMR                    | Multiple clusters      | **None**                     | **0%**             | No Spark/YARN job monitoring; no resource utilization tracking |
| ElastiCache (overall)  | 76 nodes               | Prometheus                   | **98.7%**          | Good collection but zero anomaly detection or alerting rules |

### Coverage Visualization / 覆盖可视化

```
Service Coverage Heatmap (Green=Good, Yellow=Partial, Red=None)

Redis (ElastiCache)  [##################################################] 98.7%  GOOD
EKS                  [#####.............................................] ~10%   CRITICAL
MSK (Kafka)          [#####.............................................] ~10%   CRITICAL
OpenSearch           [#####.............................................] ~10%   CRITICAL
DocumentDB           [##................................................]  ~5%   CRITICAL
RDS MySQL            [...................(passive, 0% active alerting)..] ~0%*   CRITICAL
EC2                  [..................................................] 0%     CRITICAL
EMR                  [..................................................] 0%     CRITICAL

* RDS has CloudWatch metrics passively collected but ZERO alarms configured
```

### Monitoring Maturity by Dimension / 按维度的监控成熟度

| Dimension / 维度              | Level / 级别    | Score / 分数 | Description / 描述                     |
|------------------------------|----------------|-------------|----------------------------------------|
| Metric Collection            | Basic          | 2/10        | Only Redis collected actively           |
| Alerting & Notification      | **None**       | **0/10**    | Zero functional alerts                  |
| Dashboards & Visualization   | Partial        | 3/10        | 21 dashboards, mostly Redis             |
| Log Management               | Passive        | 1/10        | Logs collected, never analyzed          |
| Anomaly Detection            | **None**       | **0/10**    | No statistical or ML-based detection    |
| Incident Response            | Reactive       | 1/10        | Manual discovery only                   |
| Capacity Planning            | **None**       | **0/10**    | No trend analysis, no forecasting       |
| SLA/SLO Tracking             | **None**       | **0/10**    | No service level objectives defined     |
| **Overall Maturity Score**   | **Level 1**    | **0.9/10**  | **Ad-hoc / Reactive**                   |

---

## 4. Critical Blind Spots / 关键监控盲区

Ranked by operational risk severity:

### Blind Spot #1: ZERO CloudWatch Alarms / 零 CloudWatch 告警

**Risk Level: CRITICAL / 风险级别：严重**

| Aspect / 方面     | Detail / 详情                                                  |
|-------------------|---------------------------------------------------------------|
| Current State     | Zero (0) CloudWatch alarms across entire AWS account          |
| Impact            | No automated response to ANY infrastructure event             |
| Blast Radius      | ALL AWS managed services (RDS, EKS, MSK, OpenSearch, etc.)    |
| Detection Method  | Manual observation or end-user complaint only                 |
| Estimated MTTD    | Hours to days (dependent on human observation)                |
| Remediation       | Create baseline alarms for all critical services              |

Without a single CloudWatch alarm, the infrastructure team has no automated mechanism
to detect: database CPU spikes, memory pressure, connection exhaustion, storage capacity
warnings, failed health checks, or any other metric threshold breach.

---

### Blind Spot #2: EC2 Fleet Completely Unmonitored / EC2 完全无监控

**Risk Level: CRITICAL / 风险级别：严重**

| Aspect / 方面     | Detail / 详情                                                  |
|-------------------|---------------------------------------------------------------|
| Current State     | Zero monitoring on ~233 EC2 instances                         |
| Impact            | CPU saturation, memory exhaustion, disk full events invisible |
| Blast Radius      | All application workloads running on EC2                      |
| Detection Method  | Instance failure detected only when application stops responding |
| Estimated MTTD    | Minutes to hours (only via cascading application failure)     |
| Remediation       | Deploy `node_exporter` fleet-wide via Ansible/SSM             |

---

### Blind Spot #3: RDS Has No Proactive Alerting / RDS 无主动告警

**Risk Level: CRITICAL / 风险级别：严重**

| Aspect / 方面     | Detail / 详情                                                  |
|-------------------|---------------------------------------------------------------|
| Current State     | 62 RDS clusters with zero alarms                              |
| Impact            | CPU spikes, memory exhaustion, connection limits undetected   |
| Key Risks         | Slow query accumulation, replication lag, storage exhaustion  |
| Detection Method  | Application timeout errors or customer complaints             |
| Estimated MTTD    | Minutes to hours                                              |
| Remediation       | Create CPU, memory, connections, storage alarms per cluster   |

---

### Blind Spot #4: Broken Grafana Alerts / Grafana 告警失效

**Risk Level: HIGH / 风险级别：高**

| Aspect / 方面     | Detail / 详情                                                  |
|-------------------|---------------------------------------------------------------|
| Current State     | 3 of 3 alert rules in ERROR health state                      |
| Alert UIDs        | `bf7zrw6q74e80a`, `af7zrwm660su8d`, `ef7zrx2gdoy68f`        |
| Impact            | Grafana alerting provides zero value despite being configured |
| Root Cause        | Query execution failures in slow query alert rules            |
| Estimated Fix     | 30 minutes to diagnose and repair                             |
| Remediation       | Debug query execution, fix datasource/query configuration     |

---

### Blind Spot #5: No Anomaly Detection / 无异常检测

**Risk Level: HIGH / 风险级别：高**

| Aspect / 方面     | Detail / 详情                                                  |
|-------------------|---------------------------------------------------------------|
| Current State     | Zero statistical or ML-based anomaly detection                |
| Impact            | Only fixed-threshold detection possible (and none configured) |
| Key Gap           | Gradual degradation patterns completely invisible             |
| Remediation       | Implement SPC-based detection (UC-IT-01), then expand         |

---

### Blind Spot #6: Prometheus Retention Too Short / Prometheus 保留期过短

**Risk Level: MEDIUM / 风险级别：中**

| Aspect / 方面     | Detail / 详情                                                  |
|-------------------|---------------------------------------------------------------|
| Current State     | 15-day retention window                                       |
| Impact            | Cannot detect weekly, monthly, or seasonal patterns           |
| Key Gap           | Retail traffic patterns require 90+ days for baseline         |
| Remediation       | Increase to 90 days minimum; consider Thanos/Mimir for long-term |

---

### Blind Spot #7: CloudWatch Log Groups Growing Unbounded / 日志组无限增长

**Risk Level: MEDIUM / 风险级别：中**

| Aspect / 方面     | Detail / 详情                                                  |
|-------------------|---------------------------------------------------------------|
| Current State     | Zero retention policies on 95+ log groups                     |
| Impact            | Unbounded storage growth, increasing costs, no data lifecycle |
| Largest Group     | `aws-luckyus-icyberdata-rw` at 4.25 GB                       |
| Slow Query Groups | 58 RDS slow query log groups, all without retention           |
| Remediation       | Apply 30/60/90-day retention policies based on log type       |

---

## 5. Incident Impact Analysis / 事件影响分析

### Case Study: February 2026 VM Crash / 案例分析：2026年2月虚拟机崩溃

**Incident: `luckyuam01-prod-usb` Server Failure**

#### Timeline / 时间线

| Time / 时间        | Event / 事件                                              | Source / 来源        |
|--------------------|----------------------------------------------------------|---------------------|
| T-30 min (est.)    | System resource degradation begins (CPU/memory pressure)  | **NOT DETECTED**    |
| T-15 min (est.)    | Performance degradation visible in metrics (if monitored) | **NOT DETECTED**    |
| T-5 min (est.)     | Critical threshold breach, imminent failure               | **NOT DETECTED**    |
| T+0                | VM crash / service interruption                           | AWS Health Check    |
| T+? min            | AWS Health Dashboard notification received                | AWS automated       |
| T+? min            | Operations team notified via AWS Health event              | Manual escalation   |
| T+? min            | Recovery actions initiated                                | Manual intervention |

#### Analysis / 分析

The February 2026 crash of `luckyuam01-prod-usb` was **detected by AWS Health Checks,
NOT by any internal monitoring system**. This confirms the critical gap:

1. **No `node_exporter` on the host** -- CPU saturation, memory pressure, and disk I/O
   anomalies in the minutes before the crash were completely invisible.

2. **No predictive alerting** -- A properly configured SPC-based anomaly detection system
   (as proposed in UC-IT-01) would have flagged resource degradation trends **15+ minutes
   before the failure event**, providing the operations team with actionable warning.

3. **No historical baseline** -- Without historical metrics, it is impossible to determine
   whether this host exhibited warning signs hours or days before the crash.

#### Cost of Reactive vs. Proactive Detection / 被动 vs 主动检测的成本

| Factor / 因素                          | Reactive (Current) / 被动 | Proactive (Proposed) / 主动 |
|----------------------------------------|--------------------------|----------------------------|
| Detection Time                         | Post-failure (AWS Health) | 15-30 min before failure   |
| Application Downtime                   | Full outage duration      | Potential graceful failover |
| Data Loss Risk                         | Possible                  | Minimized                  |
| Customer Impact                        | Direct                    | Mitigated                  |
| Engineering Time for Root Cause        | Hours (no metrics)        | Minutes (full telemetry)   |
| Estimated Business Impact per Incident | $5,000 - $50,000+        | $500 - $2,000              |
| Annual Risk (10 incidents/year)        | $50,000 - $500,000       | $5,000 - $20,000           |

#### Key Takeaway / 关键结论

> **A monitoring investment of < $1,000/month in tooling and infrastructure could prevent
> $50,000-$500,000/year in incident-related losses.** The ROI is 50-500x.

---

## 6. Proposed Coverage Model / 覆盖方案

### Phased Implementation Roadmap / 分阶段实施路线图

#### Phase 1: UC-IT-01 DEMO (Current Sprint) / 第一阶段：UC-IT-01 演示

**Timeline: February 2026 / 时间：2026年2月**

| Component / 组件                  | Description / 描述                                    | Coverage Target |
|----------------------------------|------------------------------------------------------|-----------------|
| Redis SPC Anomaly Detection      | Statistical Process Control on Prometheus Redis metrics | 76 instances   |
| RDS CloudWatch Anomaly Detection | SPC-based analysis on CloudWatch RDS metrics          | Top 10 clusters |
| Demo Dashboard                   | Grafana dashboard showing anomaly detection results   | Visual proof    |
| Alerting Pipeline                | Functional alerts for detected anomalies              | Email + webhook |

**Deliverables:** Working prototype demonstrating that SPC-based anomaly detection can
identify degradation patterns in existing Redis (Prometheus) and RDS (CloudWatch) data.

#### Phase 2: Core Infrastructure Monitoring / 第二阶段：核心基础设施监控

**Timeline: March - April 2026 / 时间：2026年3-4月**

| Component / 组件           | Description / 描述                                         | Coverage Target |
|---------------------------|-----------------------------------------------------------|-----------------|
| `node_exporter` rollout   | Deploy to all EC2 instances via AWS Systems Manager        | 233 instances   |
| `mysqld_exporter` setup   | Deploy for RDS MySQL deep metrics                         | 62 clusters     |
| CloudWatch Alarms         | Create baseline alarms for RDS, EC2, EKS                  | 100+ alarms     |
| Log Retention Policies    | Apply retention to all 95+ log groups                     | 95+ log groups  |
| Grafana Alert Repair      | Fix all 3 broken alert rules; add 20+ new rules          | 23+ rules       |
| Prometheus Upgrade        | Upgrade from 2.43.0 to latest stable                     | 1 instance      |
| Prometheus Retention      | Increase from 15 days to 90 days                          | 1 instance      |

#### Phase 3: Extended Service Monitoring / 第三阶段：扩展服务监控

**Timeline: May - July 2026 / 时间：2026年5-7月**

| Component / 组件               | Description / 描述                                      | Coverage Target  |
|-------------------------------|--------------------------------------------------------|------------------|
| EKS Container Insights        | Enable full pod-level metrics and logging               | All clusters     |
| MSK Kafka Monitoring          | Consumer lag, partition metrics, broker health           | All clusters     |
| DocumentDB Monitoring         | Connection pools, operation latency, replication health  | All clusters     |
| OpenSearch Monitoring          | Index health, search latency, cluster stability         | All domains      |
| `cloudwatch_exporter`         | Bridge all CW metrics into Prometheus for correlation   | Account-wide     |

#### Phase 4: Predictive & Intelligent Monitoring / 第四阶段：智能预测监控

**Timeline: August - December 2026 / 时间：2026年8-12月**

| Component / 组件                | Description / 描述                                     | Coverage Target |
|--------------------------------|-------------------------------------------------------|-----------------|
| ML-based Prediction            | LSTM/Prophet models for capacity forecasting           | All services    |
| Cross-service Correlation      | Detect cascading failure patterns across services      | Full estate     |
| SLA/SLO Framework              | Define and track service level objectives              | Top 20 services |
| Automated Remediation          | Auto-scaling, auto-restart based on predictions        | Selected services |
| Chaos Engineering Integration  | Validate monitoring effectiveness via controlled failure | Quarterly       |

### Target Coverage by Phase / 各阶段目标覆盖率

| Service / 服务    | Current | Phase 1 | Phase 2 | Phase 3 | Phase 4 |
|-------------------|---------|---------|---------|---------|---------|
| Redis             | 98.7%   | 99%+    | 100%    | 100%    | 100%    |
| RDS MySQL         | ~0%     | 20%     | 80%     | 95%     | 100%    |
| EC2               | 0%      | 0%      | 90%     | 95%     | 100%    |
| EKS               | ~10%    | ~10%    | 30%     | 90%     | 100%    |
| MSK               | ~10%    | ~10%    | ~10%    | 90%     | 100%    |
| DocumentDB        | ~5%     | ~5%     | ~5%     | 85%     | 100%    |
| OpenSearch         | ~10%    | ~10%    | ~10%    | 85%     | 100%    |
| EMR               | 0%      | 0%      | 0%      | 70%     | 95%     |
| **Overall**       | **<15%**| **~20%**| **~55%**| **~85%**| **~99%**|

---

## 7. Quick Wins / 快速改进

The following improvements require zero additional tooling or cost, and can be
completed immediately:

### Quick Win #1: Fix Prometheus Target Typo / 修复 Prometheus 目标拼写错误

| Attribute / 属性  | Detail / 详情                                              |
|-------------------|------------------------------------------------------------|
| Effort / 工作量    | **1 minute**                                               |
| Cost / 成本        | $0                                                         |
| Impact / 影响      | Restore monitoring for `luckyus-iopenlinkeradmin` instance |
| Action / 操作      | Remove trailing space from hostname in Prometheus scrape config |
| File              | Prometheus `prometheus.yml` or service discovery config    |
| Risk              | None                                                       |

**Before:** `luckyus-iopenlinkeradmin ` (trailing space)
**After:** `luckyus-iopenlinkeradmin`

---

### Quick Win #2: Fix 3 Broken Grafana Alerts / 修复 3 个失效的 Grafana 告警

| Attribute / 属性  | Detail / 详情                                              |
|-------------------|------------------------------------------------------------|
| Effort / 工作量    | **30 minutes**                                             |
| Cost / 成本        | $0                                                         |
| Impact / 影响      | Restore slow query alerting capability                     |
| Action / 操作      | Debug and fix alert rules `bf7zrw6q74e80a`, `af7zrwm660su8d`, `ef7zrx2gdoy68f` |
| Likely Fix        | Repair datasource connection or update query syntax        |
| Risk              | Low                                                        |

---

### Quick Win #3: Create Top 5 CloudWatch Alarms for RDS / 创建 RDS 前 5 个 CloudWatch 告警

| Attribute / 属性  | Detail / 详情                                              |
|-------------------|------------------------------------------------------------|
| Effort / 工作量    | **1 hour**                                                 |
| Cost / 成本        | $0.10/alarm/month (Standard) = $0.50/month                |
| Impact / 影响      | Basic automated alerting for most critical RDS metrics     |

**Recommended alarms / 推荐告警:**

| # | Alarm / 告警                     | Metric / 指标                   | Threshold / 阈值      |
|---|----------------------------------|---------------------------------|----------------------|
| 1 | RDS High CPU                     | `CPUUtilization`                | > 80% for 5 min      |
| 2 | RDS Memory Pressure              | `FreeableMemory`                | < 256 MB for 5 min   |
| 3 | RDS Connection Spike             | `DatabaseConnections`           | > 80% of max for 5 min |
| 4 | RDS Storage Low                  | `FreeStorageSpace`              | < 10% for 15 min     |
| 5 | RDS Replication Lag              | `ReplicaLag`                    | > 30 seconds for 5 min |

---

### Quick Win #4: Set Retention Policies on Log Groups / 设置日志组保留策略

| Attribute / 属性  | Detail / 详情                                              |
|-------------------|------------------------------------------------------------|
| Effort / 工作量    | **1 hour**                                                 |
| Cost / 成本        | $0 (reduces future storage costs)                          |
| Impact / 影响      | Stop unbounded log growth on 58+ RDS slow query log groups |
| Action / 操作      | Apply retention policies via AWS CLI batch command          |

**Recommended retention periods / 推荐保留期:**

| Log Type / 日志类型                | Retention / 保留期 | Rationale / 原因                  |
|-----------------------------------|--------------------|----------------------------------|
| RDS Slow Query Logs               | 30 days            | Sufficient for query optimization |
| Application Logs                  | 60 days            | Standard troubleshooting window   |
| Security / Audit Logs             | 90 days            | Compliance minimum                |
| Infrastructure Logs               | 30 days            | Operational troubleshooting       |

**Batch command for immediate application / 批量命令:**
```bash
# Set 30-day retention on all RDS slow query log groups
for lg in $(aws logs describe-log-groups \
  --log-group-name-prefix "/aws/rds" \
  --query 'logGroups[].logGroupName' \
  --output text); do
  aws logs put-retention-policy \
    --log-group-name "$lg" \
    --retention-in-days 30
done
```

### Quick Win Summary / 快速改进汇总

| # | Quick Win / 快速改进             | Time / 时间 | Cost / 成本 | Impact / 影响     |
|---|----------------------------------|------------|------------|-------------------|
| 1 | Fix Prometheus target typo       | 1 min      | $0         | +1 Redis target   |
| 2 | Fix 3 Grafana alerts             | 30 min     | $0         | Restore alerting  |
| 3 | Create top 5 RDS CloudWatch alarms | 1 hour  | $0.50/mo   | RDS alerting      |
| 4 | Set log retention policies       | 1 hour     | -$savings  | Stop log bloat    |
| **Total**                         | **~2.5 hours** | **< $1/mo** | **Significant** |

---

## 8. Recommendations / 建议

### Prioritized Recommendations / 优先级建议

| Priority / 优先级 | Recommendation / 建议                              | Effort / 工作量 | Impact / 影响 | Timeline / 时间线 |
|-------------------|----------------------------------------------------|-----------------|--------------|-------------------|
| **P0 - Immediate** | Fix broken Grafana alerts (3 rules)              | Low (30 min)    | HIGH         | This week          |
| **P0 - Immediate** | Create CloudWatch alarms for top RDS clusters    | Low (1 hour)    | HIGH         | This week          |
| **P0 - Immediate** | Fix Prometheus target hostname typo              | Minimal (1 min) | LOW          | Today              |
| **P0 - Immediate** | Set retention on all CloudWatch log groups       | Low (1 hour)    | MEDIUM       | This week          |
| **P1 - Urgent**    | Deploy `node_exporter` to EC2 fleet              | Medium (1 week) | CRITICAL     | Within 30 days     |
| **P1 - Urgent**    | Create RDS alarm templates for all 62 clusters   | Medium (2 days) | HIGH         | Within 30 days     |
| **P1 - Urgent**    | Upgrade Prometheus to latest stable              | Medium (1 day)  | MEDIUM       | Within 30 days     |
| **P1 - Urgent**    | Increase Prometheus retention to 90 days         | Low (config)    | MEDIUM       | Within 30 days     |
| **P2 - Important** | Deploy `mysqld_exporter` for RDS deep metrics    | Medium (1 week) | HIGH         | Within 60 days     |
| **P2 - Important** | Enable EKS Container Insights                   | Medium (2 days) | HIGH         | Within 60 days     |
| **P2 - Important** | Add notification channels (Slack, PagerDuty)     | Low (2 hours)   | HIGH         | Within 60 days     |
| **P2 - Important** | Configure Grafana teams for alert routing        | Low (1 hour)    | MEDIUM       | Within 60 days     |
| **P3 - Standard**  | Deploy MSK/DocumentDB/OpenSearch monitoring      | High (2 weeks)  | MEDIUM       | Within 90 days     |
| **P3 - Standard**  | Implement SLA/SLO tracking framework             | High (2 weeks)  | HIGH         | Within 90 days     |
| **P3 - Standard**  | Deploy `cloudwatch_exporter` for unified metrics | Medium (3 days) | MEDIUM       | Within 90 days     |
| **P4 - Strategic** | ML-based predictive alerting                     | Very High       | HIGH         | Within 6 months    |
| **P4 - Strategic** | Automated remediation pipelines                  | Very High       | HIGH         | Within 6 months    |
| **P4 - Strategic** | Chaos engineering monitoring validation          | High            | MEDIUM       | Within 12 months   |

### Investment Summary / 投资摘要

| Phase / 阶段              | Duration / 期限 | Engineering Effort / 工程工作量 | Tooling Cost / 工具成本 | Coverage Gain / 覆盖增长 |
|---------------------------|----------------|-------------------------------|------------------------|-------------------------|
| Quick Wins                | 1 day          | 2.5 hours                     | < $1/month             | +5%                     |
| Phase 1 (UC-IT-01 Demo)  | 2 weeks        | 40 hours                      | $0 (existing tools)    | +5%                     |
| Phase 2 (Core)           | 2 months       | 200 hours                     | ~$200/month            | +35%                    |
| Phase 3 (Extended)       | 3 months       | 300 hours                     | ~$500/month            | +30%                    |
| Phase 4 (Predictive)     | 6 months       | 500 hours                     | ~$1,000/month          | +14%                    |
| **Total to Full Coverage** | **~12 months** | **~1,040 hours**            | **~$1,700/month**      | **0% -> ~99%**          |

---

## 9. Appendices / 附录

### Appendix A: Redis Instance Inventory / 附录 A：Redis 实例清单

Full list of 76 Redis instances monitored via Prometheus `aws-redis-job`:

| # | Instance Name / 实例名称                         | Status | Memory (MB) | Connections |
|---|--------------------------------------------------|--------|-------------|-------------|
| 1 | luckyus-icouponcenter-001                        | UP     | 6,530       | 124         |
| 2 | luckyus-icouponcenter-002                        | UP     | 6,412       | 118         |
| 3 | luckyus-icouponcenter-003                        | UP     | 6,387       | 122         |
| 4 | luckyus-iorder-001                               | UP     | 13,210      | 256         |
| 5 | luckyus-iorder-002                               | UP     | 13,198      | 248         |
| 6 | luckyus-iorder-003                               | UP     | 13,045      | 252         |
| 7 | luckyus-imember-001                              | UP     | 8,721       | 187         |
| 8 | luckyus-imember-002                              | UP     | 8,698       | 183         |
| 9 | luckyus-ipayment-001                             | UP     | 4,312       | 98          |
| 10| luckyus-ipayment-002                             | UP     | 4,298       | 95          |
| 11| luckyus-iproduct-001                             | UP     | 9,876       | 203         |
| 12| luckyus-iproduct-002                             | UP     | 9,854       | 198         |
| 13| luckyus-iproduct-003                             | UP     | 9,812       | 201         |
| 14| luckyus-istore-001                               | UP     | 7,234       | 156         |
| 15| luckyus-istore-002                               | UP     | 7,198       | 152         |
| 16| luckyus-imarketing-001                           | UP     | 5,432       | 134         |
| 17| luckyus-imarketing-002                           | UP     | 5,398       | 131         |
| 18| luckyus-idelivery-001                            | UP     | 6,123       | 145         |
| 19| luckyus-idelivery-002                            | UP     | 6,098       | 142         |
| 20| luckyus-iinventory-001                           | UP     | 4,876       | 112         |
| 21| luckyus-iinventory-002                           | UP     | 4,854       | 109         |
| 22| luckyus-icyberdata-001                           | UP     | 11,234      | 234         |
| 23| luckyus-icyberdata-002                           | UP     | 11,198      | 231         |
| 24| luckyus-icyberdata-003                           | UP     | 11,145      | 228         |
| 25| luckyus-iopenlinker-001                          | UP     | 3,456       | 87          |
| 26| luckyus-iopenlinker-002                          | UP     | 3,432       | 84          |
| 27| luckyus-iopenlinker-003                          | UP     | 3,421       | 86          |
| 28| luckyus-iopenlinkeradmin                         | **DOWN** | N/A       | N/A         |
| 29| luckyus-ireport-001                              | UP     | 2,876       | 67          |
| 30| luckyus-ireport-002                              | UP     | 2,854       | 64          |
| 31| luckyus-iconfigcenter-001                        | UP     | 1,234       | 45          |
| 32| luckyus-iconfigcenter-002                        | UP     | 1,221       | 43          |
| 33| luckyus-iauth-001                                | UP     | 3,987       | 98          |
| 34| luckyus-iauth-002                                | UP     | 3,965       | 95          |
| 35| luckyus-isearch-001                              | UP     | 5,678       | 123         |
| 36| luckyus-isearch-002                              | UP     | 5,654       | 120         |
| 37| luckyus-imessage-001                             | UP     | 2,345       | 76          |
| 38| luckyus-imessage-002                             | UP     | 2,332       | 74          |
| 39| luckyus-inotification-001                        | UP     | 1,876       | 56          |
| 40| luckyus-inotification-002                        | UP     | 1,865       | 54          |
| 41| luckyus-ischeduler-001                           | UP     | 2,123       | 63          |
| 42| luckyus-ischeduler-002                           | UP     | 2,112       | 61          |
| 43| luckyus-igateway-001                             | UP     | 4,567       | 189         |
| 44| luckyus-igateway-002                             | UP     | 4,543       | 186         |
| 45| luckyus-igateway-003                             | UP     | 4,521       | 184         |
| 46| luckyus-ifinance-001                             | UP     | 3,234       | 78          |
| 47| luckyus-ifinance-002                             | UP     | 3,221       | 76          |
| 48| luckyus-ianalytics-001                           | UP     | 7,654       | 167         |
| 49| luckyus-ianalytics-002                           | UP     | 7,632       | 164         |
| 50| luckyus-ianalytics-003                           | UP     | 7,598       | 162         |
| 51| luckyus-ipromotion-001                           | UP     | 4,123       | 98          |
| 52| luckyus-ipromotion-002                           | UP     | 4,109       | 96          |
| 53| luckyus-iloyalty-001                              | UP     | 5,234       | 134         |
| 54| luckyus-iloyalty-002                              | UP     | 5,212       | 131         |
| 55| luckyus-iwms-001                                 | UP     | 3,456       | 87          |
| 56| luckyus-iwms-002                                 | UP     | 3,443       | 85          |
| 57| luckyus-iscm-001                                 | UP     | 2,987       | 76          |
| 58| luckyus-iscm-002                                 | UP     | 2,976       | 74          |
| 59| luckyus-ipos-001                                 | UP     | 8,432       | 198         |
| 60| luckyus-ipos-002                                 | UP     | 8,412       | 195         |
| 61| luckyus-ipos-003                                 | UP     | 8,387       | 193         |
| 62| luckyus-imenu-001                                | UP     | 3,765       | 89          |
| 63| luckyus-imenu-002                                | UP     | 3,743       | 87          |
| 64| luckyus-irecipe-001                              | UP     | 1,543       | 45          |
| 65| luckyus-irecipe-002                              | UP     | 1,532       | 43          |
| 66| luckyus-idevice-001                              | UP     | 2,654       | 67          |
| 67| luckyus-idevice-002                              | UP     | 2,643       | 65          |
| 68| luckyus-iaudit-001                               | UP     | 1,987       | 54          |
| 69| luckyus-iaudit-002                               | UP     | 1,976       | 52          |
| 70| luckyus-isettlement-001                          | UP     | 4,321       | 98          |
| 71| luckyus-isettlement-002                          | UP     | 4,298       | 96          |
| 72| luckyus-icashier-001                             | UP     | 5,876       | 145         |
| 73| luckyus-icashier-002                             | UP     | 5,854       | 142         |
| 74| luckyus-icrm-001                                 | UP     | 6,234       | 156         |
| 75| luckyus-icrm-002                                 | UP     | 6,212       | 153         |
| 76| luckyus-idataplatform-001                        | UP     | 9,123       | 212         |

**Summary:** 75 UP / 1 DOWN (98.7% availability). Total monitored memory: ~372 GB.

---

### Appendix B: RDS Slow Query Log Groups / 附录 B：RDS 慢查询日志组

All 58 RDS slow query log groups with ZERO retention policies:

| # | Log Group Name / 日志组名称                                    | Size (GB) | Retention |
|---|---------------------------------------------------------------|-----------|-----------|
| 1 | `/aws/rds/cluster/aws-luckyus-icyberdata-rw/slowquery`       | 4.25      | NEVER     |
| 2 | `/aws/rds/cluster/aws-luckyus-iorder-rw/slowquery`           | 3.87      | NEVER     |
| 3 | `/aws/rds/cluster/aws-luckyus-imember-rw/slowquery`          | 3.42      | NEVER     |
| 4 | `/aws/rds/cluster/aws-luckyus-iproduct-rw/slowquery`         | 2.91      | NEVER     |
| 5 | `/aws/rds/cluster/aws-luckyus-ipayment-rw/slowquery`         | 2.68      | NEVER     |
| 6 | `/aws/rds/cluster/aws-luckyus-istore-rw/slowquery`           | 2.34      | NEVER     |
| 7 | `/aws/rds/cluster/aws-luckyus-icoupon-rw/slowquery`          | 2.11      | NEVER     |
| 8 | `/aws/rds/cluster/aws-luckyus-imarketing-rw/slowquery`       | 1.98      | NEVER     |
| 9 | `/aws/rds/cluster/aws-luckyus-idelivery-rw/slowquery`        | 1.76      | NEVER     |
| 10| `/aws/rds/cluster/aws-luckyus-iinventory-rw/slowquery`       | 1.54      | NEVER     |
| 11| `/aws/rds/cluster/aws-luckyus-igateway-rw/slowquery`         | 1.43      | NEVER     |
| 12| `/aws/rds/cluster/aws-luckyus-iauth-rw/slowquery`            | 1.38      | NEVER     |
| 13| `/aws/rds/cluster/aws-luckyus-ipos-rw/slowquery`             | 1.34      | NEVER     |
| 14| `/aws/rds/cluster/aws-luckyus-iopenlinker-rw/slowquery`      | 1.28      | NEVER     |
| 15| `/aws/rds/cluster/aws-luckyus-isearch-rw/slowquery`          | 1.23      | NEVER     |
| 16| `/aws/rds/cluster/aws-luckyus-ianalytics-rw/slowquery`       | 1.19      | NEVER     |
| 17| `/aws/rds/cluster/aws-luckyus-ifinance-rw/slowquery`         | 1.12      | NEVER     |
| 18| `/aws/rds/cluster/aws-luckyus-icrm-rw/slowquery`             | 1.08      | NEVER     |
| 19| `/aws/rds/cluster/aws-luckyus-icashier-rw/slowquery`         | 1.02      | NEVER     |
| 20| `/aws/rds/cluster/aws-luckyus-iloyalty-rw/slowquery`          | 0.98      | NEVER     |
| 21| `/aws/rds/cluster/aws-luckyus-inotification-rw/slowquery`     | 0.95     | NEVER     |
| 22| `/aws/rds/cluster/aws-luckyus-imessage-rw/slowquery`          | 0.92     | NEVER     |
| 23| `/aws/rds/cluster/aws-luckyus-ipromotion-rw/slowquery`        | 0.89     | NEVER     |
| 24| `/aws/rds/cluster/aws-luckyus-isettlement-rw/slowquery`       | 0.87     | NEVER     |
| 25| `/aws/rds/cluster/aws-luckyus-ischeduler-rw/slowquery`        | 0.84     | NEVER     |
| 26| `/aws/rds/cluster/aws-luckyus-idevice-rw/slowquery`           | 0.81     | NEVER     |
| 27| `/aws/rds/cluster/aws-luckyus-iwms-rw/slowquery`              | 0.78     | NEVER     |
| 28| `/aws/rds/cluster/aws-luckyus-iscm-rw/slowquery`              | 0.76     | NEVER     |
| 29| `/aws/rds/cluster/aws-luckyus-ireport-rw/slowquery`           | 0.73     | NEVER     |
| 30| `/aws/rds/cluster/aws-luckyus-iconfigcenter-rw/slowquery`     | 0.68     | NEVER     |
| 31| `/aws/rds/cluster/aws-luckyus-imenu-rw/slowquery`             | 0.65     | NEVER     |
| 32| `/aws/rds/cluster/aws-luckyus-irecipe-rw/slowquery`           | 0.62     | NEVER     |
| 33| `/aws/rds/cluster/aws-luckyus-iaudit-rw/slowquery`            | 0.58     | NEVER     |
| 34| `/aws/rds/cluster/aws-luckyus-idataplatform-rw/slowquery`     | 0.54     | NEVER     |
| 35| `/aws/rds/cluster/aws-luckyus-icouponcenter-rw/slowquery`     | 0.52     | NEVER     |
| 36| `/aws/rds/cluster/aws-luckyus-icyberdata-ro/slowquery`        | 0.48     | NEVER     |
| 37| `/aws/rds/cluster/aws-luckyus-iorder-ro/slowquery`            | 0.45     | NEVER     |
| 38| `/aws/rds/cluster/aws-luckyus-imember-ro/slowquery`           | 0.42     | NEVER     |
| 39| `/aws/rds/cluster/aws-luckyus-iproduct-ro/slowquery`          | 0.38     | NEVER     |
| 40| `/aws/rds/cluster/aws-luckyus-istore-ro/slowquery`            | 0.36     | NEVER     |
| 41| `/aws/rds/cluster/aws-luckyus-ipayment-ro/slowquery`          | 0.34     | NEVER     |
| 42| `/aws/rds/cluster/aws-luckyus-ipos-ro/slowquery`              | 0.32     | NEVER     |
| 43| `/aws/rds/cluster/aws-luckyus-igateway-ro/slowquery`          | 0.31     | NEVER     |
| 44| `/aws/rds/cluster/aws-luckyus-ianalytics-ro/slowquery`        | 0.29     | NEVER     |
| 45| `/aws/rds/cluster/aws-luckyus-icrm-ro/slowquery`              | 0.27     | NEVER     |
| 46| `/aws/rds/cluster/aws-luckyus-icashier-ro/slowquery`          | 0.25     | NEVER     |
| 47| `/aws/rds/cluster/aws-luckyus-iloyalty-ro/slowquery`           | 0.23    | NEVER     |
| 48| `/aws/rds/cluster/aws-luckyus-ifinance-ro/slowquery`           | 0.21    | NEVER     |
| 49| `/aws/rds/cluster/aws-luckyus-isearch-ro/slowquery`            | 0.19    | NEVER     |
| 50| `/aws/rds/cluster/aws-luckyus-imarketing-ro/slowquery`         | 0.18    | NEVER     |
| 51| `/aws/rds/cluster/aws-luckyus-idelivery-ro/slowquery`          | 0.17    | NEVER     |
| 52| `/aws/rds/cluster/aws-luckyus-iinventory-ro/slowquery`         | 0.16    | NEVER     |
| 53| `/aws/rds/cluster/aws-luckyus-isettlement-ro/slowquery`        | 0.15    | NEVER     |
| 54| `/aws/rds/cluster/aws-luckyus-ipromotion-ro/slowquery`         | 0.14    | NEVER     |
| 55| `/aws/rds/cluster/aws-luckyus-imessage-ro/slowquery`           | 0.13    | NEVER     |
| 56| `/aws/rds/cluster/aws-luckyus-inotification-ro/slowquery`      | 0.12    | NEVER     |
| 57| `/aws/rds/cluster/aws-luckyus-iopenlinker-ro/slowquery`        | 0.11    | NEVER     |
| 58| `/aws/rds/cluster/aws-luckyus-iauth-ro/slowquery`              | 0.10    | NEVER     |

**Total slow query log storage: ~47.8 GB across 58 log groups. ZERO retention policies.**

---

### Appendix C: Grafana Alert Rule Details / 附录 C：Grafana 告警规则详情

| Field / 字段          | Alert 1                   | Alert 2                   | Alert 3                   |
|-----------------------|---------------------------|---------------------------|---------------------------|
| UID                   | `bf7zrw6q74e80a`          | `af7zrwm660su8d`          | `ef7zrx2gdoy68f`          |
| Title                 | Slow Query Alert (Primary)| Slow Query Alert (Secondary)| Slow Query Alert (Tertiary)|
| Health State          | **ERROR**                 | **ERROR**                 | **ERROR**                 |
| Folder                | Alerts                    | Alerts                    | Alerts                    |
| Rule Group            | slow-query-alerts         | slow-query-alerts         | slow-query-alerts         |
| Evaluation Interval   | 1m                        | 1m                        | 1m                        |
| For Duration          | 5m                        | 5m                        | 5m                        |
| No Data State         | NoData                    | NoData                    | NoData                    |
| Exec Error State      | Error                     | Error                     | Error                     |
| Contact Point         | email (default)           | email (default)           | email (default)           |
| Last Evaluation       | Error                     | Error                     | Error                     |
| Error Message         | Query execution failed    | Query execution failed    | Query execution failed    |

**Probable Causes / 可能原因:**
1. Datasource credentials expired or rotated without updating Grafana
2. CloudWatch Logs Insights query syntax incompatible with current log format
3. IAM permissions insufficient for CloudWatch Logs query execution
4. Query timeout due to unbounded log group sizes (no retention = large scans)

**Remediation Steps / 修复步骤:**
1. Verify datasource connectivity in Grafana admin panel
2. Test alert queries manually in Grafana Explore
3. Check IAM role permissions for CloudWatch Logs Insights
4. Reduce query time range or add retention policies to reduce scan size
5. Update query syntax if log format has changed

---

### Appendix D: AWS Service Inventory Summary / 附录 D：AWS 服务清单摘要

| Service / 服务           | Resource Type / 资源类型   | Approx Count / 大致数量 | Monitoring Status / 监控状态  |
|--------------------------|--------------------------|------------------------|-------------------------------|
| EC2                      | Instances                | ~233                   | NONE                          |
| EC2                      | Auto Scaling Groups      | ~15                    | NONE                          |
| EC2                      | Load Balancers (ALB/NLB) | ~20                    | CloudWatch (passive)          |
| RDS                      | Aurora MySQL Clusters    | 62                     | CloudWatch (passive, 0 alarms)|
| RDS                      | Aurora Reader Instances  | ~120                   | CloudWatch (passive, 0 alarms)|
| ElastiCache              | Redis Nodes              | 76                     | Prometheus (98.7%)            |
| EKS                      | Clusters                 | 3-5                    | CloudWatch (basic, ~10%)      |
| EKS                      | Worker Nodes             | ~50                    | CloudWatch (basic, ~10%)      |
| MSK                      | Kafka Clusters           | 2-3                    | CloudWatch (basic, ~10%)      |
| MSK                      | Brokers                  | ~9                     | CloudWatch (basic, ~10%)      |
| DocumentDB               | Clusters                 | 2-3                    | CloudWatch (basic, ~5%)       |
| OpenSearch               | Domains                  | 2-3                    | CloudWatch (basic, ~10%)      |
| EMR                      | Clusters                 | 2-3                    | NONE                          |
| S3                       | Buckets                  | ~50                    | CloudWatch (basic)            |
| Lambda                   | Functions                | ~30                    | CloudWatch (basic)            |
| SQS                      | Queues                   | ~20                    | CloudWatch (basic)            |
| SNS                      | Topics                   | ~10                    | CloudWatch (basic)            |
| CloudFront               | Distributions            | ~5                     | CloudWatch (basic)            |
| Route 53                 | Hosted Zones             | ~5                     | Health Checks only            |
| **Total Resources**      |                          | **~750+**              | **< 15% actively monitored**  |

---

### Appendix E: Monitoring Tool Versions / 附录 E：监控工具版本

| Tool / 工具         | Current Version / 当前版本 | Latest Stable / 最新稳定版 | Gap / 差距              |
|---------------------|--------------------------|---------------------------|------------------------|
| Prometheus          | 2.43.0 (Mar 2023)       | 2.54.x+ (2026)            | ~3 years behind        |
| Grafana             | ~10.x                   | 11.x+ (2026)              | ~1 major version behind |
| Redis Exporter      | Unknown                  | Latest                    | Needs audit            |
| AlertManager        | Not deployed             | 0.27.x+                   | Not available          |

---

## Document History / 文件历史

| Version / 版本 | Date / 日期   | Author / 作者              | Changes / 变更                       |
|----------------|--------------|---------------------------|--------------------------------------|
| 0.1            | 2026-02-10   | Data Engineering / BI Team | Initial draft                        |
| 0.5            | 2026-02-12   | Data Engineering / BI Team | Added appendices, metrics validation |
| 1.0            | 2026-02-15   | Data Engineering / BI Team | Final draft for review               |

---

*This document is part of the UC-IT-01 Infrastructure Monitoring & Anomaly Detection
use case. For questions or updates, contact the Data Engineering / BI Team.*

*本文件属于 UC-IT-01 基础设施监控与异常检测用例的一部分。如有疑问或需要更新，
请联系数据工程 / BI 团队。*

---
**END OF DOCUMENT / 文件结束**

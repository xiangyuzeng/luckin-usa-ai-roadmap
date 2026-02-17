# Luckin Coffee NA -- Alert Runbook Part 9: PIPELINE (Data Pipeline Monitoring)
# 瑞幸咖啡北美 -- 告警运行手册 第9部分: PIPELINE (数据管道监控)

> **Version / 版本:** 1.0
> **Date / 日期:** 2026-02-17
> **Category / 类别:** PIPELINE -- Data Pipeline Monitoring / 数据管道监控
> **Alert Group / 告警组:** `lck-na.alerts.pipeline` (interval: 30s)
> **Alerts in this part / 本部分告警数:** 4 (LCK-PL-001 through LCK-PL-004)
> **Consolidation / 合并:** 14 legacy alerts merged into 4 new alerts (71% reduction)
> **Format / 格式:** 5 A's Pattern (Assess, Acknowledge, Analyze, Act, Aftermath)
> **Skill Reference / 技能参考:** `/app/skills/apm-alert-investigation.md` v1.0
> **Platform:** AWS us-east-1 | EKS: luckyus-prod | DataLink ETL

---

## Table of Contents / 目录

| Alert ID | Name | Severity | Tier | Page |
|----------|------|----------|------|------|
| [LCK-PL-001](#lck-pl-001) | PipelineGoldenPathDelayCritical | critical | 3 | Golden Path Pipeline Delay Critical |
| [LCK-PL-002](#lck-pl-002) | PipelineCoreDelayWarning | warning | 2 | Core Pipeline Delay Warning |
| [LCK-PL-003](#lck-pl-003) | PipelineImportantDelayInfo | info | 1 | Important Pipeline Delay Info |
| [LCK-PL-004](#lck-pl-004) | PipelineStandardDelayOrExceptionInfo | info | 1 | Standard Pipeline Delay / Exception Batch |

---

<a id="lck-pl-001"></a>
## LCK-PL-001: PipelineGoldenPathDelayCritical

### Metadata / 元数据

```yaml
alert_id: "LCK-PL-001"
alert_name: "PipelineGoldenPathDelayCritical"
severity: "critical"
tier: "3"
category: "pipeline"
team: "data-arch"
first_responder: "data-arch on-call"
sla_response: "Tier 3: 5min"
old_alert_ids: "ALR-005, ALR-006, ALR-007, ALR-008"
consolidation: "MERGE — 4 legacy golden-path pipeline alerts merged into one critical delay alert"
skill_reference: "/app/skills/apm-alert-investigation.md"
last_updated: "2026-02-17"
```

### PromQL Expression / 告警表达式

```promql
# Datasource: df8o21agxtkw0d (UMBQuerier-Luckin)
# Evaluation interval: 30s | for: 5m
max(datalink_task_delay_seconds{pipeline_tier="golden", env="production"}) > 300
```

**Meaning / 含义:** The golden path pipeline (order processing flow) has a task delay exceeding 300 seconds (5 minutes), sustained for 5 minutes. The golden path carries real-time order data; delays directly impact revenue reporting, payment reconciliation, and operational dashboards.
黄金路径管道 (订单处理流) 任务延迟超过 300 秒 (5 分钟), 持续 5 分钟。黄金路径承载实时订单数据; 延迟直接影响收入报表、支付对账和运营仪表板。

### 1. ASSESS (First 2 Minutes) / 评估 (前2分钟)

**Goal / 目标:** CRITICAL -- Determine if golden path pipeline delay is causing downstream data staleness. Order data, payment reconciliation, and real-time dashboards depend on this pipeline.
紧急 -- 判断黄金路径管道延迟是否导致下游数据陈旧。订单数据、支付对账和实时仪表板依赖此管道。

#### 1.1 Golden Path Impact Check / 黄金路径影响检查

```bash
# Check current golden path pipeline delay / 检查当前黄金路径管道延迟
curl -s "http://prometheus:9090/api/v1/query?query=max(datalink_task_delay_seconds{pipeline_tier='golden', env='production'})" | \
  jq '.data.result[] | {task: .metric.task_name, delay_sec: .value[1]}'

# Check if order data is flowing to downstream / 检查订单数据是否流向下游
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"

# Check DataLink task status for golden tier / 检查黄金层级 DataLink 任务状态
curl -s "http://prometheus:9090/api/v1/query?query=datalink_task_delay_seconds{pipeline_tier='golden', env='production'}" | \
  jq '.data.result[] | {task: .metric.task_name, source: .metric.source_db, delay: .value[1]}'
```

#### 1.2 Quick Triage / 快速分诊

```bash
# Check for concurrent pipeline alerts (alert storm) / 检查并发管道告警 (告警风暴)
curl -s "http://alertmanager:9093/api/v2/alerts?filter=category%3D%22pipeline%22" | \
  jq '.[].labels | {alertname, severity, pipeline_tier}'

# Check upstream data sources (RDS) / 检查上游数据源 (RDS)
curl -s "http://prometheus:9090/api/v1/query?query=mysql_up{job='rds-exporter'} == 0" | \
  jq '.data.result[] | {instance: .metric.instance}'

# Check Kafka consumer lag for golden path topics / 检查黄金路径 Kafka 消费延迟
curl -s "http://prometheus:9090/api/v1/query?query=kafka_consumer_group_lag{topic=~'.*order.*|.*payment.*'}" | \
  jq '.data.result[] | {topic: .metric.topic, group: .metric.group, lag: .value[1]}'

# Check recent EKS events in DataLink namespace / 检查 DataLink 命名空间近期 EKS 事件
kubectl get events -n datalink --sort-by='.lastTimestamp' | tail -15
```

#### 1.3 Severity Classification / 严重性分类

| Condition / 条件 | Severity / 严重性 | Action / 操作 |
|-----------|----------|--------|
| Golden path delay >300s, downstream dashboards stale / 黄金路径延迟 >300s, 下游仪表板陈旧 | **Critical -- Tier 3** | Immediate escalation to China HQ / 立即升级到中国总部 |
| Golden path delay >300s, but downstream data still recent / 延迟 >300s, 但下游数据仍较新 | **Critical -- Tier 2+** | Data-Arch investigates urgently / Data-Arch 紧急调查 |
| Spike resolving on its own / 峰值自行恢复 | **Monitor closely** | Watch for recurrence / 监控复发 |

### 2. ACKNOWLEDGE (Within 5 min SLA -- Tier 3) / 确认 (5分钟 SLA -- Tier 3)

```bash
# Silence alert during investigation (15 min max for critical) / 调查期间静默告警 (危急最长15分钟)
amtool silence add alertname="PipelineGoldenPathDelayCritical" \
  --duration="15m" --comment="Investigating CRITICAL golden path delay - YOUR_NAME" --author="YOUR_NAME"
```

**WeCom Template (Critical Channel) / 企业微信模板 (紧急频道):**
```
CRITICAL Alert Acknowledged / 紧急告警已确认
Alert: PipelineGoldenPathDelayCritical (LCK-PL-001)
Severity: CRITICAL | Tier: 3
Pipeline: Golden Path (order processing)
Owner: {your_name}
Status: Investigating / 调查中
Impacted tasks: {list from triage}
ETA for update: {time + 10min}
```

**Notification channel / 通知渠道:** wecom-critical (all DevOps US + China HQ)

### 3. ANALYZE (Root Cause) / 分析 (根因)

#### 3.1 Common Causes / 常见原因

```
[ ] Upstream RDS source database slow or unavailable / 上游 RDS 源数据库慢或不可用
[ ] Kafka broker or topic partition issue / Kafka Broker 或主题分区问题
[ ] DataLink worker pod OOM or crash / DataLink Worker Pod OOM 或崩溃
[ ] AWS Glue ETL job failure or long-running job / AWS Glue ETL 作业失败或长时间运行
[ ] S3 data landing zone write failures / S3 数据落地区写入失败
[ ] Network connectivity between EKS and RDS/Kafka / EKS 与 RDS/Kafka 间网络连接问题
[ ] Schema change in upstream source without pipeline update / 上游源表结构变更但管道未更新
```

#### 3.2 Diagnostic Commands / 诊断命令

```bash
# DataLink — Check golden path task status / 检查黄金路径任务状态
# URL: https://datalink.luckinus.com/tasks?tier=golden
# Navigate: Tasks -> Golden Tier -> Running/Failed tasks

# Check DataLink worker pods / 检查 DataLink Worker Pod
kubectl get pods -n datalink -l tier=golden -o wide
kubectl describe pod -n datalink -l tier=golden,status=error | tail -30

# Check DataLink task logs for errors / 检查 DataLink 任务日志
kubectl logs -n datalink -l tier=golden --tail=100 --since=10m | \
  grep -i "exception\|error\|fail\|timeout\|delay" | tail -30

# Check upstream RDS health (order DB) / 检查上游 RDS 健康 (订单库)
curl -s "http://prometheus:9090/api/v1/query?query=mysql_global_status_threads_running{instance=~'.*salesorder.*'}"

# Check Kafka cluster health / 检查 Kafka 集群健康
curl -s "http://prometheus:9090/api/v1/query?query=kafka_brokers" | jq '.data.result'

# Check AWS Glue job status / 检查 AWS Glue 作业状态
aws glue get-job-runs --job-name "golden-path-etl" --max-items 5 --region us-east-1 | \
  jq '.JobRuns[] | {Id: .Id, State: .JobRunState, StartedOn: .StartedOn, ErrorMessage: .ErrorMessage}'

# Check S3 data landing zone / 检查 S3 数据落地区
aws s3 ls s3://luckyus-data-lake/golden/ --recursive --summarize | tail -5
```

#### 3.3 VMAlert Endpoint Verification / VMAlert 端点验证

```bash
# Check Pipeline VMAlert instance (Basic) / 检查管道 VMAlert 实例 (Basic)
curl -s "http://10.238.3.153:8880/api/v1/alerts" | \
  jq '.data.alerts[] | select(.labels.alertname == "PipelineGoldenPathDelayCritical")'
```

### 4. ACT (Remediation) / 处置 (修复)

**CRITICAL: Act fast. Golden path delay >5min means revenue reporting and payment reconciliation are stale.**
**紧急: 快速行动。黄金路径延迟 >5 分钟意味着收入报表和支付对账数据陈旧。**

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---------|--------|------------|
| DataLink worker pod crashed / DataLink Worker Pod 崩溃 | Restart pod, check resource limits / 重启 Pod, 检查资源限制 | Tier 2 |
| Upstream RDS slow/unavailable / 上游 RDS 慢/不可用 | Check RDS health, escalate to DBA / 检查 RDS 健康, 升级到 DBA | Tier 3 |
| Kafka consumer lag / Kafka 消费延迟 | Reset consumer offset, check broker / 重置消费偏移, 检查 Broker | Tier 2 |
| Glue ETL job failure / Glue ETL 作业失败 | Rerun Glue job, check error logs / 重跑 Glue 作业, 检查错误日志 | Tier 2 |
| Unknown with golden path impact / 原因不明且影响黄金路径 | Escalate to China HQ immediately / 立即升级到中国总部 | Tier 3 |

```bash
# Restart failed DataLink golden path pods / 重启失败的 DataLink 黄金路径 Pod
kubectl delete pod -n datalink -l tier=golden,status=error
kubectl rollout restart deployment/datalink-worker-golden -n datalink

# Rerun failed Glue job / 重跑失败的 Glue 作业
aws glue start-job-run --job-name "golden-path-etl" --region us-east-1

# Reset Kafka consumer offset if stuck / 如果 Kafka 消费卡住, 重置偏移
# CAUTION: May cause duplicate processing / 注意: 可能导致重复处理
# kafka-consumer-groups.sh --bootstrap-server MSK_BROKER:9092 --group golden-etl --reset-offsets --to-latest --topic ORDER_TOPIC --execute

# Scale up workers if load-related / 如果是负载相关, 扩容 Worker
kubectl scale deployment/datalink-worker-golden -n datalink --replicas=NEW_COUNT
```

**Escalation path / 升级路径:** Data-Arch -> Team Lead (5min) -> China HQ Engineering (15min no resolution)

### 5. AFTERMATH (Post-Incident) / 事后 (事件后)

- **Mandatory incident report** for all Tier 3/critical incidents / 所有 Tier 3/危急事件必须提交事件报告
- Post-mortem within 24 hours / 24 小时内完成事后分析
- Review 300s golden path threshold -- is it appropriate? / 审查 300s 黄金路径阈值是否合理
- Verify all downstream consumers received backfilled data / 验证所有下游消费者收到补充数据
- Update DataLink task monitoring if new failure mode discovered / 如发现新故障模式, 更新 DataLink 任务监控

**Old Alert Reference / 旧告警参考:** ALR-005 (DataLink-订单同步延迟>3min), ALR-006 (DataLink-支付同步延迟>3min), ALR-007 (DataLink-库存同步延迟>5min), ALR-008 (DataLink-会员同步延迟>5min)

---

<a id="lck-pl-002"></a>
## LCK-PL-002: PipelineCoreDelayWarning

### Metadata / 元数据

```yaml
alert_id: "LCK-PL-002"
alert_name: "PipelineCoreDelayWarning"
severity: "warning"
tier: "2"
category: "pipeline"
team: "data-arch"
first_responder: "data-arch on-call"
sla_response: "Tier 2: 15min"
old_alert_ids: "ALR-009, ALR-010, ALR-011"
consolidation: "MERGE — 3 legacy core pipeline delay alerts merged into one warning-level alert"
skill_reference: "/app/skills/apm-alert-investigation.md"
last_updated: "2026-02-17"
```

### PromQL Expression / 告警表达式

```promql
# Datasource: df8o21agxtkw0d (UMBQuerier-Luckin)
# Evaluation interval: 30s | for: 10m
max(datalink_task_delay_seconds{pipeline_tier="core", env="production"}) > 600
```

**Meaning / 含义:** A core-tier pipeline task delay exceeds 600 seconds (10 minutes), sustained for 10 minutes. Core pipelines feed analytics dashboards, CRM sync, and financial aggregation. Delays degrade reporting accuracy but do not block real-time order flow.
核心层级管道任务延迟超过 600 秒 (10 分钟), 持续 10 分钟。核心管道供给分析仪表板、CRM 同步和财务汇总。延迟会降低报表准确性, 但不会阻塞实时订单流。

### 1. ASSESS (First 2 Minutes) / 评估 (前2分钟)

**Goal / 目标:** Determine which core pipeline is delayed and assess impact on downstream analytics and reporting.
判断哪条核心管道延迟, 评估对下游分析和报表的影响。

#### 1.1 Golden Path Impact Check / 黄金路径影响检查

```bash
# Verify golden path is NOT affected (core delay should not impact golden) / 确认黄金路径未受影响
curl -s "http://prometheus:9090/api/v1/query?query=max(datalink_task_delay_seconds{pipeline_tier='golden', env='production'})"

# Check which core tasks are delayed / 检查哪些核心任务延迟
curl -s "http://prometheus:9090/api/v1/query?query=datalink_task_delay_seconds{pipeline_tier='core', env='production'} > 600" | \
  jq '.data.result[] | {task: .metric.task_name, source: .metric.source_db, delay_sec: .value[1]}'
```

#### 1.2 Quick Triage / 快速分诊

```bash
# Check for concurrent alerts / 检查并发告警
curl -s "http://alertmanager:9093/api/v2/alerts?filter=category%3D%22pipeline%22" | \
  jq '.[].labels | {alertname, severity, pipeline_tier}'

# Check DataLink core worker pods / 检查 DataLink 核心 Worker Pod
kubectl get pods -n datalink -l tier=core -o wide

# Check if delay is increasing or stable / 检查延迟是在增加还是稳定
curl -s "http://prometheus:9090/api/v1/query_range?query=max(datalink_task_delay_seconds{pipeline_tier='core', env='production'})&start=$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)&end=$(date -u +%Y-%m-%dT%H:%M:%SZ)&step=60s" | \
  jq '.data.result[0].values[-5:]'
```

#### 1.3 Severity Classification / 严重性分类

| Condition / 条件 | Severity / 严重性 | Action / 操作 |
|-----------|----------|--------|
| Core delay >10min AND golden path also delayed / 核心延迟 >10min 且黄金路径也延迟 | **Escalate to Tier 3** | Likely systemic issue / 可能是系统性问题 |
| Core delay >10min, golden path normal / 核心延迟 >10min, 黄金路径正常 | **Warning -- Tier 2** | Data-Arch investigates / Data-Arch 调查 |
| Delay near threshold, trending down / 接近阈值, 趋势下降 | **Monitor -- Tier 1** | Watch for 15 min / 观察 15 分钟 |

### 2. ACKNOWLEDGE (Within 15 min SLA) / 确认 (15分钟 SLA)

```bash
# Silence alert during investigation (30 min) / 调查期间静默告警 (30分钟)
amtool silence add alertname="PipelineCoreDelayWarning" \
  --duration="30m" --comment="Investigating core pipeline delay - YOUR_NAME" --author="YOUR_NAME"
```

**WeCom Template / 企业微信模板:**
```
Alert Acknowledged / 告警已确认
Alert: PipelineCoreDelayWarning (LCK-PL-002)
Severity: warning | Tier: 2
Pipeline: Core (analytics/CRM/finance)
Owner: {your_name}
Status: Investigating / 调查中
ETA for update: {time + 15min}
```

### 3. ANALYZE (Root Cause) / 分析 (根因)

#### 3.1 Common Causes / 常见原因

```
[ ] Large batch backlog in upstream source tables / 上游源表大批量积压
[ ] Glue ETL job timeout or resource contention / Glue ETL 作业超时或资源争用
[ ] DataLink worker memory pressure / DataLink Worker 内存压力
[ ] Source database slow query locking tables / 源数据库慢查询锁表
[ ] S3 write throttling / S3 写入限流
[ ] Schema drift in source tables / 源表 Schema 漂移
```

#### 3.2 Diagnostic Commands / 诊断命令

```bash
# Check DataLink core task details / 检查 DataLink 核心任务详情
kubectl logs -n datalink -l tier=core --tail=100 --since=15m | \
  grep -i "exception\|error\|fail\|timeout\|delay" | tail -30

# Check DataLink worker pod resource usage / 检查 DataLink Worker Pod 资源使用
kubectl top pods -n datalink -l tier=core

# Check upstream RDS source for locks / 检查上游 RDS 源是否有锁
# Use mcp-db-gateway for the relevant source database
# SQL: SHOW PROCESSLIST; -- check for long-running queries

# Check Glue job runs for core pipelines / 检查核心管道 Glue 作业运行
aws glue get-job-runs --job-name "core-analytics-etl" --max-items 5 --region us-east-1 | \
  jq '.JobRuns[] | {Id: .Id, State: .JobRunState, StartedOn: .StartedOn, ErrorMessage: .ErrorMessage}'

# Check S3 write activity / 检查 S3 写入活动
aws s3 ls s3://luckyus-data-lake/core/ --recursive --summarize | tail -5

# VMAlert check / VMAlert 检查
curl -s "http://10.238.3.153:8880/api/v1/alerts" | \
  jq '.data.alerts[] | select(.labels.alertname == "PipelineCoreDelayWarning")'
```

#### 3.3 VMAlert Endpoint Verification / VMAlert 端点验证

```bash
# Check Pipeline VMAlert instance (Basic) / 检查管道 VMAlert 实例 (Basic)
curl -s "http://10.238.3.153:8880/api/v1/alerts" | \
  jq '.data.alerts[] | select(.labels.alertname == "PipelineCoreDelayWarning")'
```

### 4. ACT (Remediation) / 处置 (修复)

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---------|--------|------------|
| Glue job timeout / Glue 作业超时 | Rerun with increased timeout/DPU / 增加超时/DPU 后重跑 | Tier 2 |
| DataLink worker OOM / DataLink Worker OOM | Restart pod, increase memory limit / 重启 Pod, 增加内存限制 | Tier 2 |
| Source DB lock contention / 源数据库锁争用 | Kill blocking query, escalate to DBA / 终止阻塞查询, 升级到 DBA | Tier 2 |
| Systemic issue affecting multiple tiers / 系统性问题影响多层级 | Escalate to Tier 3 / 升级到 Tier 3 | Tier 2 -> 3 |

```bash
# Restart DataLink core workers / 重启 DataLink 核心 Worker
kubectl rollout restart deployment/datalink-worker-core -n datalink

# Rerun failed Glue job with more resources / 增加资源后重跑失败的 Glue 作业
aws glue start-job-run --job-name "core-analytics-etl" \
  --allocated-capacity 10 --region us-east-1

# Scale up if backlog-related / 如果是积压相关, 扩容
kubectl scale deployment/datalink-worker-core -n datalink --replicas=NEW_COUNT
```

### 5. AFTERMATH (Post-Incident) / 事后 (事件后)

- Update this runbook with new root cause if discovered / 如发现新根因, 更新本手册
- Review if 600s (10min) core threshold is appropriate / 审查 600s (10分钟) 核心阈值是否合理
- Check downstream analytics accuracy after delay resolution / 延迟解决后检查下游分析准确性
- File incident report for Tier 2+ incidents / Tier 2+ 事件需提交事件报告

**Old Alert Reference / 旧告警参考:** ALR-009 (DataLink-CRM同步延迟>10min), ALR-010 (DataLink-财务汇总延迟>10min), ALR-011 (DataLink-分析管道延迟>10min)

---

<a id="lck-pl-003"></a>
## LCK-PL-003: PipelineImportantDelayInfo

### Metadata / 元数据

```yaml
alert_id: "LCK-PL-003"
alert_name: "PipelineImportantDelayInfo"
severity: "info"
tier: "1"
category: "pipeline"
team: "data-arch"
first_responder: "data-arch on-call"
sla_response: "Tier 1: 30min"
old_alert_ids: "ALR-012, ALR-013, ALR-014"
consolidation: "MERGE — 3 legacy important-tier pipeline delay alerts merged into one info-level alert"
skill_reference: "/app/skills/apm-alert-investigation.md"
last_updated: "2026-02-17"
```

### PromQL Expression / 告警表达式

```promql
# Datasource: df8o21agxtkw0d (UMBQuerier-Luckin)
# Evaluation interval: 30s | for: 15m
max(datalink_task_delay_seconds{pipeline_tier="important", env="production"}) > 900
```

**Meaning / 含义:** An important-tier pipeline task delay exceeds 900 seconds (15 minutes), sustained for 15 minutes. Important pipelines include supply chain data sync, inventory reporting, and HR data feeds. Delays are tolerable short-term but may impact daily operational reports.
重要层级管道任务延迟超过 900 秒 (15 分钟), 持续 15 分钟。重要管道包括供应链数据同步、库存报表和人力资源数据馈送。短期延迟可容忍, 但可能影响每日运营报表。

### 1. ASSESS (First 2 Minutes) / 评估 (前2分钟)

**Goal / 目标:** Identify which important pipeline is delayed and determine if it will impact daily operational reports.
识别哪条重要管道延迟, 判断是否会影响每日运营报表。

#### 1.1 Golden Path Impact Check / 黄金路径影响检查

```bash
# Verify golden path and core are unaffected / 确认黄金路径和核心层未受影响
curl -s "http://prometheus:9090/api/v1/query?query=max(datalink_task_delay_seconds{pipeline_tier=~'golden|core', env='production'})"

# Check which important tasks are delayed / 检查哪些重要任务延迟
curl -s "http://prometheus:9090/api/v1/query?query=datalink_task_delay_seconds{pipeline_tier='important', env='production'} > 900" | \
  jq '.data.result[] | {task: .metric.task_name, source: .metric.source_db, delay_sec: .value[1]}'
```

#### 1.2 Quick Triage / 快速分诊

```bash
# Check DataLink important worker pods / 检查 DataLink 重要层 Worker Pod
kubectl get pods -n datalink -l tier=important -o wide

# Check for related pipeline alerts / 检查相关管道告警
curl -s "http://alertmanager:9093/api/v2/alerts?filter=category%3D%22pipeline%22" | \
  jq '.[].labels | {alertname, severity, pipeline_tier}'
```

#### 1.3 Severity Classification / 严重性分类

| Condition / 条件 | Severity / 严重性 | Action / 操作 |
|-----------|----------|--------|
| Important delay AND higher tiers also delayed / 重要层延迟且高层也延迟 | **Escalate to Tier 2** | Systemic investigation / 系统性调查 |
| Important delay only, no downstream urgency / 仅重要层延迟, 无下游紧急需求 | **Info -- Tier 1** | Monitor and fix during business hours / 监控并在工作时间修复 |
| Near threshold, trending down / 接近阈值, 趋势下降 | **Monitor** | Auto-resolve expected / 预计自动恢复 |

### 2. ACKNOWLEDGE (Within 30 min SLA) / 确认 (30分钟 SLA)

```bash
# Silence alert during investigation (60 min) / 调查期间静默告警 (60分钟)
amtool silence add alertname="PipelineImportantDelayInfo" \
  --duration="60m" --comment="Investigating important pipeline delay - YOUR_NAME" --author="YOUR_NAME"
```

**WeCom Template / 企业微信模板:**
```
Alert Acknowledged / 告警已确认
Alert: PipelineImportantDelayInfo (LCK-PL-003)
Severity: info | Tier: 1
Pipeline: Important (SCM/inventory/HR)
Owner: {your_name}
Status: Monitoring / 监控中
ETA for update: {time + 30min}
```

### 3. ANALYZE (Root Cause) / 分析 (根因)

#### 3.1 Common Causes / 常见原因

```
[ ] Scheduled batch job running longer than expected / 定时批处理作业运行时间超预期
[ ] Source table data volume spike (month-end, promotion) / 源表数据量激增 (月末, 促销)
[ ] Glue job resource contention with higher-tier jobs / Glue 作业与高层作业资源争用
[ ] DataLink task configuration drift / DataLink 任务配置漂移
[ ] S3 partition issue / S3 分区问题
```

#### 3.2 Diagnostic Commands / 诊断命令

```bash
# Check DataLink important task logs / 检查 DataLink 重要任务日志
kubectl logs -n datalink -l tier=important --tail=100 --since=20m | \
  grep -i "exception\|error\|fail\|timeout" | tail -20

# Check pod resource usage / 检查 Pod 资源使用
kubectl top pods -n datalink -l tier=important

# Check Glue job status for important pipelines / 检查重要管道 Glue 作业状态
aws glue get-job-runs --job-name "important-scm-etl" --max-items 5 --region us-east-1 | \
  jq '.JobRuns[] | {Id: .Id, State: .JobRunState, StartedOn: .StartedOn, ErrorMessage: .ErrorMessage}'

# VMAlert check / VMAlert 检查
curl -s "http://10.238.3.153:8880/api/v1/alerts" | \
  jq '.data.alerts[] | select(.labels.alertname == "PipelineImportantDelayInfo")'
```

#### 3.3 VMAlert Endpoint Verification / VMAlert 端点验证

```bash
# Check Pipeline VMAlert instance (Basic) / 检查管道 VMAlert 实例 (Basic)
curl -s "http://10.238.3.153:8880/api/v1/alerts" | \
  jq '.data.alerts[] | select(.labels.alertname == "PipelineImportantDelayInfo")'
```

### 4. ACT (Remediation) / 处置 (修复)

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---------|--------|------------|
| Batch job overrun / 批处理作业超时 | Increase timeout, rerun / 增加超时, 重跑 | Tier 1 |
| Resource contention / 资源争用 | Schedule off-peak, scale workers / 调度到低峰期, 扩容 Worker | Tier 1 |
| Configuration drift / 配置漂移 | Fix task config, restart / 修复任务配置, 重启 | Tier 1 |
| Systemic issue / 系统性问题 | Escalate to Tier 2 / 升级到 Tier 2 | Tier 1 -> 2 |

```bash
# Restart DataLink important workers / 重启 DataLink 重要层 Worker
kubectl rollout restart deployment/datalink-worker-important -n datalink

# Rerun Glue job / 重跑 Glue 作业
aws glue start-job-run --job-name "important-scm-etl" --region us-east-1
```

### 5. AFTERMATH (Post-Incident) / 事后 (事件后)

- Review 900s important threshold -- is it appropriate? / 审查 900s 重要阈值是否合理
- Check if batch scheduling needs optimization / 检查批处理调度是否需要优化
- Verify daily operational reports received complete data / 验证每日运营报表收到完整数据

**Old Alert Reference / 旧告警参考:** ALR-012 (DataLink-SCM同步延迟>15min), ALR-013 (DataLink-库存报表延迟>15min), ALR-014 (DataLink-HR数据馈送延迟>15min)

---

<a id="lck-pl-004"></a>
## LCK-PL-004: PipelineStandardDelayOrExceptionInfo

### Metadata / 元数据

```yaml
alert_id: "LCK-PL-004"
alert_name: "PipelineStandardDelayOrExceptionInfo"
severity: "info"
tier: "1"
category: "pipeline"
team: "data-arch"
first_responder: "data-arch on-call"
sla_response: "Tier 1: 30min"
old_alert_ids: "ALR-015, ALR-016, ALR-017, ALR-018"
consolidation: "MERGE — 4 legacy standard-tier pipeline alerts merged into one info-level alert (delay + exception batch)"
skill_reference: "/app/skills/apm-alert-investigation.md"
last_updated: "2026-02-17"
```

### PromQL Expression / 告警表达式

```promql
# Datasource: df8o21agxtkw0d (UMBQuerier-Luckin)
# Evaluation interval: 30s | for: 30m
max(datalink_task_delay_seconds{pipeline_tier="standard", env="production"}) > 1800
or
increase(datalink_task_exception_total{pipeline_tier=~"golden|core|important|standard", env="production"}[30m]) > 10
```

**Meaning / 含义:** Either (a) a standard-tier pipeline task delay exceeds 1800 seconds (30 minutes), sustained for 30 minutes, or (b) any pipeline tier has accumulated more than 10 task exceptions in 30 minutes. Standard pipelines carry low-priority data (log archives, analytics backfill, test data). The exception clause catches cross-tier exception bursts at info level.
(a) 标准层级管道任务延迟超过 1800 秒 (30 分钟), 持续 30 分钟, 或 (b) 任意层级管道在 30 分钟内累计超过 10 次任务异常。标准管道承载低优先级数据 (日志归档、分析回填、测试数据)。异常子句在 info 级别捕获跨层异常爆发。

### 1. ASSESS (First 2 Minutes) / 评估 (前2分钟)

**Goal / 目标:** Determine if this is a standard-tier delay (low priority) or a cross-tier exception burst (may indicate systemic issue).
判断这是标准层延迟 (低优先级) 还是跨层异常爆发 (可能表明系统性问题)。

#### 1.1 Golden Path Impact Check / 黄金路径影响检查

```bash
# Verify golden path and core are unaffected / 确认黄金路径和核心层未受影响
curl -s "http://prometheus:9090/api/v1/query?query=max(datalink_task_delay_seconds{pipeline_tier=~'golden|core', env='production'})"

# Check which clause triggered: delay or exception / 检查触发子句: 延迟还是异常
curl -s "http://prometheus:9090/api/v1/query?query=max(datalink_task_delay_seconds{pipeline_tier='standard', env='production'}) > 1800" | \
  jq '.data.result[] | {task: .metric.task_name, delay_sec: .value[1]}'

curl -s "http://prometheus:9090/api/v1/query?query=increase(datalink_task_exception_total{env='production'}[30m]) > 10" | \
  jq '.data.result[] | {task: .metric.task_name, tier: .metric.pipeline_tier, exceptions: .value[1]}'
```

#### 1.2 Quick Triage / 快速分诊

```bash
# If exception clause triggered, check which tiers are affected / 如果异常子句触发, 检查哪些层受影响
curl -s "http://prometheus:9090/api/v1/query?query=increase(datalink_task_exception_total{env='production'}[30m])" | \
  jq '.data.result[] | {task: .metric.task_name, tier: .metric.pipeline_tier, exceptions: .value[1]}' | sort

# Check DataLink standard worker pods / 检查 DataLink 标准层 Worker Pod
kubectl get pods -n datalink -l tier=standard -o wide

# Check for concurrent alerts / 检查并发告警
curl -s "http://alertmanager:9093/api/v2/alerts?filter=category%3D%22pipeline%22" | \
  jq '.[].labels | {alertname, severity, pipeline_tier}'
```

#### 1.3 Severity Classification / 严重性分类

| Condition / 条件 | Severity / 严重性 | Action / 操作 |
|-----------|----------|--------|
| Exception burst across golden/core tiers / 黄金/核心层异常爆发 | **Escalate to Tier 2** | Systemic exception issue / 系统性异常问题 |
| Standard delay only, no upstream impact / 仅标准层延迟, 无上游影响 | **Info -- Tier 1** | Fix during business hours / 工作时间修复 |
| Near threshold, auto-recovering / 接近阈值, 自动恢复中 | **Monitor** | No action needed / 无需操作 |

### 2. ACKNOWLEDGE (Within 30 min SLA) / 确认 (30分钟 SLA)

```bash
# Silence alert during investigation (60 min) / 调查期间静默告警 (60分钟)
amtool silence add alertname="PipelineStandardDelayOrExceptionInfo" \
  --duration="60m" --comment="Investigating standard pipeline - YOUR_NAME" --author="YOUR_NAME"
```

**WeCom Template / 企业微信模板:**
```
Alert Acknowledged / 告警已确认
Alert: PipelineStandardDelayOrExceptionInfo (LCK-PL-004)
Severity: info | Tier: 1
Pipeline: Standard / Exception Batch
Owner: {your_name}
Status: Monitoring / 监控中
Trigger: {delay | exception_burst}
ETA for update: {time + 30min}
```

### 3. ANALYZE (Root Cause) / 分析 (根因)

#### 3.1 Common Causes / 常见原因

```
[ ] Standard pipeline deprioritized by scheduler / 标准管道被调度器降低优先级
[ ] Batch archive job accumulating backlog / 批量归档作业积压
[ ] Exception burst from bad data format in source / 源数据格式错误导致异常爆发
[ ] Glue job failure in standard tier / 标准层 Glue 作业失败
[ ] Resource starvation (higher-tier jobs consuming all workers) / 资源饥饿 (高层作业消耗所有 Worker)
[ ] Cross-tier exception: shared dependency failure / 跨层异常: 共享依赖故障
```

#### 3.2 Diagnostic Commands / 诊断命令

```bash
# Check DataLink standard and exception logs / 检查 DataLink 标准层和异常日志
kubectl logs -n datalink -l tier=standard --tail=100 --since=35m | \
  grep -i "exception\|error\|fail" | tail -20

# If exception burst, check ALL tiers / 如果异常爆发, 检查所有层级
kubectl logs -n datalink --tail=200 --since=35m | \
  grep -i "exception" | awk '{print $NF}' | sort | uniq -c | sort -rn | head -20

# Check Glue job status for standard pipelines / 检查标准管道 Glue 作业状态
aws glue get-job-runs --job-name "standard-archive-etl" --max-items 5 --region us-east-1 | \
  jq '.JobRuns[] | {Id: .Id, State: .JobRunState, StartedOn: .StartedOn, ErrorMessage: .ErrorMessage}'

# Check resource allocation across tiers / 检查跨层资源分配
kubectl top pods -n datalink --sort-by=cpu | head -20

# VMAlert check / VMAlert 检查
curl -s "http://10.238.3.153:8880/api/v1/alerts" | \
  jq '.data.alerts[] | select(.labels.alertname == "PipelineStandardDelayOrExceptionInfo")'
```

#### 3.3 VMAlert Endpoint Verification / VMAlert 端点验证

```bash
# Check Pipeline VMAlert instance (Basic) / 检查管道 VMAlert 实例 (Basic)
curl -s "http://10.238.3.153:8880/api/v1/alerts" | \
  jq '.data.alerts[] | select(.labels.alertname == "PipelineStandardDelayOrExceptionInfo")'
```

### 4. ACT (Remediation) / 处置 (修复)

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---------|--------|------------|
| Standard delay, low priority / 标准层延迟, 低优先级 | Monitor, fix during business hours / 监控, 工作时间修复 | Tier 1 |
| Exception burst from bad data / 坏数据导致异常爆发 | Fix data validation, rerun / 修复数据校验, 重跑 | Tier 1 |
| Cross-tier exception burst / 跨层异常爆发 | Investigate shared dependency, escalate / 调查共享依赖, 升级 | Tier 1 -> 2 |
| Resource starvation / 资源饥饿 | Scale workers, adjust priority / 扩容 Worker, 调整优先级 | Tier 1 |

```bash
# Restart DataLink standard workers / 重启 DataLink 标准层 Worker
kubectl rollout restart deployment/datalink-worker-standard -n datalink

# Rerun failed Glue job / 重跑失败的 Glue 作业
aws glue start-job-run --job-name "standard-archive-etl" --region us-east-1

# Scale up if resource-starved / 如果资源饥饿, 扩容
kubectl scale deployment/datalink-worker-standard -n datalink --replicas=NEW_COUNT
```

### 5. AFTERMATH (Post-Incident) / 事后 (事件后)

- Review 1800s standard threshold -- is it too strict or lenient? / 审查 1800s 标准阈值是否合理
- Review 10-exception threshold for cross-tier batch alert / 审查跨层批量告警 10 次异常阈值
- Check data quality in standard pipeline outputs / 检查标准管道输出数据质量
- Update data validation rules if bad data was root cause / 如坏数据为根因, 更新数据校验规则

**Old Alert Reference / 旧告警参考:** ALR-015 (DataLink-日志归档延迟>30min), ALR-016 (DataLink-分析回填延迟>30min), ALR-017 (DataLink-标准同步异常>5), ALR-018 (DataLink-批处理异常>10)

---

## Appendix A: Pipeline Alert Summary / 附录 A: 管道告警总览

### Alert Overview Table / 告警总览表

| Alert ID | Alert Name | Severity | Tier | Threshold | for | Old IDs | Action |
|----------|-----------|----------|------|-----------|-----|---------|--------|
| LCK-PL-001 | PipelineGoldenPathDelayCritical | critical | 3 | >300s (5min) | 5m | ALR-005~008 | MERGE |
| LCK-PL-002 | PipelineCoreDelayWarning | warning | 2 | >600s (10min) | 10m | ALR-009~011 | MERGE |
| LCK-PL-003 | PipelineImportantDelayInfo | info | 1 | >900s (15min) | 15m | ALR-012~014 | MERGE |
| LCK-PL-004 | PipelineStandardDelayOrExceptionInfo | info | 1 | >1800s (30min) OR >10 exceptions/30m | 30m | ALR-015~018 | MERGE |

### Consolidation Summary / 合并摘要

- **Before / 合并前:** 14 legacy DataLink pipeline alerts (ALR-005 through ALR-018)
- **After / 合并后:** 4 new alerts (LCK-PL-001 through LCK-PL-004)
- **Reduction / 缩减:** 71% (10 alerts eliminated, consolidated into four-tier model)
- **Key improvement / 关键改进:** Four-tier pipeline model (golden/core/important/standard) with progressively relaxed thresholds replaces flat per-task alerts. Cross-tier exception batch alert catches systemic issues.

### Complete Old-to-New Alert Mapping / 新旧告警完整映射

| Old ID | Old Name (Chinese) | Action | New ID | New Alert Name |
|--------|-------------------|--------|--------|---------------|
| ALR-005 | DataLink-订单同步延迟>3min | MERGE | LCK-PL-001 | PipelineGoldenPathDelayCritical |
| ALR-006 | DataLink-支付同步延迟>3min | MERGE | LCK-PL-001 | PipelineGoldenPathDelayCritical |
| ALR-007 | DataLink-库存同步延迟>5min | MERGE | LCK-PL-001 | PipelineGoldenPathDelayCritical |
| ALR-008 | DataLink-会员同步延迟>5min | MERGE | LCK-PL-001 | PipelineGoldenPathDelayCritical |
| ALR-009 | DataLink-CRM同步延迟>10min | MERGE | LCK-PL-002 | PipelineCoreDelayWarning |
| ALR-010 | DataLink-财务汇总延迟>10min | MERGE | LCK-PL-002 | PipelineCoreDelayWarning |
| ALR-011 | DataLink-分析管道延迟>10min | MERGE | LCK-PL-002 | PipelineCoreDelayWarning |
| ALR-012 | DataLink-SCM同步延迟>15min | MERGE | LCK-PL-003 | PipelineImportantDelayInfo |
| ALR-013 | DataLink-库存报表延迟>15min | MERGE | LCK-PL-003 | PipelineImportantDelayInfo |
| ALR-014 | DataLink-HR数据馈送延迟>15min | MERGE | LCK-PL-003 | PipelineImportantDelayInfo |
| ALR-015 | DataLink-日志归档延迟>30min | MERGE | LCK-PL-004 | PipelineStandardDelayOrExceptionInfo |
| ALR-016 | DataLink-分析回填延迟>30min | MERGE | LCK-PL-004 | PipelineStandardDelayOrExceptionInfo |
| ALR-017 | DataLink-标准同步异常>5 | MERGE | LCK-PL-004 | PipelineStandardDelayOrExceptionInfo |
| ALR-018 | DataLink-批处理异常>10 | MERGE | LCK-PL-004 | PipelineStandardDelayOrExceptionInfo |

---

## Appendix B: Environment Reference / 附录 B: 环境参考

### VMAlert Pipeline Endpoints / VMAlert 管道端点

| Instance | IP:Port | Role / 角色 |
|----------|---------|------|
| Basic | 10.238.3.153:8880 | Pipeline alert evaluation / 管道告警评估 |

### Verified Datasource UIDs / 已验证数据源 UID

| Datasource | UID | Purpose / 用途 |
|------------|-----|---------|
| UMBQuerier-Luckin | `df8o21agxtkw0d` | Primary Prometheus (pipeline, node, business metrics) |
| prometheus | `ff7hkeec6c9a8e` | General metrics / 通用指标 |
| prometheus_redis | `ff6p0gjt24phce` | Redis/ElastiCache metrics |

### Key AWS Resources / 关键 AWS 资源

| Resource / 资源 | Identifier / 标识 | Notes / 备注 |
|----------|-----------|-------|
| AWS Account | 257394478466 | Production / 生产 |
| Region | us-east-1 | Primary / 主要 |
| EKS Cluster | luckyus-prod | Main K8s cluster / 主 K8s 集群 |
| MSK Cluster | luckyus-msk-prod | Kafka for pipeline streaming / 管道流数据 Kafka |
| S3 Data Lake | luckyus-data-lake | Pipeline data landing zone / 管道数据落地区 |
| DevOps DB | aws-luckyus-devops-rw | Service registry, alert logs / 服务注册, 告警日志 |

### WeCom Notification Channels / 企业微信通知渠道

| Channel / 渠道 | Tier | Recipients / 接收人 |
|---------|------|------------|
| wecom-info | Tier 1 | US DevOps (text only) |
| wecom-warning | Tier 2 | US DevOps + Team Lead (text + phone lead) |
| wecom-critical | Tier 3 | All DevOps US + China HQ (text + phone all) |

### Escalation Path / 升级路径

```
Tier 1 (Info) -> 15min no resolution -> Tier 2 (Warning)
Tier 2 (Warning) -> 30min no resolution -> Tier 3 (Critical)
Tier 3 (Critical) -> China HQ Engineering
```

### DataLink & Glue URLs / DataLink 和 Glue 链接

```
# DataLink Dashboard / DataLink 仪表板:
https://datalink.luckinus.com/

# DataLink Task URL pattern / DataLink 任务 URL 模式:
https://datalink.luckinus.com/tasks?tier={golden|core|important|standard}

# AWS Glue Console / AWS Glue 控制台:
https://us-east-1.console.aws.amazon.com/glue/home?region=us-east-1#/v2/etl-configuration/jobs

# Grafana Pipeline dashboards / Grafana 管道仪表板:
https://grafana.luckinus.com/d/pipeline-overview   — Pipeline overview / 管道总览
https://grafana.luckinus.com/d/pipeline-delays     — Delay analysis / 延迟分析
https://grafana.luckinus.com/d/pipeline-exceptions  — Exception tracking / 异常追踪
https://grafana.luckinus.com/d/pipeline-glue        — Glue job monitoring / Glue 作业监控
```

---

*End of Part 9: PIPELINE (Data Pipeline Monitoring) -- 4 alerts*
*第9部分结束: PIPELINE (数据管道监控) -- 4 条告警*
*Generated: 2026-02-17 | Format: 5 A's Pattern (Bilingual EN/CN)*

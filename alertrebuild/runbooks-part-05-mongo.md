# Part 5: DB-MONGO — MongoDB/DocumentDB Runbooks

> **Part:** 5 of 10 | **Version:** 1.0 | **Date:** 2026-02-16 | **Status:** Complete
>
> Bilingual runbooks (English + 中文) for all 5 MongoDB/DocumentDB alerts.
> Format: Merged 5A Response Pattern + 12-Section SOP structure.

---

## Table of Contents / 目录

| # | Alert ID | Alert Name | Severity | Tier | Page |
|---|----------|-----------|----------|------|------|
| 1 | LCK-MG-001 | MongoCpuHigh_Warning | warning | 2 | [Link](#lck-mg-001--mongocpuhigh_warning) |
| 2 | LCK-MG-002 | MongoCpuHigh_Critical | critical | 3 | [Link](#lck-mg-002--mongocpuhigh_critical) |
| 3 | LCK-MG-003 | MongoMemoryLow_Warning | warning | 2 | [Link](#lck-mg-003--mongomemorylow_warning) |
| 4 | LCK-MG-004 | MongoMemoryLow_Critical | critical | 3 | [Link](#lck-mg-004--mongomemorylow_critical) |
| 5 | LCK-MG-005 | MongoConnectionHigh_Warning | warning | 2 | [Link](#lck-mg-005--mongoconnectionhigh_warning) |

---

## Category Overview / 分类概述

**MongoDB/DocumentDB** alerts monitor the 4 DocumentDB (MongoDB-compatible) instances in AWS `us-east-1`.
DocumentDB uses an Aurora-based storage engine with MongoDB API compatibility.

**MongoDB/DocumentDB** 告警监控 AWS `us-east-1` 中的 4 个 DocumentDB（兼容 MongoDB）实例。
DocumentDB 使用基于 Aurora 的存储引擎，兼容 MongoDB API。

| Feature / 特性 | AWS DocumentDB | Self-managed MongoDB |
|----------------|---------------|---------------------|
| Storage engine / 存储引擎 | Aurora-based (auto-grows) | WiredTiger |
| Max connections / 最大连接数 | ~100 per GiB RAM | Configurable |
| Backup / 备份 | Automatic continuous | Manual/oplog |
| Scaling / 扩展 | Instance class change | Shard/replica set |
| Monitoring / 监控 | CloudWatch + Prometheus exporter | mongostat/mongotop |

### Prometheus Datasource / Prometheus 数据源

| Datasource | UID | Used For / 用途 |
|------------|-----|----------|
| UMBQuerier-Luckin | `df8o21agxtkw0d` | MongoDB CPU, memory, connection metrics |
| prometheus | `ff7hkeec6c9a8e` | General infrastructure metrics / 通用基础设施指标 |

### Key Endpoints / 关键端点

| Resource / 资源 | Value / 值 |
|----------|-------|
| AWS Account | 257394478466 |
| Region | us-east-1 |
| VMAlert (Basic) | 10.238.3.153:8880 |
| DocumentDB Cluster Endpoint | `*.docdb.amazonaws.com:27017` |
| TLS CA Bundle | `global-bundle.pem` (download from AWS) |

---

## LCK-MG-001 — MongoCpuHigh_Warning

### Metadata / 元数据

```yaml
alert_id: "LCK-MG-001"
alert_name: "MongoCpuHigh_Warning"
severity: "warning"
tier: "2"
category: "db-mongo"
team: "dba"
first_responder: "US DBA"
old_ids_replaced: "ALR-030"
migration_action: "KEEP"
sla_response: "Tier 2: 15min acknowledge, 1h first update, 4h resolution"
skill_reference: "/app/skills/apm-alert-investigation.md"
last_updated: "2026-02-16"
```

### Alert Rule (from alert-rules-complete.yml) / 告警规则

```yaml
- alert: MongoCpuUsageWarning
  expr: |
    avg_over_time(mongodb_cpu_utilization{env="production"}[3m]) > 70
    and
    avg_over_time(mongodb_cpu_utilization{env="production"}[3m]) <= 90
  for: 5m
  labels:
    severity: "warning"
    tier: "2"
    team: "dba"
    category: "db-mongo"
    service: "documentdb-mongo"
  annotations:
    summary: "[LCK-NA-DB-MONGO] CpuUsage_Warning - {{ $labels.instance }}"
    impact: "MongoDB CPU elevated; query performance may degrade."
    notification_channel: "wecom+twilio-lead"
```

### 1. ASSESS (评估) — First 2 Minutes / 前2分钟

**Goal / 目标:** Determine if MongoDB CPU impacts golden path and triage severity.
确定 MongoDB CPU 是否影响黄金流程并评估严重程度。

#### 1.1 Golden Path Impact Check / 黄金流程影响检查

```bash
# Check if completed orders are flowing / 检查订单是否正常流转
# Datasource: df8o21agxtkw0d (UMBQuerier-Luckin)
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"
# If == 0 for 10min → Golden path DOWN → escalate to Tier 3
# 如果10分钟内 == 0 → 黄金流程中断 → 升级到 Tier 3
```

#### 1.2 Quick Triage / 快速分类

```bash
# Current CPU value / 当前 CPU 值
curl -s "http://prometheus:9090/api/v1/query?query=avg_over_time(mongodb_cpu_utilization{env='production'}[3m])" | jq '.data.result[] | {instance: .metric.instance, cpu: .value[1]}'

# Check if other Mongo alerts are firing / 检查是否有其他 Mongo 告警触发
curl -s "http://alertmanager:9093/api/v2/alerts?filter=category%3D%22db-mongo%22" | jq '.[].labels | {alertname, severity, instance}'
```

#### 1.3 Severity Classification / 严重程度分类

| Condition / 条件 | Severity / 严重程度 | Action / 操作 |
|-----------|----------|--------|
| Golden path impacted (orders stopped) / 黄金流程受影响 | **Critical -> Tier 3** | Wake China HQ / 通知中国总部 |
| CPU 70-90%, queries slow but orders flowing / CPU 70-90%，查询变慢但订单正常 | **Warning -> Tier 2** | US DBA investigates / US DBA 调查 |
| CPU spike already resolving / CPU 峰值已在恢复 | **Info -> Tier 1** | Monitor trend / 监控趋势 |

---

### 2. ACKNOWLEDGE (确认) — Within 15 Minutes / 15分钟内

#### 2.1 Silence Alert / 静默告警

```bash
amtool silence add \
  alertname="MongoCpuUsageWarning" \
  category="db-mongo" \
  --duration="30m" \
  --comment="Investigating CPU warning - YOUR_NAME" \
  --author="YOUR_NAME"
```

#### 2.2 WeCom Notification / 企业微信通知

```
🔔 Alert Acknowledged / 告警已确认
Alert: MongoCpuHigh_Warning (LCK-MG-001)
Severity: Warning | Tier: 2
Owner: {your_name}
Status: Investigating / 调查中
Instance: {instance}
CPU: {value}%
ETA for update: {time + 15min}
```

#### 2.3 SLA Timers / SLA 时间要求

| Milestone / 里程碑 | Deadline / 截止时间 |
|-----------|----------|
| Acknowledge / 确认 | 15 min |
| First Update / 首次更新 | 1 hour |
| Resolution / 解决 | 4 hours |

---

### 3. ANALYZE (分析) — Root Cause Investigation / 根因调查

#### 3.1 Common Causes Checklist / 常见原因清单

```
[ ] Slow or unindexed queries / 慢查询或缺少索引
[ ] Bulk write/import operation running / 批量写入/导入操作运行中
[ ] Index build in progress / 索引构建进行中
[ ] Application connection storm / 应用连接风暴
[ ] Instance class undersized for workload / 实例规格不足
```

#### 3.2 Diagnostic Commands / 诊断命令

```bash
# Connect to DocumentDB (TLS required) / 连接 DocumentDB（需要 TLS）
mongo --tls --host CLUSTER_ENDPOINT:27017 \
  --tlsCAFile global-bundle.pem \
  --username dbadmin --password PASSWORD

# Inside mongo shell / mongo shell 内:

# Check current operations (find slow queries) / 检查当前操作（查找慢查询）
db.currentOp({"secs_running": {"$gt": 5}})

# Server status — connections and opcounters / 服务器状态 — 连接数和操作计数
db.serverStatus().connections
db.serverStatus().opcounters

# Check profiler for slow queries / 检查分析器中的慢查询
db.system.profile.find({"millis": {"$gt": 1000}}).sort({"ts": -1}).limit(10)

# Index usage stats / 索引使用统计
db.COLLECTION_NAME.aggregate([{$indexStats: {}}])
```

```bash
# AWS CLI: CloudWatch CPU history / AWS CLI: CloudWatch CPU 历史
aws cloudwatch get-metric-statistics \
  --namespace AWS/DocDB \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=INSTANCE_NAME \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 --statistics Average --region us-east-1

# Check for recent instance events / 检查最近的实例事件
aws docdb describe-events \
  --source-type db-instance \
  --duration 60 --region us-east-1
```

#### 3.3 Root Cause Decision Tree / 根因决策树

```
CPU > 70%?
├─ Yes → Check currentOp for slow queries / 检查 currentOp 慢查询
│  ├─ Slow queries found / 发现慢查询 → Check missing indexes / 检查缺失索引
│  │  ├─ Missing index → Create index (off-peak) / 创建索引（低峰期）
│  │  └─ Index exists → Query optimization needed / 需要查询优化
│  └─ No slow queries / 无慢查询 → Check opcounters rate / 检查操作计数率
│     ├─ High insert/update rate → Bulk operation in progress / 批量操作进行中
│     └─ Normal rate → Instance undersized / 实例规格不足
└─ No → Alert may be resolving / 告警可能正在恢复
```

---

### 4. ACT (行动) — Remediation / 修复

#### 4.1 Tier 2 Actions (US DBA Authority) / Tier 2 操作

```bash
# Kill long-running operations / 终止长时间运行的操作
# In mongo shell:
db.currentOp({"secs_running": {"$gt": 30}}).inprog.forEach(function(op) {
  db.killOp(op.opid);
  print("Killed op: " + op.opid + " running for " + op.secs_running + "s");
});

# Create missing index (if identified) / 创建缺失索引（如果已确认）
# WARNING: Index creation consumes CPU — schedule during low-traffic
# 警告：索引创建消耗 CPU — 安排在低流量时段
db.COLLECTION.createIndex({"field": 1}, {"background": true})
```

#### 4.2 Escalation Criteria / 升级标准

| Condition / 条件 | Action / 操作 |
|-----------|--------|
| CPU stays > 70% after 30 min / CPU 30分钟后仍 > 70% | Escalate to Tier 3 / 升级到 Tier 3 |
| CPU rises above 90% / CPU 超过 90% | Auto-escalates to LCK-MG-002 (Critical) |
| Application errors increasing / 应用错误增加 | Escalate to Tier 3 / 升级到 Tier 3 |

```
Escalation path / 升级路径:
US DBA → (30 min no resolution) → US DBA + Team Lead → (30 min) → China HQ DBA
```

---

### 5. AFTERMATH (善后) — Post-Incident / 事后处理

#### 5.1 Prevention / 预防

```
[ ] Review slow query log and add missing indexes / 审查慢查询日志并添加缺失索引
[ ] Evaluate if instance class needs upgrade / 评估是否需要升级实例规格
[ ] Check application query patterns for inefficiencies / 检查应用查询模式是否有低效问题
[ ] Update threshold if alert too sensitive / 如告警过于敏感则更新阈值
```

#### 5.2 Related Alerts / 相关告警

| Alert ID | Name | Relationship / 关系 |
|----------|------|-------------|
| LCK-MG-002 | MongoCpuHigh_Critical | Escalation if CPU > 90% / CPU > 90% 时升级 |
| LCK-MG-003 | MongoMemoryLow_Warning | CPU and memory often correlate / CPU 和内存常相关 |
| LCK-MG-005 | MongoConnectionHigh_Warning | Connection storms cause CPU spikes / 连接风暴导致 CPU 峰值 |

#### 5.3 Knowledge Base Update / 知识库更新

After resolution, update / 解决后更新:
1. This runbook — add new root causes to Section 3.1 / 将新根因添加到 3.1 节
2. Alert thresholds — PR to `alert-rules-complete.yml` if needed / 如需调整提交 PR
3. Dashboard — add panel if visibility gap found / 如发现可视化缺口则添加面板

---

## LCK-MG-002 — MongoCpuHigh_Critical

### Metadata / 元数据

```yaml
alert_id: "LCK-MG-002"
alert_name: "MongoCpuHigh_Critical"
severity: "critical"
tier: "3"
category: "db-mongo"
team: "dba"
first_responder: "US DBA + China HQ"
old_ids_replaced: "ALR-030, ALR-031"
migration_action: "MERGE"
sla_response: "Tier 3: 5min acknowledge, 15min first update, 1h resolution"
skill_reference: "/app/skills/apm-alert-investigation.md"
last_updated: "2026-02-16"
```

> **Note / 注意:** The YAML rule has `tier: "1"` but the alert inventory assigns Tier 3 per the SLA framework
> (Critical = Tier 3 = 5min acknowledge). This runbook follows the inventory Tier 3 assignment.
> YAML 规则中 `tier: "1"` 但告警清单按 SLA 框架分配为 Tier 3（Critical = Tier 3 = 5分钟确认）。
> 本手册遵循清单中的 Tier 3 分配。

### Alert Rule (from alert-rules-complete.yml) / 告警规则

```yaml
- alert: MongoCpuUsageCritical
  expr: |
    avg_over_time(mongodb_cpu_utilization{env="production"}[3m]) > 90
  for: 3m
  labels:
    severity: "critical"
    tier: "1"
    team: "dba"
    category: "db-mongo"
    service: "documentdb-mongo"
  annotations:
    summary: "[LCK-NA-DB-MONGO] CpuUsage_Critical - {{ $labels.instance }}"
    impact: "MongoDB CPU critical; operations timing out, service degradation imminent."
    notification_channel: "wecom+twilio-all"
```

### 1. ASSESS (评估) — First 2 Minutes / 前2分钟

**Goal / 目标:** Confirm critical CPU state and determine golden path impact immediately.
立即确认关键 CPU 状态并确定对黄金流程的影响。

#### 1.1 Golden Path Impact Check / 黄金流程影响检查

```bash
# IMMEDIATE: Check order flow / 立即检查订单流
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"
# If == 0 → CRITICAL: Golden path DOWN / 如果 == 0 → 严重：黄金流程中断

# Check current CPU / 检查当前 CPU
curl -s "http://prometheus:9090/api/v1/query?query=avg_over_time(mongodb_cpu_utilization{env='production'}[3m])" | jq '.data.result[] | {instance: .metric.instance, cpu: .value[1]}'
```

#### 1.2 Quick Triage / 快速分类

```bash
# Is this a single instance or cluster-wide? / 是单实例还是集群范围？
curl -s "http://prometheus:9090/api/v1/query?query=mongodb_cpu_utilization{env='production'}" | jq '.data.result[] | {instance: .metric.instance, cpu: .value[1]}'

# Check all Mongo alerts firing / 检查所有触发的 Mongo 告警
curl -s "http://alertmanager:9093/api/v2/alerts?filter=category%3D%22db-mongo%22" | jq '.[].labels | {alertname, severity, instance}'
```

#### 1.3 Severity Classification / 严重程度分类

| Condition / 条件 | Severity / 严重程度 | Action / 操作 |
|-----------|----------|--------|
| Golden path DOWN + CPU > 90% | **Critical -> Tier 3** | Wake ALL: China HQ + US DevOps / 通知所有人 |
| CPU > 90% but orders flowing | **Critical -> Tier 3** | US DBA + China HQ coordinate / 协调处理 |
| CPU dropping back below 90% | **Reassess as Warning** | May downgrade to LCK-MG-001 / 可能降级 |

---

### 2. ACKNOWLEDGE (确认) — Within 5 Minutes / 5分钟内

#### 2.1 Silence Alert / 静默告警

```bash
amtool silence add \
  alertname="MongoCpuUsageCritical" \
  category="db-mongo" \
  --duration="15m" \
  --comment="CRITICAL: Investigating CPU > 90% - YOUR_NAME" \
  --author="YOUR_NAME"
```

#### 2.2 WeCom Notification / 企业微信通知

```
🚨 CRITICAL Alert Acknowledged / 严重告警已确认
Alert: MongoCpuHigh_Critical (LCK-MG-002)
Severity: CRITICAL | Tier: 3
Owner: {your_name}
Status: Investigating / 调查中
Instance: {instance}
CPU: {value}% (> 90%)
Golden Path: {OK/IMPACTED}
ETA for update: {time + 15min}
China HQ notified: YES / 已通知中国总部: 是
```

#### 2.3 SLA Timers / SLA 时间要求

| Milestone / 里程碑 | Deadline / 截止时间 |
|-----------|----------|
| Acknowledge / 确认 | **5 min** |
| First Update / 首次更新 | **15 min** |
| Resolution / 解决 | **1 hour** |

---

### 3. ANALYZE (分析) — Root Cause Investigation / 根因调查

#### 3.1 Common Causes Checklist / 常见原因清单

```
[ ] Runaway query consuming all CPU / 失控查询消耗所有 CPU
[ ] Index build on large collection / 大集合上的索引构建
[ ] Bulk data migration or ETL job / 批量数据迁移或 ETL 作业
[ ] Connection storm from application restart / 应用重启导致的连接风暴
[ ] Instance class too small for current workload / 实例规格对当前负载过小
[ ] Background maintenance (compaction) / 后台维护（压缩）
```

#### 3.2 Diagnostic Commands / 诊断命令

```bash
# Connect to DocumentDB / 连接 DocumentDB
mongo --tls --host CLUSTER_ENDPOINT:27017 \
  --tlsCAFile global-bundle.pem \
  --username dbadmin --password PASSWORD

# IMMEDIATE: Find CPU-burning operations / 立即查找消耗 CPU 的操作
db.currentOp({"secs_running": {"$gt": 3}})

# Check opcounters for abnormal rates / 检查操作计数器是否异常
db.serverStatus().opcounters

# Connection count (connection storm?) / 连接数（连接风暴？）
db.serverStatus().connections

# Profiler: slowest queries in last 10 min / 分析器：最近10分钟最慢查询
db.system.profile.find({"millis": {"$gt": 500}}).sort({"ts": -1}).limit(20)

# Collection scan detection / 全表扫描检测
db.system.profile.find({"planSummary": "COLLSCAN"}).sort({"ts": -1}).limit(10)
```

```bash
# AWS CLI: CPU spike timeline / AWS CLI: CPU 峰值时间线
aws cloudwatch get-metric-statistics \
  --namespace AWS/DocDB \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=INSTANCE_NAME \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 --statistics Average,Maximum --region us-east-1

# Check for recent DocumentDB events / 检查最近的 DocumentDB 事件
aws docdb describe-events \
  --source-type db-instance \
  --duration 120 --region us-east-1

# Instance class (check if undersized) / 实例规格（检查是否不足）
aws docdb describe-db-instances --region us-east-1 | \
  jq '.DBInstances[] | {id: .DBInstanceIdentifier, class: .DBInstanceClass, status: .DBInstanceStatus}'
```

---

### 4. ACT (行动) — Remediation / 修复

#### 4.1 Tier 3 Actions (US DBA + China HQ) / Tier 3 操作

```bash
# IMMEDIATE: Kill all long-running operations / 立即终止所有长时间运行的操作
db.currentOp({"secs_running": {"$gt": 10}}).inprog.forEach(function(op) {
  db.killOp(op.opid);
  print("KILLED op: " + op.opid + " ns: " + op.ns + " running: " + op.secs_running + "s");
});

# If application is flooding connections / 如果应用大量涌入连接:
# Coordinate with application team to reduce connection pool size
# 与应用团队协调减少连接池大小

# Emergency: Scale up instance class (requires China HQ approval)
# 紧急：升级实例规格（需要中国总部批准）
aws docdb modify-db-instance \
  --db-instance-identifier INSTANCE_NAME \
  --db-instance-class db.r6g.xlarge \
  --apply-immediately --region us-east-1
# WARNING: Instance will reboot during class change! / 警告：更改规格期间实例将重启！

# Add read replica to offload reads (if read-heavy) / 添加只读副本分流读取（如果读取密集）
aws docdb create-db-instance \
  --db-instance-identifier INSTANCE_NAME-reader \
  --db-instance-class db.r6g.large \
  --db-cluster-identifier CLUSTER_NAME \
  --region us-east-1
```

#### 4.2 Escalation Criteria / 升级标准

| Condition / 条件 | Action / 操作 |
|-----------|--------|
| CPU > 90% after 15 min of remediation / 修复15分钟后 CPU 仍 > 90% | Failover to replica / 故障转移到副本 |
| Golden path impacted / 黄金流程受影响 | All hands — US + China HQ / 全员 — US + 中国总部 |
| Cannot identify root cause in 30 min / 30分钟内无法确定根因 | Engage AWS Support / 联系 AWS 支持 |

```bash
# Emergency failover (LAST RESORT) / 紧急故障转移（最后手段）
aws docdb failover-db-cluster \
  --db-cluster-identifier CLUSTER_NAME \
  --region us-east-1
# This promotes a replica to primary / 这将把副本提升为主节点
```

---

### 5. AFTERMATH (善后) — Post-Incident / 事后处理

#### 5.1 Prevention / 预防

```
[ ] Mandatory incident report within 24 hours / 24小时内必须提交事件报告
[ ] Root cause analysis with application team / 与应用团队进行根因分析
[ ] Index audit on affected collections / 对受影响集合进行索引审计
[ ] Load test to validate capacity / 负载测试验证容量
[ ] Evaluate instance class upgrade (permanent) / 评估实例规格升级（永久）
[ ] Review application query patterns / 审查应用查询模式
```

#### 5.2 Related Alerts / 相关告警

| Alert ID | Name | Relationship / 关系 |
|----------|------|-------------|
| LCK-MG-001 | MongoCpuHigh_Warning | Warning precursor to this alert / 此告警的预警前兆 |
| LCK-MG-003 | MongoMemoryLow_Warning | CPU stress often causes memory pressure / CPU 压力常导致内存压力 |
| LCK-MG-004 | MongoMemoryLow_Critical | May fire simultaneously / 可能同时触发 |
| LCK-MG-005 | MongoConnectionHigh_Warning | Connection storms cause CPU spikes / 连接风暴导致 CPU 峰值 |

#### 5.3 Knowledge Base Update / 知识库更新

After resolution, update / 解决后更新:
1. This runbook — add new root causes and effective remediations / 添加新根因和有效修复措施
2. Incident report — file in `/app/alertrebuild/incidents/` / 在事件目录中归档
3. Alert thresholds — PR to `alert-rules-complete.yml` if needed / 如需调整提交 PR
4. Capacity plan — update DocumentDB sizing recommendations / 更新 DocumentDB 容量规划建议

---

## LCK-MG-003 — MongoMemoryLow_Warning

### Metadata / 元数据

```yaml
alert_id: "LCK-MG-003"
alert_name: "MongoMemoryLow_Warning"
severity: "warning"
tier: "2"
category: "db-mongo"
team: "dba"
first_responder: "US DBA"
old_ids_replaced: "ALR-032"
migration_action: "KEEP"
sla_response: "Tier 2: 15min acknowledge, 1h first update, 4h resolution"
skill_reference: "/app/skills/apm-alert-investigation.md"
last_updated: "2026-02-16"
```

### Alert Rule (from alert-rules-complete.yml) / 告警规则

```yaml
- alert: MongoMemoryFreeWarning
  expr: |
    mongodb_freeable_memory_bytes{env="production"} / 1024 / 1024 < 500
    and
    mongodb_freeable_memory_bytes{env="production"} / 1024 / 1024 >= 200
  for: 5m
  labels:
    severity: "warning"
    tier: "2"
    team: "dba"
    category: "db-mongo"
    service: "documentdb-mongo"
  annotations:
    summary: "[LCK-NA-DB-MONGO] MemoryFreeLow_Warning - {{ $labels.instance }}"
    impact: "MongoDB freeable memory low; swap usage may increase, performance degrades."
    notification_channel: "wecom+twilio-lead"
```

### 1. ASSESS (评估) — First 2 Minutes / 前2分钟

**Goal / 目标:** Determine memory consumption source and assess impact.
确定内存消耗来源并评估影响。

#### 1.1 Golden Path Impact Check / 黄金流程影响检查

```bash
# Check order flow / 检查订单流
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"
```

#### 1.2 Quick Triage / 快速分类

```bash
# Current freeable memory / 当前可用内存
curl -s "http://prometheus:9090/api/v1/query?query=mongodb_freeable_memory_bytes{env='production'}/1024/1024" | jq '.data.result[] | {instance: .metric.instance, memory_mb: .value[1]}'

# Memory trend (last 1h) / 内存趋势（最近1小时）
# Check in Grafana: https://grafana.luckinus.com/d/mongo-memory
```

#### 1.3 Severity Classification / 严重程度分类

| Condition / 条件 | Severity / 严重程度 | Action / 操作 |
|-----------|----------|--------|
| Memory < 500MB, trending down fast / 内存 < 500MB 且快速下降 | **Warning -> Tier 2** | Investigate immediately / 立即调查 |
| Memory < 500MB, stable / 内存 < 500MB，稳定 | **Warning -> Tier 2** | Investigate and plan / 调查并制定计划 |
| Memory recovering (> 500MB) / 内存恢复中 | **Resolving** | Monitor / 监控 |

---

### 2. ACKNOWLEDGE (确认) — Within 15 Minutes / 15分钟内

#### 2.1 Silence Alert / 静默告警

```bash
amtool silence add \
  alertname="MongoMemoryFreeWarning" \
  category="db-mongo" \
  --duration="30m" \
  --comment="Investigating low memory - YOUR_NAME" \
  --author="YOUR_NAME"
```

#### 2.2 WeCom Notification / 企业微信通知

```
🔔 Alert Acknowledged / 告警已确认
Alert: MongoMemoryLow_Warning (LCK-MG-003)
Severity: Warning | Tier: 2
Owner: {your_name}
Status: Investigating / 调查中
Instance: {instance}
Freeable Memory: {value}MB (threshold: < 500MB)
ETA for update: {time + 15min}
```

#### 2.3 SLA Timers / SLA 时间要求

| Milestone / 里程碑 | Deadline / 截止时间 |
|-----------|----------|
| Acknowledge / 确认 | 15 min |
| First Update / 首次更新 | 1 hour |
| Resolution / 解决 | 4 hours |

---

### 3. ANALYZE (分析) — Root Cause Investigation / 根因调查

#### 3.1 Common Causes Checklist / 常见原因清单

```
[ ] Working set exceeds available memory / 工作集超过可用内存
[ ] Large sort operations spilling to disk / 大排序操作溢出到磁盘
[ ] Too many open cursors / 打开的游标过多
[ ] Memory leak in application connection pool / 应用连接池内存泄漏
[ ] Instance class too small / 实例规格过小
[ ] Swap usage increasing (performance degradation) / 交换使用增加（性能下降）
```

#### 3.2 Diagnostic Commands / 诊断命令

```bash
# Connect to DocumentDB / 连接 DocumentDB
mongo --tls --host CLUSTER_ENDPOINT:27017 \
  --tlsCAFile global-bundle.pem \
  --username dbadmin --password PASSWORD

# Check server status — memory section / 检查服务器状态 — 内存部分
db.serverStatus().mem

# Connection count (each connection uses memory) / 连接数（每个连接占用内存）
db.serverStatus().connections

# Check for large sort operations / 检查大排序操作
db.currentOp({"secs_running": {"$gt": 5}})

# Collection sizes (identify memory pressure source) / 集合大小（识别内存压力来源）
db.getCollectionNames().forEach(function(c) {
  var stats = db.getCollection(c).stats();
  print(c + ": " + Math.round(stats.size/1024/1024) + "MB, indexes: " + Math.round(stats.totalIndexSize/1024/1024) + "MB");
});
```

```bash
# AWS CLI: Memory metrics / AWS CLI: 内存指标
aws cloudwatch get-metric-statistics \
  --namespace AWS/DocDB \
  --metric-name FreeableMemory \
  --dimensions Name=DBInstanceIdentifier,Value=INSTANCE_NAME \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 --statistics Minimum,Average --region us-east-1

# Swap usage / 交换使用量
aws cloudwatch get-metric-statistics \
  --namespace AWS/DocDB \
  --metric-name SwapUsage \
  --dimensions Name=DBInstanceIdentifier,Value=INSTANCE_NAME \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 --statistics Maximum --region us-east-1
```

#### 3.3 Root Cause Decision Tree / 根因决策树

```
Freeable Memory < 500MB?
├─ Yes → Check connections count / 检查连接数
│  ├─ Connections high (> 80% max) → Connection pool issue / 连接池问题 → See LCK-MG-005
│  └─ Connections normal / 连接正常 → Check collection sizes / 检查集合大小
│     ├─ Working set growing → Instance class upgrade needed / 需要升级实例规格
│     └─ Working set stable → Check for sort spills / 检查排序溢出
│        ├─ Sort spills → Add indexes for sort operations / 为排序操作添加索引
│        └─ No spills → Monitor, may need more memory / 监控，可能需要更多内存
└─ No → Alert resolving / 告警恢复中
```

---

### 4. ACT (行动) — Remediation / 修复

#### 4.1 Tier 2 Actions (US DBA Authority) / Tier 2 操作

```bash
# Kill memory-intensive operations / 终止内存密集操作
db.currentOp({"secs_running": {"$gt": 30}}).inprog.forEach(function(op) {
  db.killOp(op.opid);
});

# Close idle cursors / 关闭空闲游标
# (DocumentDB manages cursor timeout automatically at 10 min)
# (DocumentDB 自动管理游标超时，10分钟)

# If connection pool is the issue, coordinate with app team to:
# 如果连接池是问题，与应用团队协调:
# - Reduce maxPoolSize / 减少 maxPoolSize
# - Enable connection pool monitoring / 启用连接池监控
```

#### 4.2 Escalation Criteria / 升级标准

| Condition / 条件 | Action / 操作 |
|-----------|--------|
| Memory drops below 200MB / 内存降到 200MB 以下 | Auto-escalates to LCK-MG-004 (Critical) |
| Swap usage > 100MB / 交换使用 > 100MB | Escalate to Tier 3 / 升级到 Tier 3 |
| Performance visibly degraded / 性能明显下降 | Escalate to Tier 3 / 升级到 Tier 3 |

---

### 5. AFTERMATH (善后) — Post-Incident / 事后处理

#### 5.1 Prevention / 预防

```
[ ] Review instance sizing vs working set / 审查实例规格与工作集大小
[ ] Implement memory usage trending dashboard / 实施内存使用趋势仪表板
[ ] Add indexes for queries causing sort spills / 为导致排序溢出的查询添加索引
[ ] Review application connection pool settings / 审查应用连接池设置
```

#### 5.2 Related Alerts / 相关告警

| Alert ID | Name | Relationship / 关系 |
|----------|------|-------------|
| LCK-MG-004 | MongoMemoryLow_Critical | Escalation if memory < 200MB / 内存 < 200MB 时升级 |
| LCK-MG-001 | MongoCpuHigh_Warning | Low memory causes more CPU (swapping) / 低内存导致更多 CPU（交换） |
| LCK-MG-005 | MongoConnectionHigh_Warning | Connections consume memory / 连接消耗内存 |

---

## LCK-MG-004 — MongoMemoryLow_Critical

### Metadata / 元数据

```yaml
alert_id: "LCK-MG-004"
alert_name: "MongoMemoryLow_Critical"
severity: "critical"
tier: "3"
category: "db-mongo"
team: "dba"
first_responder: "US DBA + China HQ"
old_ids_replaced: "ALR-032"
migration_action: "SPLIT"
sla_response: "Tier 3: 5min acknowledge, 15min first update, 1h resolution"
skill_reference: "/app/skills/apm-alert-investigation.md"
last_updated: "2026-02-16"
```

> **Note / 注意:** The YAML rule has `tier: "1"` but the alert inventory assigns Tier 3 per the SLA framework
> (Critical = Tier 3 = 5min acknowledge). This runbook follows the inventory Tier 3 assignment.
> YAML 规则中 `tier: "1"` 但告警清单按 SLA 框架分配为 Tier 3（Critical = Tier 3 = 5分钟确认）。
> 本手册遵循清单中的 Tier 3 分配。

### Alert Rule (from alert-rules-complete.yml) / 告警规则

```yaml
- alert: MongoMemoryFreeCritical
  expr: |
    mongodb_freeable_memory_bytes{env="production"} / 1024 / 1024 < 200
  for: 3m
  labels:
    severity: "critical"
    tier: "1"
    team: "dba"
    category: "db-mongo"
    service: "documentdb-mongo"
  annotations:
    summary: "[LCK-NA-DB-MONGO] MemoryFreeLow_Critical - {{ $labels.instance }}"
    impact: "MongoDB memory critically low; OOM kill risk, potential instance crash."
    notification_channel: "wecom+twilio-all"
```

### 1. ASSESS (评估) — First 2 Minutes / 前2分钟

**Goal / 目标:** Confirm critical memory state and assess OOM risk immediately.
立即确认关键内存状态并评估 OOM 风险。

#### 1.1 Golden Path Impact Check / 黄金流程影响检查

```bash
# IMMEDIATE: Check order flow / 立即检查订单流
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"

# Check current freeable memory / 检查当前可用内存
curl -s "http://prometheus:9090/api/v1/query?query=mongodb_freeable_memory_bytes{env='production'}/1024/1024" | jq '.data.result[] | {instance: .metric.instance, memory_mb: .value[1]}'
```

#### 1.2 Quick Triage / 快速分类

```bash
# Check swap usage (DocumentDB may be swapping) / 检查交换使用（DocumentDB 可能在交换）
aws cloudwatch get-metric-statistics \
  --namespace AWS/DocDB \
  --metric-name SwapUsage \
  --dimensions Name=DBInstanceIdentifier,Value=INSTANCE_NAME \
  --start-time $(date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 --statistics Maximum --region us-east-1
```

#### 1.3 Severity Classification / 严重程度分类

| Condition / 条件 | Severity / 严重程度 | Action / 操作 |
|-----------|----------|--------|
| Memory < 200MB + golden path down / 内存 < 200MB + 黄金流程中断 | **Critical -> Tier 3** | All hands — emergency / 全员 — 紧急 |
| Memory < 200MB + orders flowing / 内存 < 200MB + 订单正常 | **Critical -> Tier 3** | US DBA + China HQ / 紧急处理 |
| Memory recovering above 200MB / 内存恢复至 200MB 以上 | **Reassess as Warning** | May downgrade to LCK-MG-003 |

---

### 2. ACKNOWLEDGE (确认) — Within 5 Minutes / 5分钟内

#### 2.1 Silence Alert / 静默告警

```bash
amtool silence add \
  alertname="MongoMemoryFreeCritical" \
  category="db-mongo" \
  --duration="15m" \
  --comment="CRITICAL: Memory < 200MB, OOM risk - YOUR_NAME" \
  --author="YOUR_NAME"
```

#### 2.2 WeCom Notification / 企业微信通知

```
🚨 CRITICAL Alert Acknowledged / 严重告警已确认
Alert: MongoMemoryLow_Critical (LCK-MG-004)
Severity: CRITICAL | Tier: 3
Owner: {your_name}
Status: Investigating / 调查中
Instance: {instance}
Freeable Memory: {value}MB (threshold: < 200MB) — OOM RISK
Golden Path: {OK/IMPACTED}
ETA for update: {time + 15min}
China HQ notified: YES / 已通知中国总部: 是
```

#### 2.3 SLA Timers / SLA 时间要求

| Milestone / 里程碑 | Deadline / 截止时间 |
|-----------|----------|
| Acknowledge / 确认 | **5 min** |
| First Update / 首次更新 | **15 min** |
| Resolution / 解决 | **1 hour** |

---

### 3. ANALYZE (分析) — Root Cause Investigation / 根因调查

#### 3.1 Common Causes Checklist / 常见原因清单

```
[ ] Working set far exceeds instance memory / 工作集远超实例内存
[ ] Memory leak from application connections / 应用连接内存泄漏
[ ] Massive sort/aggregation operations / 大量排序/聚合操作
[ ] Connection count explosion / 连接数爆发
[ ] Instance class severely undersized / 实例规格严重不足
[ ] Swap exhaustion approaching OOM / 交换耗尽接近 OOM
```

#### 3.2 Diagnostic Commands / 诊断命令

```bash
# Connect to DocumentDB / 连接 DocumentDB
mongo --tls --host CLUSTER_ENDPOINT:27017 \
  --tlsCAFile global-bundle.pem \
  --username dbadmin --password PASSWORD

# IMMEDIATE: Check memory and connections / 立即检查内存和连接
db.serverStatus().mem
db.serverStatus().connections

# Kill all non-essential operations / 终止所有非必要操作
db.currentOp({"secs_running": {"$gt": 5}}).inprog.forEach(function(op) {
  if (op.ns !== "admin.$cmd") {
    db.killOp(op.opid);
    print("KILLED: " + op.opid + " ns: " + op.ns);
  }
});
```

```bash
# AWS CLI: Memory + swap timeline / AWS CLI: 内存 + 交换时间线
aws cloudwatch get-metric-statistics \
  --namespace AWS/DocDB \
  --metric-name FreeableMemory \
  --dimensions Name=DBInstanceIdentifier,Value=INSTANCE_NAME \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 --statistics Minimum --region us-east-1

# Check current instance class / 检查当前实例规格
aws docdb describe-db-instances --region us-east-1 | \
  jq '.DBInstances[] | {id: .DBInstanceIdentifier, class: .DBInstanceClass, status: .DBInstanceStatus}'
```

---

### 4. ACT (行动) — Remediation / 修复

#### 4.1 Tier 3 Actions (US DBA + China HQ) / Tier 3 操作

```bash
# STEP 1: Kill all heavy operations immediately / 步骤1：立即终止所有重型操作
db.currentOp({"secs_running": {"$gt": 3}}).inprog.forEach(function(op) {
  db.killOp(op.opid);
  print("EMERGENCY KILL: " + op.opid);
});

# STEP 2: Scale up instance class (requires China HQ approval)
# 步骤2：升级实例规格（需要中国总部批准）
aws docdb modify-db-instance \
  --db-instance-identifier INSTANCE_NAME \
  --db-instance-class db.r6g.xlarge \
  --apply-immediately --region us-east-1
# WARNING: Instance reboots during class change! Expect ~5min downtime.
# 警告：更改规格期间实例重启！预计约5分钟停机。

# STEP 3: If instance cannot be scaled, failover to a larger replica
# 步骤3：如果无法升级实例，故障转移到更大的副本
aws docdb failover-db-cluster \
  --db-cluster-identifier CLUSTER_NAME \
  --region us-east-1
```

#### 4.2 Escalation Criteria / 升级标准

| Condition / 条件 | Action / 操作 |
|-----------|--------|
| Memory still < 200MB after killing ops / 终止操作后内存仍 < 200MB | Scale up instance immediately / 立即升级实例 |
| Instance crash or OOM / 实例崩溃或 OOM | Failover + AWS Support case / 故障转移 + 提交 AWS 支持工单 |
| Golden path impacted > 5 min / 黄金流程受影响 > 5分钟 | All hands + China HQ CTO / 全员 + 中国总部 CTO |

---

### 5. AFTERMATH (善后) — Post-Incident / 事后处理

#### 5.1 Prevention / 预防

```
[ ] Mandatory incident report within 24 hours / 24小时内必须提交事件报告
[ ] Instance class review — permanently upgrade if needed / 实例规格审查 — 必要时永久升级
[ ] Application memory profiling / 应用内存分析
[ ] Set up memory trending alerts at 70% / 设置 70% 内存趋势告警
[ ] Connection pool audit across all services / 所有服务的连接池审计
[ ] Evaluate adding read replicas / 评估添加只读副本
```

#### 5.2 Related Alerts / 相关告警

| Alert ID | Name | Relationship / 关系 |
|----------|------|-------------|
| LCK-MG-003 | MongoMemoryLow_Warning | Warning precursor / 预警前兆 |
| LCK-MG-001 | MongoCpuHigh_Warning | Low memory causes CPU spikes (swapping) / 低内存导致 CPU 峰值 |
| LCK-MG-002 | MongoCpuHigh_Critical | May fire simultaneously / 可能同时触发 |
| LCK-MG-005 | MongoConnectionHigh_Warning | Connections consume memory / 连接消耗内存 |

---

## LCK-MG-005 — MongoConnectionHigh_Warning

### Metadata / 元数据

```yaml
alert_id: "LCK-MG-005"
alert_name: "MongoConnectionHigh_Warning"
severity: "warning"
tier: "2"
category: "db-mongo"
team: "dba"
first_responder: "US DBA"
old_ids_replaced: "—"
migration_action: "NEW"
sla_response: "Tier 2: 15min acknowledge, 1h first update, 4h resolution"
skill_reference: "/app/skills/apm-alert-investigation.md"
last_updated: "2026-02-16"
```

### Alert Rule (from alert-rules-complete.yml) / 告警规则

```yaml
- alert: MongoConnectionHighWarning
  expr: |
    mongodb_connections_current{env="production"}
    / mongodb_connections_max{env="production"} * 100 > 80
  for: 5m
  labels:
    severity: "warning"
    tier: "2"
    team: "dba"
    category: "db-mongo"
    service: "documentdb-mongo"
  annotations:
    summary: "[LCK-NA-DB-MONGO] ConnectionHigh_Warning - {{ $labels.instance }}"
    impact: "MongoDB connection pool nearing capacity; new connections may be refused."
    notification_channel: "wecom+twilio-lead"
```

### 1. ASSESS (评估) — First 2 Minutes / 前2分钟

**Goal / 目标:** Determine connection consumption source and assess risk of connection exhaustion.
确定连接消耗来源并评估连接耗尽风险。

#### 1.1 Golden Path Impact Check / 黄金流程影响检查

```bash
# Check order flow / 检查订单流
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"

# Check connection utilization / 检查连接利用率
curl -s "http://prometheus:9090/api/v1/query?query=mongodb_connections_current{env='production'}/mongodb_connections_max{env='production'}*100" | jq '.data.result[] | {instance: .metric.instance, connection_pct: .value[1]}'
```

#### 1.2 Quick Triage / 快速分类

```bash
# Current and max connections / 当前和最大连接数
curl -s "http://prometheus:9090/api/v1/query?query=mongodb_connections_current{env='production'}" | jq '.data.result[] | {instance: .metric.instance, current: .value[1]}'
curl -s "http://prometheus:9090/api/v1/query?query=mongodb_connections_max{env='production'}" | jq '.data.result[] | {instance: .metric.instance, max: .value[1]}'

# Check if recent deployments may have caused connection surge / 检查最近部署是否导致连接激增
kubectl get events -n production --sort-by='.lastTimestamp' --field-selector reason=Pulling | tail -10
```

#### 1.3 Severity Classification / 严重程度分类

| Condition / 条件 | Severity / 严重程度 | Action / 操作 |
|-----------|----------|--------|
| > 80% connections, new connections failing / > 80% 连接，新连接失败 | **Warning -> Tier 2** (may escalate) | Immediate investigation / 立即调查 |
| > 80% connections, apps functioning / > 80% 连接，应用正常 | **Warning -> Tier 2** | Investigate connection pool / 调查连接池 |
| Connection count decreasing / 连接数下降 | **Resolving** | Monitor trend / 监控趋势 |

---

### 2. ACKNOWLEDGE (确认) — Within 15 Minutes / 15分钟内

#### 2.1 Silence Alert / 静默告警

```bash
amtool silence add \
  alertname="MongoConnectionHighWarning" \
  category="db-mongo" \
  --duration="30m" \
  --comment="Investigating high connections - YOUR_NAME" \
  --author="YOUR_NAME"
```

#### 2.2 WeCom Notification / 企业微信通知

```
🔔 Alert Acknowledged / 告警已确认
Alert: MongoConnectionHigh_Warning (LCK-MG-005)
Severity: Warning | Tier: 2
Owner: {your_name}
Status: Investigating / 调查中
Instance: {instance}
Connection Usage: {value}% of max
ETA for update: {time + 15min}
```

#### 2.3 SLA Timers / SLA 时间要求

| Milestone / 里程碑 | Deadline / 截止时间 |
|-----------|----------|
| Acknowledge / 确认 | 15 min |
| First Update / 首次更新 | 1 hour |
| Resolution / 解决 | 4 hours |

---

### 3. ANALYZE (分析) — Root Cause Investigation / 根因调查

#### 3.1 Common Causes Checklist / 常见原因清单

```
[ ] Application pod scaling event (more pods = more connections) / 应用 Pod 扩展事件
[ ] Connection pool misconfiguration (maxPoolSize too high) / 连接池配置错误
[ ] Connection leak (connections not properly closed) / 连接泄漏（连接未正确关闭）
[ ] Application restart causing reconnection storm / 应用重启导致重连风暴
[ ] Slow queries holding connections open / 慢查询占用连接
[ ] Cron job or batch process opening many connections / 定时任务或批处理打开大量连接
```

#### 3.2 Diagnostic Commands / 诊断命令

```bash
# Connect to DocumentDB / 连接 DocumentDB
mongo --tls --host CLUSTER_ENDPOINT:27017 \
  --tlsCAFile global-bundle.pem \
  --username dbadmin --password PASSWORD

# Connection details / 连接详情
db.serverStatus().connections
# Output: { "current": N, "available": M, "totalCreated": T }

# What's each connection doing? / 每个连接在做什么？
db.currentOp(true).inprog.forEach(function(op) {
  print("client: " + op.client + " | ns: " + op.ns + " | secs: " + (op.secs_running || 0) + " | op: " + op.op);
});

# Count connections by client IP (identify top consumers) / 按客户端 IP 统计连接数
db.currentOp(true).inprog.reduce(function(acc, op) {
  var ip = (op.client || "unknown").split(":")[0];
  acc[ip] = (acc[ip] || 0) + 1;
  return acc;
}, {})

# Check if connections are idle / 检查连接是否空闲
db.currentOp(true).inprog.filter(function(op) { return op.op === "none"; }).length
```

```bash
# AWS CLI: Connection history / AWS CLI: 连接历史
aws cloudwatch get-metric-statistics \
  --namespace AWS/DocDB \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=INSTANCE_NAME \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 --statistics Maximum --region us-east-1

# Check pod count (correlation with connections) / 检查 Pod 数量（与连接数的相关性）
kubectl get pods -n production --no-headers | wc -l

# Recent HPA scaling events / 最近的 HPA 扩展事件
kubectl get events -n production --field-selector reason=SuccessfulRescale --sort-by='.lastTimestamp' | tail -10
```

#### 3.3 Root Cause Decision Tree / 根因决策树

```
Connections > 80% of max?
├─ Yes → Check connection growth rate / 检查连接增长速率
│  ├─ Sudden spike / 突然飙升 → Check for app restart or scaling event / 检查应用重启或扩展事件
│  │  ├─ App scaling event → Expected, wait for stabilization / 预期内，等待稳定
│  │  └─ No scaling event → Connection leak suspected / 怀疑连接泄漏
│  └─ Gradual increase / 逐渐增加 → Check idle connection count / 检查空闲连接数
│     ├─ Many idle connections → Connection pool not recycling / 连接池未回收
│     └─ Active connections → Workload increase / 工作负载增加
└─ No → Alert resolving / 告警恢复中
```

---

### 4. ACT (行动) — Remediation / 修复

#### 4.1 Tier 2 Actions (US DBA Authority) / Tier 2 操作

```bash
# Kill idle connections (holding resources but not working)
# 终止空闲连接（占用资源但未工作）
# In DocumentDB, idle connections are managed by the application pool.
# Coordinate with application teams to:
# 与应用团队协调:

# 1. Reduce maxPoolSize in application connection strings
# 1. 减少应用连接字符串中的 maxPoolSize
# Example (Java/Node.js): maxPoolSize=20 → maxPoolSize=10

# 2. Enable maxIdleTimeMS to close idle connections
# 2. 启用 maxIdleTimeMS 关闭空闲连接
# Example: mongodb://...?maxIdleTimeMS=60000

# Kill long-running operations that are holding connections / 终止长时间运行的操作
db.currentOp({"secs_running": {"$gt": 60}}).inprog.forEach(function(op) {
  db.killOp(op.opid);
  print("Killed idle/long op: " + op.opid);
});
```

#### 4.2 Escalation Criteria / 升级标准

| Condition / 条件 | Action / 操作 |
|-----------|--------|
| Connections reach 95% of max / 连接达到最大值的 95% | Escalate to Tier 3 / 升级到 Tier 3 |
| New connections being refused (app errors) / 新连接被拒绝（应用报错） | Escalate to Tier 3 / 升级到 Tier 3 |
| Cannot identify connection source in 30 min / 30分钟内无法确定连接来源 | Escalate to Tier 3 / 升级到 Tier 3 |

```bash
# If Tier 3 escalation needed: Scale up instance (more memory = more max connections)
# 如果需要升级到 Tier 3：升级实例（更多内存 = 更多最大连接数）
# DocumentDB max connections ≈ 100 per GiB RAM
aws docdb modify-db-instance \
  --db-instance-identifier INSTANCE_NAME \
  --db-instance-class db.r6g.xlarge \
  --apply-immediately --region us-east-1
```

---

### 5. AFTERMATH (善后) — Post-Incident / 事后处理

#### 5.1 Prevention / 预防

```
[ ] Audit all application connection pool configurations / 审计所有应用连接池配置
[ ] Set maxPoolSize appropriate for workload / 设置适合工作负载的 maxPoolSize
[ ] Enable maxIdleTimeMS on all connection strings / 在所有连接字符串上启用 maxIdleTimeMS
[ ] Add connection monitoring to application health checks / 将连接监控添加到应用健康检查
[ ] Document expected connection count per service / 记录每个服务的预期连接数
[ ] Consider connection pooling middleware if many microservices / 如果有很多微服务考虑连接池中间件
```

#### 5.2 Related Alerts / 相关告警

| Alert ID | Name | Relationship / 关系 |
|----------|------|-------------|
| LCK-MG-001 | MongoCpuHigh_Warning | High connections increase CPU / 高连接数增加 CPU |
| LCK-MG-003 | MongoMemoryLow_Warning | Each connection uses memory / 每个连接占用内存 |
| LCK-MG-004 | MongoMemoryLow_Critical | Connection exhaustion may trigger OOM / 连接耗尽可能触发 OOM |

#### 5.3 Knowledge Base Update / 知识库更新

After resolution, update / 解决后更新:
1. This runbook — add connection source patterns / 添加连接来源模式
2. Application docs — update recommended pool settings / 更新推荐的连接池设置
3. Alert thresholds — PR to `alert-rules-complete.yml` if needed / 如需调整提交 PR
4. Monitoring — add per-service connection tracking dashboard / 添加按服务的连接跟踪仪表板

---

## Appendix A: DocumentDB Instance Reference / 附录A：DocumentDB 实例参考

| Instance Class / 实例规格 | vCPU | Memory (GiB) | Max Connections (est.) / 最大连接数（估计） |
|--------------|------|-------------|--------------------------|
| db.r6g.large | 2 | 16 | ~1,600 |
| db.r6g.xlarge | 4 | 32 | ~3,200 |
| db.r6g.2xlarge | 8 | 64 | ~6,400 |
| db.r6g.4xlarge | 16 | 128 | ~12,800 |
| db.t3.medium | 2 | 4 | ~400 |

> Max connections formula / 最大连接数公式: ~100 connections per GiB of RAM

---

## Appendix B: Old-to-New Alert ID Mapping / 附录B：新旧告警ID对照

| Old ID / 旧ID | Old Name / 旧名称 | New ID / 新ID | New Name / 新名称 | Action / 操作 |
|--------|----------|--------|----------|--------|
| ALR-030 | MongoCpuHigh | LCK-MG-001 | MongoCpuHigh_Warning | KEEP — split warning tier |
| ALR-030, ALR-031 | MongoCpuHigh, MongoCpuCritical | LCK-MG-002 | MongoCpuHigh_Critical | MERGE — unified critical |
| ALR-032 | MongoMemoryLow | LCK-MG-003 | MongoMemoryLow_Warning | KEEP — warning tier |
| ALR-032 | MongoMemoryLow | LCK-MG-004 | MongoMemoryLow_Critical | SPLIT — new critical tier |
| — | (none) | LCK-MG-005 | MongoConnectionHigh_Warning | NEW — no prior coverage |

---

## Appendix C: MCP Skill & Datasource Quick Reference / 附录C：MCP 技能和数据源快速参考

### Skill Files / 技能文件

| Category / 分类 | Skill File / 技能文件 | Invocation / 调用 |
|----------|-----------|------------|
| APM/General | `/app/skills/apm-alert-investigation.md` | `/investigate-apm` |
| RDS (related) | `/app/skills/rds-alert-investigation.md` | `/investigate-rds` |
| EC2 (if host issue) | `/app/skills/ec2-alert-investigation.md` | `/investigate-ec2` |

### Datasource UIDs / 数据源UID

| Datasource | UID | Purpose / 用途 |
|------------|-----|---------|
| UMBQuerier-Luckin | `df8o21agxtkw0d` | Primary Prometheus (MongoDB, node, RDS, business metrics) |
| prometheus | `ff7hkeec6c9a8e` | General metrics / 通用指标 |
| prometheus_redis | `ff6p0gjt24phce` | Redis/ElastiCache metrics / Redis 指标 |

### VMAlert Endpoints / VMAlert 节点

| Instance / 实例 | IP:Port | Role / 角色 |
|----------|---------|------|
| Basic | 10.238.3.153:8880 | Infrastructure alert evaluation (includes MongoDB) |
| APM-1 | 10.238.3.137:8880 | APM alert evaluation |
| APM-2 | 10.238.3.143:8880 | APM alert evaluation |
| APM-3 | 10.238.3.52:8880 | APM alert evaluation |

### Dashboard URLs / 仪表板链接

```
MongoDB Overview: https://grafana.luckinus.com/d/mongo-overview
MongoDB Memory:   https://grafana.luckinus.com/d/mongo-memory
MongoDB Connections: https://grafana.luckinus.com/d/mongo-connections
```

---

*End of Part 5 — DB-MONGO Runbooks*
*第5部分结束 — DB-MONGO 运维手册*

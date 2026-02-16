# Luckin Coffee NA -- Production Alert Runbooks
# Part 4 of 8: DB-ES -- Elasticsearch
# 瑞幸咖啡北美 -- 生产告警运维手册 第4部分（共8部分）：DB-ES -- Elasticsearch

> **Version / 版本:** 1.0
> **Category / 类别:** DB-ES (Elasticsearch)
> **Total Alerts / 告警总数:** 6 (3 warning + 3 critical)
> **Format / 格式:** 5 A's Pattern (Assess, Acknowledge, Analyze, Act, Aftermath)
> **Language / 语言:** Bilingual English + Simplified Chinese (中英双语)
> **Platform / 平台:** AWS (us-east-1) | Account: 257394478466

---

## Table of Contents / 目录

| # | Alert ID | Alert Name | Severity | Page |
|---|----------|------------|----------|------|
| 1 | LCK-ES-001 | ESClusterYellow_Warning | warning | [Link](#lck-es-001) |
| 2 | LCK-ES-002 | ESClusterRed_Critical | critical | [Link](#lck-es-002) |
| 3 | LCK-ES-003 | ESCpuHigh_Warning | warning | [Link](#lck-es-003) |
| 4 | LCK-ES-004 | ESCpuHigh_Critical | critical | [Link](#lck-es-004) |
| 5 | LCK-ES-005 | ESDiskLow_Warning | warning | [Link](#lck-es-005) |
| 6 | LCK-ES-006 | ESDiskLow_Critical | critical | [Link](#lck-es-006) |

---

## Environment Reference / 环境参考

| Resource | Identifier | Purpose |
|----------|-----------|---------|
| Prometheus (primary) | `df8o21agxtkw0d` (UMBQuerier-Luckin) | ES metrics via elasticsearch_exporter |
| Prometheus (general) | `ff7hkeec6c9a8e` (prometheus) | General infrastructure metrics |
| VMAlert (Basic) | `10.238.3.153:8880` | Infrastructure alert evaluation |
| AWS Account | `257394478466` | Production |
| AWS Region | `us-east-1` | Primary |
| ES Dashboard | `https://grafana.luckinus.com/d/es-cluster` | Cluster health |
| ES Node Dashboard | `https://grafana.luckinus.com/d/es-nodes` | Per-node metrics |
| ES Storage Dashboard | `https://grafana.luckinus.com/d/es-storage` | Disk/storage metrics |

---

<a id="lck-es-001"></a>
## LCK-ES-001 -- ESClusterYellow_Warning

### Metadata / 元数据

```yaml
alert_id: "LCK-ES-001"
alert_name: "ESClusterYellow_Warning"
severity: "warning"
tier: "2"
category: "db-es"
team: "dba"
first_responder: "US DBA"
sla_response: "Tier 2: 15min"
old_ids_replaced: "ALR-037"
action: "KEEP"
skill_reference: "/app/skills/es-alert-investigation.md"
last_updated: "2026-02-16"
```

### Alert Rule / 告警规则

```yaml
# Source: alert-rules-complete.yml — group: lck-na.alerts.db-es
alert: EsClusterYellowWarning
expr: |
  elasticsearch_cluster_health_status{color="yellow", env="production"} == 1
for: 5m
labels:
  severity: "warning"
  tier: "2"
  team: "dba"
  category: "db-es"
  service: "elasticsearch"
annotations:
  summary: "[LCK-NA-DB-ES] ClusterYellow_Warning - {{ $labels.instance }}"
  impact: "ES cluster degraded; replica shards unassigned, reduced redundancy."
  notification_channel: "wecom+twilio-lead"
```

**What this means / 含义:**
The Elasticsearch cluster health has been YELLOW for 5 minutes. Yellow means all primary shards are assigned but one or more replica shards are unassigned. Data is available but redundancy is reduced -- if a node fails, data loss may occur.

Elasticsearch 集群健康状态持续 YELLOW 5分钟。Yellow 表示所有主分片已分配，但一个或多个副本分片未分配。数据仍可用，但冗余降低 -- 如果节点故障，可能导致数据丢失。

---

### 1. ASSESS / 评估 (First 2 Minutes / 前2分钟)

**Golden Path Impact / 黄金路径影响:**
ES supports menu search and order history lookup. Yellow status means searches still work but with reduced fault tolerance.
ES 支持菜单搜索和订单历史查询。Yellow 状态意味着搜索仍然可用，但容错能力降低。

```bash
# Check cluster health status / 检查集群健康状态
curl -s "http://ES_ENDPOINT:9200/_cluster/health" | \
  jq '{status, number_of_nodes, active_primary_shards, active_shards, unassigned_shards, relocating_shards}'

# Check which shards are unassigned / 检查哪些分片未分配
curl -s "http://ES_ENDPOINT:9200/_cat/shards?v&h=index,shard,prirep,state,unassigned.reason" | \
  grep UNASSIGNED

# Verify via Prometheus / 通过 Prometheus 验证
# Datasource: df8o21agxtkw0d
# PromQL: elasticsearch_cluster_health_status{color="yellow", env="production"}
```

**Severity Classification / 严重性分类:**

| Condition / 条件 | Severity / 严重性 | Action / 操作 |
|-----------|----------|--------|
| Yellow but searches working / Yellow但搜索正常 | Warning -> Tier 2 | US DBA investigates / US DBA 调查 |
| Yellow + node down / Yellow+节点宕机 | Escalate to Critical | Treat as potential Red / 按潜在Red处理 |

---

### 2. ACKNOWLEDGE / 确认 (Within 15min SLA / 15分钟SLA内)

```bash
# Silence alert for 30 minutes during investigation
# 调查期间静默告警30分钟
amtool silence add \
  alertname="EsClusterYellowWarning" \
  service="elasticsearch" \
  --duration="30m" \
  --comment="Investigating yellow cluster - YOUR_NAME" \
  --author="YOUR_NAME"
```

Post to WeCom / 发送至企业微信:
```
Alert Acknowledged / 告警已确认
Alert: ESClusterYellow_Warning (LCK-ES-001)
Severity: warning | Tier: 2
Owner: {your_name}
Status: Investigating / 调查中
ETA for update: {time + 15min}
```

---

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
```
[ ] Node recently restarted and replicas haven't finished recovery
    节点最近重启，副本尚未完成恢复
[ ] Node removed from cluster (maintenance, failure)
    节点从集群中移除（维护、故障）
[ ] Disk watermark hit on a node, preventing replica allocation
    节点磁盘水位线触发，阻止副本分配
[ ] Insufficient nodes for replica count (replicas=1 needs 2+ nodes)
    节点数不足（replicas=1 需要 2+ 个节点）
[ ] Shard allocation manually disabled
    分片分配被手动禁用
```

```bash
# Why are shards unassigned? / 分片为何未分配？
curl -s "http://ES_ENDPOINT:9200/_cluster/allocation/explain?pretty" | \
  jq '{index: .index, shard: .shard, primary: .primary, current_state: .current_state, unassigned_info}'

# Check node status / 检查节点状态
curl -s "http://ES_ENDPOINT:9200/_cat/nodes?v&h=name,ip,heap.percent,ram.percent,cpu,load_1m,node.role,master"

# Check allocation settings / 检查分配设置
curl -s "http://ES_ENDPOINT:9200/_cluster/settings?flat_keys=true" | \
  jq '.transient | to_entries[] | select(.key | contains("allocation"))'

# Check disk watermarks on all nodes / 检查所有节点磁盘水位线
curl -s "http://ES_ENDPOINT:9200/_cat/allocation?v&h=shards,disk.indices,disk.used,disk.avail,disk.total,disk.percent,node"
```

---

### 4. ACT / 执行

**Tier 2 Authority / Tier 2 权限:** US DBA can restart allocation, adjust settings. No approval needed.
US DBA 可重启分配、调整设置。无需审批。

```bash
# If allocation was disabled, re-enable it / 如果分配被禁用，重新启用
curl -X PUT "http://ES_ENDPOINT:9200/_cluster/settings" -H 'Content-Type: application/json' -d '{
  "transient": {
    "cluster.routing.allocation.enable": "all"
  }
}'

# Force retry shard allocation / 强制重试分片分配
curl -X POST "http://ES_ENDPOINT:9200/_cluster/reroute?retry_failed=true"

# If a specific node is excluded, remove the exclusion / 如果特定节点被排除，移除排除规则
curl -X PUT "http://ES_ENDPOINT:9200/_cluster/settings" -H 'Content-Type: application/json' -d '{
  "transient": {
    "cluster.routing.allocation.exclude._name": ""
  }
}'
```

**Escalation / 升级:**
If yellow persists >30 minutes after remediation, escalate to Tier 3 (LCK-ES-002 may fire).
如果修复后 Yellow 持续超过30分钟，升级至 Tier 3（LCK-ES-002 可能触发）。

---

### 5. AFTERMATH / 后续

- Update common causes if root cause was new / 如果根因是新的，更新常见原因列表
- Review whether replica count is appropriate for cluster size / 审查副本数是否适合集群规模
- Check if ILM policies are correctly managing old indices / 检查 ILM 策略是否正确管理旧索引
- Verify monitoring covers all ES nodes / 验证监控覆盖所有ES节点

---

<a id="lck-es-002"></a>
## LCK-ES-002 -- ESClusterRed_Critical

### Metadata / 元数据

```yaml
alert_id: "LCK-ES-002"
alert_name: "ESClusterRed_Critical"
severity: "critical"
tier: "3"
category: "db-es"
team: "dba"
first_responder: "US DBA + China HQ"
sla_response: "Tier 3: 5min"
old_ids_replaced: "ALR-035, ALR-036"
action: "MERGE"
skill_reference: "/app/skills/es-alert-investigation.md"
last_updated: "2026-02-16"
```

### Alert Rule / 告警规则

```yaml
# Source: alert-rules-complete.yml — group: lck-na.alerts.db-es
alert: EsClusterRedCritical
expr: |
  elasticsearch_cluster_health_status{color="red", env="production"} == 1
for: 0m
labels:
  severity: "critical"
  tier: "1"
  team: "dba"
  category: "db-es"
  service: "elasticsearch"
annotations:
  summary: "[LCK-NA-DB-ES] ClusterRed_Critical - {{ $labels.instance }}"
  impact: "ES cluster RED; primary shards missing, data loss risk, search/index failing."
  notification_channel: "wecom+twilio-all"
```

**What this means / 含义:**
The Elasticsearch cluster is RED -- this fires **immediately** (for: 0m). RED means one or more primary shards are unassigned. Data is **actively missing or inaccessible**. Searches return incomplete results, indexing to affected indices fails. This is a data loss scenario.

Elasticsearch 集群状态为 RED -- **立即触发**（for: 0m）。RED 表示一个或多个主分片未分配。数据**正在丢失或不可访问**。搜索返回不完整结果，受影响索引的写入失败。这是数据丢失场景。

---

### 1. ASSESS / 评估 (First 2 Minutes / 前2分钟)

**Golden Path Impact / 黄金路径影响:**
**HIGH IMPACT.** Menu search and order lookups may fail or return incomplete results. Customer ordering flow is degraded.
**高影响。** 菜单搜索和订单查询可能失败或返回不完整结果。客户下单流程受损。

```bash
# Immediate cluster health / 立即检查集群健康
curl -s "http://ES_ENDPOINT:9200/_cluster/health" | \
  jq '{status, number_of_nodes, active_primary_shards, unassigned_shards, initializing_shards}'

# Which indices are RED? / 哪些索引是RED？
curl -s "http://ES_ENDPOINT:9200/_cat/indices?v&health=red&h=health,index,pri,rep,docs.count,store.size"

# Which primary shards are unassigned? / 哪些主分片未分配？
curl -s "http://ES_ENDPOINT:9200/_cat/shards?v&h=index,shard,prirep,state,unassigned.reason" | \
  grep -E "UNASSIGNED.*p"

# Node count — did we lose a node? / 节点数 -- 是否丢失节点？
curl -s "http://ES_ENDPOINT:9200/_cat/nodes?v&h=name,ip,heap.percent,ram.percent,cpu,node.role,master"
```

---

### 2. ACKNOWLEDGE / 确认 (Within 5min SLA / 5分钟SLA内)

```bash
# Silence for 15 minutes — short duration for critical
# 静默15分钟 -- 关键告警短时间
amtool silence add \
  alertname="EsClusterRedCritical" \
  service="elasticsearch" \
  --duration="15m" \
  --comment="CRITICAL: Investigating red cluster - YOUR_NAME" \
  --author="YOUR_NAME"
```

Post to WeCom Critical Channel / 发送至企业微信关键频道:
```
CRITICAL Alert Acknowledged / 关键告警已确认
Alert: ESClusterRed_Critical (LCK-ES-002)
Severity: CRITICAL | Tier: 3
Owner: {your_name}
Status: ACTIVELY INVESTIGATING / 正在紧急调查
China HQ notified: YES / 中国总部已通知: 是
ETA for update: {time + 15min}
```

**Notify immediately / 立即通知:** China HQ DBA + China HQ Engineering via WeCom + Twilio.

---

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
```
[ ] Node failure — data node holding primary shards went down
    节点故障 -- 持有主分片的数据节点宕机
[ ] Disk full — flood-stage watermark triggered read-only, then node crashed
    磁盘满 -- 洪水线水位线触发只读，随后节点崩溃
[ ] JVM heap OOM — node killed by OS OOM killer
    JVM堆内存溢出 -- 节点被操作系统OOM killer终止
[ ] Network partition — master cannot see data nodes
    网络分区 -- 主节点无法看到数据节点
[ ] Corrupted shard — primary shard data corrupted on disk
    分片损坏 -- 主分片磁盘数据损坏
```

```bash
# Why are primary shards unassigned? / 主分片为何未分配？
curl -s "http://ES_ENDPOINT:9200/_cluster/allocation/explain?pretty"

# Check node JVM heap / 检查节点JVM堆
curl -s "http://ES_ENDPOINT:9200/_nodes/stats/jvm" | \
  jq '.nodes | to_entries[] | {name: .value.name, heap_percent: .value.jvm.mem.heap_used_percent, heap_max: .value.jvm.mem.heap_max_in_bytes}'

# Check cluster events/tasks / 检查集群事件/任务
curl -s "http://ES_ENDPOINT:9200/_cat/pending_tasks?v"

# Check for recent node departures in cluster logs / 检查集群日志中最近的节点离开记录
curl -s "http://ES_ENDPOINT:9200/_cat/nodes?v&h=name,ip,node.role,master" | wc -l
# Compare to expected node count
```

---

### 4. ACT / 执行

**Tier 3 Authority / Tier 3 权限:** US DBA + China HQ Engineering. Emergency actions authorized.
US DBA + 中国总部工程团队。紧急操作已授权。

```bash
# STEP 1: Try rerouting unassigned primaries / 步骤1：尝试重新路由未分配的主分片
curl -X POST "http://ES_ENDPOINT:9200/_cluster/reroute?retry_failed=true"

# STEP 2: If a node is down and won't come back, allocate stale primary
# 步骤2：如果节点宕机且无法恢复，分配陈旧的主分片
# WARNING: This may cause data loss for writes since last flush
# 警告：这可能导致自上次刷新以来的写入数据丢失
curl -X POST "http://ES_ENDPOINT:9200/_cluster/reroute" -H 'Content-Type: application/json' -d '{
  "commands": [{
    "allocate_stale_primary": {
      "index": "INDEX_NAME",
      "shard": SHARD_NUMBER,
      "node": "TARGET_NODE_NAME",
      "accept_data_loss": true
    }
  }]
}'

# STEP 3: If data is lost, restore from snapshot / 步骤3：如果数据丢失，从快照恢复
# List available snapshots / 列出可用快照
curl -s "http://ES_ENDPOINT:9200/_snapshot/REPO_NAME/_all" | \
  jq '.snapshots[] | {snapshot: .snapshot, state: .state, start_time: .start_time}' | tail -5

# Restore a specific index / 恢复特定索引
curl -X POST "http://ES_ENDPOINT:9200/_snapshot/REPO_NAME/SNAPSHOT_NAME/_restore" \
  -H 'Content-Type: application/json' -d '{
  "indices": "INDEX_NAME",
  "ignore_unavailable": true,
  "include_global_state": false
}'
```

**Escalation / 升级:**
If cluster remains RED after 15 minutes, engage AWS Support (Premium). Contact path: China HQ -> AWS TAM.
如果集群在15分钟后仍为RED，联系AWS支持（高级）。联系路径：中国总部 -> AWS TAM。

---

### 5. AFTERMATH / 后续

- **Mandatory post-incident report** for all Tier 3 events / 所有 Tier 3 事件强制要求事后报告
- Verify all primary shards are assigned and data is complete / 验证所有主分片已分配且数据完整
- Review snapshot schedule -- ensure daily snapshots are running / 审查快照计划 -- 确保每日快照运行中
- Audit node hardware health (disk SMART, memory ECC errors) / 审计节点硬件健康（磁盘SMART、内存ECC错误）
- Consider increasing replica count if single-node failure caused RED / 如果单节点故障导致RED，考虑增加副本数

---

<a id="lck-es-003"></a>
## LCK-ES-003 -- ESCpuHigh_Warning

### Metadata / 元数据

```yaml
alert_id: "LCK-ES-003"
alert_name: "ESCpuHigh_Warning"
severity: "warning"
tier: "2"
category: "db-es"
team: "dba"
first_responder: "US DBA"
sla_response: "Tier 2: 15min"
old_ids_replaced: "ALR-033"
action: "KEEP"
skill_reference: "/app/skills/es-alert-investigation.md"
last_updated: "2026-02-16"
```

### Alert Rule / 告警规则

```yaml
# Source: alert-rules-complete.yml — group: lck-na.alerts.db-es
alert: EsNodeCpuWarning
expr: |
  elasticsearch_os_cpu_percent{env="production"} > 75
  and
  elasticsearch_os_cpu_percent{env="production"} <= 85
for: 5m
labels:
  severity: "warning"
  tier: "2"
  team: "dba"
  category: "db-es"
  service: "elasticsearch"
annotations:
  summary: "[LCK-NA-DB-ES] NodeCpu_Warning - {{ $labels.instance }}"
  impact: "ES node CPU high; query and indexing performance degrading."
  notification_channel: "wecom+twilio-lead"
```

**What this means / 含义:**
An Elasticsearch node's CPU has been between 75% and 85% for 5 minutes. Query latency is likely increasing and indexing throughput is degrading. Not yet critical, but the node is under significant load.

Elasticsearch 节点的 CPU 在 75% 到 85% 之间持续5分钟。查询延迟可能增加，索引吞吐量下降。尚未达到关键水平，但节点承受较大负载。

---

### 1. ASSESS / 评估 (First 2 Minutes / 前2分钟)

```bash
# Check CPU per node / 检查每个节点的CPU
curl -s "http://ES_ENDPOINT:9200/_cat/nodes?v&h=name,ip,cpu,load_1m,load_5m,load_15m,node.role"

# Verify via Prometheus / 通过 Prometheus 验证
# Datasource: df8o21agxtkw0d
# PromQL: elasticsearch_os_cpu_percent{env="production"}

# Check if it's a single node or cluster-wide / 检查是单节点还是集群范围
curl -s "http://ES_ENDPOINT:9200/_nodes/stats/os" | \
  jq '.nodes | to_entries[] | {name: .value.name, cpu_percent: .value.os.cpu.percent}'
```

**Severity Classification / 严重性分类:**

| Condition / 条件 | Severity / 严重性 | Action / 操作 |
|-----------|----------|--------|
| Single node 75-85% / 单节点 75-85% | Warning -> Tier 2 | Investigate query/indexing load / 调查查询/索引负载 |
| Multiple nodes 75-85% / 多节点 75-85% | Warning -> Tier 2 | May need scaling / 可能需要扩容 |

---

### 2. ACKNOWLEDGE / 确认 (Within 15min SLA / 15分钟SLA内)

```bash
amtool silence add \
  alertname="EsNodeCpuWarning" \
  service="elasticsearch" \
  --duration="30m" \
  --comment="Investigating ES CPU warning - YOUR_NAME" \
  --author="YOUR_NAME"
```

---

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
```
[ ] Heavy search queries (aggregations, wildcards, regex)
    繁重的搜索查询（聚合、通配符、正则表达式）
[ ] Bulk indexing spike
    批量索引高峰
[ ] Segment merge storm (too many small segments)
    段合并风暴（过多小段）
[ ] GC pressure causing CPU spikes
    GC压力导致CPU飙升
[ ] Expensive script-based queries (Painless scripts)
    昂贵的脚本查询（Painless脚本）
```

```bash
# Check hot threads — what is consuming CPU / 检查热线程 -- 什么在消耗CPU
curl -s "http://ES_ENDPOINT:9200/_nodes/hot_threads?threads=5&type=cpu"

# Check active tasks / 检查活动任务
curl -s "http://ES_ENDPOINT:9200/_tasks?actions=*search*&detailed&group_by=parents" | \
  jq '.tasks | to_entries | length'

curl -s "http://ES_ENDPOINT:9200/_tasks?actions=*bulk*&detailed&group_by=parents" | \
  jq '.tasks | to_entries | length'

# Check indexing rate / 检查索引速率
curl -s "http://ES_ENDPOINT:9200/_cat/nodes?v&h=name,indexing.index_total,indexing.index_current,search.query_total,search.query_current"

# Check JVM GC stats / 检查JVM GC统计
curl -s "http://ES_ENDPOINT:9200/_nodes/stats/jvm" | \
  jq '.nodes | to_entries[] | {name: .value.name, gc_old_count: .value.jvm.gc.collectors.old.collection_count, gc_old_time_ms: .value.jvm.gc.collectors.old.collection_time_in_millis}'
```

---

### 4. ACT / 执行

**Tier 2 Authority / Tier 2 权限:** US DBA can throttle indexing, cancel queries, adjust settings.

```bash
# Throttle indexing on the hot node / 限制热节点上的索引速率
curl -X PUT "http://ES_ENDPOINT:9200/_cluster/settings" -H 'Content-Type: application/json' -d '{
  "transient": {
    "indices.store.throttle.max_bytes_per_sec": "20mb"
  }
}'

# Cancel long-running search tasks / 取消长时间运行的搜索任务
# First list tasks / 首先列出任务
curl -s "http://ES_ENDPOINT:9200/_tasks?actions=*search*&detailed" | \
  jq '.tasks | to_entries[] | {task_id: .key, running_time: .value.running_time_in_nanos, description: .value.description}'

# Cancel a specific task / 取消特定任务
curl -X POST "http://ES_ENDPOINT:9200/_tasks/TASK_ID/_cancel"

# If segment merges are the cause, reduce max merge threads / 如果段合并是原因，减少最大合并线程
curl -X PUT "http://ES_ENDPOINT:9200/_settings" -H 'Content-Type: application/json' -d '{
  "index.merge.scheduler.max_thread_count": 1
}'
```

---

### 5. AFTERMATH / 后续

- Identify the query or indexing pattern that caused the spike / 识别导致飙升的查询或索引模式
- Review index settings (refresh_interval, number_of_replicas) / 审查索引设置（刷新间隔、副本数）
- Consider adding data nodes if load is consistently high / 如果负载持续偏高，考虑添加数据节点
- Review slow query log settings / 审查慢查询日志设置

---

<a id="lck-es-004"></a>
## LCK-ES-004 -- ESCpuHigh_Critical

### Metadata / 元数据

```yaml
alert_id: "LCK-ES-004"
alert_name: "ESCpuHigh_Critical"
severity: "critical"
tier: "3"
category: "db-es"
team: "dba"
first_responder: "US DBA + China HQ"
sla_response: "Tier 3: 5min"
old_ids_replaced: "ALR-033, ALR-034"
action: "MERGE"
skill_reference: "/app/skills/es-alert-investigation.md"
last_updated: "2026-02-16"
```

### Alert Rule / 告警规则

```yaml
# Source: alert-rules-complete.yml — group: lck-na.alerts.db-es
alert: EsNodeCpuCritical
expr: |
  elasticsearch_os_cpu_percent{env="production"} > 85
for: 3m
labels:
  severity: "critical"
  tier: "1"
  team: "dba"
  category: "db-es"
  service: "elasticsearch"
annotations:
  summary: "[LCK-NA-DB-ES] NodeCpu_Critical - {{ $labels.instance }}"
  impact: "ES node CPU critical; node may become unresponsive, cluster instability."
  notification_channel: "wecom+twilio-all"
```

**What this means / 含义:**
An Elasticsearch node's CPU has exceeded 85% for 3 minutes. The node may become unresponsive, causing the master to mark it as failed. If this is a data node, shards will be relocated, adding further cluster stress. If it is the master node, the cluster may lose coordination.

Elasticsearch 节点的 CPU 超过 85% 持续3分钟。节点可能变得无响应，导致主节点将其标记为故障。如果是数据节点，分片将被重新分配，增加集群压力。如果是主节点，集群可能失去协调。

---

### 1. ASSESS / 评估 (First 2 Minutes / 前2分钟)

```bash
# Immediate: which node(s) are critical? / 立即：哪些节点达到关键水平？
curl -s "http://ES_ENDPOINT:9200/_cat/nodes?v&h=name,ip,cpu,load_1m,heap.percent,node.role,master" | \
  sort -t' ' -k3 -rn

# Is it the master node? / 是否是主节点？
curl -s "http://ES_ENDPOINT:9200/_cat/master?v"

# PromQL verification / PromQL 验证
# elasticsearch_os_cpu_percent{env="production"} > 85
```

**Golden Path Impact / 黄金路径影响:**
**HIGH RISK.** If the overloaded node becomes unresponsive, cluster may degrade to YELLOW or RED, directly impacting search and order lookups.
**高风险。** 如果过载节点无响应，集群可能降级为YELLOW或RED，直接影响搜索和订单查询。

---

### 2. ACKNOWLEDGE / 确认 (Within 5min SLA / 5分钟SLA内)

```bash
amtool silence add \
  alertname="EsNodeCpuCritical" \
  service="elasticsearch" \
  --duration="15m" \
  --comment="CRITICAL: ES CPU >85% - YOUR_NAME" \
  --author="YOUR_NAME"
```

**Notify immediately / 立即通知:** China HQ DBA + China HQ Engineering via WeCom + Twilio (wecom+twilio-all).

---

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
```
[ ] Runaway query — complex aggregation or wildcard search
    失控查询 -- 复杂聚合或通配符搜索
[ ] Bulk indexing storm from application
    应用程序批量索引风暴
[ ] JVM GC death spiral — full GC consuming all CPU
    JVM GC 死循环 -- 完整GC消耗所有CPU
[ ] Segment merge on large index (force merge triggered)
    大索引上的段合并（强制合并触发）
[ ] Noisy neighbor — another process on same EC2 instance
    噪声邻居 -- 同一EC2实例上的其他进程
```

```bash
# Hot threads — top priority / 热线程 -- 最高优先级
curl -s "http://ES_ENDPOINT:9200/_nodes/hot_threads?threads=5&type=cpu&interval=1s"

# Check all running tasks / 检查所有运行中的任务
curl -s "http://ES_ENDPOINT:9200/_tasks?detailed&group_by=parents" | \
  jq '[.tasks | to_entries[] | {id: .key, action: .value.action, running_time_ns: .value.running_time_in_nanos, node: .value.node}] | sort_by(.running_time_ns) | reverse | .[0:10]'

# JVM heap and GC / JVM堆和GC
curl -s "http://ES_ENDPOINT:9200/_nodes/stats/jvm" | \
  jq '.nodes | to_entries[] | {name: .value.name, heap_percent: .value.jvm.mem.heap_used_percent, old_gc_count: .value.jvm.gc.collectors.old.collection_count}'

# Check OS-level CPU on the EC2 instance (if SSH access available)
# 检查EC2实例的操作系统级CPU（如果有SSH访问权限）
# ssh NODE_IP "top -bn1 | head -20"
```

---

### 4. ACT / 执行

**Tier 3 Authority / Tier 3 权限:** US DBA + China HQ. Emergency actions including node exclusion and scaling authorized.

```bash
# STEP 1: Cancel ALL heavy tasks on the affected node / 步骤1：取消受影响节点上的所有繁重任务
# Get node ID first / 首先获取节点ID
NODE_ID=$(curl -s "http://ES_ENDPOINT:9200/_cat/nodes?h=id,name,cpu" | sort -t' ' -k3 -rn | head -1 | awk '{print $1}')

# Cancel all tasks on that node / 取消该节点上的所有任务
for TASK_ID in $(curl -s "http://ES_ENDPOINT:9200/_tasks?nodes=$NODE_ID&detailed" | jq -r '.tasks | keys[]'); do
  curl -X POST "http://ES_ENDPOINT:9200/_tasks/$TASK_ID/_cancel"
done

# STEP 2: Exclude the hot node from new shard allocations / 步骤2：将热节点排除在新分片分配之外
curl -X PUT "http://ES_ENDPOINT:9200/_cluster/settings" -H 'Content-Type: application/json' -d '{
  "transient": {
    "cluster.routing.allocation.exclude._name": "HOT_NODE_NAME"
  }
}'

# STEP 3: If CPU doesn't drop, consider adding a new data node (Emergency)
# 步骤3：如果CPU不下降，考虑添加新数据节点（紧急）
# Launch new EC2 instance from ES AMI / 从ES AMI启动新EC2实例
# aws ec2 run-instances --image-id ami-ESNODE --instance-type r6g.xlarge \
#   --subnet-id subnet-XXXX --security-group-ids sg-XXXX \
#   --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=es-emergency-node}]' \
#   --region us-east-1

# STEP 4: After CPU stabilizes, remove the exclusion / 步骤4：CPU稳定后，移除排除规则
# curl -X PUT "http://ES_ENDPOINT:9200/_cluster/settings" -H 'Content-Type: application/json' -d '{
#   "transient": {
#     "cluster.routing.allocation.exclude._name": ""
#   }
# }'
```

---

### 5. AFTERMATH / 后续

- **Mandatory post-incident report** / 强制事后报告
- Identify and optimize the query/indexing pattern that caused CPU spike / 识别并优化导致CPU飙升的查询/索引模式
- Review node sizing — if consistently >70% CPU, cluster needs horizontal scaling / 审查节点大小 -- 如果持续>70% CPU，集群需要水平扩展
- Implement search slow log to catch expensive queries proactively / 实施搜索慢日志，主动捕获昂贵查询
- Consider circuit breaker settings to reject oversized queries / 考虑熔断器设置以拒绝超大查询

---

<a id="lck-es-005"></a>
## LCK-ES-005 -- ESDiskLow_Warning

### Metadata / 元数据

```yaml
alert_id: "LCK-ES-005"
alert_name: "ESDiskLow_Warning"
severity: "warning"
tier: "2"
category: "db-es"
team: "dba"
first_responder: "US DBA"
sla_response: "Tier 2: 15min"
old_ids_replaced: "ALR-038"
action: "KEEP"
skill_reference: "/app/skills/es-alert-investigation.md"
last_updated: "2026-02-16"
```

### Alert Rule / 告警规则

```yaml
# Source: alert-rules-complete.yml — group: lck-na.alerts.db-es
alert: EsNodeDiskWarning
expr: |
  (1 - elasticsearch_filesystem_data_available_bytes{env="production"}
  / elasticsearch_filesystem_data_size_bytes{env="production"}) * 100 > 85
  and
  (1 - elasticsearch_filesystem_data_available_bytes{env="production"}
  / elasticsearch_filesystem_data_size_bytes{env="production"}) * 100 <= 90
for: 5m
labels:
  severity: "warning"
  tier: "2"
  team: "dba"
  category: "db-es"
  service: "elasticsearch"
annotations:
  summary: "[LCK-NA-DB-ES] NodeDisk_Warning - {{ $labels.instance }}"
  impact: "ES disk filling; watermark triggers may block index allocation."
  notification_channel: "wecom+twilio-lead"
```

**What this means / 含义:**
An Elasticsearch node's disk usage is between 85% and 90% and has been for 5 minutes. This has reached the **low watermark** (85%). ES will stop allocating new shards to this node. If disk continues to fill, the high watermark (90%) will trigger shard relocation away from this node.

Elasticsearch 节点的磁盘使用率在 85% 到 90% 之间持续5分钟。已达到**低水位线**（85%）。ES 将停止向此节点分配新分片。如果磁盘继续增长，高水位线（90%）将触发分片从此节点迁移。

**ES Disk Watermark Reference / ES磁盘水位线参考:**

| Watermark / 水位线 | Default / 默认值 | Effect / 影响 |
|-----------|---------|--------|
| Low / 低 | 85% | No new shard allocation to node / 不再向节点分配新分片 |
| High / 高 | 90% | Shards relocated away from node / 分片从节点迁移 |
| Flood-stage / 洪水线 | 95% | Index set to read-only / 索引设为只读 |

---

### 1. ASSESS / 评估 (First 2 Minutes / 前2分钟)

```bash
# Check disk usage per node / 检查每个节点的磁盘使用
curl -s "http://ES_ENDPOINT:9200/_cat/allocation?v&h=shards,disk.indices,disk.used,disk.avail,disk.total,disk.percent,node"

# Which indices are largest? / 哪些索引最大？
curl -s "http://ES_ENDPOINT:9200/_cat/indices?v&s=store.size:desc&h=index,docs.count,store.size,pri.store.size" | head -20

# PromQL verification / PromQL 验证
# (1 - elasticsearch_filesystem_data_available_bytes{env="production"} / elasticsearch_filesystem_data_size_bytes{env="production"}) * 100
```

---

### 2. ACKNOWLEDGE / 确认 (Within 15min SLA / 15分钟SLA内)

```bash
amtool silence add \
  alertname="EsNodeDiskWarning" \
  service="elasticsearch" \
  --duration="30m" \
  --comment="Investigating ES disk warning - YOUR_NAME" \
  --author="YOUR_NAME"
```

---

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
```
[ ] ILM policy not rotating/deleting old indices
    ILM策略未轮换/删除旧索引
[ ] Unexpected index growth (logging storm, large bulk imports)
    意外的索引增长（日志风暴、大量批量导入）
[ ] Snapshot repository consuming local disk
    快照仓库消耗本地磁盘
[ ] Unbalanced shard distribution (hot node has too many shards)
    分片分布不均（热节点分片过多）
[ ] Too many replicas for cluster size
    集群规模下副本数过多
```

```bash
# Check ILM policy status / 检查ILM策略状态
curl -s "http://ES_ENDPOINT:9200/_ilm/policy" | jq 'keys'

# Check ILM errors / 检查ILM错误
curl -s "http://ES_ENDPOINT:9200/_all/_ilm/explain" | \
  jq '[.indices | to_entries[] | select(.value.step == "ERROR")] | length'

# Check index creation dates — identify indices that should have been deleted
# 检查索引创建日期 -- 识别应已删除的索引
curl -s "http://ES_ENDPOINT:9200/_cat/indices?v&h=index,creation.date.string,store.size&s=creation.date.string:asc" | head -20

# Check segment sizes — are there unmerged segments consuming extra space?
# 检查段大小 -- 是否有未合并的段消耗额外空间？
curl -s "http://ES_ENDPOINT:9200/_cat/segments?v&h=index,shard,segment,size,docs.count&s=size:desc" | head -20
```

---

### 4. ACT / 执行

**Tier 2 Authority / Tier 2 权限:** US DBA can delete old indices, adjust ILM, reduce replicas.

```bash
# OPTION 1: Delete old/expired indices / 选项1：删除旧的/过期的索引
# List indices older than 30 days (adjust as needed)
# 列出超过30天的索引（根据需要调整）
curl -s "http://ES_ENDPOINT:9200/_cat/indices?v&h=index,creation.date.string,store.size&s=creation.date.string:asc" | head -20

# Delete a specific old index / 删除特定的旧索引
curl -X DELETE "http://ES_ENDPOINT:9200/INDEX_NAME_OLD"

# OPTION 2: Reduce replica count for large indices / 选项2：减少大索引的副本数
curl -X PUT "http://ES_ENDPOINT:9200/INDEX_NAME/_settings" -H 'Content-Type: application/json' -d '{
  "index": {
    "number_of_replicas": 0
  }
}'

# OPTION 3: Force merge to reclaim space from deleted documents
# 选项3：强制合并以回收已删除文档的空间
# WARNING: CPU-intensive, do during low-traffic period
# 警告：CPU密集型，在低流量时段执行
curl -X POST "http://ES_ENDPOINT:9200/INDEX_NAME/_forcemerge?max_num_segments=1"

# OPTION 4: Fix ILM policy / 选项4：修复ILM策略
# Retry failed ILM steps / 重试失败的ILM步骤
curl -X POST "http://ES_ENDPOINT:9200/INDEX_NAME/_ilm/retry"
```

---

### 5. AFTERMATH / 后续

- Verify ILM policies are correctly configured and running / 验证ILM策略配置正确且运行中
- Set up disk growth alerts at lower thresholds (e.g., 75%) / 在更低阈值设置磁盘增长告警（如75%）
- Document expected index retention periods per index pattern / 记录每个索引模式的预期保留期
- Review whether disk size needs to be increased permanently / 审查是否需要永久增加磁盘大小

---

<a id="lck-es-006"></a>
## LCK-ES-006 -- ESDiskLow_Critical

### Metadata / 元数据

```yaml
alert_id: "LCK-ES-006"
alert_name: "ESDiskLow_Critical"
severity: "critical"
tier: "3"
category: "db-es"
team: "dba"
first_responder: "US DBA + China HQ"
sla_response: "Tier 3: 5min"
old_ids_replaced: "ALR-038, ALR-039"
action: "MERGE"
skill_reference: "/app/skills/es-alert-investigation.md"
last_updated: "2026-02-16"
```

### Alert Rule / 告警规则

```yaml
# Source: alert-rules-complete.yml — group: lck-na.alerts.db-es
alert: EsNodeDiskCritical
expr: |
  (1 - elasticsearch_filesystem_data_available_bytes{env="production"}
  / elasticsearch_filesystem_data_size_bytes{env="production"}) * 100 > 90
for: 3m
labels:
  severity: "critical"
  tier: "1"
  team: "dba"
  category: "db-es"
  service: "elasticsearch"
annotations:
  summary: "[LCK-NA-DB-ES] NodeDisk_Critical - {{ $labels.instance }}"
  impact: "ES disk critical; flood-stage watermark may trigger read-only indices."
  notification_channel: "wecom+twilio-all"
```

**What this means / 含义:**
An Elasticsearch node's disk usage has exceeded 90% for 3 minutes. This has reached the **high watermark**. ES is actively relocating shards away from this node. If usage reaches 95% (flood-stage), **all indices with shards on this node will be set to read-only**, blocking all writes. This is only 5% away from a write outage.

Elasticsearch 节点的磁盘使用率超过 90% 持续3分钟。已达到**高水位线**。ES 正在将分片从此节点迁移。如果使用率达到 95%（洪水线），**此节点上所有有分片的索引将被设为只读**，阻止所有写入。距离写入中断仅差5%。

---

### 1. ASSESS / 评估 (First 2 Minutes / 前2分钟)

**Golden Path Impact / 黄金路径影响:**
**HIGH RISK.** At 95%, indices go read-only. This means new orders, events, and logs cannot be indexed. Search works but data freshness stops.
**高风险。** 在95%时，索引变为只读。这意味着新订单、事件和日志无法索引。搜索可用但数据不再更新。

```bash
# Immediate disk status / 立即查看磁盘状态
curl -s "http://ES_ENDPOINT:9200/_cat/allocation?v&h=shards,disk.used,disk.avail,disk.total,disk.percent,node" | sort -t' ' -k5 -rn

# Are any indices already read-only? / 是否有索引已经只读？
curl -s "http://ES_ENDPOINT:9200/_all/_settings" | \
  jq '[to_entries[] | select(.value.settings.index.blocks.read_only_allow_delete == "true") | .key]'

# How much space can we reclaim immediately? / 我们可以立即回收多少空间？
curl -s "http://ES_ENDPOINT:9200/_cat/indices?v&s=store.size:desc&h=index,store.size,docs.count,docs.deleted,creation.date.string" | head -20
```

---

### 2. ACKNOWLEDGE / 确认 (Within 5min SLA / 5分钟SLA内)

```bash
amtool silence add \
  alertname="EsNodeDiskCritical" \
  service="elasticsearch" \
  --duration="15m" \
  --comment="CRITICAL: ES disk >90% - YOUR_NAME" \
  --author="YOUR_NAME"
```

**Notify immediately / 立即通知:** China HQ DBA + China HQ Engineering via WeCom + Twilio.

Post to WeCom Critical Channel / 发送至企业微信关键频道:
```
CRITICAL Alert / 关键告警
Alert: ESDiskLow_Critical (LCK-ES-006)
Severity: CRITICAL | Tier: 3
Disk Usage: >90% — FLOOD-STAGE (95%) IMMINENT
Node: {node_name}
Owner: {your_name}
Status: EMERGENCY REMEDIATION IN PROGRESS / 紧急修复进行中
```

---

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
```
[ ] ILM policy stuck or misconfigured — indices not rolling over
    ILM策略卡住或配置错误 -- 索引未滚动
[ ] Massive unexpected data ingestion
    大量意外数据摄入
[ ] Shard relocation piled data onto this node
    分片迁移将数据堆积到此节点
[ ] Deleted documents not reclaimed (no force merge)
    已删除文档未回收（未强制合并）
[ ] Log index explosion from error loop in application
    应用程序错误循环导致日志索引爆炸
```

```bash
# Same diagnostic commands as ES-005 plus: / 与ES-005相同的诊断命令，另加：

# Check if flood-stage watermark is close / 检查是否接近洪水线水位线
curl -s "http://ES_ENDPOINT:9200/_cluster/settings?flat_keys=true&include_defaults=true" | \
  jq '{low: .defaults["cluster.routing.allocation.disk.watermark.low"], high: .defaults["cluster.routing.allocation.disk.watermark.high"], flood_stage: .defaults["cluster.routing.allocation.disk.watermark.flood_stage"]}'

# Check shard relocation in progress / 检查正在进行的分片迁移
curl -s "http://ES_ENDPOINT:9200/_cat/recovery?v&active_only=true&h=index,shard,time,type,stage,source_node,target_node,bytes_percent"
```

---

### 4. ACT / 执行

**Tier 3 Authority / Tier 3 权限:** US DBA + China HQ. Emergency deletion, watermark adjustment, and disk expansion authorized.

```bash
# STEP 1: IMMEDIATE — If indices are already read-only, remove the block
# 步骤1：立即 -- 如果索引已经只读，移除只读标记
curl -X PUT "http://ES_ENDPOINT:9200/_all/_settings" -H 'Content-Type: application/json' -d '{
  "index.blocks.read_only_allow_delete": null
}'

# STEP 2: Delete the largest expendable indices / 步骤2：删除最大的可删除索引
# List candidates / 列出候选索引
curl -s "http://ES_ENDPOINT:9200/_cat/indices?v&s=store.size:desc&h=index,store.size,creation.date.string" | head -10

# Delete old log/temp indices / 删除旧日志/临时索引
curl -X DELETE "http://ES_ENDPOINT:9200/OLD_INDEX_NAME_1,OLD_INDEX_NAME_2"

# STEP 3: Temporarily raise the watermark to prevent read-only triggering
# 步骤3：临时提高水位线阈值以防止触发只读
curl -X PUT "http://ES_ENDPOINT:9200/_cluster/settings" -H 'Content-Type: application/json' -d '{
  "transient": {
    "cluster.routing.allocation.disk.watermark.low": "90%",
    "cluster.routing.allocation.disk.watermark.high": "95%",
    "cluster.routing.allocation.disk.watermark.flood_stage": "97%"
  }
}'
# NOTE: REVERT THIS after disk issue is resolved! / 注意：磁盘问题解决后必须恢复！

# STEP 4: Expand EBS volume (if on AWS) / 步骤4：扩展EBS卷（如果在AWS上）
# Identify the instance and volume / 识别实例和卷
# aws ec2 describe-volumes --filters "Name=attachment.instance-id,Values=INSTANCE_ID" \
#   --query 'Volumes[*].{ID:VolumeId,Size:Size,State:State}' --region us-east-1

# Expand the volume / 扩展卷
# aws ec2 modify-volume --volume-id vol-XXXXXXXX --size NEW_SIZE_GB --region us-east-1

# After EBS expansion, extend filesystem on the node / EBS扩展后，在节点上扩展文件系统
# ssh NODE_IP "sudo resize2fs /dev/xvdf"

# STEP 5: After recovery, REVERT watermark settings / 步骤5：恢复后，恢复水位线设置
# curl -X PUT "http://ES_ENDPOINT:9200/_cluster/settings" -H 'Content-Type: application/json' -d '{
#   "transient": {
#     "cluster.routing.allocation.disk.watermark.low": null,
#     "cluster.routing.allocation.disk.watermark.high": null,
#     "cluster.routing.allocation.disk.watermark.flood_stage": null
#   }
# }'
```

---

### 5. AFTERMATH / 后续

- **Mandatory post-incident report** / 强制事后报告
- Verify watermark settings have been reverted to defaults / 验证水位线设置已恢复默认值
- Implement proactive ILM policies for all index patterns / 为所有索引模式实施主动ILM策略
- Set up disk growth trend monitoring to predict future capacity needs / 设置磁盘增长趋势监控以预测未来容量需求
- Review EBS volume sizing — consider gp3 with provisioned IOPS / 审查EBS卷大小 -- 考虑使用带预置IOPS的gp3
- Add 75% disk usage alert as early warning / 添加75%磁盘使用告警作为早期预警

---

## Appendix A: Alert Pairing Quick Reference / 附录A：告警配对快速参考

All 6 ES alerts are organized as 3 warning/critical pairs:
所有6个ES告警组织为3对 warning/critical 配对：

| Warning / 警告 | Critical / 关键 | Category / 类别 |
|---------|----------|----------|
| LCK-ES-001 (ESClusterYellow_Warning) | LCK-ES-002 (ESClusterRed_Critical) | Cluster Health / 集群健康 |
| LCK-ES-003 (ESCpuHigh_Warning) | LCK-ES-004 (ESCpuHigh_Critical) | Node CPU / 节点CPU |
| LCK-ES-005 (ESDiskLow_Warning) | LCK-ES-006 (ESDiskLow_Critical) | Node Disk / 节点磁盘 |

---

## Appendix B: ES Disk Watermark Reference / 附录B：ES磁盘水位线参考

| Watermark / 水位线 | Default / 默认值 | Effect / 影响 | Recovery Action / 恢复操作 |
|-----------|---------|--------|----------------|
| Low / 低 | 85% | Stops allocating new shards to node / 停止向节点分配新分片 | Delete old indices, reduce replicas / 删除旧索引，减少副本 |
| High / 高 | 90% | Relocates shards away from node / 从节点迁移分片 | Emergency index deletion, expand disk / 紧急删除索引，扩展磁盘 |
| Flood-stage / 洪水线 | 95% | Sets indices to read-only / 索引设为只读 | Remove read-only block, immediate disk expansion / 移除只读标记，立即扩展磁盘 |

---

## Appendix C: Key ES REST API Endpoints / 附录C：关键ES REST API端点

| Endpoint | Purpose / 用途 |
|----------|--------|
| `_cluster/health` | Cluster status, node count, shard counts / 集群状态、节点数、分片数 |
| `_cluster/allocation/explain` | Why shards are unassigned / 分片未分配的原因 |
| `_cluster/settings` | View/modify cluster settings / 查看/修改集群设置 |
| `_cluster/reroute?retry_failed=true` | Retry failed shard allocation / 重试失败的分片分配 |
| `_cat/nodes?v` | Node status overview / 节点状态概览 |
| `_cat/indices?v&s=store.size:desc` | Indices sorted by size / 按大小排序的索引 |
| `_cat/shards?v` | Shard distribution / 分片分布 |
| `_cat/allocation?v` | Disk allocation per node / 每节点磁盘分配 |
| `_cat/recovery?v&active_only=true` | Active shard recoveries / 活动分片恢复 |
| `_nodes/stats/jvm,os` | JVM heap and OS stats / JVM堆和操作系统统计 |
| `_nodes/hot_threads` | CPU-consuming threads / CPU消耗线程 |
| `_tasks?detailed` | Running tasks / 运行中的任务 |

---

## Appendix D: Contact Escalation / 附录D：联系升级

| Role / 角色 | Contact / 联系方式 | When / 何时 |
|------|---------|------|
| US DBA On-Call / 美国DBA值班 | WeCom group / 企业微信群 | All ES alerts / 所有ES告警 |
| US Team Lead / 美国团队负责人 | WeCom + Twilio (US) | Tier 2+ |
| China HQ DBA / 中国总部DBA | WeCom + Twilio (CN) | Tier 3 only / 仅Tier 3 |
| China HQ Engineering / 中国总部工程 | WeCom + Twilio (CN) | Tier 3 only / 仅Tier 3 |
| AWS Support / AWS支持 | Support console / 支持控制台 | Infrastructure issues / 基础设施问题 |

---

> **End of Part 4 / 第4部分结束** -- DB-ES Elasticsearch (6 alerts / 6个告警)
> Next: Part 5 -- DB-MONGO (MongoDB/DocumentDB)
> 下一部分：第5部分 -- DB-MONGO (MongoDB/DocumentDB)

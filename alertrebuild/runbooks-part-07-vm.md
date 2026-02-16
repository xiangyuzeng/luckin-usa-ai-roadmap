# Luckin Coffee NA — Alert Runbook Part 7: INFRA-VM (VM/Host)
# 瑞幸咖啡北美 — 报警运维手册 第7部分：基础设施-虚拟机/主机

> **Version / 版本:** 1.0 | **Category / 分类:** INFRA-VM | **Alerts / 报警数:** 8 (VM-01 to VM-08)
> **Cluster / 集群:** luckyus-prod | **Region / 区域:** us-east-1 | **Account / 账户:** 257394478466
> **Consolidation / 整合:** 17 legacy alerts → 8 new alerts (53% reduction / 缩减53%)
> **Skill Reference / 技能参考:** `/app/skills/ec2-alert-investigation.md` → `/investigate-ec2`
> **Pattern / 模式:** 5A Response (Assess → Acknowledge → Analyze → Act → Aftermath)
> **Last Updated / 最后更新:** 2026-02-16

---

## Table of Contents / 目录

| # | Alert ID | Alert Name | Severity | Section |
|---|----------|------------|----------|---------|
| 1 | LCK-VM-001 | VmCpuUsageWarning | warning | [VM-01](#lck-vm-001) |
| 2 | LCK-VM-002 | VmCpuUsageCritical | critical | [VM-02](#lck-vm-002) |
| 3 | LCK-VM-003 | VmMemoryUsageWarning | warning | [VM-03](#lck-vm-003) |
| 4 | LCK-VM-004 | VmMemoryUsageCritical | critical | [VM-04](#lck-vm-004) |
| 5 | LCK-VM-005 | VmDiskUsageWarning | warning | [VM-05](#lck-vm-005) |
| 6 | LCK-VM-006 | VmDiskUsageCritical | critical | [VM-06](#lck-vm-006) |
| 7 | LCK-VM-007 | VmNetworkErrorsWarning | warning | [VM-07](#lck-vm-007) |
| 8 | LCK-VM-008 | VmInstanceDownCritical | critical | [VM-08](#lck-vm-008) |

---

## Category Overview / 分类概述

**English:** INFRA-VM alerts monitor the health and performance of all EC2/VM instances in the Luckin Coffee NA production environment. These alerts cover CPU utilization, memory usage, disk capacity, network errors, and instance availability. All alerts use `node_exporter` metrics collected via Prometheus and evaluated by the **Basic VMAlert endpoint** (10.238.3.153:8880). The 8 alerts are organized into warning/critical pairs for CPU, memory, and disk, plus a network errors warning and an instance-down critical alert.

**中文:** INFRA-VM 报警监控瑞幸咖啡北美生产环境中所有 EC2/VM 实例的健康状况和性能表现。这些报警涵盖 CPU 利用率、内存使用、磁盘容量、网络错误和实例可用性。所有报警使用通过 Prometheus 采集的 `node_exporter` 指标，由 **Basic VMAlert 节点** (10.238.3.153:8880) 进行评估。8 个报警按 CPU、内存和磁盘的警告/严重配对组织，加上网络错误警告和实例宕机严重报警。

---

## Recording Rules / 预计算规则

All recording rules are in group `lck-na.recording.vm` with evaluation interval `30s`.

| Record Name | Expression | Purpose / 用途 |
|-------------|-----------|----------------|
| `lckna:vm:cpu_avg5m` | `100 - avg by (instance)(rate(node_cpu_seconds_total{mode="idle", env="production"}[5m])) * 100` | 5-minute average CPU usage per instance / 每实例5分钟平均CPU使用率 |
| `lckna:vm:memory_avg10m` | `avg_over_time((1 - node_memory_MemAvailable_bytes{env="production"} / node_memory_MemTotal_bytes{env="production"})[10m:]) * 100` | 10-minute average memory usage / 10分钟平均内存使用率 |
| `lckna:vm:disk_util` | `100 - (node_filesystem_avail_bytes{env="production", mountpoint="/", fstype!="tmpfs"} / node_filesystem_size_bytes{env="production", mountpoint="/", fstype!="tmpfs"}) * 100` | Root partition disk utilization / 根分区磁盘利用率 |
| `lckna:vm:net_errors_rate5m` | `rate(node_network_receive_errs_total{env="production"}[5m]) + rate(node_network_transmit_errs_total{env="production"}[5m])` | 5-minute network error rate (rx+tx) / 5分钟网络错误率(收+发) |

---

## Alert Summary / 报警总览

| ID | Alert Name | Severity | Tier | Threshold | For | Old IDs | Consolidation |
|----|-----------|----------|------|-----------|-----|---------|---------------|
| VM-01 | VmCpuUsageWarning | warning | 2 | CPU > 80% ≤ 95% | 5m | ALR-100, ALR-101 | MERGE |
| VM-02 | VmCpuUsageCritical | critical | 1 | CPU > 95% | 3m | ALR-102, ALR-103 | MERGE |
| VM-03 | VmMemoryUsageWarning | warning | 2 | Memory > 85% ≤ 95% | 10m | ALR-109 | KEEP |
| VM-04 | VmMemoryUsageCritical | critical | 1 | Memory > 95% | 5m | ALR-109 | SPLIT |
| VM-05 | VmDiskUsageWarning | warning | 2 | Disk > 85% ≤ 95% | 10m | ALR-111 | KEEP |
| VM-06 | VmDiskUsageCritical | critical | 1 | Disk > 95% | 5m | ALR-104, ALR-105, ALR-111 | MERGE |
| VM-07 | VmNetworkErrorsWarning | warning | 2 | Errors > 200/s or Drops > 20/s | 5m | ALR-108, ALR-112–115 | MERGE |
| VM-08 | VmInstanceDownCritical | critical | 1 | up == 0 | 10m | ALR-110, ALR-116 | MERGE |

---

## Alert Chains / 报警链

```
CPU Chain / CPU链:
  VM-01 (warning >80%) ──escalate──▶ VM-02 (critical >95%)

Memory Chain / 内存链:
  VM-03 (warning >85%) ──escalate──▶ VM-04 (critical >95%)

Disk Chain / 磁盘链:
  VM-05 (warning >85%) ──escalate──▶ VM-06 (critical >95%)

Independent / 独立:
  VM-07 (network errors/drops)
  VM-08 (instance down) ← highest priority, may cause all other alerts
```

---

<a id="lck-vm-001"></a>
## VM-01: VmCpuUsageWarning / VM CPU 使用率偏高（警告级）

```yaml
alert_id: LCK-VM-001
alert_name: VmCpuUsageWarning
old_ids: [ALR-100, ALR-101]
consolidation: MERGE
severity: warning
tier: "2"
category: INFRA-VM
team: sys-ops
first_responder: US DevOps On-Call
sla_response: 15 min acknowledge / 1 hour first update / 4 hours resolution
notification_channel: wecom+twilio-lead
skill_reference: /app/skills/ec2-alert-investigation.md
dashboard: vm-overview
last_updated: 2026-02-16
```

### Alert Rule / 报警规则

```yaml
alert: VmCpuUsageWarning
expr: lckna:vm:cpu_avg5m > 80 and lckna:vm:cpu_avg5m <= 95
for: 5m
labels:
  severity: warning
  tier: "2"
  category: infra-vm
  team: sys-ops
  dashboard: vm-overview
annotations:
  summary: "VM CPU usage warning on {{ $labels.instance }}"
  description: "CPU usage is {{ $value | printf \"%.1f\" }}% (threshold: 80%) for 5 minutes on {{ $labels.instance }}."
  runbook_url: "https://runbooks.luckinus.com/infra-vm/vm-cpu-warning"
  dashboard_url: "https://grafana.luckinus.com/d/vm-overview"
```

### PromQL Expression / PromQL 表达式

```promql
# Recording rule used:
lckna:vm:cpu_avg5m > 80 and lckna:vm:cpu_avg5m <= 95

# Underlying raw expression:
(100 - avg by (instance)(rate(node_cpu_seconds_total{mode="idle", env="production"}[5m])) * 100) > 80
```

**Meaning / 含义:** The 5-minute average CPU utilization on a production VM has exceeded 80% but remains below 95% for at least 5 minutes. This is an early warning that the instance may be approaching capacity. Check for runaway processes, increased traffic, or batch jobs consuming CPU.

**含义：** 生产环境虚拟机的5分钟平均CPU利用率已超过80%但低于95%，持续至少5分钟。这是实例可能接近容量上限的早期警告。检查失控进程、流量增长或消耗CPU的批处理作业。

### 1. ASSESS / 评估

#### 1.1 Golden Path Impact Check / 黄金流程影响检查

```bash
# Check if golden path (order flow) is impacted
# 检查黄金流程（下单流程）是否受影响
curl -s "http://localhost:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])" | jq '.data.result[0].value[1]'
# If == 0 for 10 min → Golden path DOWN → Escalate to Tier 3
# 如果10分钟内为0 → 黄金流程中断 → 升级至Tier 3
```

#### 1.2 Quick Triage / 快速分诊

```bash
# Identify the affected instance from alert labels
# 从告警标签识别受影响实例
INSTANCE="{{ $labels.instance }}"  # e.g., 10.238.x.x:9100

# Check current CPU value
# 检查当前CPU值
curl -s "http://localhost:9090/api/v1/query?query=lckna:vm:cpu_avg5m{instance='${INSTANCE}'}" | jq '.data.result[0].value[1]'
```

#### 1.3 Severity Classification / 严重程度分类

| Condition / 条件 | Classification / 分类 | Action / 操作 |
|---|---|---|
| CPU 80-85%, no golden path impact | Low Warning / 低级警告 | Monitor, investigate when convenient |
| CPU 85-90%, trending up | Medium Warning / 中级警告 | Investigate within 30 min |
| CPU 90-95%, services slowing | High Warning / 高级警告 | Investigate immediately, prepare to escalate |
| Golden path impacted | → Treat as Tier 3 Critical / 按Tier 3处理 | Immediate escalation |

### 2. ACKNOWLEDGE / 确认 (Within 15 min / 15 分钟内)

```bash
# Silence alert for investigation window (1 hour)
# 静默告警以便调查（1小时）
amtool silence add \
  --alertmanager.url=http://alertmanager:9093 \
  --author="$(whoami)" \
  --comment="Investigating VM CPU warning on ${INSTANCE}" \
  --duration=1h \
  alertname=VmCpuUsageWarning instance="${INSTANCE}"
```

**WeCom Notification Template / 企业微信通知模板:**
```
🟡 [ACKNOWLEDGED] VM-01: VmCpuUsageWarning
Instance: {{ $labels.instance }}
CPU: {{ $value }}%
Threshold: 80%
Responder: [Your Name]
ETA: Investigating, update in 30 min
Status: Silenced for 1h
```

### 3. ANALYZE / 分析

#### 3.1 Common Causes / 常见原因

- **Runaway process / 失控进程:** Java/Python process in infinite loop or memory thrashing
- **Traffic spike / 流量突增:** Seasonal promotion or marketing event driving increased requests
- **Batch job overlap / 批处理作业重叠:** Multiple cron jobs running simultaneously
- **Insufficient instance size / 实例规格不足:** Instance type too small for workload
- **Container resource limits / 容器资源限制:** If running containers, CPU limits too high relative to instance

#### 3.2 Diagnostic Commands / 诊断命令

```bash
# SSH to the affected instance
# SSH登录受影响实例
ssh ec2-user@${INSTANCE%%:*}

# Top CPU consumers (top 10)
# CPU消耗最高的进程（前10）
top -bn1 -o %CPU | head -17

# Detailed process CPU usage
# 详细进程CPU使用情况
ps aux --sort=-%cpu | head -15

# Check load average vs CPU cores
# 检查负载均衡与CPU核心数对比
echo "Load: $(cat /proc/loadavg) | Cores: $(nproc)"

# Check for IOWait (indicates disk bottleneck)
# 检查IOWait（表示磁盘瓶颈）
iostat -x 1 3

# Check steal time (noisy neighbor on shared instance)
# 检查steal时间（共享实例上的噪声邻居）
mpstat 1 5

# Check for OOM kills driving CPU spikes
# 检查OOM kill是否导致CPU飙升
dmesg | grep -i "oom\|killed" | tail -10

# Check recent cron jobs
# 检查最近的定时任务
grep CRON /var/log/syslog | tail -20 2>/dev/null || journalctl -u cron --since "1 hour ago" | tail -20
```

#### 3.3 VMAlert Endpoint Verification / VMAlert 节点验证

```bash
# Verify alert is evaluating on the Basic VMAlert endpoint
# 验证告警在Basic VMAlert节点上评估
curl -s "http://10.238.3.153:8880/api/v1/alerts" | jq '.data.alerts[] | select(.labels.alertname=="VmCpuUsageWarning")'
```

#### 3.4 PromQL Deep Dive / PromQL 深入查询

```promql
# CPU breakdown by mode for the instance
# 按模式分解实例CPU
rate(node_cpu_seconds_total{instance="${INSTANCE}", env="production"}[5m]) * 100

# CPU trend over last hour
# 最近1小时CPU趋势
lckna:vm:cpu_avg5m{instance="${INSTANCE}"}[1h]

# Check if load average exceeds cores
# 检查负载均衡是否超过核心数
node_load5{instance="${INSTANCE}"} / count without(cpu)(node_cpu_seconds_total{instance="${INSTANCE}", mode="idle"})
```

**Dashboard:** [VM Overview](https://grafana.luckinus.com/d/vm-overview)

### 4. ACT / 处置

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---|---|---|
| Single runaway process | `kill -15 <PID>` or `kill -9 <PID>` | On-call DevOps |
| Batch job overlap | Reschedule cron jobs to stagger | On-call DevOps |
| Traffic spike (expected) | Scale instance type or add capacity | On-call DevOps + Team Lead |
| Traffic spike (unexpected) | Investigate source, consider rate limiting | On-call DevOps + Team Lead |
| Steal time > 10% | Migrate to dedicated instance | Team Lead approval |
| Consistently > 80% | Right-size instance (upgrade) | Change request |

```bash
# Kill a runaway process (use -15 first, then -9 if needed)
# 终止失控进程（先用-15，必要时用-9）
kill -15 <PID>
sleep 10
# If still running / 如果仍在运行:
kill -9 <PID>

# Check if CPU recovered
# 检查CPU是否恢复
watch -n5 "top -bn1 | head -5"
```

**Escalation / 升级:**
```
If CPU remains > 80% after 30 min investigation → Escalate to Tier 3
如果调查30分钟后CPU仍 > 80% → 升级至Tier 3

Tier 2 (Warning) → (30 min no resolution) → Tier 3 (Critical)
                                                    ↓
                                         China HQ Engineering
                                         中国总部工程团队
```

### 5. AFTERMATH / 善后

- [ ] Verify CPU < 80% for 15 minutes after remediation / 验证修复后CPU低于80%持续15分钟
- [ ] Remove alert silence / 移除告警静默
- [ ] Post WeCom resolution summary / 在企业微信发布解决摘要
- [ ] If process killed: verify service health / 如果终止了进程：验证服务健康
- [ ] Update capacity planning if instance is consistently hot / 如实例持续高负载则更新容量规划
- [ ] File change request for instance upgrade if needed / 如需要则提交实例升级变更请求
- [ ] Related alerts: VM-02 (CPU Critical) — check if escalation is imminent / 相关告警：VM-02 (CPU严重) — 检查是否即将升级

**Old Alert Reference / 旧告警参考:** ALR-100 (EC2 CPU > 80%), ALR-101 (EC2 CPU > 85%) → Merged into LCK-VM-001

---

<a id="lck-vm-002"></a>
## VM-02: VmCpuUsageCritical / VM CPU 使用率过高（严重级）

```yaml
alert_id: LCK-VM-002
alert_name: VmCpuUsageCritical
old_ids: [ALR-102, ALR-103]
consolidation: MERGE
severity: critical
tier: "1"
category: INFRA-VM
team: sys-ops
first_responder: US DevOps On-Call + Team Lead
sla_response: 5 min acknowledge / 15 min first update / 1 hour resolution
notification_channel: wecom+twilio-all
skill_reference: /app/skills/ec2-alert-investigation.md
dashboard: vm-overview
last_updated: 2026-02-16
```

### Alert Rule / 报警规则

```yaml
alert: VmCpuUsageCritical
expr: lckna:vm:cpu_avg5m > 95
for: 3m
labels:
  severity: critical
  tier: "1"
  category: infra-vm
  team: sys-ops
  dashboard: vm-overview
annotations:
  summary: "VM CPU CRITICAL on {{ $labels.instance }}"
  description: "CPU usage is {{ $value | printf \"%.1f\" }}% (threshold: 95%) for 3 minutes on {{ $labels.instance }}. Immediate action required."
  runbook_url: "https://runbooks.luckinus.com/infra-vm/vm-cpu-critical"
  dashboard_url: "https://grafana.luckinus.com/d/vm-overview"
```

### PromQL Expression / PromQL 表达式

```promql
lckna:vm:cpu_avg5m > 95
```

**Meaning / 含义:** CPU utilization on a production VM has exceeded 95% for 3 minutes. The instance is effectively saturated. Services may be unresponsive or severely degraded. This is an emergency requiring immediate triage — identify the cause and either kill processes or scale the instance.

**含义：** 生产环境虚拟机的CPU利用率已超过95%持续3分钟。实例已有效饱和。服务可能无响应或严重降级。这是需要立即分诊的紧急情况——找出原因并终止进程或扩展实例。

### 1. ASSESS / 评估

#### 1.1 Golden Path Impact Check / 黄金流程影响检查

```bash
# CRITICAL: Check golden path IMMEDIATELY
# 严重：立即检查黄金流程
curl -s "http://localhost:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])" | jq '.data.result[0].value[1]'
# If == 0 → Golden path DOWN → All hands on deck
# 如果为0 → 黄金流程中断 → 全员响应
```

#### 1.2 Quick Triage / 快速分诊

```bash
# What services run on this instance?
# 该实例上运行哪些服务？
INSTANCE="{{ $labels.instance }}"
ssh ec2-user@${INSTANCE%%:*} "systemctl list-units --type=service --state=running | grep -v snapd"

# Is this a critical path server?
# 这是否是关键路径服务器？
# Check if instance hosts: order-service, payment-service, user-service
```

#### 1.3 Severity Classification / 严重程度分类

| Condition / 条件 | Classification / 分类 | Action / 操作 |
|---|---|---|
| CPU > 95%, no golden path impact | Critical / 严重 | Immediate investigation, 5 min acknowledge |
| CPU > 95%, golden path degraded | Emergency / 紧急 | All DevOps respond, China HQ notified |
| CPU > 95% on multiple instances | Incident / 事件 | Declare incident, assemble response team |

### 2. ACKNOWLEDGE / 确认 (Within 5 min / 5 分钟内)

```bash
# Silence alert for emergency window (30 min)
# 静默告警以便紧急处理（30分钟）
amtool silence add \
  --alertmanager.url=http://alertmanager:9093 \
  --author="$(whoami)" \
  --comment="CRITICAL: Investigating VM CPU > 95% on ${INSTANCE}" \
  --duration=30m \
  alertname=VmCpuUsageCritical instance="${INSTANCE}"
```

**WeCom Notification Template / 企业微信通知模板:**
```
🔴 [CRITICAL] VM-02: VmCpuUsageCritical
Instance: {{ $labels.instance }}
CPU: {{ $value }}%
Threshold: 95%
Responder: [Your Name]
Action: Immediate investigation
ETA: First update in 15 min
```

### 3. ANALYZE / 分析

#### 3.1 Common Causes / 常见原因

- **Fork bomb / fork炸弹:** Malicious or accidental process spawning
- **Memory thrashing / 内存抖动:** Swap usage causing CPU spin on page faults
- **Application deadlock / 应用死锁:** Java thread deadlock causing CPU spin-wait
- **Crypto mining / 挖矿:** Compromised instance running unauthorized workloads
- **Cascading failure / 级联故障:** Upstream service down, retries consuming CPU

#### 3.2 Diagnostic Commands / 诊断命令

```bash
ssh ec2-user@${INSTANCE%%:*}

# Immediate top-level view
# 立即查看顶级视图
top -bn1 -o %CPU | head -20

# Check for IOWait and steal
# 检查IOWait和steal时间
mpstat -P ALL 1 3

# Process tree to find parent of runaway processes
# 进程树查找失控进程的父进程
ps auxf --sort=-%cpu | head -30

# Check for swap usage (indicates memory pressure driving CPU)
# 检查swap使用（表示内存压力导致CPU升高）
free -h
vmstat 1 5

# Check open file descriptors (fd leak)
# 检查打开文件描述符（fd泄漏）
lsof | wc -l

# Check for unusual network connections
# 检查异常网络连接
ss -tunap | grep ESTABLISHED | wc -l
```

#### 3.3 VMAlert Endpoint Verification / VMAlert 节点验证

```bash
curl -s "http://10.238.3.153:8880/api/v1/alerts" | jq '.data.alerts[] | select(.labels.alertname=="VmCpuUsageCritical")'
```

#### 3.4 AWS Console Check / AWS 控制台检查

```bash
# Get instance ID from IP
# 从IP获取实例ID
INSTANCE_IP="${INSTANCE%%:*}"
aws ec2 describe-instances --filters "Name=private-ip-address,Values=${INSTANCE_IP}" \
  --query "Reservations[0].Instances[0].{ID:InstanceId,Type:InstanceType,State:State.Name}" --output table

# Check CloudWatch CPU metrics
# 检查CloudWatch CPU指标
aws cloudwatch get-metric-statistics --namespace AWS/EC2 \
  --metric-name CPUUtilization --dimensions Name=InstanceId,Value=<INSTANCE_ID> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 --statistics Maximum
```

### 4. ACT / 处置

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---|---|---|
| Runaway process identified | `kill -9 <PID>` immediately | On-call DevOps |
| Swap thrashing | Identify memory hog, kill or restart service | On-call DevOps |
| Suspected compromise | Isolate instance (security group), escalate to security | Team Lead + Security |
| Cascading failure | Fix upstream service first | On-call DevOps + App team |
| Instance undersized | Stop & resize instance type | Team Lead approval |
| Multiple instances affected | Declare incident, scale ASG | Team Lead + China HQ |

```bash
# Emergency: kill top CPU process
# 紧急：终止最高CPU进程
TOP_PID=$(ps aux --sort=-%cpu | awk 'NR==2{print $2}')
echo "Killing PID ${TOP_PID}: $(ps -p ${TOP_PID} -o comm=)"
kill -9 ${TOP_PID}

# If instance needs to be resized (requires downtime)
# 如果需要调整实例大小（需要停机）
# aws ec2 stop-instances --instance-ids <ID>
# aws ec2 modify-instance-attribute --instance-id <ID> --instance-type '{"Value":"m5.xlarge"}'
# aws ec2 start-instances --instance-ids <ID>
```

**Escalation / 升级:**
```
Tier 3 (Critical) — immediate notify: All US DevOps + China HQ
Tier 3（严重）— 立即通知：全部美国DevOps + 中国总部

If no resolution in 30 min → Executive escalation
如果30分钟内未解决 → 管理层升级
```

### 5. AFTERMATH / 善后

- [ ] Verify CPU < 80% for 15 minutes / 验证CPU低于80%持续15分钟
- [ ] Remove alert silence / 移除告警静默
- [ ] Post WeCom resolution summary with root cause / 在企业微信发布含根因的解决摘要
- [ ] If process killed: verify affected service restored / 如终止了进程：验证受影响服务已恢复
- [ ] Conduct brief post-incident review / 进行简要事后回顾
- [ ] File capacity planning ticket if instance is undersized / 如实例规格不足则提交容量规划工单
- [ ] Update monitoring if new failure mode discovered / 如发现新故障模式则更新监控
- [ ] Related alerts: VM-01 (CPU Warning) — should resolve after VM-02 resolved / 相关告警：VM-01 (CPU警告) — 在VM-02解决后应自动恢复

**Old Alert Reference / 旧告警参考:** ALR-102 (EC2 CPU > 90%), ALR-103 (EC2 CPU > 95%) → Merged into LCK-VM-002

---

<a id="lck-vm-003"></a>
## VM-03: VmMemoryUsageWarning / VM 内存使用率偏高（警告级）

```yaml
alert_id: LCK-VM-003
alert_name: VmMemoryUsageWarning
old_ids: [ALR-109]
consolidation: KEEP
severity: warning
tier: "2"
category: INFRA-VM
team: sys-ops
first_responder: US DevOps On-Call
sla_response: 15 min acknowledge / 1 hour first update / 4 hours resolution
notification_channel: wecom+twilio-lead
skill_reference: /app/skills/ec2-alert-investigation.md
dashboard: vm-memory
last_updated: 2026-02-16
```

### Alert Rule / 报警规则

```yaml
alert: VmMemoryUsageWarning
expr: lckna:vm:memory_avg10m > 85 and lckna:vm:memory_avg10m <= 95
for: 10m
labels:
  severity: warning
  tier: "2"
  category: infra-vm
  team: sys-ops
  dashboard: vm-memory
annotations:
  summary: "VM memory usage warning on {{ $labels.instance }}"
  description: "Memory usage is {{ $value | printf \"%.1f\" }}% (threshold: 85%) for 10 minutes on {{ $labels.instance }}."
  runbook_url: "https://runbooks.luckinus.com/infra-vm/vm-memory-warning"
  dashboard_url: "https://grafana.luckinus.com/d/vm-memory"
```

### PromQL Expression / PromQL 表达式

```promql
lckna:vm:memory_avg10m > 85 and lckna:vm:memory_avg10m <= 95

# Underlying:
avg_over_time(
  (1 - node_memory_MemAvailable_bytes{env="production"} / node_memory_MemTotal_bytes{env="production"})[10m:]
) * 100
```

**Meaning / 含义:** The 10-minute average memory utilization on a production VM has exceeded 85% but remains below 95% for at least 10 minutes. This indicates the instance is running low on available memory. Investigate for memory leaks, oversized JVM heaps, or unexpected memory consumers before an OOM event occurs.

**含义：** 生产环境虚拟机的10分钟平均内存利用率已超过85%但低于95%，持续至少10分钟。这表示实例可用内存不足。在发生OOM事件之前，调查内存泄漏、过大的JVM堆或意外的内存消耗者。

### 1. ASSESS / 评估

#### 1.1 Golden Path Impact Check / 黄金流程影响检查

```bash
curl -s "http://localhost:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])" | jq '.data.result[0].value[1]'
```

#### 1.2 Quick Triage / 快速分诊

```bash
INSTANCE="{{ $labels.instance }}"
# Check current memory value
curl -s "http://localhost:9090/api/v1/query?query=lckna:vm:memory_avg10m{instance='${INSTANCE}'}" | jq '.data.result[0].value[1]'
```

#### 1.3 Severity Classification / 严重程度分类

| Condition / 条件 | Classification / 分类 | Action / 操作 |
|---|---|---|
| Memory 85-90%, stable | Low Warning / 低级警告 | Monitor, investigate when convenient |
| Memory 90-95%, trending up | High Warning / 高级警告 | Investigate immediately |
| Swap usage increasing | High Warning / 高级警告 | Potential OOM, prepare for escalation |
| Golden path impacted | → Treat as Tier 3 / 按Tier 3处理 | Immediate escalation |

### 2. ACKNOWLEDGE / 确认 (Within 15 min / 15 分钟内)

```bash
amtool silence add \
  --alertmanager.url=http://alertmanager:9093 \
  --author="$(whoami)" \
  --comment="Investigating VM memory warning on ${INSTANCE}" \
  --duration=1h \
  alertname=VmMemoryUsageWarning instance="${INSTANCE}"
```

**WeCom Notification Template / 企业微信通知模板:**
```
🟡 [ACKNOWLEDGED] VM-03: VmMemoryUsageWarning
Instance: {{ $labels.instance }}
Memory: {{ $value }}%
Threshold: 85%
Responder: [Your Name]
ETA: Investigating, update in 30 min
```

### 3. ANALYZE / 分析

#### 3.1 Common Causes / 常见原因

- **Memory leak / 内存泄漏:** Application gradually consuming memory without releasing
- **JVM heap oversized / JVM堆过大:** Java process with -Xmx set too high for instance
- **Cache growth / 缓存增长:** In-memory cache (ehcache, Guava) growing unbounded
- **Log buffer buildup / 日志缓冲积压:** Filebeat or Fluentd buffering logs in memory
- **Container memory limits / 容器内存限制:** Containers consuming more than expected

#### 3.2 Diagnostic Commands / 诊断命令

```bash
ssh ec2-user@${INSTANCE%%:*}

# Memory overview
# 内存概览
free -h

# Top memory consumers
# 内存消耗最高的进程
ps aux --sort=-%mem | head -15

# Detailed memory breakdown
# 详细内存分解
cat /proc/meminfo | grep -E "MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree|Slab"

# Check for swap usage (early OOM indicator)
# 检查swap使用（OOM早期指标）
swapon --show
vmstat 1 5

# Check for memory leaks (RSS growth over time)
# 检查内存泄漏（RSS随时间增长）
# Compare with earlier values if available
ps -eo pid,ppid,rss,vsz,comm --sort=-rss | head -15

# Check OOM killer history
# 检查OOM killer历史
dmesg | grep -i "oom\|killed" | tail -20

# Java heap usage (if Java process is top consumer)
# Java堆使用情况（如果Java进程是最大消耗者）
jcmd $(pgrep java | head -1) GC.heap_info 2>/dev/null || echo "No Java process or jcmd unavailable"
```

#### 3.3 VMAlert Endpoint Verification / VMAlert 节点验证

```bash
curl -s "http://10.238.3.153:8880/api/v1/alerts" | jq '.data.alerts[] | select(.labels.alertname=="VmMemoryUsageWarning")'
```

#### 3.4 PromQL Deep Dive / PromQL 深入查询

```promql
# Memory trend over 6 hours
lckna:vm:memory_avg10m{instance="${INSTANCE}"}[6h]

# Breakdown: used vs cached vs buffers
node_memory_MemTotal_bytes{instance="${INSTANCE}"} - node_memory_MemAvailable_bytes{instance="${INSTANCE}"}

# Swap usage
node_memory_SwapTotal_bytes{instance="${INSTANCE}"} - node_memory_SwapFree_bytes{instance="${INSTANCE}"}
```

**Dashboard:** [VM Memory](https://grafana.luckinus.com/d/vm-memory)

### 4. ACT / 处置

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---|---|---|
| Identified memory leak | Restart affected service gracefully | On-call DevOps |
| JVM heap too large | Adjust -Xmx, restart service | On-call DevOps + App team |
| Cache growth | Clear cache or set eviction policy | On-call DevOps + App team |
| Log buffer buildup | Restart log shipper, check downstream | On-call DevOps |
| Consistently > 85% | File capacity planning ticket | Change request |

```bash
# Restart a service gracefully (example: Java application)
# 优雅重启服务（示例：Java应用）
systemctl restart <service-name>

# Clear filesystem caches (temporary relief, not a fix)
# 清除文件系统缓存（临时缓解，非修复）
sync && echo 3 > /proc/sys/vm/drop_caches
```

**Escalation / 升级:**
```
If memory continues rising toward 95% → Prepare for VM-04 Critical
如果内存持续上升至95% → 准备应对VM-04严重告警

Tier 2 → (30 min no resolution) → Tier 3
```

### 5. AFTERMATH / 善后

- [ ] Verify memory < 85% for 15 minutes / 验证内存低于85%持续15分钟
- [ ] Remove alert silence / 移除告警静默
- [ ] Post WeCom resolution summary / 在企业微信发布解决摘要
- [ ] If service restarted: verify all health checks pass / 如重启了服务：验证所有健康检查通过
- [ ] For memory leaks: file bug ticket with application team / 对于内存泄漏：向应用团队提交bug工单
- [ ] Review JVM/application memory settings / 检查JVM/应用内存设置
- [ ] Related alerts: VM-04 (Memory Critical) — monitor for escalation / 相关告警：VM-04 (内存严重) — 监控是否升级

**Old Alert Reference / 旧告警参考:** ALR-109 (Host Memory > 85%) → Kept as LCK-VM-003

---

<a id="lck-vm-004"></a>
## VM-04: VmMemoryUsageCritical / VM 内存使用率过高（严重级）

```yaml
alert_id: LCK-VM-004
alert_name: VmMemoryUsageCritical
old_ids: [ALR-109]
consolidation: SPLIT
severity: critical
tier: "1"
category: INFRA-VM
team: sys-ops
first_responder: US DevOps On-Call + Team Lead
sla_response: 5 min acknowledge / 15 min first update / 1 hour resolution
notification_channel: wecom+twilio-all
skill_reference: /app/skills/ec2-alert-investigation.md
dashboard: vm-memory
last_updated: 2026-02-16
```

### Alert Rule / 报警规则

```yaml
alert: VmMemoryUsageCritical
expr: lckna:vm:memory_avg10m > 95
for: 5m
labels:
  severity: critical
  tier: "1"
  category: infra-vm
  team: sys-ops
  dashboard: vm-memory
annotations:
  summary: "VM memory CRITICAL on {{ $labels.instance }}"
  description: "Memory usage is {{ $value | printf \"%.1f\" }}% (threshold: 95%) for 5 minutes on {{ $labels.instance }}. OOM imminent."
  runbook_url: "https://runbooks.luckinus.com/infra-vm/vm-memory-critical"
  dashboard_url: "https://grafana.luckinus.com/d/vm-memory"
```

### PromQL Expression / PromQL 表达式

```promql
lckna:vm:memory_avg10m > 95
```

**Meaning / 含义:** Memory utilization has exceeded 95% for 5 minutes. OOM (Out of Memory) kill is imminent. The Linux kernel will start killing processes to reclaim memory, which may take down critical services. Act immediately to identify the largest memory consumer and either restart it or add memory.

**含义：** 内存利用率已超过95%持续5分钟。OOM (内存不足) kill即将发生。Linux内核将开始终止进程以回收内存，这可能导致关键服务宕机。立即行动，找出最大内存消耗者并重启或增加内存。

### 1. ASSESS / 评估

#### 1.1 Golden Path Impact Check / 黄金流程影响检查

```bash
# CRITICAL: Check golden path IMMEDIATELY
curl -s "http://localhost:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])" | jq '.data.result[0].value[1]'
```

#### 1.2 Quick Triage / 快速分诊

```bash
INSTANCE="{{ $labels.instance }}"
# Check if OOM kills have already occurred
ssh ec2-user@${INSTANCE%%:*} "dmesg | grep -c 'Out of memory'" 2>/dev/null
```

### 2. ACKNOWLEDGE / 确认 (Within 5 min / 5 分钟内)

```bash
amtool silence add \
  --alertmanager.url=http://alertmanager:9093 \
  --author="$(whoami)" \
  --comment="CRITICAL: Investigating VM memory > 95% on ${INSTANCE}" \
  --duration=30m \
  alertname=VmMemoryUsageCritical instance="${INSTANCE}"
```

**WeCom Notification Template / 企业微信通知模板:**
```
🔴 [CRITICAL] VM-04: VmMemoryUsageCritical
Instance: {{ $labels.instance }}
Memory: {{ $value }}%
Threshold: 95% — OOM imminent
Responder: [Your Name]
Action: Immediate investigation
ETA: First update in 15 min
```

### 3. ANALYZE / 分析

#### 3.1 Common Causes / 常见原因

- **Memory leak reaching critical / 内存泄漏到达临界:** Application exhausting available memory
- **OOM cascade / OOM级联:** OOM killer killing processes, other processes consuming freed memory
- **Fork bomb / fork炸弹:** Process spawning unbounded children
- **Shared memory segment leak / 共享内存段泄漏:** IPC shm not released

#### 3.2 Diagnostic Commands / 诊断命令

```bash
ssh ec2-user@${INSTANCE%%:*}

# Immediate assessment
free -h
ps aux --sort=-%mem | head -10

# Check OOM killer log
dmesg -T | grep -i "oom\|killed" | tail -20

# Check swap exhaustion
swapon --show
cat /proc/meminfo | grep -E "Swap|Committed"

# Check shared memory segments
ipcs -m

# Check /tmp and tmpfs usage (counts against memory)
df -h /tmp /dev/shm
```

#### 3.3 VMAlert Endpoint Verification / VMAlert 节点验证

```bash
curl -s "http://10.238.3.153:8880/api/v1/alerts" | jq '.data.alerts[] | select(.labels.alertname=="VmMemoryUsageCritical")'
```

### 4. ACT / 处置

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---|---|---|
| Single process memory hog | `kill -9 <PID>`, restart service | On-call DevOps |
| OOM kills already happening | Identify and kill top RSS process | On-call DevOps |
| All processes are legitimate | Scale instance (add memory) | Team Lead approval |
| Tmpfs full | Clear /tmp, /dev/shm | On-call DevOps |
| Multiple instances affected | Declare incident | Team Lead + China HQ |

```bash
# Emergency: kill highest memory process
# 紧急：终止最高内存消耗进程
TOP_MEM_PID=$(ps aux --sort=-%mem | awk 'NR==2{print $2}')
echo "Killing PID ${TOP_MEM_PID}: $(ps -p ${TOP_MEM_PID} -o comm=) ($(ps -p ${TOP_MEM_PID} -o rss= | awk '{printf "%.0f MB", $1/1024}'))"
kill -9 ${TOP_MEM_PID}

# Verify memory freed
sleep 5 && free -h
```

**Escalation / 升级:**
```
Tier 3 (Critical) — All US DevOps + China HQ notified immediately
如果15分钟内未解决 → 管理层升级
```

### 5. AFTERMATH / 善后

- [ ] Verify memory < 85% for 15 minutes / 验证内存低于85%持续15分钟
- [ ] Remove alert silence / 移除告警静默
- [ ] Post WeCom resolution summary with root cause / 发布含根因的解决摘要
- [ ] Verify no OOM kills occurred during incident / 验证事件期间无OOM kill发生
- [ ] Conduct post-incident review / 进行事后回顾
- [ ] File capacity planning ticket / 提交容量规划工单
- [ ] Related alerts: VM-03 (Memory Warning) should also resolve / 相关告警：VM-03 (内存警告) 也应恢复

**Old Alert Reference / 旧告警参考:** ALR-109 (Host Memory > 85%) → Split into LCK-VM-003 (warning) + LCK-VM-004 (critical)

---

<a id="lck-vm-005"></a>
## VM-05: VmDiskUsageWarning / VM 磁盘使用率偏高（警告级）

```yaml
alert_id: LCK-VM-005
alert_name: VmDiskUsageWarning
old_ids: [ALR-111]
consolidation: KEEP
severity: warning
tier: "2"
category: INFRA-VM
team: sys-ops
first_responder: US DevOps On-Call
sla_response: 15 min acknowledge / 1 hour first update / 4 hours resolution
notification_channel: wecom+twilio-lead
skill_reference: /app/skills/ec2-alert-investigation.md
dashboard: vm-disk
last_updated: 2026-02-16
```

### Alert Rule / 报警规则

```yaml
alert: VmDiskUsageWarning
expr: lckna:vm:disk_util > 85 and lckna:vm:disk_util <= 95
for: 10m
labels:
  severity: warning
  tier: "2"
  category: infra-vm
  team: sys-ops
  dashboard: vm-disk
annotations:
  summary: "VM disk usage warning on {{ $labels.instance }}"
  description: "Root partition is {{ $value | printf \"%.1f\" }}% full (threshold: 85%) for 10 minutes on {{ $labels.instance }}."
  runbook_url: "https://runbooks.luckinus.com/infra-vm/vm-disk-warning"
  dashboard_url: "https://grafana.luckinus.com/d/vm-disk"
```

### PromQL Expression / PromQL 表达式

```promql
lckna:vm:disk_util > 85 and lckna:vm:disk_util <= 95

# Underlying:
100 - (node_filesystem_avail_bytes{env="production", mountpoint="/", fstype!="tmpfs"}
/ node_filesystem_size_bytes{env="production", mountpoint="/", fstype!="tmpfs"}) * 100
```

**Meaning / 含义:** The root partition on a production VM has exceeded 85% utilization for 10 minutes. Disk space is running low. Identify large files, old logs, or unused packages consuming space. If unchecked, the disk will fill completely, causing service failures and potential data corruption.

**含义：** 生产环境虚拟机的根分区利用率已超过85%持续10分钟。磁盘空间不足。找出占用空间的大文件、旧日志或未使用的软件包。如不处理，磁盘将完全填满，导致服务故障和潜在数据损坏。

### 1. ASSESS / 评估

#### 1.1 Golden Path Impact Check / 黄金流程影响检查

```bash
curl -s "http://localhost:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])" | jq '.data.result[0].value[1]'
```

#### 1.2 Quick Triage / 快速分诊

```bash
INSTANCE="{{ $labels.instance }}"
ssh ec2-user@${INSTANCE%%:*} "df -h / && echo '---' && df -i /"
```

#### 1.3 Severity Classification / 严重程度分类

| Condition / 条件 | Classification / 分类 | Action / 操作 |
|---|---|---|
| Disk 85-90%, stable | Low Warning / 低级警告 | Clean logs within 4 hours |
| Disk 90-95%, growing | High Warning / 高级警告 | Clean immediately, prepare volume extension |
| Inodes > 80% | High Warning / 高级警告 | Find inode consumers (many small files) |
| Database partition filling | High Warning / 高级警告 | Coordinate with DBA team |

### 2. ACKNOWLEDGE / 确认 (Within 15 min / 15 分钟内)

```bash
amtool silence add \
  --alertmanager.url=http://alertmanager:9093 \
  --author="$(whoami)" \
  --comment="Investigating VM disk warning on ${INSTANCE}" \
  --duration=2h \
  alertname=VmDiskUsageWarning instance="${INSTANCE}"
```

**WeCom Notification Template / 企业微信通知模板:**
```
🟡 [ACKNOWLEDGED] VM-05: VmDiskUsageWarning
Instance: {{ $labels.instance }}
Disk: {{ $value }}%
Threshold: 85%
Responder: [Your Name]
ETA: Cleaning up, update in 1 hour
```

### 3. ANALYZE / 分析

#### 3.1 Common Causes / 常见原因

- **Log file growth / 日志文件增长:** Application or system logs not rotated
- **Docker/container images / Docker/容器镜像:** Old images and layers accumulating
- **Core dumps / 核心转储:** Application crashes generating large core files
- **Temp files / 临时文件:** Build artifacts, temp downloads not cleaned
- **Database WAL/binlog / 数据库WAL/binlog:** If local DB, transaction logs growing

#### 3.2 Diagnostic Commands / 诊断命令

```bash
ssh ec2-user@${INSTANCE%%:*}

# Disk usage overview
# 磁盘使用概览
df -h

# Find largest directories
# 查找最大目录
du -sh /* 2>/dev/null | sort -rh | head -10

# Find largest files (> 100MB)
# 查找最大文件（> 100MB）
find / -type f -size +100M -exec ls -lh {} \; 2>/dev/null | sort -k5 -rh | head -20

# Check log directory sizes
# 检查日志目录大小
du -sh /var/log/* 2>/dev/null | sort -rh | head -10

# Check Docker disk usage (if applicable)
# 检查Docker磁盘使用（如适用）
docker system df 2>/dev/null

# Check inode usage
# 检查inode使用
df -i

# Find directories with most files (inode consumers)
# 查找文件最多的目录（inode消耗者）
find / -xdev -type d -exec sh -c 'echo "$(find "$1" -maxdepth 1 | wc -l) $1"' _ {} \; 2>/dev/null | sort -rn | head -10

# Check deleted but open files (space not reclaimed)
# 检查已删除但仍打开的文件（空间未回收）
lsof +L1 2>/dev/null | head -20
```

#### 3.3 VMAlert Endpoint Verification / VMAlert 节点验证

```bash
curl -s "http://10.238.3.153:8880/api/v1/alerts" | jq '.data.alerts[] | select(.labels.alertname=="VmDiskUsageWarning")'
```

#### 3.4 PromQL Deep Dive / PromQL 深入查询

```promql
# Disk usage trend over 24 hours
lckna:vm:disk_util{instance="${INSTANCE}"}[24h]

# Predict when disk will be full (linear prediction 24h)
predict_linear(node_filesystem_avail_bytes{instance="${INSTANCE}", mountpoint="/", fstype!="tmpfs"}[6h], 24*3600) < 0
```

**Dashboard:** [VM Disk](https://grafana.luckinus.com/d/vm-disk)

### 4. ACT / 处置

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---|---|---|
| Old logs | `find /var/log -name "*.gz" -mtime +7 -delete` | On-call DevOps |
| Docker images | `docker system prune -af --volumes` | On-call DevOps |
| Core dumps | `find / -name "core.*" -delete` | On-call DevOps |
| Deleted open files | Restart service holding the file | On-call DevOps |
| Legitimate growth | Extend EBS volume | Team Lead approval |

```bash
# Clean old compressed logs (> 7 days)
# 清理旧的压缩日志（> 7天）
find /var/log -name "*.gz" -mtime +7 -delete
find /var/log -name "*.log.*" -mtime +7 -delete

# Clean journal logs (keep last 2 days)
# 清理journal日志（保留最近2天）
journalctl --vacuum-time=2d

# Clean Docker (if applicable)
# 清理Docker（如适用）
docker system prune -af --volumes 2>/dev/null

# Extend EBS volume (non-disruptive for ext4/xfs)
# 扩展EBS卷（对ext4/xfs无中断）
# Step 1: Modify volume in AWS Console or CLI
# aws ec2 modify-volume --volume-id <vol-id> --size <new-size-gb>
# Step 2: Grow filesystem
# sudo growpart /dev/xvda 1
# sudo resize2fs /dev/xvda1   # ext4
# sudo xfs_growfs /            # xfs

# Verify disk usage after cleanup
# 清理后验证磁盘使用
df -h /
```

### 5. AFTERMATH / 善后

- [ ] Verify disk < 85% after cleanup / 验证清理后磁盘低于85%
- [ ] Remove alert silence / 移除告警静默
- [ ] Post WeCom resolution summary / 发布解决摘要
- [ ] Set up log rotation if missing / 如缺失则设置日志轮转
- [ ] Configure logrotate for application logs / 为应用日志配置logrotate
- [ ] If volume extended: update capacity tracking / 如扩展了卷：更新容量跟踪
- [ ] Related alerts: VM-06 (Disk Critical) — ensure not approaching / 相关告警：VM-06 (磁盘严重) — 确保未接近

**Old Alert Reference / 旧告警参考:** ALR-111 (Disk Usage > 85%) → Kept as LCK-VM-005

---

<a id="lck-vm-006"></a>
## VM-06: VmDiskUsageCritical / VM 磁盘使用率过高（严重级）

```yaml
alert_id: LCK-VM-006
alert_name: VmDiskUsageCritical
old_ids: [ALR-104, ALR-105, ALR-111]
consolidation: MERGE
severity: critical
tier: "1"
category: INFRA-VM
team: sys-ops
first_responder: US DevOps On-Call + Team Lead
sla_response: 5 min acknowledge / 15 min first update / 1 hour resolution
notification_channel: wecom+twilio-all
skill_reference: /app/skills/ec2-alert-investigation.md
dashboard: vm-disk
last_updated: 2026-02-16
```

### Alert Rule / 报警规则

```yaml
alert: VmDiskUsageCritical
expr: lckna:vm:disk_util > 95
for: 5m
labels:
  severity: critical
  tier: "1"
  category: infra-vm
  team: sys-ops
  dashboard: vm-disk
annotations:
  summary: "VM disk CRITICAL on {{ $labels.instance }}"
  description: "Root partition is {{ $value | printf \"%.1f\" }}% full (threshold: 95%) for 5 minutes on {{ $labels.instance }}. Emergency cleanup required."
  runbook_url: "https://runbooks.luckinus.com/infra-vm/vm-disk-critical"
  dashboard_url: "https://grafana.luckinus.com/d/vm-disk"
```

### PromQL Expression / PromQL 表达式

```promql
lckna:vm:disk_util > 95
```

**Meaning / 含义:** The root partition has exceeded 95% capacity. The filesystem is nearly full and services will begin failing (unable to write logs, create temp files, or write data). Emergency cleanup is required immediately. If the disk reaches 100%, services will crash and data may be corrupted.

**含义：** 根分区已超过95%容量。文件系统几乎已满，服务将开始失败（无法写入日志、创建临时文件或写入数据）。需要立即进行紧急清理。如果磁盘达到100%，服务将崩溃且数据可能损坏。

### 1. ASSESS / 评估

#### 1.1 Golden Path Impact Check / 黄金流程影响检查

```bash
# CRITICAL: Check immediately
curl -s "http://localhost:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])" | jq '.data.result[0].value[1]'
```

#### 1.2 Quick Triage / 快速分诊

```bash
INSTANCE="{{ $labels.instance }}"
# Check exact usage and available space
ssh ec2-user@${INSTANCE%%:*} "df -h / && echo '---Inodes---' && df -i / && echo '---Largest files---' && find / -type f -size +100M -exec ls -lh {} \; 2>/dev/null | sort -k5 -rh | head -5"
```

### 2. ACKNOWLEDGE / 确认 (Within 5 min / 5 分钟内)

```bash
amtool silence add \
  --alertmanager.url=http://alertmanager:9093 \
  --author="$(whoami)" \
  --comment="CRITICAL: VM disk > 95% on ${INSTANCE}, emergency cleanup" \
  --duration=30m \
  alertname=VmDiskUsageCritical instance="${INSTANCE}"
```

**WeCom Notification Template / 企业微信通知模板:**
```
🔴 [CRITICAL] VM-06: VmDiskUsageCritical
Instance: {{ $labels.instance }}
Disk: {{ $value }}%
Threshold: 95% — services may fail
Responder: [Your Name]
Action: Emergency cleanup in progress
ETA: First update in 15 min
```

### 3. ANALYZE / 分析

#### 3.1 Common Causes / 常见原因

- **Unrotated logs / 未轮转的日志:** Application writing unbounded log files
- **Database binlog / 数据库binlog:** MySQL binary logs consuming all space
- **Core dump storm / 核心转储风暴:** Application crashing repeatedly, generating core files
- **Inode exhaustion / Inode耗尽:** Millions of small files (session files, mail queue)
- **Read-only filesystem / 只读文件系统:** Disk errors causing remount as read-only

#### 3.2 Diagnostic Commands / 诊断命令

```bash
ssh ec2-user@${INSTANCE%%:*}

# Quick space assessment
df -h / && df -i /

# Check if filesystem is read-only
mount | grep "on / " | grep -o "r[ow]"

# Find space hogs fast
du -sh /var/log /tmp /var/lib/docker /var/lib/mysql 2>/dev/null

# Find largest files created in last 24 hours
find / -type f -mtime -1 -size +50M -exec ls -lh {} \; 2>/dev/null | sort -k5 -rh | head -10

# Check deleted but open files
lsof +L1 2>/dev/null | awk '{sum+=$7} END {printf "Deleted but open: %.0f MB\n", sum/1024/1024}'
```

#### 3.3 VMAlert Endpoint Verification / VMAlert 节点验证

```bash
curl -s "http://10.238.3.153:8880/api/v1/alerts" | jq '.data.alerts[] | select(.labels.alertname=="VmDiskUsageCritical")'
```

### 4. ACT / 处置

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---|---|---|
| Large log files | Truncate: `> /var/log/large.log` | On-call DevOps |
| Deleted open files | Restart service to release space | On-call DevOps |
| Docker storage | `docker system prune -af --volumes` | On-call DevOps |
| Inode exhaustion | Find and remove small file directories | On-call DevOps |
| Read-only filesystem | `fsck` (requires downtime) or replace | Team Lead + China HQ |
| Need more space NOW | Extend EBS volume online | On-call DevOps (emergency) |

```bash
# EMERGENCY CLEANUP — execute in order of impact
# 紧急清理 — 按影响顺序执行

# 1. Truncate large log files (don't delete — keeps fd open)
# 1. 截断大日志文件（不要删除——保持fd打开）
find /var/log -name "*.log" -size +100M -exec sh -c '> "$1"' _ {} \;

# 2. Clean old logs
# 2. 清理旧日志
find /var/log -name "*.gz" -delete
journalctl --vacuum-size=100M

# 3. Clean temp files
# 3. 清理临时文件
find /tmp -type f -mtime +1 -delete

# 4. Clean Docker (if applicable)
# 4. 清理Docker（如适用）
docker system prune -af --volumes 2>/dev/null

# 5. If still critical, extend EBS volume
# 5. 如仍然严重，扩展EBS卷
# aws ec2 modify-volume --volume-id <vol-id> --size <new-size>
# sudo growpart /dev/xvda 1 && sudo resize2fs /dev/xvda1

# Verify
df -h /
```

**Escalation / 升级:**
```
Tier 3 (Critical) — All US DevOps + China HQ notified immediately
If read-only filesystem → May require instance replacement
如果只读文件系统 → 可能需要替换实例
```

### 5. AFTERMATH / 善后

- [ ] Verify disk < 85% / 验证磁盘低于85%
- [ ] Remove alert silence / 移除告警静默
- [ ] Post WeCom resolution summary / 发布解决摘要
- [ ] Set up logrotate if missing / 如缺失则设置logrotate
- [ ] Set up disk usage monitoring cron job / 设置磁盘使用监控定时任务
- [ ] Conduct post-incident review / 进行事后回顾
- [ ] File capacity planning ticket for volume extension / 提交卷扩展容量规划工单
- [ ] Related alerts: VM-05 (Disk Warning) should resolve / 相关告警：VM-05 (磁盘警告) 应恢复

**Old Alert Reference / 旧告警参考:** ALR-104 (Disk Full), ALR-105 (Inode Full), ALR-111 (Disk > 85%) → Merged into LCK-VM-006

---

<a id="lck-vm-007"></a>
## VM-07: VmNetworkErrorsWarning / VM 网络错误（警告级）

```yaml
alert_id: LCK-VM-007
alert_name: VmNetworkErrorsWarning
old_ids: [ALR-108, ALR-112, ALR-113, ALR-114, ALR-115]
consolidation: MERGE
severity: warning
tier: "2"
category: INFRA-VM
team: sys-ops
first_responder: US DevOps On-Call
sla_response: 15 min acknowledge / 1 hour first update / 4 hours resolution
notification_channel: wecom+twilio-lead
skill_reference: /app/skills/ec2-alert-investigation.md
dashboard: vm-network
last_updated: 2026-02-16
```

### Alert Rule / 报警规则

```yaml
alert: VmNetworkErrorsWarning
expr: lckna:vm:net_errors_rate5m > 200 or rate(node_network_receive_drop_total{env="production"}[5m]) > 20
for: 5m
labels:
  severity: warning
  tier: "2"
  category: infra-vm
  team: sys-ops
  dashboard: vm-network
annotations:
  summary: "VM network errors on {{ $labels.instance }}"
  description: "Network errors ({{ $value }}/s) or packet drops exceed threshold on {{ $labels.instance }}."
  runbook_url: "https://runbooks.luckinus.com/infra-vm/vm-network-errors"
  dashboard_url: "https://grafana.luckinus.com/d/vm-network"
```

### PromQL Expression / PromQL 表达式

```promql
# Two conditions (OR):
# 1. Network errors (rx+tx) > 200/s
lckna:vm:net_errors_rate5m > 200

# 2. Packet drops > 20/s
rate(node_network_receive_drop_total{env="production"}[5m]) > 20
```

**Meaning / 含义:** The production VM is experiencing either high network error rates (> 200 errors/second for TX+RX combined) or significant packet drops (> 20 drops/second) for at least 5 minutes. This may indicate NIC issues, MTU mismatches, network congestion, or underlying infrastructure problems. Can cause application timeouts and failed requests.

**含义：** 生产环境虚拟机正经历高网络错误率（TX+RX合计 > 200错误/秒）或显著丢包（> 20丢包/秒）持续至少5分钟。这可能表示网卡问题、MTU不匹配、网络拥塞或底层基础设施问题。可能导致应用超时和请求失败。

### 1. ASSESS / 评估

#### 1.1 Golden Path Impact Check / 黄金流程影响检查

```bash
curl -s "http://localhost:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])" | jq '.data.result[0].value[1]'
```

#### 1.2 Quick Triage / 快速分诊

```bash
INSTANCE="{{ $labels.instance }}"
# Check which condition triggered
curl -s "http://localhost:9090/api/v1/query?query=lckna:vm:net_errors_rate5m{instance='${INSTANCE}'}" | jq '.data.result[0].value[1]'
curl -s "http://localhost:9090/api/v1/query?query=rate(node_network_receive_drop_total{instance='${INSTANCE}',env='production'}[5m])" | jq '.data.result[0].value[1]'
```

#### 1.3 Severity Classification / 严重程度分类

| Condition / 条件 | Classification / 分类 | Action / 操作 |
|---|---|---|
| Errors 200-500/s, no app impact | Low Warning / 低级警告 | Monitor, investigate when convenient |
| Errors > 500/s or drops > 50/s | High Warning / 高级警告 | Investigate immediately |
| Multiple instances affected | Potential infra issue / 潜在基础设施问题 | Escalate to AWS support |
| Application timeouts observed | → Treat as Tier 3 / 按Tier 3处理 | Immediate escalation |

### 2. ACKNOWLEDGE / 确认 (Within 15 min / 15 分钟内)

```bash
amtool silence add \
  --alertmanager.url=http://alertmanager:9093 \
  --author="$(whoami)" \
  --comment="Investigating VM network errors on ${INSTANCE}" \
  --duration=1h \
  alertname=VmNetworkErrorsWarning instance="${INSTANCE}"
```

**WeCom Notification Template / 企业微信通知模板:**
```
🟡 [ACKNOWLEDGED] VM-07: VmNetworkErrorsWarning
Instance: {{ $labels.instance }}
Error Rate: {{ $value }}/s
Responder: [Your Name]
ETA: Investigating, update in 30 min
```

### 3. ANALYZE / 分析

#### 3.1 Common Causes / 常见原因

- **MTU mismatch / MTU不匹配:** Jumbo frames between VPC and external networks
- **NIC driver issue / 网卡驱动问题:** ENA driver bug or misconfiguration
- **Network congestion / 网络拥塞:** Bandwidth saturation on the instance
- **Security group rate limit / 安全组速率限制:** Exceeding connection tracking limits
- **AWS infrastructure issue / AWS基础设施问题:** Underlying host or network issue
- **TCP retransmissions / TCP重传:** Application-level timeout/retry storms

#### 3.2 Diagnostic Commands / 诊断命令

```bash
ssh ec2-user@${INSTANCE%%:*}

# Network interface statistics
# 网络接口统计
ip -s link show

# Detailed error breakdown
# 详细错误分解
ethtool -S eth0 2>/dev/null | grep -i "err\|drop\|timeout\|reset"

# Check MTU
# 检查MTU
ip link show | grep mtu

# TCP connection stats
# TCP连接统计
ss -s

# Check for TCP retransmissions
# 检查TCP重传
netstat -s | grep -i "retransmit\|timeout\|reset\|overflow"

# Check conntrack table (if applicable)
# 检查连接跟踪表（如适用）
cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null
cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null

# Bandwidth check
# 带宽检查
sar -n DEV 1 5 2>/dev/null || (apt-get install -y sysstat && sar -n DEV 1 5)

# Check for DNS resolution failures
# 检查DNS解析失败
dig +short google.com @169.254.169.253
```

#### 3.3 VMAlert Endpoint Verification / VMAlert 节点验证

```bash
curl -s "http://10.238.3.153:8880/api/v1/alerts" | jq '.data.alerts[] | select(.labels.alertname=="VmNetworkErrorsWarning")'
```

#### 3.4 PromQL Deep Dive / PromQL 深入查询

```promql
# Error rate by interface
rate(node_network_receive_errs_total{instance="${INSTANCE}", env="production"}[5m])
rate(node_network_transmit_errs_total{instance="${INSTANCE}", env="production"}[5m])

# Drop rate
rate(node_network_receive_drop_total{instance="${INSTANCE}", env="production"}[5m])
rate(node_network_transmit_drop_total{instance="${INSTANCE}", env="production"}[5m])

# Bandwidth utilization
rate(node_network_receive_bytes_total{instance="${INSTANCE}", env="production"}[5m]) * 8
rate(node_network_transmit_bytes_total{instance="${INSTANCE}", env="production"}[5m]) * 8
```

**Dashboard:** [VM Network](https://grafana.luckinus.com/d/vm-network)

### 4. ACT / 处置

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---|---|---|
| MTU mismatch | Adjust MTU: `ip link set eth0 mtu 1500` | On-call DevOps |
| NIC driver issue | Update ENA driver or reboot | Team Lead approval |
| Bandwidth saturation | Rate limit applications or scale | On-call DevOps + App team |
| Conntrack table full | Increase `nf_conntrack_max` | On-call DevOps |
| AWS infrastructure issue | Open AWS support case (Severity 1) | Team Lead |
| Multiple instances affected | Declare incident, AWS support | Team Lead + China HQ |

```bash
# Increase conntrack limit (temporary fix)
# 增加连接跟踪限制（临时修复）
echo 262144 > /proc/sys/net/netfilter/nf_conntrack_max

# Fix MTU if needed
# 如需要修复MTU
ip link set eth0 mtu 1500

# Check if errors cleared
# 检查错误是否清除
sleep 60 && ethtool -S eth0 2>/dev/null | grep -i "err\|drop"
```

### 5. AFTERMATH / 善后

- [ ] Verify error rate < 200/s and drops < 20/s / 验证错误率 < 200/s 且丢包 < 20/s
- [ ] Remove alert silence / 移除告警静默
- [ ] Post WeCom resolution summary / 发布解决摘要
- [ ] If MTU changed: make persistent in network config / 如修改了MTU：在网络配置中持久化
- [ ] If conntrack changed: add to sysctl.conf / 如修改了conntrack：添加到sysctl.conf
- [ ] If AWS issue: track support case / 如AWS问题：跟踪支持案例
- [ ] Related alerts: VM-08 (Instance Down) — may indicate progression / 相关告警：VM-08 (实例宕机) — 可能表示恶化

**Old Alert Reference / 旧告警参考:** ALR-108 (TCP Retransmits), ALR-112 (NIC RX Errors), ALR-113 (NIC TX Errors), ALR-114 (NIC RX Drops), ALR-115 (NIC TX Drops) → Merged into LCK-VM-007

---

<a id="lck-vm-008"></a>
## VM-08: VmInstanceDownCritical / VM 实例宕机（严重级）

```yaml
alert_id: LCK-VM-008
alert_name: VmInstanceDownCritical
old_ids: [ALR-110, ALR-116]
consolidation: MERGE
severity: critical
tier: "1"
category: INFRA-VM
team: sys-ops
first_responder: US DevOps On-Call + Team Lead
sla_response: 5 min acknowledge / 15 min first update / 1 hour resolution
notification_channel: wecom+twilio-all
skill_reference: /app/skills/ec2-alert-investigation.md
dashboard: vm-overview
last_updated: 2026-02-16
```

### Alert Rule / 报警规则

```yaml
alert: VmInstanceDownCritical
expr: up{job="node-exporter", env="production"} == 0
for: 10m
labels:
  severity: critical
  tier: "1"
  category: infra-vm
  team: sys-ops
  dashboard: vm-overview
annotations:
  summary: "VM instance DOWN: {{ $labels.instance }}"
  description: "Instance {{ $labels.instance }} has been unreachable for 10 minutes. Node exporter is not responding."
  runbook_url: "https://runbooks.luckinus.com/infra-vm/vm-instance-down"
  dashboard_url: "https://grafana.luckinus.com/d/vm-overview"
```

### PromQL Expression / PromQL 表达式

```promql
up{job="node-exporter", env="production"} == 0
```

**Meaning / 含义:** The `node_exporter` on a production VM has been unreachable for 10 minutes. The instance may be down, the network may be partitioned, or the exporter process may have crashed. This is the highest severity VM alert because a down instance means all services on that host are unavailable. Determine if the instance is truly down or if only monitoring is affected.

**含义：** 生产环境虚拟机上的 `node_exporter` 已无法访问10分钟。实例可能已宕机、网络可能已隔离、或导出器进程可能已崩溃。这是最高严重级别的VM告警，因为宕机的实例意味着该主机上的所有服务都不可用。确定实例是否真正宕机或仅监控受影响。

### 1. ASSESS / 评估

#### 1.1 Golden Path Impact Check / 黄金流程影响检查

```bash
# CRITICAL: Check golden path FIRST
curl -s "http://localhost:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])" | jq '.data.result[0].value[1]'
```

#### 1.2 Quick Triage / 快速分诊

```bash
INSTANCE="{{ $labels.instance }}"
INSTANCE_IP="${INSTANCE%%:*}"

# Can we reach the instance at all?
# 能否到达实例？
ping -c 3 -W 2 ${INSTANCE_IP}

# Can we SSH?
# 能否SSH？
ssh -o ConnectTimeout=5 ec2-user@${INSTANCE_IP} "hostname && uptime" 2>&1

# Check instance state in AWS
# 在AWS中检查实例状态
aws ec2 describe-instances --filters "Name=private-ip-address,Values=${INSTANCE_IP}" \
  --query "Reservations[0].Instances[0].{ID:InstanceId,State:State.Name,StatusChecks:StatusChecks}" --output table
```

#### 1.3 Severity Classification / 严重程度分类

| Condition / 条件 | Classification / 分类 | Action / 操作 |
|---|---|---|
| Instance responding to SSH | node_exporter down only | Restart node_exporter |
| Instance not responding, AWS shows running | Possible kernel panic / 可能内核恐慌 | Reboot via AWS |
| AWS shows stopped/terminated | Instance actually down | Investigate and restart |
| Multiple instances down | Major incident / 重大事件 | Declare incident, all hands |
| Golden path impacted | Emergency / 紧急 | All DevOps + China HQ |

### 2. ACKNOWLEDGE / 确认 (Within 5 min / 5 分钟内)

```bash
amtool silence add \
  --alertmanager.url=http://alertmanager:9093 \
  --author="$(whoami)" \
  --comment="CRITICAL: Instance ${INSTANCE} is DOWN, investigating" \
  --duration=30m \
  alertname=VmInstanceDownCritical instance="${INSTANCE}"
```

**WeCom Notification Template / 企业微信通知模板:**
```
🔴 [CRITICAL] VM-08: VmInstanceDownCritical
Instance: {{ $labels.instance }}
Status: Instance unreachable for 10+ minutes
Responder: [Your Name]
Action: Immediate investigation
ETA: First update in 15 min
```

### 3. ANALYZE / 分析

#### 3.1 Common Causes / 常见原因

- **Instance terminated/stopped / 实例终止/停止:** Accidental or scheduled termination
- **Kernel panic / 内核恐慌:** OS crash requiring hard reboot
- **OOM kill cascade / OOM kill级联:** OOM killer killed critical processes including systemd
- **EBS volume issue / EBS卷问题:** Root volume detached or impaired
- **Network partition / 网络分区:** Security group change or VPC routing issue
- **node_exporter crash / node_exporter崩溃:** Only monitoring affected, instance is fine
- **AWS maintenance event / AWS维护事件:** Scheduled or unscheduled host maintenance

#### 3.2 Diagnostic Commands / 诊断命令

```bash
INSTANCE_IP="${INSTANCE%%:*}"

# AWS Console checks (from bastion/local)
# AWS控制台检查（从堡垒机/本地）

# Get instance details
INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=private-ip-address,Values=${INSTANCE_IP}" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)

echo "Instance ID: ${INSTANCE_ID}"

# Check instance status
aws ec2 describe-instance-status --instance-ids ${INSTANCE_ID} --output table

# Check system and instance status checks
aws ec2 describe-instance-status --instance-ids ${INSTANCE_ID} \
  --query "InstanceStatuses[0].{System:SystemStatus.Status,Instance:InstanceStatus.Status}" --output table

# Check for scheduled events
aws ec2 describe-instance-status --instance-ids ${INSTANCE_ID} \
  --query "InstanceStatuses[0].Events" --output table

# Check CloudWatch system metrics
aws cloudwatch get-metric-statistics --namespace AWS/EC2 \
  --metric-name StatusCheckFailed --dimensions Name=InstanceId,Value=${INSTANCE_ID} \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 --statistics Maximum

# If SSH works — check node_exporter
# 如果SSH可用 — 检查node_exporter
ssh ec2-user@${INSTANCE_IP} "
  systemctl status node_exporter
  journalctl -u node_exporter --since '30 minutes ago' --no-pager | tail -20
  curl -s http://localhost:9100/metrics | head -5
"
```

#### 3.3 VMAlert Endpoint Verification / VMAlert 节点验证

```bash
curl -s "http://10.238.3.153:8880/api/v1/alerts" | jq '.data.alerts[] | select(.labels.alertname=="VmInstanceDownCritical")'
```

#### 3.4 Check Related Services / 检查相关服务

```bash
# What services were running on this instance?
# 该实例上运行了哪些服务？
# Check Kubernetes pods if this was an EKS node
kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=${INSTANCE_IP} 2>/dev/null

# Check if other instances in same AZ are affected
# 检查同一可用区的其他实例是否受影响
aws ec2 describe-instances --instance-ids ${INSTANCE_ID} \
  --query "Reservations[0].Instances[0].Placement.AvailabilityZone" --output text
```

### 4. ACT / 处置

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---|---|---|
| node_exporter down only | `ssh & systemctl restart node_exporter` | On-call DevOps |
| Instance hung (SSH timeout) | Reboot: `aws ec2 reboot-instances` | On-call DevOps |
| Instance stopped | Start: `aws ec2 start-instances` | On-call DevOps |
| Instance terminated | Investigate, launch replacement | Team Lead |
| System status check failed | Stop & start (moves to new host) | On-call DevOps |
| Kernel panic (serial console) | Force reboot: `aws ec2 stop-instances --force` | Team Lead |
| Multiple instances / AZ issue | Declare incident, failover to other AZ | Team Lead + China HQ |

```bash
# Restart node_exporter (if SSH works)
# 重启node_exporter（如果SSH可用）
ssh ec2-user@${INSTANCE_IP} "sudo systemctl restart node_exporter && systemctl status node_exporter"

# Reboot instance (if instance is hung)
# 重启实例（如果实例挂起）
aws ec2 reboot-instances --instance-ids ${INSTANCE_ID}
echo "Waiting for instance to reboot..."
aws ec2 wait instance-status-ok --instance-ids ${INSTANCE_ID}

# Force stop and start (moves to new host hardware)
# 强制停止和启动（迁移到新主机硬件）
# WARNING: IP address may change if not using Elastic IP
# 警告：如果未使用弹性IP，IP地址可能改变
# aws ec2 stop-instances --instance-ids ${INSTANCE_ID} --force
# aws ec2 wait instance-stopped --instance-ids ${INSTANCE_ID}
# aws ec2 start-instances --instance-ids ${INSTANCE_ID}

# Start a stopped instance
# 启动已停止的实例
# aws ec2 start-instances --instance-ids ${INSTANCE_ID}
# aws ec2 wait instance-running --instance-ids ${INSTANCE_ID}

# Verify instance is back and node_exporter responding
# 验证实例恢复且node_exporter响应
sleep 60
curl -s "http://${INSTANCE_IP}:9100/metrics" | head -5 && echo "node_exporter is UP" || echo "node_exporter still DOWN"
```

**Escalation / 升级:**
```
Tier 3 (Critical) — All US DevOps + China HQ notified immediately
Multiple instances down → Major incident declaration
多实例宕机 → 宣布重大事件

If AZ-level issue → AWS support case (Severity 1 / Business Critical)
如果是可用区级别问题 → AWS支持案例（严重性1/业务关键）
```

### 5. AFTERMATH / 善后

- [ ] Verify `up{instance="${INSTANCE}"}` == 1 for 15 minutes / 验证实例恢复15分钟
- [ ] Remove alert silence / 移除告警静默
- [ ] Post WeCom resolution summary with root cause / 发布含根因的解决摘要
- [ ] Verify all services on the instance are healthy / 验证实例上所有服务健康
- [ ] Check for any data loss or inconsistency / 检查是否有数据丢失或不一致
- [ ] If instance rebooted: check system logs for crash cause / 如重启了实例：检查系统日志查找崩溃原因
  ```bash
  ssh ec2-user@${INSTANCE_IP} "journalctl --since '1 hour ago' | grep -iE 'panic|error|crash|oom|killed' | head -20"
  ```
- [ ] If replaced/started: update monitoring config if IP changed / 如替换/启动：如IP变化则更新监控配置
- [ ] Conduct post-incident review for prolonged outage / 对长时间中断进行事后回顾
- [ ] Update runbook if new failure mode discovered / 如发现新故障模式则更新运维手册
- [ ] Related alerts: ALL VM alerts for this instance should resolve when instance recovers / 相关告警：该实例的所有VM告警在实例恢复时应全部恢复

**Old Alert Reference / 旧告警参考:** ALR-110 (Instance Heartbeat Lost), ALR-116 (NIC Down) → Merged into LCK-VM-008

---

## Cross-Reference: Old Alert ID Mapping / 旧告警ID映射

| Old Alert ID | Old Alert Name | New Alert ID | New Alert Name |
|---|---|---|---|
| ALR-100 | EC2 CPU > 80% | LCK-VM-001 | VmCpuUsageWarning |
| ALR-101 | EC2 CPU > 85% | LCK-VM-001 | VmCpuUsageWarning |
| ALR-102 | EC2 CPU > 90% | LCK-VM-002 | VmCpuUsageCritical |
| ALR-103 | EC2 CPU > 95% | LCK-VM-002 | VmCpuUsageCritical |
| ALR-104 | Disk Full | LCK-VM-006 | VmDiskUsageCritical |
| ALR-105 | Inode Full | LCK-VM-006 | VmDiskUsageCritical |
| ALR-106 | CPU IOWait > 80% | LCK-VM-002 | VmCpuUsageCritical |
| ALR-107 | CPU Load > Cores | LCK-VM-001 | VmCpuUsageWarning |
| ALR-108 | TCP Retransmits | LCK-VM-007 | VmNetworkErrorsWarning |
| ALR-109 | Host Memory > 85% | LCK-VM-003 / LCK-VM-004 | VmMemoryUsageWarning / VmMemoryUsageCritical |
| ALR-110 | Instance Heartbeat Lost | LCK-VM-008 | VmInstanceDownCritical |
| ALR-111 | Disk Usage > 85% | LCK-VM-005 / LCK-VM-006 | VmDiskUsageWarning / VmDiskUsageCritical |
| ALR-112 | NIC RX Errors | LCK-VM-007 | VmNetworkErrorsWarning |
| ALR-113 | NIC TX Errors | LCK-VM-007 | VmNetworkErrorsWarning |
| ALR-114 | NIC RX Drops | LCK-VM-007 | VmNetworkErrorsWarning |
| ALR-115 | NIC TX Drops | LCK-VM-007 | VmNetworkErrorsWarning |
| ALR-116 | NIC Down | LCK-VM-008 | VmInstanceDownCritical |

---

*End of Part 7: INFRA-VM (VM/Host) — 8 alerts covering CPU, Memory, Disk, Network, and Instance availability.*
*第7部分结束：基础设施-虚拟机/主机 — 8个告警覆盖CPU、内存、磁盘、网络和实例可用性。*

# Luckin Coffee NA — Alert Runbook Part 6: INFRA-K8S (Kubernetes/EKS)

# 瑞幸咖啡北美 — 报警运行手册 第6部分：INFRA-K8S（Kubernetes/EKS）

> **Version / 版本:** 1.0 | **Category / 分类:** INFRA-K8S | **Alerts / 报警数:** 7
> **Cluster / 集群:** luckyus-prod | **Region / 区域:** us-east-1 | **Account:** 257394478466
> **Pattern / 模式:** 5A (Assess → Acknowledge → Analyze → Act → Aftermath)
> **Last Updated / 最后更新:** 2026-02-16

---

## Category Overview / 分类概览

This runbook covers 7 Kubernetes/EKS alerts for the `luckyus-prod` EKS cluster in production.
本手册涵盖生产环境 `luckyus-prod` EKS 集群的 7 条 Kubernetes 报警。

### Recording Rules / 预计算规则

These recording rules are evaluated every 30 seconds and used by K8S-01 through K8S-05.
以下预计算规则每 30 秒评估一次，供 K8S-01 至 K8S-05 使用。

| Record Name | Expression | Used By |
|-------------|-----------|---------|
| `lckna:k8s:pod_cpu_avg3m` | `avg_over_time((rate(container_cpu_usage_seconds_total{env="production", container!="POD", container!=""}[1m]))[3m:]) * 100` | K8S-01, K8S-02, K8S-03 |
| `lckna:k8s:pod_disk_io_rate` | `rate(container_fs_reads_bytes_total{...}[3m]) + rate(container_fs_writes_bytes_total{...}[3m])` | K8S-05 |
| `lckna:k8s:pod_network_rate` | `rate(container_network_receive_bytes_total{...}[3m]) + rate(container_network_transmit_bytes_total{...}[3m])` | (reserved) |

### Alert Summary / 报警汇总

| ID | Name | Severity | Tier | Threshold | For | Old IDs | Action |
|----|------|----------|------|-----------|-----|---------|--------|
| LCK-K8-001 | PodCpuHigh_Info | info | 3 | >50% <=70% | 10m | ALR-090 | KEEP |
| LCK-K8-002 | PodCpuHigh_Warning | warning | 2 | >70% <=85% | 5m | ALR-091 | KEEP |
| LCK-K8-003 | PodCpuHigh_Critical | critical | 1 | >85% | 3m | ALR-089 | KEEP |
| LCK-K8-004 | PodRestart_Warning | warning | 2 | >1 restart/2min | 5m | ALR-093 | KEEP |
| LCK-K8-005 | PodDiskIO_Warning | warning | 3 | >50MB/s | 5m | ALR-096, ALR-097 | MERGE |
| LCK-K8-006 | PodOOM_Critical | critical | 1 | OOM event | 0m | ALR-094 | KEEP |
| LCK-K8-007 | NodeHeartbeatLost_Critical | critical | 1 | Node NotReady | 5m | ALR-092 | KEEP |

### Alert Chains / 报警链

```
CPU Escalation / CPU 升级链:
  K8S-01 (info >50%) → K8S-02 (warning >70%) → K8S-03 (critical >85%)

OOM causes Restart / OOM 导致重启:
  K8S-06 (OOM killed) → K8S-04 (pod restart)

Node Loss causes Restart / 节点丢失导致重启:
  K8S-07 (node heartbeat lost) → K8S-04 (pod restart during rescheduling)
```

---

## K8S-01: PodCpuHigh_Info / Pod CPU 偏高（信息级）

```yaml
alert_id: "LCK-K8-001"
alert_name: "K8sPodCpuUsageInfo"
old_ids: "ALR-090"
severity: "info"
tier: "3"
category: "infra-k8s"
team: "k8s-ops"
first_responder: "k8s-ops on-call"
sla_response: "30 min"
notification_channel: "wecom-only"
skill_reference: "/app/skills/k8s-alert-investigation.md"
last_updated: "2026-02-16"
```

### Alert Rule / 报警规则

```yaml
alert: K8sPodCpuUsageInfo
expr: |
  lckna:k8s:pod_cpu_avg3m > 50 and lckna:k8s:pod_cpu_avg3m <= 70
for: 10m
```

**Meaning / 含义:** Pod CPU usage (3-minute smoothed average) has been between 50% and 70% for 10 minutes. This is an early warning to monitor the trend and verify HPA configuration.
Pod CPU 使用率（3 分钟平滑均值）在 50%-70% 之间持续 10 分钟。这是一个早期预警，用于监控趋势并验证 HPA 配置。

### 1. ASSESS / 评估 (First 2 Minutes / 前 2 分钟)

```bash
# Golden path check — are orders flowing? / 黄金路径检查 — 订单是否正常流转？
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"

# Which pods are CPU-elevated? / 哪些 Pod CPU 偏高？
kubectl top pods -n production --sort-by=cpu | head -20

# Check HPA status / 检查 HPA 状态
kubectl get hpa -n production | grep -i "$(echo $LABELS_POD | cut -d- -f1-2)"
```

| Condition / 条件 | Severity / 严重度 | Action / 操作 |
|-----------|----------|--------|
| Golden path impacted / 黄金路径受影响 | Critical -> Tier 1 | Wake China HQ / 通知中国总部 |
| Pod degraded, orders OK / Pod 退化但订单正常 | Warning -> Tier 2 | US DevOps handles / 美国运维处理 |
| CPU elevated, no impact / CPU 偏高无影响 | Info -> Tier 3 | Monitor only / 仅监控 |

### 2. ACKNOWLEDGE / 确认 (Within 30 min / 30 分钟内)

```bash
# Silence alert (1h for info) / 静默报警（信息级 1 小时）
amtool silence add alertname="K8sPodCpuUsageInfo" \
  --duration="1h" --comment="Investigating - YOUR_NAME" --author="YOUR_NAME"
```

Post to WeCom / 发送到企业微信:
```
Alert Acknowledged / 报警已确认
Alert: K8sPodCpuUsageInfo (LCK-K8-001)
Severity: info | Tier: 3
Owner: {your_name}
Status: Investigating / 调查中
```

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
```
[ ] Traffic spike (check request rate) / 流量激增（检查请求速率）
[ ] HPA disabled or misconfigured / HPA 未启用或配置错误
[ ] CPU request/limit set too low / CPU request/limit 设置过低
[ ] Deployment with new resource-heavy code / 部署了高资源消耗的新代码
[ ] Background batch job running / 后台批量任务运行中
[ ] Other pod on same node consuming resources / 同节点其他 Pod 抢占资源
```

```bash
# Detailed pod resource usage / 详细 Pod 资源使用
kubectl top pods -n production -l app=SERVICE_NAME --sort-by=cpu

# Check CPU limits and requests / 检查 CPU limits 和 requests
kubectl get pods -n production -l app=SERVICE_NAME -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].resources}{"\n"}{end}'

# Recent deployments / 最近部署
kubectl get events -n production --sort-by='.lastTimestamp' --field-selector reason=Pulling | tail -10

# PromQL — CPU trend (Prometheus datasource: df8o21agxtkw0d)
# lckna:k8s:pod_cpu_avg3m{pod=~"SERVICE_NAME.*"}
```

Dashboard: `https://grafana.luckinus.com/d/k8s-pods?var-pod=POD_NAME&from=now-1h&to=now`

### 4. ACT / 处置 (Tier 3 — Monitor, non-disruptive / 仅监控，非破坏性操作)

```bash
# If HPA exists, verify it can scale / 如果 HPA 存在，验证其是否可以扩容
kubectl describe hpa SERVICE_NAME-hpa -n production

# If HPA maxReplicas is too low, consider increasing / 如果 maxReplicas 过低，考虑增加
# (Tier 2+ approval required for changes / 变更需要 Tier 2+ 批准)

# Monitor trend for 15 minutes / 监控趋势 15 分钟
watch -n 30 "kubectl top pods -n production -l app=SERVICE_NAME --sort-by=cpu"
```

**Escalation / 升级路径:**
```
Tier 3 (Info) → (15 min no resolution / 15 分钟未解决) → Tier 2
```

### 5. AFTERMATH / 善后

- [ ] Verify CPU returned below 50% / 确认 CPU 回到 50% 以下
- [ ] Review HPA configuration adequacy / 审查 HPA 配置是否充分
- [ ] Check if threshold (50%) needs adjustment / 检查阈值（50%）是否需要调整
- [ ] Update runbook if new cause found / 如发现新原因更新手册

---

## K8S-02: PodCpuHigh_Warning / Pod CPU 过高（警告级）

```yaml
alert_id: "LCK-K8-002"
alert_name: "K8sPodCpuUsageWarning"
old_ids: "ALR-091"
severity: "warning"
tier: "2"
category: "infra-k8s"
team: "k8s-ops"
first_responder: "k8s-ops on-call"
sla_response: "15 min"
notification_channel: "wecom+twilio-lead"
skill_reference: "/app/skills/k8s-alert-investigation.md"
last_updated: "2026-02-16"
```

### Alert Rule / 报警规则

```yaml
alert: K8sPodCpuUsageWarning
expr: |
  lckna:k8s:pod_cpu_avg3m > 70 and lckna:k8s:pod_cpu_avg3m <= 85
for: 5m
```

**Meaning / 含义:** Pod CPU usage (3-minute average) is between 70% and 85% for 5 minutes. CPU throttling is likely occurring, and horizontal scaling is recommended.
Pod CPU 使用率（3 分钟均值）在 70%-85% 之间持续 5 分钟。很可能正在发生 CPU 节流，建议水平扩容。

### 1. ASSESS / 评估 (First 2 Minutes / 前 2 分钟)

```bash
# Golden path check / 黄金路径检查
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"

# Identify affected pods / 识别受影响的 Pod
kubectl top pods -n production --sort-by=cpu | head -20

# Check for CPU throttling / 检查 CPU 节流
kubectl get pods -n production -l app=SERVICE_NAME -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[*].lastState}{"\n"}{end}'
```

| Condition / 条件 | Severity / 严重度 | Action / 操作 |
|-----------|----------|--------|
| Golden path impacted / 黄金路径受影响 | Critical -> Tier 1 | Wake China HQ / 通知中国总部 |
| Service degraded, golden path OK / 服务退化但订单正常 | Warning -> Tier 2 | Scale out + notify lead / 扩容并通知负责人 |
| CPU high, no user impact / CPU 高但无用户影响 | Info -> Tier 3 | Monitor / 监控 |

### 2. ACKNOWLEDGE / 确认 (Within 15 min / 15 分钟内)

```bash
# Silence alert (30m for warning) / 静默报警（警告级 30 分钟）
amtool silence add alertname="K8sPodCpuUsageWarning" \
  --duration="30m" --comment="Investigating - YOUR_NAME" --author="YOUR_NAME"
```

Post to WeCom / 发送到企业微信:
```
Alert Acknowledged / 报警已确认
Alert: K8sPodCpuUsageWarning (LCK-K8-002)
Severity: warning | Tier: 2
Owner: {your_name}
Status: Investigating / 调查中
ETA: {time + 15min}
```

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
```
[ ] Request volume exceeding pod capacity / 请求量超过 Pod 容量
[ ] HPA not scaling fast enough / HPA 扩容不够快
[ ] CPU limit too restrictive / CPU limit 过于限制
[ ] Memory leak causing excessive GC CPU / 内存泄漏导致 GC 过度使用 CPU
[ ] New deployment with regression / 新部署存在性能回退
[ ] Dependent service timeout causing retry storms / 依赖服务超时导致重试风暴
```

```bash
# Check HPA current state / 检查 HPA 当前状态
kubectl get hpa -n production | grep SERVICE_NAME
kubectl describe hpa SERVICE_NAME-hpa -n production

# Pod describe for events / Pod 描述查看事件
kubectl describe pod POD_NAME -n production | tail -30

# Check for throttling via cgroup / 通过 cgroup 检查节流
kubectl exec -it POD_NAME -n production -- cat /sys/fs/cgroup/cpu/cpu.stat 2>/dev/null || echo "cgroup v2"

# Recent rollouts / 最近的滚动更新
kubectl rollout history deployment/SERVICE_NAME -n production | tail -5

# PromQL — CPU trend (datasource: df8o21agxtkw0d)
# lckna:k8s:pod_cpu_avg3m{pod=~"SERVICE_NAME.*"}
```

Dashboard: `https://grafana.luckinus.com/d/k8s-pods?var-pod=POD_NAME&from=now-1h&to=now`

### 4. ACT / 处置 (Tier 2 — Scale and remediate / 扩容和修复)

```bash
# Scale out pods / 扩容 Pod
kubectl scale deployment/SERVICE_NAME -n production --replicas=NEW_COUNT

# Or adjust HPA max replicas / 或调整 HPA 最大副本数
kubectl patch hpa SERVICE_NAME-hpa -n production -p '{"spec":{"maxReplicas":NEW_MAX}}'

# If caused by bad deployment, rollback / 如因问题部署导致，回滚
kubectl rollout undo deployment/SERVICE_NAME -n production

# Monitor rollout / 监控滚动更新
kubectl rollout status deployment/SERVICE_NAME -n production --timeout=300s
```

**Escalation / 升级路径:**
```
Tier 2 (Warning) → (30 min no resolution / 30 分钟未解决) → Tier 1 → China HQ
```

### 5. AFTERMATH / 善后

- [ ] Verify CPU returned below 70% / 确认 CPU 回到 70% 以下
- [ ] Review and adjust HPA min/max replicas / 审查并调整 HPA 最小/最大副本数
- [ ] Check if CPU request/limit needs increase / 检查 CPU request/limit 是否需要增加
- [ ] File incident report if Tier 2+ escalation / 如升级到 Tier 2+ 则提交事件报告
- [ ] Update deployment resource profiles / 更新部署资源配置

---

## K8S-03: PodCpuHigh_Critical / Pod CPU 严重过高（紧急级）

```yaml
alert_id: "LCK-K8-003"
alert_name: "K8sPodCpuUsageCritical"
old_ids: "ALR-089"
severity: "critical"
tier: "1"
category: "infra-k8s"
team: "k8s-ops"
first_responder: "k8s-ops on-call"
sla_response: "5 min"
notification_channel: "wecom+twilio-all"
skill_reference: "/app/skills/k8s-alert-investigation.md"
last_updated: "2026-02-16"
```

### Alert Rule / 报警规则

```yaml
alert: K8sPodCpuUsageCritical
expr: |
  lckna:k8s:pod_cpu_avg3m > 85
for: 3m
```

**Meaning / 含义:** Pod CPU usage (3-minute average) exceeds 85% for 3 minutes. Heavy CPU throttling is occurring, request failures are likely, and immediate scaling or rollback is required.
Pod CPU 使用率（3 分钟均值）超过 85% 持续 3 分钟。正在发生严重 CPU 节流，请求可能失败，需要立即扩容或回滚。

### 1. ASSESS / 评估 (First 1 Minute / 前 1 分钟)

```bash
# Golden path check — PRIORITY / 黄金路径检查 — 优先级最高
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"

# Identify critical pods / 识别严重问题 Pod
kubectl top pods -n production --sort-by=cpu | head -10

# Check if alert storm / 检查是否报警风暴
curl -s "http://alertmanager:9093/api/v2/alerts?filter=category%3D%22infra-k8s%22" | \
  jq '.[].labels | {alertname, severity, instance}'
```

| Condition / 条件 | Severity / 严重度 | Action / 操作 |
|-----------|----------|--------|
| Golden path impacted / 黄金路径受影响 | **Critical -> Tier 1** | Wake China HQ immediately / 立即通知中国总部 |
| Service degraded / 服务退化 | Critical -> Tier 1 | Emergency scale + China notify / 紧急扩容 + 通知中国 |
| Isolated pod, no impact / 单一 Pod 无影响 | Warning -> Tier 2 | Scale out / 扩容 |

### 2. ACKNOWLEDGE / 确认 (Within 5 min / 5 分钟内)

```bash
# Silence alert (15m for critical) / 静默报警（紧急级 15 分钟）
amtool silence add alertname="K8sPodCpuUsageCritical" \
  --duration="15m" --comment="CRITICAL - Investigating - YOUR_NAME" --author="YOUR_NAME"
```

Post to WeCom Critical Channel / 发送到企业微信紧急频道:
```
CRITICAL Alert / 紧急报警
Alert: K8sPodCpuUsageCritical (LCK-K8-003)
Severity: critical | Tier: 1
Owner: {your_name}
Status: ACTIVE INVESTIGATION / 正在调查
ETA for update: {time + 5min}
```

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
```
[ ] Massive traffic spike / 大规模流量激增
[ ] Bad deployment — infinite loop or resource bug / 问题部署 — 死循环或资源 Bug
[ ] Downstream dependency failure causing retries / 下游依赖故障导致重试
[ ] Node resource contention / 节点资源争抢
[ ] HPA max replicas reached / HPA 已达最大副本数
[ ] DDoS or abusive client traffic / DDoS 或恶意客户端流量
```

```bash
# Immediate pod status / 立即检查 Pod 状态
kubectl get pods -n production -l app=SERVICE_NAME -o wide

# HPA status — is it maxed out? / HPA 状态 — 是否已达上限？
kubectl get hpa -n production | grep SERVICE_NAME

# Recent events / 最近事件
kubectl get events -n production --sort-by='.lastTimestamp' | tail -20

# Check which node these pods run on / 检查这些 Pod 运行在哪个节点
kubectl get pods -n production -l app=SERVICE_NAME -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}'

# Node-level CPU / 节点级别 CPU
kubectl top nodes
```

Dashboard: `https://grafana.luckinus.com/d/k8s-pods?var-pod=POD_NAME&from=now-30m&to=now`

### 4. ACT / 处置 (Tier 1 — Emergency / 紧急处置)

```bash
# STEP 1: Emergency scale out / 步骤 1：紧急扩容
kubectl scale deployment/SERVICE_NAME -n production --replicas=DOUBLE_CURRENT

# STEP 2: If bad deployment, rollback / 步骤 2：如果是问题部署，回滚
kubectl rollout undo deployment/SERVICE_NAME -n production
kubectl rollout status deployment/SERVICE_NAME -n production --timeout=300s

# STEP 3: If HPA maxed, increase max / 步骤 3：如 HPA 已满，增加上限
kubectl patch hpa SERVICE_NAME-hpa -n production -p '{"spec":{"maxReplicas":NEW_MAX}}'

# STEP 4: If node resource contention, cordon overloaded node / 步骤 4：如节点资源争抢，隔离过载节点
kubectl cordon NODE_NAME
```

**Escalation / 升级路径:**
```
Tier 1 (Critical) → China HQ Engineering (immediate / 立即)
                  → WeCom: @all in critical channel / 企业微信紧急频道 @所有人
                  → Twilio: All DevOps numbers / Twilio 呼叫所有运维号码
```

### 5. AFTERMATH / 善后

- [ ] Verify CPU returned below 85% / 确认 CPU 回到 85% 以下
- [ ] Mandatory incident report / 必须提交事件报告
- [ ] Review deployment process that caused the spike / 审查导致峰值的部署流程
- [ ] Adjust HPA policy (target CPU, min/max replicas) / 调整 HPA 策略
- [ ] Consider vertical pod autoscaling (VPA) / 考虑垂直 Pod 自动扩容
- [ ] Post-mortem with China HQ within 24h / 24 小时内与中国总部进行事后复盘

---

## K8S-04: PodRestart_Warning / Pod 重启过频（警告级）

```yaml
alert_id: "LCK-K8-004"
alert_name: "K8sPodRestartWarning"
old_ids: "ALR-093"
severity: "warning"
tier: "2"
category: "infra-k8s"
team: "k8s-ops"
first_responder: "k8s-ops on-call"
sla_response: "15 min"
notification_channel: "wecom+twilio-lead"
skill_reference: "/app/skills/k8s-alert-investigation.md"
last_updated: "2026-02-16"
```

### Alert Rule / 报警规则

```yaml
alert: K8sPodRestartWarning
expr: |
  increase(kube_pod_container_status_restarts_total{env="production"}[2m]) > 1
for: 5m
```

**Meaning / 含义:** A pod has restarted more than once within a 2-minute window, sustained for 5 minutes. This indicates a crash loop or recurring failure. Check container logs for the termination reason.
一个 Pod 在 2 分钟窗口内重启超过 1 次，持续 5 分钟。这表明存在崩溃循环或反复故障。检查容器日志以获取终止原因。

### 1. ASSESS / 评估 (First 2 Minutes / 前 2 分钟)

```bash
# Golden path check / 黄金路径检查
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"

# Which pods are restarting? / 哪些 Pod 在重启？
kubectl get pods -n production --sort-by='.status.containerStatuses[0].restartCount' | tail -20

# Check for correlated OOM alerts (K8S-06) / 检查是否有关联的 OOM 报警 (K8S-06)
curl -s "http://alertmanager:9093/api/v2/alerts?filter=alertname%3D%22K8sOomKilledCritical%22" | jq length
```

### 2. ACKNOWLEDGE / 确认 (Within 15 min / 15 分钟内)

```bash
amtool silence add alertname="K8sPodRestartWarning" \
  --duration="30m" --comment="Investigating pod restarts - YOUR_NAME" --author="YOUR_NAME"
```

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
```
[ ] OOM Kill (check K8S-06) / OOM 终止（检查 K8S-06）
[ ] Application crash (unhandled exception) / 应用崩溃（未处理异常）
[ ] Health check failure (liveness probe) / 健康检查失败（存活探针）
[ ] Dependency unavailable at startup / 启动时依赖不可用
[ ] ConfigMap or Secret mount failure / ConfigMap 或 Secret 挂载失败
[ ] Image pull failure (registry auth) / 镜像拉取失败（仓库认证）
```

```bash
# Get termination reason / 获取终止原因
kubectl get pods -n production -l app=SERVICE_NAME -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[*].lastState.terminated.reason}{"\t"}{.status.containerStatuses[*].lastState.terminated.exitCode}{"\n"}{end}'

# Recent logs from the restarting pod / 重启 Pod 的最近日志
kubectl logs POD_NAME -n production --previous --tail=100

# Current logs / 当前日志
kubectl logs POD_NAME -n production --tail=50

# Events for the pod / Pod 事件
kubectl describe pod POD_NAME -n production | grep -A 20 "Events:"

# Check liveness/readiness probe configuration / 检查存活/就绪探针配置
kubectl get pod POD_NAME -n production -o jsonpath='{.spec.containers[*].livenessProbe}'
```

### 4. ACT / 处置 (Tier 2 — Stabilize and fix / 稳定和修复)

```bash
# If OOM: increase memory limits / 如果 OOM：增加内存限制
kubectl patch deployment SERVICE_NAME -n production -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"SERVICE_NAME","resources":{"limits":{"memory":"NEW_LIMIT"}}}]}}}}'

# If bad deployment: rollback / 如果是问题部署：回滚
kubectl rollout undo deployment/SERVICE_NAME -n production

# If liveness probe too aggressive: adjust / 如果存活探针过于激进：调整
kubectl patch deployment SERVICE_NAME -n production -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"SERVICE_NAME","livenessProbe":{"initialDelaySeconds":30,"periodSeconds":15,"failureThreshold":5}}]}}}}'

# Monitor restart count / 监控重启计数
watch -n 10 "kubectl get pods -n production -l app=SERVICE_NAME"
```

**Escalation / 升级路径:**
```
Tier 2 → (30 min no resolution / 30 分钟未解决) → Tier 1 → China HQ
```

### 5. AFTERMATH / 善后

- [ ] Verify restart count stabilized at 0 / 确认重启计数稳定在 0
- [ ] Root cause documented / 根因已记录
- [ ] Memory limits reviewed if OOM-related / 如与 OOM 相关则审查内存限制
- [ ] Liveness probe thresholds reviewed / 审查存活探针阈值
- [ ] File incident report / 提交事件报告

---

## K8S-05: PodDiskIO_Warning / Pod 磁盘 IO 过高（警告级）

```yaml
alert_id: "LCK-K8-005"
alert_name: "K8sPodDiskIoWarning"
old_ids: "ALR-096, ALR-097"
migration_action: "MERGE"
severity: "warning"
tier: "3"
category: "infra-k8s"
team: "k8s-ops"
first_responder: "k8s-ops on-call"
sla_response: "30 min"
notification_channel: "wecom+twilio-lead"
skill_reference: "/app/skills/k8s-alert-investigation.md"
last_updated: "2026-02-16"
```

### Alert Rule / 报警规则

```yaml
alert: K8sPodDiskIoWarning
expr: |
  lckna:k8s:pod_disk_io_rate / 1024 / 1024 > 50
for: 5m
```

**Meaning / 含义:** Pod disk IO rate (combined read+write, 3-minute average) exceeds 50 MB/s for 5 minutes. This may cause IO contention at the node level and affect other pods on the same node.
Pod 磁盘 IO 速率（读写合计，3 分钟均值）超过 50 MB/s 持续 5 分钟。这可能在节点级别造成 IO 争抢，影响同节点的其他 Pod。

**Note / 备注:** This alert merges old ALR-096 (disk read) and ALR-097 (disk write) into a single combined IO rate alert.
此报警将旧 ALR-096（磁盘读）和 ALR-097（磁盘写）合并为一个综合 IO 速率报警。

### 1. ASSESS / 评估 (First 2 Minutes / 前 2 分钟)

```bash
# Golden path check / 黄金路径检查
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"

# Which pods have high IO? / 哪些 Pod IO 高？
# PromQL: lckna:k8s:pod_disk_io_rate / 1024 / 1024 (datasource: df8o21agxtkw0d)

# Check node-level IO / 检查节点级别 IO
kubectl top nodes
```

### 2. ACKNOWLEDGE / 确认 (Within 30 min / 30 分钟内)

```bash
amtool silence add alertname="K8sPodDiskIoWarning" \
  --duration="1h" --comment="Investigating disk IO - YOUR_NAME" --author="YOUR_NAME"
```

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
```
[ ] Excessive logging (log level set to DEBUG) / 日志过多（日志级别设为 DEBUG）
[ ] Local file writes (temp files, caches) / 本地文件写入（临时文件、缓存）
[ ] Persistent volume contention / 持久卷争抢
[ ] Container filesystem layer writes / 容器文件系统层写入
[ ] Application data serialization to disk / 应用数据序列化到磁盘
[ ] Log rotation or compression running / 日志轮转或压缩正在运行
```

```bash
# Check which process in the pod is doing IO / 检查 Pod 中哪个进程在做 IO
kubectl exec -it POD_NAME -n production -- sh -c "cat /proc/*/io 2>/dev/null | head -50" || echo "iotop not available"

# Check container filesystem usage / 检查容器文件系统使用
kubectl exec -it POD_NAME -n production -- df -h

# Check log volume size / 检查日志量大小
kubectl exec -it POD_NAME -n production -- ls -lah /var/log/ 2>/dev/null

# Which node is this pod on? / 此 Pod 在哪个节点？
kubectl get pod POD_NAME -n production -o jsonpath='{.spec.nodeName}'

# PromQL — breakdown read vs write (datasource: df8o21agxtkw0d)
# rate(container_fs_reads_bytes_total{pod="POD_NAME", env="production"}[3m]) / 1024 / 1024
# rate(container_fs_writes_bytes_total{pod="POD_NAME", env="production"}[3m]) / 1024 / 1024
```

Dashboard: `https://grafana.luckinus.com/d/k8s-pod-io?var-pod=POD_NAME&from=now-1h&to=now`

### 4. ACT / 处置 (Tier 3 — Monitor and tune / 监控和调优)

```bash
# If excessive logging: reduce log level / 如果日志过多：降低日志级别
kubectl set env deployment/SERVICE_NAME -n production LOG_LEVEL=INFO

# If temp files: clean up / 如果临时文件：清理
kubectl exec -it POD_NAME -n production -- sh -c "rm -rf /tmp/cache/*"

# If node contention: reschedule to different node / 如果节点争抢：重新调度到其他节点
kubectl delete pod POD_NAME -n production  # will be rescheduled

# For persistent fix: add ephemeral storage limits / 永久修复：添加临时存储限制
# (requires deployment spec update / 需要更新部署配置)
```

**Escalation / 升级路径:**
```
Tier 3 → (15 min no resolution / 15 分钟未解决) → Tier 2
```

### 5. AFTERMATH / 善后

- [ ] Verify disk IO returned below 50MB/s / 确认磁盘 IO 回到 50MB/s 以下
- [ ] Review logging configuration / 审查日志配置
- [ ] Consider adding ephemeral storage limits / 考虑添加临时存储限制
- [ ] Check if threshold (50MB/s) is appropriate / 检查阈值（50MB/s）是否合适

---

## K8S-06: PodOOM_Critical / Pod OOM 终止（紧急级）

```yaml
alert_id: "LCK-K8-006"
alert_name: "K8sOomKilledCritical"
old_ids: "ALR-094"
severity: "critical"
tier: "1"
category: "infra-k8s"
team: "k8s-ops"
first_responder: "k8s-ops on-call"
sla_response: "5 min"
notification_channel: "wecom+twilio-all"
skill_reference: "/app/skills/k8s-alert-investigation.md"
last_updated: "2026-02-16"
```

### Alert Rule / 报警规则

```yaml
alert: K8sOomKilledCritical
expr: |
  increase(kube_pod_container_status_last_terminated_reason{reason="OOMKilled", env="production"}[5m]) > 0
for: 0m
```

**Meaning / 含义:** A container was OOM-killed within the last 5 minutes. The `for: 0m` means this alert fires instantly when the condition is true. The pod's memory limit was exceeded, causing the Linux kernel OOM killer to terminate the process. This will also trigger K8S-04 (PodRestart) as the pod restarts.
一个容器在过去 5 分钟内被 OOM 终止。`for: 0m` 表示条件为真时立即触发报警。Pod 的内存限制被超出，导致 Linux 内核 OOM killer 终止进程。这也会触发 K8S-04（Pod 重启）。

### 1. ASSESS / 评估 (First 1 Minute / 前 1 分钟)

```bash
# Golden path check / 黄金路径检查
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"

# Which pods were OOM killed? / 哪些 Pod 被 OOM 终止？
kubectl get events -n production --field-selector reason=OOMKilling --sort-by='.lastTimestamp' | tail -10

# Check if multiple OOMs (widespread issue) / 检查是否多次 OOM（大范围问题）
kubectl get pods -n production -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[*].lastState.terminated.reason}{"\n"}{end}' | grep OOMKilled
```

### 2. ACKNOWLEDGE / 确认 (Within 5 min / 5 分钟内)

```bash
amtool silence add alertname="K8sOomKilledCritical" \
  --duration="15m" --comment="CRITICAL OOM - Investigating - YOUR_NAME" --author="YOUR_NAME"
```

Post to WeCom Critical Channel / 发送到企业微信紧急频道:
```
CRITICAL Alert / 紧急报警
Alert: K8sOomKilledCritical (LCK-K8-006)
Severity: critical | Tier: 1
Pod: {pod_name} was OOM Killed / Pod 被 OOM 终止
Owner: {your_name}
Status: ACTIVE INVESTIGATION / 正在调查
```

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
```
[ ] Memory limit too low for workload / 内存限制对工作负载来说过低
[ ] Memory leak in application / 应用内存泄漏
[ ] JVM heap misconfiguration / JVM 堆配置错误
[ ] Large request payload in memory / 大请求载荷占用内存
[ ] Cache growing unbounded / 缓存无限增长
[ ] New deployment with higher memory footprint / 新部署内存占用更大
```

```bash
# Check current memory limits / 检查当前内存限制
kubectl get pod POD_NAME -n production -o jsonpath='{.spec.containers[*].resources}' | jq .

# Previous container logs (before OOM) / 上一个容器的日志（OOM 前）
kubectl logs POD_NAME -n production --previous --tail=200

# Check memory usage of running pods / 检查运行中 Pod 的内存使用
kubectl top pods -n production -l app=SERVICE_NAME --sort-by=memory

# PromQL — memory trend before OOM (datasource: df8o21agxtkw0d)
# container_memory_working_set_bytes{pod=~"SERVICE_NAME.*", env="production"} / 1024 / 1024

# Check if JVM app — heap settings / 如果是 JVM 应用 — 堆设置
kubectl exec -it POD_NAME -n production -- env | grep -i "java\|heap\|xmx\|xms" 2>/dev/null
```

### 4. ACT / 处置 (Tier 1 — Emergency / 紧急处置)

```bash
# STEP 1: Increase memory limits immediately / 步骤 1：立即增加内存限制
kubectl patch deployment SERVICE_NAME -n production -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"SERVICE_NAME","resources":{"limits":{"memory":"NEW_LIMIT"},"requests":{"memory":"NEW_REQUEST"}}}]}}}}'

# STEP 2: Monitor new pods starting with increased limits / 步骤 2：监控使用新限制启动的新 Pod
kubectl rollout status deployment/SERVICE_NAME -n production --timeout=300s

# STEP 3: If memory leak suspected, schedule restart cycle / 步骤 3：如怀疑内存泄漏，安排重启周期
# (temporary measure until code fix / 临时措施直到代码修复)

# STEP 4: If caused by bad deployment / 步骤 4：如果是问题部署导致
kubectl rollout undo deployment/SERVICE_NAME -n production
```

**Escalation / 升级路径:**
```
Tier 1 (Critical) → China HQ Engineering (immediate / 立即)
  → WeCom: @all in critical channel / 企业微信紧急频道 @所有人
  → Twilio: All DevOps numbers / Twilio 呼叫所有运维号码
```

### 5. AFTERMATH / 善后

- [ ] Verify no more OOM events / 确认不再有 OOM 事件
- [ ] Mandatory incident report / 必须提交事件报告
- [ ] Review memory limits for the service / 审查该服务的内存限制
- [ ] If memory leak: file bug with development team / 如内存泄漏：向开发团队提交 Bug
- [ ] Consider VPA for auto memory sizing / 考虑使用 VPA 自动调整内存大小
- [ ] Post-mortem with China HQ within 24h / 24 小时内与中国总部进行事后复盘

---

## K8S-07: NodeHeartbeatLost_Critical / 节点心跳丢失（紧急级）

```yaml
alert_id: "LCK-K8-007"
alert_name: "K8sNodeHeartbeatLostCritical"
old_ids: "ALR-092"
severity: "critical"
tier: "1"
category: "infra-k8s"
team: "k8s-ops"
first_responder: "k8s-ops on-call"
sla_response: "5 min"
notification_channel: "wecom+twilio-all"
skill_reference: "/app/skills/k8s-alert-investigation.md"
last_updated: "2026-02-16"
```

### Alert Rule / 报警规则

```yaml
alert: K8sNodeHeartbeatLostCritical
expr: |
  kube_node_status_condition{condition="Ready", status="true", env="production"} == 0
for: 5m
```

**Meaning / 含义:** A Kubernetes node has been in NotReady state for 5 minutes. The kubelet has stopped sending heartbeats, which means the node is offline or severely degraded. Pods on this node will be rescheduled (triggering K8S-04), and cluster capacity is reduced.
一个 Kubernetes 节点已处于 NotReady 状态 5 分钟。kubelet 已停止发送心跳，说明节点离线或严重退化。该节点上的 Pod 将被重新调度（触发 K8S-04），集群容量减少。

### 1. ASSESS / 评估 (First 1 Minute / 前 1 分钟)

```bash
# Golden path check / 黄金路径检查
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"

# Which node is NotReady? / 哪个节点 NotReady？
kubectl get nodes -o wide | grep -v " Ready "

# How many pods were on this node? / 这个节点上有多少 Pod？
kubectl get pods -n production --field-selector spec.nodeName=NODE_NAME -o wide

# Check if multiple nodes affected / 检查是否多个节点受影响
kubectl get nodes | grep NotReady | wc -l
```

| Condition / 条件 | Severity / 严重度 | Action / 操作 |
|-----------|----------|--------|
| Multiple nodes down / 多个节点宕机 | **Critical -> Tier 1** | Emergency — possible AZ failure / 紧急 — 可能 AZ 故障 |
| Single node, pods rescheduled OK / 单节点，Pod 已重调度 | Critical -> Tier 1 | Investigate node, verify capacity / 调查节点，验证容量 |
| Single node, no pods affected / 单节点，无 Pod 受影响 | Warning -> Tier 2 | Investigate root cause / 调查根因 |

### 2. ACKNOWLEDGE / 确认 (Within 5 min / 5 分钟内)

```bash
amtool silence add alertname="K8sNodeHeartbeatLostCritical" \
  --duration="15m" --comment="CRITICAL Node down - Investigating - YOUR_NAME" --author="YOUR_NAME"
```

Post to WeCom Critical Channel / 发送到企业微信紧急频道:
```
CRITICAL Alert / 紧急报警
Alert: K8sNodeHeartbeatLostCritical (LCK-K8-007)
Severity: critical | Tier: 1
Node: {node_name} is NotReady / 节点 NotReady
Pods at risk: {count} / 受影响 Pod 数: {count}
Owner: {your_name}
Status: ACTIVE INVESTIGATION / 正在调查
```

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
```
[ ] EC2 instance terminated or stopped / EC2 实例终止或停止
[ ] kubelet process crashed / kubelet 进程崩溃
[ ] Node out of disk space / 节点磁盘空间不足
[ ] Node out of memory (system OOM) / 节点内存不足（系统级 OOM）
[ ] Network partition / 网络分区
[ ] AWS maintenance event / AWS 维护事件
```

```bash
# Check EC2 instance status / 检查 EC2 实例状态
INSTANCE_ID=$(kubectl get node NODE_NAME -o jsonpath='{.spec.providerID}' | cut -d/ -f5)
aws ec2 describe-instance-status --instance-ids $INSTANCE_ID --region us-east-1

# Check for AWS scheduled events / 检查 AWS 计划事件
aws ec2 describe-instance-status --instance-ids $INSTANCE_ID --region us-east-1 \
  --query 'InstanceStatuses[].Events[]'

# Node conditions detail / 节点条件详情
kubectl describe node NODE_NAME | grep -A 20 "Conditions:"

# Check kubelet logs (if node accessible via SSH) / 检查 kubelet 日志（如节点可通过 SSH 访问）
ssh NODE_IP "journalctl -u kubelet --since '10 minutes ago' --no-pager | tail -50"

# Check node resource pressure / 检查节点资源压力
kubectl describe node NODE_NAME | grep -E "DiskPressure|MemoryPressure|PIDPressure"

# PromQL — node_exporter metrics (if still reporting) (datasource: df8o21agxtkw0d)
# up{instance="NODE_IP:9100"}
# node_filesystem_avail_bytes{instance="NODE_IP:9100", mountpoint="/"}
```

Dashboard: `https://grafana.luckinus.com/d/k8s-nodes?var-node=NODE_NAME&from=now-1h&to=now`

### 4. ACT / 处置 (Tier 1 — Emergency / 紧急处置)

```bash
# STEP 1: Verify pods are being rescheduled / 步骤 1：确认 Pod 正在被重新调度
kubectl get pods -n production -o wide | grep -v Running

# STEP 2: If pods stuck in Pending / 步骤 2：如果 Pod 卡在 Pending
kubectl describe pods -n production --field-selector status.phase=Pending | grep -A 5 "Events:"

# STEP 3: If cluster capacity insufficient, scale node group / 步骤 3：如果集群容量不足，扩容节点组
aws eks update-nodegroup-config \
  --cluster-name luckyus-prod \
  --nodegroup-name NODEGROUP_NAME \
  --scaling-config minSize=CURRENT,maxSize=NEW_MAX,desiredSize=NEW_DESIRED \
  --region us-east-1

# STEP 4: Cordon the bad node (prevent scheduling) / 步骤 4：隔离问题节点（防止调度）
kubectl cordon NODE_NAME

# STEP 5: If node recoverable, try restarting kubelet / 步骤 5：如果节点可恢复，尝试重启 kubelet
ssh NODE_IP "sudo systemctl restart kubelet"

# STEP 6: If node unrecoverable, drain and terminate / 步骤 6：如果节点不可恢复，排空并终止
kubectl drain NODE_NAME --ignore-daemonsets --delete-emptydir-data --force
aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region us-east-1
```

**Escalation / 升级路径:**
```
Tier 1 (Critical) → China HQ Engineering (immediate / 立即)
  → WeCom: @all in critical channel / 企业微信紧急频道 @所有人
  → Twilio: All DevOps numbers / Twilio 呼叫所有运维号码

If multiple nodes: AWS Support case (infrastructure) / 如多节点：提交 AWS 支持案例
```

### 5. AFTERMATH / 善后

- [ ] Verify all pods rescheduled and running / 确认所有 Pod 已重新调度并运行
- [ ] Verify node replaced by autoscaling group / 确认节点已被自动伸缩组替换
- [ ] Mandatory incident report / 必须提交事件报告
- [ ] Review ASG health check configuration / 审查 ASG 健康检查配置
- [ ] Check for AWS scheduled maintenance / 检查 AWS 计划维护
- [ ] Verify Pod Disruption Budget (PDB) is set / 确认 Pod Disruption Budget (PDB) 已设置
- [ ] Post-mortem with China HQ within 24h / 24 小时内与中国总部进行事后复盘

---

## Cross-Reference / 交叉引用

### Alert Chains / 报警链

| Trigger Alert | Effect Alert | Relationship |
|---------------|-------------|-------------|
| K8S-01 (CPU >50%) | K8S-02 (CPU >70%) | Escalation if unresolved / 未解决时升级 |
| K8S-02 (CPU >70%) | K8S-03 (CPU >85%) | Escalation if unresolved / 未解决时升级 |
| K8S-06 (OOM Kill) | K8S-04 (Pod Restart) | OOM causes restart / OOM 导致重启 |
| K8S-07 (Node Lost) | K8S-04 (Pod Restart) | Rescheduling causes restart count / 重调度导致重启计数 |

### Cross-Category Dependencies / 跨分类依赖

| K8S Alert | Related Category | Relationship |
|-----------|-----------------|-------------|
| K8S-03 (CPU Critical) | VM alerts | Node-level CPU may also alert / 节点级 CPU 也可能报警 |
| K8S-06 (OOM) | APM alerts | Application latency spikes during OOM / OOM 期间应用延迟飙升 |
| K8S-07 (Node Lost) | VM alerts | EC2 instance status check fails / EC2 实例状态检查失败 |
| K8S-04 (Restart) | Business alerts | Service interruption may affect orders / 服务中断可能影响订单 |

---

## Appendix / 附录

### Grafana Dashboards / Grafana 仪表板

| Dashboard | UID | Purpose / 用途 |
|-----------|-----|-------|
| K8S Pods Overview | `k8s-pods` | Pod CPU, memory, restart count / Pod CPU、内存、重启计数 |
| K8S Pod IO | `k8s-pod-io` | Pod disk and network IO / Pod 磁盘和网络 IO |
| K8S Nodes | `k8s-nodes` | Node status, capacity, conditions / 节点状态、容量、条件 |

### MCP Skill Reference / MCP 技能引用

| Skill | File | Invocation |
|-------|------|-----------|
| K8s Alert Investigation | `/app/skills/k8s-alert-investigation.md` | `/investigate-k8s` |
| EC2 Alert Investigation | `/app/skills/ec2-alert-investigation.md` | `/investigate-ec2` |
| APM Alert Investigation | `/app/skills/apm-alert-investigation.md` | `/investigate-apm` |

### Key Environment Reference / 关键环境引用

| Resource | Value | Notes |
|----------|-------|-------|
| Prometheus Datasource UID | `df8o21agxtkw0d` | UMBQuerier-Luckin (primary) |
| General Prometheus UID | `ff7hkeec6c9a8e` | prometheus |
| EKS Cluster | `luckyus-prod` | Production cluster |
| AWS Account | `257394478466` | Production |
| Region | `us-east-1` | Primary |
| VMAlert (Basic) | `10.238.3.153:8880` | Infrastructure alert evaluation |
| VMAlert (APM-1) | `10.238.3.137:8880` | APM alert evaluation |
| VMAlert (APM-2) | `10.238.3.143:8880` | APM alert evaluation |
| VMAlert (APM-3) | `10.238.3.52:8880` | APM alert evaluation |

### WeCom Notification Channels / 企业微信通知频道

| Channel | Tier | Recipients / 接收人 |
|---------|------|-----------|
| wecom-only | Tier 3 | US DevOps (text only / 仅文字) |
| wecom+twilio-lead | Tier 2 | US DevOps + Team Lead (text + phone lead / 文字 + 电话负责人) |
| wecom+twilio-all | Tier 1 | All DevOps US + China HQ (text + phone all / 文字 + 电话所有人) |

---

> **End of Part 6 — INFRA-K8S Runbook (7 alerts)**
> **第 6 部分结束 — INFRA-K8S 运行手册（7 条报警）**

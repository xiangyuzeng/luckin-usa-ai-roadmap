# Luckin Coffee NA -- Alert Runbook Part 8: APM (Application Performance)
# 瑞幸咖啡北美 -- 告警运行手册 第8部分: APM (应用性能)

> **Version / 版本:** 1.0
> **Date / 日期:** 2026-02-16
> **Category / 类别:** APM -- Application Performance Monitoring / 应用性能监控
> **Alert Group / 告警组:** `lck-na.alerts.apm` (interval: 30s)
> **Alerts in this part / 本部分告警数:** 6 (LCK-AP-001 through LCK-AP-006)
> **Consolidation / 合并:** 29 legacy alerts merged into 6 new alerts (79% reduction)
> **Format / 格式:** 5 A's Pattern (Assess, Acknowledge, Analyze, Act, Aftermath)
> **Skill Reference / 技能参考:** `/app/skills/apm-alert-investigation.md` v1.0
> **Platform:** AWS us-east-1 | EKS: luckyus-prod | iZeus APM

---

## Table of Contents / 目录

| Alert ID | Name | Severity | Tier | Page |
|----------|------|----------|------|------|
| [LCK-AP-001](#lck-ap-001) | ApmServiceExceptionsWarning | warning | 2 | Service Exception Rate Warning |
| [LCK-AP-002](#lck-ap-002) | ApmServiceExceptionsCritical | critical | 1 | Service Exception Rate Critical |
| [LCK-AP-003](#lck-ap-003) | ApmLatencyP99Warning | warning | 2 | Service Latency P99 Warning |
| [LCK-AP-004](#lck-ap-004) | ApmEndpointFailuresWarning | warning | 2 | Endpoint Failures Warning |
| [LCK-AP-005](#lck-ap-005) | ApmJvmFullGcWarning | warning | 2 | JVM Full GC Warning |
| [LCK-AP-006](#lck-ap-006) | ApmInfraHealthWarning | warning | 3 | APM Infrastructure Health |

---

<a id="lck-ap-001"></a>
## LCK-AP-001: ApmServiceExceptionsWarning

### Metadata / 元数据

```yaml
alert_id: "LCK-AP-001"
alert_name: "ApmServiceExceptionsWarning"
severity: "warning"
tier: "2"
category: "apm"
team: "app-ops"
first_responder: "app-ops on-call"
sla_response: "Tier 2: 15min"
old_alert_ids: "ALR-060~068, ALR-073, ALR-086, ALR-087, ALR-088"
consolidation: "MERGE — 13 legacy iZeus strategy alerts merged into one warning-level exception rate alert"
skill_reference: "/app/skills/apm-alert-investigation.md"
last_updated: "2026-02-16"
```

### PromQL Expression / 告警表达式

```promql
# Datasource: df8o21agxtkw0d (UMBQuerier-Luckin)
# Evaluation interval: 30s | for: 5m
rate(service_exception_count{env="production"}[3m]) * 60 > 5
and
rate(service_exception_count{env="production"}[3m]) * 60 <= 20
```

**Meaning / 含义:** Service exception rate is between 5 and 20 exceptions per minute (3-minute average), sustained for 5 minutes. Elevated error rate indicates partial failures.
服务异常速率在每分钟 5~20 次之间 (3分钟均值), 持续 5 分钟。异常率升高表明存在部分请求失败。

### 1. ASSESS (First 2 Minutes) / 评估 (前2分钟)

**Goal / 目标:** Determine if elevated exception rate is impacting the golden path (user ordering flow).
判断异常率升高是否影响黄金路径 (用户下单流程)。

#### 1.1 Golden Path Impact Check / 黄金路径影响检查

```bash
# Check if completed orders are flowing / 检查订单是否正常流转
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"

# Check the specific service throwing exceptions / 检查抛出异常的具体服务
curl -s "http://prometheus:9090/api/v1/query?query=topk(5, rate(service_exception_count{env='production'}[3m]) * 60)"
```

#### 1.2 Quick Triage / 快速分诊

```bash
# Check top exception-throwing services and their rates / 检查异常率最高的服务
curl -s "http://prometheus:9090/api/v1/query?query=sort_desc(rate(service_exception_count{env='production'}[3m]) * 60 > 5)" | jq '.data.result[] | {service: .metric.service_name, rate: .value[1]}'

# Check if this is isolated or part of an alert storm / 检查是否为孤立告警或告警风暴
curl -s "http://alertmanager:9093/api/v2/alerts?filter=category%3D%22apm%22" | jq '.[].labels | {alertname, severity, service_name}'

# Check recent deployments / 检查近期部署
kubectl get events -n production --sort-by='.lastTimestamp' --field-selector reason=Pulling | tail -10
```

#### 1.3 Severity Classification / 严重性分类

| Condition / 条件 | Severity / 严重性 | Action / 操作 |
|-----------|----------|--------|
| Golden path impacted (orders stopped) / 黄金路径受影响 | **Escalate to Tier 3** | Wake China HQ / 通知中国总部 |
| Exception rate 5-20/min, some requests failing / 异常率5-20/分钟 | **Warning -- Tier 2** | App-Ops investigates / App-Ops 调查 |
| Rate near threshold, no user impact / 接近阈值, 无用户影响 | **Monitor -- Tier 1** | Watch for 15 min / 观察 15 分钟 |

### 2. ACKNOWLEDGE (Within 15 min SLA) / 确认 (15分钟 SLA)

```bash
# Silence alert during investigation (30 min) / 调查期间静默告警 (30分钟)
amtool silence add alertname="ApmServiceExceptionsWarning" \
  --duration="30m" --comment="Investigating - YOUR_NAME" --author="YOUR_NAME"
```

**WeCom Template / 企业微信模板:**
```
Alert Acknowledged / 告警已确认
Alert: ApmServiceExceptionsWarning (LCK-AP-001)
Severity: warning | Tier: 2
Owner: {your_name}
Status: Investigating / 调查中
ETA for update: {time + 15min}
```

### 3. ANALYZE (Root Cause) / 分析 (根因)

#### 3.1 Common Causes / 常见原因

```
[ ] Recent deployment introduced a bug / 近期部署引入了 Bug
[ ] Downstream dependency failure (DB, Redis, external API) / 下游依赖故障
[ ] Code exception (NullPointer, ClassCast, timeout) / 代码异常
[ ] Connection pool exhaustion / 连接池耗尽
[ ] Upstream traffic pattern change / 上游流量模式变化
[ ] Configuration change (feature flag, config center) / 配置变更
```

#### 3.2 Diagnostic Commands / 诊断命令

```bash
# iZeus APM — Check top exceptions by service / 按服务查看 Top 异常
# URL: https://izeus.luckincoffee.us/trace?service={service_name}&start={timestamp}
# Navigate: Services → {service_name} → Errors tab / 服务 → {服务名} → 错误标签页

# Check exception breakdown by type / 按异常类型查看分布
curl -s "http://prometheus:9090/api/v1/query?query=topk(10, rate(service_exception_count{env='production'}[5m]) * 60)" | \
  jq '.data.result[] | {service: .metric.service_name, exception: .metric.exception_type, rate: .value[1]}'

# Check application logs for the service / 查看该服务的应用日志
kubectl logs -n production -l app=SERVICE_NAME --tail=100 --since=10m | grep -i "exception\|error\|fail" | tail -30

# Check service pod status / 检查服务 Pod 状态
kubectl get pods -n production -l app=SERVICE_NAME -o wide
kubectl describe pod POD_NAME -n production | tail -30

# Thread dump if application is unresponsive / 如果应用无响应, 获取线程转储
kubectl exec -n production POD_NAME -- jstack $(kubectl exec -n production POD_NAME -- pgrep -f java) > /tmp/thread_dump_$(date +%Y%m%d_%H%M%S).txt
```

#### 3.3 VMAlert Endpoint Verification / VMAlert 端点验证

```bash
# Check APM VMAlert instances / 检查 APM VMAlert 实例
curl -s "http://10.238.3.137:8880/api/v1/alerts" | jq '.data.alerts[] | select(.labels.alertname == "ApmServiceExceptionsWarning")'
curl -s "http://10.238.3.143:8880/api/v1/alerts" | jq '.data.alerts[] | select(.labels.alertname == "ApmServiceExceptionsWarning")'
curl -s "http://10.238.3.52:8880/api/v1/alerts" | jq '.data.alerts[] | select(.labels.alertname == "ApmServiceExceptionsWarning")'
```

### 4. ACT (Remediation) / 处置 (修复)

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---------|--------|------------|
| Code bug in recent deployment / 近期部署代码 Bug | Rollback deployment / 回滚部署 | Tier 2 |
| Downstream dependency timeout / 下游依赖超时 | Check dependency health, add circuit breaker / 检查依赖健康, 启用熔断 | Tier 2 |
| Connection pool exhausted / 连接池耗尽 | Restart pod, tune pool settings / 重启 Pod, 调整连接池 | Tier 2 |
| Unknown root cause, rate climbing / 原因不明, 速率攀升 | Escalate to Tier 3 / 升级到 Tier 3 | Tier 2 → 3 |

```bash
# Rollback deployment / 回滚部署
kubectl rollout undo deployment/SERVICE_NAME -n production
kubectl rollout status deployment/SERVICE_NAME -n production --timeout=300s

# Rolling restart (if configuration issue) / 滚动重启 (配置问题)
kubectl rollout restart deployment/SERVICE_NAME -n production
```

### 5. AFTERMATH (Post-Incident) / 事后 (事件后)

- Update this runbook with new root cause if discovered / 如发现新根因, 更新本手册
- Review if threshold (5/min) is appropriate / 审查阈值 (5/分钟) 是否合理
- Update iZeus alert strategy if needed / 如需要, 更新 iZeus 告警策略
- File incident report for Tier 2+ incidents / Tier 2+ 事件需提交事件报告

**Old Alert Reference / 旧告警参考:** ALR-060 (iZeus-策略1 异常>2), ALR-061~068 (策略2~9 duplicates), ALR-073 (策略15 异常>3), ALR-086 (默认策略 okhttp异常>50), ALR-088 (默认策略 服务异常>5)

---

<a id="lck-ap-002"></a>
## LCK-AP-002: ApmServiceExceptionsCritical

### Metadata / 元数据

```yaml
alert_id: "LCK-AP-002"
alert_name: "ApmServiceExceptionsCritical"
severity: "critical"
tier: "1"
category: "apm"
team: "app-ops"
first_responder: "app-ops on-call"
sla_response: "Tier 1: 30min (but treat as Tier 3 urgency due to critical severity)"
old_alert_ids: "ALR-060~068, ALR-087"
consolidation: "MERGE — 10 legacy alerts into one critical exception rate alert"
skill_reference: "/app/skills/apm-alert-investigation.md"
last_updated: "2026-02-16"
```

### PromQL Expression / 告警表达式

```promql
# Datasource: df8o21agxtkw0d (UMBQuerier-Luckin)
# Evaluation interval: 30s | for: 3m
rate(service_exception_count{env="production"}[3m]) * 60 > 20
```

**Meaning / 含义:** Service exception rate exceeds 20 exceptions per minute (3-minute average), sustained for 3 minutes. Service is substantially degraded or failing.
服务异常速率超过每分钟 20 次 (3分钟均值), 持续 3 分钟。服务严重降级或故障。

### 1. ASSESS (First 2 Minutes) / 评估 (前2分钟)

**Goal / 目标:** CRITICAL -- Determine if golden path (ordering) is impacted. This is a high-severity alert requiring immediate attention.
紧急 -- 判断黄金路径 (下单流程) 是否受影响。此为高严重性告警, 需立即处理。

#### 1.1 Golden Path Impact Check / 黄金路径影响检查

```bash
# Immediately check order flow / 立即检查订单流
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"

# Check which services are critically affected / 检查哪些服务严重受影响
curl -s "http://prometheus:9090/api/v1/query?query=sort_desc(rate(service_exception_count{env='production'}[3m]) * 60 > 20)" | \
  jq '.data.result[] | {service: .metric.service_name, rate: .value[1]}'
```

#### 1.2 Quick Triage / 快速分诊

```bash
# Check for concurrent alerts (likely alert storm) / 检查并发告警 (可能告警风暴)
curl -s "http://alertmanager:9093/api/v2/alerts?filter=severity%3D%22critical%22" | \
  jq '.[].labels | {alertname, severity, service_name}'

# Check deployment events / 检查部署事件
kubectl get events -n production --sort-by='.lastTimestamp' --field-selector reason=Pulling | tail -10
```

#### 1.3 Severity Classification / 严重性分类

| Condition / 条件 | Severity / 严重性 | Action / 操作 |
|-----------|----------|--------|
| Golden path impacted / 黄金路径受影响 | **Critical -- Tier 3** | Immediate escalation to China HQ / 立即升级到中国总部 |
| High exception rate, users partially impacted / 高异常率, 部分用户受影响 | **Critical -- Tier 2+** | All hands on deck / 全员响应 |
| Spike resolving on its own / 峰值自行恢复 | **Monitor closely** | Keep silence short, watch for recurrence / 短暂静默, 监控复发 |

### 2. ACKNOWLEDGE (Within 5 min) / 确认 (5分钟内)

```bash
# Silence alert briefly (15 min max for critical) / 短暂静默告警 (危急最长15分钟)
amtool silence add alertname="ApmServiceExceptionsCritical" \
  --duration="15m" --comment="Investigating CRITICAL - YOUR_NAME" --author="YOUR_NAME"
```

**WeCom Template (Critical Channel) / 企业微信模板 (紧急频道):**
```
CRITICAL Alert Acknowledged / 紧急告警已确认
Alert: ApmServiceExceptionsCritical (LCK-AP-002)
Severity: CRITICAL | Tier: 1 (handling as Tier 3 urgency)
Owner: {your_name}
Status: Investigating / 调查中
Impacted services: {list from triage}
ETA for update: {time + 10min}
```

**Notification channel / 通知渠道:** wecom+twilio-all (all DevOps US + China HQ)

### 3. ANALYZE (Root Cause) / 分析 (根因)

#### 3.1 Common Causes / 常见原因

```
[ ] Bad deployment (most common for sudden spike) / 部署问题 (突然飙升最常见原因)
[ ] Database connection failure / 数据库连接故障
[ ] Redis cluster down or network partition / Redis 集群宕机或网络分区
[ ] External API dependency failure / 外部 API 依赖故障
[ ] Memory leak causing OOM → cascading exceptions / 内存泄漏导致 OOM → 级联异常
[ ] Certificate/credential expiry / 证书/凭证过期
```

#### 3.2 Diagnostic Commands / 诊断命令

```bash
# iZeus APM — Exception root cause analysis / 异常根因分析
# URL: https://izeus.luckincoffee.us/trace?service={service_name}&start={timestamp}
# Navigate: Services → {service_name} → Errors → Error traces / 错误链路

# Check exception types and stack traces / 检查异常类型和堆栈
kubectl logs -n production -l app=SERVICE_NAME --tail=200 --since=5m | \
  grep -i "exception\|error\|fatal" | sort | uniq -c | sort -rn | head -20

# Check database connectivity (if DB-related exceptions) / 检查数据库连接
kubectl exec -n production POD_NAME -- curl -s localhost:8080/actuator/health | jq '.components.db'

# Check Redis connectivity / 检查 Redis 连接
kubectl exec -n production POD_NAME -- curl -s localhost:8080/actuator/health | jq '.components.redis'

# Check all dependent service health / 检查所有依赖服务健康
kubectl exec -n production POD_NAME -- curl -s localhost:8080/actuator/health | jq '.'

# Get thread dump (if application appears hung) / 获取线程转储 (应用挂起时)
kubectl exec -n production POD_NAME -- jstack $(kubectl exec -n production POD_NAME -- pgrep -f java) 2>&1 | head -200
```

#### 3.3 VMAlert Endpoint Verification / VMAlert 端点验证

```bash
# Check all APM VMAlert instances for this critical alert / 检查所有 APM VMAlert 实例
for ip in 10.238.3.137 10.238.3.143 10.238.3.52; do
  echo "--- $ip ---"
  curl -s "http://$ip:8880/api/v1/alerts" | jq '.data.alerts[] | select(.labels.alertname == "ApmServiceExceptionsCritical")'
done
```

### 4. ACT (Remediation) / 处置 (修复)

**CRITICAL: Act fast. Exception rate >20/min means significant user impact.**
**紧急: 快速行动。异常率 >20/分钟意味着显著的用户影响。**

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---------|--------|------------|
| Bad deployment identified / 确认部署问题 | Immediate rollback / 立即回滚 | Tier 2 (do not wait) |
| DB connection failure / 数据库连接故障 | Check RDS, restart connection pools / 检查 RDS, 重启连接池 | Tier 2 |
| Cascading failure / 级联故障 | Enable circuit breakers, isolate service / 启用熔断, 隔离服务 | Tier 3 |
| Unknown with golden path impact / 原因不明且影响黄金路径 | Escalate to China HQ immediately / 立即升级到中国总部 | Tier 3 |

```bash
# EMERGENCY: Rollback deployment / 紧急: 回滚部署
kubectl rollout undo deployment/SERVICE_NAME -n production
kubectl rollout status deployment/SERVICE_NAME -n production --timeout=300s

# Scale up if load-related / 如果是负载相关问题, 扩容
kubectl scale deployment/SERVICE_NAME -n production --replicas=NEW_COUNT

# Pod restart if single pod issue / 单 Pod 问题时重启
kubectl delete pod POD_NAME -n production
```

**Escalation path / 升级路径:** App-Ops → Team Lead (5min) → China HQ Engineering (15min no resolution)

### 5. AFTERMATH (Post-Incident) / 事后 (事件后)

- **Mandatory incident report** for all Tier 1/critical incidents / 所有 Tier 1/危急事件必须提交事件报告
- Post-mortem within 24 hours / 24 小时内完成事后分析
- Review alert thresholds (20/min boundary between warning and critical) / 审查告警阈值
- Update deployment pipeline if deployment-related / 如与部署相关, 更新部署流水线
- Add regression test for the exception scenario / 增加该异常场景的回归测试

**Old Alert Reference / 旧告警参考:** ALR-060 (iZeus-策略1 异常>2), ALR-061~068 (策略2~9 duplicates), ALR-087 (默认策略 服务异常>20)

---

<a id="lck-ap-003"></a>
## LCK-AP-003: ApmLatencyP99Warning

### Metadata / 元数据

```yaml
alert_id: "LCK-AP-003"
alert_name: "ApmLatencyP99Warning"
severity: "warning"
tier: "2"
category: "apm"
team: "app-ops"
first_responder: "app-ops on-call"
sla_response: "Tier 2: 15min"
old_alert_ids: "ALR-070"
consolidation: "KEEP — direct mapping from legacy alert"
skill_reference: "/app/skills/apm-alert-investigation.md"
last_updated: "2026-02-16"
```

### PromQL Expression / 告警表达式

```promql
# Datasource: df8o21agxtkw0d (UMBQuerier-Luckin)
# Evaluation interval: 30s | for: 5m
service_resp_time_percentile{quantile="0.99", env="production"} > 1500
```

**Meaning / 含义:** Service p99 response time exceeds 1500ms for 5 minutes. 1% of requests are taking over 1.5 seconds, indicating user experience degradation.
服务 p99 响应时间超过 1500ms 持续 5 分钟。1% 的请求耗时超过 1.5 秒, 表明用户体验降级。

### 1. ASSESS (First 2 Minutes) / 评估 (前2分钟)

```bash
# Check which services have high latency / 检查哪些服务延迟高
curl -s "http://prometheus:9090/api/v1/query?query=topk(10, service_resp_time_percentile{quantile='0.99', env='production'} > 1500)" | \
  jq '.data.result[] | {service: .metric.service_name, p99_ms: .value[1]}'

# Check golden path order flow / 检查黄金路径订单流
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"

# Check if latency correlates with exception rate / 检查延迟是否与异常率相关
curl -s "http://prometheus:9090/api/v1/query?query=rate(service_exception_count{env='production'}[3m]) * 60 > 1"
```

### 2. ACKNOWLEDGE (Within 15 min SLA) / 确认 (15分钟 SLA)

```bash
amtool silence add alertname="ApmLatencyP99Warning" \
  --duration="30m" --comment="Investigating latency - YOUR_NAME" --author="YOUR_NAME"
```

### 3. ANALYZE (Root Cause) / 分析 (根因)

#### 3.1 Common Causes / 常见原因

```
[ ] Slow database queries (most common) / 慢查询 (最常见)
[ ] Redis latency spike / Redis 延迟飙升
[ ] Full GC pauses (check LCK-AP-005) / Full GC 暂停
[ ] Network latency to downstream services / 下游服务网络延迟
[ ] Thread pool saturation / 线程池饱和
[ ] Increased traffic without scaling / 流量增加但未扩容
```

#### 3.2 Diagnostic Commands / 诊断命令

```bash
# iZeus — Trace slow requests / 追踪慢请求
# URL: https://izeus.luckincoffee.us/trace?service={service_name}&start={timestamp}
# Navigate: Services → {service_name} → Slowest traces / 最慢链路

# Check percentile breakdown / 检查百分位分布
curl -s "http://prometheus:9090/api/v1/query?query=service_resp_time_percentile{quantile='0.99', env='production', service_name='SERVICE_NAME'}"
curl -s "http://prometheus:9090/api/v1/query?query=service_resp_time_percentile{quantile='0.95', env='production', service_name='SERVICE_NAME'}"
curl -s "http://prometheus:9090/api/v1/query?query=service_resp_time_percentile{quantile='0.50', env='production', service_name='SERVICE_NAME'}"

# Check if DB is the bottleneck / 检查数据库是否为瓶颈
# DevOps DB: aws-luckyus-devops-rw
# SQL: SELECT * FROM slow_query_log WHERE start_time > NOW() - INTERVAL 30 MINUTE ORDER BY query_time DESC LIMIT 20;

# Check JVM GC pauses (latency often correlates with GC) / 检查 JVM GC 暂停
curl -s "http://prometheus:9090/api/v1/query?query=increase(jvm_gc_count{gc_type='full', env='production', service_name='SERVICE_NAME'}[5m])"

# Check thread pool utilization / 检查线程池利用率
kubectl exec -n production POD_NAME -- curl -s localhost:8080/actuator/metrics/tomcat.threads.busy | jq '.'
kubectl exec -n production POD_NAME -- curl -s localhost:8080/actuator/metrics/tomcat.threads.config.max | jq '.'

# JVM thread dump to identify blocked threads / JVM 线程转储定位阻塞线程
kubectl exec -n production POD_NAME -- jstack $(kubectl exec -n production POD_NAME -- pgrep -f java) | grep -A 5 "BLOCKED\|WAITING"
```

### 4. ACT (Remediation) / 处置 (修复)

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---------|--------|------------|
| Slow DB queries / 慢查询 | Kill query, add index, escalate to DBA / 终止查询, 加索引, 升级到 DBA | Tier 2 |
| GC pauses / GC 暂停 | Tune JVM heap, restart pod / 调优 JVM 堆内存, 重启 Pod | Tier 2 |
| Thread pool saturation / 线程池饱和 | Scale up replicas, tune pool / 扩容副本, 调优线程池 | Tier 2 |
| Network issue / 网络问题 | Check VPC, security groups / 检查 VPC, 安全组 | Tier 2 → 3 |

```bash
# Scale up to handle load / 扩容处理负载
kubectl scale deployment/SERVICE_NAME -n production --replicas=NEW_COUNT

# Rolling restart to clear connection/thread issues / 滚动重启清除连接/线程问题
kubectl rollout restart deployment/SERVICE_NAME -n production
```

### 5. AFTERMATH (Post-Incident) / 事后 (事件后)

- Review 1500ms p99 threshold -- is it appropriate for this service? / 审查 1500ms p99 阈值
- Check if additional p95 or median latency alerts are needed / 检查是否需要 p95 或中位数延迟告警
- Consider adding per-endpoint latency alerts for critical APIs / 考虑为关键 API 增加端点级延迟告警

**Old Alert Reference / 旧告警参考:** ALR-070 (iZeus 响应>1500ms) -- direct KEEP mapping

---

<a id="lck-ap-004"></a>
## LCK-AP-004: ApmEndpointFailuresWarning

### Metadata / 元数据

```yaml
alert_id: "LCK-AP-004"
alert_name: "ApmEndpointFailuresWarning"
severity: "warning"
tier: "2"
category: "apm"
team: "app-ops"
first_responder: "app-ops on-call"
sla_response: "Tier 2: 15min"
old_alert_ids: "ALR-071, ALR-072, ALR-074, ALR-075"
consolidation: "MERGE — 4 iZeus endpoint failure strategy alerts merged"
skill_reference: "/app/skills/apm-alert-investigation.md"
last_updated: "2026-02-16"
```

### PromQL Expression / 告警表达式

```promql
# Datasource: df8o21agxtkw0d (UMBQuerier-Luckin)
# Evaluation interval: 30s | for: 5m
rate(endpoint_failure_count{env="production"}[3m]) * 60 > 2
```

**Meaning / 含义:** Specific endpoint failure rate exceeds 2 failures per minute (3-minute average), sustained for 5 minutes. One or more API endpoints are consistently failing.
特定端点失败速率超过每分钟 2 次 (3分钟均值), 持续 5 分钟。一个或多个 API 端点持续失败。

### 1. ASSESS (First 2 Minutes) / 评估 (前2分钟)

```bash
# Identify which endpoints are failing / 识别哪些端点在失败
curl -s "http://prometheus:9090/api/v1/query?query=topk(10, rate(endpoint_failure_count{env='production'}[3m]) * 60 > 2)" | \
  jq '.data.result[] | {service: .metric.service_name, endpoint: .metric.endpoint, rate: .value[1]}'

# Check if failing endpoint is on the golden path / 检查失败端点是否在黄金路径上
# Golden path endpoints: /order/create, /order/pay, /order/confirm, /menu/list
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"
```

### 2. ACKNOWLEDGE (Within 15 min SLA) / 确认 (15分钟 SLA)

```bash
amtool silence add alertname="ApmEndpointFailuresWarning" \
  --duration="30m" --comment="Investigating endpoint failures - YOUR_NAME" --author="YOUR_NAME"
```

### 3. ANALYZE (Root Cause) / 分析 (根因)

#### 3.1 Common Causes / 常见原因

```
[ ] Endpoint code bug (incorrect input handling) / 端点代码 Bug (输入处理不当)
[ ] Backend dependency for this endpoint is down / 该端点的后端依赖宕机
[ ] Rate limiting or circuit breaker tripped / 限流或熔断器触发
[ ] Invalid request pattern from client / 客户端无效请求模式
[ ] Endpoint-specific configuration error / 端点特定配置错误
```

#### 3.2 Diagnostic Commands / 诊断命令

```bash
# iZeus — Investigate failing endpoint / 调查失败端点
# URL: https://izeus.luckincoffee.us/trace?service={service_name}&start={timestamp}
# Navigate: Services → {service_name} → Endpoints → {endpoint} → Error traces

# Check endpoint-specific error logs / 检查端点特定错误日志
kubectl logs -n production -l app=SERVICE_NAME --tail=200 --since=10m | \
  grep -i "ENDPOINT_PATH" | grep -i "error\|exception\|fail" | tail -30

# Check HTTP status code distribution / 检查 HTTP 状态码分布
curl -s "http://prometheus:9090/api/v1/query?query=rate(endpoint_request_count{env='production', endpoint='ENDPOINT', status=~'5..'}[3m]) * 60"

# Check downstream service health from this endpoint / 从该端点检查下游服务健康
kubectl exec -n production POD_NAME -- curl -s localhost:8080/actuator/health | jq '.'

# VMAlert check / VMAlert 检查
curl -s "http://10.238.3.137:8880/api/v1/alerts" | jq '.data.alerts[] | select(.labels.alertname == "ApmEndpointFailuresWarning")'
```

### 4. ACT (Remediation) / 处置 (修复)

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---------|--------|------------|
| Endpoint bug / 端点 Bug | Rollback or hotfix / 回滚或热修复 | Tier 2 |
| Dependency down / 依赖宕机 | Fix dependency, enable fallback / 修复依赖, 启用降级 | Tier 2 |
| Invalid client requests / 客户端无效请求 | Identify client, add validation / 识别客户端, 添加校验 | Tier 2 |
| Rate limit issue / 限流问题 | Adjust rate limits / 调整限流 | Tier 2 |

```bash
# Rollback if deployment-related / 部署相关则回滚
kubectl rollout undo deployment/SERVICE_NAME -n production

# Restart if configuration issue / 配置问题则重启
kubectl rollout restart deployment/SERVICE_NAME -n production
```

### 5. AFTERMATH (Post-Incident) / 事后 (事件后)

- Consider adding per-endpoint alerts for golden path APIs / 考虑为黄金路径 API 增加端点级告警
- Review 2/min threshold for this endpoint / 审查该端点 2/分钟 阈值
- Add endpoint-specific integration tests / 增加端点级集成测试

**Old Alert Reference / 旧告警参考:** ALR-071 (iZeus-策略11 端点失败>=1), ALR-072 (策略12 端点失败>=1), ALR-074 (策略16 端点失败>2), ALR-075 (策略17 端点失败>3)

---

<a id="lck-ap-005"></a>
## LCK-AP-005: ApmJvmFullGcWarning

### Metadata / 元数据

```yaml
alert_id: "LCK-AP-005"
alert_name: "ApmJvmFullGcWarning"
severity: "warning"
tier: "2"
category: "apm"
team: "app-ops"
first_responder: "app-ops on-call"
sla_response: "Tier 2: 15min"
old_alert_ids: "ALR-069, ALR-079, ALR-085"
consolidation: "MERGE — 3 JVM/GC alerts merged (CPU, OAP-FGC, default strategy FGC/YGC)"
skill_reference: "/app/skills/apm-alert-investigation.md"
last_updated: "2026-02-16"
```

### PromQL Expression / 告警表达式

```promql
# Datasource: df8o21agxtkw0d (UMBQuerier-Luckin)
# Evaluation interval: 30s | for: 5m
increase(jvm_gc_count{gc_type="full", env="production"}[5m]) > 5
```

**Meaning / 含义:** More than 5 Full GC events in the last 5 minutes. Full GC causes stop-the-world pauses, leading to latency spikes and potential service unresponsiveness.
过去 5 分钟内发生超过 5 次 Full GC。Full GC 导致 Stop-The-World 暂停, 引起延迟飙升和潜在的服务无响应。

### 1. ASSESS (First 2 Minutes) / 评估 (前2分钟)

```bash
# Check which services have excessive Full GC / 检查哪些服务 Full GC 过多
curl -s "http://prometheus:9090/api/v1/query?query=topk(10, increase(jvm_gc_count{gc_type='full', env='production'}[5m]) > 5)" | \
  jq '.data.result[] | {service: .metric.service_name, instance: .metric.instance, gc_count: .value[1]}'

# Check if latency is also spiking (Full GC → high latency) / 检查延迟是否也在飙升
curl -s "http://prometheus:9090/api/v1/query?query=service_resp_time_percentile{quantile='0.99', env='production'} > 1000"

# Check golden path / 检查黄金路径
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"
```

### 2. ACKNOWLEDGE (Within 15 min SLA) / 确认 (15分钟 SLA)

```bash
amtool silence add alertname="ApmJvmFullGcWarning" \
  --duration="30m" --comment="Investigating Full GC - YOUR_NAME" --author="YOUR_NAME"
```

### 3. ANALYZE (Root Cause) / 分析 (根因)

#### 3.1 Common Causes / 常见原因

```
[ ] Memory leak in application / 应用内存泄漏
[ ] Heap size too small for workload / 堆大小不足
[ ] Large object allocation (cache, batch processing) / 大对象分配 (缓存, 批处理)
[ ] Metaspace exhaustion (class loading) / 元空间耗尽 (类加载)
[ ] Insufficient young generation space / 新生代空间不足
[ ] Traffic spike causing excessive object creation / 流量峰值导致对象创建过多
```

#### 3.2 Diagnostic Commands / 诊断命令

```bash
# JVM memory and GC statistics / JVM 内存和 GC 统计
kubectl exec -n production POD_NAME -- jstat -gcutil $(kubectl exec -n production POD_NAME -- pgrep -f java) 1000 10

# JVM heap usage / JVM 堆使用
kubectl exec -n production POD_NAME -- jstat -gccapacity $(kubectl exec -n production POD_NAME -- pgrep -f java)

# Check current GC algorithm and heap settings / 检查当前 GC 算法和堆设置
kubectl exec -n production POD_NAME -- jinfo -flags $(kubectl exec -n production POD_NAME -- pgrep -f java) | grep -i "heap\|gc\|metaspace"

# Heap histogram (top memory consumers) / 堆直方图 (最大内存消费者)
kubectl exec -n production POD_NAME -- jmap -histo:live $(kubectl exec -n production POD_NAME -- pgrep -f java) | head -30

# Heap dump (CAUTION: may cause pause, use only if critical) / 堆转储 (注意: 可能引起暂停, 仅紧急时使用)
# kubectl exec -n production POD_NAME -- jmap -dump:live,format=b,file=/tmp/heap_dump.hprof $(kubectl exec -n production POD_NAME -- pgrep -f java)

# Check GC count and timing via Prometheus / 通过 Prometheus 检查 GC 次数和时间
curl -s "http://prometheus:9090/api/v1/query?query=increase(jvm_gc_count{gc_type='full', env='production', service_name='SERVICE_NAME'}[5m])"
curl -s "http://prometheus:9090/api/v1/query?query=increase(jvm_gc_time{gc_type='full', env='production', service_name='SERVICE_NAME'}[5m])"

# Check young GC as well (YGC > 500ms is also concerning) / 也检查 Young GC
curl -s "http://prometheus:9090/api/v1/query?query=increase(jvm_gc_time{gc_type='young', env='production', service_name='SERVICE_NAME'}[5m])"

# Check Metaspace / 检查元空间
kubectl exec -n production POD_NAME -- jstat -gcmetacapacity $(kubectl exec -n production POD_NAME -- pgrep -f java)
```

#### 3.3 VMAlert Endpoint Verification / VMAlert 端点验证

```bash
for ip in 10.238.3.137 10.238.3.143 10.238.3.52; do
  echo "--- $ip ---"
  curl -s "http://$ip:8880/api/v1/alerts" | jq '.data.alerts[] | select(.labels.alertname == "ApmJvmFullGcWarning")'
done
```

### 4. ACT (Remediation) / 处置 (修复)

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---------|--------|------------|
| Memory leak / 内存泄漏 | Restart pod, schedule heap analysis / 重启 Pod, 安排堆分析 | Tier 2 |
| Heap too small / 堆太小 | Increase pod memory limits, tune JVM flags / 增加 Pod 内存限制, 调优 JVM 参数 | Tier 2 |
| Metaspace issue / 元空间问题 | Increase metaspace, check class loaders / 增加元空间, 检查类加载器 | Tier 2 |
| Traffic spike / 流量峰值 | Scale up pods / 扩容 Pod | Tier 2 |

```bash
# Rolling restart to recover from memory leak / 滚动重启从内存泄漏中恢复
kubectl rollout restart deployment/SERVICE_NAME -n production

# Scale up to distribute load / 扩容分散负载
kubectl scale deployment/SERVICE_NAME -n production --replicas=NEW_COUNT

# Tune JVM (update deployment YAML) / 调优 JVM (更新部署 YAML)
# Common JVM flags for GC tuning:
# -XX:+UseG1GC -XX:MaxGCPauseMillis=200 -XX:InitiatingHeapOccupancyPercent=45
# -Xms2g -Xmx2g -XX:MetaspaceSize=256m -XX:MaxMetaspaceSize=512m
```

### 5. AFTERMATH (Post-Incident) / 事后 (事件后)

- Analyze heap dump if captured / 如果捕获了堆转储, 进行分析
- Review JVM configuration across all Java services / 审查所有 Java 服务的 JVM 配置
- Consider adding Young GC time alerts / 考虑增加 Young GC 时间告警
- Update service capacity planning / 更新服务容量规划

**Old Alert Reference / 旧告警参考:** ALR-069 (iZeus JVM CPU>20), ALR-079 (iZeus OAP-FGC-5), ALR-085 (默认策略 FGC>0 / YGC>500ms)

---

<a id="lck-ap-006"></a>
## LCK-AP-006: ApmInfraHealthWarning

### Metadata / 元数据

```yaml
alert_id: "LCK-AP-006"
alert_name: "ApmInfraHealthWarning"
severity: "warning"
tier: "3"
category: "apm"
team: "app-ops"
first_responder: "app-ops on-call"
sla_response: "Tier 3: 5min"
old_alert_ids: "ALR-076, ALR-077, ALR-078, ALR-080, ALR-081, ALR-082, ALR-083, ALR-084"
consolidation: "MERGE — 8 iZeus node/storage/transfer health alerts merged"
skill_reference: "/app/skills/apm-alert-investigation.md"
last_updated: "2026-02-16"
```

### PromQL Expression / 告警表达式

```promql
# Datasource: df8o21agxtkw0d (UMBQuerier-Luckin)
# Evaluation interval: 30s | for: 3m
up{job=~"apm-.*", env="production"} == 0
```

**Meaning / 含义:** An APM infrastructure component (collector, OAP, receiver, storage) is down for 3 minutes. This creates monitoring blind spots -- application issues may go undetected.
APM 基础设施组件 (采集器, OAP, 接收器, 存储) 宕机 3 分钟。这会造成监控盲区 -- 应用问题可能无法被检测到。

**IMPORTANT / 重要:** This is Tier 3 despite being severity "warning" because APM blindness means other alerts may not fire.
尽管严重性为 "warning", 但这是 Tier 3, 因为 APM 失明意味着其他告警可能不会触发。

### 1. ASSESS (First 2 Minutes) / 评估 (前2分钟)

```bash
# Check which APM components are down / 检查哪些 APM 组件宕机
curl -s "http://prometheus:9090/api/v1/query?query=up{job=~'apm-.*', env='production'} == 0" | \
  jq '.data.result[] | {job: .metric.job, instance: .metric.instance}'

# Check ALL APM VMAlert instances are reachable / 检查所有 APM VMAlert 实例是否可达
for ip in 10.238.3.137 10.238.3.143 10.238.3.52; do
  echo "--- $ip ---"
  curl -s --connect-timeout 3 "http://$ip:8880/health" && echo " OK" || echo " UNREACHABLE"
done

# Check Basic VMAlert / 检查 Basic VMAlert
curl -s --connect-timeout 3 "http://10.238.3.153:8880/health" && echo " OK" || echo " UNREACHABLE"

# CRITICAL: Check if orders are still flowing (APM down doesn't mean app is down)
# 关键: 检查订单是否仍在流转 (APM 宕机不代表应用宕机)
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"
```

### 2. ACKNOWLEDGE (Within 5 min SLA -- Tier 3) / 确认 (5分钟 SLA -- Tier 3)

```bash
amtool silence add alertname="ApmInfraHealthWarning" \
  --duration="15m" --comment="Investigating APM infra - YOUR_NAME" --author="YOUR_NAME"
```

**WeCom Template (Critical Channel due to Tier 3) / 企业微信模板 (因 Tier 3 使用紧急频道):**
```
TIER 3 Alert Acknowledged / Tier 3 告警已确认
Alert: ApmInfraHealthWarning (LCK-AP-006)
Severity: warning | Tier: 3 (APM blindness risk)
Component: {job_name} at {instance}
Owner: {your_name}
Status: Investigating / 调查中
NOTE: Application may be healthy -- APM monitoring is impaired
注意: 应用可能正常 -- APM 监控受损
```

### 3. ANALYZE (Root Cause) / 分析 (根因)

#### 3.1 Common Causes / 常见原因

```
[ ] iZeus OAP node crashed or OOM / iZeus OAP 节点崩溃或 OOM
[ ] iZeus storage backend (ES) unavailable / iZeus 存储后端 (ES) 不可用
[ ] Network partition between APM components / APM 组件间网络分区
[ ] Node CPU/memory/disk exhaustion (legacy ALR-076~078) / 节点 CPU/内存/磁盘耗尽
[ ] Data pipeline issue (Agent→OAP, OAP→Receiver, Receiver→Storage) / 数据管道问题
[ ] APM collector process killed by systemd/K8s / APM 采集进程被系统终止
```

#### 3.2 Diagnostic Commands / 诊断命令

```bash
# Check APM component pods/VMs / 检查 APM 组件 Pod/VM
kubectl get pods -n monitoring -l app=izeus-oap -o wide
kubectl get pods -n monitoring -l app=izeus-receiver -o wide

# If APM runs on VMs, check the host / 如果 APM 运行在 VM 上, 检查主机
# APM nodes: 10.238.3.137, 10.238.3.143, 10.238.3.52
for ip in 10.238.3.137 10.238.3.143 10.238.3.52; do
  echo "=== $ip ==="
  ssh $ip "systemctl status oap-server 2>/dev/null || echo 'Service not found'"
  ssh $ip "free -h | head -2"
  ssh $ip "df -h / | tail -1"
  ssh $ip "uptime"
done

# Check APM component logs / 检查 APM 组件日志
kubectl logs -n monitoring -l app=izeus-oap --tail=50 --since=10m 2>/dev/null || echo "Not running in K8s"
ssh 10.238.3.137 "tail -50 /opt/oap/logs/oap.log 2>/dev/null || echo 'Log not found'"

# Check iZeus storage backend (Elasticsearch) / 检查 iZeus 存储后端 (Elasticsearch)
curl -s "http://ES_ENDPOINT:9200/_cluster/health" | jq '{status, number_of_nodes, active_shards, unassigned_shards}'

# Check data pipeline transfer metrics / 检查数据管道传输指标
# Relevant old alerts: Agent→OAP, OAP→OAP, OAPTrace→Receiver, Receiver→Thanos, Receiver→VM
curl -s "http://prometheus:9090/api/v1/query?query={__name__=~'apm_.*_transfer.*', env='production'}"
```

### 4. ACT (Remediation) / 处置 (修复)

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---------|--------|------------|
| OAP node crashed / OAP 节点崩溃 | Restart OAP service / 重启 OAP 服务 | Tier 3 |
| ES backend down / ES 后端宕机 | Restart ES, check cluster health / 重启 ES, 检查集群健康 | Tier 3 |
| Node resource exhaustion / 节点资源耗尽 | Clear disk, restart processes / 清理磁盘, 重启进程 | Tier 3 |
| Network partition / 网络分区 | Check VPC, SGs, route tables / 检查 VPC, 安全组, 路由表 | Tier 3 |

```bash
# Restart OAP on affected node / 在受影响节点重启 OAP
ssh AFFECTED_IP "systemctl restart oap-server"

# If K8s managed / 如果 K8s 管理
kubectl rollout restart deployment/izeus-oap -n monitoring

# Emergency: Restart receiver / 紧急: 重启接收器
ssh AFFECTED_IP "systemctl restart izeus-receiver"

# Clear disk if >85% full / 磁盘 >85% 时清理
ssh AFFECTED_IP "find /opt/oap/logs -name '*.log' -mtime +7 -delete"
```

**Escalation / 升级:** This is Tier 3 -- if not resolved in 15 minutes, escalate to China HQ Engineering for APM platform support.
这是 Tier 3 -- 如果 15 分钟内未解决, 升级到中国总部工程团队寻求 APM 平台支持。

### 5. AFTERMATH (Post-Incident) / 事后 (事件后)

- Verify all APM data pipelines restored / 验证所有 APM 数据管道已恢复
- Check for gaps in monitoring data during outage / 检查宕机期间监控数据的缺口
- Review APM infrastructure capacity / 审查 APM 基础设施容量
- Consider adding redundancy for single-point APM components / 考虑为单点 APM 组件增加冗余
- Verify Elasticsearch cluster health / 验证 Elasticsearch 集群健康

**Old Alert Reference / 旧告警参考:** ALR-076 (iZeus Node-CPU-85), ALR-077 (iZeus Node-Disk-85), ALR-078 (iZeus Node-Memory-95), ALR-080 (iZeus Storage-Receiver2Thanos), ALR-081 (iZeus Storage-Receiver2VM), ALR-082 (iZeus Transfer-Agent2OAP), ALR-083 (iZeus Transfer-OAP2OAP), ALR-084 (iZeus Transfer-OAPTrace2Receiver)

---

## Appendix A: APM Alert Summary / 附录 A: APM 告警总览

### Alert Overview Table / 告警总览表

| Alert ID | Alert Name | Severity | Tier | Threshold | for | Old IDs | Action |
|----------|-----------|----------|------|-----------|-----|---------|--------|
| LCK-AP-001 | ApmServiceExceptionsWarning | warning | 2 | >5 and <=20/min | 5m | ALR-060~068, 073, 086, 088 | MERGE |
| LCK-AP-002 | ApmServiceExceptionsCritical | critical | 1 | >20/min | 3m | ALR-060~068, 087 | MERGE |
| LCK-AP-003 | ApmLatencyP99Warning | warning | 2 | p99 >1500ms | 5m | ALR-070 | KEEP |
| LCK-AP-004 | ApmEndpointFailuresWarning | warning | 2 | >2/min | 5m | ALR-071, 072, 074, 075 | MERGE |
| LCK-AP-005 | ApmJvmFullGcWarning | warning | 2 | >5 Full GC/5min | 5m | ALR-069, 079, 085 | MERGE |
| LCK-AP-006 | ApmInfraHealthWarning | warning | 3 | up == 0 | 3m | ALR-076~078, 080~084 | MERGE |

### Consolidation Summary / 合并摘要

- **Before / 合并前:** 29 legacy iZeus alerts (ALR-060 through ALR-088)
- **After / 合并后:** 6 new alerts (LCK-AP-001 through LCK-AP-006)
- **Reduction / 缩减:** 79% (23 alerts eliminated, mostly duplicates from iZeus策略1~9)
- **Key improvement / 关键改进:** Two-tier exception alerting (5/min warning, 20/min critical) replaces 9 identical strategy alerts

### Complete Old-to-New Alert Mapping / 新旧告警完整映射

| Old ID | Old Name (Chinese) | Action | New ID | New Alert Name |
|--------|-------------------|--------|--------|---------------|
| ALR-060 | iZeus-策略1 异常>2 | MERGE | LCK-AP-001/002 | ServiceExceptionRate (two-tier) |
| ALR-061 | iZeus-策略2 异常>2 | ELIMINATE | -- | Duplicate of ALR-060 |
| ALR-062 | iZeus-策略3 异常>2 | ELIMINATE | -- | Duplicate of ALR-060 |
| ALR-063 | iZeus-策略4 异常>2 | ELIMINATE | -- | Duplicate of ALR-060 |
| ALR-064 | iZeus-策略5 异常>3 | ELIMINATE | -- | Duplicate of ALR-060 |
| ALR-065 | iZeus-策略6 异常>2 | ELIMINATE | -- | Duplicate of ALR-060 |
| ALR-066 | iZeus-策略7 异常>2 | ELIMINATE | -- | Duplicate of ALR-060 |
| ALR-067 | iZeus-策略8 异常>2 | ELIMINATE | -- | Duplicate of ALR-060 |
| ALR-068 | iZeus-策略9 异常>2 | ELIMINATE | -- | Duplicate of ALR-060 |
| ALR-069 | iZeus JVM CPU>20 | MERGE | LCK-AP-005 | JVMFullGC_Warning |
| ALR-070 | iZeus 响应>1500ms | KEEP | LCK-AP-003 | ServiceLatencyHigh_Warning |
| ALR-071 | iZeus-策略11 端点失败>=1 | MERGE | LCK-AP-004 | EndpointFailure_Warning |
| ALR-072 | iZeus-策略12 端点失败>=1 | MERGE | LCK-AP-004 | EndpointFailure_Warning |
| ALR-073 | iZeus-策略15 异常>3 | MERGE | LCK-AP-001 | ServiceExceptionRate_Warning |
| ALR-074 | iZeus-策略16 端点失败>2 | MERGE | LCK-AP-004 | EndpointFailure_Warning |
| ALR-075 | iZeus-策略17 端点失败>3 | MERGE | LCK-AP-004 | EndpointFailure_Warning |
| ALR-076 | iZeus Node-CPU-85 | MERGE | LCK-AP-006 | APMInfraHealth_Warning |
| ALR-077 | iZeus Node-Disk-85 | MERGE | LCK-AP-006 | APMInfraHealth_Warning |
| ALR-078 | iZeus Node-Memory-95 | MERGE | LCK-AP-006 | APMInfraHealth_Warning |
| ALR-079 | iZeus OAP-FGC-5 | MERGE | LCK-AP-005 | JVMFullGC_Warning |
| ALR-080 | iZeus Storage-Receiver2Thanos | MERGE | LCK-AP-006 | APMInfraHealth_Warning |
| ALR-081 | iZeus Storage-Receiver2VM | MERGE | LCK-AP-006 | APMInfraHealth_Warning |
| ALR-082 | iZeus Transfer-Agent2OAP | MERGE | LCK-AP-006 | APMInfraHealth_Warning |
| ALR-083 | iZeus Transfer-OAP2OAP | MERGE | LCK-AP-006 | APMInfraHealth_Warning |
| ALR-084 | iZeus Transfer-OAPTrace2Receiver | MERGE | LCK-AP-006 | APMInfraHealth_Warning |
| ALR-085 | 默认策略 FGC>0 / YGC>500ms | MERGE | LCK-AP-005 | JVMFullGC_Warning |
| ALR-086 | 默认策略 okhttp异常>50 | MERGE | LCK-AP-001 | ServiceExceptionRate_Warning |
| ALR-087 | 默认策略 服务异常>20 | MERGE | LCK-AP-002 | ServiceExceptionRate_Critical |
| ALR-088 | 默认策略 服务异常>5 | MERGE | LCK-AP-001 | ServiceExceptionRate_Warning |

---

## Appendix B: Environment Reference / 附录 B: 环境参考

### VMAlert APM Endpoints / VMAlert APM 端点

| Instance | IP:Port | Role / 角色 |
|----------|---------|------|
| APM-1 | 10.238.3.137:8880 | APM alert evaluation / APM 告警评估 |
| APM-2 | 10.238.3.143:8880 | APM alert evaluation / APM 告警评估 |
| APM-3 | 10.238.3.52:8880 | APM alert evaluation / APM 告警评估 |
| Basic | 10.238.3.153:8880 | Infrastructure alert evaluation / 基础设施告警评估 |

### Verified Datasource UIDs / 已验证数据源 UID

| Datasource | UID | Purpose / 用途 |
|------------|-----|---------|
| UMBQuerier-Luckin | `df8o21agxtkw0d` | Primary Prometheus (APM, node, business metrics) |
| prometheus | `ff7hkeec6c9a8e` | General metrics / 通用指标 |
| prometheus_redis | `ff6p0gjt24phce` | Redis/ElastiCache metrics |

### Key AWS Resources / 关键 AWS 资源

| Resource / 资源 | Identifier / 标识 | Notes / 备注 |
|----------|-----------|-------|
| AWS Account | 257394478466 | Production / 生产 |
| Region | us-east-1 | Primary / 主要 |
| EKS Cluster | luckyus-prod | Main K8s cluster / 主 K8s 集群 |
| DevOps DB | aws-luckyus-devops-rw | Service registry, alert logs / 服务注册, 告警日志 |

### WeCom Notification Channels / 企业微信通知渠道

| Channel / 渠道 | Tier | Recipients / 接收人 |
|---------|------|------------|
| wecom-info | Tier 1 | US DevOps (text only) |
| wecom-warning | Tier 2 | US DevOps + Team Lead (text + phone lead) |
| wecom-critical | Tier 3 | All DevOps US + China HQ (text + phone all) |

### iZeus APM URLs / iZeus APM 链接

```
# iZeus Dashboard / iZeus 仪表板:
https://izeus.luckincoffee.us/

# Service trace URL pattern / 服务链路追踪 URL 模式:
https://izeus.luckincoffee.us/trace?service={service_name}&start={timestamp}

# Grafana APM dashboards / Grafana APM 仪表板:
https://grafana.luckinus.com/d/apm-services   — Service overview / 服务总览
https://grafana.luckinus.com/d/apm-latency    — Latency analysis / 延迟分析
https://grafana.luckinus.com/d/apm-endpoints  — Endpoint details / 端点详情
https://grafana.luckinus.com/d/apm-jvm        — JVM metrics / JVM 指标
https://grafana.luckinus.com/d/apm-infra      — APM infrastructure / APM 基础设施
```

---

*End of Part 8: APM (Application Performance) — 6 alerts*
*第8部分结束: APM (应用性能) — 6 条告警*
*Generated: 2026-02-16 | Format: 5 A's Pattern (Bilingual EN/CN)*

# Luckin Coffee NA -- Alert Runbook Part 10: PLATFORM (Platform Services)
# 瑞幸咖啡北美 -- 告警运行手册 第10部分: PLATFORM (平台服务)

> **Version / 版本:** 1.0
> **Date / 日期:** 2026-02-17
> **Category / 类别:** PLATFORM -- Platform Services / 平台服务
> **Alert Group / 告警组:** `lck-na.alerts.platform` (interval: 30s)
> **Alerts in this part / 本部分告警数:** 4 (LCK-PT-001 through LCK-PT-004)
> **Consolidation / 合并:** 21 legacy alerts merged into 4 new alerts (81% reduction)
> **Format / 格式:** 5 A's Pattern (Assess, Acknowledge, Analyze, Act, Aftermath)
> **Skill Reference / 技能参考:** N/A (Platform services monitoring)
> **Platform:** AWS us-east-1 | EKS: luckyus-prod | Account: 257394478466

---

## Table of Contents / 目录

| Alert ID | Name | Severity | Tier | Page |
|----------|------|----------|------|------|
| [LCK-PT-001](#lck-pt-001) | PlatformSmsDeliveryWarning | warning | 2 | SMS Delivery Rate Warning |
| [LCK-PT-002](#lck-pt-002) | PlatformRiskControlPreWarning | warning | 2 | Risk Control Pre-Warning |
| [LCK-PT-003](#lck-pt-003) | PlatformRiskControlCircuitBreakerCritical | critical | 3 | Risk Control Circuit Breaker Critical |
| [LCK-PT-004](#lck-pt-004) | PlatformGatewayErrorRateCritical | critical | 3 | Gateway Error Rate Critical |

---

<a id="lck-pt-001"></a>
## LCK-PT-001: PlatformSmsDeliveryWarning

### Metadata / 元数据

```yaml
alert_id: "LCK-PT-001"
alert_name: "PlatformSmsDeliveryWarning"
severity: "warning"
tier: "2"
category: "platform"
team: "platform-ops"
first_responder: "platform-ops on-call"
sla_response: "Tier 2: 15min"
old_alert_ids: "ALR-100, ALR-101, ALR-102, ALR-103, ALR-104, ALR-105, ALR-106, ALR-107, ALR-108"
consolidation: "MERGE — 9 legacy SMS/notification alerts merged into one warning-level delivery rate alert"
skill_reference: "N/A"
last_updated: "2026-02-17"
```

### PromQL Expression / 告警表达式

```promql
# Datasource: df8o21agxtkw0d (UMBQuerier-Luckin)
# Evaluation interval: 30s | for: 5m
(
  sum(rate(sms_delivery_failure_total{env="production"}[5m]))
  /
  sum(rate(sms_delivery_total{env="production"}[5m]))
) * 100 > 10
```

**Meaning / 含义:** SMS delivery failure rate exceeds 10% over a 5-minute window, sustained for 5 minutes. Verification codes and order notifications may not reach customers reliably.
短信投递失败率超过 10% (5分钟窗口), 持续 5 分钟。验证码和订单通知可能无法可靠到达客户。

### 1. ASSESS (First 2 Minutes) / 评估 (前2分钟)

**Goal / 目标:** Determine if SMS delivery failures are impacting the golden path (user registration, login, ordering).
判断短信投递失败是否影响黄金路径 (用户注册、登录、下单)。

#### 1.1 Golden Path Impact Check / 黄金路径影响检查

```bash
# Check if new user registrations are dropping / 检查新用户注册是否下降
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"

# Check SMS delivery failure rate breakdown / 检查短信投递失败率分布
curl -s "http://prometheus:9090/api/v1/query?query=(sum(rate(sms_delivery_failure_total{env='production'}[5m])) / sum(rate(sms_delivery_total{env='production'}[5m]))) * 100"
```

#### 1.2 Quick Triage / 快速分诊

```bash
# Check SMS failure breakdown by type (OTP vs notification) / 按类型检查短信失败 (OTP vs 通知)
curl -s "http://prometheus:9090/api/v1/query?query=sort_desc(rate(sms_delivery_failure_total{env='production'}[5m]))" | \
  jq '.data.result[] | {type: .metric.sms_type, provider: .metric.provider, rate: .value[1]}'

# Check if this is isolated or part of an alert storm / 检查是否为孤立告警或告警风暴
curl -s "http://alertmanager:9093/api/v2/alerts?filter=category%3D%22platform%22" | jq '.[].labels | {alertname, severity}'

# Check AWS SNS service health / 检查 AWS SNS 服务健康
aws sns get-sms-attributes --region us-east-1
```

#### 1.3 Severity Classification / 严重性分类

| Condition / 条件 | Severity / 严重性 | Action / 操作 |
|-----------|----------|--------|
| OTP delivery blocked (login/register impossible) / OTP 投递阻断 (无法登录/注册) | **Escalate to Tier 3** | Wake China HQ / 通知中国总部 |
| Failure rate 10-30%, some OTPs delayed / 失败率10-30%, 部分OTP延迟 | **Warning -- Tier 2** | Platform-Ops investigates / Platform-Ops 调查 |
| Notification SMS only, OTP unaffected / 仅通知短信, OTP不受影响 | **Monitor -- Tier 1** | Watch for 15 min / 观察 15 分钟 |

### 2. ACKNOWLEDGE (Within 15 min SLA) / 确认 (15分钟 SLA)

```bash
# Silence alert during investigation (30 min) / 调查期间静默告警 (30分钟)
amtool silence add alertname="PlatformSmsDeliveryWarning" \
  --duration="30m" --comment="Investigating - YOUR_NAME" --author="YOUR_NAME"
```

**WeCom Template / 企业微信模板:**
```
Alert Acknowledged / 告警已确认
Alert: PlatformSmsDeliveryWarning (LCK-PT-001)
Severity: warning | Tier: 2
Owner: {your_name}
Status: Investigating / 调查中
ETA for update: {time + 15min}
```

### 3. ANALYZE (Root Cause) / 分析 (根因)

#### 3.1 Common Causes / 常见原因

```
[ ] AWS SNS regional issue or throttling / AWS SNS 区域问题或限流
[ ] SMS provider (Twilio/SNS) quota exhausted / 短信供应商配额耗尽
[ ] Invalid phone number format in user data / 用户数据中电话号码格式错误
[ ] upush service pod crash or OOM / upush 服务 Pod 崩溃或 OOM
[ ] Network connectivity to SMS provider / 与短信供应商的网络连通性
[ ] Rate limiting by carrier / 运营商限流
```

#### 3.2 Diagnostic Commands / 诊断命令

```bash
# Check upush service pods / 检查 upush 服务 Pod
kubectl get pods -n production -l app=upush -o wide
kubectl logs -n production -l app=upush --tail=100 --since=10m | grep -i "error\|fail\|timeout" | tail -30

# Check AWS SNS delivery stats / 检查 AWS SNS 投递统计
aws cloudwatch get-metric-statistics --namespace AWS/SNS \
  --metric-name NumberOfNotificationsFailed --period 300 --statistics Sum \
  --start-time $(date -u -d '30 min ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --region us-east-1

# Check upush database connection / 检查 upush 数据库连接
mysql -h aws-luckyus-upush-rw -e "SHOW PROCESSLIST" | head -20

# Check SMS queue depth / 检查短信队列深度
curl -s "http://prometheus:9090/api/v1/query?query=sms_queue_pending_total{env='production'}"
```

#### 3.3 VMAlert Endpoint Verification / VMAlert 端点验证

```bash
# Check Platform VMAlert instances / 检查 Platform VMAlert 实例
curl -s "http://10.238.3.153:8880/api/v1/alerts" | jq '.data.alerts[] | select(.labels.alertname == "PlatformSmsDeliveryWarning")'
```

### 4. ACT (Remediation) / 处置 (修复)

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---------|--------|------------|
| AWS SNS throttling / AWS SNS 限流 | Switch to Twilio backup, request SNS limit increase / 切换到 Twilio 备份, 申请 SNS 配额提升 | Tier 2 |
| upush pods unhealthy / upush Pod 异常 | Restart pods, check resource limits / 重启 Pod, 检查资源限制 | Tier 2 |
| Provider quota exhausted / 供应商配额耗尽 | Failover to backup provider / 切换到备用供应商 | Tier 2 |
| All providers failing / 所有供应商故障 | Escalate to Tier 3 / 升级到 Tier 3 | Tier 2 → 3 |

```bash
# Restart upush service / 重启 upush 服务
kubectl rollout restart deployment/upush -n production
kubectl rollout status deployment/upush -n production --timeout=300s

# Failover to Twilio backup (if SNS down) / 切换到 Twilio 备份 (如 SNS 故障)
kubectl set env deployment/upush -n production SMS_PRIMARY_PROVIDER=twilio
```

### 5. AFTERMATH (Post-Incident) / 事后 (事件后)

- Update this runbook with new root cause if discovered / 如发现新根因, 更新本手册
- Review if threshold (10% failure rate) is appropriate / 审查阈值 (10%失败率) 是否合理
- Verify SMS provider SLA compliance / 验证短信供应商 SLA 达标情况
- File incident report for Tier 2+ incidents / Tier 2+ 事件需提交事件报告

**Old Alert Reference / 旧告警参考:** ALR-100 (SMS投递失败>5%), ALR-101 (OTP发送超时>3s), ALR-102 (短信队列积压>1000), ALR-103 (SNS投递异常), ALR-104 (Twilio API错误), ALR-105 (upush服务异常), ALR-106 (验证码发送失败), ALR-107 (通知短信延迟>30s), ALR-108 (短信供应商切换)

---

<a id="lck-pt-002"></a>
## LCK-PT-002: PlatformRiskControlPreWarning

### Metadata / 元数据

```yaml
alert_id: "LCK-PT-002"
alert_name: "PlatformRiskControlPreWarning"
severity: "warning"
tier: "2"
category: "platform"
team: "platform-ops"
first_responder: "platform-ops on-call"
sla_response: "Tier 2: 15min"
old_alert_ids: "ALR-110, ALR-111, ALR-112, ALR-113, ALR-114, ALR-115, ALR-116"
consolidation: "MERGE — 7 legacy risk control alerts merged into one warning-level pre-warning alert"
skill_reference: "N/A"
last_updated: "2026-02-17"
```

### PromQL Expression / 告警表达式

```promql
# Datasource: df8o21agxtkw0d (UMBQuerier-Luckin)
# Evaluation interval: 30s | for: 5m
(
  sum(rate(risk_control_block_total{env="production"}[5m]))
  /
  sum(rate(risk_control_evaluation_total{env="production"}[5m]))
) * 100 > 5
```

**Meaning / 含义:** Risk control block rate exceeds 5% of all evaluations over a 5-minute window, sustained for 5 minutes. Legitimate users may be getting blocked by overly aggressive rules.
风控拦截率超过所有评估的 5% (5分钟窗口), 持续 5 分钟。合法用户可能被过于激进的规则拦截。

### 1. ASSESS (First 2 Minutes) / 评估 (前2分钟)

**Goal / 目标:** Determine if risk control is blocking legitimate user transactions on the golden path (ordering, payments).
判断风控是否在黄金路径 (下单、支付) 上拦截合法用户交易。

#### 1.1 Golden Path Impact Check / 黄金路径影响检查

```bash
# Check if completed orders are dropping / 检查完成订单是否下降
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"

# Check risk control block rate / 检查风控拦截率
curl -s "http://prometheus:9090/api/v1/query?query=(sum(rate(risk_control_block_total{env='production'}[5m])) / sum(rate(risk_control_evaluation_total{env='production'}[5m]))) * 100"
```

#### 1.2 Quick Triage / 快速分诊

```bash
# Check block rate by rule / 按规则检查拦截率
curl -s "http://prometheus:9090/api/v1/query?query=sort_desc(rate(risk_control_block_total{env='production'}[5m]))" | \
  jq '.data.result[] | {rule: .metric.rule_name, action: .metric.action, rate: .value[1]}'

# Check if this is isolated or part of an alert storm / 检查是否为孤立告警或告警风暴
curl -s "http://alertmanager:9093/api/v2/alerts?filter=category%3D%22platform%22" | jq '.[].labels | {alertname, severity}'

# Check iriskcontrolservice pods / 检查风控服务 Pod
kubectl get pods -n production -l app=iriskcontrolservice -o wide
```

#### 1.3 Severity Classification / 严重性分类

| Condition / 条件 | Severity / 严重性 | Action / 操作 |
|-----------|----------|--------|
| Legitimate orders being blocked >10% / 合法订单拦截>10% | **Escalate to Tier 3** | Wake China HQ / 通知中国总部 |
| Block rate 5-10%, some false positives / 拦截率5-10%, 部分误报 | **Warning -- Tier 2** | Platform-Ops investigates / Platform-Ops 调查 |
| Block rate near threshold, mostly bots / 接近阈值, 主要是机器人 | **Monitor -- Tier 1** | Watch for 15 min / 观察 15 分钟 |

### 2. ACKNOWLEDGE (Within 15 min SLA) / 确认 (15分钟 SLA)

```bash
# Silence alert during investigation (30 min) / 调查期间静默告警 (30分钟)
amtool silence add alertname="PlatformRiskControlPreWarning" \
  --duration="30m" --comment="Investigating - YOUR_NAME" --author="YOUR_NAME"
```

**WeCom Template / 企业微信模板:**
```
Alert Acknowledged / 告警已确认
Alert: PlatformRiskControlPreWarning (LCK-PT-002)
Severity: warning | Tier: 2
Owner: {your_name}
Status: Investigating / 调查中
ETA for update: {time + 15min}
```

### 3. ANALYZE (Root Cause) / 分析 (根因)

#### 3.1 Common Causes / 常见原因

```
[ ] Risk rule threshold too aggressive after recent update / 风控规则阈值更新后过于激进
[ ] Spike in bot/fraud traffic triggering legitimate-user blocks / 机器人/欺诈流量激增导致合法用户被拦截
[ ] Risk control model drift (ML model needs retraining) / 风控模型漂移 (ML模型需重训)
[ ] iriskcontrolservice resource exhaustion (slow evaluation) / 风控服务资源耗尽 (评估变慢)
[ ] Redis cache failure (risk scores not cached, all evaluated as new) / Redis 缓存故障
[ ] Config center pushed new rules / 配置中心推送了新规则
```

#### 3.2 Diagnostic Commands / 诊断命令

```bash
# Check iriskcontrolservice pods and logs / 检查风控服务 Pod 和日志
kubectl get pods -n production -l app=iriskcontrolservice -o wide
kubectl logs -n production -l app=iriskcontrolservice --tail=100 --since=10m | grep -i "block\|reject\|error" | tail -30

# Check risk control Redis cache / 检查风控 Redis 缓存
redis-cli -h luckyus-iriskcontrolservice -p 6379 INFO keyspace

# Check recent config changes / 检查近期配置变更
mysql -h aws-luckyus-iriskcontrolservice-rw -e "SELECT * FROM risk_rule_change_log ORDER BY created_at DESC LIMIT 10"

# Check risk evaluation latency / 检查风控评估延迟
curl -s "http://prometheus:9090/api/v1/query?query=histogram_quantile(0.99, rate(risk_evaluation_duration_seconds_bucket{env='production'}[5m]))"
```

#### 3.3 VMAlert Endpoint Verification / VMAlert 端点验证

```bash
# Check Platform VMAlert instances / 检查 Platform VMAlert 实例
curl -s "http://10.238.3.153:8880/api/v1/alerts" | jq '.data.alerts[] | select(.labels.alertname == "PlatformRiskControlPreWarning")'
```

### 4. ACT (Remediation) / 处置 (修复)

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---------|--------|------------|
| Overly aggressive rule / 规则过于激进 | Roll back rule change via config center / 通过配置中心回滚规则变更 | Tier 2 |
| Bot traffic spike / 机器人流量激增 | Tune WAF rules, whitelist known-good patterns / 调整 WAF 规则, 白名单已知正常模式 | Tier 2 |
| Redis cache failure / Redis 缓存故障 | Restart Redis, check memory / 重启 Redis, 检查内存 | Tier 2 |
| Model drift, unable to fix quickly / 模型漂移, 无法快速修复 | Escalate to Tier 3 / 升级到 Tier 3 | Tier 2 → 3 |

```bash
# Rollback risk control rules via config center / 通过配置中心回滚风控规则
kubectl exec -n production $(kubectl get pod -n production -l app=ibizconfigcenter -o jsonpath='{.items[0].metadata.name}') -- curl -X POST http://localhost:8080/api/rollback/risk-rules

# Restart iriskcontrolservice / 重启风控服务
kubectl rollout restart deployment/iriskcontrolservice -n production
kubectl rollout status deployment/iriskcontrolservice -n production --timeout=300s
```

### 5. AFTERMATH (Post-Incident) / 事后 (事件后)

- Update this runbook with new root cause if discovered / 如发现新根因, 更新本手册
- Review if threshold (5% block rate) is appropriate / 审查阈值 (5%拦截率) 是否合理
- Review risk control rules for false positive rate / 审查风控规则的误报率
- File incident report for Tier 2+ incidents / Tier 2+ 事件需提交事件报告

**Old Alert Reference / 旧告警参考:** ALR-110 (风控拦截率>3%), ALR-111 (风控评估超时>500ms), ALR-112 (风控规则异常), ALR-113 (风控Redis缓存失效), ALR-114 (风控模型加载失败), ALR-115 (风控服务异常>10次/分), ALR-116 (风控误拦截率>2%)

---

<a id="lck-pt-003"></a>
## LCK-PT-003: PlatformRiskControlCircuitBreakerCritical

### Metadata / 元数据

```yaml
alert_id: "LCK-PT-003"
alert_name: "PlatformRiskControlCircuitBreakerCritical"
severity: "critical"
tier: "3"
category: "platform"
team: "platform-ops"
first_responder: "platform-ops on-call"
sla_response: "Tier 3: Immediate (0 min)"
old_alert_ids: "ALR-120, ALR-121"
consolidation: "MERGE — 2 legacy circuit breaker alerts merged into one critical alert"
skill_reference: "N/A"
last_updated: "2026-02-17"
```

### PromQL Expression / 告警表达式

```promql
# Datasource: df8o21agxtkw0d (UMBQuerier-Luckin)
# Evaluation interval: 30s | for: 1m
risk_control_circuit_breaker_state{env="production"} == 1
```

**Meaning / 含义:** Risk control circuit breaker has tripped OPEN, meaning all risk evaluations are being bypassed. The system is allowing ALL transactions through without fraud/risk checks. Critical security exposure.
风控熔断器已触发打开, 所有风控评估被跳过。系统允许所有交易通过而不进行欺诈/风险检查。严重安全暴露。

### 1. ASSESS (First 2 Minutes) / 评估 (前2分钟)

**Goal / 目标:** CRITICAL -- Risk control is completely bypassed. All transactions pass without fraud checks. Immediate action needed.
紧急 -- 风控完全被旁路。所有交易不经欺诈检查即通过。需要立即行动。

#### 1.1 Golden Path Impact Check / 黄金路径影响检查

```bash
# Check if orders are still flowing (they should be -- circuit breaker allows all through) / 检查订单是否正常 (应该正常 -- 熔断允许所有通过)
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"

# Check circuit breaker state / 检查熔断器状态
curl -s "http://prometheus:9090/api/v1/query?query=risk_control_circuit_breaker_state{env='production'}"
```

#### 1.2 Quick Triage / 快速分诊

```bash
# Check what triggered the circuit breaker / 检查触发熔断的原因
kubectl logs -n production -l app=iriskcontrolservice --tail=200 --since=10m | grep -i "circuit\|breaker\|open\|trip" | tail -20

# Check for concurrent platform alerts / 检查并发平台告警
curl -s "http://alertmanager:9093/api/v2/alerts?filter=severity%3D%22critical%22" | \
  jq '.[].labels | {alertname, severity}'

# Check risk control service health / 检查风控服务健康
kubectl get pods -n production -l app=iriskcontrolservice -o wide
```

#### 1.3 Severity Classification / 严重性分类

| Condition / 条件 | Severity / 严重性 | Action / 操作 |
|-----------|----------|--------|
| Circuit breaker open, all checks bypassed / 熔断打开, 所有检查被跳过 | **Critical -- Tier 3** | Immediate escalation to China HQ / 立即升级到中国总部 |
| Circuit breaker flapping / 熔断器抖动 | **Critical -- Tier 2+** | All hands on deck / 全员响应 |
| Circuit breaker closed (auto-recovered) / 熔断器关闭 (自动恢复) | **Monitor closely** | Investigate root cause / 调查根因 |

### 2. ACKNOWLEDGE (Within Immediate SLA) / 确认 (立即响应 SLA)

```bash
# Silence alert briefly (15 min max for critical) / 短暂静默告警 (危急最长15分钟)
amtool silence add alertname="PlatformRiskControlCircuitBreakerCritical" \
  --duration="15m" --comment="CRITICAL investigating - YOUR_NAME" --author="YOUR_NAME"
```

**WeCom Template / 企业微信模板:**
```
CRITICAL Alert Acknowledged / 严重告警已确认
Alert: PlatformRiskControlCircuitBreakerCritical (LCK-PT-003)
Severity: critical | Tier: 3
Owner: {your_name}
Status: CRITICAL - Risk control bypassed / 严重 - 风控已被旁路
Impact: All transactions unprotected / 所有交易无保护
ETA for update: {time + 5min}
```

### 3. ANALYZE (Root Cause) / 分析 (根因)

#### 3.1 Common Causes / 常见原因

```
[ ] Risk control service completely down (all pods crashed) / 风控服务完全宕机 (所有Pod崩溃)
[ ] Redis dependency failure causing evaluation timeouts / Redis 依赖故障导致评估超时
[ ] Database connection pool exhaustion / 数据库连接池耗尽
[ ] Risk control service OOM killed / 风控服务 OOM 被杀
[ ] Network partition between risk service and dependencies / 风控服务与依赖间网络分区
[ ] Upstream traffic spike overwhelming risk service / 上游流量激增压垮风控服务
```

#### 3.2 Diagnostic Commands / 诊断命令

```bash
# Check iriskcontrolservice pod status / 检查风控服务 Pod 状态
kubectl get pods -n production -l app=iriskcontrolservice -o wide
kubectl describe pods -n production -l app=iriskcontrolservice | grep -A5 "State:\|Reason:\|Last State:"

# Check pod restarts and OOM events / 检查 Pod 重启和 OOM 事件
kubectl get events -n production --field-selector involvedObject.name=iriskcontrolservice --sort-by='.lastTimestamp' | tail -20

# Check risk control Redis / 检查风控 Redis
redis-cli -h luckyus-iriskcontrolservice -p 6379 PING
redis-cli -h luckyus-iriskcontrolservice -p 6379 INFO memory

# Check risk control database / 检查风控数据库
mysql -h aws-luckyus-iriskcontrolservice-rw -e "SHOW PROCESSLIST" | head -20
```

#### 3.3 VMAlert Endpoint Verification / VMAlert 端点验证

```bash
# Check Platform VMAlert instances / 检查 Platform VMAlert 实例
curl -s "http://10.238.3.153:8880/api/v1/alerts" | jq '.data.alerts[] | select(.labels.alertname == "PlatformRiskControlCircuitBreakerCritical")'
```

### 4. ACT (Remediation) / 处置 (修复)

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---------|--------|------------|
| Risk service pods crashed / 风控服务 Pod 崩溃 | Restart pods, scale up replicas / 重启 Pod, 扩容副本 | Tier 3 |
| Redis dependency down / Redis 依赖宕机 | Failover Redis, restart risk service / Redis 故障转移, 重启风控服务 | Tier 3 |
| OOM killed / OOM 被杀 | Increase memory limits, restart / 增加内存限制, 重启 | Tier 3 |
| Traffic spike / 流量激增 | Scale pods, enable rate limiting / 扩容 Pod, 启用限流 | Tier 3 |

```bash
# Emergency: Scale up risk control service / 紧急: 扩容风控服务
kubectl scale deployment/iriskcontrolservice -n production --replicas=5
kubectl rollout status deployment/iriskcontrolservice -n production --timeout=300s

# Emergency: Restart all risk control pods / 紧急: 重启所有风控 Pod
kubectl rollout restart deployment/iriskcontrolservice -n production

# Manually close circuit breaker if service is healthy / 如服务健康, 手动关闭熔断器
kubectl exec -n production $(kubectl get pod -n production -l app=iriskcontrolservice -o jsonpath='{.items[0].metadata.name}') -- curl -X POST http://localhost:8080/actuator/circuitbreaker/reset
```

### 5. AFTERMATH (Post-Incident) / 事后 (事件后)

- MANDATORY incident report for all circuit breaker events / 所有熔断事件必须提交事件报告
- Review circuit breaker threshold configuration / 审查熔断器阈值配置
- Audit transactions during bypass period for fraud / 审计旁路期间的交易是否存在欺诈
- Review risk service capacity and scaling policies / 审查风控服务容量和扩缩容策略
- Consider adding fallback risk evaluation mode / 考虑添加降级风控评估模式

**Old Alert Reference / 旧告警参考:** ALR-120 (风控熔断器打开), ALR-121 (风控服务全部宕机)

---

<a id="lck-pt-004"></a>
## LCK-PT-004: PlatformGatewayErrorRateCritical

### Metadata / 元数据

```yaml
alert_id: "LCK-PT-004"
alert_name: "PlatformGatewayErrorRateCritical"
severity: "critical"
tier: "3"
category: "platform"
team: "platform-ops"
first_responder: "platform-ops on-call"
sla_response: "Tier 3: Immediate (0 min)"
old_alert_ids: "ALR-130, ALR-131, ALR-132"
consolidation: "MERGE — 3 legacy gateway/ingress alerts merged into one critical error rate alert"
skill_reference: "N/A"
last_updated: "2026-02-17"
```

### PromQL Expression / 告警表达式

```promql
# Datasource: df8o21agxtkw0d (UMBQuerier-Luckin)
# Evaluation interval: 30s | for: 2m
(
  sum(rate(http_server_requests_total{env="production", status=~"5.."}[3m]))
  /
  sum(rate(http_server_requests_total{env="production"}[3m]))
) * 100 > 5
```

**Meaning / 含义:** API Gateway 5xx error rate exceeds 5% of all requests over a 3-minute window, sustained for 2 minutes. The gateway is the entry point for ALL mobile app traffic -- this means widespread user-facing failures.
API 网关 5xx 错误率超过所有请求的 5% (3分钟窗口), 持续 2 分钟。网关是所有移动端流量的入口 -- 这意味着大范围的用户端故障。

### 1. ASSESS (First 2 Minutes) / 评估 (前2分钟)

**Goal / 目标:** CRITICAL -- The API gateway is the single entry point for all mobile app traffic. Gateway failures mean ALL users are impacted.
紧急 -- API 网关是所有移动端流量的唯一入口。网关故障意味着所有用户受影响。

#### 1.1 Golden Path Impact Check / 黄金路径影响检查

```bash
# Check if orders are dropping / 检查订单是否下降
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"

# Check gateway error rate / 检查网关错误率
curl -s "http://prometheus:9090/api/v1/query?query=(sum(rate(http_server_requests_total{env='production', status=~'5..'}[3m])) / sum(rate(http_server_requests_total{env='production'}[3m]))) * 100"
```

#### 1.2 Quick Triage / 快速分诊

```bash
# Check error rate by backend service / 按后端服务检查错误率
curl -s "http://prometheus:9090/api/v1/query?query=sort_desc(sum by (service)(rate(http_server_requests_total{env='production', status=~'5..'}[3m])))" | \
  jq '.data.result[] | {service: .metric.service, rate: .value[1]}'

# Check for concurrent critical alerts / 检查并发严重告警
curl -s "http://alertmanager:9093/api/v2/alerts?filter=severity%3D%22critical%22" | \
  jq '.[].labels | {alertname, severity}'

# Check ALB/Ingress health / 检查 ALB/Ingress 健康
kubectl get ingress -n production
kubectl get pods -n ingress-nginx -o wide
```

#### 1.3 Severity Classification / 严重性分类

| Condition / 条件 | Severity / 严重性 | Action / 操作 |
|-----------|----------|--------|
| Gateway errors >5%, orders impacted / 网关错误>5%, 订单受影响 | **Critical -- Tier 3** | Immediate escalation to China HQ / 立即升级到中国总部 |
| Errors concentrated on one backend / 错误集中在一个后端 | **Critical -- Tier 2+** | Isolate failing service / 隔离故障服务 |
| Transient spike resolving / 瞬时峰值恢复中 | **Monitor closely** | Watch for recurrence / 监控复发 |

### 2. ACKNOWLEDGE (Within Immediate SLA) / 确认 (立即响应 SLA)

```bash
# Silence alert briefly (15 min max for critical) / 短暂静默告警 (危急最长15分钟)
amtool silence add alertname="PlatformGatewayErrorRateCritical" \
  --duration="15m" --comment="CRITICAL investigating - YOUR_NAME" --author="YOUR_NAME"
```

**WeCom Template / 企业微信模板:**
```
CRITICAL Alert Acknowledged / 严重告警已确认
Alert: PlatformGatewayErrorRateCritical (LCK-PT-004)
Severity: critical | Tier: 3
Owner: {your_name}
Status: CRITICAL - Gateway errors affecting all users / 严重 - 网关错误影响所有用户
Impact: All mobile app traffic / 所有移动端流量
ETA for update: {time + 5min}
```

### 3. ANALYZE (Root Cause) / 分析 (根因)

#### 3.1 Common Causes / 常见原因

```
[ ] Backend service crash/restart causing 502/503 / 后端服务崩溃/重启导致 502/503
[ ] Ingress controller (nginx) pod crash or OOM / Ingress 控制器 Pod 崩溃或 OOM
[ ] ALB target group health check failures / ALB 目标组健康检查失败
[ ] SSL certificate expiration / SSL 证书过期
[ ] DNS resolution failure / DNS 解析故障
[ ] DDoS attack overwhelming gateway / DDoS 攻击压垮网关
```

#### 3.2 Diagnostic Commands / 诊断命令

```bash
# Check ingress controller pods / 检查 Ingress 控制器 Pod
kubectl get pods -n ingress-nginx -o wide
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=100 --since=10m | grep -i "error\|5[0-9][0-9]\|upstream" | tail -30

# Check ALB target health / 检查 ALB 目标健康
aws elbv2 describe-target-health --target-group-arn $(aws elbv2 describe-target-groups --query 'TargetGroups[?contains(TargetGroupName, `luckyus`)].TargetGroupArn' --output text | head -1) --region us-east-1

# Check SSL certificate status / 检查 SSL 证书状态
aws acm list-certificates --region us-east-1 --query 'CertificateSummaryList[?DomainName==`*.luckincoffee.us`]'

# Check top error paths / 检查错误最多的路径
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=1000 --since=10m | grep " 5[0-9][0-9] " | awk '{print $7}' | sort | uniq -c | sort -rn | head -20

# Check DNS resolution / 检查 DNS 解析
nslookup api.luckincoffee.us
```

#### 3.3 VMAlert Endpoint Verification / VMAlert 端点验证

```bash
# Check Platform VMAlert instances / 检查 Platform VMAlert 实例
curl -s "http://10.238.3.153:8880/api/v1/alerts" | jq '.data.alerts[] | select(.labels.alertname == "PlatformGatewayErrorRateCritical")'
```

### 4. ACT (Remediation) / 处置 (修复)

| Scenario / 场景 | Action / 操作 | Authority / 权限 |
|---------|--------|------------|
| Backend service crashed / 后端服务崩溃 | Restart backend, rollback if recent deploy / 重启后端, 如近期有部署则回滚 | Tier 3 |
| Ingress controller unhealthy / Ingress 控制器异常 | Restart ingress pods, scale up / 重启 Ingress Pod, 扩容 | Tier 3 |
| SSL certificate expired / SSL 证书过期 | Renew via ACM, update ingress / 通过 ACM 续期, 更新 Ingress | Tier 3 |
| DDoS attack / DDoS 攻击 | Enable AWS Shield, WAF rate limiting / 启用 AWS Shield, WAF 限流 | Tier 3 |

```bash
# Restart ingress controller / 重启 Ingress 控制器
kubectl rollout restart deployment/ingress-nginx-controller -n ingress-nginx
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s

# Scale up ingress controller for traffic handling / 扩容 Ingress 控制器处理流量
kubectl scale deployment/ingress-nginx-controller -n ingress-nginx --replicas=5

# Rollback failing backend service / 回滚故障后端服务
kubectl rollout undo deployment/SERVICE_NAME -n production
kubectl rollout status deployment/SERVICE_NAME -n production --timeout=300s

# Emergency: Enable WAF rate limiting / 紧急: 启用 WAF 限流
aws wafv2 update-web-acl --region us-east-1 --name luckyus-prod-waf --scope REGIONAL \
  --default-action '{"Allow":{}}' --rules file:///tmp/waf-rate-limit-rules.json
```

### 5. AFTERMATH (Post-Incident) / 事后 (事件后)

- MANDATORY incident report for all gateway critical events / 所有网关严重事件必须提交事件报告
- Review gateway capacity and auto-scaling configuration / 审查网关容量和自动扩缩容配置
- Verify SSL certificate auto-renewal is working / 验证 SSL 证书自动续期正常
- Review WAF and DDoS protection settings / 审查 WAF 和 DDoS 防护设置
- Load test gateway to validate capacity planning / 压测网关验证容量规划

**Old Alert Reference / 旧告警参考:** ALR-130 (网关5xx错误率>3%), ALR-131 (Ingress控制器异常), ALR-132 (ALB目标组不健康)

---

## Appendix A: Platform Alert Summary / 附录 A: 平台告警总览

### Alert Overview Table / 告警总览表

| Alert ID | Alert Name | Severity | Tier | Threshold | for | Old IDs | Action |
|----------|-----------|----------|------|-----------|-----|---------|--------|
| LCK-PT-001 | PlatformSmsDeliveryWarning | warning | 2 | >10% failure rate | 5m | ALR-100~108 | MERGE |
| LCK-PT-002 | PlatformRiskControlPreWarning | warning | 2 | >5% block rate | 5m | ALR-110~116 | MERGE |
| LCK-PT-003 | PlatformRiskControlCircuitBreakerCritical | critical | 3 | breaker == OPEN | 1m | ALR-120~121 | MERGE |
| LCK-PT-004 | PlatformGatewayErrorRateCritical | critical | 3 | >5% 5xx rate | 2m | ALR-130~132 | MERGE |

### Consolidation Summary / 合并摘要

- **Before / 合并前:** 21 legacy platform alerts (ALR-100 through ALR-132)
- **After / 合并后:** 4 new alerts (LCK-PT-001 through LCK-PT-004)
- **Reduction / 缩减:** 81% (17 alerts eliminated, mostly duplicates and overlapping thresholds)
- **Key improvement / 关键改进:** Consolidated SMS, risk control, and gateway monitoring into focused two-tier alerting with clear escalation paths

### Complete Old-to-New Alert Mapping / 新旧告警完整映射

| Old ID | Old Name (Chinese) | Action | New ID | New Alert Name |
|--------|-------------------|--------|--------|---------------|
| ALR-100 | SMS投递失败>5% | MERGE | LCK-PT-001 | PlatformSmsDeliveryWarning |
| ALR-101 | OTP发送超时>3s | MERGE | LCK-PT-001 | PlatformSmsDeliveryWarning |
| ALR-102 | 短信队列积压>1000 | MERGE | LCK-PT-001 | PlatformSmsDeliveryWarning |
| ALR-103 | SNS投递异常 | MERGE | LCK-PT-001 | PlatformSmsDeliveryWarning |
| ALR-104 | Twilio API错误 | MERGE | LCK-PT-001 | PlatformSmsDeliveryWarning |
| ALR-105 | upush服务异常 | MERGE | LCK-PT-001 | PlatformSmsDeliveryWarning |
| ALR-106 | 验证码发送失败 | MERGE | LCK-PT-001 | PlatformSmsDeliveryWarning |
| ALR-107 | 通知短信延迟>30s | MERGE | LCK-PT-001 | PlatformSmsDeliveryWarning |
| ALR-108 | 短信供应商切换 | MERGE | LCK-PT-001 | PlatformSmsDeliveryWarning |
| ALR-110 | 风控拦截率>3% | MERGE | LCK-PT-002 | PlatformRiskControlPreWarning |
| ALR-111 | 风控评估超时>500ms | MERGE | LCK-PT-002 | PlatformRiskControlPreWarning |
| ALR-112 | 风控规则异常 | MERGE | LCK-PT-002 | PlatformRiskControlPreWarning |
| ALR-113 | 风控Redis缓存失效 | MERGE | LCK-PT-002 | PlatformRiskControlPreWarning |
| ALR-114 | 风控模型加载失败 | MERGE | LCK-PT-002 | PlatformRiskControlPreWarning |
| ALR-115 | 风控服务异常>10次/分 | MERGE | LCK-PT-002 | PlatformRiskControlPreWarning |
| ALR-116 | 风控误拦截率>2% | MERGE | LCK-PT-002 | PlatformRiskControlPreWarning |
| ALR-120 | 风控熔断器打开 | MERGE | LCK-PT-003 | PlatformRiskControlCircuitBreakerCritical |
| ALR-121 | 风控服务全部宕机 | MERGE | LCK-PT-003 | PlatformRiskControlCircuitBreakerCritical |
| ALR-130 | 网关5xx错误率>3% | MERGE | LCK-PT-004 | PlatformGatewayErrorRateCritical |
| ALR-131 | Ingress控制器异常 | MERGE | LCK-PT-004 | PlatformGatewayErrorRateCritical |
| ALR-132 | ALB目标组不健康 | MERGE | LCK-PT-004 | PlatformGatewayErrorRateCritical |

---

## Appendix B: Environment Reference / 附录 B: 环境参考

### VMAlert Platform Endpoints / VMAlert 平台端点

| Instance | IP:Port | Role / 角色 |
|----------|---------|------|
| Basic | 10.238.3.153:8880 | Infrastructure/Platform alert evaluation / 基础设施/平台告警评估 |

### Verified Datasource UIDs / 已验证数据源 UID

| Datasource | UID | Purpose / 用途 |
|------------|-----|---------|
| UMBQuerier-Luckin | `df8o21agxtkw0d` | Primary Prometheus (platform, node, business metrics) |
| prometheus | `ff7hkeec6c9a8e` | General metrics / 通用指标 |
| prometheus_redis | `ff6p0gjt24phce` | Redis/ElastiCache metrics |

### Key AWS Resources / 关键 AWS 资源

| Resource / 资源 | Identifier / 标识 | Notes / 备注 |
|----------|-----------|-------|
| AWS Account | 257394478466 | Production / 生产 |
| Region | us-east-1 | Primary / 主要 |
| EKS Cluster | luckyus-prod | Main K8s cluster / 主 K8s 集群 |
| SNS | us-east-1 | SMS delivery (primary) / 短信投递 (主) |
| WAF | luckyus-prod-waf | Web Application Firewall / Web 应用防火墙 |
| ALB | luckyus-prod-alb | Application Load Balancer |
| ACM | *.luckincoffee.us | SSL certificates / SSL 证书 |
| Route 53 | luckincoffee.us | DNS management / DNS 管理 |

### WeCom Notification Channels / 企业微信通知渠道

| Channel / 渠道 | Tier | Recipients / 接收人 |
|---------|------|------------|
| wecom-info | Tier 1 | US DevOps (text only) |
| wecom-warning | Tier 2 | US DevOps + Team Lead (text + phone lead) |
| wecom-critical | Tier 3 | All DevOps US + China HQ (text + phone all) |

### Escalation Path / 升级路径

```
Tier 1 (Info) → wecom-info → US DevOps monitors
Tier 2 (Warning) → wecom-warning → Platform-Ops on-call investigates (15min SLA)
Tier 3 (Critical) → wecom-critical → All DevOps + China HQ (Immediate SLA)
```

### Platform Service URLs / 平台服务链接

```
# Grafana Platform dashboards / Grafana 平台仪表板:
https://grafana.luckinus.com/d/platform-sms     — SMS delivery / 短信投递
https://grafana.luckinus.com/d/platform-risk     — Risk control / 风控
https://grafana.luckinus.com/d/platform-gateway  — API Gateway / API 网关
https://grafana.luckinus.com/d/platform-overview — Platform overview / 平台总览

# AWS Console links / AWS 控制台链接:
https://console.aws.amazon.com/sns/v3/home?region=us-east-1  — SNS
https://console.aws.amazon.com/wafv2/home?region=us-east-1   — WAF
https://console.aws.amazon.com/acm/home?region=us-east-1     — ACM
```

---

*End of Part 10: PLATFORM (Platform Services) -- 4 alerts*
*第10部分结束: PLATFORM (平台服务) -- 4 条告警*
*Generated: 2026-02-17 | Format: 5 A's Pattern (Bilingual EN/CN)*

# Part 1: BIZ — Business Metrics / 业务指标

> 10 Alerts: BIZ-01 through BIZ-10
> Team: biz-ops | Datasource: `df8o21agxtkw0d` (UMBQuerier-Luckin)

---

## BIZ-01: BizOrderVolumeInfo

```yaml
alert_id: "LCK-BIZ-01"
alert_name: "BizOrderVolumeInfo"
severity: "info"
tier: "1"
category: "BIZ"
team: "biz-ops"
first_responder: "biz-ops on-call"
sla_response: "30min acknowledge | 2h first update | 8h resolution"
old_ids_replaced: ["low_order_volume_info"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
sum(increase(business_completed_orders_total{env="production"}[10m])) < 5 and
sum(increase(business_completed_orders_total{env="production"}[10m])) >= 3
```
**Trigger:** `for: 10m` | **Meaning / 含义:** Completed orders dropped below 5 but still ≥3 in a 10-minute window. Mild slowdown in ordering activity. 10分钟内完成订单降至5以下但仍≥3，轻微订单放缓。

**Golden Path Impact / 黄金流程影响:** Low — orders still flowing, monitor for further degradation. 低影响，订单仍在流转。

**Quick Triage / 快速分类:**
```bash
# Check current order rate / 检查当前订单速率
curl -s "http://prometheus:9090/api/v1/query?query=sum(increase(business_completed_orders_total{env=\"production\"}[10m]))"
# Check if specific stores are down / 检查是否有门店停止下单
curl -s "http://prometheus:9090/api/v1/query?query=increase(business_completed_orders_total{env=\"production\"}[10m])"
```

### 2. ACKNOWLEDGE / 确认

- Silence alert for **1 hour** (Tier 1 SLA) / 静默告警1小时
- Post to **wecom-info** channel / 发送到wecom-info频道
- No phone escalation needed / 无需电话通知

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
1. Off-peak hours (normal low volume between 9PM-6AM ET) / 非高峰时段正常低量
2. Local holiday or weather event / 当地节假日或天气事件
3. App deployment in progress / App正在部署
4. Payment gateway latency / 支付网关延迟

**Diagnostic Commands / 诊断命令:**
```bash
# Check order trend last 1h / 检查最近1小时订单趋势
# PromQL: sum(increase(business_completed_orders_total{env="production"}[10m]))
# Check payment system health / 检查支付系统健康
# PromQL: sum(increase(business_payment_amount_total{env="production"}[10m]))
# Check app API latency / 检查App API延迟
# PromQL: histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{service=~".*order.*"}[5m])) by (le))
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 1 | Monitor for 30 min. If volume recovers, close. If drops further, escalate. 监控30分钟，恢复则关闭，继续下降则升级。 |
| Tier 2 | Check payment/menu services. Coordinate with app team. 检查支付/菜单服务，协调App团队。 |

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** BIZ-02 (Warning), BIZ-03 (Critical), BIZ-05 (Payment Warning)
- **Prevention / 预防:** Establish baseline order volume per time-of-day per store. 建立每个门店各时段的基线订单量。
- **KB Update:** If new root cause found, add to Section 3 common causes. 如发现新根因，添加到第3节常见原因。

---

## BIZ-02: BizOrderVolumeWarning

```yaml
alert_id: "LCK-BIZ-02"
alert_name: "BizOrderVolumeWarning"
severity: "warning"
tier: "2"
category: "BIZ"
team: "biz-ops"
first_responder: "biz-ops on-call"
sla_response: "15min acknowledge | 1h first update | 4h resolution"
old_ids_replaced: ["low_order_volume_warning"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
sum(increase(business_completed_orders_total{env="production"}[10m])) < 3 and
sum(increase(business_completed_orders_total{env="production"}[10m])) >= 1
```
**Trigger:** `for: 10m` | **Meaning / 含义:** Completed orders near-zero (1-2 per 10 min). Significant ordering disruption. 10分钟内仅1-2笔订单完成，严重订单中断。

**Golden Path Impact / 黄金流程影响:** Medium — golden path severely degraded, customers likely unable to complete orders reliably. 中等影响，用户下单流程严重受阻。

**Quick Triage / 快速分类:**
```bash
# Same as BIZ-01 but check for broader service issues / 同BIZ-01但检查更广泛的服务问题
# Check all backend services / 检查所有后端服务
kubectl get pods -n production --no-headers | awk '{print $1, $3}' | grep -v Running
```

### 2. ACKNOWLEDGE / 确认

- Silence alert for **30 minutes** (Tier 2 SLA) / 静默告警30分钟
- Post to **wecom-warning** channel / 发送到wecom-warning频道
- **Phone Team Lead** via Twilio / 电话通知Team Lead

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
1. Backend service outage (order/payment/menu) / 后端服务故障
2. Database connection exhaustion / 数据库连接耗尽
3. Redis cache failure affecting sessions / Redis缓存故障影响会话
4. CDN or API gateway issue / CDN或API网关问题
5. Recent bad deployment / 最近的错误部署

**Diagnostic Commands / 诊断命令:**
```bash
# Check all critical service pods / 检查所有关键服务Pod
kubectl get pods -n production -l tier=critical -o wide
# Check RDS connections / 检查RDS连接数
# PromQL: aws_rds_database_connections_average{dbinstance_identifier=~".*order.*|.*payment.*"}
# Check Redis health / 检查Redis健康状态
# PromQL: redis_up{cluster=~"luckyus-.*"}
# Check recent deployments / 检查最近部署
kubectl get events -n production --sort-by='.lastTimestamp' --field-selector reason=Pulling | tail -10
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 2 | Identify failing service. Restart if needed. Rollback recent deployment if correlated. 定位故障服务，必要时重启，如与近期部署相关则回滚。 |
| Tier 3 | If unresolved in 30 min, escalate to Tier 3. Notify China HQ. 30分钟未解决则升级到Tier 3，通知中国总部。 |

**Remediation / 修复:**
```bash
# Restart failing order service / 重启故障的订单服务
kubectl rollout restart deployment/order-service -n production
# Rollback if deployment caused issue / 如部署导致问题则回滚
kubectl rollout undo deployment/order-service -n production
```

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** BIZ-01 (Info), BIZ-03 (Critical), BIZ-05/06 (Payment)
- **Prevention / 预防:** Implement canary deployments for order-critical services. 对订单关键服务实施金丝雀部署。

---

## BIZ-03: BizOrderVolumeCritical

```yaml
alert_id: "LCK-BIZ-03"
alert_name: "BizOrderVolumeCritical"
severity: "critical"
tier: "3"
category: "BIZ"
team: "biz-ops"
first_responder: "biz-ops on-call"
sla_response: "5min acknowledge | 15min first update | 1h resolution"
old_ids_replaced: ["low_order_volume_critical"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
sum(increase(business_completed_orders_total{env="production"}[10m])) < 1
```
**Trigger:** `for: 10m` | **Meaning / 含义:** ZERO completed orders for 10+ minutes. Complete ordering system failure. 10分钟以上零订单完成，订单系统完全瘫痪。

**Golden Path Impact / 黄金流程影响:** **CRITICAL — Golden path is DOWN. No revenue flowing. 严重——黄金流程中断，无收入流入。**

### 2. ACKNOWLEDGE / 确认

- Silence alert for **15 minutes** (Tier 3 SLA) / 静默告警15分钟
- Post to **wecom-critical** channel / 发送到wecom-critical频道
- **Phone ALL DevOps + China HQ** via Twilio / 电话通知所有DevOps和中国总部
- Start incident bridge immediately / 立即启动故障桥接

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
1. Complete backend outage / 后端完全宕机
2. Database failover or outage / 数据库故障转移或宕机
3. Network partition / 网络分区
4. Payment provider outage / 支付服务商故障
5. DNS resolution failure / DNS解析故障
6. EKS cluster issues / EKS集群问题

**Diagnostic Commands / 诊断命令:**
```bash
# IMMEDIATE: Check golden path metrics / 立即检查黄金流程指标
# PromQL: sum_over_time(business_completed_orders_total[10m])
# Check ALL critical pods / 检查所有关键Pod
kubectl get pods -n production --field-selector 'status.phase!=Running'
# Check node health / 检查节点健康
kubectl get nodes --no-headers | grep -v " Ready "
# Check RDS status / 检查RDS状态
aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus]' --output table --region us-east-1
# Check external dependencies / 检查外部依赖
kubectl get endpoints -n production | grep -E "order|payment|menu"
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 3 | **ALL HANDS.** Identify root cause within 15 min. Execute emergency remediation. 全员响应，15分钟内定位根因，执行紧急修复。 |

**Emergency Remediation / 紧急修复:**
```bash
# If deployment-related: immediate rollback / 如部署相关：立即回滚
kubectl rollout undo deployment/order-service -n production
kubectl rollout undo deployment/payment-service -n production
# If RDS-related: force failover / 如RDS相关：强制故障转移
aws rds reboot-db-instance --db-instance-identifier aws-luckyus-salesorder-rw --force-failover --region us-east-1
# If EKS node issues: cordon and reschedule / 如EKS节点问题：隔离并重新调度
kubectl cordon <bad-node>
kubectl drain <bad-node> --ignore-daemonsets --delete-emptydir-data
```

### 5. AFTERMATH / 善后

- **Post-incident review MANDATORY within 24h** / 24小时内必须进行事后回顾
- **Related Alerts / 相关告警:** BIZ-01, BIZ-02, BIZ-06 (Payment Critical), RDS-11 (VIP Unreachable), RDS-12 (Failover)
- **Revenue Impact:** Calculate lost revenue = avg_orders_per_10min × avg_order_value × downtime_minutes/10. 计算收入损失。

---

## BIZ-04: BizCancellationSpikeWarning

```yaml
alert_id: "LCK-BIZ-04"
alert_name: "BizCancellationSpikeWarning"
severity: "warning"
tier: "2"
category: "BIZ"
team: "biz-ops"
first_responder: "biz-ops on-call"
sla_response: "15min acknowledge | 1h first update | 4h resolution"
old_ids_replaced: ["order_cancellation_spike"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
sum(increase(business_cancelled_orders_total{env="production"}[5m])) > 1
```
**Trigger:** `for: 5m` | **Meaning / 含义:** More than 1 cancellation in 5 minutes sustained for 5 min. Unusual cancellation activity. 5分钟内超过1笔取消订单并持续5分钟，异常取消活动。

**Golden Path Impact / 黄金流程影响:** Medium — orders are being placed but cancelled, indicating fulfillment or quality issues. 中等——订单在下单后被取消，可能是履约或质量问题。

### 2. ACKNOWLEDGE / 确认

- Silence for **30 min** / Post to **wecom-warning** / Phone Team Lead

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
1. Store operational issues (out of stock, machine down) / 门店运营问题（缺货、设备故障）
2. Long wait times causing customer cancellation / 等待时间过长导致客户取消
3. Payment processing errors causing auto-cancel / 支付处理错误导致自动取消
4. System bug creating duplicate orders that auto-cancel / 系统Bug创建重复订单后自动取消

**Diagnostic Commands / 诊断命令:**
```bash
# Check cancellation by store / 按门店检查取消订单
# PromQL: increase(business_cancelled_orders_total{env="production"}[5m])
# Check cancel reasons from DB / 从数据库检查取消原因
# Server: aws-luckyus-salesorder-rw
# SQL: SELECT cancel_reason, COUNT(*) c FROM t_order WHERE status='cancelled' AND updated_at > NOW() - INTERVAL 30 MINUTE GROUP BY cancel_reason ORDER BY c DESC LIMIT 20;
# Check payment errors / 检查支付错误
# PromQL: sum(increase(business_payment_failures_total{env="production"}[10m]))
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 2 | Identify if store-level or system-wide. If store-level, coordinate with ops. If system-wide, investigate backend. 判断是门店级别还是全系统，相应协调运营或调查后端。 |

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** BIZ-01/02/03 (Order Volume), BIZ-05/06 (Payment)
- **Prevention / 预防:** Add cancel-reason breakdown to monitoring dashboard. 在监控面板添加取消原因分类。

---

## BIZ-05: BizPaymentAmountWarning

```yaml
alert_id: "LCK-BIZ-05"
alert_name: "BizPaymentAmountWarning"
severity: "warning"
tier: "2"
category: "BIZ"
team: "biz-ops"
first_responder: "biz-ops on-call"
sla_response: "15min acknowledge | 1h first update | 4h resolution"
old_ids_replaced: ["payment_amount_low"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
sum(increase(business_payment_amount_total{env="production"}[10m])) < 500 and
sum(increase(business_payment_amount_total{env="production"}[10m])) > 0
```
**Trigger:** `for: 10m` | **Meaning / 含义:** Payment revenue dropped below $500 in 10 min but still >$0. Revenue significantly reduced. 10分钟内支付金额低于$500但仍>$0，收入显著降低。

**Golden Path Impact / 黄金流程影响:** Medium — payments processing but revenue impacted. 中等——支付仍在处理但收入受影响。

### 2. ACKNOWLEDGE / 确认

- Silence for **30 min** / Post to **wecom-warning** / Phone Team Lead

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
1. Correlated with order volume drop (check BIZ-01/02) / 与订单量下降相关
2. Payment gateway partial outage / 支付网关部分故障
3. Promotion/coupon system issue (orders at $0) / 促销/优惠券系统问题
4. Off-peak hours (normal) / 非高峰时段（正常）

**Diagnostic Commands / 诊断命令:**
```bash
# Check order volume correlation / 检查订单量关联
# PromQL: sum(increase(business_completed_orders_total{env="production"}[10m]))
# Check average order value / 检查平均客单价
# Server: aws-luckyus-salespayment-rw
# SQL: SELECT AVG(amount) avg_amount, COUNT(*) cnt FROM t_payment WHERE status='success' AND created_at > NOW() - INTERVAL 30 MINUTE;
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 2 | If correlated with order drop, focus on BIZ-02. If payment-specific, investigate payment service. 如与订单下降相关，聚焦BIZ-02；如支付独立问题，调查支付服务。 |

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** BIZ-06 (Payment Critical), BIZ-01/02/03 (Order Volume)

---

## BIZ-06: BizPaymentAmountCritical

```yaml
alert_id: "LCK-BIZ-06"
alert_name: "BizPaymentAmountCritical"
severity: "critical"
tier: "3"
category: "BIZ"
team: "biz-ops"
first_responder: "biz-ops on-call"
sla_response: "5min acknowledge | 15min first update | 1h resolution"
old_ids_replaced: ["payment_amount_zero"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
sum(increase(business_payment_amount_total{env="production"}[10m])) == 0
```
**Trigger:** `for: 10m` | **Meaning / 含义:** ZERO payment revenue for 10+ minutes. Payment system completely down. 10分钟以上零支付收入，支付系统完全瘫痪。

**Golden Path Impact / 黄金流程影响:** **CRITICAL — Step 4 (Payment 支付) of golden path is DOWN. 严重——黄金流程第4步（支付）中断。**

### 2. ACKNOWLEDGE / 确认

- Silence for **15 min** / Post to **wecom-critical** / **Phone ALL + China HQ**

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
1. Payment gateway complete outage / 支付网关完全故障
2. Payment service pod crash / 支付服务Pod崩溃
3. Payment DB connection failure / 支付数据库连接故障
4. SSL certificate expiry on payment endpoints / 支付端点SSL证书过期
5. Third-party payment provider down / 第三方支付提供商宕机

**Diagnostic Commands / 诊断命令:**
```bash
# Check payment service pods / 检查支付服务Pod
kubectl get pods -n production -l app=payment-service -o wide
kubectl logs -n production -l app=payment-service --tail=50 --since=10m
# Check payment DB / 检查支付数据库
# PromQL: aws_rds_database_connections_average{dbinstance_identifier="aws-luckyus-salespayment-rw"}
# PromQL: aws_rds_cpuutilization_average{dbinstance_identifier="aws-luckyus-salespayment-rw"}
# Check third-party payment endpoint / 检查第三方支付端点
kubectl exec -n production deployment/payment-service -- curl -s -o /dev/null -w "%{http_code}" https://payment-gateway/health
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 3 | **EMERGENCY.** Restart payment service. If DB issue, failover. If third-party, switch to backup. 紧急处理：重启支付服务，DB问题则故障转移，第三方问题则切换备用。 |

**Emergency Remediation / 紧急修复:**
```bash
kubectl rollout restart deployment/payment-service -n production
# If DB failover needed / 如需数据库故障转移
aws rds reboot-db-instance --db-instance-identifier aws-luckyus-salespayment-rw --force-failover --region us-east-1
```

### 5. AFTERMATH / 善后

- **Post-incident review MANDATORY** / 必须事后回顾
- **Related Alerts / 相关告警:** BIZ-03 (Order Critical), BIZ-05 (Payment Warning), RDS-11/12

---

## BIZ-07: BizRegistrationZeroWarning

```yaml
alert_id: "LCK-BIZ-07"
alert_name: "BizRegistrationZeroWarning"
severity: "warning"
tier: "2"
category: "BIZ"
team: "biz-ops"
first_responder: "biz-ops on-call"
sla_response: "15min acknowledge | 1h first update | 4h resolution"
old_ids_replaced: ["registration_zero_warning"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
sum(increase(business_registration_total{env="production"}[10m])) == 0
```
**Trigger:** `for: 10m` | **Meaning / 含义:** Zero new registrations for 10 minutes. Registration flow may be broken. 10分钟内零新注册，注册流程可能故障。

**Golden Path Impact / 黄金流程影响:** Low-Medium — existing users can still order, but new user acquisition stopped. 低至中等——现有用户仍可下单，但新用户获取停止。

### 2. ACKNOWLEDGE / 确认

- Silence for **30 min** / Post to **wecom-warning** / Phone Team Lead

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
1. SMS delivery failure (OTP not sent) / 短信发送失败（验证码未发出）
2. Registration service down / 注册服务宕机
3. Auth service or token issue / 认证服务或Token问题
4. Normal during late-night hours / 深夜时段正常现象

**Diagnostic Commands / 诊断命令:**
```bash
# Check SMS delivery / 检查短信发送
# PromQL: sms_delivery_failure_rate
# Check auth service / 检查认证服务
kubectl get pods -n production -l app=auth-service -o wide
# Check member registration service / 检查会员注册服务
kubectl get pods -n production -l app=member-service -o wide
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 2 | If SMS-related, check PlatformSmsDeliveryWarning (PLAT-01). If service-related, restart. 如短信相关，检查PLAT-01；如服务相关，重启。 |

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** BIZ-08 (Reg Critical), PLAT-01 (SMS Delivery)

---

## BIZ-08: BizRegistrationZeroCritical

```yaml
alert_id: "LCK-BIZ-08"
alert_name: "BizRegistrationZeroCritical"
severity: "critical"
tier: "3"
category: "BIZ"
team: "biz-ops"
first_responder: "biz-ops on-call"
sla_response: "5min acknowledge | 15min first update | 1h resolution"
old_ids_replaced: ["registration_zero_critical"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
sum(increase(business_registration_total{env="production"}[30m])) == 0
```
**Trigger:** `for: 30m` | **Meaning / 含义:** Zero registrations for 30+ minutes. Registration system completely broken. 30分钟以上零注册，注册系统完全故障。

**Golden Path Impact / 黄金流程影响:** Medium — new user acquisition completely stopped for extended period. 中等——新用户获取长时间完全停止。

### 2. ACKNOWLEDGE / 确认

- Silence for **15 min** / Post to **wecom-critical** / **Phone ALL + China HQ**

### 3. ANALYZE / 分析

**Diagnostic Commands / 诊断命令:**
```bash
# Same as BIZ-07 but more urgent / 同BIZ-07但更紧急
# Check if app store update broke registration / 检查App Store更新是否破坏了注册
# Check DB health for member tables / 检查会员表DB健康
# PromQL: aws_rds_cpuutilization_average{dbinstance_identifier=~".*member.*|.*auth.*"}
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 3 | Emergency fix of registration pipeline. Restart auth/member services. Fix SMS if that's the cause. 紧急修复注册流程，重启认证/会员服务，修复短信问题。 |

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** BIZ-07 (Reg Warning), PLAT-01 (SMS)

---

## BIZ-09: BizTrafficAnomalyWarning

```yaml
alert_id: "LCK-BIZ-09"
alert_name: "BizTrafficAnomalyWarning"
severity: "warning"
tier: "2"
category: "BIZ"
team: "biz-ops"
first_responder: "biz-ops on-call"
sla_response: "15min acknowledge | 1h first update | 4h resolution"
old_ids_replaced: ["traffic_anomaly_info", "traffic_anomaly_warning"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
sum(rate(http_requests_total{env="production"}[5m])) /
sum(rate(http_requests_total{env="production"}[5m] offset 1d)) > 3
```
**Trigger:** `for: 5m` | **Meaning / 含义:** Current traffic is 3× higher than same time yesterday. Could be legitimate (promotion) or attack (DDoS, bot). 当前流量是昨日同期的3倍以上，可能是正常促销或攻击。

**Golden Path Impact / 黄金流程影响:** Variable — depends on whether traffic is legitimate. Could cause service degradation under load. 不确定——取决于流量是否合法，可能导致服务降级。

### 2. ACKNOWLEDGE / 确认

- Silence for **30 min** / Post to **wecom-warning** / Phone Team Lead

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
1. Marketing campaign or promotion launch / 营销活动或促销上线
2. Bot/scraper traffic / 机器人/爬虫流量
3. DDoS attack / DDoS攻击
4. Legitimate viral growth / 合法的病毒式增长

**Diagnostic Commands / 诊断命令:**
```bash
# Check traffic by endpoint / 按端点检查流量
# PromQL: topk(10, sum by(endpoint)(rate(http_requests_total{env="production"}[5m])))
# Check if specific IPs or user agents / 检查是否为特定IP或User Agent
# Check WAF logs / 检查WAF日志
aws waf-regional get-sampled-requests --web-acl-id <id> --rule-id <id> --time-window Start=$(date -u -d '30 min ago' +%Y-%m-%dT%H:%M:%SZ),End=$(date -u +%Y-%m-%dT%H:%M:%SZ) --max-items 100 --region us-east-1
# Check if infrastructure can handle load / 检查基础设施能否承载
kubectl top nodes
kubectl top pods -n production --sort-by=cpu | head -20
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 2 | If legitimate traffic: scale up services. If attack: enable WAF rules, rate limiting. 合法流量则扩容，攻击则启用WAF规则和限流。 |

**Scale Up / 扩容:**
```bash
# Scale critical services / 扩容关键服务
kubectl scale deployment/order-service -n production --replicas=10
kubectl scale deployment/api-gateway -n production --replicas=10
```

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** BIZ-10 (Latency), K8S-01/02/03 (Pod CPU), PLAT-04 (Gateway Error Rate)
- **Prevention / 预防:** Implement auto-scaling policies. Set up WAF rate limiting. 实施自动扩容策略，设置WAF限流。

---

## BIZ-10: BizLatencyP99Warning

```yaml
alert_id: "LCK-BIZ-10"
alert_name: "BizLatencyP99Warning"
severity: "warning"
tier: "2"
category: "BIZ"
team: "biz-ops"
first_responder: "biz-ops on-call"
sla_response: "15min acknowledge | 1h first update | 4h resolution"
old_ids_replaced: ["high_latency_p99_warning", "high_latency_p99_critical"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
histogram_quantile(0.99,
  sum(rate(http_request_duration_seconds_bucket{env="production"}[5m])) by (le)
) > 3
```
**Trigger:** `for: 5m` | **Meaning / 含义:** P99 latency exceeds 3 seconds. 1% of requests taking >3s. User experience severely degraded. P99延迟超过3秒，1%的请求耗时>3秒，用户体验严重下降。

**Golden Path Impact / 黄金流程影响:** Medium-High — users experience slow app, potential cart abandonment. 中至高——用户体验卡顿，可能放弃下单。

### 2. ACKNOWLEDGE / 确认

- Silence for **30 min** / Post to **wecom-warning** / Phone Team Lead

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
1. Database slow queries / 数据库慢查询
2. Upstream API latency (third-party) / 上游API延迟（第三方）
3. Resource saturation (CPU/memory) / 资源饱和（CPU/内存）
4. Network latency / 网络延迟
5. GC pauses (JVM services) / GC暂停（JVM服务）

**Diagnostic Commands / 诊断命令:**
```bash
# Break down latency by service / 按服务分解延迟
# PromQL: histogram_quantile(0.99, sum by(service, le)(rate(http_request_duration_seconds_bucket{env="production"}[5m])))
# Check slow queries / 检查慢查询
# PromQL: lckna:rds:slow_queries_rate3m
# Check JVM GC / 检查JVM GC
# PromQL: increase(jvm_gc_count{gc_type="full"}[5m])
# Check service CPU / 检查服务CPU
kubectl top pods -n production --sort-by=cpu | head -20
# iZeus trace analysis / iZeus链路追踪分析
# https://izeus.luckincoffee.us/trace?service=order-service&start=<timestamp>
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 2 | Identify bottleneck service. Optimize slow queries. Scale up if resource-bound. 定位瓶颈服务，优化慢查询，资源不足则扩容。 |

**Remediation / 修复:**
```bash
# If DB slow queries causing latency / 如数据库慢查询导致延迟
# Kill long-running queries
# Server: aws-luckyus-salesorder-rw
# SQL: SELECT id, time, info FROM information_schema.processlist WHERE time > 10 AND command != 'Sleep' ORDER BY time DESC;
# Scale up services under load / 扩容负载较高的服务
kubectl scale deployment/<bottleneck-service> -n production --replicas=<increased>
```

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** RDS-04/05/06 (Slow Queries), APM-03 (APM Latency), BIZ-09 (Traffic Anomaly)
- **Prevention / 预防:** Set up slow query alerting per-service. Implement query optimization reviews. 设置每服务慢查询告警，实施查询优化审查。

---

*End of Part 1: BIZ — Business Metrics (10 alerts)*

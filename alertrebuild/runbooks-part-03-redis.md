# Part 3: DB-REDIS — ElastiCache Redis

> 10 Alerts: REDIS-01 through REDIS-10
> Team: dba | Datasource: `ff6p0gjt24phce` (prometheus_redis)
> Skill File: `/app/skills/redis-alert-investigation.md` (v1.0)

---

## REDIS-01: RedisCpuUsageInfo

```yaml
alert_id: "LCK-REDIS-01"
alert_name: "RedisCpuUsageInfo"
severity: "info"
tier: "1"
category: "DB-REDIS"
team: "dba"
first_responder: "dba on-call"
sla_response: "30min acknowledge | 2h first update | 8h resolution"
old_ids_replaced: ["redis_cpu_high_info"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL (Recording Rule):**
```promql
lckna:redis:cpu_avg3m{} > 50 and lckna:redis:cpu_avg3m{} <= 65
```
**Base:** `avg_over_time(redis_cpu_usage{cluster!~".*reader.*"}[3m])`

**Trigger:** `for: 5m` | **Meaning / 含义:** Redis CPU at 50-65% for 5 min. Elevated utilization but within capacity. Redis CPU在50-65%持续5分钟，使用率升高但仍在容量范围内。

**Golden Path Impact / 黄金流程影响:** Low — cache responding normally. 低——缓存响应正常。

### 2. ACKNOWLEDGE / 确认

- Silence for **1 hour** / Post to **wecom-info** / No phone

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
1. Increased cache hit rate (more traffic) / 缓存命中率增加（更多流量）
2. Expensive commands (KEYS, SORT, large SUNION) / 耗时命令
3. Hot key pattern / 热点Key模式
4. Lua script execution / Lua脚本执行

**Diagnostic Commands / 诊断命令:**
```bash
# Check which cluster / 检查哪个集群
# PromQL (datasource: ff6p0gjt24phce): lckna:redis:cpu_avg3m > 50
# Check slow log / 检查慢日志
redis-cli -h master.CLUSTER_NAME.vyllrs.use1.cache.amazonaws.com -p 6379 --tls --no-auth-warning SLOWLOG GET 20
# Check hot commands / 检查热门命令
redis-cli -h master.CLUSTER_NAME.vyllrs.use1.cache.amazonaws.com -p 6379 --tls --no-auth-warning INFO commandstats
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 1 | Monitor. Identify expensive commands via SLOWLOG. Recommend app-level optimization. 监控，通过SLOWLOG识别耗时命令，建议应用层优化。 |

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** REDIS-02, REDIS-03, REDIS-06 (Latency)

---

## REDIS-02: RedisCpuUsageWarning

```yaml
alert_id: "LCK-REDIS-02"
alert_name: "RedisCpuUsageWarning"
severity: "warning"
tier: "2"
category: "DB-REDIS"
team: "dba"
first_responder: "dba on-call"
sla_response: "15min acknowledge | 1h first update | 4h resolution"
old_ids_replaced: ["redis_cpu_high_warning"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
lckna:redis:cpu_avg3m{} > 65 and lckna:redis:cpu_avg3m{} <= 90
```
**Trigger:** `for: 5m` | **Meaning / 含义:** Redis CPU at 65-90%. Significant load. Redis CPU在65-90%，负载显著。

### 2. ACKNOWLEDGE / 确认

- Silence for **30 min** / Post to **wecom-warning** / Phone Team Lead

### 3. ANALYZE / 分析

**Diagnostic Commands / 诊断命令:**
```bash
# SLOWLOG analysis / 慢日志分析
redis-cli -h master.CLUSTER_NAME.vyllrs.use1.cache.amazonaws.com -p 6379 --tls --no-auth-warning SLOWLOG GET 50
# Check if KEYS or SCAN abuse / 检查是否滥用KEYS或SCAN
redis-cli -h master.CLUSTER_NAME.vyllrs.use1.cache.amazonaws.com -p 6379 --tls --no-auth-warning INFO commandstats | grep -E "keys|scan|sort"
# Check memory fragmentation (causes CPU overhead) / 检查内存碎片（导致CPU开销）
redis-cli -h master.CLUSTER_NAME.vyllrs.use1.cache.amazonaws.com -p 6379 --tls --no-auth-warning INFO memory | grep mem_fragmentation_ratio
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 2 | Identify and eliminate expensive commands. Scale up node type if persistent. 识别并消除耗时命令，持续则升级节点规格。 |

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** REDIS-01, REDIS-03

---

## REDIS-03: RedisCpuUsageCritical

```yaml
alert_id: "LCK-REDIS-03"
alert_name: "RedisCpuUsageCritical"
severity: "critical"
tier: "3"
category: "DB-REDIS"
team: "dba"
first_responder: "dba on-call"
sla_response: "5min acknowledge | 15min first update | 1h resolution"
old_ids_replaced: ["redis_cpu_high_critical"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
lckna:redis:cpu_avg3m{} > 90
```
**Trigger:** `for: 3m` | **Meaning / 含义:** Redis CPU >90%. Cache near saturation, commands timing out. Redis CPU超过90%，缓存接近饱和，命令超时。

**Golden Path Impact / 黄金流程影响:** **HIGH — cache timeouts cascade to application layer. 高——缓存超时级联到应用层。**

### 2. ACKNOWLEDGE / 确认

- Silence for **15 min** / Post to **wecom-critical** / **Phone ALL + China HQ**

### 3. ANALYZE / 分析

```bash
# IMMEDIATE: Check for runaway Lua scripts / 立即检查失控Lua脚本
redis-cli -h master.CLUSTER_NAME.vyllrs.use1.cache.amazonaws.com -p 6379 --tls --no-auth-warning SCRIPT EXISTS <sha>
# Check client list for abusive connections / 检查客户端列表中的滥用连接
redis-cli -h master.CLUSTER_NAME.vyllrs.use1.cache.amazonaws.com -p 6379 --tls --no-auth-warning CLIENT LIST | sort -t= -k8 -rn | head -10
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 3 | **Scale up node type immediately. Kill abusive scripts. Coordinate with app teams to reduce load.** 立即升级节点规格，终止滥用脚本，协调应用团队降低负载。 |

**Emergency Remediation / 紧急修复:**
```bash
# Scale up ElastiCache node type / 升级ElastiCache节点规格
aws elasticache modify-replication-group --replication-group-id CLUSTER_NAME --cache-node-type cache.r6g.xlarge --apply-immediately --region us-east-1
```

### 5. AFTERMATH / 善后

- **Post-incident review MANDATORY** / 必须事后回顾
- **Related Alerts / 相关告警:** REDIS-01/02, REDIS-06 (Latency), BIZ-10 (App Latency)

---

## REDIS-04: RedisMemoryUsageWarning

```yaml
alert_id: "LCK-REDIS-04"
alert_name: "RedisMemoryUsageWarning"
severity: "warning"
tier: "2"
category: "DB-REDIS"
team: "dba"
first_responder: "dba on-call"
sla_response: "15min acknowledge | 1h first update | 4h resolution"
old_ids_replaced: ["redis_memory_high_warning"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
lckna:redis:memory_ratio_avg3m{} > 80 and lckna:redis:memory_ratio_avg3m{} <= 95
```
**Base:** `avg_over_time(redis_memory_usage_ratio[3m])`

**Trigger:** `for: 5m` | **Meaning / 含义:** Memory usage at 80-95%. Approaching maxmemory. 内存使用率80-95%，接近maxmemory。

### 2. ACKNOWLEDGE / 确认

- Silence for **30 min** / Post to **wecom-warning** / Phone Team Lead

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
1. Missing TTL on keys / Key缺少TTL
2. Uncontrolled key growth / Key数量不受控增长
3. Large values (>1MB per key) / 大Value（每Key>1MB）
4. Memory fragmentation / 内存碎片

**Diagnostic Commands / 诊断命令:**
```bash
# Check memory details / 检查内存详情
redis-cli -h master.CLUSTER_NAME.vyllrs.use1.cache.amazonaws.com -p 6379 --tls --no-auth-warning INFO memory
# Check key count and TTL distribution / 检查Key数量和TTL分布
redis-cli -h master.CLUSTER_NAME.vyllrs.use1.cache.amazonaws.com -p 6379 --tls --no-auth-warning INFO keyspace
# Check biggest keys (sampled) / 检查最大Key（采样）
redis-cli -h master.CLUSTER_NAME.vyllrs.use1.cache.amazonaws.com -p 6379 --tls --no-auth-warning --bigkeys --i 0.1
# Check eviction policy / 检查淘汰策略
redis-cli -h master.CLUSTER_NAME.vyllrs.use1.cache.amazonaws.com -p 6379 --tls --no-auth-warning CONFIG GET maxmemory-policy
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 2 | Add TTL to keys without expiry. Delete unnecessary keys. Scale up memory if needed. 给无过期时间的Key添加TTL，删除不必要的Key，必要时升级内存。 |

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** REDIS-05 (Critical), REDIS-07 (Evictions)
- **Prevention / 预防:** Enforce TTL policy for all application keys. See `/app/runbooks/redis-isales-market-remediation/`. 强制所有应用Key的TTL策略。

---

## REDIS-05: RedisMemoryUsageCritical

```yaml
alert_id: "LCK-REDIS-05"
alert_name: "RedisMemoryUsageCritical"
severity: "critical"
tier: "3"
category: "DB-REDIS"
team: "dba"
first_responder: "dba on-call"
sla_response: "5min acknowledge | 15min first update | 1h resolution"
old_ids_replaced: ["redis_memory_high_critical"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
lckna:redis:memory_ratio_avg3m{} > 95
```
**Trigger:** `for: 1m` | **Meaning / 含义:** Memory >95%. Evictions active or OOM imminent. 内存超过95%，淘汰机制已激活或即将OOM。

**Golden Path Impact / 黄金流程影响:** **CRITICAL — cache evictions causing cache misses, increased DB load. 严重——缓存淘汰导致缓存未命中，增加DB负载。**

### 2. ACKNOWLEDGE / 确认

- Silence for **15 min** / Post to **wecom-critical** / **Phone ALL + China HQ**

### 3. ANALYZE / 分析

```bash
# Check evictions / 检查淘汰
# PromQL (ff6p0gjt24phce): rate(redis_evicted_keys_total{cluster="CLUSTER_NAME"}[3m]) * 60
# Check memory breakdown / 检查内存分布
redis-cli -h master.CLUSTER_NAME.vyllrs.use1.cache.amazonaws.com -p 6379 --tls --no-auth-warning MEMORY DOCTOR
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 3 | **Emergency scale up. Flush non-essential caches if approved. Add TTL to all keys without expiry.** 紧急扩容，经批准后清除非必要缓存，给所有无过期时间的Key添加TTL。 |

**Emergency Remediation / 紧急修复:**
```bash
# Scale up immediately / 立即扩容
aws elasticache modify-replication-group --replication-group-id CLUSTER_NAME --cache-node-type cache.r6g.xlarge --apply-immediately --region us-east-1
# Flush specific non-critical DB (REQUIRES APPROVAL) / 清除特定非关键DB（需要批准）
# redis-cli -h master.CLUSTER_NAME... FLUSHDB ASYNC (DB number)
```

### 5. AFTERMATH / 善后

- **Post-incident review MANDATORY** / 必须事后回顾
- **Related Alerts / 相关告警:** REDIS-04, REDIS-07 (Evictions), RDS-01/02 (DB CPU from cache misses)

---

## REDIS-06: RedisLatencyP99Warning

```yaml
alert_id: "LCK-REDIS-06"
alert_name: "RedisLatencyP99Warning"
severity: "warning"
tier: "2"
category: "DB-REDIS"
team: "dba"
first_responder: "dba on-call"
sla_response: "15min acknowledge | 1h first update | 4h resolution"
old_ids_replaced: ["redis_latency_high"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
redis_commands_latency{quantile="0.99"} > 5
```
**Trigger:** `for: 5m` | **Meaning / 含义:** P99 command latency >5ms for 5 min. Slow responses from Redis. P99命令延迟超过5ms持续5分钟，Redis响应缓慢。

### 2. ACKNOWLEDGE / 确认

- Silence for **30 min** / Post to **wecom-warning** / Phone Team Lead

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
1. High CPU causing processing delays / 高CPU导致处理延迟
2. Network latency between app and Redis / 应用与Redis之间的网络延迟
3. Expensive commands blocking event loop / 耗时命令阻塞事件循环
4. Large key operations / 大Key操作

**Diagnostic Commands / 诊断命令:**
```bash
# Check SLOWLOG / 检查慢日志
redis-cli -h master.CLUSTER_NAME.vyllrs.use1.cache.amazonaws.com -p 6379 --tls --no-auth-warning SLOWLOG GET 30
# Check latency stats / 检查延迟统计
redis-cli -h master.CLUSTER_NAME.vyllrs.use1.cache.amazonaws.com -p 6379 --tls --no-auth-warning LATENCY LATEST
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 2 | Identify and optimize slow commands. Check network path. Consider pipeline/batch optimization. 识别优化慢命令，检查网络路径，考虑pipeline/批量优化。 |

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** REDIS-01/02/03 (CPU), BIZ-10 (App Latency)

---

## REDIS-07: RedisEvictionsWarning

```yaml
alert_id: "LCK-REDIS-07"
alert_name: "RedisEvictionsWarning"
severity: "warning"
tier: "2"
category: "DB-REDIS"
team: "dba"
first_responder: "dba on-call"
sla_response: "15min acknowledge | 1h first update | 4h resolution"
old_ids_replaced: ["redis_evictions_high"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
rate(redis_evicted_keys_total[3m]) * 60 > 1000
```
**Trigger:** `for: 5m` | **Meaning / 含义:** >1000 keys evicted per minute. Cache thrashing — keys being removed faster than expected. 每分钟淘汰超过1000个Key，缓存抖动。

### 2. ACKNOWLEDGE / 确认

- Silence for **30 min** / Post to **wecom-warning** / Phone Team Lead

### 3. ANALYZE / 分析

```bash
# Check memory status / 检查内存状态
# PromQL (ff6p0gjt24phce): redis_memory_usage_ratio{cluster="CLUSTER_NAME"}
# Check eviction policy / 检查淘汰策略
redis-cli -h master.CLUSTER_NAME.vyllrs.use1.cache.amazonaws.com -p 6379 --tls --no-auth-warning CONFIG GET maxmemory-policy
# Check hit rate (evictions cause misses) / 检查命中率
# PromQL: redis_keyspace_hits_total / (redis_keyspace_hits_total + redis_keyspace_misses_total)
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 2 | Scale up memory. Optimize key TTLs. Review eviction policy (allkeys-lru vs volatile-lru). 扩大内存，优化Key TTL，审查淘汰策略。 |

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** REDIS-04/05 (Memory), RDS-01/02 (DB CPU from cache misses)

---

## REDIS-08: RedisConnectionRatioWarning

```yaml
alert_id: "LCK-REDIS-08"
alert_name: "RedisConnectionRatioWarning"
severity: "warning"
tier: "2"
category: "DB-REDIS"
team: "dba"
first_responder: "dba on-call"
sla_response: "15min acknowledge | 1h first update | 4h resolution"
old_ids_replaced: ["redis_connections_high"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL (Recording Rule):**
```promql
lckna:redis:connection_ratio{} > 60
```
**Base:** `redis_connected_clients / redis_config_maxclients * 100`

**Trigger:** `for: 5m` | **Meaning / 含义:** Connection usage >60% of max. Risk of connection exhaustion. 连接使用率超过最大值的60%，存在连接耗尽风险。

### 2. ACKNOWLEDGE / 确认

- Silence for **30 min** / Post to **wecom-warning** / Phone Team Lead

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
1. Application connection pool misconfiguration / 应用连接池配置错误
2. Connection leak (not returning connections) / 连接泄漏
3. Too many application replicas connecting / 过多应用副本连接
4. Pub/Sub subscriber accumulation / 发布/订阅订阅者累积

**Diagnostic Commands / 诊断命令:**
```bash
# Check current connections / 检查当前连接
redis-cli -h master.CLUSTER_NAME.vyllrs.use1.cache.amazonaws.com -p 6379 --tls --no-auth-warning INFO clients
# Check connected clients by IP / 按IP检查连接客户端
redis-cli -h master.CLUSTER_NAME.vyllrs.use1.cache.amazonaws.com -p 6379 --tls --no-auth-warning CLIENT LIST | awk -F'[ =]' '{for(i=1;i<=NF;i++) if($i=="addr") print $(i+1)}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -10
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 2 | Reduce connection pool sizes on applications. Fix connection leaks. Increase maxclients if justified. 减少应用连接池大小，修复连接泄漏，必要时增加maxclients。 |

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** REDIS-10 (Instance Down), REDIS-01/02 (CPU)

---

## REDIS-09: RedisNetworkBandwidthWarning

```yaml
alert_id: "LCK-REDIS-09"
alert_name: "RedisNetworkBandwidthWarning"
severity: "warning"
tier: "2"
category: "DB-REDIS"
team: "dba"
first_responder: "dba on-call"
sla_response: "15min acknowledge | 1h first update | 4h resolution"
old_ids_replaced: ["redis_network_bandwidth_high"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
(rate(redis_net_input_bytes_total[3m]) + rate(redis_net_output_bytes_total[3m])) * 8 / 1024 / 1024 > 32
```
**Trigger:** `for: 5m` | **Meaning / 含义:** Network bandwidth >32 Mbps. High data transfer through Redis. 网络带宽超过32Mbps，Redis数据传输量大。

### 2. ACKNOWLEDGE / 确认

- Silence for **30 min** / Post to **wecom-warning** / Phone Team Lead

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
1. Large value reads/writes / 大Value读写
2. Mass key scan operations / 大量Key扫描操作
3. Replication sync / 复制同步
4. Pub/Sub high-volume messages / 发布/订阅高消息量

**Diagnostic Commands / 诊断命令:**
```bash
# Check command stats / 检查命令统计
redis-cli -h master.CLUSTER_NAME.vyllrs.use1.cache.amazonaws.com -p 6379 --tls --no-auth-warning INFO commandstats | sort -t: -k3 -rn | head -10
# Check big keys / 检查大Key
redis-cli -h master.CLUSTER_NAME.vyllrs.use1.cache.amazonaws.com -p 6379 --tls --no-auth-warning --bigkeys --i 0.1
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 2 | Optimize large values (compression, splitting). Scale to larger node type for more bandwidth. 优化大Value（压缩、拆分），升级到更大节点类型获取更多带宽。 |

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** REDIS-01/02 (CPU), REDIS-06 (Latency)

---

## REDIS-10: RedisInstanceDownCritical

```yaml
alert_id: "LCK-REDIS-10"
alert_name: "RedisInstanceDownCritical"
severity: "critical"
tier: "3"
category: "DB-REDIS"
team: "dba"
first_responder: "dba on-call"
sla_response: "5min acknowledge | 15min first update | 1h resolution"
old_ids_replaced: ["redis_instance_down"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
redis_up{} == 0
```
**Trigger:** `for: 1m` | **Meaning / 含义:** Redis instance/cluster completely down. 完全无法访问Redis实例/集群。Redis实例/集群完全宕机。

**Golden Path Impact / 黄金流程影响:** **CRITICAL — all cached data unavailable. Application falls back to DB (massive load spike). 严重——所有缓存数据不可用，应用回退到DB（巨大负载飙升）。**

### 2. ACKNOWLEDGE / 确认

- Silence for **15 min** / Post to **wecom-critical** / **Phone ALL + China HQ**

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
1. AWS ElastiCache maintenance / AWS ElastiCache维护
2. Node failure (automatic failover should trigger) / 节点故障（应触发自动故障转移）
3. Security group or network change / 安全组或网络变更
4. OOM kill / OOM终止

**Diagnostic Commands / 诊断命令:**
```bash
# Check ElastiCache status / 检查ElastiCache状态
aws elasticache describe-replication-groups --replication-group-id CLUSTER_NAME --region us-east-1
# Check ElastiCache events / 检查ElastiCache事件
aws elasticache describe-events --source-type replication-group --source-identifier CLUSTER_NAME --duration 60 --region us-east-1
# Check if failover happened / 检查是否发生故障转移
aws elasticache describe-events --source-type replication-group --duration 60 --region us-east-1 | grep -i failover
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 3 | **If failover: monitor recovery. If persistent: manual failover. Monitor DB load spike from cache misses.** 故障转移中则监控恢复；持续宕机则手动故障转移；监控缓存失效导致的DB负载飙升。 |

**Emergency Remediation / 紧急修复:**
```bash
# Force failover / 强制故障转移
aws elasticache modify-replication-group --replication-group-id CLUSTER_NAME --automatic-failover-enabled --apply-immediately --region us-east-1
# Monitor DB load from cache misses / 监控缓存失效导致的DB负载
# PromQL: lckna:rds:cpu_avg3m
```

### 5. AFTERMATH / 善后

- **Post-incident review MANDATORY** / 必须事后回顾
- **Related Alerts / 相关告警:** RDS-01/02/03 (DB CPU from cache fallback), BIZ-01/02/03 (Order Volume)
- **Prevention / 预防:** Ensure Multi-AZ replication. Test failover procedures quarterly. 确保Multi-AZ复制，每季度测试故障转移流程。

---

*End of Part 3: DB-REDIS — ElastiCache Redis (10 alerts)*

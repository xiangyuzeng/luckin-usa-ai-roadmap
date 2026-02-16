# Part 2: DB-RDS — RDS MySQL / 数据库RDS

> 12 Alerts: RDS-01 through RDS-12
> Team: dba | Datasource: `df8o21agxtkw0d` (UMBQuerier-Luckin)
> Skill File: `/app/skills/rds-alert-investigation.md` (v2.0)

---

## RDS-01: RdsCpuUsageInfo

```yaml
alert_id: "LCK-RDS-01"
alert_name: "RdsCpuUsageInfo"
severity: "info"
tier: "1"
category: "DB-RDS"
team: "dba"
first_responder: "dba on-call"
sla_response: "30min acknowledge | 2h first update | 8h resolution"
old_ids_replaced: ["rds_cpu_high_info"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL (Recording Rule):**
```promql
lckna:rds:cpu_avg3m{} > 50 and lckna:rds:cpu_avg3m{} <= 70
```
**Base:** `avg_over_time(aws_rds_cpuutilization_average{dbinstance_identifier!~".*reader.*"}[3m])`

**Trigger:** `for: 10m` | **Meaning / 含义:** RDS CPU averaged 50-70% for 10 min. Elevated but not dangerous. RDS CPU平均值50-70%持续10分钟，升高但未达危险水平。

**Golden Path Impact / 黄金流程影响:** Low — database responsive, queries running normally. 低——数据库响应正常。

### 2. ACKNOWLEDGE / 确认

- Silence for **1 hour** / Post to **wecom-info** / No phone call

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
1. Increased query load (business peak) / 查询负载增加（业务高峰）
2. Inefficient query plans after stats change / 统计信息变化后查询计划低效
3. Batch job running (ETL, reports) / 批处理任务运行（ETL、报表）
4. Connection pool saturation / 连接池饱和

**Diagnostic Commands / 诊断命令:**
```bash
# Check which instance / 检查哪个实例
# PromQL: lckna:rds:cpu_avg3m > 50
# Check active threads / 检查活跃线程
# PromQL: lckna:rds:threads_avg2m{dbinstance_identifier="INSTANCE_NAME"}
# Check slow queries / 检查慢查询
# PromQL: lckna:rds:slow_queries_rate3m{dbinstance_identifier="INSTANCE_NAME"}
# Check processlist / 检查进程列表
# Server: aws-luckyus-{name}-rw (via mcp-db-gateway)
# SQL: SELECT id, user, host, db, command, time, state, LEFT(info,100) as query FROM information_schema.processlist WHERE command != 'Sleep' ORDER BY time DESC LIMIT 20;
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 1 | Monitor. Identify top queries. Suggest optimization if persistent. 监控，识别TOP查询，持续则建议优化。 |

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** RDS-02 (Warning), RDS-03 (Critical), RDS-04/05/06 (Slow Queries)
- **Prevention / 预防:** Regular slow query review. Index optimization. 定期慢查询审查和索引优化。

---

## RDS-02: RdsCpuUsageWarning

```yaml
alert_id: "LCK-RDS-02"
alert_name: "RdsCpuUsageWarning"
severity: "warning"
tier: "2"
category: "DB-RDS"
team: "dba"
first_responder: "dba on-call"
sla_response: "15min acknowledge | 1h first update | 4h resolution"
old_ids_replaced: ["rds_cpu_high_warning"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
lckna:rds:cpu_avg3m{} > 70 and lckna:rds:cpu_avg3m{} <= 90
```
**Trigger:** `for: 5m` | **Meaning / 含义:** RDS CPU at 70-90% for 5 min. Database under significant load. RDS CPU达到70-90%持续5分钟，数据库负载显著。

**Golden Path Impact / 黄金流程影响:** Medium — queries may slow down, latency increasing. 中等——查询可能变慢，延迟增加。

### 2. ACKNOWLEDGE / 确认

- Silence for **30 min** / Post to **wecom-warning** / Phone Team Lead

### 3. ANALYZE / 分析

**Diagnostic Commands / 诊断命令:**
```bash
# Identify CPU-heavy queries / 识别CPU密集查询
# Server: aws-luckyus-{instance}-rw
# SQL: SELECT * FROM performance_schema.events_statements_summary_by_digest ORDER BY SUM_CPU_TIME DESC LIMIT 10;
# Or check processlist for long-running queries / 或检查长时间运行的查询
# SQL: SELECT id, user, db, time, LEFT(info, 200) FROM information_schema.processlist WHERE command != 'Sleep' AND time > 5 ORDER BY time DESC;
# Check for lock waits / 检查锁等待
# SQL: SELECT * FROM information_schema.innodb_lock_waits;
# Check connection count / 检查连接数
# PromQL: aws_rds_database_connections_average{dbinstance_identifier="INSTANCE_NAME"}
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 2 | Kill long-running queries if identified. Optimize or add indexes. Consider read replica offload. 终止长时间查询，优化或添加索引，考虑读副本分流。 |

**Remediation / 修复:**
```bash
# Kill specific long query / 终止特定长查询
# SQL: KILL <process_id>;
# Analyze slow query / 分析慢查询
# SQL: EXPLAIN SELECT ...; (the problematic query)
```

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** RDS-01, RDS-03, RDS-07/08/09 (Active Threads)

---

## RDS-03: RdsCpuUsageCritical

```yaml
alert_id: "LCK-RDS-03"
alert_name: "RdsCpuUsageCritical"
severity: "critical"
tier: "3"
category: "DB-RDS"
team: "dba"
first_responder: "dba on-call"
sla_response: "5min acknowledge | 15min first update | 1h resolution"
old_ids_replaced: ["rds_cpu_high_critical"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
lckna:rds:cpu_avg3m{} > 90
```
**Trigger:** `for: 3m` | **Meaning / 含义:** RDS CPU above 90% for 3 min. Database nearing failure. RDS CPU超过90%持续3分钟，数据库接近崩溃。

**Golden Path Impact / 黄金流程影响:** **HIGH — queries timing out, order flow likely impacted. 高——查询超时，订单流程可能受影响。**

### 2. ACKNOWLEDGE / 确认

- Silence for **15 min** / Post to **wecom-critical** / **Phone ALL + China HQ**

### 3. ANALYZE / 分析

**Diagnostic Commands / 诊断命令:**
```bash
# IMMEDIATE: Check processlist / 立即检查进程列表
# SQL: SELECT id, user, db, time, state, LEFT(info, 200) FROM information_schema.processlist WHERE command != 'Sleep' ORDER BY time DESC LIMIT 30;
# Check for runaway queries / 检查失控查询
# SQL: SELECT id, time, info FROM information_schema.processlist WHERE time > 30 AND command = 'Query';
# Check InnoDB status / 检查InnoDB状态
# SQL: SHOW ENGINE INNODB STATUS\G
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 3 | **Kill all non-essential long queries immediately.** If CPU doesn't drop, scale up instance class (requires China approval). 立即终止所有非必要长查询。CPU不降则升级实例规格（需中国总部批准）。 |

**Emergency Remediation / 紧急修复:**
```bash
# Kill ALL queries running > 30 seconds / 终止所有运行>30秒的查询
# SQL: SELECT CONCAT('KILL ', id, ';') FROM information_schema.processlist WHERE command = 'Query' AND time > 30;
# Scale up instance (Tier 3 with China approval) / 升级实例（Tier 3需中国批准）
aws rds modify-db-instance --db-instance-identifier INSTANCE_NAME --db-instance-class db.r6g.2xlarge --apply-immediately --region us-east-1
```

### 5. AFTERMATH / 善后

- **Post-incident review MANDATORY** / 必须事后回顾
- **Related Alerts / 相关告警:** RDS-01/02, RDS-09 (Active Threads Critical), BIZ-01/02/03 (Order Volume)

---

## RDS-04: RdsSlowQueriesInfo

```yaml
alert_id: "LCK-RDS-04"
alert_name: "RdsSlowQueriesInfo"
severity: "info"
tier: "1"
category: "DB-RDS"
team: "dba"
first_responder: "dba on-call"
sla_response: "30min acknowledge | 2h first update | 8h resolution"
old_ids_replaced: ["rds_slow_queries_info"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
lckna:rds:slow_queries_rate3m{} > 10 and lckna:rds:slow_queries_rate3m{} <= 50
```
**Base:** `rate(aws_rds_slow_queries_average[3m]) * 60`

**Trigger:** `for: 5m` | **Meaning / 含义:** 10-50 slow queries per minute for 5 min. Moderate slow query volume. 每分钟10-50个慢查询持续5分钟，慢查询量适中。

### 2. ACKNOWLEDGE / 确认

- Silence for **1 hour** / Post to **wecom-info** / No phone

### 3. ANALYZE / 分析

**Diagnostic Commands / 诊断命令:**
```bash
# Check slow query log / 检查慢查询日志
# Server: aws-luckyus-{instance}-rw
# SQL: SELECT start_time, user_host, query_time, lock_time, rows_examined, rows_sent, LEFT(sql_text,200) FROM mysql.slow_log WHERE start_time > NOW() - INTERVAL 30 MINUTE ORDER BY query_time DESC LIMIT 20;
# Check which DB has most slow queries / 检查哪个DB慢查询最多
# PromQL: topk(5, lckna:rds:slow_queries_rate3m)
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 1 | Monitor. Queue top slow queries for optimization during next maintenance window. 监控，将TOP慢查询排队到下个维护窗口优化。 |

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** RDS-05, RDS-06, RDS-01/02 (CPU), BIZ-10 (Latency)

---

## RDS-05: RdsSlowQueriesWarning

```yaml
alert_id: "LCK-RDS-05"
alert_name: "RdsSlowQueriesWarning"
severity: "warning"
tier: "2"
category: "DB-RDS"
team: "dba"
first_responder: "dba on-call"
sla_response: "15min acknowledge | 1h first update | 4h resolution"
old_ids_replaced: ["rds_slow_queries_warning"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
lckna:rds:slow_queries_rate3m{} > 50 and lckna:rds:slow_queries_rate3m{} <= 200
```
**Trigger:** `for: 5m` | **Meaning / 含义:** 50-200 slow queries/min. Heavy slow query load impacting performance. 每分钟50-200个慢查询，严重影响性能。

### 2. ACKNOWLEDGE / 确认

- Silence for **30 min** / Post to **wecom-warning** / Phone Team Lead

### 3. ANALYZE / 分析

**Diagnostic Commands / 诊断命令:**
```bash
# Identify top offending queries by digest / 按摘要识别TOP违规查询
# SQL: SELECT DIGEST_TEXT, COUNT_STAR, AVG_TIMER_WAIT/1000000000 as avg_ms, SUM_ROWS_EXAMINED FROM performance_schema.events_statements_summary_by_digest ORDER BY COUNT_STAR * AVG_TIMER_WAIT DESC LIMIT 10;
# Check for missing indexes / 检查缺失索引
# SQL: EXPLAIN <slow_query>;
# Check if recent schema change / 检查是否有近期架构变更
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 2 | Add missing indexes. Optimize top queries. Kill if causing cascading delays. 添加缺失索引，优化TOP查询，如导致级联延迟则终止。 |

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** RDS-04, RDS-06, RDS-02 (CPU Warning)

---

## RDS-06: RdsSlowQueriesCritical

```yaml
alert_id: "LCK-RDS-06"
alert_name: "RdsSlowQueriesCritical"
severity: "critical"
tier: "3"
category: "DB-RDS"
team: "dba"
first_responder: "dba on-call"
sla_response: "5min acknowledge | 15min first update | 1h resolution"
old_ids_replaced: ["rds_slow_queries_critical"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
lckna:rds:slow_queries_rate3m{} > 200
```
**Trigger:** `for: 3m` | **Meaning / 含义:** >200 slow queries/min for 3 min. Database in critical state. 每分钟超过200个慢查询持续3分钟，数据库处于危急状态。

**Golden Path Impact / 黄金流程影响:** **HIGH — all application queries delayed. 高——所有应用查询延迟。**

### 2. ACKNOWLEDGE / 确认

- Silence for **15 min** / Post to **wecom-critical** / **Phone ALL + China HQ**

### 3. ANALYZE / 分析

**Diagnostic Commands / 诊断命令:**
```bash
# IMMEDIATE: Get top slow queries NOW / 立即获取当前TOP慢查询
# SQL: SELECT id, user, db, time, state, LEFT(info,200) FROM information_schema.processlist WHERE command = 'Query' AND time > 2 ORDER BY time DESC LIMIT 30;
# Check if single bad query is responsible / 检查是否单个坏查询导致
# SQL: SELECT DIGEST_TEXT, COUNT_STAR, SUM_TIMER_WAIT/1000000000000 as total_sec FROM performance_schema.events_statements_summary_by_digest ORDER BY SUM_TIMER_WAIT DESC LIMIT 5;
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 3 | **Kill offending queries immediately.** Apply emergency indexes if identified. Scale up if needed. 立即终止违规查询，识别后紧急添加索引，必要时升级实例。 |

### 5. AFTERMATH / 善后

- **Post-incident review MANDATORY** / 必须事后回顾
- **Related Alerts / 相关告警:** RDS-03 (CPU Critical), BIZ-10 (Latency)

---

## RDS-07: RdsActiveThreadsInfo

```yaml
alert_id: "LCK-RDS-07"
alert_name: "RdsActiveThreadsInfo"
severity: "info"
tier: "1"
category: "DB-RDS"
team: "dba"
first_responder: "dba on-call"
sla_response: "30min acknowledge | 2h first update | 8h resolution"
old_ids_replaced: ["rds_threads_high_info"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
lckna:rds:threads_avg2m{} > 12 and lckna:rds:threads_avg2m{} <= 24
```
**Base:** `avg_over_time(aws_rds_active_transactions_average[2m])`

**Trigger:** `for: 5m` | **Meaning / 含义:** 12-24 active threads for 5 min. Moderate concurrency. 12-24个活跃线程持续5分钟，中等并发。

### 2-5. (Follow standard Tier 1 pattern / 遵循标准Tier 1模式)

- **Monitor** thread count. Check for slow queries causing thread pile-up. 监控线程数，检查慢查询导致的线程堆积。
- **Related Alerts:** RDS-08, RDS-09, RDS-01 (CPU)

---

## RDS-08: RdsActiveThreadsWarning

```yaml
alert_id: "LCK-RDS-08"
alert_name: "RdsActiveThreadsWarning"
severity: "warning"
tier: "2"
category: "DB-RDS"
team: "dba"
first_responder: "dba on-call"
sla_response: "15min acknowledge | 1h first update | 4h resolution"
old_ids_replaced: ["rds_threads_high_warning"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
lckna:rds:threads_avg2m{} > 24 and lckna:rds:threads_avg2m{} <= 48
```
**Trigger:** `for: 3m` | **Meaning / 含义:** 24-48 active threads. High concurrency — likely queries blocking each other. 24-48个活跃线程，高并发，可能存在查询互相阻塞。

### 2. ACKNOWLEDGE / 确认

- Silence for **30 min** / Post to **wecom-warning** / Phone Team Lead

### 3. ANALYZE / 分析

**Diagnostic Commands / 诊断命令:**
```bash
# Check for lock contention / 检查锁争用
# SQL: SELECT * FROM sys.innodb_lock_waits\G
# Check thread states / 检查线程状态
# SQL: SELECT state, COUNT(*) FROM information_schema.processlist WHERE command != 'Sleep' GROUP BY state ORDER BY COUNT(*) DESC;
# Check if connection pool exhaustion / 检查连接池是否耗尽
# SQL: SHOW STATUS LIKE 'Threads_connected';
# SQL: SHOW VARIABLES LIKE 'max_connections';
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 2 | Resolve lock contention. Kill blocking queries. Increase max_connections if pool saturated. 解决锁争用，终止阻塞查询，连接池饱和则增加max_connections。 |

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** RDS-07, RDS-09, RDS-02 (CPU Warning)

---

## RDS-09: RdsActiveThreadsCritical

```yaml
alert_id: "LCK-RDS-09"
alert_name: "RdsActiveThreadsCritical"
severity: "critical"
tier: "3"
category: "DB-RDS"
team: "dba"
first_responder: "dba on-call"
sla_response: "5min acknowledge | 15min first update | 1h resolution"
old_ids_replaced: ["rds_threads_high_critical"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
lckna:rds:threads_avg2m{} > 48
```
**Trigger:** `for: 2m` | **Meaning / 含义:** >48 active threads for 2 min. Database connection saturation imminent. 超过48个活跃线程持续2分钟，数据库连接即将饱和。

**Golden Path Impact / 黄金流程影响:** **HIGH — new connections likely being refused. 高——新连接可能被拒绝。**

### 2. ACKNOWLEDGE / 确认

- Silence for **15 min** / Post to **wecom-critical** / **Phone ALL + China HQ**

### 3. ANALYZE / 分析

```bash
# IMMEDIATE: Check thread pile-up / 立即检查线程堆积
# SQL: SELECT user, db, command, state, COUNT(*) cnt FROM information_schema.processlist GROUP BY user, db, command, state ORDER BY cnt DESC LIMIT 20;
# Check for deadlocks / 检查死锁
# SQL: SHOW ENGINE INNODB STATUS\G  (look for LATEST DETECTED DEADLOCK)
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 3 | **Kill all idle connections. Kill long queries. If deadlocked, identify and resolve.** 终止所有空闲连接和长查询，如死锁则识别并解决。 |

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** RDS-03 (CPU Critical), BIZ-03 (Order Critical)

---

## RDS-10: RdsDiskFreeWarning

```yaml
alert_id: "LCK-RDS-10"
alert_name: "RdsDiskFreeWarning"
severity: "warning"
tier: "2"
category: "DB-RDS"
team: "dba"
first_responder: "dba on-call"
sla_response: "15min acknowledge | 1h first update | 4h resolution"
old_ids_replaced: ["rds_disk_low_warning", "rds_disk_low_critical"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
lckna:rds:disk_gb{} / aws_rds_allocated_storage_average{} * 100 < 15
```
**Base:** `aws_rds_free_storage_space_average / 1024 / 1024 / 1024`

**Trigger:** `for: 5m` | **Meaning / 含义:** Less than 15% disk space free. Database at risk of running out of storage. 剩余磁盘空间不足15%，数据库面临存储耗尽风险。

**Golden Path Impact / 黄金流程影响:** Medium-High — if disk fills, writes stop, orders fail. 中至高——磁盘满则写入停止，订单失败。

### 2. ACKNOWLEDGE / 确认

- Silence for **30 min** / Post to **wecom-warning** / Phone Team Lead

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
1. Binary log accumulation / 二进制日志积累
2. Large table growth (unarchived data) / 大表增长（未归档数据）
3. Temporary table space from complex queries / 复杂查询的临时表空间
4. InnoDB undo log growth / InnoDB undo日志增长

**Diagnostic Commands / 诊断命令:**
```bash
# Check current disk usage / 检查当前磁盘使用
# PromQL: lckna:rds:disk_gb{dbinstance_identifier="INSTANCE_NAME"}
# Check largest tables / 检查最大表
# SQL: SELECT table_schema, table_name, ROUND(data_length/1024/1024,2) as data_mb, ROUND(index_length/1024/1024,2) as index_mb, ROUND((data_length+index_length)/1024/1024,2) as total_mb FROM information_schema.tables ORDER BY (data_length+index_length) DESC LIMIT 20;
# Check binary log size / 检查二进制日志大小
# SQL: SHOW BINARY LOGS;
# Check disk growth trend / 检查磁盘增长趋势
aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name FreeStorageSpace --dimensions Name=DBInstanceIdentifier,Value=INSTANCE_NAME --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --period 3600 --statistics Minimum --region us-east-1
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 2 | Purge binary logs. Archive old data. Expand storage if needed. 清理二进制日志，归档旧数据，必要时扩容存储。 |

**Remediation / 修复:**
```bash
# Purge old binary logs / 清理旧二进制日志
# SQL: PURGE BINARY LOGS BEFORE DATE(NOW() - INTERVAL 3 DAY);
# Expand storage (non-disruptive) / 扩容存储（无中断）
aws rds modify-db-instance --db-instance-identifier INSTANCE_NAME --allocated-storage NEW_SIZE_GB --apply-immediately --region us-east-1
```

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** All RDS alerts
- **Prevention / 预防:** Set up automated binlog purge. Implement data archival policies. 设置自动binlog清理和数据归档策略。

---

## RDS-11: RdsVipUnreachableCritical

```yaml
alert_id: "LCK-RDS-11"
alert_name: "RdsVipUnreachableCritical"
severity: "critical"
tier: "3"
category: "DB-RDS"
team: "dba"
first_responder: "dba on-call"
sla_response: "5min acknowledge | 15min first update | 1h resolution"
old_ids_replaced: ["rds_vip_unreachable"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
probe_success{job="rds-blackbox", instance=~".*rds.*"} == 0
```
**Trigger:** `for: 1m` | **Meaning / 含义:** RDS endpoint unreachable via network probe. Database completely inaccessible. RDS端点网络探测不通，数据库完全无法访问。

**Golden Path Impact / 黄金流程影响:** **CRITICAL — applications cannot reach database. 严重——应用程序无法连接数据库。**

### 2. ACKNOWLEDGE / 确认

- Silence for **15 min** / Post to **wecom-critical** / **Phone ALL + China HQ**

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
1. RDS instance in maintenance/reboot / RDS实例维护/重启中
2. Security group change / 安全组变更
3. VPC/subnet issue / VPC/子网问题
4. DNS resolution failure / DNS解析故障
5. RDS failover in progress / RDS故障转移进行中

**Diagnostic Commands / 诊断命令:**
```bash
# Check RDS status / 检查RDS状态
aws rds describe-db-instances --db-instance-identifier INSTANCE_NAME --query 'DBInstances[0].[DBInstanceStatus,Endpoint]' --region us-east-1
# Check recent RDS events / 检查最近RDS事件
aws rds describe-events --source-identifier INSTANCE_NAME --source-type db-instance --duration 60 --region us-east-1
# Check DNS resolution / 检查DNS解析
nslookup INSTANCE_NAME.xxxx.us-east-1.rds.amazonaws.com
# Check security groups / 检查安全组
aws rds describe-db-instances --db-instance-identifier INSTANCE_NAME --query 'DBInstances[0].VpcSecurityGroups' --region us-east-1
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 3 | If failover: wait and monitor. If SG change: revert. If DNS: flush and retry. 故障转移则等待监控，安全组变更则恢复，DNS问题则刷新重试。 |

### 5. AFTERMATH / 善后

- **Related Alerts / 相关告警:** RDS-12 (Failover), BIZ-03 (Order Critical)

---

## RDS-12: RdsFailoverCritical

```yaml
alert_id: "LCK-RDS-12"
alert_name: "RdsFailoverCritical"
severity: "critical"
tier: "3"
category: "DB-RDS"
team: "dba"
first_responder: "dba on-call"
sla_response: "5min acknowledge | 15min first update | 1h resolution"
old_ids_replaced: ["rds_failover_detected"]
last_updated: "2026-02-16"
```

### 1. ASSESS / 评估

**PromQL:**
```promql
changes(aws_rds_engine_uptime_average{dbinstance_identifier!~".*reader.*"}[10m]) > 0
```
**Trigger:** `for: 0m` (instant) | **Meaning / 含义:** RDS engine uptime reset detected — instance restarted or failed over. RDS引擎运行时间重置——实例已重启或故障转移。

**Golden Path Impact / 黄金流程影响:** **CRITICAL — brief connection loss during failover (typically 30-120 seconds). 严重——故障转移期间短暂连接丢失（通常30-120秒）。**

### 2. ACKNOWLEDGE / 确认

- Silence for **15 min** / Post to **wecom-critical** / **Phone ALL + China HQ**

### 3. ANALYZE / 分析

**Common Causes / 常见原因:**
1. AWS automated failover (hardware issue) / AWS自动故障转移（硬件问题）
2. Manual failover triggered / 手动触发故障转移
3. RDS maintenance window / RDS维护窗口
4. Instance reboot / 实例重启

**Diagnostic Commands / 诊断命令:**
```bash
# Check failover details / 检查故障转移详情
aws rds describe-events --source-identifier INSTANCE_NAME --source-type db-instance --duration 60 --region us-east-1
# Check current instance status / 检查当前实例状态
aws rds describe-db-instances --db-instance-identifier INSTANCE_NAME --query 'DBInstances[0].[DBInstanceStatus,MultiAZ,SecondaryAvailabilityZone]' --region us-east-1
# Verify application reconnection / 验证应用重连
# PromQL: aws_rds_database_connections_average{dbinstance_identifier="INSTANCE_NAME"}
```

### 4. ACT / 行动

| Tier | Action / 行动 |
|------|--------------|
| Tier 3 | Verify instance is back online. Verify applications reconnected. Monitor for data consistency. 验证实例恢复在线，确认应用已重连，监控数据一致性。 |

**Post-Failover Checks / 故障转移后检查:**
```bash
# Check replication lag (if Multi-AZ) / 检查复制延迟
# PromQL: aws_rds_replica_lag_average{dbinstance_identifier="INSTANCE_NAME"}
# Check application connection pools / 检查应用连接池
kubectl get pods -n production -o wide | grep -i error
```

### 5. AFTERMATH / 善后

- **Post-incident review MANDATORY** / 必须事后回顾
- **Related Alerts / 相关告警:** RDS-11 (VIP Unreachable), BIZ-03 (Order Critical)
- **Prevention / 预防:** Ensure Multi-AZ is enabled. Test application reconnection logic. 确保启用Multi-AZ，测试应用重连逻辑。

---

*End of Part 2: DB-RDS — RDS MySQL (12 alerts)*

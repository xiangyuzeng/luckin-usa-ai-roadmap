-- ============================================================
-- UC-IT-01: Predictive Infrastructure Monitoring
-- 预测性基础设施监控
-- File: 03_extract_redis_metrics.sql
-- Source: Prometheus API (http://localhost:9090)
-- Target: dbatest (test.infra_metric_daily)
-- Purpose: Extract Redis metrics from Prometheus API and insert
--          into the analytics tables. Contains SQL templates for
--          the Python orchestrator (prometheus_collector.py) and
--          standalone SQL for manual data loading.
-- 中文描述: 从Prometheus API提取Redis指标并插入分析表。
--          包含Python编排器使用的SQL模板和手动数据加载的独立SQL。
-- Author: Data Engineering / BI Team
-- Created: 2026-02-15
-- ============================================================
--
-- ARCHITECTURE:
-- ┌─────────────────┐     ┌──────────────────────┐     ┌──────────────────┐
-- │ Prometheus API   │────►│ prometheus_collector  │────►│ test.infra_      │
-- │ localhost:9090   │     │ .py (Python)          │     │ metric_daily     │
-- │ (PromQL queries) │     │ (ETL orchestrator)    │     │ (MySQL / dbatest)│
-- └─────────────────┘     └──────────────────────┘     └──────────────────┘
--
-- WORKFLOW:
--   1. Python orchestrator queries Prometheus API using PromQL
--   2. Response JSON is parsed to extract metric values per instance
--   3. Instance name is extracted from the Redis connection URL
--   4. INSERT INTO statements are executed against dbatest
--   5. Data quality checks verify the loaded data
--
-- INSTANCE NAME EXTRACTION LOGIC:
--   Connection URL format:
--     rediss://master.luckyus-<SERVICE_NAME>.vyllrs.use1.cache.amazonaws.com:6379
--
--   Python regex:
--     re.search(r'master\.luckyus-(.+?)\.vyllrs', addr).group(1)
--
--   SQL equivalent (for verification):
--     SUBSTRING_INDEX(SUBSTRING_INDEX(addr, 'luckyus-', -1), '.vyllrs', 1)
--
--   Example:
--     Input:  rediss://master.luckyus-isales-market.vyllrs.use1.cache.amazonaws.com:6379
--     Output: isales-market
--
-- DEPENDENCIES:
--   - 02_create_monitoring_schema.sql must have been executed first
--   - Prometheus API must be accessible at http://localhost:9090
-- ============================================================

USE test;


-- ############################################################################
-- SECTION 1: REDIS MEMORY METRICS
-- Redis内存指标
-- ############################################################################
-- Memory metrics are the most critical for Redis capacity planning.
-- A Redis instance running out of memory will start evicting keys or
-- reject writes entirely, causing application failures.

-- ============================================================
-- 1.1 redis_memory_used_bytes — Total memory used by Redis
-- Redis使用的总内存（字节）
-- ============================================================
-- RUN AGAINST: Prometheus API
-- PromQL: redis_memory_used_bytes{job="redis_exporter"}
-- API:    GET http://localhost:9090/api/v1/query?query=redis_memory_used_bytes{job="redis_exporter"}
--
-- For historical daily average:
-- PromQL: avg_over_time(redis_memory_used_bytes{job="redis_exporter"}[24h])
-- API:    GET http://localhost:9090/api/v1/query?query=avg_over_time(redis_memory_used_bytes{job="redis_exporter"}[24h])
--
-- Unit: bytes
-- Expected range: 1MB (small instances) to 2GB (isales-market)

-- SQL Template for Python orchestrator (prometheus_collector.py)
-- Placeholders: %s will be replaced by the Python script
INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('REDIS', %s, %s, %s,
     'redis_memory_used_bytes', %s, 'bytes', 'PROMETHEUS', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 1.2 redis_memory_max_bytes — Maximum configured memory
-- Redis配置的最大内存（字节）
-- ============================================================
-- RUN AGAINST: Prometheus API
-- PromQL: redis_memory_max_bytes{job="redis_exporter"}
-- Unit: bytes
-- Note: Returns 0 if maxmemory is not set (no limit)

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('REDIS', %s, %s, %s,
     'redis_memory_max_bytes', %s, 'bytes', 'PROMETHEUS', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 1.3 redis_memory_used_rss_bytes — Resident Set Size
-- Redis常驻内存集大小（字节）
-- ============================================================
-- RUN AGAINST: Prometheus API
-- PromQL: redis_memory_used_rss_bytes{job="redis_exporter"}
-- Unit: bytes
-- Note: RSS includes memory fragmentation. RSS >> used_bytes indicates fragmentation.

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('REDIS', %s, %s, %s,
     'redis_memory_used_rss_bytes', %s, 'bytes', 'PROMETHEUS', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 1.4 redis_mem_fragmentation_ratio — Memory fragmentation
-- Redis内存碎片率
-- ============================================================
-- RUN AGAINST: Prometheus API
-- PromQL: redis_mem_fragmentation_ratio{job="redis_exporter"}
-- Unit: ratio (dimensionless)
-- Healthy: 1.0 - 1.5 | Warning: > 1.5 | Critical: > 2.0 or < 1.0

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('REDIS', %s, %s, %s,
     'redis_mem_fragmentation_ratio', %s, 'ratio', 'PROMETHEUS', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ############################################################################
-- SECTION 2: REDIS CONNECTION METRICS
-- Redis连接指标
-- ############################################################################
-- Connection metrics track client connectivity. A sudden spike in connections
-- may indicate a connection leak; dropped connections suggest capacity issues.

-- ============================================================
-- 2.1 redis_connected_clients — Current connected clients
-- 当前连接的客户端数
-- ============================================================
-- RUN AGAINST: Prometheus API
-- PromQL: redis_connected_clients{job="redis_exporter"}
-- Unit: count
-- Top consumers: jumpserver (320), aapi-unionauth (209), sapi-unionauth (206)

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('REDIS', %s, %s, %s,
     'redis_connected_clients', %s, 'count', 'PROMETHEUS', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 2.2 redis_blocked_clients — Clients blocked on BLPOP/BRPOP
-- 被阻塞的客户端数
-- ============================================================
-- RUN AGAINST: Prometheus API
-- PromQL: redis_blocked_clients{job="redis_exporter"}
-- Unit: count
-- Expected: Usually 0. Any non-zero value warrants investigation.

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('REDIS', %s, %s, %s,
     'redis_blocked_clients', %s, 'count', 'PROMETHEUS', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 2.3 redis_rejected_connections_total — Rejected connections (counter)
-- 被拒绝的连接总数（累计）
-- ============================================================
-- RUN AGAINST: Prometheus API
-- PromQL: increase(redis_rejected_connections_total{job="redis_exporter"}[24h])
-- Unit: count (daily increase)
-- Note: This is a counter — use increase() or rate() in PromQL

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('REDIS', %s, %s, %s,
     'redis_rejected_connections_daily', %s, 'count', 'PROMETHEUS', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 2.4 redis_connections_received_total — Total connections received (counter)
-- 接收的总连接数（累计）
-- ============================================================
-- RUN AGAINST: Prometheus API
-- PromQL: increase(redis_connections_received_total{job="redis_exporter"}[24h])
-- Unit: count (daily increase)

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('REDIS', %s, %s, %s,
     'redis_connections_received_daily', %s, 'count', 'PROMETHEUS', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ############################################################################
-- SECTION 3: REDIS OPERATIONS METRICS
-- Redis操作指标
-- ############################################################################
-- Operations metrics measure throughput and cache effectiveness.

-- ============================================================
-- 3.1 redis_commands_processed_total — Command rate (counter)
-- 处理的命令总数（累计）
-- ============================================================
-- RUN AGAINST: Prometheus API
-- PromQL (rate): rate(redis_commands_processed_total{job="redis_exporter"}[5m])
-- PromQL (daily total): increase(redis_commands_processed_total{job="redis_exporter"}[24h])
-- Unit: ops_per_sec (rate) or count (daily total)

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('REDIS', %s, %s, %s,
     'redis_commands_per_sec', %s, 'ops_per_sec', 'PROMETHEUS', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 3.2 redis_commands_duration_seconds_total — Command duration (counter)
-- 命令执行耗时总计（累计，秒）
-- ============================================================
-- RUN AGAINST: Prometheus API
-- PromQL: rate(redis_commands_duration_seconds_total{job="redis_exporter"}[5m])
-- Unit: seconds (average duration per second of processing)

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('REDIS', %s, %s, %s,
     'redis_commands_duration_avg_sec', %s, 'seconds', 'PROMETHEUS', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 3.3 redis_keyspace_hits_total — Cache hits (counter)
-- 缓存命中总数（累计）
-- ============================================================
-- RUN AGAINST: Prometheus API
-- PromQL: increase(redis_keyspace_hits_total{job="redis_exporter"}[24h])
-- Unit: count (daily increase)

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('REDIS', %s, %s, %s,
     'redis_keyspace_hits_daily', %s, 'count', 'PROMETHEUS', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 3.4 redis_keyspace_misses_total — Cache misses (counter)
-- 缓存未命中总数（累计）
-- ============================================================
-- RUN AGAINST: Prometheus API
-- PromQL: increase(redis_keyspace_misses_total{job="redis_exporter"}[24h])
-- Unit: count (daily increase)

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('REDIS', %s, %s, %s,
     'redis_keyspace_misses_daily', %s, 'count', 'PROMETHEUS', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ############################################################################
-- SECTION 4: REDIS CPU METRICS
-- Redis CPU指标
-- ############################################################################
-- CPU metrics help identify instances that are compute-bound.
-- Redis is single-threaded for command execution, so high CPU on the
-- main thread is a bottleneck indicator.

-- ============================================================
-- 4.1 redis_cpu_sys_seconds_total — System CPU (counter)
-- 系统CPU使用时间（累计，秒）
-- ============================================================
-- RUN AGAINST: Prometheus API
-- PromQL: rate(redis_cpu_sys_seconds_total{job="redis_exporter"}[5m])
-- Unit: seconds/second (CPU utilization fraction)

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('REDIS', %s, %s, %s,
     'redis_cpu_sys_rate', %s, 'percent', 'PROMETHEUS', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 4.2 redis_cpu_user_seconds_total — User CPU (counter)
-- 用户CPU使用时间（累计，秒）
-- ============================================================
-- RUN AGAINST: Prometheus API
-- PromQL: rate(redis_cpu_user_seconds_total{job="redis_exporter"}[5m])
-- Unit: seconds/second (CPU utilization fraction)

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('REDIS', %s, %s, %s,
     'redis_cpu_user_rate', %s, 'percent', 'PROMETHEUS', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ############################################################################
-- SECTION 5: REDIS REPLICATION METRICS
-- Redis复制指标
-- ############################################################################
-- Replication metrics are important for high-availability monitoring.
-- ElastiCache Redis uses replication for read replicas and failover.

-- ============================================================
-- 5.1 redis_connected_slaves — Connected replicas
-- 连接的从节点数
-- ============================================================
-- RUN AGAINST: Prometheus API
-- PromQL: redis_connected_slaves{job="redis_exporter"}
-- Unit: count
-- Expected: 1 for most instances (one read replica)

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('REDIS', %s, %s, %s,
     'redis_connected_slaves', %s, 'count', 'PROMETHEUS', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 5.2 redis_repl_backlog_is_active — Replication backlog status
-- 复制积压缓冲区是否活跃
-- ============================================================
-- RUN AGAINST: Prometheus API
-- PromQL: redis_repl_backlog_is_active{job="redis_exporter"}
-- Unit: boolean (0 or 1)

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('REDIS', %s, %s, %s,
     'redis_repl_backlog_active', %s, 'boolean', 'PROMETHEUS', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ############################################################################
-- SECTION 6: REDIS EVICTION METRICS
-- Redis驱逐指标
-- ############################################################################
-- Eviction and expiration metrics indicate memory pressure and TTL activity.

-- ============================================================
-- 6.1 redis_evicted_keys_total — Evicted keys (counter)
-- 被驱逐的键总数（累计）
-- ============================================================
-- RUN AGAINST: Prometheus API
-- PromQL: increase(redis_evicted_keys_total{job="redis_exporter"}[24h])
-- Unit: count (daily increase)
-- CRITICAL: Non-zero evictions mean Redis is running out of memory!

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('REDIS', %s, %s, %s,
     'redis_evicted_keys_daily', %s, 'count', 'PROMETHEUS', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 6.2 redis_expired_keys_total — Expired keys (counter)
-- 过期的键总数（累计）
-- ============================================================
-- RUN AGAINST: Prometheus API
-- PromQL: increase(redis_expired_keys_total{job="redis_exporter"}[24h])
-- Unit: count (daily increase)
-- Note: Healthy instances should have regular expirations; zero may mean no TTLs set.

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('REDIS', %s, %s, %s,
     'redis_expired_keys_daily', %s, 'count', 'PROMETHEUS', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ############################################################################
-- SECTION 7: COMPUTED METRICS
-- 计算指标
-- ############################################################################
-- Derived metrics calculated from raw metrics. These provide higher-level
-- indicators that are more meaningful for anomaly detection.

-- ============================================================
-- 7.1 hit_rate — Cache hit rate
-- 缓存命中率
-- ============================================================
-- Formula: hits / (hits + misses)
-- PromQL:
--   rate(redis_keyspace_hits_total[5m]) /
--   (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m]))
--
-- Unit: percent (0.0 - 1.0, stored as 0-100)
-- Healthy: > 95% | Warning: < 90% | Critical: < 80%
--
-- The Python orchestrator computes this from the raw hits and misses values:
--   hit_rate = hits / (hits + misses) * 100  if (hits + misses) > 0 else None

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('REDIS', %s, %s, %s,
     'redis_hit_rate', %s, 'percent', 'PROMETHEUS', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 7.2 memory_utilization — Memory usage percentage
-- 内存使用率
-- ============================================================
-- Formula: memory_used_bytes / memory_max_bytes * 100
-- Only computable when maxmemory is set (memory_max_bytes > 0)
--
-- Unit: percent (0-100)
-- Healthy: < 70% | Warning: 70-85% | Critical: > 85% | Emergency: > 95%

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('REDIS', %s, %s, %s,
     'redis_memory_utilization', %s, 'percent', 'PROMETHEUS', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 7.3 Standalone SQL: Compute hit_rate from already-loaded raw metrics
-- 独立SQL：从已加载的原始指标计算命中率
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
-- This can be run after raw hits and misses have been loaded into
-- infra_metric_daily, as an alternative to the Python computation.

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
SELECT
    h.service_type,
    h.instance_id,
    h.instance_name,
    h.metric_date,
    'redis_hit_rate'                                          AS metric_name,
    CASE
        WHEN (h.metric_value + m.metric_value) > 0
        THEN ROUND(h.metric_value / (h.metric_value + m.metric_value) * 100, 2)
        ELSE NULL
    END                                                       AS metric_value,
    'percent'                                                 AS metric_unit,
    'PROMETHEUS'                                              AS source,
    h.day_of_week,
    h.is_weekend
FROM test.infra_metric_daily h
JOIN test.infra_metric_daily m
    ON  h.service_type = m.service_type
    AND h.instance_id  = m.instance_id
    AND h.metric_date  = m.metric_date
WHERE h.metric_name = 'redis_keyspace_hits_daily'
  AND m.metric_name = 'redis_keyspace_misses_daily'
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 7.4 Standalone SQL: Compute memory_utilization from loaded metrics
-- 独立SQL：从已加载的指标计算内存使用率
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
SELECT
    u.service_type,
    u.instance_id,
    u.instance_name,
    u.metric_date,
    'redis_memory_utilization'                                AS metric_name,
    CASE
        WHEN mx.metric_value > 0
        THEN ROUND(u.metric_value / mx.metric_value * 100, 2)
        ELSE NULL
    END                                                       AS metric_value,
    'percent'                                                 AS metric_unit,
    'PROMETHEUS'                                              AS source,
    u.day_of_week,
    u.is_weekend
FROM test.infra_metric_daily u
JOIN test.infra_metric_daily mx
    ON  u.service_type = mx.service_type
    AND u.instance_id  = mx.instance_id
    AND u.metric_date  = mx.metric_date
WHERE u.metric_name  = 'redis_memory_used_bytes'
  AND mx.metric_name = 'redis_memory_max_bytes'
  AND mx.metric_value > 0
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ############################################################################
-- SECTION 8: DATA QUALITY CHECKS
-- 数据质量检查
-- ############################################################################
-- Run these queries after data loading to verify completeness and accuracy.

-- ============================================================
-- 8.1 Row count per metric name
-- 每个指标的行数
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
SELECT
    metric_name,
    COUNT(*)            AS row_count,
    COUNT(DISTINCT instance_id) AS instance_count,
    MIN(metric_date)    AS earliest_date,
    MAX(metric_date)    AS latest_date
FROM test.infra_metric_daily
WHERE service_type = 'REDIS'
GROUP BY metric_name
ORDER BY metric_name;


-- ============================================================
-- 8.2 Check for NULL metric values
-- 检查空指标值
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
SELECT
    metric_name,
    COUNT(*)                                        AS total_rows,
    SUM(CASE WHEN metric_value IS NULL THEN 1 ELSE 0 END) AS null_count,
    ROUND(SUM(CASE WHEN metric_value IS NULL THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                    AS null_pct
FROM test.infra_metric_daily
WHERE service_type = 'REDIS'
GROUP BY metric_name
HAVING null_count > 0
ORDER BY null_pct DESC;


-- ============================================================
-- 8.3 Validate metric value ranges
-- 验证指标值范围
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
SELECT
    metric_name,
    metric_unit,
    MIN(metric_value)           AS min_value,
    AVG(metric_value)           AS avg_value,
    MAX(metric_value)           AS max_value,
    STDDEV(metric_value)        AS stddev_value
FROM test.infra_metric_daily
WHERE service_type = 'REDIS'
  AND metric_value IS NOT NULL
GROUP BY metric_name, metric_unit
ORDER BY metric_name;


-- ============================================================
-- 8.4 Check for expected instance coverage
-- 检查预期实例覆盖率
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
-- We expect 75 instances (76 minus 1 DOWN) for each metric on each day.
SELECT
    metric_date,
    metric_name,
    COUNT(DISTINCT instance_id) AS instance_count,
    CASE
        WHEN COUNT(DISTINCT instance_id) >= 75 THEN 'OK'
        WHEN COUNT(DISTINCT instance_id) >= 70 THEN 'WARNING'
        ELSE 'CRITICAL'
    END AS coverage_status
FROM test.infra_metric_daily
WHERE service_type = 'REDIS'
GROUP BY metric_date, metric_name
HAVING instance_count < 75
ORDER BY metric_date DESC, metric_name;


-- ============================================================
-- 8.5 Check for duplicate entries
-- 检查重复数据
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
-- The UNIQUE KEY should prevent duplicates, but verify anyway
SELECT
    service_type,
    instance_id,
    metric_date,
    metric_name,
    COUNT(*) AS dup_count
FROM test.infra_metric_daily
WHERE service_type = 'REDIS'
GROUP BY service_type, instance_id, metric_date, metric_name
HAVING dup_count > 1;


-- ============================================================
-- 8.6 Validate fragmentation ratio range
-- 验证碎片率范围
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
-- Fragmentation ratio should normally be between 0.5 and 5.0
-- Values outside this range likely indicate measurement errors.
SELECT
    instance_id,
    instance_name,
    metric_date,
    metric_value AS fragmentation_ratio,
    CASE
        WHEN metric_value < 0.5 THEN 'ANOMALOUS_LOW'
        WHEN metric_value > 5.0 THEN 'ANOMALOUS_HIGH'
        WHEN metric_value < 1.0 THEN 'SWAPPING'
        WHEN metric_value > 2.0 THEN 'HIGH_FRAGMENTATION'
        ELSE 'NORMAL'
    END AS status
FROM test.infra_metric_daily
WHERE service_type = 'REDIS'
  AND metric_name = 'redis_mem_fragmentation_ratio'
  AND (metric_value < 0.5 OR metric_value > 5.0)
ORDER BY metric_value DESC;


-- ############################################################################
-- SECTION 9: SAMPLE VERIFICATION QUERIES
-- 示例验证查询
-- ############################################################################
-- Quick queries to spot-check data after loading.

-- ============================================================
-- 9.1 Latest metrics for top-memory instance (isales-market)
-- isales-market最新指标
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
SELECT
    metric_date,
    metric_name,
    metric_value,
    metric_unit
FROM test.infra_metric_daily
WHERE service_type = 'REDIS'
  AND instance_name = 'isales-market'
  AND metric_date = (SELECT MAX(metric_date) FROM test.infra_metric_daily WHERE service_type = 'REDIS')
ORDER BY metric_name;


-- ============================================================
-- 9.2 Memory trend for isales-market (last 14 days)
-- isales-market内存趋势（最近14天）
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
SELECT
    metric_date,
    ROUND(metric_value / 1024 / 1024, 2) AS memory_mb,
    day_of_week,
    is_weekend
FROM test.infra_metric_daily
WHERE service_type = 'REDIS'
  AND instance_name = 'isales-market'
  AND metric_name = 'redis_memory_used_bytes'
ORDER BY metric_date DESC
LIMIT 14;


-- ============================================================
-- 9.3 All instances sorted by latest memory usage
-- 所有实例按最新内存使用排序
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
SELECT
    instance_name,
    ROUND(metric_value / 1024 / 1024, 2) AS memory_mb,
    metric_date
FROM test.infra_metric_daily
WHERE service_type = 'REDIS'
  AND metric_name = 'redis_memory_used_bytes'
  AND metric_date = (SELECT MAX(metric_date) FROM test.infra_metric_daily WHERE service_type = 'REDIS')
ORDER BY metric_value DESC
LIMIT 20;


-- ============================================================
-- 9.4 Fleet summary: total metrics loaded
-- 集群摘要：已加载的指标总数
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
SELECT
    service_type,
    COUNT(*)                                AS total_rows,
    COUNT(DISTINCT instance_id)             AS unique_instances,
    COUNT(DISTINCT metric_name)             AS unique_metrics,
    COUNT(DISTINCT metric_date)             AS date_range_days,
    MIN(metric_date)                        AS earliest_date,
    MAX(metric_date)                        AS latest_date
FROM test.infra_metric_daily
WHERE service_type = 'REDIS'
GROUP BY service_type;


-- ============================================================
-- 9.5 Connection metrics for high-client instances
-- 高连接数实例的连接指标
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
SELECT
    m.instance_name,
    m.metric_date,
    m.metric_value AS connected_clients,
    b.metric_value AS blocked_clients,
    r.metric_value AS rejected_daily
FROM test.infra_metric_daily m
LEFT JOIN test.infra_metric_daily b
    ON  m.service_type = b.service_type
    AND m.instance_id  = b.instance_id
    AND m.metric_date  = b.metric_date
    AND b.metric_name  = 'redis_blocked_clients'
LEFT JOIN test.infra_metric_daily r
    ON  m.service_type = r.service_type
    AND m.instance_id  = r.instance_id
    AND m.metric_date  = r.metric_date
    AND r.metric_name  = 'redis_rejected_connections_daily'
WHERE m.service_type = 'REDIS'
  AND m.metric_name = 'redis_connected_clients'
  AND m.metric_value > 100
  AND m.metric_date = (SELECT MAX(metric_date) FROM test.infra_metric_daily WHERE service_type = 'REDIS')
ORDER BY m.metric_value DESC;


-- ============================================================
-- NEXT STEP: Execute 04_extract_cloudwatch_metrics.sql for RDS/EC2 data.
-- ============================================================
-- END OF FILE: 03_extract_redis_metrics.sql
-- ============================================================

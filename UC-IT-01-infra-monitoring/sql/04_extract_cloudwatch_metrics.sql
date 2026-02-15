-- ============================================================
-- UC-IT-01: Predictive Infrastructure Monitoring
-- 预测性基础设施监控
-- File: 04_extract_cloudwatch_metrics.sql
-- Source: CloudWatch API (via boto3 / MCP CloudWatch tools)
-- Target: dbatest (test.infra_metric_daily)
-- Purpose: Extract CloudWatch RDS and EC2 metrics and insert
--          into the analytics tables. Contains SQL templates for
--          the Python orchestrator (cloudwatch_collector.py) and
--          standalone SQL for manual data loading.
-- 中文描述: 从CloudWatch API提取RDS和EC2指标并插入分析表。
--          包含Python编排器使用的SQL模板和手动数据加载的独立SQL。
-- Author: Data Engineering / BI Team
-- Created: 2026-02-15
-- ============================================================
--
-- ARCHITECTURE:
-- ┌─────────────────┐     ┌──────────────────────┐     ┌──────────────────┐
-- │ CloudWatch API   │────►│ cloudwatch_collector  │────►│ test.infra_      │
-- │ (boto3 / MCP)    │     │ .py (Python)          │     │ metric_daily     │
-- │ Namespace:       │     │ (ETL orchestrator)    │     │ (MySQL / dbatest)│
-- │  AWS/RDS         │     │                       │     │                  │
-- │  AWS/EC2         │     │                       │     │                  │
-- └─────────────────┘     └──────────────────────┘     └──────────────────┘
--
-- CLOUDWATCH QUERY PATTERN:
--   Every CloudWatch metric query requires:
--     - Namespace:   The AWS service namespace (e.g., AWS/RDS, AWS/EC2)
--     - MetricName:  The specific metric (e.g., CPUUtilization)
--     - Dimensions:  Key-value pairs identifying the resource
--     - Statistics:  Aggregation type (Average, Sum, Maximum, Minimum)
--     - Period:      Aggregation window in seconds (e.g., 86400 for daily)
--     - StartTime:   Query start time (ISO 8601)
--     - EndTime:     Query end time (ISO 8601)
--
-- RDS DIMENSION PATTERNS:
--   Instance-level:  {"Name": "DBInstanceIdentifier", "Value": "luckyus-<service>-instance-1"}
--   Cluster-level:   {"Name": "DBClusterIdentifier",  "Value": "luckyus-<service>"}
--
-- NAMING CONVENTION:
--   CloudWatch DBClusterIdentifier: luckyus-<service>
--   Maps to instance_name:          <service>
--   Example: luckyus-isales-market → isales-market
--
-- RDS LOG GROUP PATTERN:
--   /aws/rds/cluster/luckyus-<service>/slowquery
--   Total: 58 log groups discovered
--
-- DEPENDENCIES:
--   - 02_create_monitoring_schema.sql must have been executed first
--   - AWS credentials must be configured (boto3 / IAM role)
--   - CloudWatch API access required
-- ============================================================

USE test;


-- ############################################################################
-- SECTION 1: RDS CPU METRICS
-- RDS CPU指标
-- ############################################################################
-- CPU utilization is the primary performance indicator for RDS instances.
-- Aurora MySQL can scale read replicas horizontally, but write instances
-- are vertically scaled — high CPU on the writer is a capacity concern.

-- ============================================================
-- 1.1 CPUUtilization — Average CPU usage (percent)
-- CPU利用率（百分比）
-- ============================================================
-- RUN AGAINST: CloudWatch API
-- Namespace:   AWS/RDS
-- MetricName:  CPUUtilization
-- Dimensions:  DBClusterIdentifier = "luckyus-<service>"
-- Statistics:  Average
-- Period:      86400 (1 day)
-- Unit:        Percent (0-100)
--
-- boto3 example:
--   response = cloudwatch.get_metric_statistics(
--       Namespace='AWS/RDS',
--       MetricName='CPUUtilization',
--       Dimensions=[{'Name': 'DBClusterIdentifier', 'Value': 'luckyus-isales-market'}],
--       StartTime=start_time,
--       EndTime=end_time,
--       Period=86400,
--       Statistics=['Average']
--   )
--
-- Expected range: 5-80% (normal), > 80% (warning), > 90% (critical)
-- Typical values: 10-30% for most clusters, 40-60% for heavy workloads

-- SQL Template for Python orchestrator (cloudwatch_collector.py)
INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('RDS', %s, %s, %s,
     'rds_cpu_utilization', %s, 'percent', 'CLOUDWATCH', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ############################################################################
-- SECTION 2: RDS MEMORY METRICS
-- RDS内存指标
-- ############################################################################
-- Aurora MySQL manages memory through its own buffer pool and page cache.
-- FreeableMemory shows how much memory is available before the OS starts
-- swapping, which is a severe performance issue.

-- ============================================================
-- 2.1 FreeableMemory — Available memory (bytes)
-- 可用内存（字节）
-- ============================================================
-- RUN AGAINST: CloudWatch API
-- Namespace:   AWS/RDS
-- MetricName:  FreeableMemory
-- Dimensions:  DBClusterIdentifier = "luckyus-<service>"
-- Statistics:  Average
-- Period:      86400 (1 day)
-- Unit:        Bytes
--
-- Warning: < 1 GB | Critical: < 500 MB | Emergency: < 200 MB
-- Note: Low FreeableMemory doesn't always mean a problem; Aurora uses
-- available memory for caching. But a downward trend is concerning.

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('RDS', %s, %s, %s,
     'rds_freeable_memory', %s, 'bytes', 'CLOUDWATCH', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 2.2 SwapUsage — Swap space used (bytes)
-- 交换空间使用量（字节）
-- ============================================================
-- RUN AGAINST: CloudWatch API
-- Namespace:   AWS/RDS
-- MetricName:  SwapUsage
-- Dimensions:  DBClusterIdentifier = "luckyus-<service>"
-- Statistics:  Average
-- Period:      86400 (1 day)
-- Unit:        Bytes
--
-- Healthy: 0 bytes (no swapping)
-- ANY non-zero swap usage indicates memory pressure and should trigger alerts.

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('RDS', %s, %s, %s,
     'rds_swap_usage', %s, 'bytes', 'CLOUDWATCH', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ############################################################################
-- SECTION 3: RDS CONNECTION METRICS
-- RDS连接指标
-- ############################################################################
-- Database connections are a limited resource. Aurora MySQL has a max
-- connection limit based on instance class. Connection exhaustion causes
-- application errors.

-- ============================================================
-- 3.1 DatabaseConnections — Active connections (count)
-- 活跃数据库连接数
-- ============================================================
-- RUN AGAINST: CloudWatch API
-- Namespace:   AWS/RDS
-- MetricName:  DatabaseConnections
-- Dimensions:  DBClusterIdentifier = "luckyus-<service>"
-- Statistics:  Average
-- Period:      86400 (1 day)
-- Unit:        Count
--
-- Max connections vary by instance class:
--   db.r6g.large:  1000-2000 (depending on parameter group)
--   db.r5.xlarge:  2000-4000
--   db.r5.2xlarge: 4000-8000
-- Warning threshold: > 80% of max | Critical: > 90% of max

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('RDS', %s, %s, %s,
     'rds_database_connections', %s, 'count', 'CLOUDWATCH', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ############################################################################
-- SECTION 4: RDS STORAGE METRICS
-- RDS存储指标
-- ############################################################################
-- Aurora MySQL uses a shared storage layer that automatically grows.
-- However, monitoring storage helps identify data growth trends and
-- potential cost increases.

-- ============================================================
-- 4.1 FreeStorageSpace — Available storage (bytes)
-- 可用存储空间（字节）
-- ============================================================
-- RUN AGAINST: CloudWatch API
-- Namespace:   AWS/RDS
-- MetricName:  FreeStorageSpace
-- Dimensions:  DBClusterIdentifier = "luckyus-<service>"
-- Statistics:  Average
-- Period:      86400 (1 day)
-- Unit:        Bytes
--
-- Note: For Aurora, this metric may not be directly applicable since
-- Aurora storage auto-scales. Use VolumeBytesUsed for Aurora clusters.

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('RDS', %s, %s, %s,
     'rds_free_storage_space', %s, 'bytes', 'CLOUDWATCH', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 4.2 DiskQueueDepth — Pending I/O requests (count)
-- 待处理I/O请求队列深度
-- ============================================================
-- RUN AGAINST: CloudWatch API
-- Namespace:   AWS/RDS
-- MetricName:  DiskQueueDepth
-- Dimensions:  DBClusterIdentifier = "luckyus-<service>"
-- Statistics:  Average
-- Period:      86400 (1 day)
-- Unit:        Count
--
-- Healthy: < 1 (on average) | Warning: > 2 | Critical: > 5
-- High queue depth indicates storage I/O bottleneck.

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('RDS', %s, %s, %s,
     'rds_disk_queue_depth', %s, 'count', 'CLOUDWATCH', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ############################################################################
-- SECTION 5: RDS LATENCY METRICS
-- RDS延迟指标
-- ############################################################################
-- Latency metrics measure the time taken for read and write I/O operations.
-- These are critical for understanding application performance impact.

-- ============================================================
-- 5.1 ReadLatency — Average read I/O latency (seconds)
-- 平均读I/O延迟（秒）
-- ============================================================
-- RUN AGAINST: CloudWatch API
-- Namespace:   AWS/RDS
-- MetricName:  ReadLatency
-- Dimensions:  DBClusterIdentifier = "luckyus-<service>"
-- Statistics:  Average
-- Period:      86400 (1 day)
-- Unit:        Seconds
--
-- Healthy: < 0.005 (5ms) | Warning: > 0.010 (10ms) | Critical: > 0.020 (20ms)

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('RDS', %s, %s, %s,
     'rds_read_latency', %s, 'seconds', 'CLOUDWATCH', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 5.2 WriteLatency — Average write I/O latency (seconds)
-- 平均写I/O延迟（秒）
-- ============================================================
-- RUN AGAINST: CloudWatch API
-- Namespace:   AWS/RDS
-- MetricName:  WriteLatency
-- Dimensions:  DBClusterIdentifier = "luckyus-<service>"
-- Statistics:  Average
-- Period:      86400 (1 day)
-- Unit:        Seconds
--
-- Healthy: < 0.005 (5ms) | Warning: > 0.010 (10ms) | Critical: > 0.020 (20ms)
-- Note: Aurora write latency is typically higher than read due to
-- distributed storage replication (6 copies across 3 AZs).

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('RDS', %s, %s, %s,
     'rds_write_latency', %s, 'seconds', 'CLOUDWATCH', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ############################################################################
-- SECTION 6: RDS IOPS METRICS
-- RDS IOPS指标
-- ############################################################################
-- IOPS metrics measure the number of I/O operations per second.
-- Aurora provides baseline IOPS that scale with storage volume size.

-- ============================================================
-- 6.1 ReadIOPS — Read operations per second
-- 每秒读操作数
-- ============================================================
-- RUN AGAINST: CloudWatch API
-- Namespace:   AWS/RDS
-- MetricName:  ReadIOPS
-- Dimensions:  DBClusterIdentifier = "luckyus-<service>"
-- Statistics:  Average
-- Period:      86400 (1 day)
-- Unit:        Count/Second

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('RDS', %s, %s, %s,
     'rds_read_iops', %s, 'ops_per_sec', 'CLOUDWATCH', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 6.2 WriteIOPS — Write operations per second
-- 每秒写操作数
-- ============================================================
-- RUN AGAINST: CloudWatch API
-- Namespace:   AWS/RDS
-- MetricName:  WriteIOPS
-- Dimensions:  DBClusterIdentifier = "luckyus-<service>"
-- Statistics:  Average
-- Period:      86400 (1 day)
-- Unit:        Count/Second

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('RDS', %s, %s, %s,
     'rds_write_iops', %s, 'ops_per_sec', 'CLOUDWATCH', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ############################################################################
-- SECTION 7: RDS NETWORK METRICS
-- RDS网络指标
-- ############################################################################
-- Network throughput metrics help identify data transfer patterns and
-- potential network bottlenecks.

-- ============================================================
-- 7.1 NetworkReceiveThroughput — Inbound network (bytes/sec)
-- 网络接收吞吐量（字节/秒）
-- ============================================================
-- RUN AGAINST: CloudWatch API
-- Namespace:   AWS/RDS
-- MetricName:  NetworkReceiveThroughput
-- Dimensions:  DBClusterIdentifier = "luckyus-<service>"
-- Statistics:  Average
-- Period:      86400 (1 day)
-- Unit:        Bytes/Second
--
-- This includes both client traffic and replication traffic.

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('RDS', %s, %s, %s,
     'rds_network_receive_throughput', %s, 'bytes_per_sec', 'CLOUDWATCH', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 7.2 NetworkTransmitThroughput — Outbound network (bytes/sec)
-- 网络发送吞吐量（字节/秒）
-- ============================================================
-- RUN AGAINST: CloudWatch API
-- Namespace:   AWS/RDS
-- MetricName:  NetworkTransmitThroughput
-- Dimensions:  DBClusterIdentifier = "luckyus-<service>"
-- Statistics:  Average
-- Period:      86400 (1 day)
-- Unit:        Bytes/Second

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('RDS', %s, %s, %s,
     'rds_network_transmit_throughput', %s, 'bytes_per_sec', 'CLOUDWATCH', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ############################################################################
-- SECTION 8: RDS REPLICATION METRICS
-- RDS复制指标
-- ############################################################################
-- Aurora read replicas receive updates asynchronously. Replica lag
-- measures how far behind the replica is from the writer.

-- ============================================================
-- 8.1 ReplicaLag — Replication delay (seconds)
-- 复制延迟（秒）
-- ============================================================
-- RUN AGAINST: CloudWatch API
-- Namespace:   AWS/RDS
-- MetricName:  AuroraReplicaLag (Aurora-specific) or ReplicaLag (standard RDS)
-- Dimensions:  DBInstanceIdentifier = "luckyus-<service>-instance-2" (reader)
-- Statistics:  Average
-- Period:      86400 (1 day)
-- Unit:        Seconds (Aurora uses Milliseconds internally)
--
-- Healthy: < 0.020 (20ms) for Aurora
-- Warning: > 0.100 (100ms)
-- Critical: > 1.0 (1 second)
-- Note: Aurora replication lag is typically very low (< 20ms) because
-- it uses shared storage rather than binlog replication.

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('RDS', %s, %s, %s,
     'rds_replica_lag', %s, 'seconds', 'CLOUDWATCH', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ############################################################################
-- SECTION 9: SLOW QUERY LOG ANALYSIS
-- 慢查询日志分析
-- ############################################################################
-- Slow query counts are extracted from the 58 CloudWatch log groups
-- matching the pattern: /aws/rds/cluster/luckyus-*/slowquery
--
-- This gives us a daily count of slow queries per RDS cluster,
-- which is a key input for the SPC anomaly detection engine.

-- ============================================================
-- 9.1 Slow Query Log Groups — Full List
-- 慢查询日志组完整列表
-- ============================================================
-- The 58 RDS slow query log groups follow the naming pattern:
--   /aws/rds/cluster/luckyus-<service>/slowquery
--
-- Full list of discovered log groups:
--   /aws/rds/cluster/luckyus-isales-market/slowquery
--   /aws/rds/cluster/luckyus-web/slowquery
--   /aws/rds/cluster/luckyus-ireplenishment/slowquery
--   /aws/rds/cluster/luckyus-scm-shopstock/slowquery
--   /aws/rds/cluster/luckyus-pub-dm/slowquery
--   /aws/rds/cluster/luckyus-opshop/slowquery
--   /aws/rds/cluster/luckyus-isales-order/slowquery
--   /aws/rds/cluster/luckyus-ifinance/slowquery
--   /aws/rds/cluster/luckyus-hrs/slowquery
--   /aws/rds/cluster/luckyus-oa/slowquery
--   /aws/rds/cluster/luckyus-icustomer/slowquery
--   /aws/rds/cluster/luckyus-icrm/slowquery
--   /aws/rds/cluster/luckyus-iwms/slowquery
--   /aws/rds/cluster/luckyus-itms/slowquery
--   /aws/rds/cluster/luckyus-datav/slowquery
--   /aws/rds/cluster/luckyus-bi-report/slowquery
--   /aws/rds/cluster/luckyus-scm-supplier/slowquery
--   /aws/rds/cluster/luckyus-iscm/slowquery
--   /aws/rds/cluster/luckyus-ilog/slowquery
--   /aws/rds/cluster/luckyus-message-center/slowquery
--   /aws/rds/cluster/luckyus-task-center/slowquery
--   /aws/rds/cluster/luckyus-isales-member/slowquery
--   /aws/rds/cluster/luckyus-iwarehouse/slowquery
--   /aws/rds/cluster/luckyus-scm-purchase/slowquery
--   /aws/rds/cluster/luckyus-isales-product/slowquery
--   /aws/rds/cluster/luckyus-isales-payment/slowquery
--   /aws/rds/cluster/luckyus-isales-delivery/slowquery
--   /aws/rds/cluster/luckyus-isales-promotion/slowquery
--   /aws/rds/cluster/luckyus-idata/slowquery
--   /aws/rds/cluster/luckyus-scm-commodity/slowquery
--   /aws/rds/cluster/luckyus-print-service/slowquery
--   /aws/rds/cluster/luckyus-sapi-gateway/slowquery
--   /aws/rds/cluster/luckyus-aapi-gateway/slowquery
--   /aws/rds/cluster/luckyus-oapi-gateway/slowquery
--   /aws/rds/cluster/luckyus-config-center/slowquery
--   /aws/rds/cluster/luckyus-registry-center/slowquery
--   /aws/rds/cluster/luckyus-isales-coupon/slowquery
--   /aws/rds/cluster/luckyus-isales-inventory/slowquery
--   /aws/rds/cluster/luckyus-scm-logistics/slowquery
--   /aws/rds/cluster/luckyus-scm-quality/slowquery
--   /aws/rds/cluster/luckyus-scm-warehouse/slowquery
--   /aws/rds/cluster/luckyus-report-center/slowquery
--   /aws/rds/cluster/luckyus-approval-center/slowquery
--   /aws/rds/cluster/luckyus-workflow-engine/slowquery
--   /aws/rds/cluster/luckyus-notification-service/slowquery
--   /aws/rds/cluster/luckyus-file-service/slowquery
--   /aws/rds/cluster/luckyus-auth-service/slowquery
--   /aws/rds/cluster/luckyus-user-center/slowquery
--   /aws/rds/cluster/luckyus-org-center/slowquery
--   /aws/rds/cluster/luckyus-pay-center/slowquery
--   /aws/rds/cluster/luckyus-settle-center/slowquery
--   /aws/rds/cluster/luckyus-mdm/slowquery
--   /aws/rds/cluster/luckyus-dms/slowquery
--   /aws/rds/cluster/luckyus-pos-service/slowquery
--   /aws/rds/cluster/luckyus-mini-program/slowquery
--   /aws/rds/cluster/luckyus-wechat-service/slowquery
--   /aws/rds/cluster/luckyus-search-service/slowquery
--   /aws/rds/cluster/luckyus-analytics-engine/slowquery


-- ============================================================
-- 9.2 Slow Query Count — Daily count per cluster
-- 每日每集群慢查询数量
-- ============================================================
-- RUN AGAINST: CloudWatch API (Logs Insights)
-- Query to count slow queries per day per log group:
--
-- CloudWatch Logs Insights query:
--   fields @timestamp, @message
--   | stats count(*) as slow_query_count by bin(1d)
--
-- boto3 example:
--   response = logs_client.start_query(
--       logGroupName='/aws/rds/cluster/luckyus-isales-market/slowquery',
--       startTime=int(start_time.timestamp()),
--       endTime=int(end_time.timestamp()),
--       queryString='stats count(*) as slow_query_count by bin(1d)',
--       limit=1000
--   )
--
-- MCP tool equivalent:
--   execute_log_insights_query(
--       log_group_names=['/aws/rds/cluster/luckyus-isales-market/slowquery'],
--       start_time='2026-02-14T00:00:00Z',
--       end_time='2026-02-15T00:00:00Z',
--       query_string='stats count(*) as slow_query_count by bin(1d)',
--       limit=50
--   )

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('RDS', %s, %s, %s,
     'rds_slow_query_count', %s, 'count', 'CLOUDWATCH', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 9.3 Slow Query Log Retention Check
-- 慢查询日志保留检查
-- ============================================================
-- RUN AGAINST: CloudWatch API (Logs)
-- AWS CLI:
--   aws logs describe-log-groups \
--     --log-group-name-prefix '/aws/rds/cluster/luckyus-' \
--     --query 'logGroups[?contains(logGroupName, `slowquery`)].
--              {name:logGroupName, retention:retentionInDays, bytes:storedBytes}'
--
-- FINDING: Most log groups have NO retention policy set.
-- COST IMPACT: Unbounded log retention increases CloudWatch Logs costs.
-- RECOMMENDATION: Set 30-day retention on all slow query log groups.
--
-- AWS CLI to set retention:
--   for lg in $(aws logs describe-log-groups \
--     --log-group-name-prefix '/aws/rds/cluster/luckyus-' \
--     --query 'logGroups[?contains(logGroupName, `slowquery`)].logGroupName' \
--     --output text); do
--       aws logs put-retention-policy --log-group-name "$lg" --retention-in-days 30
--   done


-- ############################################################################
-- SECTION 10: EC2 METRICS (FUTURE — PLACEHOLDER)
-- EC2指标（未来——占位）
-- ############################################################################
-- EC2 instances currently have ZERO Prometheus/exporter-based monitoring.
-- Only basic CloudWatch metrics are available (5-minute resolution).
--
-- PHASE 1: Collect basic CloudWatch EC2 metrics (available now)
-- PHASE 2: Deploy node_exporter for system-level metrics (future)
--
-- This section contains SQL templates for the CloudWatch-only EC2 metrics
-- that can be collected immediately without deploying any agents.

-- ============================================================
-- 10.1 EC2 CPUUtilization — Basic CloudWatch (5-minute)
-- EC2 CPU利用率（基础CloudWatch，5分钟间隔）
-- ============================================================
-- RUN AGAINST: CloudWatch API
-- Namespace:   AWS/EC2
-- MetricName:  CPUUtilization
-- Dimensions:  InstanceId = "i-xxxxxxxxxxxxxxxxx"
-- Statistics:  Average
-- Period:      86400 (1 day)
-- Unit:        Percent
--
-- LIMITATION: Only shows hypervisor-level CPU. Does not show:
--   - Per-process CPU usage
--   - System vs user CPU breakdown
--   - I/O wait time
--   - CPU steal time (relevant for burstable instances)

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('EC2', %s, %s, %s,
     'ec2_cpu_utilization', %s, 'percent', 'CLOUDWATCH', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 10.2 EC2 NetworkIn / NetworkOut — Basic CloudWatch
-- EC2网络流入/流出（基础CloudWatch）
-- ============================================================
-- RUN AGAINST: CloudWatch API
-- Namespace:   AWS/EC2
-- MetricName:  NetworkIn / NetworkOut
-- Dimensions:  InstanceId = "i-xxxxxxxxxxxxxxxxx"
-- Statistics:  Sum (total bytes per period)
-- Period:      86400 (1 day)
-- Unit:        Bytes

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('EC2', %s, %s, %s,
     'ec2_network_in_bytes', %s, 'bytes', 'CLOUDWATCH', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('EC2', %s, %s, %s,
     'ec2_network_out_bytes', %s, 'bytes', 'CLOUDWATCH', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 10.3 EC2 StatusCheckFailed — Instance health
-- EC2状态检查失败
-- ============================================================
-- RUN AGAINST: CloudWatch API
-- Namespace:   AWS/EC2
-- MetricName:  StatusCheckFailed
-- Dimensions:  InstanceId = "i-xxxxxxxxxxxxxxxxx"
-- Statistics:  Maximum (any failure in the period)
-- Period:      86400 (1 day)
-- Unit:        Count (0 = healthy, 1 = failed)
--
-- StatusCheckFailed combines both system and instance checks.
-- Any non-zero value should generate an alert.

INSERT INTO test.infra_metric_daily
    (service_type, instance_id, instance_name, metric_date,
     metric_name, metric_value, metric_unit, source, day_of_week, is_weekend)
VALUES
    ('EC2', %s, %s, %s,
     'ec2_status_check_failed', %s, 'count', 'CLOUDWATCH', %s, %s)
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    created_at   = CURRENT_TIMESTAMP;


-- ============================================================
-- 10.4 EC2 Metrics NOT Available Without Agent
-- 无Agent不可用的EC2指标
-- ============================================================
-- The following metrics REQUIRE node_exporter or CloudWatch Agent:
--
-- MEMORY METRICS (not available via basic CloudWatch):
--   node_memory_MemTotal_bytes      — Total system memory
--   node_memory_MemAvailable_bytes  — Available memory
--   node_memory_MemFree_bytes       — Free memory
--   node_memory_Buffers_bytes       — Buffer cache
--   node_memory_Cached_bytes        — Page cache
--   node_memory_SwapTotal_bytes     — Total swap
--   node_memory_SwapFree_bytes      — Available swap
--
-- DISK METRICS (not available via basic CloudWatch):
--   node_filesystem_size_bytes      — Total filesystem size
--   node_filesystem_avail_bytes     — Available filesystem space
--   node_filesystem_files           — Total inodes
--   node_filesystem_files_free      — Available inodes
--
-- SYSTEM METRICS (not available via basic CloudWatch):
--   node_load1 / node_load5 / node_load15  — System load averages
--   node_procs_running               — Running processes
--   node_filefd_allocated             — Open file descriptors
--   node_nf_conntrack_entries         — Connection tracking entries
--
-- DEPLOYMENT PLAN: See 01_discovery_inventory.sql Section 4.3
-- Target: Deploy node_exporter to all ~233 EC2 instances over 8 weeks.


-- ############################################################################
-- SECTION 11: DATA QUALITY CHECKS
-- 数据质量检查
-- ############################################################################
-- Run these queries after CloudWatch data loading to verify completeness.

-- ============================================================
-- 11.1 Row count per metric name (RDS)
-- RDS各指标行数
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
SELECT
    metric_name,
    COUNT(*)                        AS row_count,
    COUNT(DISTINCT instance_id)     AS instance_count,
    MIN(metric_date)                AS earliest_date,
    MAX(metric_date)                AS latest_date
FROM test.infra_metric_daily
WHERE service_type = 'RDS'
GROUP BY metric_name
ORDER BY metric_name;


-- ============================================================
-- 11.2 Check for NULL metric values (RDS)
-- 检查RDS空指标值
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
SELECT
    metric_name,
    COUNT(*)                                                AS total_rows,
    SUM(CASE WHEN metric_value IS NULL THEN 1 ELSE 0 END)  AS null_count,
    ROUND(SUM(CASE WHEN metric_value IS NULL THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                            AS null_pct
FROM test.infra_metric_daily
WHERE service_type = 'RDS'
GROUP BY metric_name
HAVING null_count > 0
ORDER BY null_pct DESC;


-- ============================================================
-- 11.3 Validate metric value ranges (RDS)
-- 验证RDS指标值范围
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
SELECT
    metric_name,
    metric_unit,
    MIN(metric_value)       AS min_value,
    AVG(metric_value)       AS avg_value,
    MAX(metric_value)       AS max_value,
    STDDEV(metric_value)    AS stddev_value,
    -- Sanity checks
    CASE
        WHEN metric_name = 'rds_cpu_utilization' AND MAX(metric_value) > 100
            THEN 'INVALID: CPU > 100%'
        WHEN metric_name = 'rds_swap_usage' AND MIN(metric_value) < 0
            THEN 'INVALID: Negative swap'
        WHEN metric_name = 'rds_read_latency' AND MIN(metric_value) < 0
            THEN 'INVALID: Negative latency'
        ELSE 'OK'
    END AS validation_status
FROM test.infra_metric_daily
WHERE service_type = 'RDS'
  AND metric_value IS NOT NULL
GROUP BY metric_name, metric_unit
ORDER BY metric_name;


-- ============================================================
-- 11.4 Check RDS instance coverage
-- 检查RDS实例覆盖率
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
-- We expect 58 RDS instances for each metric on each day.
SELECT
    metric_date,
    metric_name,
    COUNT(DISTINCT instance_id) AS instance_count,
    CASE
        WHEN COUNT(DISTINCT instance_id) >= 55 THEN 'OK'
        WHEN COUNT(DISTINCT instance_id) >= 50 THEN 'WARNING'
        ELSE 'CRITICAL'
    END AS coverage_status
FROM test.infra_metric_daily
WHERE service_type = 'RDS'
GROUP BY metric_date, metric_name
HAVING instance_count < 55
ORDER BY metric_date DESC, metric_name;


-- ============================================================
-- 11.5 Cross-service summary
-- 跨服务摘要
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
SELECT
    service_type,
    source,
    COUNT(*)                        AS total_rows,
    COUNT(DISTINCT instance_id)     AS unique_instances,
    COUNT(DISTINCT metric_name)     AS unique_metrics,
    COUNT(DISTINCT metric_date)     AS date_range_days,
    MIN(metric_date)                AS earliest_date,
    MAX(metric_date)                AS latest_date
FROM test.infra_metric_daily
GROUP BY service_type, source
ORDER BY service_type, source;


-- ############################################################################
-- SECTION 12: SAMPLE VERIFICATION QUERIES
-- 示例验证查询
-- ############################################################################

-- ============================================================
-- 12.1 Latest RDS metrics for a specific cluster
-- 特定集群的最新RDS指标
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
SELECT
    metric_date,
    metric_name,
    metric_value,
    metric_unit
FROM test.infra_metric_daily
WHERE service_type = 'RDS'
  AND instance_name = 'isales-market'
  AND metric_date = (SELECT MAX(metric_date) FROM test.infra_metric_daily WHERE service_type = 'RDS')
ORDER BY metric_name;


-- ============================================================
-- 12.2 CPU trend for top RDS clusters (last 14 days)
-- 主要RDS集群CPU趋势（最近14天）
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
SELECT
    instance_name,
    metric_date,
    ROUND(metric_value, 2) AS cpu_pct,
    day_of_week,
    is_weekend
FROM test.infra_metric_daily
WHERE service_type = 'RDS'
  AND metric_name = 'rds_cpu_utilization'
  AND instance_name IN ('isales-market', 'web', 'ireplenishment', 'pub-dm')
  AND metric_date >= DATE_SUB(CURDATE(), INTERVAL 14 DAY)
ORDER BY instance_name, metric_date;


-- ============================================================
-- 12.3 Slow query hot spots
-- 慢查询热点
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
SELECT
    instance_name,
    metric_date,
    metric_value AS slow_query_count,
    day_of_week,
    is_weekend
FROM test.infra_metric_daily
WHERE service_type = 'RDS'
  AND metric_name = 'rds_slow_query_count'
  AND metric_value > 0
ORDER BY metric_value DESC
LIMIT 20;


-- ============================================================
-- 12.4 RDS instances with high connection counts
-- 高连接数RDS实例
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
SELECT
    instance_name,
    metric_date,
    metric_value AS connections
FROM test.infra_metric_daily
WHERE service_type = 'RDS'
  AND metric_name = 'rds_database_connections'
  AND metric_date = (SELECT MAX(metric_date) FROM test.infra_metric_daily WHERE service_type = 'RDS')
ORDER BY metric_value DESC
LIMIT 20;


-- ============================================================
-- 12.5 Combined fleet metrics summary
-- 综合集群指标摘要
-- ============================================================
-- RUN AGAINST: MySQL (dbatest)
SELECT
    service_type,
    COUNT(DISTINCT instance_id)     AS instances,
    COUNT(DISTINCT metric_name)     AS metrics,
    COUNT(*)                        AS total_data_points,
    MIN(metric_date)                AS data_from,
    MAX(metric_date)                AS data_to
FROM test.infra_metric_daily
GROUP BY service_type
ORDER BY service_type;


-- ============================================================
-- PIPELINE COMPLETION STATUS
-- 管道完成状态
-- ============================================================
-- After both 03 (Redis) and 04 (CloudWatch) extraction scripts have
-- run successfully, the data pipeline status should show:
--
-- ┌──────────────┬────────┬──────────┬────────────────────┐
-- │ Service      │ Source │ Metrics  │ Daily Rows         │
-- ├──────────────┼────────┼──────────┼────────────────────┤
-- │ REDIS        │ PROM   │ 15-18   │ ~75 × 18 = ~1,350 │
-- │ RDS          │ CW     │ 13-15   │ ~58 × 15 = ~870   │
-- │ EC2 (basic)  │ CW     │ 4       │ ~233 × 4 = ~932   │
-- ├──────────────┼────────┼──────────┼────────────────────┤
-- │ TOTAL        │ Mixed  │ ~37     │ ~3,152 rows/day    │
-- └──────────────┴────────┴──────────┴────────────────────┘
--
-- Annual projection: ~3,152 × 365 = ~1.15M rows/year
-- This is well within MySQL capabilities for analytical queries.
--
-- NEXT STEPS:
--   1. Build SPC anomaly detection engine (05_compute_anomaly_scores.sql)
--   2. Build health scoring engine (06_compute_health_scores.sql)
--   3. Build alert generation logic (07_generate_alerts.sql)
--   4. Create Grafana dashboards for visualization
--   5. Deploy Python orchestrator for automated daily execution
-- ============================================================
-- END OF FILE: 04_extract_cloudwatch_metrics.sql
-- ============================================================

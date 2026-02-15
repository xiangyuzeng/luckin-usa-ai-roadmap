-- ============================================================
-- UC-IT-01: Predictive Infrastructure Monitoring
-- 预测性基础设施监控
-- File: 02_create_monitoring_schema.sql
-- Source: N/A (DDL only)
-- Target: dbatest (test schema)
-- Purpose: Create 6 analytics tables and 3 views for
--          infrastructure monitoring and SPC anomaly detection.
--          All objects use IF NOT EXISTS for safe re-execution.
-- 中文描述: 在dbatest服务器的test模式下创建6个分析表和3个视图，
--          用于基础设施监控和SPC异常检测。
--          所有对象使用IF NOT EXISTS确保可安全重复执行。
-- Author: Data Engineering / BI Team
-- Created: 2026-02-15
-- ============================================================
--
-- TABLES:
--   1. test.infra_metric_daily         — Core metrics fact table / 核心指标事实表
--   2. test.infra_anomaly_scores       — SPC computations / SPC统计过程控制计算
--   3. test.infra_health_scores        — Fleet health scores / 集群健康评分
--   4. test.infra_anomaly_alerts       — Alert records / 异常预警记录
--   5. test.infra_fleet_inventory      — Infrastructure registry / 基础设施注册表
--   6. test.infra_monitoring_pipeline_log — Execution log / 管道执行日志
--
-- VIEWS:
--   1. test.v_infra_fleet_summary      — Instance counts by service/status
--   2. test.v_infra_latest_health      — Latest health scores per instance
--   3. test.v_active_anomaly_alerts    — Unacknowledged alerts by severity
--
-- USAGE:
--   Execute this script once against the dbatest server to initialize.
--   Re-running is safe — all statements use IF NOT EXISTS.
--
--   mysql -h aws-luckyus-dbatest-rw -u <user> -p < 02_create_monitoring_schema.sql
--
-- DEPENDENCIES:
--   - 01_discovery_inventory.sql (reference only, not required for execution)
-- ============================================================

USE test;


-- ############################################################################
-- TABLE 1: infra_metric_daily
-- 核心指标事实表 / Core daily infrastructure metrics fact table
-- ############################################################################
-- One row per (service_type, instance_id, metric_date, metric_name).
-- Stores daily aggregated metrics from Prometheus, CloudWatch, and other sources.
-- This is the foundation table that feeds the SPC anomaly detection engine.
--
-- Expected volume: ~76 Redis × 15 metrics × 365 days = ~416K rows/year (Redis only)
--                  ~58 RDS × 20 metrics × 365 days   = ~423K rows/year (RDS)
--                  Total first year estimate: ~1M rows
-- ============================================================

CREATE TABLE IF NOT EXISTS test.infra_metric_daily (
    id              BIGINT          AUTO_INCREMENT PRIMARY KEY
                                    COMMENT 'Auto-increment primary key / 自增主键',
    service_type    VARCHAR(20)     NOT NULL
                                    COMMENT 'Service category: REDIS/RDS/EC2/EKS/MSK/DOCDB/OPENSEARCH/EMR',
    instance_id     VARCHAR(200)    NOT NULL
                                    COMMENT 'Unique instance identifier (e.g., Redis addr, RDS DBInstanceId)',
    instance_name   VARCHAR(100)    DEFAULT NULL
                                    COMMENT 'Human-readable name / 实例名称 (e.g., isales-market)',
    metric_date     DATE            NOT NULL
                                    COMMENT 'Metric observation date / 指标观测日期',
    metric_name     VARCHAR(80)     NOT NULL
                                    COMMENT 'Metric name (e.g., memory_used_bytes, cpu_utilization)',
    metric_value    DOUBLE          DEFAULT NULL
                                    COMMENT 'Metric value (daily average or aggregate) / 指标值',
    metric_unit     VARCHAR(30)     DEFAULT NULL
                                    COMMENT 'Unit: bytes, percent, count, seconds, ops_per_sec / 单位',
    source          VARCHAR(30)     NOT NULL DEFAULT 'PROMETHEUS'
                                    COMMENT 'Data source: PROMETHEUS/CLOUDWATCH/EXPORTER/MCP_DB',
    day_of_week     TINYINT         DEFAULT NULL
                                    COMMENT 'Day of week: 1=Mon..7=Sun / 星期几',
    is_weekend      BOOLEAN         DEFAULT FALSE
                                    COMMENT 'Weekend flag for seasonality / 周末标记',
    created_at      DATETIME        DEFAULT CURRENT_TIMESTAMP
                                    COMMENT 'Row creation timestamp / 行创建时间',

    -- Uniqueness: one metric value per service+instance+date+metric
    UNIQUE KEY uq_metric (service_type, instance_id, metric_date, metric_name),

    -- Query optimization indexes
    INDEX idx_date (metric_date),
    INDEX idx_service (service_type),
    INDEX idx_instance (instance_id),
    INDEX idx_metric_name (metric_name),
    INDEX idx_service_date (service_type, metric_date)

) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='UC-IT-01: Daily infrastructure metrics / 每日基础设施指标';


-- ############################################################################
-- TABLE 2: infra_anomaly_scores
-- SPC统计过程控制计算 / Statistical Process Control anomaly scores
-- ############################################################################
-- Stores rolling window statistics and Western Electric rule evaluations
-- for each metric time series. This table is populated by the SPC engine
-- after infra_metric_daily has been loaded.
--
-- Western Electric Rules:
--   Rule 1: Single point > 3σ from mean (Nelson Rule 1)
--   Rule 2: 2 of 3 consecutive points > 2σ on same side
--   Rule 3: 4 of 5 consecutive points > 1σ on same side
--   Rule 4: 8 consecutive points on same side of mean
--   Rule 5: 6 consecutive points trending in same direction
--
-- Severity mapping:
--   NONE     = No rules triggered
--   INFO     = Rule 4 or 5 only (trend/shift detection)
--   WARNING  = Rule 2 or 3 triggered
--   CRITICAL = Rule 1 triggered (single point beyond 3σ)
--   EMERGENCY = Rule 1 + rate_of_change anomaly (rapid degradation)
-- ============================================================

CREATE TABLE IF NOT EXISTS test.infra_anomaly_scores (
    id                  BIGINT          AUTO_INCREMENT PRIMARY KEY
                                        COMMENT 'Auto-increment primary key / 自增主键',
    service_type        VARCHAR(20)     NOT NULL
                                        COMMENT 'Service category: REDIS/RDS/EC2/EKS/MSK/DOCDB/OPENSEARCH/EMR',
    instance_id         VARCHAR(200)    NOT NULL
                                        COMMENT 'Unique instance identifier / 唯一实例标识符',
    metric_date         DATE            NOT NULL
                                        COMMENT 'Metric observation date / 指标观测日期',
    metric_name         VARCHAR(80)     NOT NULL
                                        COMMENT 'Metric name / 指标名称',
    metric_value        DOUBLE          DEFAULT NULL
                                        COMMENT 'Raw metric value for this date / 原始指标值',

    -- Rolling window statistics (14-day window)
    rolling_mean_14d    DOUBLE          DEFAULT NULL
                                        COMMENT '14-day rolling mean / 14天滚动均值',
    rolling_std_14d     DOUBLE          DEFAULT NULL
                                        COMMENT '14-day rolling standard deviation / 14天滚动标准差',
    z_score             DOUBLE          DEFAULT NULL
                                        COMMENT 'Z-score: (value - mean) / std / Z分数',

    -- Control limits
    ucl_2sigma          DOUBLE          DEFAULT NULL
                                        COMMENT 'Upper control limit at 2σ / 2σ上控制线',
    ucl_3sigma          DOUBLE          DEFAULT NULL
                                        COMMENT 'Upper control limit at 3σ / 3σ上控制线',
    lcl_2sigma          DOUBLE          DEFAULT NULL
                                        COMMENT 'Lower control limit at 2σ / 2σ下控制线',
    lcl_3sigma          DOUBLE          DEFAULT NULL
                                        COMMENT 'Lower control limit at 3σ / 3σ下控制线',

    -- Rate of change
    rate_of_change_1d   DOUBLE          DEFAULT NULL
                                        COMMENT 'Day-over-day rate of change (%) / 日环比变化率(%)',
    rate_of_change_7d   DOUBLE          DEFAULT NULL
                                        COMMENT 'Week-over-week rate of change (%) / 周环比变化率(%)',

    -- Western Electric Rules (TRUE = rule violated)
    we_rule1            BOOLEAN         DEFAULT FALSE
                                        COMMENT 'WE Rule 1: Single point > 3σ / 单点超3σ',
    we_rule2            BOOLEAN         DEFAULT FALSE
                                        COMMENT 'WE Rule 2: 2 of 3 points > 2σ same side / 3点中2点超2σ',
    we_rule3            BOOLEAN         DEFAULT FALSE
                                        COMMENT 'WE Rule 3: 4 of 5 points > 1σ same side / 5点中4点超1σ',
    we_rule4            BOOLEAN         DEFAULT FALSE
                                        COMMENT 'WE Rule 4: 8 consecutive same side / 连续8点同侧',
    we_rule5            BOOLEAN         DEFAULT FALSE
                                        COMMENT 'WE Rule 5: 6 consecutive trending / 连续6点趋势',

    -- Composite anomaly severity
    anomaly_severity    ENUM('NONE','INFO','WARNING','CRITICAL','EMERGENCY')
                        DEFAULT 'NONE'
                        COMMENT 'Anomaly severity level / 异常严重等级',

    created_at          DATETIME        DEFAULT CURRENT_TIMESTAMP
                                        COMMENT 'Row creation timestamp / 行创建时间',

    -- Uniqueness: one score per service+instance+date+metric
    UNIQUE KEY uq_anomaly (service_type, instance_id, metric_date, metric_name),

    INDEX idx_date (metric_date),
    INDEX idx_severity (anomaly_severity),
    INDEX idx_service_date (service_type, metric_date),
    INDEX idx_instance_date (instance_id, metric_date),
    INDEX idx_zscore (z_score)

) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='UC-IT-01: SPC anomaly scores / SPC异常评分';


-- ############################################################################
-- TABLE 3: infra_health_scores
-- 集群健康评分 / Fleet health scores per instance per day
-- ############################################################################
-- Composite health score combining multiple metric dimensions into a single
-- grade (A-F) for each instance on each day. This powers the fleet-level
-- health dashboard and trend reporting.
--
-- Scoring methodology:
--   Each dimension scored 0-100 based on metric values vs. thresholds.
--   composite_score = weighted average of all dimension scores.
--   health_grade: A (>=90), B (>=80), C (>=70), D (>=60), F (<60)
-- ============================================================

CREATE TABLE IF NOT EXISTS test.infra_health_scores (
    id                      BIGINT          AUTO_INCREMENT PRIMARY KEY
                                            COMMENT 'Auto-increment primary key / 自增主键',
    service_type            VARCHAR(20)     NOT NULL
                                            COMMENT 'Service category / 服务类型',
    instance_id             VARCHAR(200)    NOT NULL
                                            COMMENT 'Unique instance identifier / 唯一实例标识符',
    instance_name           VARCHAR(100)    DEFAULT NULL
                                            COMMENT 'Human-readable name / 实例名称',
    metric_date             DATE            NOT NULL
                                            COMMENT 'Score date / 评分日期',

    -- Dimension scores (0-100 scale)
    availability_score      DECIMAL(5,1)    DEFAULT NULL
                                            COMMENT 'Availability dimension (0-100) / 可用性评分',
    performance_score       DECIMAL(5,1)    DEFAULT NULL
                                            COMMENT 'Performance dimension (0-100) / 性能评分',
    capacity_score          DECIMAL(5,1)    DEFAULT NULL
                                            COMMENT 'Capacity/utilization dimension (0-100) / 容量评分',
    error_rate_score        DECIMAL(5,1)    DEFAULT NULL
                                            COMMENT 'Error rate dimension (0-100) / 错误率评分',
    latency_score           DECIMAL(5,1)    DEFAULT NULL
                                            COMMENT 'Latency dimension (0-100) / 延迟评分',

    -- Composite
    composite_score         DECIMAL(5,1)    DEFAULT NULL
                                            COMMENT 'Weighted composite score (0-100) / 综合加权评分',
    health_grade            CHAR(1)         DEFAULT NULL
                                            COMMENT 'Letter grade: A/B/C/D/F / 等级: A/B/C/D/F',
    trend_direction         VARCHAR(10)     DEFAULT NULL
                                            COMMENT 'IMPROVING/STABLE/DEGRADING / 趋势方向',
    week_over_week_change   DECIMAL(5,2)    DEFAULT NULL
                                            COMMENT 'WoW composite score change (%) / 周环比变化(%)',

    created_at              DATETIME        DEFAULT CURRENT_TIMESTAMP
                                            COMMENT 'Row creation timestamp / 行创建时间',

    -- Uniqueness
    UNIQUE KEY uq_health (service_type, instance_id, metric_date),

    INDEX idx_date (metric_date),
    INDEX idx_grade (health_grade),
    INDEX idx_composite (composite_score),
    INDEX idx_service_date (service_type, metric_date),
    INDEX idx_trend (trend_direction)

) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='UC-IT-01: Infrastructure health scores / 基础设施健康评分';


-- ############################################################################
-- TABLE 4: infra_anomaly_alerts
-- 异常预警记录 / Alert records generated by the SPC engine
-- ############################################################################
-- Each row represents a generated alert when anomaly conditions are detected.
-- Alerts are created by the Python orchestrator when SPC rules are triggered.
-- Supports bilingual descriptions (English + Chinese) for international teams.
-- ============================================================

CREATE TABLE IF NOT EXISTS test.infra_anomaly_alerts (
    id                          BIGINT          AUTO_INCREMENT PRIMARY KEY
                                                COMMENT 'Auto-increment primary key / 自增主键',
    service_type                VARCHAR(20)     NOT NULL
                                                COMMENT 'Service category / 服务类型',
    instance_id                 VARCHAR(200)    NOT NULL
                                                COMMENT 'Unique instance identifier / 唯一实例标识符',
    alert_date                  DATE            NOT NULL
                                                COMMENT 'Date the alert was generated / 预警生成日期',
    alert_type                  VARCHAR(30)     NOT NULL
                                                COMMENT 'Alert type: SPC_RULE1/SPC_RULE2/.../CAPACITY/TREND',
    severity                    ENUM('INFO','WARNING','CRITICAL','EMERGENCY')
                                NOT NULL DEFAULT 'WARNING'
                                COMMENT 'Alert severity level / 预警严重等级',

    -- Metric context
    metric_name                 VARCHAR(80)     NOT NULL
                                                COMMENT 'Metric that triggered the alert / 触发指标',
    current_value               DOUBLE          DEFAULT NULL
                                                COMMENT 'Current metric value / 当前指标值',
    threshold_value             DOUBLE          DEFAULT NULL
                                                COMMENT 'Threshold that was breached / 触发阈值',
    z_score                     DOUBLE          DEFAULT NULL
                                                COMMENT 'Z-score at time of alert / 触发时Z分数',
    consecutive_anomaly_days    INT             DEFAULT 0
                                                COMMENT 'Days of continuous anomaly / 连续异常天数',
    predicted_breach_hours      INT             DEFAULT NULL
                                                COMMENT 'Predicted hours until critical breach / 预测突破时间(小时)',

    -- Bilingual descriptions
    description_en              TEXT            DEFAULT NULL
                                                COMMENT 'English alert description / 英文描述',
    description_cn              TEXT            DEFAULT NULL
                                                COMMENT 'Chinese alert description / 中文描述',
    recommended_action          TEXT            DEFAULT NULL
                                                COMMENT 'Recommended remediation action / 建议修复操作',

    -- Acknowledgement workflow
    acknowledged                BOOLEAN         DEFAULT FALSE
                                                COMMENT 'Whether alert has been acknowledged / 是否已确认',
    acknowledged_by             VARCHAR(50)     DEFAULT NULL
                                                COMMENT 'Who acknowledged the alert / 确认人',
    acknowledged_at             DATETIME        DEFAULT NULL
                                                COMMENT 'When alert was acknowledged / 确认时间',

    created_at                  DATETIME        DEFAULT CURRENT_TIMESTAMP
                                                COMMENT 'Row creation timestamp / 行创建时间',

    INDEX idx_date (alert_date),
    INDEX idx_severity (severity),
    INDEX idx_service (service_type),
    INDEX idx_instance (instance_id),
    INDEX idx_ack (acknowledged),
    INDEX idx_type (alert_type),
    INDEX idx_severity_date (severity, alert_date)

) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='UC-IT-01: Infrastructure anomaly alerts / 基础设施异常预警';


-- ############################################################################
-- TABLE 5: infra_fleet_inventory
-- 基础设施注册表 / Infrastructure fleet registry
-- ############################################################################
-- Master registry of all discovered infrastructure instances. Updated
-- by the discovery pipeline and maintained as the source of truth for
-- what should be monitored.
-- ============================================================

CREATE TABLE IF NOT EXISTS test.infra_fleet_inventory (
    id                  BIGINT          AUTO_INCREMENT PRIMARY KEY
                                        COMMENT 'Auto-increment primary key / 自增主键',
    service_type        VARCHAR(20)     NOT NULL
                                        COMMENT 'Service category: REDIS/RDS/EC2/EKS/MSK/DOCDB/OPENSEARCH/EMR',
    instance_id         VARCHAR(200)    NOT NULL
                                        COMMENT 'Unique instance identifier / 唯一实例标识符',
    instance_name       VARCHAR(100)    DEFAULT NULL
                                        COMMENT 'Human-readable name / 实例名称',
    region              VARCHAR(20)     DEFAULT 'us-east-1'
                                        COMMENT 'AWS region / AWS区域',
    availability_zone   VARCHAR(20)     DEFAULT NULL
                                        COMMENT 'Availability zone (e.g., us-east-1a) / 可用区',
    instance_class      VARCHAR(50)     DEFAULT NULL
                                        COMMENT 'Instance class/type (e.g., cache.r6g.large, db.r5.xlarge)',
    engine_version      VARCHAR(30)     DEFAULT NULL
                                        COMMENT 'Engine version (e.g., Redis 7.0, Aurora MySQL 3.04)',
    monitoring_source   VARCHAR(30)     DEFAULT NULL
                                        COMMENT 'Primary monitoring source: PROMETHEUS/CLOUDWATCH/BOTH/NONE',
    scrape_interval_sec INT             DEFAULT NULL
                                        COMMENT 'Prometheus scrape interval in seconds (e.g., 15, 30, 60)',
    first_seen_date     DATE            DEFAULT NULL
                                        COMMENT 'Date instance was first discovered / 首次发现日期',
    last_seen_date      DATE            DEFAULT NULL
                                        COMMENT 'Date instance was last seen active / 最后活跃日期',
    status              VARCHAR(20)     DEFAULT 'ACTIVE'
                                        COMMENT 'Instance status: ACTIVE/INACTIVE/DECOMMISSIONED/ERROR',
    tags                JSON            DEFAULT NULL
                                        COMMENT 'Additional metadata as JSON / JSON格式附加元数据',
    created_at          DATETIME        DEFAULT CURRENT_TIMESTAMP
                                        COMMENT 'Row creation timestamp / 行创建时间',
    updated_at          DATETIME        DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
                                        COMMENT 'Last update timestamp / 最后更新时间',

    -- Uniqueness: one entry per service+instance
    UNIQUE KEY uq_inventory (service_type, instance_id),

    INDEX idx_service (service_type),
    INDEX idx_status (status),
    INDEX idx_region (region),
    INDEX idx_source (monitoring_source),
    INDEX idx_last_seen (last_seen_date)

) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='UC-IT-01: Infrastructure fleet inventory / 基础设施集群清单';


-- ############################################################################
-- TABLE 6: infra_monitoring_pipeline_log
-- 管道执行日志 / Pipeline execution tracking
-- ############################################################################
-- Tracks every step of the monitoring pipeline execution. Same pattern
-- used in UC-SC-01 (store_anomaly_pipeline_log) and UC-OP-02
-- (store_anomaly_pipeline_log) for consistency across all use cases.
-- ============================================================

CREATE TABLE IF NOT EXISTS test.infra_monitoring_pipeline_log (
    id                  BIGINT          AUTO_INCREMENT PRIMARY KEY
                                        COMMENT 'Auto-increment primary key / 自增主键',
    run_id              VARCHAR(50)     NOT NULL
                                        COMMENT 'Unique pipeline run identifier (UUID) / 管道运行唯一标识',
    step_num            INT             NOT NULL
                                        COMMENT 'Step sequence number / 步骤序号',
    step_name           VARCHAR(80)     NOT NULL
                                        COMMENT 'Step name / 步骤名称',
    description         TEXT            DEFAULT NULL
                                        COMMENT 'Step description / 步骤描述',
    status              ENUM('RUNNING','SUCCESS','FAILED','SKIPPED')
                        NOT NULL DEFAULT 'RUNNING'
                        COMMENT 'Execution status / 执行状态',
    rows_affected       INT             DEFAULT 0
                                        COMMENT 'Number of rows affected / 影响行数',
    duration_seconds    DECIMAL(8,2)    DEFAULT NULL
                                        COMMENT 'Step duration in seconds / 步骤执行时长(秒)',
    error_message       TEXT            DEFAULT NULL
                                        COMMENT 'Error details if failed / 失败错误详情',
    server_source       VARCHAR(30)     DEFAULT NULL
                                        COMMENT 'Source server: PROMETHEUS/CLOUDWATCH/DBATEST',
    created_at          DATETIME        DEFAULT CURRENT_TIMESTAMP
                                        COMMENT 'Row creation timestamp / 行创建时间',

    INDEX idx_run (run_id),
    INDEX idx_status (status),
    INDEX idx_step (step_name),
    INDEX idx_created (created_at)

) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='UC-IT-01: Pipeline execution log / 管道执行日志';


-- ############################################################################
-- VIEW 1: v_infra_fleet_summary
-- 集群摘要视图 / Fleet summary by service type and status
-- ############################################################################
-- Provides a quick overview of instance counts grouped by service type
-- and current status. Used by the fleet dashboard.
-- ============================================================

CREATE OR REPLACE VIEW test.v_infra_fleet_summary AS
SELECT
    fi.service_type,
    fi.status,
    COUNT(*)                                        AS instance_count,
    SUM(CASE WHEN fi.monitoring_source IN ('PROMETHEUS','BOTH')
             THEN 1 ELSE 0 END)                    AS prometheus_monitored,
    SUM(CASE WHEN fi.monitoring_source IN ('CLOUDWATCH','BOTH')
             THEN 1 ELSE 0 END)                    AS cloudwatch_monitored,
    SUM(CASE WHEN fi.monitoring_source = 'NONE' OR fi.monitoring_source IS NULL
             THEN 1 ELSE 0 END)                    AS unmonitored,
    ROUND(
        SUM(CASE WHEN fi.monitoring_source IS NOT NULL
                  AND fi.monitoring_source != 'NONE'
                 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1
    )                                               AS coverage_pct,
    MIN(fi.first_seen_date)                         AS earliest_discovered,
    MAX(fi.last_seen_date)                          AS latest_seen
FROM test.infra_fleet_inventory fi
GROUP BY fi.service_type, fi.status
ORDER BY fi.service_type, fi.status;


-- ############################################################################
-- VIEW 2: v_infra_latest_health
-- 最新健康评分视图 / Latest health scores per instance
-- ############################################################################
-- Returns the most recent health score for each instance. Uses a subquery
-- to find the max date per instance, then joins back to get full row.
-- ============================================================

CREATE OR REPLACE VIEW test.v_infra_latest_health AS
SELECT
    hs.service_type,
    hs.instance_id,
    hs.instance_name,
    hs.metric_date,
    hs.availability_score,
    hs.performance_score,
    hs.capacity_score,
    hs.error_rate_score,
    hs.latency_score,
    hs.composite_score,
    hs.health_grade,
    hs.trend_direction,
    hs.week_over_week_change
FROM test.infra_health_scores hs
INNER JOIN (
    SELECT
        service_type,
        instance_id,
        MAX(metric_date) AS max_date
    FROM test.infra_health_scores
    GROUP BY service_type, instance_id
) latest
    ON  hs.service_type = latest.service_type
    AND hs.instance_id  = latest.instance_id
    AND hs.metric_date  = latest.max_date
ORDER BY hs.composite_score ASC;    -- worst health first


-- ############################################################################
-- VIEW 3: v_active_anomaly_alerts
-- 活跃异常预警视图 / Unacknowledged alerts ordered by severity
-- ############################################################################
-- Returns all alerts that have not been acknowledged, ordered by severity
-- (EMERGENCY first) and then by alert date (most recent first).
-- This powers the "active alerts" panel in Grafana dashboards.
-- ============================================================

CREATE OR REPLACE VIEW test.v_active_anomaly_alerts AS
SELECT
    aa.id                       AS alert_id,
    aa.service_type,
    aa.instance_id,
    aa.alert_date,
    aa.alert_type,
    aa.severity,
    aa.metric_name,
    aa.current_value,
    aa.threshold_value,
    aa.z_score,
    aa.consecutive_anomaly_days,
    aa.predicted_breach_hours,
    aa.description_en,
    aa.description_cn,
    aa.recommended_action,
    aa.created_at,
    -- Severity sort order for dashboard display
    CASE aa.severity
        WHEN 'EMERGENCY' THEN 1
        WHEN 'CRITICAL'  THEN 2
        WHEN 'WARNING'   THEN 3
        WHEN 'INFO'      THEN 4
    END                         AS severity_order
FROM test.infra_anomaly_alerts aa
WHERE aa.acknowledged = FALSE
ORDER BY severity_order ASC, aa.alert_date DESC;


-- ############################################################################
-- VERIFICATION QUERIES
-- 验证查询
-- ############################################################################
-- Run these after creating the schema to verify everything was created.

-- Check all tables exist
SELECT
    TABLE_NAME,
    TABLE_ROWS,
    TABLE_COMMENT
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'test'
  AND TABLE_NAME LIKE 'infra_%'
ORDER BY TABLE_NAME;

-- Check all views exist
SELECT
    TABLE_NAME,
    VIEW_DEFINITION
FROM information_schema.VIEWS
WHERE TABLE_SCHEMA = 'test'
  AND TABLE_NAME LIKE 'v_infra_%'
ORDER BY TABLE_NAME;

-- Check column counts per table
SELECT
    TABLE_NAME,
    COUNT(*) AS column_count
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = 'test'
  AND TABLE_NAME LIKE 'infra_%'
GROUP BY TABLE_NAME
ORDER BY TABLE_NAME;

-- Check index counts per table
SELECT
    TABLE_NAME,
    COUNT(DISTINCT INDEX_NAME) AS index_count
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'test'
  AND TABLE_NAME LIKE 'infra_%'
GROUP BY TABLE_NAME
ORDER BY TABLE_NAME;


-- ============================================================
-- SCHEMA SUMMARY
-- 模式摘要
-- ============================================================
-- Tables created: 6
--   1. infra_metric_daily          (12 columns, 6 indexes)
--   2. infra_anomaly_scores        (23 columns, 6 indexes)
--   3. infra_health_scores         (15 columns, 6 indexes)
--   4. infra_anomaly_alerts        (19 columns, 7 indexes)
--   5. infra_fleet_inventory       (16 columns, 6 indexes)
--   6. infra_monitoring_pipeline_log (11 columns, 4 indexes)
--
-- Views created: 3
--   1. v_infra_fleet_summary       — fleet overview
--   2. v_infra_latest_health       — latest health per instance
--   3. v_active_anomaly_alerts     — unacknowledged alerts
--
-- NEXT STEP: Execute 03_extract_redis_metrics.sql to begin data loading.
-- ============================================================
-- END OF FILE: 02_create_monitoring_schema.sql
-- ============================================================

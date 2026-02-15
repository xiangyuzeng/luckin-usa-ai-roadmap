-- ============================================================================
-- UC-SC-01 Forecast Accuracy Monitor
-- 02_create_analytics_schema.sql - Analytics Table DDL
-- ============================================================================
-- Purpose:  Create the analytics tables for forecast accuracy monitoring.
--           These tables store computed metrics derived from the source tables
--           documented in 01_schema_discovery.sql.
--
-- Target:   aws-luckyus-dbatest-rw  ->  schema: test
--
-- Tables:
--   1. test.forecast_accuracy_daily   - Row-level prediction vs actual comparison
--   2. test.forecast_accuracy_summary - Aggregated accuracy metrics by dimension
--   3. test.forecast_alerts           - Threshold-based alert records
--   4. test.forecast_pipeline_run_log - ETL pipeline execution tracking
--
-- Usage:    Execute this script once to initialize the schema.
--           Re-running is safe (uses IF NOT EXISTS).
--
-- Author:   Data Engineering / BI Team
-- Created:  2026-02-15
-- ============================================================================


-- ============================================================================
-- TABLE 1: forecast_accuracy_daily
-- 每日预测准确性明细表 / Daily prediction-vs-actual comparison
-- ============================================================================
-- One row per (date, store, SKU) recording the predicted values from the
-- replenishment algorithm against the actual consumption derived from
-- stock change records (reason_code IN ('025','1001','1002') AND total_adjust_num < 0).
-- This is the foundational fact table from which all summary metrics
-- and alerts are computed.
-- ============================================================================

CREATE TABLE IF NOT EXISTS test.forecast_accuracy_daily (
    id                  BIGINT          NOT NULL AUTO_INCREMENT PRIMARY KEY,

    -- Dimensional keys / 维度键
    accuracy_date       DATE            NOT NULL    COMMENT '比较日期 / Comparison date',
    shop_dept_id        BIGINT          NOT NULL    COMMENT '门店ID / Store ID (FK to t_shop_info)',
    shop_name           VARCHAR(100)                COMMENT '门店名称 / Store name (denormalized)',
    goods_code          VARCHAR(32)     NOT NULL    COMMENT '货物编号(GS code) / Goods code',
    goods_name          VARCHAR(200)                COMMENT '货物名称 / Goods name (denormalized)',
    large_class_name    VARCHAR(100)                COMMENT '大类名称 / Product large category name',

    -- Prediction values / 预测值
    predicted_demand    DECIMAL(12,2)               COMMENT '预测需求(vlt_avg_demand) / Predicted demand from algorithm',
    predicted_order_qty DECIMAL(12,2)               COMMENT '预测订货量(order_num) / Predicted order quantity',

    -- Actual values / 实际值
    actual_consumption  DECIMAL(12,2)               COMMENT '实际消耗量 / Actual consumption (SUM ABS(total_adjust_num) WHERE reason_code IN 025+1001+1002 AND total_adjust_num < 0)',

    -- Error metrics / 误差指标
    absolute_error      DECIMAL(12,2)               COMMENT '绝对误差 / ABS(predicted - actual)',
    absolute_pct_error  DECIMAL(10,4)               COMMENT '绝对百分比误差(APE) / ABS(predicted - actual) / actual',
    forecast_error      DECIMAL(12,2)               COMMENT '预测误差(正=过预测) / predicted - actual (positive = over-forecast)',
    bias_pct            DECIMAL(10,4)               COMMENT '偏差百分比 / (predicted - actual) / actual',
    squared_error       DECIMAL(20,4)               COMMENT '平方误差 / (predicted - actual)^2',

    -- Lineage / 数据溯源
    prediction_dt       VARCHAR(32)                 COMMENT '预测生成日期(dt partition) / Prediction generation date',
    task_version_id     BIGINT                      COMMENT '任务版本 / Algorithm task version ID',

    -- Metadata / 元数据
    computed_at         DATETIME        DEFAULT CURRENT_TIMESTAMP
                                                    COMMENT '计算时间 / Row computation timestamp',

    -- Indexes / 索引
    INDEX idx_date_shop   (accuracy_date, shop_dept_id),
    INDEX idx_date_goods  (accuracy_date, goods_code),
    INDEX idx_shop_goods  (shop_dept_id, goods_code),
    INDEX idx_date        (accuracy_date)

) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='UC-SC-01: 每日预测准确性明细 / Daily forecast accuracy detail (prediction vs consumption)';


-- ============================================================================
-- TABLE 2: forecast_accuracy_summary
-- 预测准确性汇总表 / Aggregated accuracy metrics by period and dimension
-- ============================================================================
-- Pre-computed summary statistics aggregated across various time periods
-- (daily, weekly, monthly, rolling windows) and dimensional cuts
-- (overall, by store, by product, by category, by day-of-week).
-- Powers the monitoring dashboard with sub-second query performance.
-- ============================================================================

CREATE TABLE IF NOT EXISTS test.forecast_accuracy_summary (
    id                  BIGINT          NOT NULL AUTO_INCREMENT PRIMARY KEY,

    -- Period / 时间段
    period_type         ENUM('DAILY','WEEKLY','MONTHLY','ROLLING_7D','ROLLING_30D')
                                        NOT NULL    COMMENT '汇总周期类型 / Aggregation period type',
    period_start        DATE                        COMMENT '周期开始日期 / Period start date (inclusive)',
    period_end          DATE                        COMMENT '周期结束日期 / Period end date (inclusive)',

    -- Dimension / 维度
    dimension_type      ENUM('OVERALL','STORE','PRODUCT','CATEGORY','DOW')
                                        NOT NULL    COMMENT '维度类型 / Dimension type for grouping',
    dimension_value     VARCHAR(100)                COMMENT '维度值 / Dimension value (store_id, goods_code, category, etc.)',
    dimension_name      VARCHAR(200)                COMMENT '维度名称 / Dimension display name (store name, product name, etc.)',

    -- Core accuracy metrics / 核心准确性指标
    mape                DECIMAL(10,4)               COMMENT 'Mean Absolute Percentage Error / 平均绝对百分比误差',
    wmape               DECIMAL(10,4)               COMMENT 'Weighted MAPE / 加权MAPE (weighted by actual volume)',
    rmse                DECIMAL(12,4)               COMMENT 'Root Mean Squared Error / 均方根误差',
    mfe                 DECIMAL(12,4)               COMMENT 'Mean Forecast Error (Bias) / 平均预测误差(偏差)',

    -- Operational metrics / 运营指标
    accuracy_rate_20    DECIMAL(10,4)               COMMENT '% predictions within 20% of actual / 20%容差内命中率',
    tracking_signal     DECIMAL(10,4)               COMMENT 'Cumulative bias / MAD / 跟踪信号(累积偏差/MAD)',

    -- Volume & coverage / 量级和覆盖率
    prediction_count    INT                         COMMENT '预测记录数 / Number of prediction records in period',
    coverage_pct        DECIMAL(10,4)               COMMENT '覆盖率 / % of store-SKU combos with both prediction and actual',
    avg_actual          DECIMAL(12,2)               COMMENT '平均实际消耗 / Average actual consumption in period',

    -- Metadata / 元数据
    computed_at         DATETIME        DEFAULT CURRENT_TIMESTAMP
                                                    COMMENT '计算时间 / Row computation timestamp',

    -- Indexes / 索引
    INDEX idx_period    (period_type, period_start),
    INDEX idx_dimension (dimension_type, dimension_value)

) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='UC-SC-01: 预测准确性汇总指标 / Aggregated forecast accuracy metrics by period & dimension';


-- ============================================================================
-- TABLE 3: forecast_alerts
-- 预测预警表 / Threshold-based alerting for forecast quality issues
-- ============================================================================
-- Stores alerts generated when forecast accuracy metrics breach configured
-- thresholds. Supports acknowledgement workflow for operations team.
-- Alert types:
--   CRITICAL  - Accuracy below critical threshold (e.g., MAPE > 100%)
--   WARNING   - Accuracy below warning threshold (e.g., MAPE > 50%)
--   BIAS      - Systematic over/under-prediction detected (tracking signal)
--   COVERAGE  - Data coverage dropped below threshold
--   DRIFT     - Significant change in accuracy trend detected
-- ============================================================================

CREATE TABLE IF NOT EXISTS test.forecast_alerts (
    id                  BIGINT          NOT NULL AUTO_INCREMENT PRIMARY KEY,

    -- Alert identification / 预警标识
    alert_timestamp     DATETIME        DEFAULT CURRENT_TIMESTAMP
                                                    COMMENT '预警时间 / Alert generation timestamp',
    alert_type          ENUM('CRITICAL','WARNING','BIAS','COVERAGE','DRIFT')
                                        NOT NULL    COMMENT '预警类型 / Alert severity/type classification',

    -- Entity / 关联实体
    entity_type         ENUM('STORE','PRODUCT','CATEGORY','SYSTEM')
                                        NOT NULL    COMMENT '实体类型 / Entity type that triggered the alert',
    entity_id           VARCHAR(50)                 COMMENT '实体ID / Entity identifier (store_id, goods_code, etc.)',
    entity_name         VARCHAR(200)                COMMENT '实体名称 / Entity display name',

    -- Metric details / 指标详情
    metric_name         VARCHAR(50)                 COMMENT '指标名称 / Metric that triggered alert (mape, wmape, bias, etc.)',
    metric_value        DECIMAL(10,4)               COMMENT '指标值 / Current metric value',
    threshold_value     DECIMAL(10,4)               COMMENT '阈值 / Threshold that was breached',
    baseline_value      DECIMAL(10,4)               COMMENT '基线值 / Historical baseline value for comparison',

    -- Context / 上下文
    description         TEXT                        COMMENT '描述 / Human-readable alert description',
    recommended_action  TEXT                        COMMENT '建议措施 / Recommended corrective action',

    -- Acknowledgement workflow / 确认流程
    is_acknowledged     BOOLEAN         DEFAULT FALSE
                                                    COMMENT '是否已确认 / Whether alert has been acknowledged',
    acknowledged_by     VARCHAR(100)                COMMENT '确认人 / Username who acknowledged the alert',
    acknowledged_at     DATETIME                    COMMENT '确认时间 / Acknowledgement timestamp',

    -- Indexes / 索引
    INDEX idx_type_time (alert_type, alert_timestamp),
    INDEX idx_entity    (entity_type, entity_id)

) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='UC-SC-01: 预测质量预警记录 / Forecast quality alerts with acknowledgement workflow';


-- ============================================================================
-- TABLE 4: forecast_pipeline_run_log
-- 管道运行日志表 / ETL pipeline execution tracking
-- ============================================================================
-- Tracks every execution of the forecast accuracy ETL pipeline, recording
-- start/end times, status, row counts, and error details. Used for
-- operational monitoring and data freshness verification.
-- ============================================================================

CREATE TABLE IF NOT EXISTS test.forecast_pipeline_run_log (
    id                  BIGINT          NOT NULL AUTO_INCREMENT PRIMARY KEY,

    -- Run identification / 运行标识
    run_id              VARCHAR(64)     NOT NULL    COMMENT '运行ID / Unique pipeline run identifier (UUID)',
    pipeline_name       VARCHAR(100)    NOT NULL    COMMENT '管道名称 / Pipeline name (e.g., forecast_accuracy_daily_etl)',
    step_name           VARCHAR(100)                COMMENT '步骤名称 / Pipeline step name (e.g., extract, transform, load)',

    -- Timing / 时间信息
    run_start           DATETIME        NOT NULL    COMMENT '开始时间 / Pipeline run start timestamp',
    run_end             DATETIME                    COMMENT '结束时间 / Pipeline run end timestamp',
    duration_seconds    INT                         COMMENT '耗时(秒) / Execution duration in seconds',

    -- Data scope / 数据范围
    data_date_start     DATE                        COMMENT '数据起始日期 / Start date of data processed',
    data_date_end       DATE                        COMMENT '数据截止日期 / End date of data processed',

    -- Status / 状态
    status              ENUM('RUNNING','SUCCESS','FAILED','PARTIAL','SKIPPED')
                                        NOT NULL DEFAULT 'RUNNING'
                                                    COMMENT '运行状态 / Pipeline execution status',

    -- Row counts / 行数统计
    rows_extracted      INT                         COMMENT '提取行数 / Rows extracted from source',
    rows_transformed    INT                         COMMENT '转换行数 / Rows after transformation',
    rows_loaded         INT                         COMMENT '加载行数 / Rows loaded to target table',
    rows_errored        INT             DEFAULT 0   COMMENT '错误行数 / Rows that failed processing',

    -- Target table / 目标表
    target_table        VARCHAR(100)                COMMENT '目标表 / Target table name loaded by this step',

    -- Error handling / 错误处理
    error_message       TEXT                        COMMENT '错误信息 / Error message if status = FAILED',
    error_detail        TEXT                        COMMENT '错误详情 / Full error traceback or detail',

    -- Environment / 环境信息
    triggered_by        VARCHAR(100)    DEFAULT 'scheduler'
                                                    COMMENT '触发方式 / How the run was triggered (scheduler, manual, backfill)',
    host_name           VARCHAR(100)                COMMENT '执行主机 / Host machine that executed the pipeline',
    config_snapshot     JSON                        COMMENT '配置快照 / JSON snapshot of pipeline configuration at run time',

    -- Metadata / 元数据
    created_at          DATETIME        DEFAULT CURRENT_TIMESTAMP
                                                    COMMENT '记录创建时间 / Row creation timestamp',
    updated_at          DATETIME        DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
                                                    COMMENT '记录更新时间 / Row last update timestamp',

    -- Indexes / 索引
    UNIQUE INDEX idx_run_step   (run_id, step_name),
    INDEX idx_pipeline_status   (pipeline_name, status),
    INDEX idx_run_start         (run_start),
    INDEX idx_data_date         (data_date_start, data_date_end),
    INDEX idx_status            (status)

) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='UC-SC-01: ETL管道运行日志 / Pipeline execution tracking for forecast accuracy ETL';


-- ============================================================================
-- VERIFICATION QUERIES (run after table creation)
-- ============================================================================
-- Uncomment and run these to verify the tables were created successfully:
/*
SELECT TABLE_NAME,
       TABLE_COMMENT,
       TABLE_ROWS,
       CREATE_TIME
FROM   information_schema.TABLES
WHERE  TABLE_SCHEMA = 'test'
  AND  TABLE_NAME IN (
           'forecast_accuracy_daily',
           'forecast_accuracy_summary',
           'forecast_alerts',
           'forecast_pipeline_run_log'
       )
ORDER  BY TABLE_NAME;
*/

-- ============================================================================
-- END OF DDL
-- ============================================================================

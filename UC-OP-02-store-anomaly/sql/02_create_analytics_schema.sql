-- ============================================================
-- UC-OP-02: Store Performance Anomaly Detection
-- File: 02_create_analytics_schema.sql
-- Target Server: aws-luckyus-dbatest-rw
-- Target Schema: test
-- Purpose: Create 5 analytics tables for SPC anomaly detection
-- 创建5个分析表用于SPC异常检测
-- ============================================================
--
-- Tables:
--   1. test.store_kpi_daily          - Core daily KPI fact table / 每店每日KPI事实表
--   2. test.store_anomaly_scores     - SPC computations per store/metric/day / SPC统计过程控制计算
--   3. test.store_health_scores      - Composite health per store/day / 门店综合健康评分
--   4. test.store_anomaly_alerts     - Alert records / 异常预警记录
--   5. test.store_anomaly_pipeline_log - Execution tracking / 管道执行日志
--
-- Usage:    Execute this script once to initialize the schema.
--           Re-running is safe (uses DROP IF EXISTS + CREATE IF NOT EXISTS).
--
-- Author:   Data Engineering / BI Team
-- Created:  2026-02-15
-- ============================================================


-- ============================================================
-- TABLE 1: store_kpi_daily
-- 每店每日KPI指标表 / Core daily KPI fact table
-- ============================================================
-- One row per (store, date) containing revenue, operations,
-- staffing, and quality KPIs aggregated from multiple source
-- databases. This is the foundational fact table from which
-- all anomaly detection computations are derived.
-- 每个门店每天一行，包含从多个源数据库汇总的收入、运营、
-- 人员配置和质量KPI。这是所有异常检测计算的基础事实表。
-- ============================================================

-- Safety: Drop existing table if re-initializing schema
-- 安全措施：如果重新初始化模式则删除已有表
DROP TABLE IF EXISTS test.store_kpi_daily;

CREATE TABLE IF NOT EXISTS test.store_kpi_daily (
    id                      BIGINT          AUTO_INCREMENT PRIMARY KEY
                                                            COMMENT '自增主键 / Auto-increment primary key',
    store_id                BIGINT          NOT NULL        COMMENT '门店ID (dept_id from t_shop_info) / Store ID',
    store_name              VARCHAR(100)                    COMMENT '门店名称 / Shop name',
    store_no                VARCHAR(20)                     COMMENT '门店编号 e.g. US00001 / Shop number',
    metric_date             DATE            NOT NULL        COMMENT '业务日期 / Business date',

    -- Revenue KPIs (from luckyus_sales_order.t_order)
    -- 收入KPI（来自 luckyus_sales_order.t_order）
    total_revenue           DECIMAL(12,2)                   COMMENT '每日总收入(USD) / Daily gross revenue in USD',
    order_count             INT                             COMMENT '完成订单数 / Number of completed orders',
    avg_order_value         DECIMAL(10,2)                   COMMENT '平均订单金额 = revenue/orders / AOV = revenue / orders',
    refund_count            INT             DEFAULT 0       COMMENT '退款订单数 / Number of refunded orders',
    refund_amount           DECIMAL(12,2)   DEFAULT 0       COMMENT '退款总金额(USD) / Total refund amount USD',

    -- Operations KPIs (from luckyus_opproduction.t_production)
    -- 运营KPI（来自 luckyus_opproduction.t_production）
    production_count        INT                             COMMENT '生产项目数 / Items produced',
    avg_production_time_sec DECIMAL(10,2)                   COMMENT '平均生产时间(秒) / Avg seconds per production',

    -- Staffing KPIs (from luckyus_opempefficiency)
    -- 人员KPI（来自 luckyus_opempefficiency）
    scheduled_hours         DECIMAL(8,2)                    COMMENT '排班总工时 / Total scheduled employee hours',
    employee_count          INT                             COMMENT '排班员工数 / Distinct employees scheduled',

    -- Quality KPIs (from luckyus_opqualitycontrol)
    -- 质量KPI（来自 luckyus_opqualitycontrol）
    inspection_count        INT             DEFAULT 0       COMMENT '检查次数 / Number of inspections',
    avg_quality_score       DECIMAL(5,2)                    COMMENT '平均质量评分 / Avg inspection score',

    -- Derived metrics / 衍生指标
    revenue_per_labor_hour  DECIMAL(10,2)                   COMMENT '每工时收入 = revenue/scheduled_hours / Revenue / scheduled_hours',
    orders_per_labor_hour   DECIMAL(10,2)                   COMMENT '每工时订单数 = orders/scheduled_hours / Orders / scheduled_hours',
    day_of_week             TINYINT                         COMMENT '星期几 0=Mon..6=Sun / Day of week',
    is_weekend              BOOLEAN                         COMMENT '是否周末 (Sat/Sun) / Weekend flag',

    -- Metadata / 元数据
    created_at              TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
                                                            COMMENT '记录创建时间 / Row creation timestamp',
    updated_at              TIMESTAMP       DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
                                                            COMMENT '记录更新时间 / Row last update timestamp',

    -- Constraints & Indexes / 约束和索引
    UNIQUE KEY uk_store_date (store_id, metric_date),
    INDEX idx_date     (metric_date),
    INDEX idx_store    (store_id),
    INDEX idx_store_no (store_no)

) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COMMENT='UC-OP-02: 每店每日KPI指标 / Daily KPI metrics per store';


-- ============================================================
-- TABLE 2: store_anomaly_scores
-- SPC异常评分表 / SPC computations per store/metric/day
-- ============================================================
-- Stores Statistical Process Control (SPC) calculations for
-- each store/metric/day combination. Includes rolling statistics,
-- z-scores, control limits, and Western Electric rule violations.
-- 存储每个门店/指标/日期组合的统计过程控制(SPC)计算结果。
-- 包括滚动统计、z分数、控制限和Western Electric规则违反情况。
-- ============================================================

-- Safety: Drop existing table if re-initializing schema
-- 安全措施：如果重新初始化模式则删除已有表
DROP TABLE IF EXISTS test.store_anomaly_scores;

CREATE TABLE IF NOT EXISTS test.store_anomaly_scores (
    id                      BIGINT          AUTO_INCREMENT PRIMARY KEY
                                                            COMMENT '自增主键 / Auto-increment primary key',
    store_id                BIGINT          NOT NULL        COMMENT '门店ID / Store ID',
    store_name              VARCHAR(100)                    COMMENT '门店名称 / Store name',
    metric_date             DATE            NOT NULL        COMMENT '指标日期 / Metric date',
    metric_name             VARCHAR(50)     NOT NULL        COMMENT '指标名称 (e.g. total_revenue, order_count) / Metric name',
    metric_value            DECIMAL(14,4)                   COMMENT '当日指标值 / Current day metric value',

    -- 28-day rolling statistics / 28天滚动统计
    rolling_mean_28d        DECIMAL(14,4)                   COMMENT '28天滚动均值 / 28-day rolling mean',
    rolling_std_28d         DECIMAL(14,4)                   COMMENT '28天滚动标准差 / 28-day rolling standard deviation',
    z_score                 DECIMAL(8,4)                    COMMENT 'z分数 = (value - mean) / std / Z-score',

    -- Control limits / 控制限
    ucl_2sigma              DECIMAL(14,4)                   COMMENT '上控制限 2σ / Upper control limit (mean + 2*std)',
    ucl_3sigma              DECIMAL(14,4)                   COMMENT '上控制限 3σ / Upper control limit (mean + 3*std)',
    lcl_2sigma              DECIMAL(14,4)                   COMMENT '下控制限 2σ / Lower control limit (mean - 2*std)',
    lcl_3sigma              DECIMAL(14,4)                   COMMENT '下控制限 3σ / Lower control limit (mean - 3*std)',

    -- Same day-of-week statistics / 同星期统计
    same_dow_mean           DECIMAL(14,4)                   COMMENT '同星期均值 / Same day-of-week mean',
    same_dow_std            DECIMAL(14,4)                   COMMENT '同星期标准差 / Same day-of-week standard deviation',
    dow_z_score             DECIMAL(8,4)                    COMMENT '同星期z分数 / Day-of-week adjusted z-score',

    -- Western Electric rules / Western Electric规则
    we_rule1                BOOLEAN         DEFAULT FALSE   COMMENT 'WE规则1: 单点超过3σ / Single point beyond 3 sigma',
    we_rule2                BOOLEAN         DEFAULT FALSE   COMMENT 'WE规则2: 3点中2点超过2σ(同侧) / 2 of 3 beyond 2 sigma same side',
    we_rule3                BOOLEAN         DEFAULT FALSE   COMMENT 'WE规则3: 5点中4点超过1σ(同侧) / 4 of 5 beyond 1 sigma same side',
    we_rule4                BOOLEAN         DEFAULT FALSE   COMMENT 'WE规则4: 连续8点在中心线同侧 / 8 consecutive same side of center',
    we_rule5                BOOLEAN         DEFAULT FALSE   COMMENT 'WE规则5: 连续6点递减 / 6 consecutive declining',

    -- Anomaly classification / 异常分类
    anomaly_severity        ENUM('NONE','INFO','WARNING','CRITICAL')
                                            DEFAULT 'NONE'  COMMENT '异常严重度 / Anomaly severity level',

    -- Metadata / 元数据
    created_at              TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
                                                            COMMENT '记录创建时间 / Row creation timestamp',

    -- Constraints & Indexes / 约束和索引
    UNIQUE KEY uk_store_date_metric (store_id, metric_date, metric_name),
    INDEX idx_date     (metric_date),
    INDEX idx_store    (store_id),
    INDEX idx_severity (anomaly_severity)

) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COMMENT='UC-OP-02: SPC异常评分 / SPC anomaly scores per store/metric/day';


-- ============================================================
-- TABLE 3: store_health_scores
-- 门店综合健康评分表 / Composite health score per store/day
-- ============================================================
-- Combines multiple dimension scores into a single composite
-- health score with weighted formula:
--   40% revenue + 20% ops + 15% quality + 15% staffing + 10% customer
-- Also tracks week-over-week trends and assigns letter grades.
-- 将多个维度评分合并为加权综合健康评分，并跟踪周环比趋势。
-- ============================================================

-- Safety: Drop existing table if re-initializing schema
-- 安全措施：如果重新初始化模式则删除已有表
DROP TABLE IF EXISTS test.store_health_scores;

CREATE TABLE IF NOT EXISTS test.store_health_scores (
    id                      BIGINT          AUTO_INCREMENT PRIMARY KEY
                                                            COMMENT '自增主键 / Auto-increment primary key',
    store_id                BIGINT          NOT NULL        COMMENT '门店ID / Store ID',
    store_name              VARCHAR(100)                    COMMENT '门店名称 / Store name',
    metric_date             DATE            NOT NULL        COMMENT '评分日期 / Score date',

    -- Dimension scores (0-100 scale) / 维度评分（0-100分制）
    revenue_score           DECIMAL(5,2)                    COMMENT '收入评分 (0-100) / Revenue dimension score',
    ops_score               DECIMAL(5,2)                    COMMENT '运营评分 (0-100) / Operations dimension score',
    quality_score           DECIMAL(5,2)                    COMMENT '质量评分 (0-100) / Quality dimension score',
    staffing_score          DECIMAL(5,2)                    COMMENT '人员评分 (0-100) / Staffing dimension score',
    customer_score          DECIMAL(5,2)                    COMMENT '顾客评分 (0-100) / Customer dimension score',

    -- Composite score / 综合评分
    -- Formula: 40% revenue + 20% ops + 15% quality + 15% staffing + 10% customer
    -- 公式: 40%收入 + 20%运营 + 15%质量 + 15%人员 + 10%顾客
    composite_score         DECIMAL(5,2)                    COMMENT '综合评分 (加权) / Weighted composite score',

    -- Health grade / 健康等级
    health_grade            CHAR(1)                         COMMENT '健康等级 A/B/C/D/F / Health grade letter',

    -- Trend analysis / 趋势分析
    week_over_week_change   DECIMAL(8,4)                    COMMENT '周环比变化 / Week-over-week composite score change',
    trend_direction         ENUM('IMPROVING','STABLE','DECLINING')
                                                            COMMENT '趋势方向 / Score trend direction',

    -- Metadata / 元数据
    created_at              TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
                                                            COMMENT '记录创建时间 / Row creation timestamp',

    -- Constraints & Indexes / 约束和索引
    UNIQUE KEY uk_store_date (store_id, metric_date),
    INDEX idx_date          (metric_date),
    INDEX idx_store         (store_id),
    INDEX idx_grade         (health_grade),
    INDEX idx_composite     (composite_score)

) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COMMENT='UC-OP-02: 门店综合健康评分 / Composite health score per store/day';


-- ============================================================
-- TABLE 4: store_anomaly_alerts
-- 异常预警记录表 / Alert records for detected anomalies
-- ============================================================
-- Stores alert records generated when SPC rules are violated
-- or health scores drop below thresholds. Supports bilingual
-- descriptions and an acknowledgement workflow for operations.
-- 存储SPC规则违反或健康评分低于阈值时生成的预警记录。
-- 支持中英文描述和运营团队确认流程。
-- ============================================================

-- Safety: Drop existing table if re-initializing schema
-- 安全措施：如果重新初始化模式则删除已有表
DROP TABLE IF EXISTS test.store_anomaly_alerts;

CREATE TABLE IF NOT EXISTS test.store_anomaly_alerts (
    id                      BIGINT          AUTO_INCREMENT PRIMARY KEY
                                                            COMMENT '自增主键 / Auto-increment primary key',
    store_id                BIGINT          NOT NULL        COMMENT '门店ID / Store ID',
    store_name              VARCHAR(100)                    COMMENT '门店名称 / Store name',
    alert_date              DATE            NOT NULL        COMMENT '预警日期 / Alert date',
    alert_type              VARCHAR(50)     NOT NULL        COMMENT '预警类型 (e.g. SPC_RULE, HEALTH_DROP, TREND) / Alert type',

    -- Severity / 严重程度
    severity                ENUM('INFO','WARNING','CRITICAL')
                                            NOT NULL        COMMENT '严重程度 / Alert severity level',

    -- Metric context / 指标上下文
    metric_name             VARCHAR(50)                     COMMENT '触发指标名称 / Metric name that triggered the alert',
    current_value           DECIMAL(14,4)                   COMMENT '当前值 / Current metric value',
    expected_value          DECIMAL(14,4)                   COMMENT '期望值 / Expected (mean/baseline) value',
    threshold_value         DECIMAL(14,4)                   COMMENT '阈值 / Threshold value breached',
    z_score                 DECIMAL(8,4)                    COMMENT 'z分数 / Z-score at time of alert',
    consecutive_days        INT             DEFAULT 1       COMMENT '连续天数 / Consecutive days anomaly persisted',

    -- Western Electric rule reference / WE规则引用
    we_rule_violated        VARCHAR(20)                     COMMENT '违反的WE规则 (e.g. RULE1, RULE2) / Western Electric rule violated',

    -- Bilingual descriptions / 中英文描述
    description_en          TEXT                            COMMENT '英文描述 / Alert description in English',
    description_cn          TEXT                            COMMENT '中文描述 / Alert description in Chinese',
    recommended_action      TEXT                            COMMENT '建议措施 / Recommended corrective action',

    -- Acknowledgement workflow / 确认流程
    acknowledged            BOOLEAN         DEFAULT FALSE   COMMENT '是否已确认 / Whether alert has been acknowledged',
    acknowledged_by         VARCHAR(100)                    COMMENT '确认人 / Username who acknowledged the alert',
    acknowledged_at         TIMESTAMP       NULL            COMMENT '确认时间 / Acknowledgement timestamp',

    -- Metadata / 元数据
    created_at              TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
                                                            COMMENT '记录创建时间 / Row creation timestamp',

    -- Indexes / 索引
    INDEX idx_store      (store_id),
    INDEX idx_alert_date (alert_date),
    INDEX idx_severity   (severity),
    INDEX idx_store_date (store_id, alert_date),
    INDEX idx_ack        (acknowledged)

) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COMMENT='UC-OP-02: 异常预警记录 / Store anomaly alert records with acknowledgement workflow';


-- ============================================================
-- TABLE 5: store_anomaly_pipeline_log
-- 管道执行日志表 / Pipeline execution tracking
-- ============================================================
-- Tracks every execution step of the SPC anomaly detection
-- pipeline, recording status, timing, row counts, and errors.
-- Follows the same pattern as UC-SC-01 forecast_pipeline_run_log.
-- 跟踪SPC异常检测管道的每个执行步骤，记录状态、时间、
-- 行数和错误信息。遵循与UC-SC-01相同的管道日志模式。
-- ============================================================

-- Safety: Drop existing table if re-initializing schema
-- 安全措施：如果重新初始化模式则删除已有表
DROP TABLE IF EXISTS test.store_anomaly_pipeline_log;

CREATE TABLE IF NOT EXISTS test.store_anomaly_pipeline_log (
    id                      BIGINT          AUTO_INCREMENT PRIMARY KEY
                                                            COMMENT '自增主键 / Auto-increment primary key',

    -- Run identification / 运行标识
    run_id                  VARCHAR(36)     NOT NULL        COMMENT '运行ID (UUID) / Unique pipeline run identifier',
    run_date                DATE            NOT NULL        COMMENT '运行日期 / Pipeline execution date',

    -- Step tracking / 步骤跟踪
    step_number             INT             NOT NULL        COMMENT '步骤序号 / Step sequence number',
    step_name               VARCHAR(100)    NOT NULL        COMMENT '步骤名称 / Pipeline step name',
    step_description        VARCHAR(500)                    COMMENT '步骤描述 / Step description',

    -- Status / 状态
    status                  ENUM('RUNNING','SUCCESS','FAILED','SKIPPED')
                                            DEFAULT 'RUNNING'
                                                            COMMENT '运行状态 / Step execution status',

    -- Row counts / 行数统计
    rows_affected           INT             DEFAULT 0       COMMENT '影响行数 / Rows affected by this step',

    -- Timing / 时间信息
    duration_seconds        DECIMAL(10,3)                   COMMENT '耗时(秒) / Step duration in seconds',

    -- Error handling / 错误处理
    error_message           TEXT                            COMMENT '错误信息 / Error message if status = FAILED',

    -- Timestamps / 时间戳
    started_at              TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
                                                            COMMENT '开始时间 / Step start timestamp',
    completed_at            TIMESTAMP       NULL            COMMENT '完成时间 / Step completion timestamp',

    -- Indexes / 索引
    INDEX idx_run_id   (run_id),
    INDEX idx_run_date (run_date),
    INDEX idx_status   (status)

) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COMMENT='UC-OP-02: 管道执行日志 / SPC anomaly detection pipeline execution tracking';


-- ============================================================
-- VERIFICATION QUERIES
-- 验证查询 — Run after table creation to confirm success
-- ============================================================

-- 1. Show all UC-OP-02 analytics tables / 显示所有UC-OP-02分析表
SELECT TABLE_NAME,
       TABLE_COMMENT,
       TABLE_ROWS,
       CREATE_TIME
FROM   information_schema.TABLES
WHERE  TABLE_SCHEMA = 'test'
  AND  TABLE_NAME IN (
           'store_kpi_daily',
           'store_anomaly_scores',
           'store_health_scores',
           'store_anomaly_alerts',
           'store_anomaly_pipeline_log'
       )
ORDER BY TABLE_NAME;

-- 2. Describe each table / 查看每张表结构
DESCRIBE test.store_kpi_daily;
DESCRIBE test.store_anomaly_scores;
DESCRIBE test.store_health_scores;
DESCRIBE test.store_anomaly_alerts;
DESCRIBE test.store_anomaly_pipeline_log;

-- 3. Count tables created (expect 5) / 统计已创建的表数（预期5张）
SELECT COUNT(*) AS tables_created
FROM   information_schema.TABLES
WHERE  TABLE_SCHEMA = 'test'
  AND  TABLE_NAME LIKE 'store_%';


-- ============================================================
-- END OF DDL — UC-OP-02 Store Performance Anomaly Detection
-- DDL脚本结束 — UC-OP-02 门店绩效异常检测
-- ============================================================

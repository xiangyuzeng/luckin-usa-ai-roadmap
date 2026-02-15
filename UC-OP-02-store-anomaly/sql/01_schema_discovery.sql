-- ##############################################################################
-- UC-OP-02: Store Performance Anomaly Detection
-- Schema Discovery & Source Table Documentation
-- UC-OP-02: 门店绩效异常检测 - 数据源表结构发现与文档
--
-- Purpose : Catalog every source table across 6 database servers that feeds
--           the anomaly-detection pipeline. Each section lists key columns,
--           data types, business meaning, and sample exploration queries.
-- 目的    : 梳理异常检测流水线所依赖的6台数据库服务器上的全部源表,
--           列出关键字段、数据类型、业务含义及示例查询。
--
-- Author  : Data Engineering Team
-- Created : 2026-02-15
-- Version : 1.0
--
-- IMPORTANT NOTES / 重要说明:
--   1. All monetary values (pay_money, total_money) are in USD dollars, NOT cents.
--      所有金额字段以美元(dollars)为单位, 非美分(cents)。
--   2. dept_id in most tables is the universal store identifier.
--      dept_id 是跨系统通用的门店标识符。
--   3. Timestamps are in UTC unless otherwise noted.
--      时间戳默认为 UTC, 除非另有说明。
--   4. Queries use MySQL-compatible syntax (Aurora MySQL 8.0).
--      查询使用 MySQL 兼容语法 (Aurora MySQL 8.0)。
-- ##############################################################################


-- ============================================================
-- Section 1: Store Master Data
-- 第1节: 门店主数据
-- Server: aws-luckyus-opshop-rw
-- Database: luckyus_opshop
-- Purpose: Core store reference table - identifiers, names,
--          geo-coordinates, status, and setup dates.
--          The single source of truth for store attributes.
-- 目的: 门店核心参照表 - 标识、名称、坐标、状态与开业日期。
--       门店属性的唯一权威数据源。
-- ============================================================

-- ------------------------------------
-- Table: t_shop_info
-- 表: t_shop_info (门店信息表)
-- ------------------------------------
-- Key columns / 关键字段:
--   dept_id              BIGINT        -- Store identifier (PK); used as shop_id in other DBs
--                                      -- 门店标识 (主键); 在其他库中作为 shop_id 使用
--   shop_no              VARCHAR(8)    -- Store number code, e.g. 'US001', 'US002'
--                                      -- 门店编号, 如 'US001', 'US002'
--   shop_name            VARCHAR(128)  -- Display name of the store
--                                      -- 门店显示名称
--   status               INT           -- 1 = active, 0 = inactive/closed
--                                      -- 1=营业中, 0=停业/关闭
--   address              VARCHAR(256)  -- Street address
--                                      -- 门店街道地址
--   location_longitude   DECIMAL(10,7) -- GPS longitude (WGS-84)
--                                      -- GPS 经度
--   location_latitude    DECIMAL(10,7) -- GPS latitude  (WGS-84)
--                                      -- GPS 纬度
--   set_up_time          DATETIME      -- Date the store was established / opened
--                                      -- 门店开业时间
--   create_time          DATETIME      -- Record creation timestamp
--   update_time          DATETIME      -- Last update timestamp

-- Explore table structure
-- 查看表结构
-- SHOW CREATE TABLE luckyus_opshop.t_shop_info;
-- DESC luckyus_opshop.t_shop_info;

-- 1.1  List all active US stores (excluding test stores US99xx)
-- 1.1  列出所有活跃的美国门店 (排除 US99xx 测试门店)
SELECT
    dept_id,
    shop_no,
    shop_name,
    status,
    address,
    location_longitude,
    location_latitude,
    set_up_time,
    create_time,
    update_time
FROM luckyus_opshop.t_shop_info
WHERE shop_no LIKE 'US%'
  AND shop_no NOT LIKE 'US99%'
  AND status = 1
ORDER BY shop_no;

-- 1.2  Count active vs inactive US stores
-- 1.2  统计活跃与非活跃的美国门店数量
SELECT
    status,
    COUNT(*)                          AS store_count,
    MIN(set_up_time)                  AS earliest_setup,
    MAX(set_up_time)                  AS latest_setup
FROM luckyus_opshop.t_shop_info
WHERE shop_no LIKE 'US%'
  AND shop_no NOT LIKE 'US99%'
GROUP BY status
ORDER BY status DESC;

-- 1.3  Build a reusable store dimension CTE (used in downstream queries)
-- 1.3  构建可复用的门店维度 CTE (供下游查询引用)
-- NOTE: dept_id here is referenced as shop_id in sales, production, QC, etc.
-- 注意: 此处的 dept_id 在销售、生产、质检等系统中被引用为 shop_id
/*
WITH store_dim AS (
    SELECT
        dept_id            AS shop_id,
        shop_no,
        shop_name,
        location_longitude AS lng,
        location_latitude  AS lat,
        set_up_time
    FROM luckyus_opshop.t_shop_info
    WHERE shop_no LIKE 'US%'
      AND shop_no NOT LIKE 'US99%'
      AND status = 1
)
SELECT * FROM store_dim;
*/


-- ============================================================
-- Section 2: Sales Orders
-- 第2节: 销售订单
-- Server: aws-luckyus-salesorder-rw
-- Database: luckyus_sales_order
-- Purpose: Order-level transactional data including revenue,
--          payment amounts, and pre-aggregated operational stats.
-- 目的: 订单级交易数据, 包括收入、支付金额及预聚合运营统计。
-- ============================================================

-- ------------------------------------
-- Table: t_order
-- 表: t_order (订单主表)
-- ------------------------------------
-- Key columns / 关键字段:
--   id                   BIGINT            -- Order PK / 订单主键
--   shop_id              BIGINT            -- Maps to t_shop_info.dept_id / 映射至 t_shop_info.dept_id
--   shop_name            VARCHAR(128)      -- Denormalized store name / 冗余门店名称
--   total_money          DECIMAL(12,4)     -- Gross order amount (USD dollars) / 订单总金额(美元)
--   payable_money        DECIMAL(12,4)     -- Amount due after discounts (USD) / 折后应付金额(美元)
--   pay_money            DECIMAL(12,4)     -- Actual amount paid (USD dollars, NOT cents)
--                                          -- 实际支付金额(美元, 非美分)
--   status               INT               -- Order status: 20 = paid/completed
--                                          -- 订单状态: 20 = 已支付/已完成
--   create_time          DATETIME          -- Order creation timestamp / 下单时间
--   pay_time             DATETIME          -- Payment timestamp / 支付时间
--   finish_time          DATETIME          -- Order completion timestamp / 订单完成时间
--   order_no             VARCHAR(32)       -- Human-readable order number / 可读订单号

-- 2.1  Sample: Daily revenue by store for last 30 days (completed orders only)
-- 2.1  示例: 最近30天按门店按日的营收 (仅已完成订单)
SELECT
    shop_id,
    shop_name,
    DATE(pay_time)                              AS pay_date,
    COUNT(*)                                    AS order_count,
    SUM(pay_money)                              AS daily_revenue,
    SUM(total_money)                            AS daily_gross,
    AVG(pay_money)                              AS avg_ticket
FROM luckyus_sales_order.t_order
WHERE status = 20
  AND pay_time >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
  AND pay_time <  CURDATE()
GROUP BY shop_id, shop_name, DATE(pay_time)
ORDER BY shop_id, pay_date;

-- 2.2  Monthly revenue aggregation by store (core KPI input)
-- 2.2  按门店按月营收汇总 (核心KPI输入)
SELECT
    shop_id,
    shop_name,
    DATE_FORMAT(pay_time, '%Y-%m')              AS revenue_month,
    COUNT(*)                                    AS order_count,
    SUM(pay_money)                              AS monthly_revenue,
    SUM(total_money)                            AS monthly_gross,
    AVG(pay_money)                              AS avg_order_value,
    MIN(pay_time)                               AS first_order_time,
    MAX(pay_time)                               AS last_order_time
FROM luckyus_sales_order.t_order
WHERE status = 20
  AND pay_time >= '2024-01-01'
  AND pay_time <  '2025-01-01'
GROUP BY shop_id, shop_name, DATE_FORMAT(pay_time, '%Y-%m')
ORDER BY shop_id, revenue_month;

-- ------------------------------------
-- Table: t_order_store_fact
-- 表: t_order_store_fact (门店订单统计事实表)
-- ------------------------------------
-- Pre-aggregated operational statistics; contains ORDER QUANTITIES ONLY, no revenue.
-- 预聚合运营统计; 仅包含订单数量, 不含收入金额。
-- Key columns / 关键字段:
--   cycle_type              INT           -- Aggregation period: 1=daily, 2=weekly, 3=monthly
--                                         -- 聚合周期: 1=日, 2=周, 3=月
--   shop_id                 BIGINT        -- Store identifier / 门店标识
--   total_order_quantity     INT           -- Total number of orders in the cycle
--                                         -- 周期内订单总数
--   data_time               DATE          -- Period start date / 统计周期起始日期

-- 2.3  Daily order counts from the fact table (last 7 days)
-- 2.3  事实表中最近7天的每日订单数
SELECT
    shop_id,
    data_time,
    total_order_quantity
FROM luckyus_sales_order.t_order_store_fact
WHERE cycle_type = 1
  AND data_time >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
ORDER BY shop_id, data_time;

-- ------------------------------------
-- Table: t_order_stat_fact
-- 表: t_order_stat_fact (订单统计附加事实表)
-- ------------------------------------
-- Additional aggregated metrics complementing t_order_store_fact.
-- 补充 t_order_store_fact 的额外聚合指标。
-- Key columns / 关键字段:
--   shop_id                 BIGINT        -- Store identifier / 门店标识
--   stat_date               DATE          -- Statistics date / 统计日期
--   order_count             INT           -- Number of orders / 订单数
--   cancel_count            INT           -- Cancelled orders / 取消订单数
--   refund_count            INT           -- Refunded orders / 退款订单数
--   avg_completion_time     INT           -- Avg seconds from create to finish / 平均完成时间(秒)

-- 2.4  Check additional order stats
-- 2.4  查看附加订单统计
SELECT
    shop_id,
    stat_date,
    order_count,
    cancel_count,
    refund_count,
    avg_completion_time
FROM luckyus_sales_order.t_order_stat_fact
WHERE stat_date >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
ORDER BY shop_id, stat_date;


-- ============================================================
-- Section 3: Production Data
-- 第3节: 生产数据
-- Server: aws-luckyus-opproduction-rw
-- Database: luckyus_opproduction
-- Purpose: Per-order production lifecycle: accept -> work -> done.
--          Key for computing production time (speed-of-service).
-- 目的: 单笔订单生产全生命周期: 接单 -> 制作 -> 完成。
--       用于计算生产时间 (出品速度)。
-- ============================================================

-- ------------------------------------
-- Table: t_production
-- 表: t_production (生产记录表)
-- ------------------------------------
-- Key columns / 关键字段:
--   id                   BIGINT        -- Production record PK / 生产记录主键
--   order_id             BIGINT        -- FK to t_order.id / 关联订单 ID
--   dept_id              BIGINT        -- Store identifier (= t_shop_info.dept_id)
--                                      -- 门店标识 (= t_shop_info.dept_id)
--   shop_name            VARCHAR(128)  -- Denormalized store name / 冗余门店名称
--   product_status       INT           -- Production status code / 生产状态码
--   order_create_time    DATETIME      -- When the order was placed / 下单时间
--   accept_time          DATETIME      -- When production was accepted/started / 接单时间
--   done_time            DATETIME      -- When production was completed / 完成时间
--   pay_money            DECIMAL(12,4) -- Paid amount (USD) / 支付金额(美元)
--   total_money          DECIMAL(12,4) -- Gross amount (USD) / 总金额(美元)
--
-- Production time = TIMESTAMPDIFF(SECOND, accept_time, done_time)
-- 生产时间 = TIMESTAMPDIFF(SECOND, accept_time, done_time) (单位: 秒)

-- 3.1  Average production time per store per day (last 30 days)
-- 3.1  最近30天按门店按日的平均生产时间
SELECT
    dept_id                                         AS shop_id,
    shop_name,
    DATE(accept_time)                               AS production_date,
    COUNT(*)                                        AS production_count,
    AVG(TIMESTAMPDIFF(SECOND, accept_time, done_time))  AS avg_production_seconds,
    MIN(TIMESTAMPDIFF(SECOND, accept_time, done_time))  AS min_production_seconds,
    MAX(TIMESTAMPDIFF(SECOND, accept_time, done_time))  AS max_production_seconds,
    STDDEV(TIMESTAMPDIFF(SECOND, accept_time, done_time)) AS stddev_production_seconds
FROM luckyus_opproduction.t_production
WHERE accept_time >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
  AND accept_time <  CURDATE()
  AND done_time   IS NOT NULL
  AND accept_time IS NOT NULL
GROUP BY dept_id, shop_name, DATE(accept_time)
ORDER BY dept_id, production_date;

-- 3.2  Production time distribution (percentile approximation)
-- 3.2  生产时间分布 (百分位近似)
SELECT
    dept_id                                         AS shop_id,
    COUNT(*)                                        AS total_productions,
    AVG(TIMESTAMPDIFF(SECOND, accept_time, done_time))  AS avg_seconds,
    -- Rough percentile buckets / 粗略百分位分桶
    SUM(CASE WHEN TIMESTAMPDIFF(SECOND, accept_time, done_time) <= 300  THEN 1 ELSE 0 END) AS under_5min,
    SUM(CASE WHEN TIMESTAMPDIFF(SECOND, accept_time, done_time) BETWEEN 301 AND 600 THEN 1 ELSE 0 END) AS between_5_10min,
    SUM(CASE WHEN TIMESTAMPDIFF(SECOND, accept_time, done_time) BETWEEN 601 AND 900 THEN 1 ELSE 0 END) AS between_10_15min,
    SUM(CASE WHEN TIMESTAMPDIFF(SECOND, accept_time, done_time) > 900   THEN 1 ELSE 0 END) AS over_15min
FROM luckyus_opproduction.t_production
WHERE accept_time >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
  AND accept_time <  CURDATE()
  AND done_time   IS NOT NULL
  AND accept_time IS NOT NULL
GROUP BY dept_id
ORDER BY dept_id;

-- 3.3  Hourly production volume pattern (for seasonality detection)
-- 3.3  按小时生产量模式 (用于季节性检测)
SELECT
    dept_id                                         AS shop_id,
    HOUR(accept_time)                               AS hour_of_day,
    COUNT(*)                                        AS production_count,
    AVG(TIMESTAMPDIFF(SECOND, accept_time, done_time))  AS avg_seconds
FROM luckyus_opproduction.t_production
WHERE accept_time >= DATE_SUB(CURDATE(), INTERVAL 14 DAY)
  AND accept_time <  CURDATE()
  AND done_time   IS NOT NULL
GROUP BY dept_id, HOUR(accept_time)
ORDER BY dept_id, hour_of_day;


-- ============================================================
-- Section 4: Quality Control
-- 第4节: 质量控制
-- Server: aws-luckyus-opqualitycontrol-rw
-- Database: luckyus_opqualitycontrol
-- Purpose: Store inspection check-ins and scoring data.
--          Provides quality dimension for anomaly detection.
-- 目的: 门店巡检签到与评分数据。
--       为异常检测提供质量维度。
-- ============================================================

-- ------------------------------------
-- Table: t_shopcheck_data
-- 表: t_shopcheck_data (门店巡检签到表)
-- ------------------------------------
-- Key columns / 关键字段:
--   id                   BIGINT        -- Inspection record PK / 巡检记录主键
--   dept_id              BIGINT        -- Store identifier / 门店标识
--   check_date           DATE          -- Inspection date / 巡检日期
--   status               INT           -- Inspection status / 巡检状态
--   check_duration       INT           -- Duration in seconds / 巡检时长(秒)
--   create_time          DATETIME      -- Record creation timestamp / 记录创建时间

-- 4.1  Inspection frequency per store (last 90 days)
-- 4.1  门店巡检频率 (最近90天)
SELECT
    dept_id                                         AS shop_id,
    COUNT(*)                                        AS inspection_count,
    COUNT(DISTINCT check_date)                      AS distinct_check_days,
    AVG(check_duration)                             AS avg_check_duration_sec,
    MIN(check_date)                                 AS first_check,
    MAX(check_date)                                 AS last_check
FROM luckyus_opqualitycontrol.t_shopcheck_data
WHERE check_date >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
GROUP BY dept_id
ORDER BY dept_id;

-- ------------------------------------
-- Table: t_shopcheck_report
-- 表: t_shopcheck_report (门店巡检评分报告表)
-- ------------------------------------
-- Key columns / 关键字段:
--   id                   BIGINT        -- Report PK / 报告主键
--   dept_id              BIGINT        -- Store identifier / 门店标识
--   shopcheck_data_id    BIGINT        -- FK to t_shopcheck_data.id / 关联巡检签到 ID
--   score                SMALLINT      -- Inspection score (0-100 typical) / 巡检评分 (通常0-100)
--   score_desc           VARCHAR(256)  -- Score description/comments / 评分说明
--   check_date           DATE          -- Inspection date / 巡检日期
--   second_category_name VARCHAR(128)  -- Sub-category of the inspection item
--                                      -- 巡检项目二级分类名称
--   create_time          DATETIME      -- Record creation timestamp / 记录创建时间

-- 4.2  Average quality score per store per month
-- 4.2  按门店按月平均质检评分
SELECT
    dept_id                                         AS shop_id,
    DATE_FORMAT(check_date, '%Y-%m')                AS check_month,
    COUNT(*)                                        AS report_count,
    AVG(score)                                      AS avg_score,
    MIN(score)                                      AS min_score,
    MAX(score)                                      AS max_score
FROM luckyus_opqualitycontrol.t_shopcheck_report
WHERE check_date >= '2024-01-01'
GROUP BY dept_id, DATE_FORMAT(check_date, '%Y-%m')
ORDER BY dept_id, check_month;

-- 4.3  Quality score by inspection sub-category (for drill-down)
-- 4.3  按巡检子类别的质量评分 (用于下钻分析)
SELECT
    dept_id                                         AS shop_id,
    second_category_name,
    COUNT(*)                                        AS item_count,
    AVG(score)                                      AS avg_score
FROM luckyus_opqualitycontrol.t_shopcheck_report
WHERE check_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY dept_id, second_category_name
ORDER BY dept_id, avg_score ASC;

-- 4.4  Join inspection check-in with scores for full picture
-- 4.4  关联巡检签到与评分, 获取完整视图
SELECT
    d.dept_id                                       AS shop_id,
    d.check_date,
    d.check_duration                                AS duration_sec,
    r.second_category_name,
    r.score,
    r.score_desc
FROM luckyus_opqualitycontrol.t_shopcheck_data  d
JOIN luckyus_opqualitycontrol.t_shopcheck_report r
  ON r.shopcheck_data_id = d.id
WHERE d.check_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
ORDER BY d.dept_id, d.check_date, r.second_category_name;


-- ============================================================
-- Section 5: Employee Efficiency
-- 第5节: 员工效率
-- Server: aws-luckyus-opempefficiency-rw
-- Database: luckyus_opempefficiency
-- Purpose: Scheduling and attendance records to compute
--          labor hours per store per day.
-- 目的: 排班与考勤记录, 用于计算门店每日人工工时。
-- ============================================================

-- ------------------------------------
-- Table: t_emp_scheduling
-- 表: t_emp_scheduling (员工排班表)
-- ------------------------------------
-- Key columns / 关键字段:
--   id                   BIGINT        -- Scheduling record PK / 排班记录主键
--   emp_no               VARCHAR(32)   -- Employee number / 员工编号
--   dept_id              BIGINT        -- Home department of the employee / 员工所属部门
--   scheduling_date      DATE          -- Scheduled work date / 排班日期
--   effect_hours         FLOAT(7,2)    -- Effective scheduled hours / 有效排班工时
--   work_type            INT           -- Type of work shift / 班次类型
--   scheduling_dept_id   BIGINT        -- Department where scheduled to work
--                                      -- 实际排班门店 (可能与 dept_id 不同,表示跨店支援)

-- 5.1  Daily scheduled labor hours and headcount per store
-- 5.1  门店每日排班工时与排班人数
SELECT
    scheduling_dept_id                              AS shop_id,
    scheduling_date,
    COUNT(DISTINCT emp_no)                          AS scheduled_employees,
    SUM(effect_hours)                               AS total_scheduled_hours,
    AVG(effect_hours)                               AS avg_hours_per_employee
FROM luckyus_opempefficiency.t_emp_scheduling
WHERE scheduling_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
  AND scheduling_date <  CURDATE()
GROUP BY scheduling_dept_id, scheduling_date
ORDER BY scheduling_dept_id, scheduling_date;

-- 5.2  Cross-store support detection (employees working outside home dept)
-- 5.2  跨店支援检测 (员工在非所属门店排班)
SELECT
    dept_id                                         AS home_shop_id,
    scheduling_dept_id                              AS working_shop_id,
    scheduling_date,
    COUNT(DISTINCT emp_no)                          AS cross_store_employees,
    SUM(effect_hours)                               AS cross_store_hours
FROM luckyus_opempefficiency.t_emp_scheduling
WHERE scheduling_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
  AND dept_id <> scheduling_dept_id
GROUP BY dept_id, scheduling_dept_id, scheduling_date
ORDER BY scheduling_date, home_shop_id;

-- ------------------------------------
-- Table: t_attendance
-- 表: t_attendance (员工考勤表)
-- ------------------------------------
-- Key columns / 关键字段:
--   id                   BIGINT        -- Attendance record PK / 考勤记录主键
--   emp_no               VARCHAR(32)   -- Employee number / 员工编号
--   dept_id              BIGINT        -- Store identifier / 门店标识
--   attendance_date      DATE          -- Actual attendance date / 实际出勤日期
--   effect_hours         FLOAT(7,2)    -- Actual hours worked / 实际工作工时
--   work_type            INT           -- Type of work shift / 班次类型

-- 5.3  Daily actual attendance vs schedule comparison
-- 5.3  每日实际出勤与排班对比
SELECT
    s.scheduling_dept_id                            AS shop_id,
    s.scheduling_date                               AS work_date,
    COUNT(DISTINCT s.emp_no)                        AS scheduled_count,
    COUNT(DISTINCT a.emp_no)                        AS attended_count,
    SUM(s.effect_hours)                             AS scheduled_hours,
    SUM(a.effect_hours)                             AS actual_hours,
    ROUND(COUNT(DISTINCT a.emp_no) / NULLIF(COUNT(DISTINCT s.emp_no), 0) * 100, 1)
                                                    AS attendance_rate_pct
FROM luckyus_opempefficiency.t_emp_scheduling s
LEFT JOIN luckyus_opempefficiency.t_attendance a
  ON  a.emp_no          = s.emp_no
  AND a.attendance_date = s.scheduling_date
  AND a.dept_id         = s.scheduling_dept_id
WHERE s.scheduling_date >= DATE_SUB(CURDATE(), INTERVAL 14 DAY)
  AND s.scheduling_date <  CURDATE()
GROUP BY s.scheduling_dept_id, s.scheduling_date
ORDER BY s.scheduling_dept_id, s.scheduling_date;

-- 5.4  Weekly labor hour trend per store (for anomaly baseline)
-- 5.4  门店每周人工工时趋势 (用于异常基线)
SELECT
    scheduling_dept_id                              AS shop_id,
    YEARWEEK(scheduling_date, 1)                    AS year_week,
    MIN(scheduling_date)                            AS week_start,
    COUNT(DISTINCT emp_no)                          AS unique_employees,
    SUM(effect_hours)                               AS total_hours,
    AVG(effect_hours)                               AS avg_hours_per_shift
FROM luckyus_opempefficiency.t_emp_scheduling
WHERE scheduling_date >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
GROUP BY scheduling_dept_id, YEARWEEK(scheduling_date, 1)
ORDER BY scheduling_dept_id, year_week;


-- ============================================================
-- Section 6: Analytics Output Tables
-- 第6节: 分析输出表
-- Server: aws-luckyus-dbatest-rw
-- Database: test
-- Purpose: Destination tables for the anomaly detection pipeline.
--          These 5 tables store computed KPIs, anomaly scores,
--          health scores, alerts, and pipeline run metadata.
-- 目的: 异常检测流水线的目标输出表。
--       这5张表存储计算后的KPI、异常评分、健康评分、告警及流水线运行元数据。
-- ============================================================

-- ------------------------------------
-- Table: store_kpi_daily
-- 表: store_kpi_daily (门店日度KPI表)
-- Purpose: Daily KPI metrics aggregated per store
-- 目的: 按门店聚合的日度KPI指标
-- ------------------------------------
/*
CREATE TABLE IF NOT EXISTS test.store_kpi_daily (
    id                  BIGINT AUTO_INCREMENT PRIMARY KEY,
    shop_id             BIGINT          NOT NULL  COMMENT '门店ID (dept_id)',
    kpi_date            DATE            NOT NULL  COMMENT 'KPI日期',
    revenue             DECIMAL(14,4)   DEFAULT 0 COMMENT '日营收(USD)',
    order_count         INT             DEFAULT 0 COMMENT '订单数',
    avg_ticket          DECIMAL(10,4)   DEFAULT 0 COMMENT '平均客单价(USD)',
    avg_production_sec  FLOAT           DEFAULT 0 COMMENT '平均生产时间(秒)',
    scheduled_hours     FLOAT           DEFAULT 0 COMMENT '排班工时',
    actual_hours        FLOAT           DEFAULT 0 COMMENT '实际工时',
    employee_count      INT             DEFAULT 0 COMMENT '排班人数',
    quality_score       FLOAT           DEFAULT NULL COMMENT '质检评分(如有)',
    revenue_per_labor_hour DECIMAL(10,4) DEFAULT NULL COMMENT '人工时效(USD/小时)',
    created_at          DATETIME        DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME        DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_shop_date (shop_id, kpi_date),
    INDEX idx_kpi_date (kpi_date),
    INDEX idx_shop_id (shop_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='门店日度KPI指标';
*/

-- ------------------------------------
-- Table: store_anomaly_scores
-- 表: store_anomaly_scores (门店异常评分表)
-- Purpose: Per-KPI anomaly scores computed by the detection model
-- 目的: 检测模型计算的逐KPI异常评分
-- ------------------------------------
/*
CREATE TABLE IF NOT EXISTS test.store_anomaly_scores (
    id                  BIGINT AUTO_INCREMENT PRIMARY KEY,
    shop_id             BIGINT          NOT NULL  COMMENT '门店ID',
    score_date          DATE            NOT NULL  COMMENT '评分日期',
    kpi_name            VARCHAR(64)     NOT NULL  COMMENT 'KPI名称',
    kpi_value           FLOAT                     COMMENT 'KPI实际值',
    expected_value      FLOAT                     COMMENT '模型预期值',
    anomaly_score       FLOAT           NOT NULL  COMMENT '异常得分 (0-1)',
    is_anomaly          TINYINT(1)      DEFAULT 0 COMMENT '是否异常 (1=是)',
    direction           VARCHAR(8)                COMMENT 'high / low / normal',
    model_version       VARCHAR(32)               COMMENT '模型版本',
    created_at          DATETIME        DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_shop_date_kpi (shop_id, score_date, kpi_name),
    INDEX idx_score_date (score_date),
    INDEX idx_anomaly (is_anomaly, score_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='门店异常评分';
*/

-- ------------------------------------
-- Table: store_health_scores
-- 表: store_health_scores (门店健康评分表)
-- Purpose: Composite health score per store per day
-- 目的: 门店每日综合健康评分
-- ------------------------------------
/*
CREATE TABLE IF NOT EXISTS test.store_health_scores (
    id                  BIGINT AUTO_INCREMENT PRIMARY KEY,
    shop_id             BIGINT          NOT NULL  COMMENT '门店ID',
    score_date          DATE            NOT NULL  COMMENT '评分日期',
    health_score        FLOAT           NOT NULL  COMMENT '综合健康评分 (0-100)',
    revenue_component   FLOAT                     COMMENT '营收分项',
    efficiency_component FLOAT                    COMMENT '效率分项',
    quality_component   FLOAT                     COMMENT '质量分项',
    labor_component     FLOAT                     COMMENT '人工分项',
    risk_level          VARCHAR(16)               COMMENT 'low / medium / high / critical',
    created_at          DATETIME        DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME        DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_shop_date (shop_id, score_date),
    INDEX idx_score_date (score_date),
    INDEX idx_risk_level (risk_level, score_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='门店健康评分';
*/

-- ------------------------------------
-- Table: store_anomaly_alerts
-- 表: store_anomaly_alerts (门店异常告警表)
-- Purpose: Generated alerts when anomaly thresholds are breached
-- 目的: 当异常阈值被触发时生成的告警记录
-- ------------------------------------
/*
CREATE TABLE IF NOT EXISTS test.store_anomaly_alerts (
    id                  BIGINT AUTO_INCREMENT PRIMARY KEY,
    shop_id             BIGINT          NOT NULL  COMMENT '门店ID',
    alert_date          DATE            NOT NULL  COMMENT '告警日期',
    alert_type          VARCHAR(64)     NOT NULL  COMMENT '告警类型',
    severity            VARCHAR(16)     NOT NULL  COMMENT 'info / warning / critical',
    kpi_name            VARCHAR(64)               COMMENT '相关KPI',
    kpi_value           FLOAT                     COMMENT 'KPI实际值',
    threshold_value     FLOAT                     COMMENT '阈值',
    message             TEXT                      COMMENT '告警消息',
    is_acknowledged     TINYINT(1)      DEFAULT 0 COMMENT '是否已确认',
    acknowledged_by     VARCHAR(64)               COMMENT '确认人',
    acknowledged_at     DATETIME                  COMMENT '确认时间',
    created_at          DATETIME        DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_shop_date (shop_id, alert_date),
    INDEX idx_severity (severity, alert_date),
    INDEX idx_unack (is_acknowledged, alert_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='门店异常告警';
*/

-- ------------------------------------
-- Table: store_anomaly_pipeline_log
-- 表: store_anomaly_pipeline_log (异常检测流水线运行日志)
-- Purpose: Track pipeline execution history, status, and metrics
-- 目的: 追踪流水线执行历史、状态和指标
-- ------------------------------------
/*
CREATE TABLE IF NOT EXISTS test.store_anomaly_pipeline_log (
    id                  BIGINT AUTO_INCREMENT PRIMARY KEY,
    run_id              VARCHAR(64)     NOT NULL  COMMENT '运行ID (UUID)',
    run_date            DATE            NOT NULL  COMMENT '数据日期',
    pipeline_stage      VARCHAR(64)     NOT NULL  COMMENT '流水线阶段',
    status              VARCHAR(16)     NOT NULL  COMMENT 'running / success / failed',
    started_at          DATETIME        NOT NULL  COMMENT '开始时间',
    finished_at         DATETIME                  COMMENT '结束时间',
    rows_processed      INT             DEFAULT 0 COMMENT '处理行数',
    shops_processed     INT             DEFAULT 0 COMMENT '处理门店数',
    anomalies_detected  INT             DEFAULT 0 COMMENT '检出异常数',
    error_message       TEXT                      COMMENT '错误信息',
    created_at          DATETIME        DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_run_stage (run_id, pipeline_stage),
    INDEX idx_run_date (run_date),
    INDEX idx_status (status, run_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='异常检测流水线日志';
*/


-- ============================================================
-- Section 7: Data Coverage Summary
-- 第7节: 数据覆盖度汇总
-- Server: (cross-server queries - run individually per server)
-- Purpose: Template queries to verify data completeness per
--          store per month across all source systems.
-- 目的: 模板查询, 用于验证各源系统中按门店按月的数据完整性。
-- ============================================================

-- 7.1  Sales data coverage per store per month
-- 7.1  按门店按月的销售数据覆盖度
-- Run on: aws-luckyus-salesorder-rw / luckyus_sales_order
SELECT
    shop_id,
    DATE_FORMAT(pay_time, '%Y-%m')                  AS data_month,
    COUNT(*)                                        AS order_count,
    COUNT(DISTINCT DATE(pay_time))                  AS days_with_orders,
    DAY(LAST_DAY(pay_time))                         AS days_in_month,
    ROUND(COUNT(DISTINCT DATE(pay_time))
        / DAY(LAST_DAY(pay_time)) * 100, 1)        AS coverage_pct
FROM luckyus_sales_order.t_order
WHERE status = 20
  AND pay_time >= '2024-01-01'
GROUP BY shop_id, DATE_FORMAT(pay_time, '%Y-%m'), LAST_DAY(pay_time)
ORDER BY shop_id, data_month;

-- 7.2  Production data coverage per store per month
-- 7.2  按门店按月的生产数据覆盖度
-- Run on: aws-luckyus-opproduction-rw / luckyus_opproduction
SELECT
    dept_id                                         AS shop_id,
    DATE_FORMAT(accept_time, '%Y-%m')               AS data_month,
    COUNT(*)                                        AS production_count,
    COUNT(DISTINCT DATE(accept_time))               AS days_with_production,
    DAY(LAST_DAY(accept_time))                      AS days_in_month,
    ROUND(COUNT(DISTINCT DATE(accept_time))
        / DAY(LAST_DAY(accept_time)) * 100, 1)     AS coverage_pct
FROM luckyus_opproduction.t_production
WHERE accept_time >= '2024-01-01'
  AND done_time IS NOT NULL
GROUP BY dept_id, DATE_FORMAT(accept_time, '%Y-%m'), LAST_DAY(accept_time)
ORDER BY dept_id, data_month;

-- 7.3  Scheduling data coverage per store per month
-- 7.3  按门店按月的排班数据覆盖度
-- Run on: aws-luckyus-opempefficiency-rw / luckyus_opempefficiency
SELECT
    scheduling_dept_id                              AS shop_id,
    DATE_FORMAT(scheduling_date, '%Y-%m')           AS data_month,
    COUNT(*)                                        AS scheduling_records,
    COUNT(DISTINCT scheduling_date)                 AS days_with_schedules,
    COUNT(DISTINCT emp_no)                          AS unique_employees,
    SUM(effect_hours)                               AS total_hours
FROM luckyus_opempefficiency.t_emp_scheduling
WHERE scheduling_date >= '2024-01-01'
GROUP BY scheduling_dept_id, DATE_FORMAT(scheduling_date, '%Y-%m')
ORDER BY scheduling_dept_id, data_month;

-- 7.4  Quality control data coverage per store per month
-- 7.4  按门店按月的质检数据覆盖度
-- Run on: aws-luckyus-opqualitycontrol-rw / luckyus_opqualitycontrol
SELECT
    dept_id                                         AS shop_id,
    DATE_FORMAT(check_date, '%Y-%m')                AS data_month,
    COUNT(*)                                        AS inspection_count,
    COUNT(DISTINCT check_date)                      AS days_with_inspections,
    AVG(score)                                      AS avg_score
FROM luckyus_opqualitycontrol.t_shopcheck_report
WHERE check_date >= '2024-01-01'
GROUP BY dept_id, DATE_FORMAT(check_date, '%Y-%m')
ORDER BY dept_id, data_month;

-- 7.5  Cross-reference: verify store IDs exist in master data
-- 7.5  交叉验证: 确认各系统的门店ID在主数据中存在
-- Run on: aws-luckyus-opshop-rw (or via federated query / application)
-- This is a template; replace the subquery with actual IDs from each source.
/*
-- Check which shop_ids from sales are NOT in master data
SELECT DISTINCT o.shop_id
FROM luckyus_sales_order.t_order o
WHERE o.status = 20
  AND o.pay_time >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
  AND o.shop_id NOT IN (
      SELECT dept_id FROM luckyus_opshop.t_shop_info
      WHERE shop_no LIKE 'US%' AND shop_no NOT LIKE 'US99%'
  );
*/

-- 7.6  Unified coverage summary template (run per-server, aggregate in Python)
-- 7.6  统一覆盖度汇总模板 (按服务器执行, 在 Python 中汇总)
-- The Python pipeline should collect results from 7.1-7.4 and build a matrix:
-- Python 流水线应汇总 7.1-7.4 的结果, 构建如下矩阵:
--
--   shop_id | month   | has_sales | has_production | has_schedule | has_quality
--   --------|---------|-----------|----------------|--------------|------------
--   12345   | 2024-01 |     Y     |       Y        |      Y       |     N
--   12345   | 2024-02 |     Y     |       Y        |      Y       |     Y
--   ...
--
-- Stores missing ANY dimension for a given month should be flagged for review.
-- 任一维度缺失的门店-月份组合应被标记以供审查。


-- ##############################################################################
-- END OF SCHEMA DISCOVERY
-- 架构发现文档结束
--
-- Summary of source tables / 源表汇总:
--   Server 1 (opshop)            : t_shop_info               (门店主数据)
--   Server 2 (salesorder)        : t_order, t_order_store_fact, t_order_stat_fact
--                                                             (销售订单)
--   Server 3 (opproduction)      : t_production              (生产数据)
--   Server 4 (opqualitycontrol)  : t_shopcheck_data, t_shopcheck_report
--                                                             (质量控制)
--   Server 5 (opempefficiency)   : t_emp_scheduling, t_attendance
--                                                             (员工效率)
--   Server 6 (dbatest)           : store_kpi_daily, store_anomaly_scores,
--                                  store_health_scores, store_anomaly_alerts,
--                                  store_anomaly_pipeline_log (分析输出)
--
-- Total source tables : 10 (read) + 5 (write) = 15
-- 源表总计            : 10 (读取) + 5 (写入) = 15
-- ##############################################################################

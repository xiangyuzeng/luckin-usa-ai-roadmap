-- ============================================================
-- UC-OP-02: Store Performance Anomaly Detection
-- File: 04_extract_operations_kpis.sql
-- Sources: aws-luckyus-opproduction-rw (luckyus_opproduction)
--          aws-luckyus-opempefficiency-rw (luckyus_opempefficiency)
--          aws-luckyus-opqualitycontrol-rw (luckyus_opqualitycontrol)
-- Target: aws-luckyus-dbatest-rw (test.store_kpi_daily)
-- Purpose: Extract production, staffing, and quality KPIs
-- 提取生产、人员排班和质量检查KPI
-- ============================================================
--
-- CROSS-SERVER ARCHITECTURE NOTE / 跨服务器架构说明:
-- ---------------------------------------------------------------
-- The source tables reside on THREE separate MySQL servers:
--   1. aws-luckyus-opproduction-rw    -> luckyus_opproduction
--   2. aws-luckyus-opempefficiency-rw -> luckyus_opempefficiency
--   3. aws-luckyus-opqualitycontrol-rw -> luckyus_opqualitycontrol
--
-- The target table resides on a fourth server:
--   4. aws-luckyus-dbatest-rw         -> test.store_kpi_daily
--
-- Because MySQL does not support cross-server JOINs natively,
-- each Part (A/B/C) runs on its respective source server and
-- the Python orchestrator moves intermediate results to the
-- target server for final assembly.
-- 由于MySQL不支持跨服务器JOIN，每个部分在各自的源服务器上运行，
-- Python编排器负责将中间结果传输到目标服务器进行最终组装。
-- ---------------------------------------------------------------
--
-- DATA PROFILE (from discovery) / 数据概况:
--   Production: 500K+ rows, 36 shops, data from 2025-03-24
--   Staffing:   16-17K rows each table, 17-18 shops, from 2025-03-22
--   Quality:    ~120 rows, 17 shops (sparse / 稀疏数据)
--
-- Active store IDs / 活跃门店:
--   1127, 1128, 1131, 1140, 1141,
--   20008, 20009, 20010, 20011, 20046
-- ============================================================


-- ############################################################
-- PART A: PRODUCTION KPIs
-- 第A部分：生产KPI
-- Server: aws-luckyus-opproduction-rw
-- Source:  luckyus_opproduction.t_production
-- ############################################################

-- ----------------------------------------------------------
-- A-1. Daily production count and average production time
--      per store (completed orders only).
--      每日每门店生产完成量及平均生产耗时（仅已完成订单）
-- ----------------------------------------------------------
-- Key columns:
--   dept_id            : store identifier / 门店ID
--   order_create_time  : order creation timestamp / 下单时间
--   accept_time        : production start timestamp / 接单时间
--   done_time          : production end timestamp / 完成时间
--   product_status     : order lifecycle status / 订单状态
--   pay_money          : order payment amount / 支付金额
-- ----------------------------------------------------------
-- Production time = TIMESTAMPDIFF(SECOND, accept_time, done_time)
-- Filters:
--   - accept_time and done_time both NOT NULL (valid timestamps)
--   - done_time > accept_time  (exclude negative / zero durations)
--   - dept_id restricted to 10 active stores
-- ----------------------------------------------------------

-- >>> Run on: aws-luckyus-opproduction-rw <<<
-- >>> Output staging table: tmp_production_kpi <<<

SELECT
    dept_id,
    DATE(order_create_time)                                   AS metric_date,
    -- Production volume / 生产量
    COUNT(*)                                                  AS production_count,
    -- Average production time in seconds / 平均生产时间（秒）
    AVG(TIMESTAMPDIFF(SECOND, accept_time, done_time))        AS avg_production_time_sec,
    -- Median approximation: we use percentile later in Python
    -- 中位数近似：后续在Python中计算百分位
    MIN(TIMESTAMPDIFF(SECOND, accept_time, done_time))        AS min_production_time_sec,
    MAX(TIMESTAMPDIFF(SECOND, accept_time, done_time))        AS max_production_time_sec,
    -- Standard deviation for anomaly detection / 标准差用于异常检测
    STDDEV_SAMP(TIMESTAMPDIFF(SECOND, accept_time, done_time)) AS stddev_production_time_sec,
    -- Revenue metrics from production / 生产收入指标
    SUM(pay_money)                                            AS total_production_revenue,
    AVG(pay_money)                                            AS avg_order_value
FROM luckyus_opproduction.t_production
WHERE accept_time IS NOT NULL
  AND done_time   IS NOT NULL
  AND done_time   > accept_time
  AND dept_id IN (1127, 1128, 1131, 1140, 1141,
                  20008, 20009, 20010, 20011, 20046)
GROUP BY dept_id, DATE(order_create_time)
ORDER BY dept_id, metric_date;


-- ----------------------------------------------------------
-- A-2. Hourly production distribution (for peak-hour analysis).
--      每小时生产分布（用于高峰时段分析）
-- ----------------------------------------------------------
-- This provides the orchestrator with intra-day patterns
-- to detect shift in peak hours — a leading anomaly indicator.
-- 为编排器提供日内模式，检测高峰时段偏移（领先异常指标）
-- ----------------------------------------------------------

-- >>> Run on: aws-luckyus-opproduction-rw <<<
-- >>> Output staging table: tmp_production_hourly <<<

SELECT
    dept_id,
    DATE(order_create_time)                                   AS metric_date,
    HOUR(order_create_time)                                   AS hour_of_day,
    COUNT(*)                                                  AS hourly_order_count,
    AVG(TIMESTAMPDIFF(SECOND, accept_time, done_time))        AS hourly_avg_prod_time_sec,
    SUM(pay_money)                                            AS hourly_revenue
FROM luckyus_opproduction.t_production
WHERE accept_time IS NOT NULL
  AND done_time   IS NOT NULL
  AND done_time   > accept_time
  AND dept_id IN (1127, 1128, 1131, 1140, 1141,
                  20008, 20009, 20010, 20011, 20046)
GROUP BY dept_id, DATE(order_create_time), HOUR(order_create_time)
ORDER BY dept_id, metric_date, hour_of_day;


-- ############################################################
-- PART B: STAFFING KPIs
-- 第B部分：人员排班KPI
-- Server: aws-luckyus-opempefficiency-rw
-- Sources: luckyus_opempefficiency.t_emp_scheduling
--          luckyus_opempefficiency.t_attendance
-- ############################################################

-- ----------------------------------------------------------
-- B-1. Daily scheduled hours and headcount per store.
--      每日每门店排班工时及在岗人数
-- ----------------------------------------------------------
-- Key columns (t_emp_scheduling):
--   scheduling_dept_id : store where shift is scheduled / 排班门店
--   scheduling_date    : shift date (DATE type) / 排班日期
--   effect_hours       : effective scheduled hours FLOAT(7,2) / 有效排班工时
--   emp_no             : employee number / 员工编号
--   work_type          : shift type / 班次类型
-- ----------------------------------------------------------

-- >>> Run on: aws-luckyus-opempefficiency-rw <<<
-- >>> Output staging table: tmp_staffing_scheduled <<<

SELECT
    scheduling_dept_id                          AS dept_id,
    scheduling_date                             AS metric_date,
    -- Total scheduled labor hours / 总排班工时
    SUM(effect_hours)                           AS scheduled_hours,
    -- Headcount: unique employees scheduled / 排班人数（去重）
    COUNT(DISTINCT emp_no)                      AS scheduled_employee_count,
    -- Average hours per employee / 人均排班工时
    SUM(effect_hours) / NULLIF(COUNT(DISTINCT emp_no), 0)
                                                AS avg_hours_per_employee,
    -- Shift type distribution (for pattern analysis)
    -- 班次分布（用于模式分析）
    SUM(CASE WHEN work_type = 'MORNING'  THEN 1 ELSE 0 END) AS morning_shift_count,
    SUM(CASE WHEN work_type = 'AFTERNOON' THEN 1 ELSE 0 END) AS afternoon_shift_count,
    SUM(CASE WHEN work_type = 'EVENING'  THEN 1 ELSE 0 END) AS evening_shift_count,
    SUM(CASE WHEN work_type NOT IN ('MORNING','AFTERNOON','EVENING')
                                         THEN 1 ELSE 0 END) AS other_shift_count
FROM luckyus_opempefficiency.t_emp_scheduling
WHERE scheduling_dept_id IN (1127, 1128, 1131, 1140, 1141,
                             20008, 20009, 20010, 20011, 20046)
GROUP BY scheduling_dept_id, scheduling_date
ORDER BY dept_id, metric_date;


-- ----------------------------------------------------------
-- B-2. Daily actual attendance hours and headcount per store.
--      每日每门店实际出勤工时及到岗人数
-- ----------------------------------------------------------
-- t_attendance mirrors t_emp_scheduling structure but tracks
-- actual clock-in/out rather than planned schedules.
-- t_attendance与t_emp_scheduling结构类似，但记录实际打卡而非计划排班
-- ----------------------------------------------------------

-- >>> Run on: aws-luckyus-opempefficiency-rw <<<
-- >>> Output staging table: tmp_staffing_attendance <<<

SELECT
    dept_id,
    attendance_date                             AS metric_date,
    -- Actual labor hours worked / 实际出勤工时
    SUM(effect_hours)                           AS actual_hours,
    -- Actual headcount on-site / 实际到岗人数
    COUNT(DISTINCT emp_no)                      AS actual_employee_count,
    -- Average actual hours per employee / 人均实际工时
    SUM(effect_hours) / NULLIF(COUNT(DISTINCT emp_no), 0)
                                                AS avg_actual_hours_per_employee
FROM luckyus_opempefficiency.t_attendance
WHERE dept_id IN (1127, 1128, 1131, 1140, 1141,
                  20008, 20009, 20010, 20011, 20046)
GROUP BY dept_id, attendance_date
ORDER BY dept_id, metric_date;


-- ############################################################
-- PART C: QUALITY KPIs
-- 第C部分：质量检查KPI
-- Server: aws-luckyus-opqualitycontrol-rw
-- Sources: luckyus_opqualitycontrol.t_shopcheck_report
--          luckyus_opqualitycontrol.t_shopcheck_data
-- ############################################################

-- ----------------------------------------------------------
-- C-1. Daily inspection count and average quality score.
--      每日每门店巡检次数及平均质量评分
-- ----------------------------------------------------------
-- Key columns (t_shopcheck_report):
--   dept_id          : store identifier / 门店ID
--   shopcheck_data_id: FK to t_shopcheck_data / 关联巡检数据
--   check_date       : inspection date / 检查日期
--   score            : inspection score SMALLINT / 检查评分
--   score_desc       : score description / 评分说明
-- ----------------------------------------------------------
-- NOTE: Only ~120 records across 17 shops — this is sparse data.
-- Many store-days will have NULL quality metrics.
-- 注意：仅约120条记录覆盖17家门店——数据稀疏，
-- 许多门店日将无质量指标数据。
-- ----------------------------------------------------------

-- >>> Run on: aws-luckyus-opqualitycontrol-rw <<<
-- >>> Output staging table: tmp_quality_report <<<

SELECT
    r.dept_id,
    r.check_date                                AS metric_date,
    -- Inspection volume / 巡检次数
    COUNT(*)                                    AS inspection_count,
    -- Average quality score / 平均质量评分
    AVG(r.score)                                AS avg_quality_score,
    -- Score range for variability detection / 评分范围用于波动检测
    MIN(r.score)                                AS min_quality_score,
    MAX(r.score)                                AS max_quality_score,
    -- Count of low-scoring inspections (threshold: 60)
    -- 低分巡检数量（阈值：60分）
    SUM(CASE WHEN r.score < 60 THEN 1 ELSE 0 END) AS low_score_count
FROM luckyus_opqualitycontrol.t_shopcheck_report r
WHERE r.dept_id IN (1127, 1128, 1131, 1140, 1141,
                    20008, 20009, 20010, 20011, 20046)
GROUP BY r.dept_id, r.check_date
ORDER BY r.dept_id, metric_date;


-- ----------------------------------------------------------
-- C-2. Inspection duration from t_shopcheck_data.
--      巡检时长（来源：t_shopcheck_data）
-- ----------------------------------------------------------
-- Supplements C-1 with time-spent-on-inspection metrics.
-- A sudden drop in check_duration may indicate rushed checks.
-- 补充C-1，提供巡检耗时指标。巡检时长骤降可能表示敷衍检查。
-- ----------------------------------------------------------

-- >>> Run on: aws-luckyus-opqualitycontrol-rw <<<
-- >>> Output staging table: tmp_quality_duration <<<

SELECT
    d.dept_id,
    d.check_date                                AS metric_date,
    COUNT(*)                                    AS check_data_count,
    AVG(d.check_duration)                       AS avg_check_duration,
    -- Status distribution / 状态分布
    SUM(CASE WHEN d.status = 1 THEN 1 ELSE 0 END) AS completed_checks,
    SUM(CASE WHEN d.status = 0 THEN 1 ELSE 0 END) AS incomplete_checks
FROM luckyus_opqualitycontrol.t_shopcheck_data d
WHERE d.dept_id IN (1127, 1128, 1131, 1140, 1141,
                    20008, 20009, 20010, 20011, 20046)
GROUP BY d.dept_id, d.check_date
ORDER BY d.dept_id, metric_date;


-- ############################################################
-- PART D: DERIVED METRICS (run on target server)
-- 第D部分：衍生指标（在目标服务器上运行）
-- Server: aws-luckyus-dbatest-rw
-- Target: test.store_kpi_daily
-- ############################################################

-- ----------------------------------------------------------
-- D-0. Prerequisite: ensure base KPI columns exist.
--      前置条件：确保基础KPI列已存在
-- ----------------------------------------------------------
-- The orchestrator loads Parts A/B/C staging data into
-- test.store_kpi_daily before running Part D.
-- 编排器将A/B/C部分的临时数据加载到 test.store_kpi_daily 后再运行D部分。
-- ----------------------------------------------------------

-- >>> Run on: aws-luckyus-dbatest-rw <<<

-- ----------------------------------------------------------
-- D-1. Revenue per labor hour / 每工时营收
-- ----------------------------------------------------------
-- Combines production revenue (Part A) with scheduled hours
-- (Part B) to measure labor productivity.
-- 结合生产营收（A部分）和排班工时（B部分）衡量劳动生产率。
-- Formula: revenue_per_labor_hour = total_revenue / scheduled_hours
-- ----------------------------------------------------------

UPDATE test.store_kpi_daily
SET revenue_per_labor_hour = total_production_revenue / NULLIF(scheduled_hours, 0)
WHERE scheduled_hours IS NOT NULL
  AND total_production_revenue IS NOT NULL;

-- ----------------------------------------------------------
-- D-2. Orders per labor hour / 每工时订单数
-- ----------------------------------------------------------
-- Measures operational throughput relative to staffing.
-- 衡量相对于人员配置的运营吞吐量。
-- Formula: orders_per_labor_hour = production_count / scheduled_hours
-- ----------------------------------------------------------

UPDATE test.store_kpi_daily
SET orders_per_labor_hour = production_count / NULLIF(scheduled_hours, 0)
WHERE scheduled_hours IS NOT NULL
  AND production_count IS NOT NULL;

-- ----------------------------------------------------------
-- D-3. Staffing efficiency ratio / 人员效率比
-- ----------------------------------------------------------
-- Compares actual attendance to scheduled hours.
-- Ratio < 1.0 means understaffed vs plan; > 1.0 means overtime.
-- 比较实际出勤与排班工时。比值<1.0表示人员不足；>1.0表示加班。
-- Formula: staffing_efficiency = actual_hours / scheduled_hours
-- ----------------------------------------------------------

UPDATE test.store_kpi_daily
SET staffing_efficiency = actual_hours / NULLIF(scheduled_hours, 0)
WHERE scheduled_hours IS NOT NULL
  AND actual_hours IS NOT NULL;

-- ----------------------------------------------------------
-- D-4. Average production time per employee / 人均生产时间
-- ----------------------------------------------------------
-- Normalizes production workload by headcount.
-- 按人数归一化生产工作量。
-- Formula: production_time_per_employee =
--          (avg_production_time_sec * production_count) / employee_count
-- ----------------------------------------------------------

UPDATE test.store_kpi_daily
SET production_time_per_employee =
    (avg_production_time_sec * production_count)
    / NULLIF(scheduled_employee_count, 0)
WHERE avg_production_time_sec IS NOT NULL
  AND production_count IS NOT NULL
  AND scheduled_employee_count IS NOT NULL;

-- ----------------------------------------------------------
-- D-5. Average order value / 平均客单价
-- ----------------------------------------------------------
-- Calculated from production revenue and order count.
-- 由生产营收和订单数计算。
-- Formula: avg_order_value = total_production_revenue / production_count
-- ----------------------------------------------------------

UPDATE test.store_kpi_daily
SET avg_order_value = total_production_revenue / NULLIF(production_count, 0)
WHERE total_production_revenue IS NOT NULL
  AND production_count IS NOT NULL;


-- ############################################################
-- PART E: DATA COVERAGE VERIFICATION
-- 第E部分：数据覆盖率验证
-- Server: aws-luckyus-dbatest-rw (after all data loaded)
-- ############################################################

-- ----------------------------------------------------------
-- E-1. Store-level coverage summary.
--      门店级数据覆盖概况
-- ----------------------------------------------------------
-- Identifies which stores have production / staffing / quality
-- data and flags coverage gaps for the anomaly model.
-- 识别哪些门店有生产/人员/质量数据，标记覆盖缺口。
-- ----------------------------------------------------------

-- >>> Run on: aws-luckyus-dbatest-rw <<<

SELECT
    dept_id,
    -- Date range with data / 有数据的日期范围
    MIN(metric_date)                            AS earliest_date,
    MAX(metric_date)                            AS latest_date,
    COUNT(DISTINCT metric_date)                 AS total_days,
    -- Production coverage / 生产数据覆盖
    SUM(CASE WHEN production_count IS NOT NULL
                  AND production_count > 0
             THEN 1 ELSE 0 END)                 AS days_with_production,
    -- Staffing coverage / 人员数据覆盖
    SUM(CASE WHEN scheduled_hours IS NOT NULL
                  AND scheduled_hours > 0
             THEN 1 ELSE 0 END)                 AS days_with_staffing,
    -- Quality coverage (expected to be sparse) / 质量数据覆盖（预期稀疏）
    SUM(CASE WHEN inspection_count IS NOT NULL
                  AND inspection_count > 0
             THEN 1 ELSE 0 END)                 AS days_with_quality,
    -- Derived metric coverage / 衍生指标覆盖
    SUM(CASE WHEN revenue_per_labor_hour IS NOT NULL
             THEN 1 ELSE 0 END)                 AS days_with_labor_metrics
FROM test.store_kpi_daily
WHERE dept_id IN (1127, 1128, 1131, 1140, 1141,
                  20008, 20009, 20010, 20011, 20046)
GROUP BY dept_id
ORDER BY dept_id;


-- ----------------------------------------------------------
-- E-2. Cross-domain coverage matrix.
--      跨域数据覆盖矩阵
-- ----------------------------------------------------------
-- Shows the intersection of data sources per store-day.
-- Rows with all three domains present are "full coverage".
-- 展示每个门店日各数据源的交集情况。三个域都有数据的为"完全覆盖"。
-- ----------------------------------------------------------

SELECT
    CASE
        WHEN production_count > 0 AND scheduled_hours > 0 AND inspection_count > 0
            THEN 'FULL'
        WHEN production_count > 0 AND scheduled_hours > 0
            THEN 'PROD+STAFF'
        WHEN production_count > 0 AND inspection_count > 0
            THEN 'PROD+QUALITY'
        WHEN scheduled_hours > 0 AND inspection_count > 0
            THEN 'STAFF+QUALITY'
        WHEN production_count > 0
            THEN 'PROD_ONLY'
        WHEN scheduled_hours > 0
            THEN 'STAFF_ONLY'
        WHEN inspection_count > 0
            THEN 'QUALITY_ONLY'
        ELSE 'NO_DATA'
    END                                         AS coverage_type,
    COUNT(*)                                    AS row_count,
    COUNT(DISTINCT dept_id)                     AS store_count,
    -- Percentage of total rows / 占总行数百分比
    ROUND(COUNT(*) * 100.0
          / (SELECT COUNT(*) FROM test.store_kpi_daily
             WHERE dept_id IN (1127,1128,1131,1140,1141,
                               20008,20009,20010,20011,20046)),
          2)                                    AS pct_of_total
FROM test.store_kpi_daily
WHERE dept_id IN (1127, 1128, 1131, 1140, 1141,
                  20008, 20009, 20010, 20011, 20046)
GROUP BY coverage_type
ORDER BY row_count DESC;


-- ----------------------------------------------------------
-- E-3. Data freshness check / 数据新鲜度检查
-- ----------------------------------------------------------
-- Ensures we have recent data before anomaly detection runs.
-- Alerts if the most recent data is older than 2 days.
-- 在运行异常检测前确保有最新数据。若最近数据超过2天则告警。
-- ----------------------------------------------------------

SELECT
    dept_id,
    MAX(metric_date)                            AS most_recent_date,
    DATEDIFF(CURDATE(), MAX(metric_date))       AS days_since_last_data,
    CASE
        WHEN DATEDIFF(CURDATE(), MAX(metric_date)) > 2
            THEN 'STALE'
        ELSE 'OK'
    END                                         AS freshness_status
FROM test.store_kpi_daily
WHERE dept_id IN (1127, 1128, 1131, 1140, 1141,
                  20008, 20009, 20010, 20011, 20046)
GROUP BY dept_id
ORDER BY days_since_last_data DESC;


-- ============================================================
-- EXECUTION NOTES / 执行说明
-- ============================================================
-- 1. The Python orchestrator runs Parts A, B, C in PARALLEL
--    on their respective source servers.
--    Python编排器在各自源服务器上并行运行A、B、C部分。
--
-- 2. Staging results (tmp_*) are collected and INSERT/UPDATE'd
--    into test.store_kpi_daily on the target server.
--    临时结果(tmp_*)被收集并INSERT/UPDATE到目标服务器的
--    test.store_kpi_daily表中。
--
-- 3. Part D derived metrics run AFTER all staging data is loaded.
--    D部分衍生指标在所有临时数据加载完成后运行。
--
-- 4. Part E verification runs LAST to confirm data integrity.
--    E部分验证最后运行，以确认数据完整性。
--
-- 5. Quality data (Part C) is sparse (~120 rows / 17 shops).
--    The anomaly model should handle NULLs gracefully for
--    quality KPIs on most store-days.
--    质量数据（C部分）稀疏（约120行/17家门店）。异常模型需对
--    大多数门店日的质量KPI空值进行合理处理。
--
-- 6. Production data starts 2025-03-24, staffing from 2025-03-22.
--    Derived metrics (Part D) only available for overlapping dates.
--    生产数据起始2025-03-24，排班数据起始2025-03-22。
--    衍生指标（D部分）仅在日期重叠时可用。
-- ============================================================

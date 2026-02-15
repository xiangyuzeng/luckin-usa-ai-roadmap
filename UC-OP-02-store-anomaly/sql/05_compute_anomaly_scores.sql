-- ============================================================
-- UC-OP-02: Store Performance Anomaly Detection
-- File: 05_compute_anomaly_scores.sql
-- Source: aws-luckyus-dbatest-rw (test.store_kpi_daily)
-- Target: aws-luckyus-dbatest-rw (test.store_anomaly_scores)
-- Purpose: Compute SPC Z-scores, control limits, WE rules
-- 计算SPC Z分数、控制限和西部电气规则
-- ============================================================
--
-- Overview / 概述:
--   This is the core analytics engine of the UC-OP-02 pipeline.
--   It reads daily KPI data from store_kpi_daily and computes
--   Statistical Process Control (SPC) metrics for each store/metric
--   combination, writing results into store_anomaly_scores.
--
--   这是UC-OP-02管道的核心分析引擎。它从store_kpi_daily读取每日
--   KPI数据，为每个门店/指标组合计算统计过程控制(SPC)指标，
--   并将结果写入store_anomaly_scores。
--
-- Pipeline Steps / 管道步骤:
--   Section 1: Z-Score Computation (28-day rolling window)
--              Z分数计算（28天滚动窗口）
--   Section 2: Day-of-Week Adjusted Z-Scores (8-week DOW window)
--              星期调整Z分数（8周同星期窗口）
--   Section 3: Western Electric Rules (5 rules)
--              西部电气规则（5条规则）
--   Section 4: Anomaly Severity Classification
--              异常严重度分类
--   Section 5: Verification & QA Queries
--              验证和质量保证查询
--
-- SPC Background / SPC背景:
--   Statistical Process Control was developed by Walter Shewhart
--   at Bell Labs in the 1920s. It uses control charts to monitor
--   whether a process is in a state of statistical control.
--   统计过程控制由Walter Shewhart于1920年代在贝尔实验室开发。
--   它使用控制图来监测过程是否处于统计控制状态。
--
--   Western Electric Rules were published in the 1956 AT&T
--   "Statistical Quality Control Handbook" to detect non-random
--   patterns in control chart data even before points cross 3-sigma.
--   西部电气规则发表于1956年AT&T《统计质量控制手册》，用于在
--   数据点越过3-sigma之前检测控制图数据中的非随机模式。
--
-- Prerequisites / 前置条件:
--   - test.store_kpi_daily must be populated (run 03_extract_kpis.sql)
--   - test.store_anomaly_scores table must exist (run 02_create_analytics_schema.sql)
--   - At least 28 days of historical data should be available
--
-- Metrics Computed / 计算的指标:
--   1. total_revenue          - 每日总收入 / Daily gross revenue
--   2. order_count            - 订单数量 / Number of orders
--   3. avg_order_value        - 平均订单金额 / Average order value
--   4. production_count       - 生产项目数 / Items produced
--   5. avg_production_time_sec - 平均生产时间 / Avg production time
--   6. scheduled_hours        - 排班工时 / Scheduled employee hours
--   7. avg_quality_score      - 平均质量评分 / Average quality score
--   8. revenue_per_labor_hour - 每工时收入 / Revenue per labor hour
--
-- Author:   Data Engineering / BI Team
-- Created:  2026-02-15
-- ============================================================


-- ############################################################
-- SECTION 0: PREPARATION
-- 准备工作 — Clear target table for idempotent re-runs
-- ############################################################

-- Truncate the anomaly_scores table so this script is idempotent.
-- If you want incremental loads, replace TRUNCATE with a
-- date-range DELETE instead.
-- 截断异常评分表以便此脚本可重复执行。
-- 如需增量加载，请将TRUNCATE替换为按日期范围的DELETE。

TRUNCATE TABLE test.store_anomaly_scores;


-- ############################################################
-- SECTION 1: Z-SCORE COMPUTATION (28-DAY ROLLING WINDOW)
-- 第一节: Z分数计算（28天滚动窗口）
-- ############################################################
--
-- For each of the 8 tracked metrics, we compute:
--   rolling_mean_28d : Mean of the metric over the prior 28 days
--                      (including current day). This is the center
--                      line of our SPC control chart.
--                      过去28天指标的均值（包括当天），即SPC控制图的中心线。
--
--   rolling_std_28d  : Sample standard deviation over same window.
--                      This measures natural process variation.
--                      同窗口的样本标准差，衡量过程的自然变异。
--
--   z_score          : Number of standard deviations the current
--                      observation is from the rolling mean.
--                      z = (x - mu) / sigma
--                      当前观测值偏离滚动均值的标准差倍数。
--
-- We use ROWS BETWEEN 27 PRECEDING AND CURRENT ROW to get exactly
-- 28 data points (27 prior + 1 current). This corresponds to a
-- 4-week lookback which is standard for retail SPC.
-- 我们使用 ROWS BETWEEN 27 PRECEDING AND CURRENT ROW 来获取恰好
-- 28个数据点（27个前值+1个当前值），对应零售SPC标准的4周回溯期。
--
-- NOTE: We insert with z_score=NULL first, then UPDATE it in a
-- second pass. This avoids issues with MySQL's restriction on
-- using window functions directly in computed expressions within
-- the same SELECT that references them.
-- 注意：我们先插入z_score=NULL，然后在第二步中UPDATE。这避免了
-- MySQL对在同一SELECT中直接使用窗口函数计算表达式的限制。
-- ############################################################


-- ─────────────────────────────────────────────────────
-- 1.1  Metric: total_revenue (每日总收入)
-- ─────────────────────────────────────────────────────
-- Revenue is the primary business KPI. Sudden drops may indicate
-- POS failures, staffing issues, or local competitive events.
-- Spikes could indicate catering orders or promotional successes.
-- 收入是主要业务KPI。骤降可能表示POS故障、人员问题或本地竞争。
-- 骤升可能表示团体订单或促销成功。

INSERT INTO test.store_anomaly_scores
    (store_id, store_name, metric_date, metric_name, metric_value,
     rolling_mean_28d, rolling_std_28d)
SELECT
    s.store_id,
    s.store_name,
    s.metric_date,
    'total_revenue'                                         AS metric_name,
    s.total_revenue                                         AS metric_value,
    AVG(s.total_revenue) OVER w28                           AS rolling_mean_28d,
    STDDEV_SAMP(s.total_revenue) OVER w28                   AS rolling_std_28d
FROM test.store_kpi_daily s
WHERE s.metric_date >= '2025-04-01'
  AND s.total_revenue IS NOT NULL
WINDOW w28 AS (
    PARTITION BY s.store_id
    ORDER BY s.metric_date
    ROWS BETWEEN 27 PRECEDING AND CURRENT ROW
);


-- ─────────────────────────────────────────────────────
-- 1.2  Metric: order_count (订单数量)
-- ─────────────────────────────────────────────────────
-- Order count tracks transaction volume. Declines without
-- corresponding revenue declines suggest higher AOV; declines
-- with revenue declines signal genuine traffic loss.
-- 订单数量追踪交易量。订单减少但收入未减少说明AOV提高；
-- 订单和收入同时减少则表示真正的客流量下降。

INSERT INTO test.store_anomaly_scores
    (store_id, store_name, metric_date, metric_name, metric_value,
     rolling_mean_28d, rolling_std_28d)
SELECT
    s.store_id,
    s.store_name,
    s.metric_date,
    'order_count'                                           AS metric_name,
    s.order_count                                           AS metric_value,
    AVG(s.order_count) OVER w28                             AS rolling_mean_28d,
    STDDEV_SAMP(s.order_count) OVER w28                     AS rolling_std_28d
FROM test.store_kpi_daily s
WHERE s.metric_date >= '2025-04-01'
  AND s.order_count IS NOT NULL
WINDOW w28 AS (
    PARTITION BY s.store_id
    ORDER BY s.metric_date
    ROWS BETWEEN 27 PRECEDING AND CURRENT ROW
);


-- ─────────────────────────────────────────────────────
-- 1.3  Metric: avg_order_value (平均订单金额)
-- ─────────────────────────────────────────────────────
-- Average Order Value (AOV) = total_revenue / order_count.
-- Shifts in AOV may indicate menu price changes, upselling
-- effectiveness, or product mix shifts.
-- 平均订单金额(AOV) = 总收入 / 订单数。
-- AOV变化可能表示菜单价格变更、追加销售效果或产品组合变化。

INSERT INTO test.store_anomaly_scores
    (store_id, store_name, metric_date, metric_name, metric_value,
     rolling_mean_28d, rolling_std_28d)
SELECT
    s.store_id,
    s.store_name,
    s.metric_date,
    'avg_order_value'                                       AS metric_name,
    s.avg_order_value                                       AS metric_value,
    AVG(s.avg_order_value) OVER w28                         AS rolling_mean_28d,
    STDDEV_SAMP(s.avg_order_value) OVER w28                 AS rolling_std_28d
FROM test.store_kpi_daily s
WHERE s.metric_date >= '2025-04-01'
  AND s.avg_order_value IS NOT NULL
WINDOW w28 AS (
    PARTITION BY s.store_id
    ORDER BY s.metric_date
    ROWS BETWEEN 27 PRECEDING AND CURRENT ROW
);


-- ─────────────────────────────────────────────────────
-- 1.4  Metric: production_count (生产项目数)
-- ─────────────────────────────────────────────────────
-- Production count tracks kitchen/back-of-house throughput.
-- Low production with high orders may indicate operational
-- bottlenecks; high production with low orders may indicate
-- waste from over-preparation.
-- 生产项目数追踪厨房/后台产能。
-- 低生产高订单可能表示运营瓶颈；高生产低订单可能表示过度准备的浪费。

INSERT INTO test.store_anomaly_scores
    (store_id, store_name, metric_date, metric_name, metric_value,
     rolling_mean_28d, rolling_std_28d)
SELECT
    s.store_id,
    s.store_name,
    s.metric_date,
    'production_count'                                      AS metric_name,
    s.production_count                                      AS metric_value,
    AVG(s.production_count) OVER w28                         AS rolling_mean_28d,
    STDDEV_SAMP(s.production_count) OVER w28                 AS rolling_std_28d
FROM test.store_kpi_daily s
WHERE s.metric_date >= '2025-04-01'
  AND s.production_count IS NOT NULL
WINDOW w28 AS (
    PARTITION BY s.store_id
    ORDER BY s.metric_date
    ROWS BETWEEN 27 PRECEDING AND CURRENT ROW
);


-- ─────────────────────────────────────────────────────
-- 1.5  Metric: avg_production_time_sec (平均生产时间)
-- ─────────────────────────────────────────────────────
-- Average production time in seconds per item. Increases may
-- indicate equipment issues, training gaps, or recipe complexity
-- changes. Decreases could signal improved efficiency or corner-cutting.
-- 每件产品的平均生产时间（秒）。增加可能表示设备问题、培训不足或
-- 配方复杂度变化。减少可能表示效率提升或偷工减料。

INSERT INTO test.store_anomaly_scores
    (store_id, store_name, metric_date, metric_name, metric_value,
     rolling_mean_28d, rolling_std_28d)
SELECT
    s.store_id,
    s.store_name,
    s.metric_date,
    'avg_production_time_sec'                               AS metric_name,
    s.avg_production_time_sec                               AS metric_value,
    AVG(s.avg_production_time_sec) OVER w28                  AS rolling_mean_28d,
    STDDEV_SAMP(s.avg_production_time_sec) OVER w28          AS rolling_std_28d
FROM test.store_kpi_daily s
WHERE s.metric_date >= '2025-04-01'
  AND s.avg_production_time_sec IS NOT NULL
WINDOW w28 AS (
    PARTITION BY s.store_id
    ORDER BY s.metric_date
    ROWS BETWEEN 27 PRECEDING AND CURRENT ROW
);


-- ─────────────────────────────────────────────────────
-- 1.6  Metric: scheduled_hours (排班工时)
-- ─────────────────────────────────────────────────────
-- Total scheduled employee hours per day. Too many hours with
-- low revenue signals overstaffing; too few hours with high
-- revenue signals understaffing and potential service issues.
-- 每日排班总工时。工时多但收入低说明超编；
-- 工时少但收入高说明人手不足和潜在服务问题。

INSERT INTO test.store_anomaly_scores
    (store_id, store_name, metric_date, metric_name, metric_value,
     rolling_mean_28d, rolling_std_28d)
SELECT
    s.store_id,
    s.store_name,
    s.metric_date,
    'scheduled_hours'                                       AS metric_name,
    s.scheduled_hours                                       AS metric_value,
    AVG(s.scheduled_hours) OVER w28                          AS rolling_mean_28d,
    STDDEV_SAMP(s.scheduled_hours) OVER w28                  AS rolling_std_28d
FROM test.store_kpi_daily s
WHERE s.metric_date >= '2025-04-01'
  AND s.scheduled_hours IS NOT NULL
WINDOW w28 AS (
    PARTITION BY s.store_id
    ORDER BY s.metric_date
    ROWS BETWEEN 27 PRECEDING AND CURRENT ROW
);


-- ─────────────────────────────────────────────────────
-- 1.7  Metric: avg_quality_score (平均质量评分)
-- ─────────────────────────────────────────────────────
-- Quality inspection score (0-100 scale). Persistent declines
-- may indicate training gaps or equipment degradation. Sudden
-- drops warrant immediate investigation.
-- 质量检查评分（0-100分制）。持续下降可能表示培训不足或
-- 设备退化。突然下降需要立即调查。

INSERT INTO test.store_anomaly_scores
    (store_id, store_name, metric_date, metric_name, metric_value,
     rolling_mean_28d, rolling_std_28d)
SELECT
    s.store_id,
    s.store_name,
    s.metric_date,
    'avg_quality_score'                                     AS metric_name,
    s.avg_quality_score                                     AS metric_value,
    AVG(s.avg_quality_score) OVER w28                        AS rolling_mean_28d,
    STDDEV_SAMP(s.avg_quality_score) OVER w28                AS rolling_std_28d
FROM test.store_kpi_daily s
WHERE s.metric_date >= '2025-04-01'
  AND s.avg_quality_score IS NOT NULL
WINDOW w28 AS (
    PARTITION BY s.store_id
    ORDER BY s.metric_date
    ROWS BETWEEN 27 PRECEDING AND CURRENT ROW
);


-- ─────────────────────────────────────────────────────
-- 1.8  Metric: revenue_per_labor_hour (每工时收入)
-- ─────────────────────────────────────────────────────
-- Revenue per scheduled labor hour. This is the primary
-- labor efficiency metric, combining revenue performance and
-- staffing efficiency into a single indicator.
-- 每排班工时的收入。这是主要的劳动效率指标，
-- 将收入表现和人员效率合并为单一指标。

INSERT INTO test.store_anomaly_scores
    (store_id, store_name, metric_date, metric_name, metric_value,
     rolling_mean_28d, rolling_std_28d)
SELECT
    s.store_id,
    s.store_name,
    s.metric_date,
    'revenue_per_labor_hour'                                AS metric_name,
    s.revenue_per_labor_hour                                AS metric_value,
    AVG(s.revenue_per_labor_hour) OVER w28                   AS rolling_mean_28d,
    STDDEV_SAMP(s.revenue_per_labor_hour) OVER w28           AS rolling_std_28d
FROM test.store_kpi_daily s
WHERE s.metric_date >= '2025-04-01'
  AND s.revenue_per_labor_hour IS NOT NULL
WINDOW w28 AS (
    PARTITION BY s.store_id
    ORDER BY s.metric_date
    ROWS BETWEEN 27 PRECEDING AND CURRENT ROW
);


-- ─────────────────────────────────────────────────────
-- 1.9  Compute Z-Scores and Control Limits
-- 计算Z分数和控制限
-- ─────────────────────────────────────────────────────
-- Now that rolling_mean_28d and rolling_std_28d are populated,
-- we can compute:
--   z_score    = (metric_value - rolling_mean_28d) / rolling_std_28d
--   ucl_2sigma = rolling_mean_28d + 2 * rolling_std_28d
--   ucl_3sigma = rolling_mean_28d + 3 * rolling_std_28d
--   lcl_2sigma = rolling_mean_28d - 2 * rolling_std_28d
--   lcl_3sigma = rolling_mean_28d - 3 * rolling_std_28d
--
-- NULLIF(rolling_std_28d, 0) prevents division by zero when
-- a store has zero variance (e.g., constant metric values or
-- only 1 day of data in the window).
-- NULLIF(rolling_std_28d, 0) 防止当门店方差为零时除以零
-- （例如，指标值恒定或窗口中只有1天数据）。
--
-- Control limit interpretation / 控制限解读:
--   2-sigma limits: ~95.4% of normal data falls within
--                   约95.4%的正常数据落在此范围内
--   3-sigma limits: ~99.7% of normal data falls within
--                   约99.7%的正常数据落在此范围内
--   Points beyond 3-sigma are very unlikely under normal
--   conditions (< 0.3% probability per observation).
--   超过3-sigma的点在正常条件下非常不可能（每次观测<0.3%概率）。

UPDATE test.store_anomaly_scores
SET
    z_score    = (metric_value - rolling_mean_28d)
                 / NULLIF(rolling_std_28d, 0),

    ucl_2sigma = rolling_mean_28d + 2.0 * rolling_std_28d,
    ucl_3sigma = rolling_mean_28d + 3.0 * rolling_std_28d,
    lcl_2sigma = rolling_mean_28d - 2.0 * rolling_std_28d,
    lcl_3sigma = rolling_mean_28d - 3.0 * rolling_std_28d

WHERE rolling_std_28d IS NOT NULL
  AND rolling_std_28d > 0;


-- ############################################################
-- SECTION 2: DAY-OF-WEEK ADJUSTED Z-SCORES
-- 第二节: 星期调整Z分数
-- ############################################################
--
-- Retail stores exhibit strong day-of-week (DOW) seasonality:
-- weekends typically have higher revenue/orders, while weekdays
-- may be quieter. A Monday with $5,000 revenue is not comparable
-- to a Saturday with $5,000.
-- 零售门店表现出强烈的星期(DOW)季节性：
-- 周末通常收入/订单更高，而工作日可能较安静。
-- 周一$5,000收入与周六$5,000不可比较。
--
-- To account for this, we compute the mean and standard deviation
-- for the SAME day of week over the trailing 8 weeks. This gives
-- us a "Monday vs. Mondays" comparison.
-- 为解决此问题，我们计算过去8周内同一星期几的均值和标准差。
-- 这给我们提供了"周一与周一"的比较。
--
-- DOW Z-score = (actual - dow_mean) / dow_std
-- 星期Z分数 = (实际值 - 同星期均值) / 同星期标准差
--
-- Implementation: We use a self-join approach because MySQL
-- window functions with RANGE + DAYOFWEEK filtering are complex.
-- We join each anomaly_scores row back to store_kpi_daily for
-- the same store_id, same day_of_week, within 56 days prior.
-- 实现方式：我们使用自联接方法，因为MySQL窗口函数配合
-- RANGE + DAYOFWEEK过滤较为复杂。我们将每条anomaly_scores
-- 记录与前56天内同门店、同星期几的store_kpi_daily记录联接。
-- ############################################################


-- ─────────────────────────────────────────────────────
-- 2.1  Compute DOW statistics via correlated subquery
-- 通过关联子查询计算星期统计
-- ─────────────────────────────────────────────────────
-- We use a temporary table to pre-compute DOW stats to avoid
-- expensive correlated subqueries running row-by-row.
-- 我们使用临时表预计算星期统计，以避免逐行执行的关联子查询开销。

DROP TEMPORARY TABLE IF EXISTS tmp_dow_stats;

CREATE TEMPORARY TABLE tmp_dow_stats AS
SELECT
    a.store_id,
    a.metric_date,
    a.metric_name,
    AVG(
        CASE a.metric_name
            WHEN 'total_revenue'          THEN k.total_revenue
            WHEN 'order_count'            THEN k.order_count
            WHEN 'avg_order_value'        THEN k.avg_order_value
            WHEN 'production_count'       THEN k.production_count
            WHEN 'avg_production_time_sec' THEN k.avg_production_time_sec
            WHEN 'scheduled_hours'        THEN k.scheduled_hours
            WHEN 'avg_quality_score'      THEN k.avg_quality_score
            WHEN 'revenue_per_labor_hour' THEN k.revenue_per_labor_hour
        END
    ) AS dow_mean,
    STDDEV_SAMP(
        CASE a.metric_name
            WHEN 'total_revenue'          THEN k.total_revenue
            WHEN 'order_count'            THEN k.order_count
            WHEN 'avg_order_value'        THEN k.avg_order_value
            WHEN 'production_count'       THEN k.production_count
            WHEN 'avg_production_time_sec' THEN k.avg_production_time_sec
            WHEN 'scheduled_hours'        THEN k.scheduled_hours
            WHEN 'avg_quality_score'      THEN k.avg_quality_score
            WHEN 'revenue_per_labor_hour' THEN k.revenue_per_labor_hour
        END
    ) AS dow_std
FROM test.store_anomaly_scores a
JOIN test.store_kpi_daily k
    ON  k.store_id    = a.store_id
    -- Same day of week: DAYOFWEEK returns 1=Sun..7=Sat
    -- 同一星期几：DAYOFWEEK返回1=周日..7=周六
    AND DAYOFWEEK(k.metric_date) = DAYOFWEEK(a.metric_date)
    -- Within 56 days prior (8 weeks lookback)
    -- 前56天内（8周回溯）
    AND k.metric_date BETWEEN DATE_SUB(a.metric_date, INTERVAL 56 DAY)
                          AND a.metric_date
    -- Exclude dates too far in the future from the KPI table
    -- 排除KPI表中过远未来的日期
    AND k.metric_date <= a.metric_date
GROUP BY a.store_id, a.metric_date, a.metric_name;

-- Add index to speed up the subsequent JOIN / 添加索引加速后续JOIN
ALTER TABLE tmp_dow_stats ADD INDEX idx_lookup (store_id, metric_date, metric_name);


-- ─────────────────────────────────────────────────────
-- 2.2  Update anomaly_scores with DOW statistics
-- 用星期统计更新anomaly_scores
-- ─────────────────────────────────────────────────────

UPDATE test.store_anomaly_scores a
JOIN tmp_dow_stats d
    ON  d.store_id    = a.store_id
    AND d.metric_date = a.metric_date
    AND d.metric_name = a.metric_name
SET
    a.same_dow_mean = d.dow_mean,
    a.same_dow_std  = d.dow_std,
    a.dow_z_score   = (a.metric_value - d.dow_mean)
                      / NULLIF(d.dow_std, 0);

-- Clean up temporary table / 清理临时表
DROP TEMPORARY TABLE IF EXISTS tmp_dow_stats;


-- ############################################################
-- SECTION 3: WESTERN ELECTRIC RULES
-- 第三节: 西部电气规则
-- ############################################################
--
-- The Western Electric rules are a set of decision rules for
-- detecting non-random patterns on control charts. They trigger
-- alerts earlier than waiting for a single 3-sigma violation.
-- 西部电气规则是一组用于检测控制图上非随机模式的判定规则。
-- 它们比等待单次3-sigma违反更早触发警报。
--
-- We implement 5 rules:
-- 我们实施5条规则:
--
-- Rule 1: Single point beyond 3 sigma (|z| > 3)
--         单点超过3sigma
--   -> Probability under normality: 0.27% per point
--      正态分布下的概率：每点0.27%
--   -> Interpretation: Almost certainly a special cause
--      解读：几乎可以确定是特殊原因
--
-- Rule 2: 2 of 3 consecutive points beyond 2 sigma (same side)
--         连续3点中有2点超过2sigma（同侧）
--   -> Probability under normality: ~0.16%
--      正态分布下的概率：约0.16%
--   -> Interpretation: Process shift likely beginning
--      解读：过程偏移可能开始
--
-- Rule 3: 4 of 5 consecutive points beyond 1 sigma (same side)
--         连续5点中有4点超过1sigma（同侧）
--   -> Probability under normality: ~0.27%
--      正态分布下的概率：约0.27%
--   -> Interpretation: Small but persistent shift
--      解读：小幅但持续的偏移
--
-- Rule 4: 8 consecutive points on same side of center line
--         连续8点在中心线同侧
--   -> Probability under normality: (0.5)^8 = 0.39%
--      正态分布下的概率：(0.5)^8 = 0.39%
--   -> Interpretation: Process mean has shifted
--      解读：过程均值已发生偏移
--
-- Rule 5: 6 consecutive declining points (monotonic decrease)
--         连续6点递减（单调递减）
--   -> Interpretation: Systematic downward trend
--      解读：系统性下降趋势
--
-- Implementation uses LAG() window functions to access prior
-- z-score values within the same store/metric partition.
-- 实现使用LAG()窗口函数访问同一门店/指标分区内的先前z分数值。
-- ############################################################


-- ─────────────────────────────────────────────────────
-- 3.1  WE Rule 1: Single point beyond 3 sigma
-- WE规则1: 单点超过3sigma
-- ─────────────────────────────────────────────────────
-- This is the most straightforward rule: if |z_score| > 3,
-- the point is beyond the 3-sigma control limit.
-- 这是最直接的规则：如果|z_score| > 3，该点超出3-sigma控制限。
--
-- In a normal distribution, only 0.27% of points fall outside
-- 3 sigma (0.135% on each side). Observing such a point is
-- strong evidence of a special cause.
-- 在正态分布中，只有0.27%的点落在3sigma之外（每侧0.135%）。
-- 观察到这样的点是特殊原因的有力证据。

UPDATE test.store_anomaly_scores
SET we_rule1 = (ABS(z_score) > 3)
WHERE z_score IS NOT NULL;


-- ─────────────────────────────────────────────────────
-- 3.2  WE Rule 2: 2 of 3 consecutive beyond 2 sigma (same side)
-- WE规则2: 连续3点中2点超过2sigma（同侧）
-- ─────────────────────────────────────────────────────
-- Check current point plus the two preceding points.
-- At least 2 of these 3 must be beyond 2 sigma on the SAME side
-- (all above +2 or all below -2). This detects emerging shifts
-- that haven't yet reached 3 sigma.
-- 检查当前点加前两个点。这3个点中至少2个必须在同侧超过2sigma
-- （全部高于+2或全部低于-2）。这检测尚未达到3sigma的新出现的偏移。

UPDATE test.store_anomaly_scores a
JOIN (
    SELECT
        id,
        z_score                                                  AS z0,
        LAG(z_score, 1) OVER w AS z1,
        LAG(z_score, 2) OVER w AS z2
    FROM test.store_anomaly_scores
    WINDOW w AS (PARTITION BY store_id, metric_name ORDER BY metric_date)
) b ON a.id = b.id
SET a.we_rule2 = (
    -- Upper side: 2 of 3 points above +2 sigma
    -- 上侧：3点中2点高于+2sigma
    (   (CASE WHEN b.z0 > 2 THEN 1 ELSE 0 END)
      + (CASE WHEN b.z1 > 2 THEN 1 ELSE 0 END)
      + (CASE WHEN b.z2 > 2 THEN 1 ELSE 0 END)
    ) >= 2
    OR
    -- Lower side: 2 of 3 points below -2 sigma
    -- 下侧：3点中2点低于-2sigma
    (   (CASE WHEN b.z0 < -2 THEN 1 ELSE 0 END)
      + (CASE WHEN b.z1 < -2 THEN 1 ELSE 0 END)
      + (CASE WHEN b.z2 < -2 THEN 1 ELSE 0 END)
    ) >= 2
)
WHERE b.z0 IS NOT NULL
  AND b.z1 IS NOT NULL
  AND b.z2 IS NOT NULL;


-- ─────────────────────────────────────────────────────
-- 3.3  WE Rule 3: 4 of 5 consecutive beyond 1 sigma (same side)
-- WE规则3: 连续5点中4点超过1sigma（同侧）
-- ─────────────────────────────────────────────────────
-- Check current point plus the four preceding points.
-- At least 4 of these 5 must be beyond 1 sigma on the SAME side.
-- This detects small but persistent process shifts.
-- 检查当前点加前四个点。这5个点中至少4个必须在同侧超过1sigma。
-- 这检测小幅但持续的过程偏移。
--
-- Under normality, ~15.87% of points exceed 1 sigma on one side.
-- Having 4 of 5 on the same side: C(5,4) * 0.1587^4 * 0.8413^1
-- + C(5,5) * 0.1587^5 ≈ 0.27% — quite unlikely by chance.
-- 在正态分布下，约15.87%的点在一侧超过1sigma。
-- 5点中4点在同侧：C(5,4)*0.1587^4*0.8413^1 + C(5,5)*0.1587^5
-- ≈ 0.27% — 偶然发生的可能性很小。

UPDATE test.store_anomaly_scores a
JOIN (
    SELECT
        id,
        z_score                                                  AS z0,
        LAG(z_score, 1) OVER w AS z1,
        LAG(z_score, 2) OVER w AS z2,
        LAG(z_score, 3) OVER w AS z3,
        LAG(z_score, 4) OVER w AS z4
    FROM test.store_anomaly_scores
    WINDOW w AS (PARTITION BY store_id, metric_name ORDER BY metric_date)
) b ON a.id = b.id
SET a.we_rule3 = (
    -- Upper side: 4 of 5 points above +1 sigma
    -- 上侧：5点中4点高于+1sigma
    (   (CASE WHEN b.z0 > 1 THEN 1 ELSE 0 END)
      + (CASE WHEN b.z1 > 1 THEN 1 ELSE 0 END)
      + (CASE WHEN b.z2 > 1 THEN 1 ELSE 0 END)
      + (CASE WHEN b.z3 > 1 THEN 1 ELSE 0 END)
      + (CASE WHEN b.z4 > 1 THEN 1 ELSE 0 END)
    ) >= 4
    OR
    -- Lower side: 4 of 5 points below -1 sigma
    -- 下侧：5点中4点低于-1sigma
    (   (CASE WHEN b.z0 < -1 THEN 1 ELSE 0 END)
      + (CASE WHEN b.z1 < -1 THEN 1 ELSE 0 END)
      + (CASE WHEN b.z2 < -1 THEN 1 ELSE 0 END)
      + (CASE WHEN b.z3 < -1 THEN 1 ELSE 0 END)
      + (CASE WHEN b.z4 < -1 THEN 1 ELSE 0 END)
    ) >= 4
)
WHERE b.z0 IS NOT NULL
  AND b.z1 IS NOT NULL
  AND b.z2 IS NOT NULL
  AND b.z3 IS NOT NULL
  AND b.z4 IS NOT NULL;


-- ─────────────────────────────────────────────────────
-- 3.4  WE Rule 4: 8 consecutive points on same side of center
-- WE规则4: 连续8点在中心线同侧
-- ─────────────────────────────────────────────────────
-- Check current point plus the seven preceding points.
-- All 8 must be on the same side of zero (all positive or all
-- negative z-scores). Under normality, the probability of 8
-- consecutive points on one side is (0.5)^8 = 0.39%.
-- 检查当前点加前七个点。全部8个必须在零的同侧
-- （全正或全负z分数）。在正态分布下，
-- 连续8点在一侧的概率为(0.5)^8 = 0.39%。
--
-- This rule detects sustained mean shifts where individual
-- points don't exceed sigma limits but collectively indicate
-- the process center has moved.
-- 此规则检测持续的均值偏移，其中单个点不超过sigma限
-- 但总体表明过程中心已移动。

UPDATE test.store_anomaly_scores a
JOIN (
    SELECT
        id,
        z_score                                                  AS z0,
        LAG(z_score, 1) OVER w AS z1,
        LAG(z_score, 2) OVER w AS z2,
        LAG(z_score, 3) OVER w AS z3,
        LAG(z_score, 4) OVER w AS z4,
        LAG(z_score, 5) OVER w AS z5,
        LAG(z_score, 6) OVER w AS z6,
        LAG(z_score, 7) OVER w AS z7
    FROM test.store_anomaly_scores
    WINDOW w AS (PARTITION BY store_id, metric_name ORDER BY metric_date)
) b ON a.id = b.id
SET a.we_rule4 = (
    -- All 8 points above center (all z > 0)
    -- 全部8点在中心线以上（全部z > 0）
    (    b.z0 > 0 AND b.z1 > 0 AND b.z2 > 0 AND b.z3 > 0
     AND b.z4 > 0 AND b.z5 > 0 AND b.z6 > 0 AND b.z7 > 0
    )
    OR
    -- All 8 points below center (all z < 0)
    -- 全部8点在中心线以下（全部z < 0）
    (    b.z0 < 0 AND b.z1 < 0 AND b.z2 < 0 AND b.z3 < 0
     AND b.z4 < 0 AND b.z5 < 0 AND b.z6 < 0 AND b.z7 < 0
    )
)
WHERE b.z0 IS NOT NULL
  AND b.z1 IS NOT NULL
  AND b.z2 IS NOT NULL
  AND b.z3 IS NOT NULL
  AND b.z4 IS NOT NULL
  AND b.z5 IS NOT NULL
  AND b.z6 IS NOT NULL
  AND b.z7 IS NOT NULL;


-- ─────────────────────────────────────────────────────
-- 3.5  WE Rule 5: 6 consecutive declining points
-- WE规则5: 连续6点递减
-- ─────────────────────────────────────────────────────
-- Check current point plus the five preceding points.
-- The metric_value must be monotonically decreasing across
-- all 6 points: v5 > v4 > v3 > v2 > v1 > v0.
-- 检查当前点加前五个点。metric_value必须在全部6个点上
-- 单调递减：v5 > v4 > v3 > v2 > v1 > v0。
--
-- This rule detects systematic trends that may indicate
-- gradual equipment degradation, declining customer satisfaction,
-- or creeping operational issues. A monotonic run of 6 points
-- is unlikely in a stationary process.
-- 此规则检测可能表示设备逐渐退化、客户满意度下降或
-- 运营问题蔓延的系统性趋势。在平稳过程中，
-- 连续6点的单调运行是不太可能的。
--
-- NOTE: We compare metric_value (not z_score) because the raw
-- trend is what we care about for this rule.
-- 注意：我们比较的是metric_value（不是z_score），因为
-- 此规则关注的是原始趋势。

UPDATE test.store_anomaly_scores a
JOIN (
    SELECT
        id,
        metric_value                                             AS v0,
        LAG(metric_value, 1) OVER w AS v1,
        LAG(metric_value, 2) OVER w AS v2,
        LAG(metric_value, 3) OVER w AS v3,
        LAG(metric_value, 4) OVER w AS v4,
        LAG(metric_value, 5) OVER w AS v5
    FROM test.store_anomaly_scores
    WINDOW w AS (PARTITION BY store_id, metric_name ORDER BY metric_date)
) b ON a.id = b.id
SET a.we_rule5 = (
    -- Monotonic decrease: each predecessor is greater than its successor
    -- 单调递减：每个前驱大于其后继
        b.v5 > b.v4
    AND b.v4 > b.v3
    AND b.v3 > b.v2
    AND b.v2 > b.v1
    AND b.v1 > b.v0
)
WHERE b.v0 IS NOT NULL
  AND b.v1 IS NOT NULL
  AND b.v2 IS NOT NULL
  AND b.v3 IS NOT NULL
  AND b.v4 IS NOT NULL
  AND b.v5 IS NOT NULL;


-- ############################################################
-- SECTION 4: ANOMALY SEVERITY CLASSIFICATION
-- 第四节: 异常严重度分类
-- ############################################################
--
-- Classify each row into a severity tier based on which
-- Western Electric rules were violated. The hierarchy is:
-- 根据违反的西部电气规则将每行分类到严重度等级。层级为:
--
--   CRITICAL : Rule 1 triggered (single point beyond 3 sigma)
--              规则1触发（单点超过3sigma）
--              This represents an extreme deviation requiring
--              immediate attention.
--              这代表需要立即关注的极端偏差。
--
--   WARNING  : Rule 2 or Rule 3 triggered
--              规则2或规则3触发
--              (2-of-3 beyond 2sigma, or 4-of-5 beyond 1sigma)
--              Emerging pattern that should be investigated within
--              the current shift or business day.
--              应在当前班次或工作日内调查的新出现模式。
--
--   INFO     : Rule 4 or Rule 5 triggered
--              规则4或规则5触发
--              (8 consecutive same side, or 6 declining)
--              Trend or shift pattern that should be monitored.
--              Should be reviewed during weekly operations meetings.
--              应持续监控的趋势或偏移模式。
--              应在每周运营会议上审查。
--
--   NONE     : No rules triggered — process appears in control
--              无规则触发 — 过程看似受控
--
-- Priority ordering: CRITICAL > WARNING > INFO > NONE
-- If multiple rules are triggered, the highest severity wins.
-- 优先级排序：CRITICAL > WARNING > INFO > NONE
-- 如果多条规则同时触发，取最高严重度。
-- ############################################################

UPDATE test.store_anomaly_scores
SET anomaly_severity = CASE
    -- Highest priority: beyond 3 sigma / 最高优先级：超过3sigma
    WHEN we_rule1 = TRUE
        THEN 'CRITICAL'

    -- Medium priority: 2-of-3 or 4-of-5 patterns / 中等优先级：2/3或4/5模式
    WHEN we_rule2 = TRUE OR we_rule3 = TRUE
        THEN 'WARNING'

    -- Lower priority: sustained shift or declining trend / 较低优先级：持续偏移或下降趋势
    WHEN we_rule4 = TRUE OR we_rule5 = TRUE
        THEN 'INFO'

    -- No anomaly detected / 未检测到异常
    ELSE 'NONE'
END
WHERE z_score IS NOT NULL;


-- ############################################################
-- SECTION 5: VERIFICATION & QA QUERIES
-- 第五节: 验证和质量保证查询
-- ############################################################
--
-- These queries validate the output of the anomaly scoring
-- pipeline. Run them after execution to confirm correctness.
-- 这些查询验证异常评分管道的输出。执行后运行以确认正确性。
-- ############################################################


-- ─────────────────────────────────────────────────────
-- 5.1  Anomaly count by severity level
-- 按严重度级别统计异常数量
-- ─────────────────────────────────────────────────────
-- Expected: Majority should be NONE; CRITICAL should be rare.
-- A healthy distribution might look like:
--   NONE: ~85-95%, INFO: ~3-8%, WARNING: ~1-4%, CRITICAL: ~0.5-2%
-- 预期：大部分应为NONE；CRITICAL应该很少。
-- 健康的分布可能是：
--   NONE: ~85-95%, INFO: ~3-8%, WARNING: ~1-4%, CRITICAL: ~0.5-2%

SELECT
    anomaly_severity,
    COUNT(*)                                                AS cnt,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)     AS pct
FROM test.store_anomaly_scores
GROUP BY anomaly_severity
ORDER BY FIELD(anomaly_severity, 'CRITICAL', 'WARNING', 'INFO', 'NONE');


-- ─────────────────────────────────────────────────────
-- 5.2  Anomaly count by severity and metric
-- 按严重度和指标统计异常数量
-- ─────────────────────────────────────────────────────
-- Helps identify which metrics are most frequently anomalous.
-- If one metric dominates CRITICAL, it may need baseline recalibration.
-- 帮助识别哪些指标最频繁异常。
-- 如果某个指标主导CRITICAL，可能需要重新校准基线。

SELECT
    metric_name,
    SUM(CASE WHEN anomaly_severity = 'CRITICAL' THEN 1 ELSE 0 END) AS critical_cnt,
    SUM(CASE WHEN anomaly_severity = 'WARNING'  THEN 1 ELSE 0 END) AS warning_cnt,
    SUM(CASE WHEN anomaly_severity = 'INFO'     THEN 1 ELSE 0 END) AS info_cnt,
    SUM(CASE WHEN anomaly_severity = 'NONE'     THEN 1 ELSE 0 END) AS none_cnt,
    COUNT(*)                                                        AS total
FROM test.store_anomaly_scores
GROUP BY metric_name
ORDER BY critical_cnt DESC, warning_cnt DESC;


-- ─────────────────────────────────────────────────────
-- 5.3  Western Electric rule trigger counts
-- 西部电气规则触发计数
-- ─────────────────────────────────────────────────────
-- Shows how frequently each WE rule fires. If Rule 4 (8 consec.)
-- fires very often, the rolling window may need to be lengthened
-- to better capture the process mean.
-- 显示每条WE规则触发的频率。如果规则4（连续8点）
-- 触发非常频繁，滚动窗口可能需要延长以更好地捕捉过程均值。

SELECT
    'WE Rule 1: Beyond 3σ'           AS rule_description,
    SUM(we_rule1)                     AS trigger_count,
    COUNT(*)                          AS total_rows,
    ROUND(100.0 * SUM(we_rule1) / COUNT(*), 3) AS trigger_pct
FROM test.store_anomaly_scores
WHERE z_score IS NOT NULL

UNION ALL

SELECT
    'WE Rule 2: 2/3 beyond 2σ'      AS rule_description,
    SUM(we_rule2)                     AS trigger_count,
    COUNT(*)                          AS total_rows,
    ROUND(100.0 * SUM(we_rule2) / COUNT(*), 3) AS trigger_pct
FROM test.store_anomaly_scores
WHERE z_score IS NOT NULL

UNION ALL

SELECT
    'WE Rule 3: 4/5 beyond 1σ'      AS rule_description,
    SUM(we_rule3)                     AS trigger_count,
    COUNT(*)                          AS total_rows,
    ROUND(100.0 * SUM(we_rule3) / COUNT(*), 3) AS trigger_pct
FROM test.store_anomaly_scores
WHERE z_score IS NOT NULL

UNION ALL

SELECT
    'WE Rule 4: 8 consecutive'       AS rule_description,
    SUM(we_rule4)                     AS trigger_count,
    COUNT(*)                          AS total_rows,
    ROUND(100.0 * SUM(we_rule4) / COUNT(*), 3) AS trigger_pct
FROM test.store_anomaly_scores
WHERE z_score IS NOT NULL

UNION ALL

SELECT
    'WE Rule 5: 6 declining'         AS rule_description,
    SUM(we_rule5)                     AS trigger_count,
    COUNT(*)                          AS total_rows,
    ROUND(100.0 * SUM(we_rule5) / COUNT(*), 3) AS trigger_pct
FROM test.store_anomaly_scores
WHERE z_score IS NOT NULL;


-- ─────────────────────────────────────────────────────
-- 5.4  8th Ave store (store_id=1127) revenue anomaly timeline
-- 第八大道门店(store_id=1127)收入异常时间线
-- ─────────────────────────────────────────────────────
-- 8th Ave is a flagship store. Check its revenue anomaly pattern
-- to validate that the model produces reasonable results.
-- 第八大道是旗舰门店。检查其收入异常模式以验证模型产生合理结果。
--
-- Look for:
-- 检查项目:
--   1. Z-scores roughly between -3 and +3 most of the time
--      Z分数大部分时间大致在-3到+3之间
--   2. CRITICAL alerts should be rare (a few per quarter)
--      CRITICAL警报应该很少（每季度几个）
--   3. DOW z-scores should differ from raw z-scores for weekdays vs weekends
--      工作日和周末的DOW z分数应与原始z分数不同

SELECT
    metric_date,
    metric_value,
    ROUND(rolling_mean_28d, 2)    AS mean_28d,
    ROUND(z_score, 2)             AS z_score,
    ROUND(dow_z_score, 2)         AS dow_z,
    we_rule1, we_rule2, we_rule3, we_rule4, we_rule5,
    anomaly_severity
FROM test.store_anomaly_scores
WHERE store_id    = 1127
  AND metric_name = 'total_revenue'
ORDER BY metric_date DESC
LIMIT 60;


-- ─────────────────────────────────────────────────────
-- 5.5  Z-score distribution check (should be roughly normal)
-- Z分数分布检查（应大致呈正态分布）
-- ─────────────────────────────────────────────────────
-- Bucket z-scores into ranges and count. A well-behaved SPC
-- model should produce a roughly bell-shaped distribution.
-- 将z分数分桶并计数。表现良好的SPC模型应产生大致钟形分布。
--
-- Expected approximate distribution for normal data:
-- 正态数据的预期近似分布:
--   |z| <= 1 : ~68.3%
--   1 < |z| <= 2 : ~27.2%
--   2 < |z| <= 3 : ~4.3%
--   |z| > 3 : ~0.3%

SELECT
    CASE
        WHEN z_score IS NULL            THEN 'NULL'
        WHEN ABS(z_score) <= 1          THEN '|z| <= 1  (within 1σ)'
        WHEN ABS(z_score) <= 2          THEN '1 < |z| <= 2  (1σ-2σ)'
        WHEN ABS(z_score) <= 3          THEN '2 < |z| <= 3  (2σ-3σ)'
        ELSE                                 '|z| > 3  (beyond 3σ)'
    END                                                     AS z_bucket,
    COUNT(*)                                                AS cnt,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)     AS pct
FROM test.store_anomaly_scores
GROUP BY z_bucket
ORDER BY FIELD(z_bucket,
    '|z| <= 1  (within 1σ)',
    '1 < |z| <= 2  (1σ-2σ)',
    '2 < |z| <= 3  (2σ-3σ)',
    '|z| > 3  (beyond 3σ)',
    'NULL'
);


-- ─────────────────────────────────────────────────────
-- 5.6  Top 10 most anomalous store-days (by severity + z-score)
-- 最异常的10个门店日（按严重度+z分数）
-- ─────────────────────────────────────────────────────
-- Useful for spot-checking whether the CRITICAL and WARNING
-- labels make operational sense.
-- 用于抽查CRITICAL和WARNING标签是否具有运营意义。

SELECT
    store_id,
    store_name,
    metric_date,
    metric_name,
    ROUND(metric_value, 2)        AS metric_value,
    ROUND(rolling_mean_28d, 2)    AS mean_28d,
    ROUND(z_score, 2)             AS z_score,
    anomaly_severity,
    CONCAT_WS(', ',
        IF(we_rule1, 'R1:3σ',    NULL),
        IF(we_rule2, 'R2:2/3>2σ', NULL),
        IF(we_rule3, 'R3:4/5>1σ', NULL),
        IF(we_rule4, 'R4:8consec', NULL),
        IF(we_rule5, 'R5:6decl',  NULL)
    )                              AS rules_triggered
FROM test.store_anomaly_scores
WHERE anomaly_severity IN ('CRITICAL', 'WARNING')
ORDER BY
    FIELD(anomaly_severity, 'CRITICAL', 'WARNING'),
    ABS(z_score) DESC
LIMIT 10;


-- ─────────────────────────────────────────────────────
-- 5.7  Per-store anomaly summary (latest 30 days)
-- 每门店异常汇总（最近30天）
-- ─────────────────────────────────────────────────────
-- Summarize anomaly counts per store over the past 30 days.
-- Stores with many anomalies across multiple metrics may need
-- comprehensive operational review.
-- 汇总过去30天每门店的异常计数。
-- 多指标频繁异常的门店可能需要全面运营审查。

SELECT
    store_id,
    store_name,
    SUM(CASE WHEN anomaly_severity = 'CRITICAL' THEN 1 ELSE 0 END) AS critical_30d,
    SUM(CASE WHEN anomaly_severity = 'WARNING'  THEN 1 ELSE 0 END) AS warning_30d,
    SUM(CASE WHEN anomaly_severity = 'INFO'     THEN 1 ELSE 0 END) AS info_30d,
    COUNT(DISTINCT CASE WHEN anomaly_severity != 'NONE'
                        THEN metric_name END)                       AS metrics_affected,
    COUNT(DISTINCT CASE WHEN anomaly_severity != 'NONE'
                        THEN metric_date END)                       AS anomaly_days
FROM test.store_anomaly_scores
WHERE metric_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY store_id, store_name
HAVING critical_30d > 0 OR warning_30d > 0
ORDER BY critical_30d DESC, warning_30d DESC
LIMIT 20;


-- ─────────────────────────────────────────────────────
-- 5.8  DOW Z-score vs Raw Z-score comparison
-- 星期Z分数与原始Z分数对比
-- ─────────────────────────────────────────────────────
-- Compare raw z_score to dow_z_score. The DOW-adjusted score
-- should be smaller (closer to zero) for expected day-of-week
-- variation and larger when the deviation goes beyond DOW norms.
-- 比较原始z_score和dow_z_score。DOW调整后的分数对于预期的
-- 星期变化应更小（更接近零），而当偏差超出DOW规范时应更大。
--
-- Example: A Saturday revenue of $12,000 might have z=-1.5 vs
-- the 28-day mean, but dow_z=+0.3 vs other Saturdays (normal).
-- 示例：周六收入$12,000相对28天均值可能z=-1.5，
-- 但相对其他周六dow_z=+0.3（正常）。

SELECT
    DAYOFWEEK(metric_date)                                  AS dow_num,
    CASE DAYOFWEEK(metric_date)
        WHEN 1 THEN 'Sun' WHEN 2 THEN 'Mon'
        WHEN 3 THEN 'Tue' WHEN 4 THEN 'Wed'
        WHEN 5 THEN 'Thu' WHEN 6 THEN 'Fri'
        WHEN 7 THEN 'Sat'
    END                                                     AS dow_name,
    metric_name,
    ROUND(AVG(ABS(z_score)), 3)                             AS avg_abs_z,
    ROUND(AVG(ABS(dow_z_score)), 3)                         AS avg_abs_dow_z,
    ROUND(AVG(ABS(z_score)) - AVG(ABS(dow_z_score)), 3)    AS z_improvement,
    COUNT(*)                                                AS row_cnt
FROM test.store_anomaly_scores
WHERE z_score IS NOT NULL
  AND dow_z_score IS NOT NULL
GROUP BY dow_num, dow_name, metric_name
ORDER BY metric_name, dow_num;


-- ─────────────────────────────────────────────────────
-- 5.9  Row count sanity check
-- 行数完整性检查
-- ─────────────────────────────────────────────────────
-- Verify that the number of rows in store_anomaly_scores
-- approximately equals: (stores) x (days) x (8 metrics).
-- 验证store_anomaly_scores中的行数大约等于：
-- （门店数）x（天数）x（8个指标）。

SELECT
    'store_anomaly_scores'                                  AS table_name,
    COUNT(*)                                                AS total_rows,
    COUNT(DISTINCT store_id)                                AS distinct_stores,
    COUNT(DISTINCT metric_date)                             AS distinct_dates,
    COUNT(DISTINCT metric_name)                             AS distinct_metrics,
    MIN(metric_date)                                        AS min_date,
    MAX(metric_date)                                        AS max_date,
    SUM(CASE WHEN z_score IS NULL THEN 1 ELSE 0 END)       AS null_z_scores,
    SUM(CASE WHEN dow_z_score IS NULL THEN 1 ELSE 0 END)   AS null_dow_z_scores
FROM test.store_anomaly_scores;


-- ─────────────────────────────────────────────────────
-- 5.10 Control limit width check
-- 控制限宽度检查
-- ─────────────────────────────────────────────────────
-- Verify that control limits have reasonable widths.
-- Very narrow limits (std ≈ 0) may indicate insufficient data
-- or a metric with near-zero variance. Very wide limits may
-- indicate highly volatile metrics needing different treatment.
-- 验证控制限具有合理的宽度。
-- 非常窄的限（std ≈ 0）可能表示数据不足或方差接近零的指标。
-- 非常宽的限可能表示高度波动的指标需要不同处理。

SELECT
    metric_name,
    ROUND(AVG(rolling_std_28d), 2)                          AS avg_std,
    ROUND(MIN(rolling_std_28d), 2)                          AS min_std,
    ROUND(MAX(rolling_std_28d), 2)                          AS max_std,
    ROUND(AVG(ucl_3sigma - lcl_3sigma), 2)                  AS avg_control_width,
    SUM(CASE WHEN rolling_std_28d < 0.01 THEN 1 ELSE 0 END) AS near_zero_std_cnt
FROM test.store_anomaly_scores
WHERE rolling_std_28d IS NOT NULL
GROUP BY metric_name
ORDER BY metric_name;


-- ############################################################
-- END OF SCRIPT
-- 脚本结束
-- ############################################################
--
-- Summary of operations performed / 执行的操作摘要:
--   1. Truncated store_anomaly_scores (idempotent reset)
--      截断store_anomaly_scores（幂等重置）
--   2. Inserted 8 metrics x (stores x days) rows with 28-day rolling stats
--      插入8个指标 x (门店数 x 天数)行及28天滚动统计
--   3. Computed z-scores and 2σ/3σ control limits
--      计算z分数和2σ/3σ控制限
--   4. Computed day-of-week adjusted z-scores (8-week window)
--      计算星期调整z分数（8周窗口）
--   5. Evaluated 5 Western Electric rules per row
--      对每行评估5条西部电气规则
--   6. Classified anomaly severity (CRITICAL/WARNING/INFO/NONE)
--      分类异常严重度（CRITICAL/WARNING/INFO/NONE）
--   7. Ran verification queries for data quality assurance
--      运行验证查询进行数据质量保证
--
-- Next Steps / 后续步骤:
--   - Run 06_compute_health_scores.sql to aggregate into composite scores
--     运行06_compute_health_scores.sql聚合为综合评分
--   - Run 07_generate_alerts.sql to create alert records
--     运行07_generate_alerts.sql创建预警记录
--   - Review verification query outputs for data quality issues
--     审查验证查询输出以发现数据质量问题
--
-- ============================================================
-- END — UC-OP-02 Store Performance Anomaly Scoring Engine
-- 结束 — UC-OP-02 门店绩效异常评分引擎
-- ============================================================

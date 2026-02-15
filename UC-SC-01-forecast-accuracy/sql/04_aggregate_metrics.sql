-- ============================================================================
-- UC-SC-01 Forecast Accuracy Monitor
-- 04_aggregate_metrics.sql - Multi-Dimensional Aggregated Metrics
-- 多维度聚合指标计算
-- ============================================================================
-- Purpose:  Compute aggregated forecast accuracy metrics from the daily detail
--           table (test.forecast_accuracy_daily) into the summary table
--           (test.forecast_accuracy_summary) across multiple period types
--           and dimension cuts.
-- 目的:     从每日明细表 (test.forecast_accuracy_daily) 计算聚合预测准确性指标，
--           写入汇总表 (test.forecast_accuracy_summary)，覆盖多种时间周期和维度切面。
--
-- Target Server: aws-luckyus-dbatest-rw
-- Target Schema: test
--
-- Period Types / 周期类型:
--   DAILY        - Single day / 单日
--   WEEKLY       - ISO week (Mon-Sun) / ISO周（周一至周日）
--   MONTHLY      - Calendar month / 日历月
--   ROLLING_7D   - Trailing 7-day rolling window / 滚动7天窗口
--   ROLLING_30D  - Trailing 30-day rolling window / 滚动30天窗口
--
-- Dimension Types / 维度类型:
--   OVERALL      - All stores, all products / 全部门店、全部商品
--   STORE        - Per store / 按门店
--   PRODUCT      - Per SKU (goods_code) / 按SKU
--   CATEGORY     - Per large category / 按大类
--   DOW          - Per day-of-week / 按星期几
--
-- Metrics Formulas / 指标公式:
--   MAPE           = AVG(absolute_pct_error) WHERE actual > 0
--   WMAPE          = SUM(absolute_error) / SUM(actual_consumption)
--   RMSE           = SQRT(AVG(squared_error))
--   MFE (Bias)     = AVG(forecast_error)
--   accuracy_rate_20 = % of records with APE <= 20%
--   tracking_signal  = SUM(forecast_error) / AVG(absolute_error)
--   coverage_pct   = matched predictions / total predictions
--
-- Parameters (set by orchestrator):
--   @calc_date_start  DATE  - Start of calculation window (inclusive)
--   @calc_date_end    DATE  - End of calculation window (inclusive)
--
-- Author:   Data Engineering / BI Team
-- Created:  2026-02-15
-- ============================================================================

-- SET @calc_date_start = '2026-02-01';
-- SET @calc_date_end   = '2026-02-14';


-- ############################################################################
-- IDEMPOTENCY: Delete existing summary rows for recalculation range
-- 幂等性: 删除重新计算范围内已有的汇总行
-- ############################################################################
-- Delete summaries whose period overlaps the recalculation window.
-- For rolling windows, we delete rows whose period_end falls within the range.
-- 删除周期与重新计算窗口重叠的汇总记录。
-- 对于滚动窗口，删除 period_end 在范围内的行。

DELETE FROM test.forecast_accuracy_summary
WHERE period_end >= @calc_date_start
  AND period_start <= @calc_date_end;


-- ############################################################################
-- SECTION 1: DAILY x OVERALL / 每日 x 全局
-- ############################################################################
-- One row per day, aggregated across all stores and products.
-- 每天一行，跨所有门店和商品聚合。

INSERT INTO test.forecast_accuracy_summary (
    period_type, period_start, period_end,
    dimension_type, dimension_value, dimension_name,
    mape, wmape, rmse, mfe,
    accuracy_rate_20, tracking_signal,
    prediction_count, coverage_pct, avg_actual,
    computed_at
)
SELECT
    'DAILY'                                                         AS period_type,
    d.accuracy_date                                                 AS period_start,
    d.accuracy_date                                                 AS period_end,
    'OVERALL'                                                       AS dimension_type,
    'ALL'                                                           AS dimension_value,
    'All Stores & Products'                                         AS dimension_name,

    -- MAPE: Mean Absolute Percentage Error (exclude zero-actual rows)
    -- MAPE: 平均绝对百分比误差（排除实际值为0的行）
    ROUND(AVG(CASE WHEN d.actual_consumption > 0 THEN d.absolute_pct_error END), 4)
                                                                    AS mape,

    -- WMAPE: Weighted MAPE = SUM(|error|) / SUM(actual)
    -- WMAPE: 加权MAPE = SUM(|误差|) / SUM(实际值)
    ROUND(SUM(d.absolute_error) / NULLIF(SUM(d.actual_consumption), 0), 4)
                                                                    AS wmape,

    -- RMSE: Root Mean Squared Error
    -- RMSE: 均方根误差
    ROUND(SQRT(AVG(d.squared_error)), 4)                            AS rmse,

    -- MFE (Bias): Mean Forecast Error (positive = systematic over-forecast)
    -- MFE (偏差): 平均预测误差（正值 = 系统性过度预测）
    ROUND(AVG(d.forecast_error), 4)                                 AS mfe,

    -- accuracy_rate_20: % of records within 20% tolerance
    -- accuracy_rate_20: 20%容差内命中率
    ROUND(SUM(CASE WHEN d.absolute_pct_error <= 0.20 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 4)                                   AS accuracy_rate_20,

    -- tracking_signal: Cumulative bias / MAD
    -- tracking_signal: 跟踪信号 = 累积偏差 / 平均绝对偏差
    ROUND(SUM(d.forecast_error) / NULLIF(AVG(d.absolute_error), 0), 4)
                                                                    AS tracking_signal,

    -- Volume / 量级
    COUNT(*)                                                        AS prediction_count,

    -- coverage_pct: placeholder (computed separately in drift detection)
    -- coverage_pct: 占位符（在漂移检测中单独计算）
    NULL                                                            AS coverage_pct,

    ROUND(AVG(d.actual_consumption), 2)                             AS avg_actual,
    NOW()                                                           AS computed_at

FROM test.forecast_accuracy_daily d
WHERE d.accuracy_date >= @calc_date_start
  AND d.accuracy_date <= @calc_date_end
GROUP BY d.accuracy_date;


-- ############################################################################
-- SECTION 2: DAILY x STORE / 每日 x 门店
-- ############################################################################
-- One row per (day, store) combination.
-- 每个(日期, 门店)组合一行。

INSERT INTO test.forecast_accuracy_summary (
    period_type, period_start, period_end,
    dimension_type, dimension_value, dimension_name,
    mape, wmape, rmse, mfe,
    accuracy_rate_20, tracking_signal,
    prediction_count, coverage_pct, avg_actual,
    computed_at
)
SELECT
    'DAILY'                                                         AS period_type,
    d.accuracy_date                                                 AS period_start,
    d.accuracy_date                                                 AS period_end,
    'STORE'                                                         AS dimension_type,
    CAST(d.shop_dept_id AS CHAR)                                    AS dimension_value,
    MAX(d.shop_name)                                                AS dimension_name,

    ROUND(AVG(CASE WHEN d.actual_consumption > 0 THEN d.absolute_pct_error END), 4) AS mape,
    ROUND(SUM(d.absolute_error) / NULLIF(SUM(d.actual_consumption), 0), 4) AS wmape,
    ROUND(SQRT(AVG(d.squared_error)), 4)                            AS rmse,
    ROUND(AVG(d.forecast_error), 4)                                 AS mfe,
    ROUND(SUM(CASE WHEN d.absolute_pct_error <= 0.20 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 4)                                   AS accuracy_rate_20,
    ROUND(SUM(d.forecast_error) / NULLIF(AVG(d.absolute_error), 0), 4) AS tracking_signal,
    COUNT(*)                                                        AS prediction_count,
    NULL                                                            AS coverage_pct,
    ROUND(AVG(d.actual_consumption), 2)                             AS avg_actual,
    NOW()                                                           AS computed_at

FROM test.forecast_accuracy_daily d
WHERE d.accuracy_date >= @calc_date_start
  AND d.accuracy_date <= @calc_date_end
GROUP BY d.accuracy_date, d.shop_dept_id;


-- ############################################################################
-- SECTION 3: DAILY x PRODUCT / 每日 x 商品
-- ############################################################################
-- One row per (day, goods_code) across all stores.
-- 每个(日期, 商品编码)组合一行，跨所有门店。

INSERT INTO test.forecast_accuracy_summary (
    period_type, period_start, period_end,
    dimension_type, dimension_value, dimension_name,
    mape, wmape, rmse, mfe,
    accuracy_rate_20, tracking_signal,
    prediction_count, coverage_pct, avg_actual,
    computed_at
)
SELECT
    'DAILY'                                                         AS period_type,
    d.accuracy_date                                                 AS period_start,
    d.accuracy_date                                                 AS period_end,
    'PRODUCT'                                                       AS dimension_type,
    d.goods_code                                                    AS dimension_value,
    MAX(d.goods_name)                                               AS dimension_name,

    ROUND(AVG(CASE WHEN d.actual_consumption > 0 THEN d.absolute_pct_error END), 4) AS mape,
    ROUND(SUM(d.absolute_error) / NULLIF(SUM(d.actual_consumption), 0), 4) AS wmape,
    ROUND(SQRT(AVG(d.squared_error)), 4)                            AS rmse,
    ROUND(AVG(d.forecast_error), 4)                                 AS mfe,
    ROUND(SUM(CASE WHEN d.absolute_pct_error <= 0.20 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 4)                                   AS accuracy_rate_20,
    ROUND(SUM(d.forecast_error) / NULLIF(AVG(d.absolute_error), 0), 4) AS tracking_signal,
    COUNT(*)                                                        AS prediction_count,
    NULL                                                            AS coverage_pct,
    ROUND(AVG(d.actual_consumption), 2)                             AS avg_actual,
    NOW()                                                           AS computed_at

FROM test.forecast_accuracy_daily d
WHERE d.accuracy_date >= @calc_date_start
  AND d.accuracy_date <= @calc_date_end
GROUP BY d.accuracy_date, d.goods_code;


-- ############################################################################
-- SECTION 4: DAILY x CATEGORY / 每日 x 品类
-- ############################################################################
-- One row per (day, large_class_name) across all stores and SKUs.
-- 每个(日期, 大类名称)组合一行，跨所有门店和SKU。

INSERT INTO test.forecast_accuracy_summary (
    period_type, period_start, period_end,
    dimension_type, dimension_value, dimension_name,
    mape, wmape, rmse, mfe,
    accuracy_rate_20, tracking_signal,
    prediction_count, coverage_pct, avg_actual,
    computed_at
)
SELECT
    'DAILY'                                                         AS period_type,
    d.accuracy_date                                                 AS period_start,
    d.accuracy_date                                                 AS period_end,
    'CATEGORY'                                                      AS dimension_type,
    COALESCE(d.large_class_name, 'UNKNOWN')                         AS dimension_value,
    COALESCE(d.large_class_name, 'Unknown Category')                AS dimension_name,

    ROUND(AVG(CASE WHEN d.actual_consumption > 0 THEN d.absolute_pct_error END), 4) AS mape,
    ROUND(SUM(d.absolute_error) / NULLIF(SUM(d.actual_consumption), 0), 4) AS wmape,
    ROUND(SQRT(AVG(d.squared_error)), 4)                            AS rmse,
    ROUND(AVG(d.forecast_error), 4)                                 AS mfe,
    ROUND(SUM(CASE WHEN d.absolute_pct_error <= 0.20 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 4)                                   AS accuracy_rate_20,
    ROUND(SUM(d.forecast_error) / NULLIF(AVG(d.absolute_error), 0), 4) AS tracking_signal,
    COUNT(*)                                                        AS prediction_count,
    NULL                                                            AS coverage_pct,
    ROUND(AVG(d.actual_consumption), 2)                             AS avg_actual,
    NOW()                                                           AS computed_at

FROM test.forecast_accuracy_daily d
WHERE d.accuracy_date >= @calc_date_start
  AND d.accuracy_date <= @calc_date_end
GROUP BY d.accuracy_date, d.large_class_name;


-- ############################################################################
-- SECTION 5: DAILY x DOW (Day of Week) / 每日 x 星期几
-- ############################################################################
-- Aggregated by day-of-week (1=Sunday, 7=Saturday in MySQL DAYOFWEEK()).
-- We use DAYNAME() for readability.
-- 按星期几聚合（MySQL DAYOFWEEK(): 1=周日, 7=周六）。
-- 使用 DAYNAME() 增加可读性。

INSERT INTO test.forecast_accuracy_summary (
    period_type, period_start, period_end,
    dimension_type, dimension_value, dimension_name,
    mape, wmape, rmse, mfe,
    accuracy_rate_20, tracking_signal,
    prediction_count, coverage_pct, avg_actual,
    computed_at
)
SELECT
    'DAILY'                                                         AS period_type,
    d.accuracy_date                                                 AS period_start,
    d.accuracy_date                                                 AS period_end,
    'DOW'                                                           AS dimension_type,
    CAST(DAYOFWEEK(d.accuracy_date) AS CHAR)                        AS dimension_value,
    DAYNAME(d.accuracy_date)                                        AS dimension_name,

    ROUND(AVG(CASE WHEN d.actual_consumption > 0 THEN d.absolute_pct_error END), 4) AS mape,
    ROUND(SUM(d.absolute_error) / NULLIF(SUM(d.actual_consumption), 0), 4) AS wmape,
    ROUND(SQRT(AVG(d.squared_error)), 4)                            AS rmse,
    ROUND(AVG(d.forecast_error), 4)                                 AS mfe,
    ROUND(SUM(CASE WHEN d.absolute_pct_error <= 0.20 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 4)                                   AS accuracy_rate_20,
    ROUND(SUM(d.forecast_error) / NULLIF(AVG(d.absolute_error), 0), 4) AS tracking_signal,
    COUNT(*)                                                        AS prediction_count,
    NULL                                                            AS coverage_pct,
    ROUND(AVG(d.actual_consumption), 2)                             AS avg_actual,
    NOW()                                                           AS computed_at

FROM test.forecast_accuracy_daily d
WHERE d.accuracy_date >= @calc_date_start
  AND d.accuracy_date <= @calc_date_end
GROUP BY d.accuracy_date, DAYOFWEEK(d.accuracy_date), DAYNAME(d.accuracy_date);


-- ############################################################################
-- SECTION 6: WEEKLY x OVERALL / 每周 x 全局
-- ############################################################################
-- Aggregated by ISO week across all dimensions.
-- 按ISO周聚合，跨所有维度。

INSERT INTO test.forecast_accuracy_summary (
    period_type, period_start, period_end,
    dimension_type, dimension_value, dimension_name,
    mape, wmape, rmse, mfe,
    accuracy_rate_20, tracking_signal,
    prediction_count, coverage_pct, avg_actual,
    computed_at
)
SELECT
    'WEEKLY'                                                        AS period_type,
    -- ISO week starts Monday
    DATE_SUB(d.accuracy_date, INTERVAL (WEEKDAY(d.accuracy_date)) DAY) AS period_start,
    DATE_ADD(DATE_SUB(d.accuracy_date, INTERVAL (WEEKDAY(d.accuracy_date)) DAY), INTERVAL 6 DAY) AS period_end,
    'OVERALL'                                                       AS dimension_type,
    'ALL'                                                           AS dimension_value,
    CONCAT('Week ', YEARWEEK(d.accuracy_date, 1))                   AS dimension_name,

    ROUND(AVG(CASE WHEN d.actual_consumption > 0 THEN d.absolute_pct_error END), 4) AS mape,
    ROUND(SUM(d.absolute_error) / NULLIF(SUM(d.actual_consumption), 0), 4) AS wmape,
    ROUND(SQRT(AVG(d.squared_error)), 4)                            AS rmse,
    ROUND(AVG(d.forecast_error), 4)                                 AS mfe,
    ROUND(SUM(CASE WHEN d.absolute_pct_error <= 0.20 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 4)                                   AS accuracy_rate_20,
    ROUND(SUM(d.forecast_error) / NULLIF(AVG(d.absolute_error), 0), 4) AS tracking_signal,
    COUNT(*)                                                        AS prediction_count,
    NULL                                                            AS coverage_pct,
    ROUND(AVG(d.actual_consumption), 2)                             AS avg_actual,
    NOW()                                                           AS computed_at

FROM test.forecast_accuracy_daily d
WHERE d.accuracy_date >= @calc_date_start
  AND d.accuracy_date <= @calc_date_end
GROUP BY YEARWEEK(d.accuracy_date, 1),
         DATE_SUB(d.accuracy_date, INTERVAL (WEEKDAY(d.accuracy_date)) DAY);


-- ############################################################################
-- SECTION 7: WEEKLY x STORE / 每周 x 门店
-- ############################################################################

INSERT INTO test.forecast_accuracy_summary (
    period_type, period_start, period_end,
    dimension_type, dimension_value, dimension_name,
    mape, wmape, rmse, mfe,
    accuracy_rate_20, tracking_signal,
    prediction_count, coverage_pct, avg_actual,
    computed_at
)
SELECT
    'WEEKLY'                                                        AS period_type,
    DATE_SUB(d.accuracy_date, INTERVAL (WEEKDAY(d.accuracy_date)) DAY) AS period_start,
    DATE_ADD(DATE_SUB(d.accuracy_date, INTERVAL (WEEKDAY(d.accuracy_date)) DAY), INTERVAL 6 DAY) AS period_end,
    'STORE'                                                         AS dimension_type,
    CAST(d.shop_dept_id AS CHAR)                                    AS dimension_value,
    MAX(d.shop_name)                                                AS dimension_name,

    ROUND(AVG(CASE WHEN d.actual_consumption > 0 THEN d.absolute_pct_error END), 4) AS mape,
    ROUND(SUM(d.absolute_error) / NULLIF(SUM(d.actual_consumption), 0), 4) AS wmape,
    ROUND(SQRT(AVG(d.squared_error)), 4)                            AS rmse,
    ROUND(AVG(d.forecast_error), 4)                                 AS mfe,
    ROUND(SUM(CASE WHEN d.absolute_pct_error <= 0.20 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 4)                                   AS accuracy_rate_20,
    ROUND(SUM(d.forecast_error) / NULLIF(AVG(d.absolute_error), 0), 4) AS tracking_signal,
    COUNT(*)                                                        AS prediction_count,
    NULL                                                            AS coverage_pct,
    ROUND(AVG(d.actual_consumption), 2)                             AS avg_actual,
    NOW()                                                           AS computed_at

FROM test.forecast_accuracy_daily d
WHERE d.accuracy_date >= @calc_date_start
  AND d.accuracy_date <= @calc_date_end
GROUP BY YEARWEEK(d.accuracy_date, 1),
         DATE_SUB(d.accuracy_date, INTERVAL (WEEKDAY(d.accuracy_date)) DAY),
         d.shop_dept_id;


-- ############################################################################
-- SECTION 8: MONTHLY x OVERALL / 每月 x 全局
-- ############################################################################

INSERT INTO test.forecast_accuracy_summary (
    period_type, period_start, period_end,
    dimension_type, dimension_value, dimension_name,
    mape, wmape, rmse, mfe,
    accuracy_rate_20, tracking_signal,
    prediction_count, coverage_pct, avg_actual,
    computed_at
)
SELECT
    'MONTHLY'                                                       AS period_type,
    DATE_FORMAT(d.accuracy_date, '%Y-%m-01')                        AS period_start,
    LAST_DAY(d.accuracy_date)                                       AS period_end,
    'OVERALL'                                                       AS dimension_type,
    'ALL'                                                           AS dimension_value,
    DATE_FORMAT(d.accuracy_date, '%Y-%m')                           AS dimension_name,

    ROUND(AVG(CASE WHEN d.actual_consumption > 0 THEN d.absolute_pct_error END), 4) AS mape,
    ROUND(SUM(d.absolute_error) / NULLIF(SUM(d.actual_consumption), 0), 4) AS wmape,
    ROUND(SQRT(AVG(d.squared_error)), 4)                            AS rmse,
    ROUND(AVG(d.forecast_error), 4)                                 AS mfe,
    ROUND(SUM(CASE WHEN d.absolute_pct_error <= 0.20 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 4)                                   AS accuracy_rate_20,
    ROUND(SUM(d.forecast_error) / NULLIF(AVG(d.absolute_error), 0), 4) AS tracking_signal,
    COUNT(*)                                                        AS prediction_count,
    NULL                                                            AS coverage_pct,
    ROUND(AVG(d.actual_consumption), 2)                             AS avg_actual,
    NOW()                                                           AS computed_at

FROM test.forecast_accuracy_daily d
WHERE d.accuracy_date >= @calc_date_start
  AND d.accuracy_date <= @calc_date_end
GROUP BY DATE_FORMAT(d.accuracy_date, '%Y-%m-01'), LAST_DAY(d.accuracy_date);


-- ############################################################################
-- SECTION 9: MONTHLY x CATEGORY / 每月 x 品类
-- ############################################################################

INSERT INTO test.forecast_accuracy_summary (
    period_type, period_start, period_end,
    dimension_type, dimension_value, dimension_name,
    mape, wmape, rmse, mfe,
    accuracy_rate_20, tracking_signal,
    prediction_count, coverage_pct, avg_actual,
    computed_at
)
SELECT
    'MONTHLY'                                                       AS period_type,
    DATE_FORMAT(d.accuracy_date, '%Y-%m-01')                        AS period_start,
    LAST_DAY(d.accuracy_date)                                       AS period_end,
    'CATEGORY'                                                      AS dimension_type,
    COALESCE(d.large_class_name, 'UNKNOWN')                         AS dimension_value,
    COALESCE(d.large_class_name, 'Unknown Category')                AS dimension_name,

    ROUND(AVG(CASE WHEN d.actual_consumption > 0 THEN d.absolute_pct_error END), 4) AS mape,
    ROUND(SUM(d.absolute_error) / NULLIF(SUM(d.actual_consumption), 0), 4) AS wmape,
    ROUND(SQRT(AVG(d.squared_error)), 4)                            AS rmse,
    ROUND(AVG(d.forecast_error), 4)                                 AS mfe,
    ROUND(SUM(CASE WHEN d.absolute_pct_error <= 0.20 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 4)                                   AS accuracy_rate_20,
    ROUND(SUM(d.forecast_error) / NULLIF(AVG(d.absolute_error), 0), 4) AS tracking_signal,
    COUNT(*)                                                        AS prediction_count,
    NULL                                                            AS coverage_pct,
    ROUND(AVG(d.actual_consumption), 2)                             AS avg_actual,
    NOW()                                                           AS computed_at

FROM test.forecast_accuracy_daily d
WHERE d.accuracy_date >= @calc_date_start
  AND d.accuracy_date <= @calc_date_end
GROUP BY DATE_FORMAT(d.accuracy_date, '%Y-%m-01'), LAST_DAY(d.accuracy_date), d.large_class_name;


-- ############################################################################
-- SECTION 10: ROLLING_7D x STORE / 滚动7天 x 门店
-- ############################################################################
-- For each day in the range, compute metrics over the trailing 7 days per store.
-- Requires data for (calc_date - 6 days) through calc_date.
-- 对范围内的每一天，计算每个门店过去7天的滚动指标。
-- 需要 (calc_date - 6天) 到 calc_date 的数据。

INSERT INTO test.forecast_accuracy_summary (
    period_type, period_start, period_end,
    dimension_type, dimension_value, dimension_name,
    mape, wmape, rmse, mfe,
    accuracy_rate_20, tracking_signal,
    prediction_count, coverage_pct, avg_actual,
    computed_at
)
SELECT
    'ROLLING_7D'                                                    AS period_type,
    DATE_SUB(ref.ref_date, INTERVAL 6 DAY)                         AS period_start,
    ref.ref_date                                                    AS period_end,
    'STORE'                                                         AS dimension_type,
    CAST(d.shop_dept_id AS CHAR)                                    AS dimension_value,
    MAX(d.shop_name)                                                AS dimension_name,

    ROUND(AVG(CASE WHEN d.actual_consumption > 0 THEN d.absolute_pct_error END), 4) AS mape,
    ROUND(SUM(d.absolute_error) / NULLIF(SUM(d.actual_consumption), 0), 4) AS wmape,
    ROUND(SQRT(AVG(d.squared_error)), 4)                            AS rmse,
    ROUND(AVG(d.forecast_error), 4)                                 AS mfe,
    ROUND(SUM(CASE WHEN d.absolute_pct_error <= 0.20 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 4)                                   AS accuracy_rate_20,
    ROUND(SUM(d.forecast_error) / NULLIF(AVG(d.absolute_error), 0), 4) AS tracking_signal,
    COUNT(*)                                                        AS prediction_count,
    NULL                                                            AS coverage_pct,
    ROUND(AVG(d.actual_consumption), 2)                             AS avg_actual,
    NOW()                                                           AS computed_at

FROM (
    -- Generate reference dates within the calculation window
    -- 生成计算窗口内的参考日期
    SELECT DISTINCT accuracy_date AS ref_date
    FROM test.forecast_accuracy_daily
    WHERE accuracy_date >= @calc_date_start
      AND accuracy_date <= @calc_date_end
) ref
INNER JOIN test.forecast_accuracy_daily d
    ON d.accuracy_date BETWEEN DATE_SUB(ref.ref_date, INTERVAL 6 DAY) AND ref.ref_date
GROUP BY ref.ref_date, d.shop_dept_id;


-- ############################################################################
-- SECTION 11: ROLLING_7D x OVERALL / 滚动7天 x 全局
-- ############################################################################

INSERT INTO test.forecast_accuracy_summary (
    period_type, period_start, period_end,
    dimension_type, dimension_value, dimension_name,
    mape, wmape, rmse, mfe,
    accuracy_rate_20, tracking_signal,
    prediction_count, coverage_pct, avg_actual,
    computed_at
)
SELECT
    'ROLLING_7D'                                                    AS period_type,
    DATE_SUB(ref.ref_date, INTERVAL 6 DAY)                         AS period_start,
    ref.ref_date                                                    AS period_end,
    'OVERALL'                                                       AS dimension_type,
    'ALL'                                                           AS dimension_value,
    'All Stores & Products (7D Rolling)'                            AS dimension_name,

    ROUND(AVG(CASE WHEN d.actual_consumption > 0 THEN d.absolute_pct_error END), 4) AS mape,
    ROUND(SUM(d.absolute_error) / NULLIF(SUM(d.actual_consumption), 0), 4) AS wmape,
    ROUND(SQRT(AVG(d.squared_error)), 4)                            AS rmse,
    ROUND(AVG(d.forecast_error), 4)                                 AS mfe,
    ROUND(SUM(CASE WHEN d.absolute_pct_error <= 0.20 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 4)                                   AS accuracy_rate_20,
    ROUND(SUM(d.forecast_error) / NULLIF(AVG(d.absolute_error), 0), 4) AS tracking_signal,
    COUNT(*)                                                        AS prediction_count,
    NULL                                                            AS coverage_pct,
    ROUND(AVG(d.actual_consumption), 2)                             AS avg_actual,
    NOW()                                                           AS computed_at

FROM (
    SELECT DISTINCT accuracy_date AS ref_date
    FROM test.forecast_accuracy_daily
    WHERE accuracy_date >= @calc_date_start
      AND accuracy_date <= @calc_date_end
) ref
INNER JOIN test.forecast_accuracy_daily d
    ON d.accuracy_date BETWEEN DATE_SUB(ref.ref_date, INTERVAL 6 DAY) AND ref.ref_date
GROUP BY ref.ref_date;


-- ############################################################################
-- SECTION 12: ROLLING_30D x OVERALL / 滚动30天 x 全局
-- ############################################################################

INSERT INTO test.forecast_accuracy_summary (
    period_type, period_start, period_end,
    dimension_type, dimension_value, dimension_name,
    mape, wmape, rmse, mfe,
    accuracy_rate_20, tracking_signal,
    prediction_count, coverage_pct, avg_actual,
    computed_at
)
SELECT
    'ROLLING_30D'                                                   AS period_type,
    DATE_SUB(ref.ref_date, INTERVAL 29 DAY)                        AS period_start,
    ref.ref_date                                                    AS period_end,
    'OVERALL'                                                       AS dimension_type,
    'ALL'                                                           AS dimension_value,
    'All Stores & Products (30D Rolling)'                           AS dimension_name,

    ROUND(AVG(CASE WHEN d.actual_consumption > 0 THEN d.absolute_pct_error END), 4) AS mape,
    ROUND(SUM(d.absolute_error) / NULLIF(SUM(d.actual_consumption), 0), 4) AS wmape,
    ROUND(SQRT(AVG(d.squared_error)), 4)                            AS rmse,
    ROUND(AVG(d.forecast_error), 4)                                 AS mfe,
    ROUND(SUM(CASE WHEN d.absolute_pct_error <= 0.20 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 4)                                   AS accuracy_rate_20,
    ROUND(SUM(d.forecast_error) / NULLIF(AVG(d.absolute_error), 0), 4) AS tracking_signal,
    COUNT(*)                                                        AS prediction_count,
    NULL                                                            AS coverage_pct,
    ROUND(AVG(d.actual_consumption), 2)                             AS avg_actual,
    NOW()                                                           AS computed_at

FROM (
    SELECT DISTINCT accuracy_date AS ref_date
    FROM test.forecast_accuracy_daily
    WHERE accuracy_date >= @calc_date_start
      AND accuracy_date <= @calc_date_end
) ref
INNER JOIN test.forecast_accuracy_daily d
    ON d.accuracy_date BETWEEN DATE_SUB(ref.ref_date, INTERVAL 29 DAY) AND ref.ref_date
GROUP BY ref.ref_date;


-- ############################################################################
-- SECTION 13: ROLLING_30D x STORE / 滚动30天 x 门店
-- ############################################################################

INSERT INTO test.forecast_accuracy_summary (
    period_type, period_start, period_end,
    dimension_type, dimension_value, dimension_name,
    mape, wmape, rmse, mfe,
    accuracy_rate_20, tracking_signal,
    prediction_count, coverage_pct, avg_actual,
    computed_at
)
SELECT
    'ROLLING_30D'                                                   AS period_type,
    DATE_SUB(ref.ref_date, INTERVAL 29 DAY)                        AS period_start,
    ref.ref_date                                                    AS period_end,
    'STORE'                                                         AS dimension_type,
    CAST(d.shop_dept_id AS CHAR)                                    AS dimension_value,
    MAX(d.shop_name)                                                AS dimension_name,

    ROUND(AVG(CASE WHEN d.actual_consumption > 0 THEN d.absolute_pct_error END), 4) AS mape,
    ROUND(SUM(d.absolute_error) / NULLIF(SUM(d.actual_consumption), 0), 4) AS wmape,
    ROUND(SQRT(AVG(d.squared_error)), 4)                            AS rmse,
    ROUND(AVG(d.forecast_error), 4)                                 AS mfe,
    ROUND(SUM(CASE WHEN d.absolute_pct_error <= 0.20 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 4)                                   AS accuracy_rate_20,
    ROUND(SUM(d.forecast_error) / NULLIF(AVG(d.absolute_error), 0), 4) AS tracking_signal,
    COUNT(*)                                                        AS prediction_count,
    NULL                                                            AS coverage_pct,
    ROUND(AVG(d.actual_consumption), 2)                             AS avg_actual,
    NOW()                                                           AS computed_at

FROM (
    SELECT DISTINCT accuracy_date AS ref_date
    FROM test.forecast_accuracy_daily
    WHERE accuracy_date >= @calc_date_start
      AND accuracy_date <= @calc_date_end
) ref
INNER JOIN test.forecast_accuracy_daily d
    ON d.accuracy_date BETWEEN DATE_SUB(ref.ref_date, INTERVAL 29 DAY) AND ref.ref_date
GROUP BY ref.ref_date, d.shop_dept_id;


-- ############################################################################
-- SECTION 14: ROLLING_7D x CATEGORY / 滚动7天 x 品类
-- ############################################################################

INSERT INTO test.forecast_accuracy_summary (
    period_type, period_start, period_end,
    dimension_type, dimension_value, dimension_name,
    mape, wmape, rmse, mfe,
    accuracy_rate_20, tracking_signal,
    prediction_count, coverage_pct, avg_actual,
    computed_at
)
SELECT
    'ROLLING_7D'                                                    AS period_type,
    DATE_SUB(ref.ref_date, INTERVAL 6 DAY)                         AS period_start,
    ref.ref_date                                                    AS period_end,
    'CATEGORY'                                                      AS dimension_type,
    COALESCE(d.large_class_name, 'UNKNOWN')                         AS dimension_value,
    COALESCE(d.large_class_name, 'Unknown Category')                AS dimension_name,

    ROUND(AVG(CASE WHEN d.actual_consumption > 0 THEN d.absolute_pct_error END), 4) AS mape,
    ROUND(SUM(d.absolute_error) / NULLIF(SUM(d.actual_consumption), 0), 4) AS wmape,
    ROUND(SQRT(AVG(d.squared_error)), 4)                            AS rmse,
    ROUND(AVG(d.forecast_error), 4)                                 AS mfe,
    ROUND(SUM(CASE WHEN d.absolute_pct_error <= 0.20 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 4)                                   AS accuracy_rate_20,
    ROUND(SUM(d.forecast_error) / NULLIF(AVG(d.absolute_error), 0), 4) AS tracking_signal,
    COUNT(*)                                                        AS prediction_count,
    NULL                                                            AS coverage_pct,
    ROUND(AVG(d.actual_consumption), 2)                             AS avg_actual,
    NOW()                                                           AS computed_at

FROM (
    SELECT DISTINCT accuracy_date AS ref_date
    FROM test.forecast_accuracy_daily
    WHERE accuracy_date >= @calc_date_start
      AND accuracy_date <= @calc_date_end
) ref
INNER JOIN test.forecast_accuracy_daily d
    ON d.accuracy_date BETWEEN DATE_SUB(ref.ref_date, INTERVAL 6 DAY) AND ref.ref_date
GROUP BY ref.ref_date, d.large_class_name;


-- ############################################################################
-- VERIFICATION / 验证
-- ############################################################################
/*
-- Summary count by period_type and dimension_type
-- 按周期类型和维度类型统计汇总行数
SELECT
    period_type,
    dimension_type,
    COUNT(*)                  AS row_count,
    MIN(period_start)         AS earliest_start,
    MAX(period_end)           AS latest_end,
    ROUND(AVG(mape), 4)       AS avg_mape,
    ROUND(AVG(wmape), 4)      AS avg_wmape
FROM test.forecast_accuracy_summary
WHERE period_end >= @calc_date_start
GROUP BY period_type, dimension_type
ORDER BY period_type, dimension_type;
*/


-- ============================================================================
-- END OF 04_aggregate_metrics.sql
-- ============================================================================

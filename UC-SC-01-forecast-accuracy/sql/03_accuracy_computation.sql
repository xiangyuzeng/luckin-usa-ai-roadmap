-- ============================================================================
-- UC-SC-01 Forecast Accuracy Monitor
-- 03_accuracy_computation.sql - Prediction vs Actual Accuracy Computation
-- 预测准确性计算 - 预测值与实际值对比
-- ============================================================================
-- Purpose:  Extract predictions and actuals from SEPARATE source database
--           servers, then join and compute accuracy metrics into the analytics
--           table test.forecast_accuracy_daily on the analytics server.
-- 目的:     从不同的源数据库服务器分别提取预测数据和实际消耗数据，
--           然后在分析服务器上进行关联计算，写入 test.forecast_accuracy_daily。
--
-- IMPORTANT: Source tables and analytics tables live on DIFFERENT MySQL servers.
--            This script is organized as separate extract queries and load queries.
--            A Python/shell orchestrator must execute each section against its
--            respective server, staging data in temp tables or flat files between.
-- 重要:     源表和分析表位于不同的MySQL服务器。本脚本按独立的提取查询和加载查询组织。
--            Python/shell 编排器需对各自的服务器执行各段查询，中间通过临时表或文件暂存数据。
--
-- Architecture:
--   Step 1: Run on aws-luckyus-ireplenishment-rw  -> Extract predictions
--   Step 2: Run on aws-luckyus-scm-shopstock-rw   -> Extract actuals
--   Step 3: Run on aws-luckyus-dbatest-rw         -> Join & compute metrics
--
-- Parameters (set by orchestrator before execution):
--   @calc_date_start  DATE  - Start of calculation window (inclusive)
--   @calc_date_end    DATE  - End of calculation window (inclusive)
--
-- Validated Consumption Formula / 已验证的消耗公式:
--   reason_code IN ('025','1001','1002')
--   AND total_adjust_num < 0
--   actual_consumption = SUM(ABS(total_adjust_num))
--
-- Join Keys / 关联键:
--   predictions.shop_dept_id  = actuals.shop_dept_id
--   predictions.goods_code    = actuals.goods_mid
--   predictions.dt            = DATE(actuals.operated_time)
--
-- Active Stores / 活跃门店 (10):
--   1127, 1128, 1140, 1141, 20008, 20010, 20011, 20027, 20031, 20032
--
-- Author:   Data Engineering / BI Team
-- Created:  2026-02-15
-- ============================================================================


-- ############################################################################
-- STEP 1: EXTRACT PREDICTIONS / 提取预测数据
-- Server: aws-luckyus-ireplenishment-rw
-- Database: luckyus_ireplenishment
-- ############################################################################
-- Extracts the latest prediction version per (shop_dept_id, goods_code, dt)
-- for all 10 active stores within the specified date range.
-- 提取指定日期范围内10个活跃门店每个(门店, 商品, 日期)组合的最新预测版本。
--
-- Output columns (to be staged as CSV or temp table):
--   dt, shop_dept_id, goods_code, goods_name, large_class_name,
--   vlt_avg_demand, order_num, task_version_id
--
-- NOTE: The dt column may be formatted as 'YYYYMMDD' or 'YYYY-MM-DD'.
--       The subquery uses MAX(task_version_id) to deduplicate multiple runs
--       for the same prediction date.
-- 注意: dt 列可能为 'YYYYMMDD' 或 'YYYY-MM-DD' 格式。
--       子查询使用 MAX(task_version_id) 对同一预测日期的多次运行进行去重。
-- ############################################################################

-- SET @calc_date_start = '2026-02-01';
-- SET @calc_date_end   = '2026-02-14';

-- --- EXTRACT QUERY: Run on aws-luckyus-ireplenishment-rw ---
SELECT
    p.dt                                        AS dt,
    p.shop_dept_id                              AS shop_dept_id,
    p.goods_code                                AS goods_code,
    p.goods_name                                AS goods_name,
    p.large_class_name                          AS large_class_name,
    p.vlt_avg_demand                            AS vlt_avg_demand,
    p.order_num                                 AS order_num,
    p.task_version_id                           AS task_version_id
FROM luckyus_ireplenishment.t_order_predict_alg_v2 p
INNER JOIN (
    -- Subquery: get the latest task_version_id per (shop_dept_id, goods_code, dt)
    -- 子查询: 获取每个(门店, 商品, 日期)组合的最新任务版本
    SELECT
        shop_dept_id,
        goods_code,
        dt,
        MAX(task_version_id) AS max_version_id
    FROM luckyus_ireplenishment.t_order_predict_alg_v2
    WHERE dt >= @calc_date_start
      AND dt <= @calc_date_end
      AND shop_dept_id IN (1127, 1128, 1140, 1141, 20008, 20010, 20011, 20027, 20031, 20032)
    GROUP BY shop_dept_id, goods_code, dt
) latest
    ON  p.shop_dept_id    = latest.shop_dept_id
    AND p.goods_code      = latest.goods_code
    AND p.dt              = latest.dt
    AND p.task_version_id = latest.max_version_id
WHERE p.dt >= @calc_date_start
  AND p.dt <= @calc_date_end
  AND p.shop_dept_id IN (1127, 1128, 1140, 1141, 20008, 20010, 20011, 20027, 20031, 20032)
ORDER BY p.dt, p.shop_dept_id, p.goods_code;


-- ############################################################################
-- STEP 2: EXTRACT ACTUALS (Consumption) / 提取实际消耗数据
-- Server: aws-luckyus-scm-shopstock-rw
-- Database: luckyus_scm_shopstock
-- ############################################################################
-- Aggregates daily actual consumption per (shop_dept_id, goods_mid) using
-- the validated consumption formula:
--   reason_code IN ('025','1001','1002') AND total_adjust_num < 0
--   actual_consumption = SUM(ABS(total_adjust_num))
--
-- 使用已验证的消耗公式按(门店, 商品中码)聚合每日实际消耗:
--   reason_code IN ('025','1001','1002') 且 total_adjust_num < 0
--   actual_consumption = SUM(ABS(total_adjust_num))
--
-- Output columns (to be staged as CSV or temp table):
--   consumption_date, shop_dept_id, goods_mid, actual_consumption, record_count
--
-- IMPORTANT JOIN KEY NOTE:
--   The join to predictions uses goods_mid (NOT goods_code) from this table.
--   predictions.goods_code = actuals.goods_mid
-- 重要关联键说明:
--   与预测表关联时使用 goods_mid（不是 goods_code）。
--   predictions.goods_code = actuals.goods_mid
-- ############################################################################

-- --- EXTRACT QUERY: Run on aws-luckyus-scm-shopstock-rw ---
SELECT
    DATE(scr.operated_time)                     AS consumption_date,
    scr.shop_dept_id                            AS shop_dept_id,
    scr.goods_mid                               AS goods_mid,
    SUM(ABS(scr.total_adjust_num))              AS actual_consumption,
    COUNT(*)                                    AS record_count
FROM luckyus_scm_shopstock.t_shop_goods_stock_change_record scr
WHERE scr.operated_time >= CONCAT(@calc_date_start, ' 00:00:00')
  AND scr.operated_time <  DATE_ADD(@calc_date_end, INTERVAL 1 DAY)
  AND scr.reason_code IN ('025', '1001', '1002')
  AND scr.total_adjust_num < 0
  AND scr.shop_dept_id IN (1127, 1128, 1140, 1141, 20008, 20010, 20011, 20027, 20031, 20032)
GROUP BY DATE(scr.operated_time), scr.shop_dept_id, scr.goods_mid
ORDER BY consumption_date, scr.shop_dept_id, scr.goods_mid;


-- ############################################################################
-- STEP 3: JOIN & COMPUTE ACCURACY METRICS / 关联计算准确性指标
-- Server: aws-luckyus-dbatest-rw
-- Database / Schema: test
-- ############################################################################
-- Prerequisites:
--   The orchestrator must first load Step 1 output into tmp_predictions
--   and Step 2 output into tmp_actuals as staging tables on the analytics
--   server (aws-luckyus-dbatest-rw).
--
-- 前置条件:
--   编排器必须先将步骤1的输出加载到 tmp_predictions 临时表，
--   步骤2的输出加载到 tmp_actuals 临时表（均在分析服务器上）。
--
-- Primary prediction value: vlt_avg_demand (not order_num)
-- 主要预测值: vlt_avg_demand（不是 order_num）
-- ############################################################################

-- --- 3a: Create staging tables (run on aws-luckyus-dbatest-rw) ---
-- 创建暂存表（在分析服务器上执行）

DROP TABLE IF EXISTS test.tmp_predictions;
CREATE TABLE test.tmp_predictions (
    dt                VARCHAR(32)     NOT NULL,
    shop_dept_id      BIGINT          NOT NULL,
    goods_code        VARCHAR(32)     NOT NULL,
    goods_name        VARCHAR(200),
    large_class_name  VARCHAR(100),
    vlt_avg_demand    DECIMAL(12,2),
    order_num         DECIMAL(12,2),
    task_version_id   BIGINT,
    PRIMARY KEY (dt, shop_dept_id, goods_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP TABLE IF EXISTS test.tmp_actuals;
CREATE TABLE test.tmp_actuals (
    consumption_date  DATE            NOT NULL,
    shop_dept_id      BIGINT          NOT NULL,
    goods_mid         VARCHAR(32)     NOT NULL,
    actual_consumption DECIMAL(12,2),
    record_count      INT,
    PRIMARY KEY (consumption_date, shop_dept_id, goods_mid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- --- 3b: LOAD staged data into tmp tables ---
-- Orchestrator inserts Step 1 data into test.tmp_predictions
-- Orchestrator inserts Step 2 data into test.tmp_actuals
-- (via LOAD DATA INFILE, INSERT, or bulk loader)
-- 编排器将步骤1数据插入 test.tmp_predictions
-- 编排器将步骤2数据插入 test.tmp_actuals
-- （通过 LOAD DATA INFILE、INSERT 或批量加载器）


-- --- 3c: Idempotency - delete existing rows for the date range ---
-- 幂等性 - 删除日期范围内已有的数据
DELETE FROM test.forecast_accuracy_daily
WHERE accuracy_date >= @calc_date_start
  AND accuracy_date <= @calc_date_end;


-- --- 3d: INSERT computed accuracy metrics ---
-- 插入计算后的准确性指标
-- Join key: predictions.goods_code = actuals.goods_mid
-- Join key: predictions.dt = actuals.consumption_date
-- Primary prediction value: vlt_avg_demand
-- 关联键: predictions.goods_code = actuals.goods_mid
-- 关联键: predictions.dt = actuals.consumption_date
-- 主要预测值: vlt_avg_demand

INSERT INTO test.forecast_accuracy_daily (
    accuracy_date,
    shop_dept_id,
    shop_name,
    goods_code,
    goods_name,
    large_class_name,
    predicted_demand,
    predicted_order_qty,
    actual_consumption,
    absolute_error,
    absolute_pct_error,
    forecast_error,
    bias_pct,
    squared_error,
    prediction_dt,
    task_version_id,
    computed_at
)
SELECT
    -- Dimensional keys / 维度键
    a.consumption_date                                          AS accuracy_date,
    p.shop_dept_id                                              AS shop_dept_id,
    NULL                                                        AS shop_name,       -- Enriched in post-processing / 后处理中填充
    p.goods_code                                                AS goods_code,
    p.goods_name                                                AS goods_name,
    p.large_class_name                                          AS large_class_name,

    -- Prediction values / 预测值
    -- Primary metric: vlt_avg_demand (smoothed demand forecast)
    -- 主要指标: vlt_avg_demand（平滑需求预测）
    p.vlt_avg_demand                                            AS predicted_demand,
    p.order_num                                                 AS predicted_order_qty,

    -- Actual consumption / 实际消耗
    a.actual_consumption                                        AS actual_consumption,

    -- Error metrics / 误差指标
    -- absolute_error = |predicted - actual|
    -- 绝对误差 = |预测值 - 实际值|
    ABS(p.vlt_avg_demand - a.actual_consumption)                AS absolute_error,

    -- absolute_pct_error = |predicted - actual| / actual (NULL when actual = 0)
    -- 绝对百分比误差 = |预测值 - 实际值| / 实际值（实际值为0时为NULL）
    ABS(p.vlt_avg_demand - a.actual_consumption)
        / NULLIF(a.actual_consumption, 0)                       AS absolute_pct_error,

    -- forecast_error = predicted - actual (positive = over-prediction)
    -- 预测误差 = 预测值 - 实际值（正值表示过度预测）
    (p.vlt_avg_demand - a.actual_consumption)                   AS forecast_error,

    -- bias_pct = (predicted - actual) / actual
    -- 偏差百分比 = (预测值 - 实际值) / 实际值
    (p.vlt_avg_demand - a.actual_consumption)
        / NULLIF(a.actual_consumption, 0)                       AS bias_pct,

    -- squared_error = (predicted - actual)^2
    -- 平方误差 = (预测值 - 实际值)^2
    POW(p.vlt_avg_demand - a.actual_consumption, 2)             AS squared_error,

    -- Lineage / 数据溯源
    p.dt                                                        AS prediction_dt,
    p.task_version_id                                           AS task_version_id,

    -- Metadata / 元数据
    NOW()                                                       AS computed_at

FROM test.tmp_predictions p
INNER JOIN test.tmp_actuals a
    ON  p.shop_dept_id = a.shop_dept_id
    AND p.goods_code   = a.goods_mid
    AND p.dt           = a.consumption_date
WHERE a.actual_consumption IS NOT NULL
  AND p.vlt_avg_demand     IS NOT NULL;


-- --- 3e: Post-processing - Enrich shop_name from store master ---
-- 后处理 - 从门店主数据补充门店名称
-- NOTE: The orchestrator should run a separate query against aws-luckyus-opshop-rw
--       to fetch shop_name for all 10 stores, then update here.
--       Alternatively, maintain a local lookup.
-- 注意: 编排器应对 aws-luckyus-opshop-rw 执行单独查询获取10个门店的名称，然后在此更新。
--       或者维护本地查找表。

-- Store name mapping for 10 active stores (hardcoded fallback):
-- 10个活跃门店名称映射（硬编码备用）:
UPDATE test.forecast_accuracy_daily SET shop_name = '8th & Broadway'   WHERE shop_dept_id = 1127  AND shop_name IS NULL;
UPDATE test.forecast_accuracy_daily SET shop_name = '28th & 6th'      WHERE shop_dept_id = 1128  AND shop_name IS NULL;
UPDATE test.forecast_accuracy_daily SET shop_name = '100 Maiden Ln'   WHERE shop_dept_id = 1140  AND shop_name IS NULL;
UPDATE test.forecast_accuracy_daily SET shop_name = '54th & 8th'      WHERE shop_dept_id = 1141  AND shop_name IS NULL;
UPDATE test.forecast_accuracy_daily SET shop_name = '33rd & 10th'     WHERE shop_dept_id = 20008 AND shop_name IS NULL;
UPDATE test.forecast_accuracy_daily SET shop_name = '102 Fulton'      WHERE shop_dept_id = 20010 AND shop_name IS NULL;
UPDATE test.forecast_accuracy_daily SET shop_name = '37th & Broadway' WHERE shop_dept_id = 20011 AND shop_name IS NULL;
UPDATE test.forecast_accuracy_daily SET shop_name = '21st & 3rd'      WHERE shop_dept_id = 20027 AND shop_name IS NULL;
UPDATE test.forecast_accuracy_daily SET shop_name = '15th & 3rd'      WHERE shop_dept_id = 20031 AND shop_name IS NULL;
UPDATE test.forecast_accuracy_daily SET shop_name = '221 Grand'       WHERE shop_dept_id = 20032 AND shop_name IS NULL;


-- --- 3f: Cleanup staging tables ---
-- 清理暂存表
DROP TABLE IF EXISTS test.tmp_predictions;
DROP TABLE IF EXISTS test.tmp_actuals;


-- --- 3g: Verification query ---
-- 验证查询 - 检查插入结果
/*
SELECT
    accuracy_date,
    COUNT(*)                                AS row_count,
    COUNT(DISTINCT shop_dept_id)            AS store_count,
    COUNT(DISTINCT goods_code)              AS sku_count,
    ROUND(AVG(absolute_pct_error), 4)       AS avg_ape,
    ROUND(SUM(absolute_error) / NULLIF(SUM(actual_consumption), 0), 4) AS wmape,
    ROUND(AVG(forecast_error), 2)           AS avg_bias
FROM test.forecast_accuracy_daily
WHERE accuracy_date >= @calc_date_start
  AND accuracy_date <= @calc_date_end
GROUP BY accuracy_date
ORDER BY accuracy_date;
*/


-- ============================================================================
-- END OF 03_accuracy_computation.sql
-- ============================================================================

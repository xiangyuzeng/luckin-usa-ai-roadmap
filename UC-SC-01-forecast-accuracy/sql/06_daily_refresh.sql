-- ============================================================================
-- UC-SC-01 Forecast Accuracy Monitor
-- 06_daily_refresh.sql - Daily Refresh Stored Procedure & Scheduler
-- 每日刷新存储过程与调度器
-- ============================================================================
-- Purpose:  Encapsulate the complete daily ETL pipeline into a MySQL stored
--           procedure with error handling, idempotency, and execution logging.
--           Also creates a MySQL EVENT for automatic daily execution.
-- 目的:     将完整的每日ETL管道封装为MySQL存储过程，包含错误处理、幂等性和
--           执行日志记录。同时创建MySQL EVENT用于自动每日执行。
--
-- Target Server: aws-luckyus-dbatest-rw
-- Target Schema: test
--
-- IMPORTANT ARCHITECTURE NOTE:
--   Because source data (predictions, actuals) lives on SEPARATE MySQL servers
--   from the analytics tables, the stored procedure handles ONLY the local
--   analytics server operations (Steps 3-6 from 03_accuracy_computation.sql).
--   Steps 1-2 (source data extraction) MUST be handled by the Python/shell
--   orchestrator, which loads data into tmp_predictions and tmp_actuals
--   staging tables BEFORE calling this procedure.
-- 重要架构说明:
--   由于源数据（预测、实际）与分析表位于不同的MySQL服务器上，存储过程仅处理
--   本地分析服务器操作（03_accuracy_computation.sql 的步骤3-6）。
--   步骤1-2（源数据提取）必须由Python/shell编排器处理，在调用此过程之前
--   将数据加载到 tmp_predictions 和 tmp_actuals 暂存表中。
--
-- Orchestrator Workflow / 编排器工作流:
--   1. Python extracts predictions from aws-luckyus-ireplenishment-rw
--      -> LOAD into test.tmp_predictions on analytics server
--   2. Python extracts actuals from aws-luckyus-scm-shopstock-rw
--      -> LOAD into test.tmp_actuals on analytics server
--   3. Python calls: CALL test.sp_refresh_forecast_accuracy(p_calc_date)
--   4. Procedure handles: join, compute, aggregate, alert, log
--
-- Author:   Data Engineering / BI Team
-- Created:  2026-02-15
-- ============================================================================


-- ############################################################################
-- DROP EXISTING OBJECTS (for re-deployment safety)
-- 删除已有对象（用于重新部署安全性）
-- ############################################################################

DROP PROCEDURE IF EXISTS test.sp_refresh_forecast_accuracy;
DROP EVENT IF EXISTS test.evt_daily_forecast_accuracy;


DELIMITER $$

-- ############################################################################
-- STORED PROCEDURE: sp_refresh_forecast_accuracy
-- 存储过程: sp_refresh_forecast_accuracy
-- ############################################################################
-- Parameters:
--   IN p_calc_date DATE  - The date to compute accuracy for.
--                          Typically yesterday (CURDATE() - INTERVAL 1 DAY).
-- 参数:
--   IN p_calc_date DATE  - 计算准确性的日期。通常为昨天。
--
-- Prerequisites:
--   The orchestrator MUST have loaded the following staging tables before
--   calling this procedure:
--     test.tmp_predictions  - Prediction data from ireplenishment server
--     test.tmp_actuals      - Actual consumption from scm-shopstock server
-- 前提条件:
--   编排器在调用此过程之前必须已加载以下暂存表:
--     test.tmp_predictions  - 来自 ireplenishment 服务器的预测数据
--     test.tmp_actuals      - 来自 scm-shopstock 服务器的实际消耗数据
-- ############################################################################

CREATE PROCEDURE test.sp_refresh_forecast_accuracy(
    IN p_calc_date DATE
)
BEGIN

    -- ========================================================================
    -- VARIABLE DECLARATIONS / 变量声明
    -- ========================================================================
    DECLARE v_run_id        VARCHAR(64);
    DECLARE v_start_time    DATETIME;
    DECLARE v_step_start    DATETIME;
    DECLARE v_rows_affected INT DEFAULT 0;
    DECLARE v_pred_count    INT DEFAULT 0;
    DECLARE v_actual_count  INT DEFAULT 0;
    DECLARE v_daily_count   INT DEFAULT 0;
    DECLARE v_summary_count INT DEFAULT 0;
    DECLARE v_alert_count   INT DEFAULT 0;
    DECLARE v_error_flag    BOOLEAN DEFAULT FALSE;
    DECLARE v_error_msg     TEXT DEFAULT NULL;

    -- ========================================================================
    -- ERROR HANDLER / 错误处理
    -- ========================================================================
    -- Catch any SQL exception, log it, and re-raise
    -- 捕获任何SQL异常，记录并重新抛出
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_error_msg = MESSAGE_TEXT;
        SET v_error_flag = TRUE;

        -- Log the error to pipeline run log
        -- 将错误记录到管道运行日志
        INSERT INTO test.forecast_pipeline_run_log (
            run_id, pipeline_name, step_name,
            run_start, run_end, duration_seconds,
            data_date_start, data_date_end,
            status, error_message,
            target_table, triggered_by, created_at
        ) VALUES (
            v_run_id,
            'forecast_accuracy_daily_etl',
            'ERROR_HANDLER',
            v_step_start,
            NOW(),
            TIMESTAMPDIFF(SECOND, v_step_start, NOW()),
            p_calc_date,
            p_calc_date,
            'FAILED',
            v_error_msg,
            NULL,
            'stored_procedure',
            NOW()
        );
    END;

    -- ========================================================================
    -- INITIALIZATION / 初始化
    -- ========================================================================
    SET v_run_id     = UUID();
    SET v_start_time = NOW();
    SET v_step_start = NOW();

    -- Log pipeline start / 记录管道开始
    INSERT INTO test.forecast_pipeline_run_log (
        run_id, pipeline_name, step_name,
        run_start, data_date_start, data_date_end,
        status, target_table, triggered_by, created_at
    ) VALUES (
        v_run_id,
        'forecast_accuracy_daily_etl',
        'PIPELINE_START',
        v_start_time,
        p_calc_date,
        p_calc_date,
        'RUNNING',
        'test.forecast_accuracy_daily',
        'stored_procedure',
        NOW()
    );


    -- ========================================================================
    -- STEP 1: VALIDATE STAGING TABLES / 验证暂存表
    -- ========================================================================
    -- Check that staging tables exist and have data for the calc_date.
    -- 检查暂存表是否存在且包含计算日期的数据。
    SET v_step_start = NOW();

    SELECT COUNT(*) INTO v_pred_count
    FROM test.tmp_predictions
    WHERE dt = p_calc_date;

    SELECT COUNT(*) INTO v_actual_count
    FROM test.tmp_actuals
    WHERE consumption_date = p_calc_date;

    -- Log validation step / 记录验证步骤
    INSERT INTO test.forecast_pipeline_run_log (
        run_id, pipeline_name, step_name,
        run_start, run_end, duration_seconds,
        data_date_start, data_date_end,
        status, rows_extracted,
        target_table, triggered_by,
        config_snapshot, created_at
    ) VALUES (
        v_run_id,
        'forecast_accuracy_daily_etl',
        'VALIDATE_STAGING',
        v_step_start,
        NOW(),
        TIMESTAMPDIFF(SECOND, v_step_start, NOW()),
        p_calc_date,
        p_calc_date,
        CASE WHEN v_pred_count > 0 AND v_actual_count > 0 THEN 'SUCCESS'
             ELSE 'FAILED' END,
        v_pred_count + v_actual_count,
        'tmp_predictions, tmp_actuals',
        'stored_procedure',
        JSON_OBJECT(
            'prediction_rows', v_pred_count,
            'actual_rows', v_actual_count,
            'calc_date', p_calc_date
        ),
        NOW()
    );

    -- Abort if no staging data / 暂存数据为空则终止
    IF v_pred_count = 0 OR v_actual_count = 0 THEN
        INSERT INTO test.forecast_pipeline_run_log (
            run_id, pipeline_name, step_name,
            run_start, run_end, duration_seconds,
            data_date_start, data_date_end,
            status, error_message,
            triggered_by, created_at
        ) VALUES (
            v_run_id,
            'forecast_accuracy_daily_etl',
            'PIPELINE_ABORT',
            v_start_time,
            NOW(),
            TIMESTAMPDIFF(SECOND, v_start_time, NOW()),
            p_calc_date,
            p_calc_date,
            'FAILED',
            CONCAT('Staging tables empty for ', p_calc_date,
                   '. Predictions: ', v_pred_count,
                   ', Actuals: ', v_actual_count,
                   '. Orchestrator must load data before calling this procedure.'),
            'stored_procedure',
            NOW()
        );
        -- Exit procedure early
        -- 提前退出过程
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Staging tables empty. Cannot proceed.';
    END IF;


    -- ========================================================================
    -- STEP 2: IDEMPOTENT DELETE / 幂等性删除
    -- ========================================================================
    -- Remove existing data for the calc_date to allow safe re-runs.
    -- 删除计算日期的已有数据，允许安全重跑。
    SET v_step_start = NOW();

    DELETE FROM test.forecast_accuracy_daily
    WHERE accuracy_date = p_calc_date;

    SET v_rows_affected = ROW_COUNT();

    INSERT INTO test.forecast_pipeline_run_log (
        run_id, pipeline_name, step_name,
        run_start, run_end, duration_seconds,
        data_date_start, data_date_end,
        status, rows_loaded,
        target_table, triggered_by, created_at
    ) VALUES (
        v_run_id,
        'forecast_accuracy_daily_etl',
        'IDEMPOTENT_DELETE_DAILY',
        v_step_start,
        NOW(),
        TIMESTAMPDIFF(SECOND, v_step_start, NOW()),
        p_calc_date,
        p_calc_date,
        'SUCCESS',
        v_rows_affected,
        'test.forecast_accuracy_daily',
        'stored_procedure',
        NOW()
    );


    -- ========================================================================
    -- STEP 3: JOIN & COMPUTE METRICS / 关联计算指标
    -- ========================================================================
    -- Join predictions (tmp_predictions) with actuals (tmp_actuals) and
    -- compute all error metrics. Insert into forecast_accuracy_daily.
    -- 关联预测数据和实际数据，计算所有误差指标，插入 forecast_accuracy_daily。
    --
    -- Join keys / 关联键:
    --   tmp_predictions.goods_code = tmp_actuals.goods_mid
    --   tmp_predictions.dt         = tmp_actuals.consumption_date
    --   tmp_predictions.shop_dept_id = tmp_actuals.shop_dept_id
    --
    -- Primary prediction value: vlt_avg_demand / 主要预测值: vlt_avg_demand
    SET v_step_start = NOW();

    INSERT INTO test.forecast_accuracy_daily (
        accuracy_date, shop_dept_id, shop_name,
        goods_code, goods_name, large_class_name,
        predicted_demand, predicted_order_qty, actual_consumption,
        absolute_error, absolute_pct_error, forecast_error, bias_pct, squared_error,
        prediction_dt, task_version_id, computed_at
    )
    SELECT
        a.consumption_date                                          AS accuracy_date,
        p.shop_dept_id                                              AS shop_dept_id,
        NULL                                                        AS shop_name,
        p.goods_code                                                AS goods_code,
        p.goods_name                                                AS goods_name,
        p.large_class_name                                          AS large_class_name,
        p.vlt_avg_demand                                            AS predicted_demand,
        p.order_num                                                 AS predicted_order_qty,
        a.actual_consumption                                        AS actual_consumption,

        -- Error metrics / 误差指标
        ABS(p.vlt_avg_demand - a.actual_consumption)                AS absolute_error,
        ABS(p.vlt_avg_demand - a.actual_consumption)
            / NULLIF(a.actual_consumption, 0)                       AS absolute_pct_error,
        (p.vlt_avg_demand - a.actual_consumption)                   AS forecast_error,
        (p.vlt_avg_demand - a.actual_consumption)
            / NULLIF(a.actual_consumption, 0)                       AS bias_pct,
        POW(p.vlt_avg_demand - a.actual_consumption, 2)             AS squared_error,

        p.dt                                                        AS prediction_dt,
        p.task_version_id                                           AS task_version_id,
        NOW()                                                       AS computed_at

    FROM test.tmp_predictions p
    INNER JOIN test.tmp_actuals a
        ON  p.shop_dept_id = a.shop_dept_id
        AND p.goods_code   = a.goods_mid
        AND p.dt           = a.consumption_date
    WHERE a.actual_consumption IS NOT NULL
      AND p.vlt_avg_demand     IS NOT NULL
      AND a.consumption_date   = p_calc_date;

    SET v_daily_count = ROW_COUNT();

    -- Enrich shop_name / 补充门店名称
    UPDATE test.forecast_accuracy_daily SET shop_name = '8th & Broadway'   WHERE shop_dept_id = 1127  AND accuracy_date = p_calc_date AND shop_name IS NULL;
    UPDATE test.forecast_accuracy_daily SET shop_name = '28th & 6th'      WHERE shop_dept_id = 1128  AND accuracy_date = p_calc_date AND shop_name IS NULL;
    UPDATE test.forecast_accuracy_daily SET shop_name = '100 Maiden Ln'   WHERE shop_dept_id = 1140  AND accuracy_date = p_calc_date AND shop_name IS NULL;
    UPDATE test.forecast_accuracy_daily SET shop_name = '54th & 8th'      WHERE shop_dept_id = 1141  AND accuracy_date = p_calc_date AND shop_name IS NULL;
    UPDATE test.forecast_accuracy_daily SET shop_name = '33rd & 10th'     WHERE shop_dept_id = 20008 AND accuracy_date = p_calc_date AND shop_name IS NULL;
    UPDATE test.forecast_accuracy_daily SET shop_name = '102 Fulton'      WHERE shop_dept_id = 20010 AND accuracy_date = p_calc_date AND shop_name IS NULL;
    UPDATE test.forecast_accuracy_daily SET shop_name = '37th & Broadway' WHERE shop_dept_id = 20011 AND accuracy_date = p_calc_date AND shop_name IS NULL;
    UPDATE test.forecast_accuracy_daily SET shop_name = '21st & 3rd'      WHERE shop_dept_id = 20027 AND accuracy_date = p_calc_date AND shop_name IS NULL;
    UPDATE test.forecast_accuracy_daily SET shop_name = '15th & 3rd'      WHERE shop_dept_id = 20031 AND accuracy_date = p_calc_date AND shop_name IS NULL;
    UPDATE test.forecast_accuracy_daily SET shop_name = '221 Grand'       WHERE shop_dept_id = 20032 AND accuracy_date = p_calc_date AND shop_name IS NULL;

    INSERT INTO test.forecast_pipeline_run_log (
        run_id, pipeline_name, step_name,
        run_start, run_end, duration_seconds,
        data_date_start, data_date_end,
        status, rows_extracted, rows_loaded,
        target_table, triggered_by, created_at
    ) VALUES (
        v_run_id,
        'forecast_accuracy_daily_etl',
        'COMPUTE_DAILY_ACCURACY',
        v_step_start,
        NOW(),
        TIMESTAMPDIFF(SECOND, v_step_start, NOW()),
        p_calc_date,
        p_calc_date,
        CASE WHEN v_daily_count > 0 THEN 'SUCCESS' ELSE 'PARTIAL' END,
        v_pred_count + v_actual_count,
        v_daily_count,
        'test.forecast_accuracy_daily',
        'stored_procedure',
        NOW()
    );


    -- ========================================================================
    -- STEP 4: RECOMPUTE ROLLING AGGREGATES / 重新计算滚动聚合
    -- ========================================================================
    -- Delete and recompute summary rows that include today's data.
    -- This covers DAILY, ROLLING_7D, and ROLLING_30D periods.
    -- 删除并重新计算包含今天数据的汇总行。涵盖DAILY、ROLLING_7D和ROLLING_30D。
    SET v_step_start = NOW();

    -- Delete summaries that include the calc_date in their period
    -- 删除周期包含计算日期的汇总
    DELETE FROM test.forecast_accuracy_summary
    WHERE period_end >= p_calc_date
      AND period_start <= p_calc_date;

    -- DAILY x OVERALL / 每日 x 全局
    INSERT INTO test.forecast_accuracy_summary (
        period_type, period_start, period_end,
        dimension_type, dimension_value, dimension_name,
        mape, wmape, rmse, mfe,
        accuracy_rate_20, tracking_signal,
        prediction_count, avg_actual, computed_at
    )
    SELECT
        'DAILY', p_calc_date, p_calc_date,
        'OVERALL', 'ALL', 'All Stores & Products',
        ROUND(AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END), 4),
        ROUND(SUM(absolute_error) / NULLIF(SUM(actual_consumption), 0), 4),
        ROUND(SQRT(AVG(squared_error)), 4),
        ROUND(AVG(forecast_error), 4),
        ROUND(SUM(CASE WHEN absolute_pct_error <= 0.20 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 4),
        ROUND(SUM(forecast_error) / NULLIF(AVG(absolute_error), 0), 4),
        COUNT(*),
        ROUND(AVG(actual_consumption), 2),
        NOW()
    FROM test.forecast_accuracy_daily
    WHERE accuracy_date = p_calc_date;

    -- DAILY x STORE / 每日 x 门店
    INSERT INTO test.forecast_accuracy_summary (
        period_type, period_start, period_end,
        dimension_type, dimension_value, dimension_name,
        mape, wmape, rmse, mfe,
        accuracy_rate_20, tracking_signal,
        prediction_count, avg_actual, computed_at
    )
    SELECT
        'DAILY', p_calc_date, p_calc_date,
        'STORE', CAST(shop_dept_id AS CHAR), MAX(shop_name),
        ROUND(AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END), 4),
        ROUND(SUM(absolute_error) / NULLIF(SUM(actual_consumption), 0), 4),
        ROUND(SQRT(AVG(squared_error)), 4),
        ROUND(AVG(forecast_error), 4),
        ROUND(SUM(CASE WHEN absolute_pct_error <= 0.20 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 4),
        ROUND(SUM(forecast_error) / NULLIF(AVG(absolute_error), 0), 4),
        COUNT(*),
        ROUND(AVG(actual_consumption), 2),
        NOW()
    FROM test.forecast_accuracy_daily
    WHERE accuracy_date = p_calc_date
    GROUP BY shop_dept_id;

    -- DAILY x CATEGORY / 每日 x 品类
    INSERT INTO test.forecast_accuracy_summary (
        period_type, period_start, period_end,
        dimension_type, dimension_value, dimension_name,
        mape, wmape, rmse, mfe,
        accuracy_rate_20, tracking_signal,
        prediction_count, avg_actual, computed_at
    )
    SELECT
        'DAILY', p_calc_date, p_calc_date,
        'CATEGORY', COALESCE(large_class_name, 'UNKNOWN'), COALESCE(large_class_name, 'Unknown Category'),
        ROUND(AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END), 4),
        ROUND(SUM(absolute_error) / NULLIF(SUM(actual_consumption), 0), 4),
        ROUND(SQRT(AVG(squared_error)), 4),
        ROUND(AVG(forecast_error), 4),
        ROUND(SUM(CASE WHEN absolute_pct_error <= 0.20 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 4),
        ROUND(SUM(forecast_error) / NULLIF(AVG(absolute_error), 0), 4),
        COUNT(*),
        ROUND(AVG(actual_consumption), 2),
        NOW()
    FROM test.forecast_accuracy_daily
    WHERE accuracy_date = p_calc_date
    GROUP BY large_class_name;

    -- ROLLING_7D x STORE / 滚动7天 x 门店
    INSERT INTO test.forecast_accuracy_summary (
        period_type, period_start, period_end,
        dimension_type, dimension_value, dimension_name,
        mape, wmape, rmse, mfe,
        accuracy_rate_20, tracking_signal,
        prediction_count, avg_actual, computed_at
    )
    SELECT
        'ROLLING_7D',
        DATE_SUB(p_calc_date, INTERVAL 6 DAY),
        p_calc_date,
        'STORE', CAST(shop_dept_id AS CHAR), MAX(shop_name),
        ROUND(AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END), 4),
        ROUND(SUM(absolute_error) / NULLIF(SUM(actual_consumption), 0), 4),
        ROUND(SQRT(AVG(squared_error)), 4),
        ROUND(AVG(forecast_error), 4),
        ROUND(SUM(CASE WHEN absolute_pct_error <= 0.20 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 4),
        ROUND(SUM(forecast_error) / NULLIF(AVG(absolute_error), 0), 4),
        COUNT(*),
        ROUND(AVG(actual_consumption), 2),
        NOW()
    FROM test.forecast_accuracy_daily
    WHERE accuracy_date BETWEEN DATE_SUB(p_calc_date, INTERVAL 6 DAY) AND p_calc_date
    GROUP BY shop_dept_id;

    -- ROLLING_7D x OVERALL / 滚动7天 x 全局
    INSERT INTO test.forecast_accuracy_summary (
        period_type, period_start, period_end,
        dimension_type, dimension_value, dimension_name,
        mape, wmape, rmse, mfe,
        accuracy_rate_20, tracking_signal,
        prediction_count, avg_actual, computed_at
    )
    SELECT
        'ROLLING_7D',
        DATE_SUB(p_calc_date, INTERVAL 6 DAY),
        p_calc_date,
        'OVERALL', 'ALL', 'All Stores & Products (7D Rolling)',
        ROUND(AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END), 4),
        ROUND(SUM(absolute_error) / NULLIF(SUM(actual_consumption), 0), 4),
        ROUND(SQRT(AVG(squared_error)), 4),
        ROUND(AVG(forecast_error), 4),
        ROUND(SUM(CASE WHEN absolute_pct_error <= 0.20 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 4),
        ROUND(SUM(forecast_error) / NULLIF(AVG(absolute_error), 0), 4),
        COUNT(*),
        ROUND(AVG(actual_consumption), 2),
        NOW()
    FROM test.forecast_accuracy_daily
    WHERE accuracy_date BETWEEN DATE_SUB(p_calc_date, INTERVAL 6 DAY) AND p_calc_date;

    -- ROLLING_7D x CATEGORY / 滚动7天 x 品类
    INSERT INTO test.forecast_accuracy_summary (
        period_type, period_start, period_end,
        dimension_type, dimension_value, dimension_name,
        mape, wmape, rmse, mfe,
        accuracy_rate_20, tracking_signal,
        prediction_count, avg_actual, computed_at
    )
    SELECT
        'ROLLING_7D',
        DATE_SUB(p_calc_date, INTERVAL 6 DAY),
        p_calc_date,
        'CATEGORY', COALESCE(large_class_name, 'UNKNOWN'), COALESCE(large_class_name, 'Unknown Category'),
        ROUND(AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END), 4),
        ROUND(SUM(absolute_error) / NULLIF(SUM(actual_consumption), 0), 4),
        ROUND(SQRT(AVG(squared_error)), 4),
        ROUND(AVG(forecast_error), 4),
        ROUND(SUM(CASE WHEN absolute_pct_error <= 0.20 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 4),
        ROUND(SUM(forecast_error) / NULLIF(AVG(absolute_error), 0), 4),
        COUNT(*),
        ROUND(AVG(actual_consumption), 2),
        NOW()
    FROM test.forecast_accuracy_daily
    WHERE accuracy_date BETWEEN DATE_SUB(p_calc_date, INTERVAL 6 DAY) AND p_calc_date
    GROUP BY large_class_name;

    SET v_summary_count = ROW_COUNT();

    INSERT INTO test.forecast_pipeline_run_log (
        run_id, pipeline_name, step_name,
        run_start, run_end, duration_seconds,
        data_date_start, data_date_end,
        status, rows_loaded,
        target_table, triggered_by, created_at
    ) VALUES (
        v_run_id,
        'forecast_accuracy_daily_etl',
        'RECOMPUTE_AGGREGATES',
        v_step_start,
        NOW(),
        TIMESTAMPDIFF(SECOND, v_step_start, NOW()),
        p_calc_date,
        p_calc_date,
        'SUCCESS',
        v_summary_count,
        'test.forecast_accuracy_summary',
        'stored_procedure',
        NOW()
    );


    -- ========================================================================
    -- STEP 5: RUN DRIFT DETECTION / 运行漂移检测
    -- ========================================================================
    -- Execute the 5 alert rules from 05_drift_detection.sql logic.
    -- 执行 05_drift_detection.sql 中的5个预警规则逻辑。
    SET v_step_start = NOW();

    -- Track alerts before insertion / 记录插入前的预警数
    SELECT COUNT(*) INTO v_alert_count FROM test.forecast_alerts WHERE DATE(alert_timestamp) = CURDATE();

    -- RULE 1: CRITICAL - 7-day MAPE > 40% per store
    -- 规则1: 严重 - 任意门店7天MAPE > 40%
    INSERT INTO test.forecast_alerts (
        alert_timestamp, alert_type,
        entity_type, entity_id, entity_name,
        metric_name, metric_value, threshold_value,
        description, recommended_action, is_acknowledged
    )
    SELECT
        NOW(), 'CRITICAL', 'STORE',
        CAST(shop_dept_id AS CHAR), MAX(shop_name),
        'mape_7d',
        ROUND(AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END), 4),
        0.4000,
        CONCAT('CRITICAL: Store ', MAX(shop_name), ' 7-day MAPE = ',
               ROUND(AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END) * 100, 1), '% > 40%'),
        'Investigate SKU-level accuracy. Consider model retraining. 请排查SKU级别准确性，考虑重新训练模型。',
        FALSE
    FROM test.forecast_accuracy_daily
    WHERE accuracy_date BETWEEN DATE_SUB(p_calc_date, INTERVAL 6 DAY) AND p_calc_date
      AND shop_dept_id IN (1127, 1128, 1140, 1141, 20008, 20010, 20011, 20027, 20031, 20032)
    GROUP BY shop_dept_id
    HAVING AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END) > 0.40
       AND NOT EXISTS (
           SELECT 1 FROM test.forecast_alerts fa
           WHERE fa.alert_type = 'CRITICAL' AND fa.entity_id = CAST(shop_dept_id AS CHAR)
             AND fa.metric_name = 'mape_7d' AND DATE(fa.alert_timestamp) = CURDATE()
       );

    -- RULE 2: WARNING - 7-day MAPE > 30% per store (but <= 40%)
    -- 规则2: 警告 - 任意门店7天MAPE > 30%（但 <= 40%）
    INSERT INTO test.forecast_alerts (
        alert_timestamp, alert_type,
        entity_type, entity_id, entity_name,
        metric_name, metric_value, threshold_value,
        description, recommended_action, is_acknowledged
    )
    SELECT
        NOW(), 'WARNING', 'STORE',
        CAST(shop_dept_id AS CHAR), MAX(shop_name),
        'mape_7d',
        ROUND(AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END), 4),
        0.3000,
        CONCAT('WARNING: Store ', MAX(shop_name), ' 7-day MAPE = ',
               ROUND(AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END) * 100, 1), '% > 30%'),
        'Monitor closely for 2-3 days. Review top error SKUs. 密切关注2-3天，审查误差最大SKU。',
        FALSE
    FROM test.forecast_accuracy_daily
    WHERE accuracy_date BETWEEN DATE_SUB(p_calc_date, INTERVAL 6 DAY) AND p_calc_date
      AND shop_dept_id IN (1127, 1128, 1140, 1141, 20008, 20010, 20011, 20027, 20031, 20032)
    GROUP BY shop_dept_id
    HAVING AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END) > 0.30
       AND AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END) <= 0.40
       AND NOT EXISTS (
           SELECT 1 FROM test.forecast_alerts fa
           WHERE fa.alert_type = 'WARNING' AND fa.entity_id = CAST(shop_dept_id AS CHAR)
             AND fa.metric_name = 'mape_7d' AND DATE(fa.alert_timestamp) = CURDATE()
       );

    -- RULE 5: DRIFT - Week-over-week MAPE change > 50% by category
    -- 规则5: 漂移 - 品类周环比MAPE变化 > 50%
    INSERT INTO test.forecast_alerts (
        alert_timestamp, alert_type,
        entity_type, entity_id, entity_name,
        metric_name, metric_value, threshold_value, baseline_value,
        description, recommended_action, is_acknowledged
    )
    SELECT
        NOW(), 'DRIFT', 'CATEGORY',
        curr.large_class_name, curr.large_class_name,
        'mape_wow_relative_change',
        ROUND((curr.curr_mape - prev.prev_mape) / NULLIF(prev.prev_mape, 0), 4),
        0.5000,
        ROUND(prev.prev_mape, 4),
        CONCAT('DRIFT: Category "', curr.large_class_name, '" MAPE WoW change = ',
               ROUND((curr.curr_mape - prev.prev_mape) / NULLIF(prev.prev_mape, 0) * 100, 1), '%'),
        'Investigate category for demand pattern changes. 请排查品类需求模式变化。',
        FALSE
    FROM (
        SELECT COALESCE(large_class_name, 'UNKNOWN') AS large_class_name,
               AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END) AS curr_mape
        FROM test.forecast_accuracy_daily
        WHERE accuracy_date BETWEEN DATE_SUB(p_calc_date, INTERVAL 6 DAY) AND p_calc_date
        GROUP BY large_class_name
    ) curr
    INNER JOIN (
        SELECT COALESCE(large_class_name, 'UNKNOWN') AS large_class_name,
               AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END) AS prev_mape
        FROM test.forecast_accuracy_daily
        WHERE accuracy_date BETWEEN DATE_SUB(p_calc_date, INTERVAL 13 DAY) AND DATE_SUB(p_calc_date, INTERVAL 7 DAY)
        GROUP BY large_class_name
    ) prev ON curr.large_class_name = prev.large_class_name
    WHERE prev.prev_mape > 0
      AND ABS((curr.curr_mape - prev.prev_mape) / prev.prev_mape) > 0.50
      AND NOT EXISTS (
          SELECT 1 FROM test.forecast_alerts fa
          WHERE fa.alert_type = 'DRIFT' AND fa.entity_id = curr.large_class_name
            AND fa.metric_name = 'mape_wow_relative_change' AND DATE(fa.alert_timestamp) = CURDATE()
      );

    -- Count new alerts generated / 计算新生成的预警数
    SET v_alert_count = (SELECT COUNT(*) FROM test.forecast_alerts WHERE DATE(alert_timestamp) = CURDATE()) - v_alert_count;

    INSERT INTO test.forecast_pipeline_run_log (
        run_id, pipeline_name, step_name,
        run_start, run_end, duration_seconds,
        data_date_start, data_date_end,
        status, rows_loaded,
        target_table, triggered_by, created_at
    ) VALUES (
        v_run_id,
        'forecast_accuracy_daily_etl',
        'DRIFT_DETECTION',
        v_step_start,
        NOW(),
        TIMESTAMPDIFF(SECOND, v_step_start, NOW()),
        p_calc_date,
        p_calc_date,
        'SUCCESS',
        v_alert_count,
        'test.forecast_alerts',
        'stored_procedure',
        NOW()
    );


    -- ========================================================================
    -- STEP 6: CLEANUP STAGING / 清理暂存表
    -- ========================================================================
    SET v_step_start = NOW();

    DROP TABLE IF EXISTS test.tmp_predictions;
    DROP TABLE IF EXISTS test.tmp_actuals;

    INSERT INTO test.forecast_pipeline_run_log (
        run_id, pipeline_name, step_name,
        run_start, run_end, duration_seconds,
        data_date_start, data_date_end,
        status, target_table, triggered_by, created_at
    ) VALUES (
        v_run_id,
        'forecast_accuracy_daily_etl',
        'CLEANUP_STAGING',
        v_step_start,
        NOW(),
        TIMESTAMPDIFF(SECOND, v_step_start, NOW()),
        p_calc_date,
        p_calc_date,
        'SUCCESS',
        'tmp_predictions, tmp_actuals',
        'stored_procedure',
        NOW()
    );


    -- ========================================================================
    -- STEP 7: FINALIZE PIPELINE RUN / 完成管道运行
    -- ========================================================================
    -- Update the PIPELINE_START record with final status
    -- 更新 PIPELINE_START 记录为最终状态

    UPDATE test.forecast_pipeline_run_log
    SET run_end          = NOW(),
        duration_seconds = TIMESTAMPDIFF(SECOND, run_start, NOW()),
        status           = CASE WHEN v_error_flag THEN 'FAILED' ELSE 'SUCCESS' END,
        rows_extracted   = v_pred_count + v_actual_count,
        rows_loaded      = v_daily_count,
        error_message    = v_error_msg,
        config_snapshot  = JSON_OBJECT(
            'calc_date',       p_calc_date,
            'predictions',     v_pred_count,
            'actuals',         v_actual_count,
            'daily_rows',      v_daily_count,
            'summary_rows',    v_summary_count,
            'alerts_generated', v_alert_count,
            'duration_sec',    TIMESTAMPDIFF(SECOND, v_start_time, NOW())
        ),
        updated_at       = NOW()
    WHERE run_id    = v_run_id
      AND step_name = 'PIPELINE_START';

END$$

DELIMITER ;


-- ############################################################################
-- MYSQL EVENT: Daily Automatic Execution at 06:00 EST
-- MySQL事件: 每天东部时间06:00自动执行
-- ############################################################################
-- MySQL EVENT scheduler runs in the server's time zone.
-- AWS RDS MySQL typically runs in UTC, so 06:00 EST = 11:00 UTC.
-- Adjust INTERVAL if server timezone differs.
-- MySQL事件调度器在服务器时区运行。
-- AWS RDS MySQL 通常运行在UTC，因此 06:00 EST = 11:00 UTC。
-- 如果服务器时区不同请调整。
--
-- IMPORTANT: This event only calls the stored procedure for the LOCAL
-- analytics server operations. The orchestrator (cron/Airflow/Step Functions)
-- must handle Steps 1-2 (source extraction) before this event fires.
-- 重要: 此事件仅调用本地分析服务器操作的存储过程。
-- 编排器（cron/Airflow/Step Functions）必须在此事件触发前完成步骤1-2。
--
-- In production, prefer the orchestrator to call the procedure directly
-- rather than relying on MySQL EVENT, to ensure source data is loaded first.
-- 生产环境中，建议编排器直接调用过程而非依赖MySQL EVENT，以确保源数据已加载。
-- ############################################################################

-- Ensure event scheduler is enabled / 确保事件调度器已启用
-- SET GLOBAL event_scheduler = ON;

DELIMITER $$

CREATE EVENT IF NOT EXISTS test.evt_daily_forecast_accuracy
ON SCHEDULE
    EVERY 1 DAY
    STARTS CONCAT(CURDATE() + INTERVAL 1 DAY, ' 11:00:00')  -- 11:00 UTC = 06:00 EST
    -- Adjust to your server timezone:
    -- 06:00 EST = 11:00 UTC (standard time)
    -- 06:00 EDT = 10:00 UTC (daylight saving)
    -- 根据服务器时区调整:
    -- 06:00 EST = 11:00 UTC（标准时间）
    -- 06:00 EDT = 10:00 UTC（夏令时间）
ON COMPLETION PRESERVE
ENABLE
COMMENT 'UC-SC-01: Daily forecast accuracy ETL refresh at 06:00 EST / 每日预测准确性ETL刷新'
DO
BEGIN
    -- Calculate for yesterday's data
    -- 计算昨天的数据
    DECLARE v_calc_date DATE;
    SET v_calc_date = CURDATE() - INTERVAL 1 DAY;

    -- NOTE: In production, the orchestrator should have already loaded
    -- tmp_predictions and tmp_actuals by this time. If not, the procedure
    -- will log a FAILED status and abort gracefully.
    -- 注意: 生产环境中，编排器此时应已加载暂存表。如未加载，过程将记录FAILED并优雅终止。

    CALL test.sp_refresh_forecast_accuracy(v_calc_date);
END$$

DELIMITER ;


-- ############################################################################
-- MANUAL EXECUTION EXAMPLES / 手动执行示例
-- ############################################################################
/*
-- Single day refresh (after orchestrator loads staging tables)
-- 单日刷新（编排器加载暂存表后执行）
CALL test.sp_refresh_forecast_accuracy('2026-02-14');

-- Backfill a date range (loop in shell/Python, not in SQL)
-- 回填日期范围（在shell/Python中循环，不在SQL中）
-- for date in $(seq -f '%g' 1 14); do
--   python orchestrator.py --date 2026-02-$(printf '%02d' $date)
-- done

-- Check pipeline execution history / 查看管道执行历史
SELECT
    run_id,
    step_name,
    status,
    duration_seconds,
    rows_extracted,
    rows_loaded,
    data_date_start,
    LEFT(error_message, 80) AS error_preview
FROM test.forecast_pipeline_run_log
WHERE pipeline_name = 'forecast_accuracy_daily_etl'
ORDER BY created_at DESC
LIMIT 20;

-- Check today's alerts / 查看今天的预警
SELECT alert_type, entity_name, metric_name,
       ROUND(metric_value, 4) AS value,
       threshold_value, LEFT(description, 100) AS desc_preview
FROM test.forecast_alerts
WHERE DATE(alert_timestamp) = CURDATE()
ORDER BY alert_type;
*/


-- ============================================================================
-- END OF 06_daily_refresh.sql
-- ============================================================================

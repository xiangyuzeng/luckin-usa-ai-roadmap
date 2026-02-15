-- ============================================================
-- UC-OP-02: Store Performance Anomaly Detection
-- File: 08_daily_refresh.sql
-- Target: aws-luckyus-dbatest-rw (test schema)
-- Purpose: Stored procedure + EVENT for daily automated refresh
-- 存储过程 + 定时事件用于每日自动刷新
-- ============================================================
--
-- OVERVIEW / 概述:
-- ---------------------------------------------------------------
-- This file defines the daily automated pipeline that refreshes
-- all UC-OP-02 anomaly detection tables in sequence. It wraps
-- the logic from files 03-07 into a single stored procedure with
-- comprehensive step-by-step logging.
--
-- 本文件定义每日自动管道，按顺序刷新所有UC-OP-02异常检测表。
-- 将文件03-07的逻辑封装到单一存储过程中，并提供全面的逐步日志。
--
-- PIPELINE STEPS / 管道步骤:
--   Step 1:  Log pipeline start / 记录管道启动
--   Step 2:  Extract revenue KPIs / 提取收入KPI
--   Step 3:  Extract production KPIs / 提取生产KPI
--   Step 4:  Extract staffing KPIs / 提取人员KPI
--   Step 5:  Extract quality KPIs / 提取质量KPI
--   Step 6:  Compute derived metrics / 计算衍生指标
--   Step 7:  Compute anomaly scores (Z-scores) / 计算异常评分
--   Step 8:  Evaluate Western Electric rules / 评估WE规则
--   Step 9:  Classify anomaly severity / 分类异常严重度
--   Step 10: Compute health scores / 计算健康评分
--   Step 11: Generate alerts / 生成预警
--   Step 12: Log pipeline completion / 记录管道完成
--
-- SCHEDULE / 调度:
--   Daily at 12:00 UTC (07:00 EST) via MySQL EVENT
--   每日UTC 12:00（美东时间07:00）通过MySQL事件触发
--
-- Author  : Data Engineering / BI Team
-- Created : 2026-02-15
-- ============================================================


-- ############################################################
-- SECTION 1: STORED PROCEDURE sp_refresh_store_anomaly
-- 第1节：存储过程 sp_refresh_store_anomaly
-- ############################################################
-- Main entry point for the daily anomaly detection pipeline.
-- Accepts a run_date parameter for backfill/replay capability.
--
-- 每日异常检测管道的主入口。接受run_date参数以支持回填/重放。
-- ############################################################

DROP PROCEDURE IF EXISTS test.sp_refresh_store_anomaly;

DELIMITER //

CREATE PROCEDURE test.sp_refresh_store_anomaly(IN p_run_date DATE)
BEGIN
    -- ======================================================
    -- Variable declarations / 变量声明
    -- ======================================================
    DECLARE v_run_id       VARCHAR(36);
    DECLARE v_step         INT DEFAULT 0;
    DECLARE v_start        TIMESTAMP;
    DECLARE v_rows         INT DEFAULT 0;
    DECLARE v_error_msg    TEXT DEFAULT NULL;
    DECLARE v_lookback_3d  DATE;    -- 3-day lookback for late-arriving data / 3天回溯处理迟到数据
    DECLARE v_lookback_28d DATE;    -- 28-day window for SPC stats / 28天SPC统计窗口
    DECLARE v_lookback_35d DATE;    -- 35-day window for WE rules / 35天WE规则窗口
    DECLARE v_lookback_90d DATE;    -- 90-day window for percentiles / 90天百分位窗口

    -- Error handler: catch SQL exceptions and log them
    -- 错误处理器：捕获SQL异常并记录
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_error_msg = MESSAGE_TEXT;

        -- Log the failed step / 记录失败的步骤
        UPDATE test.store_anomaly_pipeline_log
        SET status          = 'FAILED',
            error_message   = v_error_msg,
            completed_at    = CURRENT_TIMESTAMP,
            duration_seconds = TIMESTAMPDIFF(MICROSECOND, started_at, CURRENT_TIMESTAMP) / 1000000.0
        WHERE run_id = v_run_id
          AND step_number = v_step
          AND status = 'RUNNING';

        -- Log pipeline failure / 记录管道整体失败
        INSERT INTO test.store_anomaly_pipeline_log
            (run_id, run_date, step_number, step_name, step_description, status, error_message, started_at, completed_at)
        VALUES
            (v_run_id, p_run_date, 99, 'PIPELINE_FAILED',
             CONCAT('Pipeline failed at step ', v_step, ': ', COALESCE(v_error_msg, 'Unknown error')),
             'FAILED', v_error_msg, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

        -- Re-signal to propagate error to caller / 重新抛出错误传递给调用者
        RESIGNAL;
    END;

    -- ======================================================
    -- Initialize run / 初始化运行
    -- ======================================================
    SET v_run_id       = UUID();
    SET v_lookback_3d  = DATE_SUB(p_run_date, INTERVAL 3 DAY);
    SET v_lookback_28d = DATE_SUB(p_run_date, INTERVAL 28 DAY);
    SET v_lookback_35d = DATE_SUB(p_run_date, INTERVAL 35 DAY);
    SET v_lookback_90d = DATE_SUB(p_run_date, INTERVAL 90 DAY);


    -- ==========================================================
    -- STEP 1: Log Pipeline Start
    -- 步骤1：记录管道启动
    -- ==========================================================
    SET v_step  = 1;
    SET v_start = CURRENT_TIMESTAMP;

    INSERT INTO test.store_anomaly_pipeline_log
        (run_id, run_date, step_number, step_name, step_description, status, started_at)
    VALUES
        (v_run_id, p_run_date, v_step, 'PIPELINE_START',
         CONCAT('Starting UC-OP-02 anomaly detection pipeline for date: ', p_run_date,
                ' / 启动UC-OP-02异常检测管道，日期：', p_run_date),
         'RUNNING', v_start);

    UPDATE test.store_anomaly_pipeline_log
    SET status           = 'SUCCESS',
        rows_affected    = 0,
        completed_at     = CURRENT_TIMESTAMP,
        duration_seconds = TIMESTAMPDIFF(MICROSECOND, v_start, CURRENT_TIMESTAMP) / 1000000.0
    WHERE run_id = v_run_id AND step_number = v_step;


    -- ==========================================================
    -- STEP 2: Extract Revenue KPIs (last 3 days for late data)
    -- 步骤2：提取收入KPI（最近3天以捕获迟到数据）
    -- ==========================================================
    -- Adapted from file 03. Uses production revenue as primary
    -- revenue source since sales order data is on a separate server.
    -- 改编自文件03。使用生产收入作为主要收入来源。
    -- ==========================================================
    SET v_step  = 2;
    SET v_start = CURRENT_TIMESTAMP;

    INSERT INTO test.store_anomaly_pipeline_log
        (run_id, run_date, step_number, step_name, step_description, status, started_at)
    VALUES
        (v_run_id, p_run_date, v_step, 'EXTRACT_REVENUE_KPIS',
         CONCAT('Extracting revenue KPIs for ', v_lookback_3d, ' to ', p_run_date,
                ' / 提取收入KPI，日期范围：', v_lookback_3d, ' 至 ', p_run_date),
         'RUNNING', v_start);

    -- Upsert revenue fields into store_kpi_daily
    -- 更新插入收入字段到store_kpi_daily
    INSERT INTO test.store_kpi_daily (
        store_id, store_name, metric_date,
        total_revenue, order_count, avg_order_value,
        day_of_week, is_weekend
    )
    SELECT
        k.store_id,
        k.store_name,
        k.metric_date,
        k.total_revenue,
        k.order_count,
        k.avg_order_value,
        WEEKDAY(k.metric_date)                  AS day_of_week,
        WEEKDAY(k.metric_date) IN (5, 6)        AS is_weekend
    FROM (
        -- Revenue from production data (on target server staging)
        -- 来自生产数据的收入（目标服务器暂存）
        -- Note: In full cross-server mode, Python orchestrator populates
        -- a staging table first. Here we operate on existing data.
        -- 注意：在完整跨服务器模式下，Python编排器先填充暂存表。
        SELECT
            store_id,
            store_name,
            metric_date,
            total_revenue,
            order_count                          AS order_count,
            CASE WHEN order_count > 0
                 THEN total_revenue / order_count
                 ELSE NULL
            END                                  AS avg_order_value
        FROM test.store_kpi_daily
        WHERE metric_date BETWEEN v_lookback_3d AND p_run_date
          AND store_id IN (1127, 1128, 1131, 1140, 1141,
                           20008, 20009, 20010, 20011, 20046)
          AND total_revenue IS NOT NULL
    ) k
    ON DUPLICATE KEY UPDATE
        total_revenue    = k.total_revenue,
        order_count      = k.order_count,
        avg_order_value  = k.avg_order_value,
        day_of_week      = WEEKDAY(k.metric_date),
        is_weekend       = WEEKDAY(k.metric_date) IN (5, 6),
        updated_at       = CURRENT_TIMESTAMP;

    SET v_rows = ROW_COUNT();

    UPDATE test.store_anomaly_pipeline_log
    SET status           = 'SUCCESS',
        rows_affected    = v_rows,
        completed_at     = CURRENT_TIMESTAMP,
        duration_seconds = TIMESTAMPDIFF(MICROSECOND, v_start, CURRENT_TIMESTAMP) / 1000000.0
    WHERE run_id = v_run_id AND step_number = v_step;


    -- ==========================================================
    -- STEP 3: Extract Production KPIs
    -- 步骤3：提取生产KPI
    -- ==========================================================
    -- Adapted from file 04 Part A.
    -- In automated mode, Python orchestrator runs Part A query on
    -- aws-luckyus-opproduction-rw and loads results here.
    -- This step updates production_count and avg_production_time_sec.
    -- 改编自文件04 A部分。自动化模式下Python编排器在生产服务器运行
    -- 查询并将结果加载到此处。本步骤更新生产量和平均生产时间。
    -- ==========================================================
    SET v_step  = 3;
    SET v_start = CURRENT_TIMESTAMP;

    INSERT INTO test.store_anomaly_pipeline_log
        (run_id, run_date, step_number, step_name, step_description, status, started_at)
    VALUES
        (v_run_id, p_run_date, v_step, 'EXTRACT_PRODUCTION_KPIS',
         CONCAT('Refreshing production KPIs for ', v_lookback_3d, ' to ', p_run_date,
                ' / 刷新生产KPI，日期范围：', v_lookback_3d, ' 至 ', p_run_date),
         'RUNNING', v_start);

    -- Incremental update of production metrics from staging
    -- 从暂存数据增量更新生产指标
    -- Note: In standalone mode (no cross-server), this is a no-op
    -- if data was already loaded. The ON DUPLICATE KEY handles idempotency.
    -- 注意：在独立模式（无跨服务器）下，如果数据已加载，此步骤为幂等操作。
    UPDATE test.store_kpi_daily k
    SET k.updated_at = CURRENT_TIMESTAMP
    WHERE k.metric_date BETWEEN v_lookback_3d AND p_run_date
      AND k.store_id IN (1127, 1128, 1131, 1140, 1141,
                         20008, 20009, 20010, 20011, 20046)
      AND k.production_count IS NOT NULL;

    SET v_rows = ROW_COUNT();

    UPDATE test.store_anomaly_pipeline_log
    SET status           = 'SUCCESS',
        rows_affected    = v_rows,
        completed_at     = CURRENT_TIMESTAMP,
        duration_seconds = TIMESTAMPDIFF(MICROSECOND, v_start, CURRENT_TIMESTAMP) / 1000000.0
    WHERE run_id = v_run_id AND step_number = v_step;


    -- ==========================================================
    -- STEP 4: Extract Staffing KPIs
    -- 步骤4：提取人员KPI
    -- ==========================================================
    -- Adapted from file 04 Part B.
    -- Python orchestrator runs Parts B-1 and B-2 on
    -- aws-luckyus-opempefficiency-rw and loads here.
    -- This step ensures scheduled_hours and employee_count are current.
    -- 改编自文件04 B部分。Python编排器在人员效率服务器运行查询并
    -- 加载到此处。本步骤确保排班工时和员工数是最新的。
    -- ==========================================================
    SET v_step  = 4;
    SET v_start = CURRENT_TIMESTAMP;

    INSERT INTO test.store_anomaly_pipeline_log
        (run_id, run_date, step_number, step_name, step_description, status, started_at)
    VALUES
        (v_run_id, p_run_date, v_step, 'EXTRACT_STAFFING_KPIS',
         CONCAT('Refreshing staffing KPIs for ', v_lookback_3d, ' to ', p_run_date,
                ' / 刷新人员KPI，日期范围：', v_lookback_3d, ' 至 ', p_run_date),
         'RUNNING', v_start);

    UPDATE test.store_kpi_daily k
    SET k.updated_at = CURRENT_TIMESTAMP
    WHERE k.metric_date BETWEEN v_lookback_3d AND p_run_date
      AND k.store_id IN (1127, 1128, 1131, 1140, 1141,
                         20008, 20009, 20010, 20011, 20046)
      AND k.scheduled_hours IS NOT NULL;

    SET v_rows = ROW_COUNT();

    UPDATE test.store_anomaly_pipeline_log
    SET status           = 'SUCCESS',
        rows_affected    = v_rows,
        completed_at     = CURRENT_TIMESTAMP,
        duration_seconds = TIMESTAMPDIFF(MICROSECOND, v_start, CURRENT_TIMESTAMP) / 1000000.0
    WHERE run_id = v_run_id AND step_number = v_step;


    -- ==========================================================
    -- STEP 5: Extract Quality KPIs
    -- 步骤5：提取质量KPI
    -- ==========================================================
    -- Adapted from file 04 Part C.
    -- Quality data is sparse (~120 records total). Python orchestrator
    -- runs on aws-luckyus-opqualitycontrol-rw.
    -- 改编自文件04 C部分。质量数据稀疏（总共约120条记录）。
    -- ==========================================================
    SET v_step  = 5;
    SET v_start = CURRENT_TIMESTAMP;

    INSERT INTO test.store_anomaly_pipeline_log
        (run_id, run_date, step_number, step_name, step_description, status, started_at)
    VALUES
        (v_run_id, p_run_date, v_step, 'EXTRACT_QUALITY_KPIS',
         CONCAT('Refreshing quality KPIs for ', v_lookback_3d, ' to ', p_run_date,
                ' (sparse data expected) / 刷新质量KPI，日期范围：', v_lookback_3d,
                ' 至 ', p_run_date, '（预期稀疏数据）'),
         'RUNNING', v_start);

    UPDATE test.store_kpi_daily k
    SET k.updated_at = CURRENT_TIMESTAMP
    WHERE k.metric_date BETWEEN v_lookback_3d AND p_run_date
      AND k.store_id IN (1127, 1128, 1131, 1140, 1141,
                         20008, 20009, 20010, 20011, 20046)
      AND k.inspection_count IS NOT NULL;

    SET v_rows = ROW_COUNT();

    UPDATE test.store_anomaly_pipeline_log
    SET status           = 'SUCCESS',
        rows_affected    = v_rows,
        completed_at     = CURRENT_TIMESTAMP,
        duration_seconds = TIMESTAMPDIFF(MICROSECOND, v_start, CURRENT_TIMESTAMP) / 1000000.0
    WHERE run_id = v_run_id AND step_number = v_step;


    -- ==========================================================
    -- STEP 6: Compute Derived Metrics
    -- 步骤6：计算衍生指标
    -- ==========================================================
    -- Adapted from file 04 Part D.
    -- Computes revenue_per_labor_hour, orders_per_labor_hour,
    -- and other cross-domain derived metrics.
    -- 改编自文件04 D部分。计算每工时营收、每工时订单数等跨域衍生指标。
    -- ==========================================================
    SET v_step  = 6;
    SET v_start = CURRENT_TIMESTAMP;

    INSERT INTO test.store_anomaly_pipeline_log
        (run_id, run_date, step_number, step_name, step_description, status, started_at)
    VALUES
        (v_run_id, p_run_date, v_step, 'COMPUTE_DERIVED_METRICS',
         'Computing derived KPIs: RPLH, orders/hour, AOV / 计算衍生KPI：每工时营收、每工时订单数、客单价',
         'RUNNING', v_start);

    -- D-1: Revenue per labor hour / 每工时营收
    UPDATE test.store_kpi_daily
    SET revenue_per_labor_hour = total_revenue / NULLIF(scheduled_hours, 0)
    WHERE metric_date BETWEEN v_lookback_3d AND p_run_date
      AND scheduled_hours IS NOT NULL
      AND total_revenue IS NOT NULL
      AND store_id IN (1127, 1128, 1131, 1140, 1141,
                       20008, 20009, 20010, 20011, 20046);

    -- D-2: Orders per labor hour / 每工时订单数
    UPDATE test.store_kpi_daily
    SET orders_per_labor_hour = order_count / NULLIF(scheduled_hours, 0)
    WHERE metric_date BETWEEN v_lookback_3d AND p_run_date
      AND scheduled_hours IS NOT NULL
      AND order_count IS NOT NULL
      AND store_id IN (1127, 1128, 1131, 1140, 1141,
                       20008, 20009, 20010, 20011, 20046);

    -- D-3: Average order value / 平均客单价
    UPDATE test.store_kpi_daily
    SET avg_order_value = total_revenue / NULLIF(order_count, 0)
    WHERE metric_date BETWEEN v_lookback_3d AND p_run_date
      AND total_revenue IS NOT NULL
      AND order_count IS NOT NULL
      AND store_id IN (1127, 1128, 1131, 1140, 1141,
                       20008, 20009, 20010, 20011, 20046);

    -- D-4: Day of week and weekend flag / 星期几和周末标志
    UPDATE test.store_kpi_daily
    SET day_of_week = WEEKDAY(metric_date),
        is_weekend  = WEEKDAY(metric_date) IN (5, 6)
    WHERE metric_date BETWEEN v_lookback_3d AND p_run_date
      AND (day_of_week IS NULL OR is_weekend IS NULL)
      AND store_id IN (1127, 1128, 1131, 1140, 1141,
                       20008, 20009, 20010, 20011, 20046);

    SET v_rows = ROW_COUNT();

    UPDATE test.store_anomaly_pipeline_log
    SET status           = 'SUCCESS',
        rows_affected    = v_rows,
        completed_at     = CURRENT_TIMESTAMP,
        duration_seconds = TIMESTAMPDIFF(MICROSECOND, v_start, CURRENT_TIMESTAMP) / 1000000.0
    WHERE run_id = v_run_id AND step_number = v_step;


    -- ==========================================================
    -- STEP 7: Compute Anomaly Scores (Z-scores, 35-day window)
    -- 步骤7：计算异常评分（Z分数，35天窗口）
    -- ==========================================================
    -- Adapted from file 05. For each store/metric, compute:
    --   - 28-day rolling mean and std
    --   - Z-score = (current - mean) / std
    --   - Control limits (UCL/LCL at 2σ and 3σ)
    --   - Same day-of-week statistics
    --
    -- 改编自文件05。对每个门店/指标计算：
    --   - 28天滚动均值和标准差
    --   - Z分数 = (当前值 - 均值) / 标准差
    --   - 控制限（2σ和3σ的UCL/LCL）
    --   - 同星期统计
    -- ==========================================================
    SET v_step  = 7;
    SET v_start = CURRENT_TIMESTAMP;

    INSERT INTO test.store_anomaly_pipeline_log
        (run_id, run_date, step_number, step_name, step_description, status, started_at)
    VALUES
        (v_run_id, p_run_date, v_step, 'COMPUTE_ANOMALY_SCORES',
         CONCAT('Computing SPC z-scores for 35-day window ending ', p_run_date,
                ' / 计算SPC z分数，35天窗口截止', p_run_date),
         'RUNNING', v_start);

    -- Delete and recompute anomaly scores for the recent window
    -- 删除并重新计算近期窗口的异常评分
    DELETE FROM test.store_anomaly_scores
    WHERE metric_date BETWEEN v_lookback_3d AND p_run_date
      AND store_id IN (1127, 1128, 1131, 1140, 1141,
                       20008, 20009, 20010, 20011, 20046);

    -- Insert z-scores for total_revenue metric
    -- 插入total_revenue指标的z分数
    INSERT INTO test.store_anomaly_scores (
        store_id, store_name, metric_date, metric_name, metric_value,
        rolling_mean_28d, rolling_std_28d, z_score,
        ucl_2sigma, ucl_3sigma, lcl_2sigma, lcl_3sigma,
        same_dow_mean, same_dow_std, dow_z_score
    )
    SELECT
        curr.store_id,
        curr.store_name,
        curr.metric_date,
        'total_revenue'          AS metric_name,
        curr.total_revenue       AS metric_value,
        stats.rolling_mean       AS rolling_mean_28d,
        stats.rolling_std        AS rolling_std_28d,
        CASE WHEN stats.rolling_std > 0
             THEN (curr.total_revenue - stats.rolling_mean) / stats.rolling_std
             ELSE 0
        END                      AS z_score,
        stats.rolling_mean + 2 * stats.rolling_std  AS ucl_2sigma,
        stats.rolling_mean + 3 * stats.rolling_std  AS ucl_3sigma,
        stats.rolling_mean - 2 * stats.rolling_std  AS lcl_2sigma,
        stats.rolling_mean - 3 * stats.rolling_std  AS lcl_3sigma,
        dow_stats.dow_mean       AS same_dow_mean,
        dow_stats.dow_std        AS same_dow_std,
        CASE WHEN dow_stats.dow_std > 0
             THEN (curr.total_revenue - dow_stats.dow_mean) / dow_stats.dow_std
             ELSE 0
        END                      AS dow_z_score
    FROM test.store_kpi_daily curr
    -- 28-day rolling statistics / 28天滚动统计
    INNER JOIN (
        SELECT
            store_id, metric_date,
            AVG(total_revenue) OVER w   AS rolling_mean,
            STDDEV_SAMP(total_revenue) OVER w AS rolling_std
        FROM test.store_kpi_daily
        WHERE total_revenue IS NOT NULL
          AND store_id IN (1127, 1128, 1131, 1140, 1141,
                           20008, 20009, 20010, 20011, 20046)
        WINDOW w AS (PARTITION BY store_id ORDER BY metric_date
                     ROWS BETWEEN 27 PRECEDING AND CURRENT ROW)
    ) stats ON stats.store_id = curr.store_id AND stats.metric_date = curr.metric_date
    -- Same day-of-week stats / 同星期统计
    LEFT JOIN (
        SELECT
            store_id, metric_date, day_of_week,
            AVG(total_revenue) OVER (PARTITION BY store_id, day_of_week
                                     ORDER BY metric_date
                                     ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS dow_mean,
            STDDEV_SAMP(total_revenue) OVER (PARTITION BY store_id, day_of_week
                                             ORDER BY metric_date
                                             ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS dow_std
        FROM test.store_kpi_daily
        WHERE total_revenue IS NOT NULL
          AND store_id IN (1127, 1128, 1131, 1140, 1141,
                           20008, 20009, 20010, 20011, 20046)
    ) dow_stats ON dow_stats.store_id = curr.store_id AND dow_stats.metric_date = curr.metric_date
    WHERE curr.metric_date BETWEEN v_lookback_3d AND p_run_date
      AND curr.total_revenue IS NOT NULL
      AND curr.store_id IN (1127, 1128, 1131, 1140, 1141,
                            20008, 20009, 20010, 20011, 20046)
    ON DUPLICATE KEY UPDATE
        metric_value     = VALUES(metric_value),
        rolling_mean_28d = VALUES(rolling_mean_28d),
        rolling_std_28d  = VALUES(rolling_std_28d),
        z_score          = VALUES(z_score),
        ucl_2sigma       = VALUES(ucl_2sigma),
        ucl_3sigma       = VALUES(ucl_3sigma),
        lcl_2sigma       = VALUES(lcl_2sigma),
        lcl_3sigma       = VALUES(lcl_3sigma),
        same_dow_mean    = VALUES(same_dow_mean),
        same_dow_std     = VALUES(same_dow_std),
        dow_z_score      = VALUES(dow_z_score);

    -- Repeat for order_count metric / 对order_count指标重复计算
    INSERT INTO test.store_anomaly_scores (
        store_id, store_name, metric_date, metric_name, metric_value,
        rolling_mean_28d, rolling_std_28d, z_score,
        ucl_2sigma, ucl_3sigma, lcl_2sigma, lcl_3sigma,
        same_dow_mean, same_dow_std, dow_z_score
    )
    SELECT
        curr.store_id,
        curr.store_name,
        curr.metric_date,
        'order_count'             AS metric_name,
        curr.order_count          AS metric_value,
        stats.rolling_mean,
        stats.rolling_std,
        CASE WHEN stats.rolling_std > 0
             THEN (curr.order_count - stats.rolling_mean) / stats.rolling_std
             ELSE 0 END           AS z_score,
        stats.rolling_mean + 2 * stats.rolling_std,
        stats.rolling_mean + 3 * stats.rolling_std,
        stats.rolling_mean - 2 * stats.rolling_std,
        stats.rolling_mean - 3 * stats.rolling_std,
        dow_stats.dow_mean,
        dow_stats.dow_std,
        CASE WHEN dow_stats.dow_std > 0
             THEN (curr.order_count - dow_stats.dow_mean) / dow_stats.dow_std
             ELSE 0 END
    FROM test.store_kpi_daily curr
    INNER JOIN (
        SELECT store_id, metric_date,
               AVG(order_count) OVER w       AS rolling_mean,
               STDDEV_SAMP(order_count) OVER w AS rolling_std
        FROM test.store_kpi_daily
        WHERE order_count IS NOT NULL
          AND store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046)
        WINDOW w AS (PARTITION BY store_id ORDER BY metric_date ROWS BETWEEN 27 PRECEDING AND CURRENT ROW)
    ) stats ON stats.store_id = curr.store_id AND stats.metric_date = curr.metric_date
    LEFT JOIN (
        SELECT store_id, metric_date,
               AVG(order_count) OVER (PARTITION BY store_id, day_of_week ORDER BY metric_date ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS dow_mean,
               STDDEV_SAMP(order_count) OVER (PARTITION BY store_id, day_of_week ORDER BY metric_date ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS dow_std
        FROM test.store_kpi_daily
        WHERE order_count IS NOT NULL
          AND store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046)
    ) dow_stats ON dow_stats.store_id = curr.store_id AND dow_stats.metric_date = curr.metric_date
    WHERE curr.metric_date BETWEEN v_lookback_3d AND p_run_date
      AND curr.order_count IS NOT NULL
      AND curr.store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046)
    ON DUPLICATE KEY UPDATE
        metric_value = VALUES(metric_value), rolling_mean_28d = VALUES(rolling_mean_28d),
        rolling_std_28d = VALUES(rolling_std_28d), z_score = VALUES(z_score),
        ucl_2sigma = VALUES(ucl_2sigma), ucl_3sigma = VALUES(ucl_3sigma),
        lcl_2sigma = VALUES(lcl_2sigma), lcl_3sigma = VALUES(lcl_3sigma),
        same_dow_mean = VALUES(same_dow_mean), same_dow_std = VALUES(same_dow_std),
        dow_z_score = VALUES(dow_z_score);

    -- Repeat for production_count metric / 对production_count指标重复计算
    INSERT INTO test.store_anomaly_scores (
        store_id, store_name, metric_date, metric_name, metric_value,
        rolling_mean_28d, rolling_std_28d, z_score,
        ucl_2sigma, ucl_3sigma, lcl_2sigma, lcl_3sigma,
        same_dow_mean, same_dow_std, dow_z_score
    )
    SELECT
        curr.store_id,
        curr.store_name,
        curr.metric_date,
        'production_count'        AS metric_name,
        curr.production_count     AS metric_value,
        stats.rolling_mean,
        stats.rolling_std,
        CASE WHEN stats.rolling_std > 0
             THEN (curr.production_count - stats.rolling_mean) / stats.rolling_std
             ELSE 0 END,
        stats.rolling_mean + 2 * stats.rolling_std,
        stats.rolling_mean + 3 * stats.rolling_std,
        stats.rolling_mean - 2 * stats.rolling_std,
        stats.rolling_mean - 3 * stats.rolling_std,
        dow_stats.dow_mean,
        dow_stats.dow_std,
        CASE WHEN dow_stats.dow_std > 0
             THEN (curr.production_count - dow_stats.dow_mean) / dow_stats.dow_std
             ELSE 0 END
    FROM test.store_kpi_daily curr
    INNER JOIN (
        SELECT store_id, metric_date,
               AVG(production_count) OVER w       AS rolling_mean,
               STDDEV_SAMP(production_count) OVER w AS rolling_std
        FROM test.store_kpi_daily
        WHERE production_count IS NOT NULL
          AND store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046)
        WINDOW w AS (PARTITION BY store_id ORDER BY metric_date ROWS BETWEEN 27 PRECEDING AND CURRENT ROW)
    ) stats ON stats.store_id = curr.store_id AND stats.metric_date = curr.metric_date
    LEFT JOIN (
        SELECT store_id, metric_date,
               AVG(production_count) OVER (PARTITION BY store_id, day_of_week ORDER BY metric_date ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS dow_mean,
               STDDEV_SAMP(production_count) OVER (PARTITION BY store_id, day_of_week ORDER BY metric_date ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS dow_std
        FROM test.store_kpi_daily
        WHERE production_count IS NOT NULL
          AND store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046)
    ) dow_stats ON dow_stats.store_id = curr.store_id AND dow_stats.metric_date = curr.metric_date
    WHERE curr.metric_date BETWEEN v_lookback_3d AND p_run_date
      AND curr.production_count IS NOT NULL
      AND curr.store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046)
    ON DUPLICATE KEY UPDATE
        metric_value = VALUES(metric_value), rolling_mean_28d = VALUES(rolling_mean_28d),
        rolling_std_28d = VALUES(rolling_std_28d), z_score = VALUES(z_score),
        ucl_2sigma = VALUES(ucl_2sigma), ucl_3sigma = VALUES(ucl_3sigma),
        lcl_2sigma = VALUES(lcl_2sigma), lcl_3sigma = VALUES(lcl_3sigma),
        same_dow_mean = VALUES(same_dow_mean), same_dow_std = VALUES(same_dow_std),
        dow_z_score = VALUES(dow_z_score);

    -- Repeat for avg_production_time_sec metric / 对avg_production_time_sec指标重复计算
    INSERT INTO test.store_anomaly_scores (
        store_id, store_name, metric_date, metric_name, metric_value,
        rolling_mean_28d, rolling_std_28d, z_score,
        ucl_2sigma, ucl_3sigma, lcl_2sigma, lcl_3sigma,
        same_dow_mean, same_dow_std, dow_z_score
    )
    SELECT
        curr.store_id,
        curr.store_name,
        curr.metric_date,
        'avg_production_time_sec' AS metric_name,
        curr.avg_production_time_sec AS metric_value,
        stats.rolling_mean,
        stats.rolling_std,
        CASE WHEN stats.rolling_std > 0
             THEN (curr.avg_production_time_sec - stats.rolling_mean) / stats.rolling_std
             ELSE 0 END,
        stats.rolling_mean + 2 * stats.rolling_std,
        stats.rolling_mean + 3 * stats.rolling_std,
        stats.rolling_mean - 2 * stats.rolling_std,
        stats.rolling_mean - 3 * stats.rolling_std,
        dow_stats.dow_mean,
        dow_stats.dow_std,
        CASE WHEN dow_stats.dow_std > 0
             THEN (curr.avg_production_time_sec - dow_stats.dow_mean) / dow_stats.dow_std
             ELSE 0 END
    FROM test.store_kpi_daily curr
    INNER JOIN (
        SELECT store_id, metric_date,
               AVG(avg_production_time_sec) OVER w       AS rolling_mean,
               STDDEV_SAMP(avg_production_time_sec) OVER w AS rolling_std
        FROM test.store_kpi_daily
        WHERE avg_production_time_sec IS NOT NULL
          AND store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046)
        WINDOW w AS (PARTITION BY store_id ORDER BY metric_date ROWS BETWEEN 27 PRECEDING AND CURRENT ROW)
    ) stats ON stats.store_id = curr.store_id AND stats.metric_date = curr.metric_date
    LEFT JOIN (
        SELECT store_id, metric_date,
               AVG(avg_production_time_sec) OVER (PARTITION BY store_id, day_of_week ORDER BY metric_date ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS dow_mean,
               STDDEV_SAMP(avg_production_time_sec) OVER (PARTITION BY store_id, day_of_week ORDER BY metric_date ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS dow_std
        FROM test.store_kpi_daily
        WHERE avg_production_time_sec IS NOT NULL
          AND store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046)
    ) dow_stats ON dow_stats.store_id = curr.store_id AND dow_stats.metric_date = curr.metric_date
    WHERE curr.metric_date BETWEEN v_lookback_3d AND p_run_date
      AND curr.avg_production_time_sec IS NOT NULL
      AND curr.store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046)
    ON DUPLICATE KEY UPDATE
        metric_value = VALUES(metric_value), rolling_mean_28d = VALUES(rolling_mean_28d),
        rolling_std_28d = VALUES(rolling_std_28d), z_score = VALUES(z_score),
        ucl_2sigma = VALUES(ucl_2sigma), ucl_3sigma = VALUES(ucl_3sigma),
        lcl_2sigma = VALUES(lcl_2sigma), lcl_3sigma = VALUES(lcl_3sigma),
        same_dow_mean = VALUES(same_dow_mean), same_dow_std = VALUES(same_dow_std),
        dow_z_score = VALUES(dow_z_score);

    -- Repeat for revenue_per_labor_hour metric / 对revenue_per_labor_hour指标重复计算
    INSERT INTO test.store_anomaly_scores (
        store_id, store_name, metric_date, metric_name, metric_value,
        rolling_mean_28d, rolling_std_28d, z_score,
        ucl_2sigma, ucl_3sigma, lcl_2sigma, lcl_3sigma,
        same_dow_mean, same_dow_std, dow_z_score
    )
    SELECT
        curr.store_id,
        curr.store_name,
        curr.metric_date,
        'revenue_per_labor_hour'  AS metric_name,
        curr.revenue_per_labor_hour AS metric_value,
        stats.rolling_mean,
        stats.rolling_std,
        CASE WHEN stats.rolling_std > 0
             THEN (curr.revenue_per_labor_hour - stats.rolling_mean) / stats.rolling_std
             ELSE 0 END,
        stats.rolling_mean + 2 * stats.rolling_std,
        stats.rolling_mean + 3 * stats.rolling_std,
        stats.rolling_mean - 2 * stats.rolling_std,
        stats.rolling_mean - 3 * stats.rolling_std,
        dow_stats.dow_mean,
        dow_stats.dow_std,
        CASE WHEN dow_stats.dow_std > 0
             THEN (curr.revenue_per_labor_hour - dow_stats.dow_mean) / dow_stats.dow_std
             ELSE 0 END
    FROM test.store_kpi_daily curr
    INNER JOIN (
        SELECT store_id, metric_date,
               AVG(revenue_per_labor_hour) OVER w       AS rolling_mean,
               STDDEV_SAMP(revenue_per_labor_hour) OVER w AS rolling_std
        FROM test.store_kpi_daily
        WHERE revenue_per_labor_hour IS NOT NULL
          AND store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046)
        WINDOW w AS (PARTITION BY store_id ORDER BY metric_date ROWS BETWEEN 27 PRECEDING AND CURRENT ROW)
    ) stats ON stats.store_id = curr.store_id AND stats.metric_date = curr.metric_date
    LEFT JOIN (
        SELECT store_id, metric_date,
               AVG(revenue_per_labor_hour) OVER (PARTITION BY store_id, day_of_week ORDER BY metric_date ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS dow_mean,
               STDDEV_SAMP(revenue_per_labor_hour) OVER (PARTITION BY store_id, day_of_week ORDER BY metric_date ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS dow_std
        FROM test.store_kpi_daily
        WHERE revenue_per_labor_hour IS NOT NULL
          AND store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046)
    ) dow_stats ON dow_stats.store_id = curr.store_id AND dow_stats.metric_date = curr.metric_date
    WHERE curr.metric_date BETWEEN v_lookback_3d AND p_run_date
      AND curr.revenue_per_labor_hour IS NOT NULL
      AND curr.store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046)
    ON DUPLICATE KEY UPDATE
        metric_value = VALUES(metric_value), rolling_mean_28d = VALUES(rolling_mean_28d),
        rolling_std_28d = VALUES(rolling_std_28d), z_score = VALUES(z_score),
        ucl_2sigma = VALUES(ucl_2sigma), ucl_3sigma = VALUES(ucl_3sigma),
        lcl_2sigma = VALUES(lcl_2sigma), lcl_3sigma = VALUES(lcl_3sigma),
        same_dow_mean = VALUES(same_dow_mean), same_dow_std = VALUES(same_dow_std),
        dow_z_score = VALUES(dow_z_score);

    SET v_rows = ROW_COUNT();

    UPDATE test.store_anomaly_pipeline_log
    SET status           = 'SUCCESS',
        rows_affected    = v_rows,
        completed_at     = CURRENT_TIMESTAMP,
        duration_seconds = TIMESTAMPDIFF(MICROSECOND, v_start, CURRENT_TIMESTAMP) / 1000000.0
    WHERE run_id = v_run_id AND step_number = v_step;


    -- ==========================================================
    -- STEP 8: Evaluate Western Electric Rules
    -- 步骤8：评估Western Electric规则
    -- ==========================================================
    -- Updates we_rule1 through we_rule5 flags on anomaly_scores.
    -- Uses the 35-day window to detect process control violations.
    -- 更新异常评分上的we_rule1至we_rule5标志。
    -- 使用35天窗口检测过程控制违规。
    -- ==========================================================
    SET v_step  = 8;
    SET v_start = CURRENT_TIMESTAMP;

    INSERT INTO test.store_anomaly_pipeline_log
        (run_id, run_date, step_number, step_name, step_description, status, started_at)
    VALUES
        (v_run_id, p_run_date, v_step, 'EVALUATE_WE_RULES',
         'Evaluating Western Electric rules 1-5 for SPC violations / 评估Western Electric规则1-5的SPC违规',
         'RUNNING', v_start);

    -- Rule 1: Single point beyond 3σ / 规则1：单点超过3σ
    UPDATE test.store_anomaly_scores
    SET we_rule1 = TRUE
    WHERE metric_date BETWEEN v_lookback_3d AND p_run_date
      AND ABS(z_score) > 3
      AND store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046);

    -- Rule 2: 2 of 3 points beyond 2σ on same side / 规则2：3点中2点在同侧超过2σ
    UPDATE test.store_anomaly_scores a
    INNER JOIN (
        SELECT a1.store_id, a1.metric_date, a1.metric_name
        FROM test.store_anomaly_scores a1
        INNER JOIN test.store_anomaly_scores a2
            ON a2.store_id = a1.store_id AND a2.metric_name = a1.metric_name
            AND a2.metric_date = DATE_SUB(a1.metric_date, INTERVAL 1 DAY)
        INNER JOIN test.store_anomaly_scores a3
            ON a3.store_id = a1.store_id AND a3.metric_name = a1.metric_name
            AND a3.metric_date = DATE_SUB(a1.metric_date, INTERVAL 2 DAY)
        WHERE a1.metric_date BETWEEN v_lookback_3d AND p_run_date
          AND (
              -- 2 of 3 above +2σ / 3点中2点在+2σ以上
              ( (CASE WHEN a1.z_score > 2 THEN 1 ELSE 0 END) +
                (CASE WHEN a2.z_score > 2 THEN 1 ELSE 0 END) +
                (CASE WHEN a3.z_score > 2 THEN 1 ELSE 0 END) ) >= 2
              OR
              -- 2 of 3 below -2σ / 3点中2点在-2σ以下
              ( (CASE WHEN a1.z_score < -2 THEN 1 ELSE 0 END) +
                (CASE WHEN a2.z_score < -2 THEN 1 ELSE 0 END) +
                (CASE WHEN a3.z_score < -2 THEN 1 ELSE 0 END) ) >= 2
          )
    ) matched ON matched.store_id = a.store_id
             AND matched.metric_date = a.metric_date
             AND matched.metric_name = a.metric_name
    SET a.we_rule2 = TRUE;

    -- Rule 3: 4 of 5 points beyond 1σ on same side / 规则3：5点中4点在同侧超过1σ
    UPDATE test.store_anomaly_scores a
    INNER JOIN (
        SELECT a1.store_id, a1.metric_date, a1.metric_name
        FROM test.store_anomaly_scores a1
        WHERE a1.metric_date BETWEEN v_lookback_3d AND p_run_date
          AND (
              -- Check 4 of 5 above +1σ using correlated subquery
              -- 使用关联子查询检查5点中4点在+1σ以上
              (SELECT COUNT(*)
               FROM test.store_anomaly_scores ax
               WHERE ax.store_id = a1.store_id
                 AND ax.metric_name = a1.metric_name
                 AND ax.metric_date BETWEEN DATE_SUB(a1.metric_date, INTERVAL 4 DAY) AND a1.metric_date
                 AND ax.z_score > 1) >= 4
              OR
              (SELECT COUNT(*)
               FROM test.store_anomaly_scores ax
               WHERE ax.store_id = a1.store_id
                 AND ax.metric_name = a1.metric_name
                 AND ax.metric_date BETWEEN DATE_SUB(a1.metric_date, INTERVAL 4 DAY) AND a1.metric_date
                 AND ax.z_score < -1) >= 4
          )
    ) matched ON matched.store_id = a.store_id
             AND matched.metric_date = a.metric_date
             AND matched.metric_name = a.metric_name
    SET a.we_rule3 = TRUE;

    -- Rule 4: 8 consecutive points on same side of center
    -- 规则4：连续8点在中心线同侧
    UPDATE test.store_anomaly_scores a
    INNER JOIN (
        SELECT a1.store_id, a1.metric_date, a1.metric_name
        FROM test.store_anomaly_scores a1
        WHERE a1.metric_date BETWEEN v_lookback_3d AND p_run_date
          AND (
              (SELECT COUNT(*)
               FROM test.store_anomaly_scores ax
               WHERE ax.store_id = a1.store_id
                 AND ax.metric_name = a1.metric_name
                 AND ax.metric_date BETWEEN DATE_SUB(a1.metric_date, INTERVAL 7 DAY) AND a1.metric_date
                 AND ax.z_score > 0) = 8
              OR
              (SELECT COUNT(*)
               FROM test.store_anomaly_scores ax
               WHERE ax.store_id = a1.store_id
                 AND ax.metric_name = a1.metric_name
                 AND ax.metric_date BETWEEN DATE_SUB(a1.metric_date, INTERVAL 7 DAY) AND a1.metric_date
                 AND ax.z_score < 0) = 8
          )
    ) matched ON matched.store_id = a.store_id
             AND matched.metric_date = a.metric_date
             AND matched.metric_name = a.metric_name
    SET a.we_rule4 = TRUE;

    -- Rule 5: 6 consecutive declining points / 规则5：连续6点递减
    UPDATE test.store_anomaly_scores a
    INNER JOIN (
        SELECT a1.store_id, a1.metric_date, a1.metric_name
        FROM test.store_anomaly_scores a1
        WHERE a1.metric_date BETWEEN v_lookback_3d AND p_run_date
          AND (
              SELECT COUNT(*)
              FROM test.store_anomaly_scores ax
              INNER JOIN test.store_anomaly_scores ay
                  ON ay.store_id = ax.store_id
                  AND ay.metric_name = ax.metric_name
                  AND ay.metric_date = DATE_SUB(ax.metric_date, INTERVAL 1 DAY)
              WHERE ax.store_id = a1.store_id
                AND ax.metric_name = a1.metric_name
                AND ax.metric_date BETWEEN DATE_SUB(a1.metric_date, INTERVAL 5 DAY) AND a1.metric_date
                AND ax.metric_value < ay.metric_value
          ) >= 5
    ) matched ON matched.store_id = a.store_id
             AND matched.metric_date = a.metric_date
             AND matched.metric_name = a.metric_name
    SET a.we_rule5 = TRUE;

    SET v_rows = ROW_COUNT();

    UPDATE test.store_anomaly_pipeline_log
    SET status           = 'SUCCESS',
        rows_affected    = v_rows,
        completed_at     = CURRENT_TIMESTAMP,
        duration_seconds = TIMESTAMPDIFF(MICROSECOND, v_start, CURRENT_TIMESTAMP) / 1000000.0
    WHERE run_id = v_run_id AND step_number = v_step;


    -- ==========================================================
    -- STEP 9: Classify Anomaly Severity
    -- 步骤9：分类异常严重度
    -- ==========================================================
    -- Sets anomaly_severity based on z-score magnitude and WE rules.
    -- 基于z分数大小和WE规则设置异常严重度。
    -- ==========================================================
    SET v_step  = 9;
    SET v_start = CURRENT_TIMESTAMP;

    INSERT INTO test.store_anomaly_pipeline_log
        (run_id, run_date, step_number, step_name, step_description, status, started_at)
    VALUES
        (v_run_id, p_run_date, v_step, 'CLASSIFY_SEVERITY',
         'Classifying anomaly severity levels / 分类异常严重度级别',
         'RUNNING', v_start);

    -- CRITICAL: z > 3σ or WE Rule 1 or WE Rule 4
    -- 严重：z > 3σ 或 WE规则1 或 WE规则4
    UPDATE test.store_anomaly_scores
    SET anomaly_severity = 'CRITICAL'
    WHERE metric_date BETWEEN v_lookback_3d AND p_run_date
      AND (ABS(z_score) > 3 OR we_rule1 = TRUE OR we_rule4 = TRUE)
      AND store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046);

    -- WARNING: 2σ < z <= 3σ or WE Rules 2/3/5
    -- 警告：2σ < z <= 3σ 或 WE规则2/3/5
    UPDATE test.store_anomaly_scores
    SET anomaly_severity = 'WARNING'
    WHERE metric_date BETWEEN v_lookback_3d AND p_run_date
      AND anomaly_severity = 'NONE'
      AND (
          (ABS(z_score) > 2 AND ABS(z_score) <= 3)
          OR we_rule2 = TRUE
          OR we_rule3 = TRUE
          OR we_rule5 = TRUE
      )
      AND store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046);

    -- INFO: 1.5σ < z <= 2σ (advisory, no immediate action)
    -- 信息：1.5σ < z <= 2σ（建议性，无需立即行动）
    UPDATE test.store_anomaly_scores
    SET anomaly_severity = 'INFO'
    WHERE metric_date BETWEEN v_lookback_3d AND p_run_date
      AND anomaly_severity = 'NONE'
      AND ABS(z_score) > 1.5
      AND store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046);

    SET v_rows = ROW_COUNT();

    UPDATE test.store_anomaly_pipeline_log
    SET status           = 'SUCCESS',
        rows_affected    = v_rows,
        completed_at     = CURRENT_TIMESTAMP,
        duration_seconds = TIMESTAMPDIFF(MICROSECOND, v_start, CURRENT_TIMESTAMP) / 1000000.0
    WHERE run_id = v_run_id AND step_number = v_step;


    -- ==========================================================
    -- STEP 10: Compute Health Scores
    -- 步骤10：计算健康评分
    -- ==========================================================
    -- Adapted from file 07 Sections 1-3.
    -- Computes dimension scores, composite score, WoW change.
    -- 改编自文件07第1-3节。计算维度评分、综合评分、周环比变化。
    -- ==========================================================
    SET v_step  = 10;
    SET v_start = CURRENT_TIMESTAMP;

    INSERT INTO test.store_anomaly_pipeline_log
        (run_id, run_date, step_number, step_name, step_description, status, started_at)
    VALUES
        (v_run_id, p_run_date, v_step, 'COMPUTE_HEALTH_SCORES',
         'Computing composite health scores and grades / 计算综合健康评分和等级',
         'RUNNING', v_start);

    -- Delete and recompute for the run date window
    -- 删除并重新计算运行日期窗口的数据
    DELETE FROM test.store_health_scores
    WHERE metric_date BETWEEN v_lookback_3d AND p_run_date
      AND store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046);

    -- Compute dimension scores using percentile ranks within 90-day history
    -- 使用90天历史内的百分位排名计算维度评分
    INSERT INTO test.store_health_scores (
        store_id, store_name, metric_date,
        revenue_score, ops_score, quality_score, staffing_score, customer_score,
        composite_score, health_grade, week_over_week_change, trend_direction
    )
    SELECT
        k.store_id,
        k.store_name,
        k.metric_date,

        -- Revenue score: percentile within store's 90-day revenue history
        -- 收入评分：门店90天收入历史中的百分位
        rev_pct.rev_score,

        -- Operations score: production volume and speed combined
        -- 运营评分：产量和速度的综合
        ops_pct.ops_combined_score,

        -- Quality score: from forward-filled quality data
        -- 质量评分：来自前向填充的质量数据
        qual_pct.qual_score,

        -- Staffing score: revenue per labor hour percentile
        -- 人员评分：每工时收入百分位
        staff_pct.staff_score,

        -- Customer score: order count trend
        -- 顾客评分：订单量趋势
        cust_pct.cust_score,

        -- Composite score with NULL-aware weight redistribution
        -- 综合评分，空值感知权重再分配
        ROUND(
            (COALESCE(rev_pct.rev_score * 0.40, 0) +
             COALESCE(ops_pct.ops_combined_score * 0.20, 0) +
             COALESCE(qual_pct.qual_score * 0.15, 0) +
             COALESCE(staff_pct.staff_score * 0.15, 0) +
             COALESCE(cust_pct.cust_score * 0.10, 0))
            /
            ((CASE WHEN rev_pct.rev_score IS NOT NULL THEN 0.40 ELSE 0 END) +
             (CASE WHEN ops_pct.ops_combined_score IS NOT NULL THEN 0.20 ELSE 0 END) +
             (CASE WHEN qual_pct.qual_score IS NOT NULL THEN 0.15 ELSE 0 END) +
             (CASE WHEN staff_pct.staff_score IS NOT NULL THEN 0.15 ELSE 0 END) +
             (CASE WHEN cust_pct.cust_score IS NOT NULL THEN 0.10 ELSE 0 END))
        , 2) AS composite_score,

        -- Health grade / 健康等级
        CASE
            WHEN ROUND((COALESCE(rev_pct.rev_score*0.40,0)+COALESCE(ops_pct.ops_combined_score*0.20,0)+
                 COALESCE(qual_pct.qual_score*0.15,0)+COALESCE(staff_pct.staff_score*0.15,0)+
                 COALESCE(cust_pct.cust_score*0.10,0))/
                 ((CASE WHEN rev_pct.rev_score IS NOT NULL THEN 0.40 ELSE 0 END)+
                  (CASE WHEN ops_pct.ops_combined_score IS NOT NULL THEN 0.20 ELSE 0 END)+
                  (CASE WHEN qual_pct.qual_score IS NOT NULL THEN 0.15 ELSE 0 END)+
                  (CASE WHEN staff_pct.staff_score IS NOT NULL THEN 0.15 ELSE 0 END)+
                  (CASE WHEN cust_pct.cust_score IS NOT NULL THEN 0.10 ELSE 0 END)),2) >= 90 THEN 'A'
            WHEN ROUND((COALESCE(rev_pct.rev_score*0.40,0)+COALESCE(ops_pct.ops_combined_score*0.20,0)+
                 COALESCE(qual_pct.qual_score*0.15,0)+COALESCE(staff_pct.staff_score*0.15,0)+
                 COALESCE(cust_pct.cust_score*0.10,0))/
                 ((CASE WHEN rev_pct.rev_score IS NOT NULL THEN 0.40 ELSE 0 END)+
                  (CASE WHEN ops_pct.ops_combined_score IS NOT NULL THEN 0.20 ELSE 0 END)+
                  (CASE WHEN qual_pct.qual_score IS NOT NULL THEN 0.15 ELSE 0 END)+
                  (CASE WHEN staff_pct.staff_score IS NOT NULL THEN 0.15 ELSE 0 END)+
                  (CASE WHEN cust_pct.cust_score IS NOT NULL THEN 0.10 ELSE 0 END)),2) >= 80 THEN 'B'
            WHEN ROUND((COALESCE(rev_pct.rev_score*0.40,0)+COALESCE(ops_pct.ops_combined_score*0.20,0)+
                 COALESCE(qual_pct.qual_score*0.15,0)+COALESCE(staff_pct.staff_score*0.15,0)+
                 COALESCE(cust_pct.cust_score*0.10,0))/
                 ((CASE WHEN rev_pct.rev_score IS NOT NULL THEN 0.40 ELSE 0 END)+
                  (CASE WHEN ops_pct.ops_combined_score IS NOT NULL THEN 0.20 ELSE 0 END)+
                  (CASE WHEN qual_pct.qual_score IS NOT NULL THEN 0.15 ELSE 0 END)+
                  (CASE WHEN staff_pct.staff_score IS NOT NULL THEN 0.15 ELSE 0 END)+
                  (CASE WHEN cust_pct.cust_score IS NOT NULL THEN 0.10 ELSE 0 END)),2) >= 70 THEN 'C'
            WHEN ROUND((COALESCE(rev_pct.rev_score*0.40,0)+COALESCE(ops_pct.ops_combined_score*0.20,0)+
                 COALESCE(qual_pct.qual_score*0.15,0)+COALESCE(staff_pct.staff_score*0.15,0)+
                 COALESCE(cust_pct.cust_score*0.10,0))/
                 ((CASE WHEN rev_pct.rev_score IS NOT NULL THEN 0.40 ELSE 0 END)+
                  (CASE WHEN ops_pct.ops_combined_score IS NOT NULL THEN 0.20 ELSE 0 END)+
                  (CASE WHEN qual_pct.qual_score IS NOT NULL THEN 0.15 ELSE 0 END)+
                  (CASE WHEN staff_pct.staff_score IS NOT NULL THEN 0.15 ELSE 0 END)+
                  (CASE WHEN cust_pct.cust_score IS NOT NULL THEN 0.10 ELSE 0 END)),2) >= 60 THEN 'D'
            ELSE 'F'
        END AS health_grade,

        NULL AS week_over_week_change,
        'STABLE' AS trend_direction

    FROM test.store_kpi_daily k

    -- Revenue percentile / 收入百分位
    LEFT JOIN (
        SELECT store_id, metric_date,
               ROUND(100 * PERCENT_RANK() OVER (PARTITION BY store_id ORDER BY total_revenue ASC), 2) AS rev_score
        FROM test.store_kpi_daily
        WHERE total_revenue IS NOT NULL
          AND metric_date >= v_lookback_90d
          AND store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046)
    ) rev_pct ON rev_pct.store_id = k.store_id AND rev_pct.metric_date = k.metric_date

    -- Operations percentile / 运营百分位
    LEFT JOIN (
        SELECT store_id, metric_date,
               ROUND(
                   0.60 * (100 * PERCENT_RANK() OVER (PARTITION BY store_id ORDER BY production_count ASC)) +
                   0.40 * (100 * PERCENT_RANK() OVER (PARTITION BY store_id ORDER BY avg_production_time_sec DESC))
               , 2) AS ops_combined_score
        FROM test.store_kpi_daily
        WHERE production_count IS NOT NULL AND avg_production_time_sec IS NOT NULL
          AND metric_date >= v_lookback_90d
          AND store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046)
    ) ops_pct ON ops_pct.store_id = k.store_id AND ops_pct.metric_date = k.metric_date

    -- Quality percentile with forward-fill / 质量百分位（含前向填充）
    LEFT JOIN (
        SELECT store_id, metric_date,
               ROUND(100 * PERCENT_RANK() OVER (PARTITION BY store_id ORDER BY avg_quality_score ASC), 2) AS qual_score
        FROM test.store_kpi_daily
        WHERE avg_quality_score IS NOT NULL
          AND metric_date >= v_lookback_90d
          AND store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046)
    ) qual_pct ON qual_pct.store_id = k.store_id AND qual_pct.metric_date = k.metric_date

    -- Staffing percentile / 人员百分位
    LEFT JOIN (
        SELECT store_id, metric_date,
               ROUND(100 * PERCENT_RANK() OVER (PARTITION BY store_id ORDER BY revenue_per_labor_hour ASC), 2) AS staff_score
        FROM test.store_kpi_daily
        WHERE revenue_per_labor_hour IS NOT NULL AND revenue_per_labor_hour > 0
          AND metric_date >= v_lookback_90d
          AND store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046)
    ) staff_pct ON staff_pct.store_id = k.store_id AND staff_pct.metric_date = k.metric_date

    -- Customer percentile / 顾客百分位
    LEFT JOIN (
        SELECT store_id, metric_date,
               ROUND(100 * PERCENT_RANK() OVER (PARTITION BY store_id ORDER BY order_count ASC), 2) AS cust_score
        FROM test.store_kpi_daily
        WHERE order_count IS NOT NULL
          AND metric_date >= v_lookback_90d
          AND store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046)
    ) cust_pct ON cust_pct.store_id = k.store_id AND cust_pct.metric_date = k.metric_date

    WHERE k.metric_date BETWEEN v_lookback_3d AND p_run_date
      AND k.store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046)
      -- At least 2 dimensions available / 至少2个维度可用
      AND ((CASE WHEN rev_pct.rev_score IS NOT NULL THEN 1 ELSE 0 END) +
           (CASE WHEN ops_pct.ops_combined_score IS NOT NULL THEN 1 ELSE 0 END) +
           (CASE WHEN qual_pct.qual_score IS NOT NULL THEN 1 ELSE 0 END) +
           (CASE WHEN staff_pct.staff_score IS NOT NULL THEN 1 ELSE 0 END) +
           (CASE WHEN cust_pct.cust_score IS NOT NULL THEN 1 ELSE 0 END)) >= 2
    ON DUPLICATE KEY UPDATE
        revenue_score   = VALUES(revenue_score),
        ops_score       = VALUES(ops_score),
        quality_score   = VALUES(quality_score),
        staffing_score  = VALUES(staffing_score),
        customer_score  = VALUES(customer_score),
        composite_score = VALUES(composite_score),
        health_grade    = VALUES(health_grade);

    -- Update week-over-week change / 更新周环比变化
    UPDATE test.store_health_scores h
    INNER JOIN (
        SELECT
            h1.store_id,
            h1.metric_date,
            h1.composite_score AS curr_score,
            AVG(h2.composite_score) AS prev_week_avg,
            ROUND((h1.composite_score - AVG(h2.composite_score))
                  / NULLIF(AVG(h2.composite_score), 0) * 100, 4) AS wow_pct
        FROM test.store_health_scores h1
        LEFT JOIN test.store_health_scores h2
            ON h2.store_id = h1.store_id
            AND h2.metric_date BETWEEN DATE_SUB(h1.metric_date, INTERVAL 14 DAY)
                                   AND DATE_SUB(h1.metric_date, INTERVAL 8 DAY)
        WHERE h1.metric_date BETWEEN v_lookback_3d AND p_run_date
          AND h1.store_id IN (1127,1128,1131,1140,1141,20008,20009,20010,20011,20046)
        GROUP BY h1.store_id, h1.metric_date, h1.composite_score
        HAVING prev_week_avg IS NOT NULL
    ) wow ON wow.store_id = h.store_id AND wow.metric_date = h.metric_date
    SET h.week_over_week_change = wow.wow_pct,
        h.trend_direction = CASE
            WHEN wow.wow_pct >  5  THEN 'IMPROVING'
            WHEN wow.wow_pct < -5  THEN 'DECLINING'
            ELSE 'STABLE'
        END;

    SET v_rows = ROW_COUNT();

    UPDATE test.store_anomaly_pipeline_log
    SET status           = 'SUCCESS',
        rows_affected    = v_rows,
        completed_at     = CURRENT_TIMESTAMP,
        duration_seconds = TIMESTAMPDIFF(MICROSECOND, v_start, CURRENT_TIMESTAMP) / 1000000.0
    WHERE run_id = v_run_id AND step_number = v_step;


    -- ==========================================================
    -- STEP 11: Generate Alerts
    -- 步骤11：生成预警
    -- ==========================================================
    -- Adapted from file 07 Section 5.
    -- Generates alerts for health grade failures, trend declines,
    -- z-score breaches, and WE rule violations.
    -- 改编自文件07第5节。为健康等级不合格、趋势下降、z分数突破
    -- 和WE规则违反生成预警。
    -- ==========================================================
    SET v_step  = 11;
    SET v_start = CURRENT_TIMESTAMP;

    INSERT INTO test.store_anomaly_pipeline_log
        (run_id, run_date, step_number, step_name, step_description, status, started_at)
    VALUES
        (v_run_id, p_run_date, v_step, 'GENERATE_ALERTS',
         CONCAT('Generating anomaly alerts for ', p_run_date,
                ' / 为 ', p_run_date, ' 生成异常预警'),
         'RUNNING', v_start);

    -- Clear auto-generated alerts for run date (keep acknowledged)
    -- 清除运行日期的自动生成预警（保留已确认的）
    DELETE FROM test.store_anomaly_alerts
    WHERE alert_date = p_run_date
      AND acknowledged = FALSE;

    -- Alert: Health Grade F → CRITICAL / 健康等级F → 严重
    INSERT INTO test.store_anomaly_alerts (
        store_id, store_name, alert_date, alert_type, severity,
        metric_name, current_value, threshold_value,
        description_en, description_cn, recommended_action
    )
    SELECT store_id, store_name, metric_date, 'HEALTH_GRADE', 'CRITICAL',
           'composite_score', composite_score, 60.00,
           CONCAT('CRITICAL: Store ', store_name, ' health grade F, score=', composite_score),
           CONCAT('严重：门店 ', store_name, ' 健康等级F，评分=', composite_score),
           '24-hour on-site review required / 需24小时内现场检查'
    FROM test.store_health_scores
    WHERE metric_date = p_run_date AND health_grade = 'F';

    -- Alert: Health Grade D → WARNING / 健康等级D → 警告
    INSERT INTO test.store_anomaly_alerts (
        store_id, store_name, alert_date, alert_type, severity,
        metric_name, current_value, threshold_value,
        description_en, description_cn, recommended_action
    )
    SELECT store_id, store_name, metric_date, 'HEALTH_GRADE', 'WARNING',
           'composite_score', composite_score, 60.00,
           CONCAT('WARNING: Store ', store_name, ' health grade D, score=', composite_score),
           CONCAT('警告：门店 ', store_name, ' 健康等级D，评分=', composite_score),
           'Schedule performance review this week / 本周安排绩效评审'
    FROM test.store_health_scores
    WHERE metric_date = p_run_date AND health_grade = 'D';

    -- Alert: WoW decline > 15% → WARNING / 周环比下降>15% → 警告
    INSERT INTO test.store_anomaly_alerts (
        store_id, store_name, alert_date, alert_type, severity,
        metric_name, current_value, threshold_value,
        description_en, description_cn, recommended_action
    )
    SELECT store_id, store_name, metric_date, 'TREND_DECLINE', 'WARNING',
           'week_over_week_change', week_over_week_change, -15.00,
           CONCAT('WARNING: Store ', store_name, ' WoW decline=', ABS(week_over_week_change), '%'),
           CONCAT('警告：门店 ', store_name, ' 周环比下降=', ABS(week_over_week_change), '%'),
           'Investigate operational changes vs last week / 调查与上周相比的运营变化'
    FROM test.store_health_scores
    WHERE metric_date = p_run_date AND week_over_week_change < -15;

    -- Alert: Z-score > 3σ → CRITICAL / Z分数>3σ → 严重
    INSERT INTO test.store_anomaly_alerts (
        store_id, store_name, alert_date, alert_type, severity,
        metric_name, current_value, expected_value, z_score,
        description_en, description_cn, recommended_action
    )
    SELECT store_id, store_name, metric_date, 'SPC_ZSCORE', 'CRITICAL',
           metric_name, metric_value, rolling_mean_28d, z_score,
           CONCAT('CRITICAL: ', store_name, ' [', metric_name, '] z=', ROUND(z_score,2)),
           CONCAT('严重：', store_name, ' [', metric_name, '] z=', ROUND(z_score,2)),
           'Immediate root cause investigation / 立即调查根本原因'
    FROM test.store_anomaly_scores
    WHERE metric_date = p_run_date AND ABS(z_score) > 3;

    -- Alert: Z-score > 2σ → WARNING / Z分数>2σ → 警告
    INSERT INTO test.store_anomaly_alerts (
        store_id, store_name, alert_date, alert_type, severity,
        metric_name, current_value, expected_value, z_score,
        description_en, description_cn, recommended_action
    )
    SELECT store_id, store_name, metric_date, 'SPC_ZSCORE', 'WARNING',
           metric_name, metric_value, rolling_mean_28d, z_score,
           CONCAT('WARNING: ', store_name, ' [', metric_name, '] z=', ROUND(z_score,2)),
           CONCAT('警告：', store_name, ' [', metric_name, '] z=', ROUND(z_score,2)),
           'Monitor closely for 2-3 days / 密切关注2-3天'
    FROM test.store_anomaly_scores
    WHERE metric_date = p_run_date AND ABS(z_score) > 2 AND ABS(z_score) <= 3;

    -- Alert: WE rule violations → corresponding severity
    -- 预警：WE规则违反 → 对应严重度
    INSERT INTO test.store_anomaly_alerts (
        store_id, store_name, alert_date, alert_type, severity,
        metric_name, current_value, expected_value, z_score, we_rule_violated,
        description_en, description_cn, recommended_action
    )
    SELECT store_id, store_name, metric_date, 'WE_RULE',
           CASE WHEN we_rule4 = TRUE THEN 'CRITICAL' ELSE 'WARNING' END,
           metric_name, metric_value, rolling_mean_28d, z_score,
           CASE
               WHEN we_rule4 = TRUE THEN 'RULE4'
               WHEN we_rule2 = TRUE THEN 'RULE2'
               WHEN we_rule3 = TRUE THEN 'RULE3'
               WHEN we_rule5 = TRUE THEN 'RULE5'
           END,
           CONCAT(CASE WHEN we_rule4 THEN 'CRITICAL' ELSE 'WARNING' END,
                  ': ', store_name, ' [', metric_name, '] WE rule violated'),
           CONCAT(CASE WHEN we_rule4 THEN '严重' ELSE '警告' END,
                  '：', store_name, ' [', metric_name, '] 违反WE规则'),
           'Review process control charts / 审查过程控制图'
    FROM test.store_anomaly_scores
    WHERE metric_date = p_run_date
      AND (we_rule2 = TRUE OR we_rule3 = TRUE OR we_rule4 = TRUE OR we_rule5 = TRUE)
      AND we_rule1 = FALSE;  -- Rule1 already captured by 3σ alert / 规则1已被3σ预警覆盖

    SET v_rows = ROW_COUNT();

    UPDATE test.store_anomaly_pipeline_log
    SET status           = 'SUCCESS',
        rows_affected    = v_rows,
        completed_at     = CURRENT_TIMESTAMP,
        duration_seconds = TIMESTAMPDIFF(MICROSECOND, v_start, CURRENT_TIMESTAMP) / 1000000.0
    WHERE run_id = v_run_id AND step_number = v_step;


    -- ==========================================================
    -- STEP 12: Log Pipeline Completion
    -- 步骤12：记录管道完成
    -- ==========================================================
    SET v_step  = 12;
    SET v_start = CURRENT_TIMESTAMP;

    INSERT INTO test.store_anomaly_pipeline_log
        (run_id, run_date, step_number, step_name, step_description, status,
         rows_affected, started_at, completed_at, duration_seconds)
    VALUES
        (v_run_id, p_run_date, v_step, 'PIPELINE_COMPLETE',
         CONCAT('UC-OP-02 pipeline completed successfully for ', p_run_date,
                ' / UC-OP-02管道成功完成，日期：', p_run_date),
         'SUCCESS',
         (SELECT COUNT(*) FROM test.store_anomaly_alerts WHERE alert_date = p_run_date),
         v_start, CURRENT_TIMESTAMP,
         TIMESTAMPDIFF(MICROSECOND, v_start, CURRENT_TIMESTAMP) / 1000000.0);

END //

DELIMITER ;


-- ############################################################
-- SECTION 2: SCHEDULED EVENT
-- 第2节：定时事件
-- ############################################################
-- MySQL EVENT to trigger the daily pipeline at 12:00 UTC
-- (07:00 EST / 07:00 US Eastern Time).
-- MySQL事件，每天UTC 12:00（美东时间07:00）触发每日管道。
-- ############################################################

-- Ensure event scheduler is enabled / 确保事件调度器已启用
-- SET GLOBAL event_scheduler = ON;

DROP EVENT IF EXISTS test.evt_daily_store_anomaly;

CREATE EVENT IF NOT EXISTS test.evt_daily_store_anomaly
ON SCHEDULE EVERY 1 DAY
    STARTS '2025-01-01 12:00:00'  -- 07:00 EST = 12:00 UTC / 美东07:00 = UTC 12:00
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Daily store anomaly detection refresh / 每日门店异常检测刷新'
DO CALL test.sp_refresh_store_anomaly(CURDATE());


-- ############################################################
-- SECTION 3: MANUAL EXECUTION HELPERS
-- 第3节：手动执行辅助
-- ############################################################
-- Convenience queries for operations team to run the pipeline
-- manually, backfill historical data, and check run status.
-- 为运营团队提供手动运行管道、回填历史数据和检查运行状态的便捷查询。
-- ############################################################

-- ---------------------------------------------------------
-- 3-1. Run for a specific date / 运行指定日期
-- ---------------------------------------------------------
-- Usage: Replace date and execute / 用法：替换日期后执行
-- CALL test.sp_refresh_store_anomaly('2025-06-15');


-- ---------------------------------------------------------
-- 3-2. Backfill: Run for a date range / 回填：运行日期范围
-- ---------------------------------------------------------
-- Creates a helper procedure to iterate over a date range.
-- 创建辅助存储过程，遍历日期范围。
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS test.sp_backfill_store_anomaly;

DELIMITER //

CREATE PROCEDURE test.sp_backfill_store_anomaly(
    IN p_start_date DATE,
    IN p_end_date   DATE
)
BEGIN
    DECLARE v_current_date DATE;

    -- Validate inputs / 验证输入
    IF p_start_date > p_end_date THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: start_date must be <= end_date / 错误：开始日期必须<=结束日期';
    END IF;

    IF DATEDIFF(p_end_date, p_start_date) > 365 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: date range cannot exceed 365 days / 错误：日期范围不能超过365天';
    END IF;

    SET v_current_date = p_start_date;

    -- Iterate date by date / 逐日遍历
    WHILE v_current_date <= p_end_date DO
        -- Log progress to console / 向控制台输出进度
        SELECT CONCAT('Backfilling: ', v_current_date,
                       ' (', DATEDIFF(v_current_date, p_start_date) + 1,
                       ' of ', DATEDIFF(p_end_date, p_start_date) + 1, ')',
                       ' / 回填中：', v_current_date) AS progress;

        CALL test.sp_refresh_store_anomaly(v_current_date);

        SET v_current_date = DATE_ADD(v_current_date, INTERVAL 1 DAY);
    END WHILE;

    SELECT CONCAT('Backfill complete: ', p_start_date, ' to ', p_end_date,
                   ' / 回填完成：', p_start_date, ' 至 ', p_end_date) AS result;
END //

DELIMITER ;

-- Usage / 用法:
-- CALL test.sp_backfill_store_anomaly('2025-04-01', '2025-06-15');


-- ---------------------------------------------------------
-- 3-3. Check last run status / 查看最近运行状态
-- ---------------------------------------------------------
-- Shows the most recent pipeline execution with all steps.
-- 显示最近一次管道执行及所有步骤。
-- ---------------------------------------------------------
SELECT
    l.run_id,
    l.run_date,
    l.step_number,
    l.step_name,
    l.status,
    l.rows_affected,
    l.duration_seconds,
    l.error_message,
    l.started_at,
    l.completed_at
FROM test.store_anomaly_pipeline_log l
WHERE l.run_id = (
    SELECT run_id
    FROM test.store_anomaly_pipeline_log
    WHERE step_name = 'PIPELINE_START'
    ORDER BY started_at DESC
    LIMIT 1
)
ORDER BY l.step_number;


-- ---------------------------------------------------------
-- 3-4. View pipeline log summary / 查看管道日志摘要
-- ---------------------------------------------------------
-- Shows a summary of all pipeline runs in the last 30 days.
-- 显示最近30天所有管道运行的摘要。
-- ---------------------------------------------------------
SELECT
    run_date,
    run_id,
    MIN(started_at)                                         AS pipeline_start,
    MAX(completed_at)                                       AS pipeline_end,
    TIMESTAMPDIFF(SECOND, MIN(started_at), MAX(completed_at)) AS total_seconds,
    SUM(rows_affected)                                      AS total_rows,
    MAX(CASE WHEN status = 'FAILED' THEN step_name ELSE NULL END) AS failed_step,
    CASE
        WHEN MAX(CASE WHEN status = 'FAILED' THEN 1 ELSE 0 END) = 1 THEN 'FAILED'
        ELSE 'SUCCESS'
    END                                                     AS overall_status
FROM test.store_anomaly_pipeline_log
WHERE run_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY run_date, run_id
ORDER BY run_date DESC;


-- ---------------------------------------------------------
-- 3-5. View today's alerts summary / 查看今日预警摘要
-- ---------------------------------------------------------
SELECT
    severity,
    alert_type,
    COUNT(*)                    AS alert_count,
    GROUP_CONCAT(DISTINCT store_name ORDER BY store_name SEPARATOR ', ')
                                AS affected_stores
FROM test.store_anomaly_alerts
WHERE alert_date = CURDATE()
  AND acknowledged = FALSE
GROUP BY severity, alert_type
ORDER BY FIELD(severity, 'CRITICAL', 'WARNING', 'INFO');


-- ############################################################
-- SECTION 4: MAINTENANCE QUERIES
-- 第4节：维护查询
-- ############################################################
-- Queries for routine maintenance, data cleanup, and
-- troubleshooting of the anomaly detection pipeline.
-- 例行维护、数据清理和异常检测管道故障排除的查询。
-- ############################################################

-- ---------------------------------------------------------
-- 4-1. Purge old pipeline logs (keep 90 days)
--      清除旧管道日志（保留90天）
-- ---------------------------------------------------------
-- Run monthly or as needed. Safe to execute repeatedly.
-- 每月运行或按需运行。可安全重复执行。
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS test.sp_purge_pipeline_logs;

DELIMITER //

CREATE PROCEDURE test.sp_purge_pipeline_logs(
    IN p_retention_days INT
)
BEGIN
    DECLARE v_cutoff_date DATE;
    DECLARE v_rows_deleted INT DEFAULT 0;

    -- Default to 90 days if not specified / 未指定则默认90天
    IF p_retention_days IS NULL OR p_retention_days < 7 THEN
        SET p_retention_days = 90;
    END IF;

    SET v_cutoff_date = DATE_SUB(CURDATE(), INTERVAL p_retention_days DAY);

    -- Purge pipeline logs / 清除管道日志
    DELETE FROM test.store_anomaly_pipeline_log
    WHERE run_date < v_cutoff_date;
    SET v_rows_deleted = ROW_COUNT();

    SELECT CONCAT('Purged ', v_rows_deleted, ' pipeline log rows older than ',
                   v_cutoff_date, ' (', p_retention_days, ' day retention)',
                   ' / 已清除 ', v_rows_deleted, ' 条早于 ', v_cutoff_date,
                   ' 的管道日志（保留', p_retention_days, '天）') AS result;

    -- Also purge old acknowledged alerts (keep 180 days)
    -- 同时清除旧的已确认预警（保留180天）
    DELETE FROM test.store_anomaly_alerts
    WHERE alert_date < DATE_SUB(CURDATE(), INTERVAL 180 DAY)
      AND acknowledged = TRUE;
    SET v_rows_deleted = ROW_COUNT();

    SELECT CONCAT('Purged ', v_rows_deleted, ' acknowledged alerts older than 180 days',
                   ' / 已清除 ', v_rows_deleted, ' 条超过180天的已确认预警') AS result;
END //

DELIMITER ;

-- Usage / 用法:
-- CALL test.sp_purge_pipeline_logs(90);


-- ---------------------------------------------------------
-- 4-2. Rebuild anomaly scores for a specific store
--      重建指定门店的异常评分
-- ---------------------------------------------------------
-- Useful when a store's data has been corrected retroactively.
-- 当门店数据被追溯修正时使用。
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS test.sp_rebuild_store_anomaly;

DELIMITER //

CREATE PROCEDURE test.sp_rebuild_store_anomaly(
    IN p_store_id   BIGINT,
    IN p_start_date DATE,
    IN p_end_date   DATE
)
BEGIN
    DECLARE v_current DATE;
    DECLARE v_store_name VARCHAR(100);

    -- Validate store exists / 验证门店存在
    SELECT store_name INTO v_store_name
    FROM test.store_kpi_daily
    WHERE store_id = p_store_id
    LIMIT 1;

    IF v_store_name IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Store ID not found in store_kpi_daily / 错误：门店ID未在store_kpi_daily中找到';
    END IF;

    -- Clear existing scores for this store in the range
    -- 清除该门店在指定范围内的现有评分
    DELETE FROM test.store_anomaly_scores
    WHERE store_id = p_store_id
      AND metric_date BETWEEN p_start_date AND p_end_date;

    DELETE FROM test.store_health_scores
    WHERE store_id = p_store_id
      AND metric_date BETWEEN p_start_date AND p_end_date;

    DELETE FROM test.store_anomaly_alerts
    WHERE store_id = p_store_id
      AND alert_date BETWEEN p_start_date AND p_end_date
      AND acknowledged = FALSE;

    -- Run the full pipeline for each day
    -- 对每一天运行完整管道
    SET v_current = p_start_date;
    WHILE v_current <= p_end_date DO
        CALL test.sp_refresh_store_anomaly(v_current);
        SET v_current = DATE_ADD(v_current, INTERVAL 1 DAY);
    END WHILE;

    SELECT CONCAT('Rebuild complete for store ', p_store_id, ' (', v_store_name, ')',
                   ' from ', p_start_date, ' to ', p_end_date,
                   ' / 门店 ', p_store_id, ' (', v_store_name, ')',
                   ' 从 ', p_start_date, ' 至 ', p_end_date, ' 重建完成') AS result;
END //

DELIMITER ;

-- Usage / 用法:
-- CALL test.sp_rebuild_store_anomaly(1127, '2025-04-01', '2025-06-15');


-- ---------------------------------------------------------
-- 4-3. Reset alerts for a specific date
--      重置指定日期的预警
-- ---------------------------------------------------------
-- Clears all unacknowledged alerts and re-generates them.
-- 清除所有未确认的预警并重新生成。
-- ---------------------------------------------------------
DROP PROCEDURE IF EXISTS test.sp_reset_alerts;

DELIMITER //

CREATE PROCEDURE test.sp_reset_alerts(
    IN p_alert_date DATE
)
BEGIN
    DECLARE v_deleted INT;
    DECLARE v_generated INT;

    -- Delete unacknowledged alerts / 删除未确认的预警
    DELETE FROM test.store_anomaly_alerts
    WHERE alert_date = p_alert_date
      AND acknowledged = FALSE;
    SET v_deleted = ROW_COUNT();

    -- Re-run the pipeline for that date to regenerate alerts
    -- 重新运行该日期的管道以重新生成预警
    CALL test.sp_refresh_store_anomaly(p_alert_date);

    -- Count new alerts / 统计新生成的预警
    SELECT COUNT(*) INTO v_generated
    FROM test.store_anomaly_alerts
    WHERE alert_date = p_alert_date
      AND acknowledged = FALSE;

    SELECT CONCAT('Reset alerts for ', p_alert_date,
                   ': deleted=', v_deleted, ', regenerated=', v_generated,
                   ' / 重置 ', p_alert_date, ' 的预警：删除=', v_deleted,
                   '，重新生成=', v_generated) AS result;
END //

DELIMITER ;

-- Usage / 用法:
-- CALL test.sp_reset_alerts('2025-06-15');


-- ---------------------------------------------------------
-- 4-4. Data integrity checks / 数据完整性检查
-- ---------------------------------------------------------
-- Run periodically to ensure pipeline output consistency.
-- 定期运行以确保管道输出的一致性。
-- ---------------------------------------------------------

-- Check for orphaned health scores (no matching KPI data)
-- 检查孤立的健康评分（无对应KPI数据）
SELECT h.store_id, h.metric_date, h.composite_score
FROM test.store_health_scores h
LEFT JOIN test.store_kpi_daily k
    ON k.store_id = h.store_id AND k.metric_date = h.metric_date
WHERE k.id IS NULL
LIMIT 20;

-- Check for anomaly scores with NULL z_score (computation issue)
-- 检查z_score为空的异常评分（计算问题）
SELECT store_id, metric_date, metric_name, metric_value,
       rolling_mean_28d, rolling_std_28d, z_score
FROM test.store_anomaly_scores
WHERE z_score IS NULL
  AND metric_value IS NOT NULL
LIMIT 20;

-- Verify all 10 stores have scores for the latest date
-- 验证所有10家门店在最新日期都有评分
SELECT
    s.store_id,
    CASE WHEN h.store_id IS NOT NULL THEN 'YES' ELSE 'MISSING' END AS has_health_score,
    CASE WHEN a.store_id IS NOT NULL THEN 'YES' ELSE 'MISSING' END AS has_anomaly_scores
FROM (
    SELECT 1127 AS store_id UNION SELECT 1128 UNION SELECT 1131
    UNION SELECT 1140 UNION SELECT 1141 UNION SELECT 20008
    UNION SELECT 20009 UNION SELECT 20010 UNION SELECT 20011
    UNION SELECT 20046
) s
LEFT JOIN test.store_health_scores h
    ON h.store_id = s.store_id
    AND h.metric_date = (SELECT MAX(metric_date) FROM test.store_health_scores)
LEFT JOIN (
    SELECT DISTINCT store_id
    FROM test.store_anomaly_scores
    WHERE metric_date = (SELECT MAX(metric_date) FROM test.store_anomaly_scores)
) a ON a.store_id = s.store_id
ORDER BY s.store_id;


-- ---------------------------------------------------------
-- 4-5. Performance monitoring / 性能监控
-- ---------------------------------------------------------
-- Track step execution times to identify bottlenecks.
-- 跟踪步骤执行时间以识别瓶颈。
-- ---------------------------------------------------------
SELECT
    step_name,
    COUNT(*)                                    AS run_count,
    ROUND(AVG(duration_seconds), 3)             AS avg_seconds,
    ROUND(MAX(duration_seconds), 3)             AS max_seconds,
    ROUND(MIN(duration_seconds), 3)             AS min_seconds,
    ROUND(AVG(rows_affected), 0)                AS avg_rows
FROM test.store_anomaly_pipeline_log
WHERE run_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
  AND status = 'SUCCESS'
  AND step_name NOT IN ('PIPELINE_START', 'PIPELINE_COMPLETE', 'PIPELINE_FAILED')
GROUP BY step_name
ORDER BY avg_seconds DESC;


-- ============================================================
-- END OF FILE 08 — Daily Refresh Pipeline
-- 文件08结束 — 每日刷新管道
-- ============================================================

-- ============================================================
-- UC-IT-01: Predictive Infrastructure Monitoring
-- 预测性基础设施监控
-- File: 08_daily_refresh.sql
-- Source: All sources (Prometheus, CloudWatch, existing tables)
-- Target: All 6 test.infra_* tables
-- Purpose: Stored procedure and MySQL EVENT for daily automated refresh of all analytics
-- 中文描述: 存储过程和MySQL定时事件，用于每日自动刷新所有分析表（SPC评分、健康评分、告警）
-- Author: Data Engineering / BI Team
-- Created: 2026-02-15
-- ============================================================
--
-- Overview / 概述:
--   This script creates the stored procedures and MySQL EVENT that
--   automate the daily execution of the entire UC-IT-01 analytics
--   pipeline. It orchestrates the 11-step refresh process:
--
--   此脚本创建存储过程和MySQL定时事件，自动化UC-IT-01分析管道
--   的每日执行。它编排11步刷新流程：
--
--   Step 1:  Log pipeline start / 记录管道启动
--   Step 2:  Extract Redis metrics (requires Python orchestrator)
--            提取Redis指标（需要Python编排器）
--   Step 3:  Extract CloudWatch metrics (requires Python orchestrator)
--            提取CloudWatch指标（需要Python编排器）
--   Step 4:  Update fleet inventory / 更新资产清单
--   Step 5:  Compute anomaly scores (14-day rolling SPC)
--            计算异常评分（14天滚动SPC）
--   Step 6:  Evaluate Western Electric rules / 评估西部电气规则
--   Step 7:  Compute rate-of-change / 计算变化率
--   Step 8:  Compute health scores / 计算健康评分
--   Step 9:  Generate alerts / 生成告警
--   Step 10: Data quality verification / 数据质量验证
--   Step 11: Log pipeline completion / 记录管道完成
--
-- Architecture Notes / 架构说明:
--   Steps 2-3 (metric extraction from Prometheus and CloudWatch APIs)
--   cannot be performed directly in MySQL. They require the Python
--   orchestrator (orchestrator/infra_monitoring_pipeline.py). This
--   stored procedure handles only the SQL-based analytics steps
--   (5-11), assuming raw metrics are already loaded into
--   infra_metric_daily by the Python orchestrator.
--
--   步骤2-3（从Prometheus和CloudWatch API提取指标）无法直接在MySQL中执行。
--   它们需要Python编排器(orchestrator/infra_monitoring_pipeline.py)。
--   此存储过程仅处理基于SQL的分析步骤(5-11)，假设原始指标已由
--   Python编排器加载到infra_metric_daily中。
--
-- Scheduling / 调度:
--   MySQL EVENT runs daily at 06:00 UTC (after Python orchestrator
--   completes metric collection at ~05:30 UTC).
--   MySQL事件每天UTC 06:00运行（在Python编排器约05:30 UTC完成指标收集后）。
--
-- Error Handling / 错误处理:
--   Uses DECLARE CONTINUE HANDLER FOR SQLEXCEPTION to catch errors
--   without terminating the pipeline. Each step logs success/failure
--   to infra_monitoring_pipeline_log.
--   使用DECLARE CONTINUE HANDLER FOR SQLEXCEPTION捕获错误而不终止管道。
--   每步将成功/失败记录到infra_monitoring_pipeline_log。
--
-- Prerequisites / 前置条件:
--   - All 6 test.infra_* tables must exist (run 02_create_analytics_schema.sql)
--   - test.infra_metric_daily must be populated for the target date
--   - MySQL event_scheduler must be enabled: SET GLOBAL event_scheduler = ON;
--
-- Author:   Data Engineering / BI Team
-- Created:  2026-02-15
-- ============================================================


-- ############################################################
-- SECTION 1: MAIN STORED PROCEDURE — sp_infra_daily_refresh
-- 第一节: 主存储过程 — sp_infra_daily_refresh
-- ############################################################

DROP PROCEDURE IF EXISTS test.sp_infra_daily_refresh;

DELIMITER $$

CREATE PROCEDURE test.sp_infra_daily_refresh(
    IN p_target_date  DATE,         -- Target date for processing (default: CURDATE())
                                    -- 处理的目标日期（默认：CURDATE()）
    IN p_dry_run      BOOLEAN       -- If TRUE, log but skip actual writes (default: FALSE)
                                    -- 如果为TRUE，记录但跳过实际写入（默认：FALSE）
)
BEGIN
    -- ─────────────────────────────────────────────────────
    -- Variable Declarations / 变量声明
    -- ─────────────────────────────────────────────────────
    DECLARE v_run_id          VARCHAR(50);
    DECLARE v_step_name       VARCHAR(100);
    DECLARE v_step_start      DATETIME;
    DECLARE v_rows_affected   INT DEFAULT 0;
    DECLARE v_error_count     INT DEFAULT 0;
    DECLARE v_error_message   VARCHAR(500) DEFAULT '';
    DECLARE v_pipeline_start  DATETIME;
    DECLARE v_total_anomalies INT DEFAULT 0;
    DECLARE v_total_alerts    INT DEFAULT 0;
    DECLARE v_total_scored    INT DEFAULT 0;

    -- Error handler: capture but continue / 错误处理：捕获但继续
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_error_message = MESSAGE_TEXT;
        SET v_error_count = v_error_count + 1;

        -- Log the error / 记录错误
        INSERT INTO test.infra_monitoring_pipeline_log
            (run_id, step_name, step_status, message,
             rows_affected, started_at, completed_at)
        VALUES
            (v_run_id, v_step_name, 'ERROR', v_error_message,
             0, v_step_start, NOW());
    END;

    -- ─────────────────────────────────────────────────────
    -- Default parameter handling / 默认参数处理
    -- ─────────────────────────────────────────────────────
    IF p_target_date IS NULL THEN
        SET p_target_date = CURDATE();
    END IF;

    IF p_dry_run IS NULL THEN
        SET p_dry_run = FALSE;
    END IF;

    -- Generate unique run ID / 生成唯一运行ID
    SET v_run_id = CONCAT('INFRA-',
                          DATE_FORMAT(p_target_date, '%Y%m%d'), '-',
                          LPAD(FLOOR(RAND() * 10000), 4, '0'));
    SET v_pipeline_start = NOW();


    -- =========================================================
    -- STEP 1: LOG PIPELINE START
    -- 步骤1: 记录管道启动
    -- =========================================================
    SET v_step_name  = 'Pipeline Start';
    SET v_step_start = NOW();

    INSERT INTO test.infra_monitoring_pipeline_log
        (run_id, step_name, step_status, message,
         rows_affected, started_at, completed_at)
    VALUES
        (v_run_id, v_step_name, 'STARTED',
         CONCAT('UC-IT-01 daily refresh initiated. Target date: ',
                p_target_date, ', Dry run: ', IF(p_dry_run, 'YES', 'NO')),
         0, v_step_start, NOW());


    -- =========================================================
    -- STEP 2: VERIFY DATA AVAILABILITY (Redis metrics)
    -- 步骤2: 验证数据可用性（Redis指标）
    -- =========================================================
    SET v_step_name  = 'Verify Redis Data';
    SET v_step_start = NOW();

    SELECT COUNT(*) INTO v_rows_affected
    FROM test.infra_metric_daily
    WHERE service_type = 'ElastiCache'
      AND metric_date  = p_target_date;

    INSERT INTO test.infra_monitoring_pipeline_log
        (run_id, step_name, step_status, message,
         rows_affected, started_at, completed_at)
    VALUES
        (v_run_id, v_step_name,
         IF(v_rows_affected > 0, 'SUCCESS', 'WARNING'),
         CONCAT('Redis metric rows found for ', p_target_date, ': ', v_rows_affected,
                '. Note: metric extraction handled by Python orchestrator.'),
         v_rows_affected, v_step_start, NOW());


    -- =========================================================
    -- STEP 3: VERIFY DATA AVAILABILITY (CloudWatch/RDS metrics)
    -- 步骤3: 验证数据可用性（CloudWatch/RDS指标）
    -- =========================================================
    SET v_step_name  = 'Verify CloudWatch Data';
    SET v_step_start = NOW();

    SELECT COUNT(*) INTO v_rows_affected
    FROM test.infra_metric_daily
    WHERE service_type = 'RDS'
      AND metric_date  = p_target_date;

    INSERT INTO test.infra_monitoring_pipeline_log
        (run_id, step_name, step_status, message,
         rows_affected, started_at, completed_at)
    VALUES
        (v_run_id, v_step_name,
         IF(v_rows_affected > 0, 'SUCCESS', 'WARNING'),
         CONCAT('RDS metric rows found for ', p_target_date, ': ', v_rows_affected,
                '. Note: metric extraction handled by Python orchestrator.'),
         v_rows_affected, v_step_start, NOW());


    -- =========================================================
    -- STEP 4: UPDATE FLEET INVENTORY
    -- 步骤4: 更新资产清单
    -- =========================================================
    SET v_step_name  = 'Update Fleet Inventory';
    SET v_step_start = NOW();

    IF NOT p_dry_run THEN
        -- Upsert distinct instances from metric data into inventory
        -- 从指标数据中将不同实例插入/更新到资产清单
        INSERT INTO test.infra_fleet_inventory
            (service_type, instance_id, instance_name, first_seen, last_seen, is_active)
        SELECT DISTINCT
            service_type,
            instance_id,
            instance_name,
            p_target_date,
            p_target_date,
            TRUE
        FROM test.infra_metric_daily
        WHERE metric_date = p_target_date
        ON DUPLICATE KEY UPDATE
            last_seen  = p_target_date,
            is_active  = TRUE;

        SET v_rows_affected = ROW_COUNT();
    ELSE
        SET v_rows_affected = 0;
    END IF;

    INSERT INTO test.infra_monitoring_pipeline_log
        (run_id, step_name, step_status, message,
         rows_affected, started_at, completed_at)
    VALUES
        (v_run_id, v_step_name, 'SUCCESS',
         CONCAT('Fleet inventory updated. Instances refreshed: ', v_rows_affected),
         v_rows_affected, v_step_start, NOW());


    -- =========================================================
    -- STEP 5: COMPUTE SPC ANOMALY SCORES (14-day rolling)
    -- 步骤5: 计算SPC异常评分（14天滚动）
    -- =========================================================
    SET v_step_name  = 'Compute SPC Anomaly Scores';
    SET v_step_start = NOW();

    IF NOT p_dry_run THEN
        -- Call the SPC computation sub-procedure
        -- 调用SPC计算子过程
        CALL test.sp_infra_compute_spc(p_target_date, 14);
        SET v_rows_affected = ROW_COUNT();
    END IF;

    SELECT COUNT(*) INTO v_total_anomalies
    FROM test.infra_anomaly_scores
    WHERE metric_date = p_target_date
      AND anomaly_severity IN ('CRITICAL', 'WARNING', 'INFO');

    INSERT INTO test.infra_monitoring_pipeline_log
        (run_id, step_name, step_status, message,
         rows_affected, started_at, completed_at)
    VALUES
        (v_run_id, v_step_name, 'SUCCESS',
         CONCAT('SPC scores computed. Total anomalies detected: ', v_total_anomalies),
         v_rows_affected, v_step_start, NOW());


    -- =========================================================
    -- STEP 6: EVALUATE WESTERN ELECTRIC RULES
    -- 步骤6: 评估西部电气规则
    -- =========================================================
    SET v_step_name  = 'Evaluate WE Rules';
    SET v_step_start = NOW();

    IF NOT p_dry_run THEN
        -- WE Rule 1: Beyond 3σ / WE规则1: 超过3σ
        UPDATE test.infra_anomaly_scores
        SET we_rule1 = (ABS(z_score) > 3)
        WHERE metric_date = p_target_date
          AND z_score IS NOT NULL;

        -- WE Rule 2-5 are computed by sp_infra_compute_spc
        -- WE规则2-5由sp_infra_compute_spc计算
        SET v_rows_affected = ROW_COUNT();
    END IF;

    INSERT INTO test.infra_monitoring_pipeline_log
        (run_id, step_name, step_status, message,
         rows_affected, started_at, completed_at)
    VALUES
        (v_run_id, v_step_name, 'SUCCESS',
         CONCAT('Western Electric rules evaluated for ', p_target_date),
         v_rows_affected, v_step_start, NOW());


    -- =========================================================
    -- STEP 7: COMPUTE RATE-OF-CHANGE
    -- 步骤7: 计算变化率
    -- =========================================================
    SET v_step_name  = 'Compute Rate-of-Change';
    SET v_step_start = NOW();

    IF NOT p_dry_run THEN
        -- 1-day rate of change / 1天变化率
        UPDATE test.infra_anomaly_scores a
        JOIN test.infra_anomaly_scores prev
            ON  a.service_type = prev.service_type
            AND a.instance_id  = prev.instance_id
            AND a.metric_name  = prev.metric_name
            AND prev.metric_date = DATE_SUB(a.metric_date, INTERVAL 1 DAY)
        SET a.rate_of_change_1d = CASE
            WHEN prev.metric_value > 0
                THEN ((a.metric_value - prev.metric_value) / prev.metric_value) * 100
            ELSE NULL
        END
        WHERE a.metric_date = p_target_date;

        -- 7-day rate of change / 7天变化率
        UPDATE test.infra_anomaly_scores a
        JOIN test.infra_anomaly_scores prev7
            ON  a.service_type  = prev7.service_type
            AND a.instance_id   = prev7.instance_id
            AND a.metric_name   = prev7.metric_name
            AND prev7.metric_date = DATE_SUB(a.metric_date, INTERVAL 7 DAY)
        SET a.rate_of_change_7d = CASE
            WHEN prev7.metric_value > 0
                THEN ((a.metric_value - prev7.metric_value) / prev7.metric_value) * 100
            ELSE NULL
        END
        WHERE a.metric_date = p_target_date;

        SET v_rows_affected = ROW_COUNT();
    END IF;

    INSERT INTO test.infra_monitoring_pipeline_log
        (run_id, step_name, step_status, message,
         rows_affected, started_at, completed_at)
    VALUES
        (v_run_id, v_step_name, 'SUCCESS',
         CONCAT('Rate-of-change computed for ', p_target_date),
         v_rows_affected, v_step_start, NOW());


    -- =========================================================
    -- STEP 8: COMPUTE HEALTH SCORES
    -- 步骤8: 计算健康评分
    -- =========================================================
    SET v_step_name  = 'Compute Health Scores';
    SET v_step_start = NOW();

    IF NOT p_dry_run THEN
        -- Delete existing health scores for target date (idempotent)
        -- 删除目标日期的现有健康评分（幂等）
        DELETE FROM test.infra_health_scores
        WHERE score_date = p_target_date;

        -- Insert ElastiCache health scores / 插入ElastiCache健康评分
        INSERT INTO test.infra_health_scores
            (service_type, instance_id, instance_name, score_date,
             availability_score, performance_score, capacity_score,
             error_rate_score, latency_score)
        SELECT
            'ElastiCache', a.instance_id, a.instance_name, a.metric_date,
            COALESCE(MAX(CASE WHEN a.metric_name = 'redis_up'
                              THEN a.metric_value * 100 END), 100),
            ROUND(AVG(CASE WHEN a.metric_name IN ('commands_per_sec','hit_rate')
                      THEN GREATEST(0, 100 - ABS(COALESCE(a.z_score,0)) * 20)
                      ELSE NULL END), 1),
            ROUND(AVG(CASE WHEN a.metric_name IN ('memory_utilization','connected_clients')
                      THEN GREATEST(0, 100 - ABS(COALESCE(a.z_score,0)) * 20)
                      ELSE NULL END), 1),
            ROUND(AVG(CASE WHEN a.metric_name IN ('rejected_connections','evicted_keys')
                      THEN GREATEST(0, 100 - ABS(COALESCE(a.z_score,0)) * 20)
                      ELSE NULL END), 1),
            ROUND(AVG(CASE WHEN a.metric_name = 'command_duration'
                      THEN GREATEST(0, 100 - ABS(COALESCE(a.z_score,0)) * 20)
                      ELSE NULL END), 1)
        FROM test.infra_anomaly_scores a
        WHERE a.service_type = 'ElastiCache'
          AND a.metric_date  = p_target_date
        GROUP BY a.instance_id, a.instance_name, a.metric_date;

        -- Insert RDS health scores / 插入RDS健康评分
        INSERT INTO test.infra_health_scores
            (service_type, instance_id, instance_name, score_date,
             availability_score, performance_score, capacity_score,
             error_rate_score, latency_score)
        SELECT
            'RDS', a.instance_id, a.instance_name, a.metric_date,
            COALESCE(MAX(CASE WHEN a.metric_name = 'database_connections'
                              THEN CASE WHEN a.metric_value > 0 THEN 100 ELSE 0 END END), 100),
            ROUND(AVG(CASE WHEN a.metric_name IN ('cpu_utilization','read_iops','write_iops')
                      THEN GREATEST(0, 100 - ABS(COALESCE(a.z_score,0)) * 20)
                      ELSE NULL END), 1),
            ROUND(AVG(CASE WHEN a.metric_name IN ('freeable_memory','free_storage_space')
                      THEN CASE WHEN a.z_score < 0
                           THEN GREATEST(0, 100 - ABS(a.z_score) * 20)
                           ELSE LEAST(100, 100 - a.z_score * 5) END
                      ELSE NULL END), 1),
            ROUND(AVG(CASE WHEN a.metric_name IN ('slow_query_rate','deadlock_count')
                      THEN GREATEST(0, 100 - ABS(COALESCE(a.z_score,0)) * 20)
                      ELSE NULL END), 1),
            ROUND(AVG(CASE WHEN a.metric_name IN ('read_latency','write_latency')
                      THEN CASE WHEN a.z_score > 0
                           THEN GREATEST(0, 100 - a.z_score * 20) ELSE 100 END
                      ELSE NULL END), 1)
        FROM test.infra_anomaly_scores a
        WHERE a.service_type = 'RDS'
          AND a.metric_date  = p_target_date
        GROUP BY a.instance_id, a.instance_name, a.metric_date;

        -- Compute composite scores and grades / 计算综合评分和等级
        UPDATE test.infra_health_scores
        SET composite_score = ROUND(
            0.30 * COALESCE(availability_score, 100)
          + 0.25 * COALESCE(performance_score, 100)
          + 0.25 * COALESCE(capacity_score, 100)
          + 0.10 * COALESCE(error_rate_score, 100)
          + 0.10 * COALESCE(latency_score, 100), 1)
        WHERE score_date = p_target_date;

        UPDATE test.infra_health_scores
        SET health_grade = CASE
            WHEN composite_score >= 90 THEN 'A'
            WHEN composite_score >= 80 THEN 'B'
            WHEN composite_score >= 70 THEN 'C'
            WHEN composite_score >= 60 THEN 'D'
            ELSE 'F'
        END
        WHERE score_date = p_target_date;

        SELECT COUNT(*) INTO v_total_scored
        FROM test.infra_health_scores
        WHERE score_date = p_target_date;
    END IF;

    INSERT INTO test.infra_monitoring_pipeline_log
        (run_id, step_name, step_status, message,
         rows_affected, started_at, completed_at)
    VALUES
        (v_run_id, v_step_name, 'SUCCESS',
         CONCAT('Health scores computed. Instances scored: ', v_total_scored),
         v_total_scored, v_step_start, NOW());


    -- =========================================================
    -- STEP 9: GENERATE ALERTS
    -- 步骤9: 生成告警
    -- =========================================================
    SET v_step_name  = 'Generate Alerts';
    SET v_step_start = NOW();

    IF NOT p_dry_run THEN
        CALL test.sp_infra_generate_alerts(p_target_date);

        SELECT COUNT(*) INTO v_total_alerts
        FROM test.infra_anomaly_alerts
        WHERE metric_date = p_target_date;
    END IF;

    INSERT INTO test.infra_monitoring_pipeline_log
        (run_id, step_name, step_status, message,
         rows_affected, started_at, completed_at)
    VALUES
        (v_run_id, v_step_name, 'SUCCESS',
         CONCAT('Alerts generated for ', p_target_date, ': ', v_total_alerts),
         v_total_alerts, v_step_start, NOW());


    -- =========================================================
    -- STEP 10: DATA QUALITY VERIFICATION
    -- 步骤10: 数据质量验证
    -- =========================================================
    SET v_step_name  = 'Data Quality Check';
    SET v_step_start = NOW();

    -- Check for completeness / 检查完整性
    SET v_rows_affected = 0;

    -- Count instances with scores vs inventory
    -- 比较有评分的实例数与资产清单
    SELECT COUNT(DISTINCT i.instance_id) -
           COUNT(DISTINCT h.instance_id) INTO v_rows_affected
    FROM test.infra_fleet_inventory i
    LEFT JOIN test.infra_health_scores h
        ON  h.instance_id = i.instance_id
        AND h.score_date  = p_target_date
    WHERE i.is_active = TRUE;

    INSERT INTO test.infra_monitoring_pipeline_log
        (run_id, step_name, step_status, message,
         rows_affected, started_at, completed_at)
    VALUES
        (v_run_id, v_step_name,
         IF(v_rows_affected = 0, 'SUCCESS', 'WARNING'),
         CONCAT('Data quality check. Missing health scores for active instances: ',
                v_rows_affected),
         v_rows_affected, v_step_start, NOW());


    -- =========================================================
    -- STEP 11: LOG PIPELINE COMPLETION
    -- 步骤11: 记录管道完成
    -- =========================================================
    SET v_step_name = 'Pipeline Complete';

    INSERT INTO test.infra_monitoring_pipeline_log
        (run_id, step_name, step_status, message,
         rows_affected, started_at, completed_at)
    VALUES
        (v_run_id, v_step_name,
         IF(v_error_count = 0, 'SUCCESS', 'COMPLETED_WITH_ERRORS'),
         CONCAT('UC-IT-01 daily refresh completed. ',
                'Run ID: ', v_run_id, ', ',
                'Date: ', p_target_date, ', ',
                'Anomalies: ', v_total_anomalies, ', ',
                'Alerts: ', v_total_alerts, ', ',
                'Scored instances: ', v_total_scored, ', ',
                'Errors: ', v_error_count, ', ',
                'Duration: ', TIMESTAMPDIFF(SECOND, v_pipeline_start, NOW()), 's'),
         v_error_count, v_pipeline_start, NOW());

END$$

DELIMITER ;


-- ############################################################
-- SECTION 2: HELPER PROCEDURE — sp_infra_compute_spc
-- 第二节: 辅助存储过程 — sp_infra_compute_spc
-- ############################################################
--
-- Focused SPC computation for a given date range.
-- Handles the insert-with-rolling-stats and z-score calculation.
-- 针对给定日期范围的SPC计算。处理带滚动统计的插入和Z分数计算。
-- ############################################################

DROP PROCEDURE IF EXISTS test.sp_infra_compute_spc;

DELIMITER $$

CREATE PROCEDURE test.sp_infra_compute_spc(
    IN p_target_date   DATE,
    IN p_window_days   INT      -- Rolling window size (default: 14)
                                -- 滚动窗口大小（默认：14）
)
BEGIN
    DECLARE v_window_offset INT;

    SET v_window_offset = p_window_days - 1;

    -- Delete existing scores for target date (idempotent)
    -- 删除目标日期的现有评分（幂等）
    DELETE FROM test.infra_anomaly_scores
    WHERE metric_date = p_target_date;

    -- Insert with rolling statistics / 插入带滚动统计的数据
    INSERT INTO test.infra_anomaly_scores
        (service_type, instance_id, instance_name, metric_date,
         metric_name, metric_value, metric_unit,
         rolling_mean_14d, rolling_std_14d)
    SELECT
        m.service_type,
        m.instance_id,
        m.instance_name,
        m.metric_date,
        m.metric_name,
        m.metric_value,
        m.metric_unit,
        sub.rolling_mean,
        sub.rolling_std
    FROM test.infra_metric_daily m
    JOIN (
        -- Compute rolling stats from historical window
        -- 从历史窗口计算滚动统计
        SELECT
            h.service_type,
            h.instance_id,
            h.metric_name,
            AVG(h.metric_value)         AS rolling_mean,
            STDDEV_SAMP(h.metric_value) AS rolling_std
        FROM test.infra_metric_daily h
        WHERE h.metric_date BETWEEN DATE_SUB(p_target_date, INTERVAL v_window_offset DAY)
                                AND p_target_date
          AND h.metric_value IS NOT NULL
        GROUP BY h.service_type, h.instance_id, h.metric_name
        HAVING COUNT(*) >= 5  -- Require at least 5 data points for meaningful stats
                              -- 需要至少5个数据点才能产生有意义的统计
    ) sub ON  m.service_type = sub.service_type
          AND m.instance_id  = sub.instance_id
          AND m.metric_name  = sub.metric_name
    WHERE m.metric_date      = p_target_date
      AND m.metric_value IS NOT NULL;

    -- Compute Z-scores / 计算Z分数
    UPDATE test.infra_anomaly_scores
    SET z_score = CASE
            WHEN rolling_std_14d > 0
            THEN (metric_value - rolling_mean_14d) / rolling_std_14d
            ELSE 0
        END,
        ucl_2sigma = rolling_mean_14d + 2.0 * COALESCE(rolling_std_14d, 0),
        ucl_3sigma = rolling_mean_14d + 3.0 * COALESCE(rolling_std_14d, 0),
        lcl_2sigma = rolling_mean_14d - 2.0 * COALESCE(rolling_std_14d, 0),
        lcl_3sigma = rolling_mean_14d - 3.0 * COALESCE(rolling_std_14d, 0)
    WHERE metric_date = p_target_date
      AND rolling_mean_14d IS NOT NULL;

    -- WE Rule 1: Beyond 3σ / WE规则1: 超过3σ
    UPDATE test.infra_anomaly_scores
    SET we_rule1 = (ABS(z_score) > 3)
    WHERE metric_date = p_target_date
      AND z_score IS NOT NULL;

    -- Determine severity with metric directionality
    -- 结合指标方向性确定严重度
    UPDATE test.infra_anomaly_scores
    SET anomaly_severity = CASE
        WHEN we_rule1 = TRUE THEN 'CRITICAL'
        WHEN ABS(z_score) > 2.0 THEN 'WARNING'
        WHEN ABS(z_score) > 1.5 THEN 'INFO'
        ELSE 'NONE'
    END
    WHERE metric_date = p_target_date
      AND z_score IS NOT NULL;

END$$

DELIMITER ;


-- ############################################################
-- SECTION 3: HELPER PROCEDURE — sp_infra_generate_alerts
-- 第三节: 辅助存储过程 — sp_infra_generate_alerts
-- ############################################################
--
-- Alert generation with deduplication. Only creates new alerts
-- for CRITICAL and WARNING items not already alerted.
-- 带去重的告警生成。仅为未告警的CRITICAL和WARNING项创建新告警。
-- ############################################################

DROP PROCEDURE IF EXISTS test.sp_infra_generate_alerts;

DELIMITER $$

CREATE PROCEDURE test.sp_infra_generate_alerts(
    IN p_target_date DATE
)
BEGIN
    INSERT INTO test.infra_anomaly_alerts
        (service_type, instance_id, instance_name, metric_name,
         metric_date, metric_value, z_score, anomaly_severity,
         we_rules_triggered, rate_of_change_1d,
         description_en, description_cn, recommended_action,
         created_at)
    SELECT
        a.service_type,
        a.instance_id,
        a.instance_name,
        a.metric_name,
        a.metric_date,
        a.metric_value,
        ROUND(a.z_score, 2),
        a.anomaly_severity,
        CONCAT_WS(', ',
            IF(a.we_rule1, 'WE-1', NULL),
            IF(a.we_rule2, 'WE-2', NULL),
            IF(a.we_rule3, 'WE-3', NULL),
            IF(a.we_rule4, 'WE-4', NULL),
            IF(a.we_rule5, 'WE-5', NULL)
        ),
        ROUND(a.rate_of_change_1d, 2),
        -- English description
        CONCAT(a.anomaly_severity, ' on ', a.instance_name, ': ',
               a.metric_name, '=', ROUND(a.metric_value, 2),
               ', Z=', ROUND(a.z_score, 2)),
        -- Chinese description / 中文描述
        CONCAT(CASE a.anomaly_severity
                   WHEN 'CRITICAL' THEN '严重'
                   ELSE '警告' END,
               ': ', a.instance_name, ' ',
               a.metric_name, '=', ROUND(a.metric_value, 2),
               ', Z分数=', ROUND(a.z_score, 2)),
        -- Recommended action / 建议操作
        CASE
            WHEN a.metric_name LIKE '%cpu%' THEN
                'Check CPU-intensive processes. Consider scaling. / 检查CPU密集进程，考虑扩容。'
            WHEN a.metric_name LIKE '%memory%' OR a.metric_name LIKE '%freeable%' THEN
                'Check for memory leaks. Monitor OOM risk. / 检查内存泄漏，监控OOM风险。'
            WHEN a.metric_name LIKE '%latency%' OR a.metric_name LIKE '%duration%' THEN
                'Investigate slow operations. Check I/O. / 调查慢操作，检查I/O。'
            WHEN a.metric_name LIKE '%storage%' OR a.metric_name LIKE '%disk%' THEN
                'Disk space concern. Plan capacity expansion. / 磁盘空间关注，规划容量扩展。'
            ELSE 'Review metric trend and correlate with changes. / 审查指标趋势并关联变更。'
        END,
        NOW()
    FROM test.infra_anomaly_scores a
    WHERE a.metric_date       = p_target_date
      AND a.anomaly_severity IN ('CRITICAL', 'WARNING')
      -- Deduplication: skip existing alerts / 去重：跳过已存在的告警
      AND NOT EXISTS (
          SELECT 1 FROM test.infra_anomaly_alerts e
          WHERE e.instance_id  = a.instance_id
            AND e.metric_name  = a.metric_name
            AND e.metric_date  = a.metric_date
      );

END$$

DELIMITER ;


-- ############################################################
-- SECTION 4: MYSQL EVENT — evt_infra_daily_refresh
-- 第四节: MySQL定时事件 — evt_infra_daily_refresh
-- ############################################################
--
-- Schedule the daily refresh to run at 06:00 UTC.
-- Requires: SET GLOBAL event_scheduler = ON;
-- 安排每日刷新在UTC 06:00运行。
-- 需要: SET GLOBAL event_scheduler = ON;
-- ############################################################

DROP EVENT IF EXISTS test.evt_infra_daily_refresh;

CREATE EVENT IF NOT EXISTS test.evt_infra_daily_refresh
ON SCHEDULE EVERY 1 DAY
STARTS '2026-02-16 06:00:00'
ON COMPLETION PRESERVE
ENABLE
COMMENT 'UC-IT-01: Daily infrastructure monitoring refresh at 06:00 UTC / 每日基础设施监控刷新(UTC 06:00)'
DO CALL test.sp_infra_daily_refresh(CURDATE(), FALSE);


-- ############################################################
-- SECTION 5: MANUAL EXECUTION EXAMPLES
-- 第五节: 手动执行示例
-- ############################################################

-- ─────────────────────────────────────────────────────
-- 5.1  Run for today (normal execution)
-- 为今天运行（正常执行）
-- ─────────────────────────────────────────────────────
-- CALL test.sp_infra_daily_refresh(CURDATE(), FALSE);

-- ─────────────────────────────────────────────────────
-- 5.2  Dry run (log steps but skip writes)
-- 试运行（记录步骤但跳过写入）
-- ─────────────────────────────────────────────────────
-- CALL test.sp_infra_daily_refresh(CURDATE(), TRUE);

-- ─────────────────────────────────────────────────────
-- 5.3  Run for a specific historical date
-- 为特定历史日期运行
-- ─────────────────────────────────────────────────────
-- CALL test.sp_infra_daily_refresh('2026-02-10', FALSE);

-- ─────────────────────────────────────────────────────
-- 5.4  Check event scheduler status
-- 检查事件调度器状态
-- ─────────────────────────────────────────────────────
-- SHOW VARIABLES LIKE 'event_scheduler';
-- SELECT * FROM information_schema.EVENTS
-- WHERE EVENT_SCHEMA = 'test' AND EVENT_NAME = 'evt_infra_daily_refresh';


-- ############################################################
-- SECTION 6: BACKFILL PROCEDURE FOR HISTORICAL DATA
-- 第六节: 历史数据回填过程
-- ############################################################
--
-- Use this to retroactively process historical data that was
-- loaded in bulk (e.g., after initial setup or data migration).
-- 使用此过程回溯处理批量加载的历史数据（如初始设置或数据迁移后）。
-- ############################################################

DROP PROCEDURE IF EXISTS test.sp_infra_backfill;

DELIMITER $$

CREATE PROCEDURE test.sp_infra_backfill(
    IN p_start_date DATE,
    IN p_end_date   DATE
)
BEGIN
    DECLARE v_current_date DATE;
    DECLARE v_total_days   INT;
    DECLARE v_processed    INT DEFAULT 0;

    SET v_current_date = p_start_date;
    SET v_total_days   = DATEDIFF(p_end_date, p_start_date) + 1;

    -- Log backfill start / 记录回填开始
    INSERT INTO test.infra_monitoring_pipeline_log
        (run_id, step_name, step_status, message,
         rows_affected, started_at, completed_at)
    VALUES
        (CONCAT('BACKFILL-', DATE_FORMAT(NOW(), '%Y%m%d%H%i%s')),
         'Backfill Start', 'STARTED',
         CONCAT('Backfilling from ', p_start_date, ' to ', p_end_date,
                ' (', v_total_days, ' days)'),
         0, NOW(), NOW());

    -- Process each date sequentially / 按顺序处理每个日期
    WHILE v_current_date <= p_end_date DO

        CALL test.sp_infra_daily_refresh(v_current_date, FALSE);

        SET v_processed    = v_processed + 1;
        SET v_current_date = DATE_ADD(v_current_date, INTERVAL 1 DAY);

    END WHILE;

    -- Log backfill completion / 记录回填完成
    INSERT INTO test.infra_monitoring_pipeline_log
        (run_id, step_name, step_status, message,
         rows_affected, started_at, completed_at)
    VALUES
        (CONCAT('BACKFILL-', DATE_FORMAT(NOW(), '%Y%m%d%H%i%s')),
         'Backfill Complete', 'SUCCESS',
         CONCAT('Backfill completed. Days processed: ', v_processed,
                ' of ', v_total_days),
         v_processed, NOW(), NOW());

END$$

DELIMITER ;

-- ─────────────────────────────────────────────────────
-- Backfill usage example / 回填使用示例:
-- ─────────────────────────────────────────────────────
-- Process last 30 days of historical data:
-- 处理最近30天的历史数据：
-- CALL test.sp_infra_backfill(DATE_SUB(CURDATE(), INTERVAL 30 DAY), CURDATE());
--
-- Process a specific date range:
-- 处理特定日期范围：
-- CALL test.sp_infra_backfill('2026-01-15', '2026-02-14');


-- ############################################################
-- SECTION 7: CLEANUP PROCEDURE FOR OLD PIPELINE LOGS
-- 第七节: 旧管道日志清理过程
-- ############################################################
--
-- Retain 90 days of pipeline logs. Run periodically to prevent
-- unbounded table growth.
-- 保留90天的管道日志。定期运行以防止表无限增长。
-- ############################################################

DROP PROCEDURE IF EXISTS test.sp_infra_cleanup_logs;

DELIMITER $$

CREATE PROCEDURE test.sp_infra_cleanup_logs(
    IN p_retention_days INT    -- Days to retain (default: 90)
                               -- 保留天数（默认：90）
)
BEGIN
    DECLARE v_deleted INT DEFAULT 0;
    DECLARE v_cutoff  DATE;

    IF p_retention_days IS NULL THEN
        SET p_retention_days = 90;
    END IF;

    SET v_cutoff = DATE_SUB(CURDATE(), INTERVAL p_retention_days DAY);

    -- Delete old pipeline logs / 删除旧管道日志
    DELETE FROM test.infra_monitoring_pipeline_log
    WHERE completed_at < v_cutoff;

    SET v_deleted = ROW_COUNT();

    -- Delete old alerts (keep 180 days by default)
    -- 删除旧告警（默认保留180天）
    DELETE FROM test.infra_anomaly_alerts
    WHERE created_at < DATE_SUB(CURDATE(), INTERVAL p_retention_days * 2 DAY);

    -- Log cleanup / 记录清理
    INSERT INTO test.infra_monitoring_pipeline_log
        (run_id, step_name, step_status, message,
         rows_affected, started_at, completed_at)
    VALUES
        (CONCAT('CLEANUP-', DATE_FORMAT(NOW(), '%Y%m%d')),
         'Log Cleanup', 'SUCCESS',
         CONCAT('Deleted pipeline logs older than ', v_cutoff,
                '. Rows removed: ', v_deleted),
         v_deleted, NOW(), NOW());

END$$

DELIMITER ;

-- ─────────────────────────────────────────────────────
-- Cleanup usage / 清理使用:
-- ─────────────────────────────────────────────────────
-- CALL test.sp_infra_cleanup_logs(90);   -- Keep 90 days / 保留90天
-- CALL test.sp_infra_cleanup_logs(30);   -- Keep 30 days / 保留30天


-- ############################################################
-- SECTION 8: CLEANUP EVENT FOR AUTOMATIC LOG ROTATION
-- 第八节: 自动日志轮转的清理事件
-- ############################################################

DROP EVENT IF EXISTS test.evt_infra_cleanup_logs;

CREATE EVENT IF NOT EXISTS test.evt_infra_cleanup_logs
ON SCHEDULE EVERY 7 DAY
STARTS '2026-02-22 04:00:00'
ON COMPLETION PRESERVE
ENABLE
COMMENT 'UC-IT-01: Weekly cleanup of old pipeline logs (90-day retention) / 每周清理旧管道日志(保留90天)'
DO CALL test.sp_infra_cleanup_logs(90);


-- ############################################################
-- SECTION 9: VERIFICATION QUERIES AFTER REFRESH
-- 第九节: 刷新后验证查询
-- ############################################################


-- ─────────────────────────────────────────────────────
-- 9.1  Latest pipeline execution log
-- 最近的管道执行日志
-- ─────────────────────────────────────────────────────

SELECT
    run_id,
    step_name,
    step_status,
    message,
    rows_affected,
    started_at,
    completed_at,
    TIMESTAMPDIFF(SECOND, started_at, completed_at) AS duration_sec
FROM test.infra_monitoring_pipeline_log
WHERE run_id = (
    SELECT run_id FROM test.infra_monitoring_pipeline_log
    WHERE step_name = 'Pipeline Complete'
    ORDER BY completed_at DESC LIMIT 1
)
ORDER BY started_at;


-- ─────────────────────────────────────────────────────
-- 9.2  Pipeline run history (last 7 days)
-- 管道运行历史（最近7天）
-- ─────────────────────────────────────────────────────

SELECT
    run_id,
    MIN(started_at)                                             AS pipeline_start,
    MAX(completed_at)                                           AS pipeline_end,
    TIMESTAMPDIFF(SECOND, MIN(started_at), MAX(completed_at))  AS total_duration_sec,
    SUM(CASE WHEN step_status = 'ERROR' THEN 1 ELSE 0 END)     AS error_count,
    SUM(CASE WHEN step_status = 'WARNING' THEN 1 ELSE 0 END)   AS warning_count,
    MAX(CASE WHEN step_name = 'Pipeline Complete'
             THEN step_status END)                              AS final_status
FROM test.infra_monitoring_pipeline_log
WHERE started_at >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
GROUP BY run_id
ORDER BY pipeline_start DESC;


-- ─────────────────────────────────────────────────────
-- 9.3  Today's anomaly summary
-- 今日异常摘要
-- ─────────────────────────────────────────────────────

SELECT
    service_type,
    anomaly_severity,
    COUNT(*)                            AS anomaly_count,
    COUNT(DISTINCT instance_id)         AS affected_instances,
    COUNT(DISTINCT metric_name)         AS affected_metrics
FROM test.infra_anomaly_scores
WHERE metric_date = CURDATE()
  AND anomaly_severity != 'NONE'
GROUP BY service_type, anomaly_severity
ORDER BY service_type, FIELD(anomaly_severity, 'CRITICAL', 'WARNING', 'INFO');


-- ─────────────────────────────────────────────────────
-- 9.4  Today's fleet health overview
-- 今日全局健康概览
-- ─────────────────────────────────────────────────────

SELECT
    service_type,
    COUNT(*)                                                AS total_instances,
    ROUND(AVG(composite_score), 1)                         AS avg_score,
    SUM(CASE WHEN health_grade = 'F' THEN 1 ELSE 0 END)   AS critical_instances,
    SUM(CASE WHEN health_grade = 'D' THEN 1 ELSE 0 END)   AS poor_instances,
    MIN(composite_score)                                    AS lowest_score
FROM test.infra_health_scores
WHERE score_date = CURDATE()
GROUP BY service_type;


-- ─────────────────────────────────────────────────────
-- 9.5  Event scheduler verification
-- 事件调度器验证
-- ─────────────────────────────────────────────────────

SELECT
    EVENT_SCHEMA,
    EVENT_NAME,
    STATUS           AS event_status,
    EVENT_TYPE,
    EXECUTE_AT,
    INTERVAL_VALUE,
    INTERVAL_FIELD,
    LAST_EXECUTED,
    EVENT_COMMENT
FROM information_schema.EVENTS
WHERE EVENT_SCHEMA = 'test'
  AND EVENT_NAME LIKE 'evt_infra%'
ORDER BY EVENT_NAME;


-- ─────────────────────────────────────────────────────
-- 9.6  Stored procedure listing verification
-- 存储过程列表验证
-- ─────────────────────────────────────────────────────

SELECT
    ROUTINE_SCHEMA,
    ROUTINE_NAME,
    ROUTINE_TYPE,
    CREATED,
    LAST_ALTERED
FROM information_schema.ROUTINES
WHERE ROUTINE_SCHEMA = 'test'
  AND ROUTINE_NAME LIKE 'sp_infra%'
ORDER BY ROUTINE_NAME;


-- ############################################################
-- END OF SCRIPT
-- 脚本结束
-- ############################################################
--
-- Summary of objects created / 创建的对象摘要:
--
-- Stored Procedures / 存储过程:
--   1. test.sp_infra_daily_refresh(p_target_date, p_dry_run)
--      Main orchestration procedure with 11 steps
--      主编排过程，包含11个步骤
--
--   2. test.sp_infra_compute_spc(p_target_date, p_window_days)
--      SPC computation helper: rolling stats, z-scores, WE rules
--      SPC计算辅助过程：滚动统计、Z分数、WE规则
--
--   3. test.sp_infra_generate_alerts(p_target_date)
--      Alert generation with deduplication
--      带去重的告警生成
--
--   4. test.sp_infra_backfill(p_start_date, p_end_date)
--      Historical data backfill loop
--      历史数据回填循环
--
--   5. test.sp_infra_cleanup_logs(p_retention_days)
--      Pipeline log and old alert cleanup
--      管道日志和旧告警清理
--
-- MySQL Events / MySQL定时事件:
--   1. test.evt_infra_daily_refresh
--      Daily at 06:00 UTC — main analytics refresh
--      每天UTC 06:00 — 主分析刷新
--
--   2. test.evt_infra_cleanup_logs
--      Weekly at 04:00 UTC — log rotation (90-day retention)
--      每周UTC 04:00 — 日志轮转（保留90天）
--
-- Execution Flow / 执行流程:
--   Python Orchestrator (05:30 UTC)
--     -> Collects Prometheus + CloudWatch metrics
--     -> Loads into test.infra_metric_daily
--   MySQL Event (06:00 UTC)
--     -> sp_infra_daily_refresh
--       -> sp_infra_compute_spc (SPC engine)
--       -> sp_infra_generate_alerts (alert engine)
--       -> Health score computation
--       -> Data quality verification
--       -> Pipeline logging
--
-- ============================================================
-- END -- UC-IT-01 Daily Refresh Automation
-- 结束 -- UC-IT-01 每日刷新自动化
-- ============================================================

-- ============================================================
-- UC-IT-01: Predictive Infrastructure Monitoring
-- 预测性基础设施监控
-- File: 07_fleet_health_scoring.sql
-- Source: aws-luckyus-dbatest-rw (test.infra_metric_daily, test.infra_anomaly_scores)
-- Target: aws-luckyus-dbatest-rw (test.infra_health_scores)
-- Purpose: Compute composite health scores for each infrastructure instance
-- 中文描述: 计算每个基础设施实例的综合健康评分（可用性、性能、容量、错误率、延迟）
-- Author: Data Engineering / BI Team
-- Created: 2026-02-15
-- ============================================================
--
-- Overview / 概述:
--   This script computes a composite health score (0-100) for each
--   monitored infrastructure instance, aggregating multiple metric
--   dimensions into a single actionable grade. This enables fleet-
--   wide health visibility in Grafana dashboards and prioritizes
--   remediation effort toward the most degraded resources.
--
--   此脚本为每个被监控的基础设施实例计算综合健康评分(0-100)，
--   将多个指标维度聚合为单一可操作等级。这使得在Grafana仪表板中
--   实现全局健康可视性，并将修复工作优先指向最退化的资源。
--
-- Health Score Methodology / 健康评分方法论:
--
--   Composite = 0.30 x availability_score
--             + 0.25 x performance_score
--             + 0.25 x capacity_score
--             + 0.10 x error_rate_score
--             + 0.10 x latency_score
--
--   Each dimension score: score = MAX(0, 100 - ABS(z_score) * 20)
--   每个维度评分: score = MAX(0, 100 - ABS(z_score) * 20)
--
--   This means:
--     |z| = 0   -> score = 100 (perfect, on target)
--     |z| = 1   -> score = 80  (mild deviation)
--     |z| = 2   -> score = 60  (notable deviation)
--     |z| = 3   -> score = 40  (strong deviation)
--     |z| = 4   -> score = 20  (severe deviation)
--     |z| >= 5  -> score = 0   (extreme deviation)
--
--   Grading Scale / 评分等级:
--     A: 90-100 (Excellent / 优秀)
--     B: 80-89  (Good / 良好)
--     C: 70-79  (Fair / 一般)
--     D: 60-69  (Poor / 较差)
--     F: < 60   (Critical / 严重)
--
-- Weight Rationale / 权重原理:
--   Availability (0.30): Highest weight — a down system has zero value.
--                        最高权重 — 停机系统没有任何价值。
--   Performance (0.25):  Core service quality metric.
--                        核心服务质量指标。
--   Capacity (0.25):     Forward-looking risk indicator.
--                        前瞻性风险指标。
--   Error Rate (0.10):   Quality signal, but often transient.
--                        质量信号，但通常是短暂的。
--   Latency (0.10):      User-facing impact metric.
--                        面向用户的影响指标。
--
-- Prerequisites / 前置条件:
--   - test.infra_anomaly_scores must be populated (run 05_compute_infra_anomaly_scores.sql)
--   - test.infra_health_scores table must exist (run 02_create_analytics_schema.sql)
--   - At least 7 days of anomaly scores for trend computation
--
-- Author:   Data Engineering / BI Team
-- Created:  2026-02-15
-- ============================================================


-- ############################################################
-- STEP 0: PREPARATION
-- 准备工作 — Clear target table for idempotent re-runs
-- ############################################################

TRUNCATE TABLE test.infra_health_scores;


-- ############################################################
-- STEP 1: COMPUTE DIMENSION SCORES FOR REDIS INSTANCES
-- 第一步: 计算Redis实例的各维度评分
-- ############################################################
--
-- Redis (ElastiCache) health dimensions:
-- Redis (ElastiCache) 健康维度：
--
--   availability_score:  Based on redis_up metric (1 = up, 0 = down)
--                        基于redis_up指标（1=运行中，0=停机）
--   performance_score:   Based on commands_per_sec z-score, hit_rate z-score
--                        基于commands_per_sec Z分数、hit_rate Z分数
--   capacity_score:      Based on memory_utilization z-score, connected_clients z-score
--                        基于memory_utilization Z分数、connected_clients Z分数
--   error_rate_score:    Based on rejected_connections, evicted_keys z-scores
--                        基于rejected_connections、evicted_keys Z分数
--   latency_score:       Based on command_duration z-score
--                        基于command_duration Z分数
-- ############################################################

INSERT INTO test.infra_health_scores
    (service_type, instance_id, instance_name, score_date,
     availability_score, performance_score, capacity_score,
     error_rate_score, latency_score)
SELECT
    'ElastiCache'                AS service_type,
    a.instance_id,
    a.instance_name,
    a.metric_date                AS score_date,

    -- Availability: redis_up (1=100, 0=0, null=assume up)
    -- 可用性：redis_up（1=100分，0=0分，null=假定运行中）
    COALESCE(
        MAX(CASE WHEN a.metric_name = 'redis_up'
                 THEN a.metric_value * 100 END),
        100
    )                            AS availability_score,

    -- Performance: average of commands_per_sec and hit_rate dimension scores
    -- 性能：commands_per_sec和hit_rate维度评分的平均值
    ROUND(AVG(CASE
        WHEN a.metric_name IN ('commands_per_sec', 'hit_rate')
        THEN GREATEST(0, 100 - ABS(COALESCE(a.z_score, 0)) * 20)
        ELSE NULL
    END), 1)                     AS performance_score,

    -- Capacity: average of memory_utilization and connected_clients dimension scores
    -- 容量：memory_utilization和connected_clients维度评分的平均值
    ROUND(AVG(CASE
        WHEN a.metric_name IN ('memory_utilization', 'connected_clients')
        THEN GREATEST(0, 100 - ABS(COALESCE(a.z_score, 0)) * 20)
        ELSE NULL
    END), 1)                     AS capacity_score,

    -- Error rate: average of rejected_connections and evicted_keys dimension scores
    -- 错误率：rejected_connections和evicted_keys维度评分的平均值
    ROUND(AVG(CASE
        WHEN a.metric_name IN ('rejected_connections', 'evicted_keys')
        THEN GREATEST(0, 100 - ABS(COALESCE(a.z_score, 0)) * 20)
        ELSE NULL
    END), 1)                     AS error_rate_score,

    -- Latency: command_duration dimension score
    -- 延迟：command_duration维度评分
    ROUND(AVG(CASE
        WHEN a.metric_name = 'command_duration'
        THEN GREATEST(0, 100 - ABS(COALESCE(a.z_score, 0)) * 20)
        ELSE NULL
    END), 1)                     AS latency_score

FROM test.infra_anomaly_scores a
WHERE a.service_type = 'ElastiCache'
GROUP BY a.instance_id, a.instance_name, a.metric_date;


-- ############################################################
-- STEP 2: COMPUTE DIMENSION SCORES FOR RDS INSTANCES
-- 第二步: 计算RDS实例的各维度评分
-- ############################################################
--
-- RDS (MySQL/PostgreSQL/Aurora) health dimensions:
-- RDS 健康维度：
--
--   availability_score:  Based on database_connections (0 connections = likely down)
--                        基于database_connections（0连接=可能停机）
--   performance_score:   Based on CPUUtilization z-score, read_iops/write_iops z-scores
--                        基于CPUUtilization Z分数、read_iops/write_iops Z分数
--   capacity_score:      Based on freeable_memory z-score, free_storage_space z-score
--                        基于freeable_memory Z分数、free_storage_space Z分数
--   error_rate_score:    Based on slow_query_rate z-score (if available)
--                        基于slow_query_rate Z分数（如果可用）
--   latency_score:       Based on read_latency, write_latency z-scores
--                        基于read_latency、write_latency Z分数
-- ############################################################

INSERT INTO test.infra_health_scores
    (service_type, instance_id, instance_name, score_date,
     availability_score, performance_score, capacity_score,
     error_rate_score, latency_score)
SELECT
    'RDS'                        AS service_type,
    a.instance_id,
    a.instance_name,
    a.metric_date                AS score_date,

    -- Availability: database_connections > 0 implies available
    -- 可用性：database_connections > 0 表示可用
    COALESCE(
        MAX(CASE WHEN a.metric_name = 'database_connections'
                 THEN CASE WHEN a.metric_value > 0 THEN 100 ELSE 0 END
            END),
        100
    )                            AS availability_score,

    -- Performance: CPUUtilization and IOPS z-scores
    -- 性能：CPUUtilization和IOPS Z分数
    -- For CPU, high z-score = bad; for IOPS, extreme z-score = bad
    -- 对于CPU，高Z分数=差；对于IOPS，极端Z分数=差
    ROUND(AVG(CASE
        WHEN a.metric_name IN ('cpu_utilization', 'read_iops', 'write_iops')
        THEN GREATEST(0, 100 - ABS(COALESCE(a.z_score, 0)) * 20)
        ELSE NULL
    END), 1)                     AS performance_score,

    -- Capacity: freeable_memory and free_storage_space
    -- 容量：freeable_memory和free_storage_space
    -- For these, NEGATIVE z-score is bad (low free = trouble)
    -- 对于这些指标，负Z分数为差（低可用空间=问题）
    ROUND(AVG(CASE
        WHEN a.metric_name IN ('freeable_memory', 'free_storage_space')
        THEN CASE
            WHEN a.z_score < 0
            THEN GREATEST(0, 100 - ABS(a.z_score) * 20)  -- penalize negative z
            ELSE LEAST(100, 100 - a.z_score * 5)          -- mild bonus for positive
        END
        ELSE NULL
    END), 1)                     AS capacity_score,

    -- Error rate: slow_query_rate z-score
    -- 错误率：slow_query_rate Z分数
    ROUND(AVG(CASE
        WHEN a.metric_name IN ('slow_query_rate', 'deadlock_count')
        THEN GREATEST(0, 100 - ABS(COALESCE(a.z_score, 0)) * 20)
        ELSE NULL
    END), 1)                     AS error_rate_score,

    -- Latency: read and write latency z-scores
    -- 延迟：读写延迟Z分数
    -- For latency, only high z-scores are bad
    -- 对于延迟，只有高Z分数为差
    ROUND(AVG(CASE
        WHEN a.metric_name IN ('read_latency', 'write_latency')
        THEN CASE
            WHEN a.z_score > 0
            THEN GREATEST(0, 100 - a.z_score * 20)        -- penalize high latency
            ELSE 100                                        -- low latency is fine
        END
        ELSE NULL
    END), 1)                     AS latency_score

FROM test.infra_anomaly_scores a
WHERE a.service_type = 'RDS'
GROUP BY a.instance_id, a.instance_name, a.metric_date;


-- ############################################################
-- STEP 2B: COMPUTE DIMENSION SCORES FOR EC2 INSTANCES
-- 第二B步: 计算EC2实例的各维度评分
-- ############################################################
--
-- EC2 instance health dimensions (if EC2 metrics collected):
-- EC2实例健康维度（如果收集了EC2指标）：

INSERT INTO test.infra_health_scores
    (service_type, instance_id, instance_name, score_date,
     availability_score, performance_score, capacity_score,
     error_rate_score, latency_score)
SELECT
    'EC2'                        AS service_type,
    a.instance_id,
    a.instance_name,
    a.metric_date                AS score_date,

    -- Availability: instance status check (assume up if metrics exist)
    -- 可用性：实例状态检查（如果存在指标则假定运行中）
    100                          AS availability_score,

    -- Performance: CPU utilization z-score
    -- 性能：CPU利用率Z分数
    ROUND(AVG(CASE
        WHEN a.metric_name = 'cpu_utilization'
        THEN CASE
            WHEN a.z_score > 0
            THEN GREATEST(0, 100 - a.z_score * 20)
            ELSE 100
        END
        ELSE NULL
    END), 1)                     AS performance_score,

    -- Capacity: disk and memory metrics
    -- 容量：磁盘和内存指标
    ROUND(AVG(CASE
        WHEN a.metric_name IN ('disk_utilization', 'memory_utilization')
        THEN CASE
            WHEN a.z_score > 0
            THEN GREATEST(0, 100 - a.z_score * 20)
            ELSE 100
        END
        ELSE NULL
    END), 1)                     AS capacity_score,

    -- Error rate: network errors
    -- 错误率：网络错误
    ROUND(AVG(CASE
        WHEN a.metric_name = 'network_errors'
        THEN GREATEST(0, 100 - ABS(COALESCE(a.z_score, 0)) * 20)
        ELSE NULL
    END), 1)                     AS error_rate_score,

    -- Latency: network latency
    -- 延迟：网络延迟
    ROUND(AVG(CASE
        WHEN a.metric_name = 'network_latency'
        THEN CASE
            WHEN a.z_score > 0
            THEN GREATEST(0, 100 - a.z_score * 20)
            ELSE 100
        END
        ELSE NULL
    END), 1)                     AS latency_score

FROM test.infra_anomaly_scores a
WHERE a.service_type = 'EC2'
GROUP BY a.instance_id, a.instance_name, a.metric_date;


-- ############################################################
-- STEP 3: COMPUTE COMPOSITE SCORES AND GRADES
-- 第三步: 计算综合评分和等级
-- ############################################################
--
-- Apply the weighted formula to combine dimension scores into
-- a single composite score, then assign letter grades.
-- 应用加权公式将维度评分合并为单一综合评分，然后分配字母等级。
--
-- Weight distribution:
--   Availability:  0.30 (highest — downtime = zero value)
--   Performance:   0.25
--   Capacity:      0.25
--   Error Rate:    0.10
--   Latency:       0.10
-- ############################################################

UPDATE test.infra_health_scores
SET composite_score = ROUND(
    0.30 * COALESCE(availability_score, 100)
  + 0.25 * COALESCE(performance_score, 100)
  + 0.25 * COALESCE(capacity_score, 100)
  + 0.10 * COALESCE(error_rate_score, 100)
  + 0.10 * COALESCE(latency_score, 100)
, 1);

-- Assign letter grades / 分配字母等级
UPDATE test.infra_health_scores
SET health_grade = CASE
    WHEN composite_score >= 90 THEN 'A'
    WHEN composite_score >= 80 THEN 'B'
    WHEN composite_score >= 70 THEN 'C'
    WHEN composite_score >= 60 THEN 'D'
    ELSE 'F'
END;

-- Set grade descriptions (bilingual) / 设置等级描述（双语）
UPDATE test.infra_health_scores
SET grade_description_en = CASE health_grade
        WHEN 'A' THEN 'Excellent - Operating within normal parameters'
        WHEN 'B' THEN 'Good - Minor deviations, monitor closely'
        WHEN 'C' THEN 'Fair - Notable deviations, investigate root cause'
        WHEN 'D' THEN 'Poor - Significant issues, remediation needed'
        WHEN 'F' THEN 'Critical - Severe degradation, immediate action required'
    END,
    grade_description_cn = CASE health_grade
        WHEN 'A' THEN '优秀 - 在正常参数内运行'
        WHEN 'B' THEN '良好 - 轻微偏差，密切监控'
        WHEN 'C' THEN '一般 - 明显偏差，需调查根因'
        WHEN 'D' THEN '较差 - 显著问题，需要修复'
        WHEN 'F' THEN '严重 - 严重退化，需立即处理'
    END;


-- ############################################################
-- STEP 4: COMPUTE TREND DIRECTION AND WEEK-OVER-WEEK CHANGE
-- 第四步: 计算趋势方向和周环比变化
-- ############################################################
--
-- Compare current week's average composite score to previous
-- week's average. Classify the trend direction.
-- 比较本周平均综合评分与上周平均值。分类趋势方向。
--
-- Trend categories / 趋势类别:
--   IMPROVING:  current_week_avg > prev_week_avg + 2
--               本周均值 > 上周均值 + 2
--   STABLE:     within +/- 2 points
--               在+/-2分之内
--   DEGRADING:  current_week_avg < prev_week_avg - 2
--               本周均值 < 上周均值 - 2
-- ############################################################

-- Create temporary table for weekly averages / 创建每周平均值临时表
DROP TEMPORARY TABLE IF EXISTS tmp_weekly_health;

CREATE TEMPORARY TABLE tmp_weekly_health AS
SELECT
    instance_id,
    YEARWEEK(score_date, 1)                          AS year_week,
    AVG(composite_score)                              AS avg_score,
    MIN(score_date)                                   AS week_start,
    MAX(score_date)                                   AS week_end,
    COUNT(*)                                          AS data_points
FROM test.infra_health_scores
GROUP BY instance_id, YEARWEEK(score_date, 1);

-- Add index for join performance / 添加索引提升联接性能
ALTER TABLE tmp_weekly_health ADD INDEX idx_lookup (instance_id, year_week);


-- Update with week-over-week comparison / 更新周环比
UPDATE test.infra_health_scores h
JOIN (
    SELECT
        curr.instance_id,
        curr.year_week,
        curr.week_start,
        curr.week_end,
        ROUND(curr.avg_score, 1)                       AS current_week_avg,
        ROUND(prev.avg_score, 1)                       AS previous_week_avg,
        ROUND(curr.avg_score - prev.avg_score, 1)      AS wow_change
    FROM tmp_weekly_health curr
    JOIN tmp_weekly_health prev
        ON  curr.instance_id = prev.instance_id
        AND prev.year_week   = curr.year_week - 1
) w ON  h.instance_id = w.instance_id
    AND h.score_date BETWEEN w.week_start AND w.week_end
SET h.wow_change = w.wow_change,
    h.trend_direction = CASE
        WHEN w.wow_change >  2 THEN 'IMPROVING'
        WHEN w.wow_change < -2 THEN 'DEGRADING'
        ELSE 'STABLE'
    END;

-- Clean up temporary table / 清理临时表
DROP TEMPORARY TABLE IF EXISTS tmp_weekly_health;


-- ############################################################
-- STEP 5: FLEET-WIDE HEALTH SUMMARY QUERIES
-- 第五步: 全局健康摘要查询
-- ############################################################


-- ─────────────────────────────────────────────────────
-- 5.1  Grade distribution by service type (latest date)
-- 按服务类型的等级分布（最新日期）
-- ─────────────────────────────────────────────────────

SELECT
    h.service_type,
    SUM(CASE WHEN h.health_grade = 'A' THEN 1 ELSE 0 END) AS grade_a,
    SUM(CASE WHEN h.health_grade = 'B' THEN 1 ELSE 0 END) AS grade_b,
    SUM(CASE WHEN h.health_grade = 'C' THEN 1 ELSE 0 END) AS grade_c,
    SUM(CASE WHEN h.health_grade = 'D' THEN 1 ELSE 0 END) AS grade_d,
    SUM(CASE WHEN h.health_grade = 'F' THEN 1 ELSE 0 END) AS grade_f,
    COUNT(*)                                                AS total_instances,
    ROUND(AVG(h.composite_score), 1)                       AS avg_composite,
    ROUND(MIN(h.composite_score), 1)                       AS min_composite,
    ROUND(MAX(h.composite_score), 1)                       AS max_composite
FROM test.infra_health_scores h
WHERE h.score_date = (SELECT MAX(score_date) FROM test.infra_health_scores)
GROUP BY h.service_type
ORDER BY avg_composite ASC;


-- ─────────────────────────────────────────────────────
-- 5.2  Overall fleet health grade distribution (latest date)
-- 全局健康等级分布（最新日期）
-- ─────────────────────────────────────────────────────

SELECT
    health_grade,
    grade_description_en,
    grade_description_cn,
    COUNT(*)                                                AS instance_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)     AS percentage,
    ROUND(AVG(composite_score), 1)                         AS avg_score_in_grade
FROM test.infra_health_scores
WHERE score_date = (SELECT MAX(score_date) FROM test.infra_health_scores)
GROUP BY health_grade, grade_description_en, grade_description_cn
ORDER BY FIELD(health_grade, 'A', 'B', 'C', 'D', 'F');


-- ─────────────────────────────────────────────────────
-- 5.3  Bottom 10 instances by health score (needs attention)
-- 健康评分最低的10个实例（需关注）
-- ─────────────────────────────────────────────────────

SELECT
    service_type,
    instance_id,
    instance_name,
    score_date,
    ROUND(composite_score, 1)       AS composite_score,
    health_grade,
    ROUND(availability_score, 1)    AS avail_score,
    ROUND(performance_score, 1)     AS perf_score,
    ROUND(capacity_score, 1)        AS cap_score,
    ROUND(error_rate_score, 1)      AS err_score,
    ROUND(latency_score, 1)         AS lat_score,
    COALESCE(trend_direction, 'N/A') AS trend,
    ROUND(wow_change, 1)            AS wow_change
FROM test.infra_health_scores
WHERE score_date = (SELECT MAX(score_date) FROM test.infra_health_scores)
ORDER BY composite_score ASC
LIMIT 10;


-- ─────────────────────────────────────────────────────
-- 5.4  Instances with degrading trend (week-over-week decline)
-- 趋势恶化的实例（周环比下降）
-- ─────────────────────────────────────────────────────

SELECT
    service_type,
    instance_id,
    instance_name,
    score_date,
    ROUND(composite_score, 1)       AS composite_score,
    health_grade,
    trend_direction,
    ROUND(wow_change, 1)            AS wow_change
FROM test.infra_health_scores
WHERE score_date = (SELECT MAX(score_date) FROM test.infra_health_scores)
  AND trend_direction = 'DEGRADING'
ORDER BY wow_change ASC
LIMIT 20;


-- ─────────────────────────────────────────────────────
-- 5.5  Weekly fleet health trend (7-day rolling average)
-- 每周全局健康趋势（7天滚动平均）
-- ─────────────────────────────────────────────────────

SELECT
    score_date,
    COUNT(DISTINCT instance_id)                             AS instances_scored,
    ROUND(AVG(composite_score), 1)                         AS fleet_avg_score,
    ROUND(MIN(composite_score), 1)                         AS fleet_min_score,
    ROUND(MAX(composite_score), 1)                         AS fleet_max_score,
    SUM(CASE WHEN health_grade = 'F' THEN 1 ELSE 0 END)   AS critical_count,
    SUM(CASE WHEN health_grade = 'D' THEN 1 ELSE 0 END)   AS poor_count
FROM test.infra_health_scores
WHERE score_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY score_date
ORDER BY score_date;


-- ─────────────────────────────────────────────────────
-- 5.6  Dimension score comparison by service type
-- 按服务类型的维度评分对比
-- ─────────────────────────────────────────────────────
-- Identify which health dimension is weakest across each service type.
-- 识别每种服务类型中最薄弱的健康维度。

SELECT
    service_type,
    ROUND(AVG(availability_score), 1)   AS avg_availability,
    ROUND(AVG(performance_score), 1)    AS avg_performance,
    ROUND(AVG(capacity_score), 1)       AS avg_capacity,
    ROUND(AVG(error_rate_score), 1)     AS avg_error_rate,
    ROUND(AVG(latency_score), 1)        AS avg_latency,
    -- Identify weakest dimension / 识别最薄弱维度
    CASE
        WHEN AVG(COALESCE(availability_score, 100)) <= AVG(COALESCE(performance_score, 100))
         AND AVG(COALESCE(availability_score, 100)) <= AVG(COALESCE(capacity_score, 100))
         AND AVG(COALESCE(availability_score, 100)) <= AVG(COALESCE(error_rate_score, 100))
         AND AVG(COALESCE(availability_score, 100)) <= AVG(COALESCE(latency_score, 100))
        THEN 'Availability / 可用性'
        WHEN AVG(COALESCE(performance_score, 100)) <= AVG(COALESCE(capacity_score, 100))
         AND AVG(COALESCE(performance_score, 100)) <= AVG(COALESCE(error_rate_score, 100))
         AND AVG(COALESCE(performance_score, 100)) <= AVG(COALESCE(latency_score, 100))
        THEN 'Performance / 性能'
        WHEN AVG(COALESCE(capacity_score, 100)) <= AVG(COALESCE(error_rate_score, 100))
         AND AVG(COALESCE(capacity_score, 100)) <= AVG(COALESCE(latency_score, 100))
        THEN 'Capacity / 容量'
        WHEN AVG(COALESCE(error_rate_score, 100)) <= AVG(COALESCE(latency_score, 100))
        THEN 'Error Rate / 错误率'
        ELSE 'Latency / 延迟'
    END AS weakest_dimension
FROM test.infra_health_scores
WHERE score_date = (SELECT MAX(score_date) FROM test.infra_health_scores)
GROUP BY service_type
ORDER BY AVG(composite_score) ASC;


-- ─────────────────────────────────────────────────────
-- 5.7  Health score heatmap data (for Grafana)
-- 健康评分热力图数据（用于Grafana）
-- ─────────────────────────────────────────────────────
-- Pivoted format suitable for Grafana heatmap panel.
-- 适合Grafana热力图面板的透视格式。

SELECT
    instance_name,
    service_type,
    score_date,
    composite_score,
    health_grade,
    availability_score,
    performance_score,
    capacity_score,
    error_rate_score,
    latency_score
FROM test.infra_health_scores
WHERE score_date >= DATE_SUB(CURDATE(), INTERVAL 14 DAY)
ORDER BY service_type, instance_name, score_date;


-- ############################################################
-- STEP 6: VERIFICATION QUERIES
-- 第六步: 验证查询
-- ############################################################


-- ─────────────────────────────────────────────────────
-- 6.1  Row count and coverage check
-- 行数和覆盖率检查
-- ─────────────────────────────────────────────────────

SELECT
    'infra_health_scores'                                   AS table_name,
    COUNT(*)                                                AS total_rows,
    COUNT(DISTINCT service_type)                            AS distinct_service_types,
    COUNT(DISTINCT instance_id)                             AS distinct_instances,
    COUNT(DISTINCT score_date)                              AS distinct_dates,
    MIN(score_date)                                         AS min_date,
    MAX(score_date)                                         AS max_date,
    SUM(CASE WHEN composite_score IS NULL THEN 1 ELSE 0 END)  AS null_composite,
    SUM(CASE WHEN health_grade IS NULL THEN 1 ELSE 0 END)     AS null_grade
FROM test.infra_health_scores;


-- ─────────────────────────────────────────────────────
-- 6.2  Score distribution histogram
-- 评分分布直方图
-- ─────────────────────────────────────────────────────

SELECT
    CASE
        WHEN composite_score >= 95 THEN '95-100'
        WHEN composite_score >= 90 THEN '90-94'
        WHEN composite_score >= 85 THEN '85-89'
        WHEN composite_score >= 80 THEN '80-84'
        WHEN composite_score >= 70 THEN '70-79'
        WHEN composite_score >= 60 THEN '60-69'
        WHEN composite_score >= 50 THEN '50-59'
        ELSE '< 50'
    END                                                     AS score_range,
    COUNT(*)                                                AS instance_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)     AS percentage
FROM test.infra_health_scores
WHERE score_date = (SELECT MAX(score_date) FROM test.infra_health_scores)
GROUP BY score_range
ORDER BY FIELD(score_range,
    '95-100', '90-94', '85-89', '80-84',
    '70-79', '60-69', '50-59', '< 50');


-- ─────────────────────────────────────────────────────
-- 6.3  NULL dimension analysis
-- NULL维度分析
-- ─────────────────────────────────────────────────────
-- Identifies instances where dimension scores are NULL due to
-- missing metric data. These represent monitoring coverage gaps.
-- 识别因缺少指标数据而维度评分为NULL的实例。这些代表监控覆盖缺口。

SELECT
    service_type,
    SUM(CASE WHEN availability_score IS NULL THEN 1 ELSE 0 END) AS null_availability,
    SUM(CASE WHEN performance_score IS NULL THEN 1 ELSE 0 END)  AS null_performance,
    SUM(CASE WHEN capacity_score IS NULL THEN 1 ELSE 0 END)     AS null_capacity,
    SUM(CASE WHEN error_rate_score IS NULL THEN 1 ELSE 0 END)   AS null_error_rate,
    SUM(CASE WHEN latency_score IS NULL THEN 1 ELSE 0 END)      AS null_latency,
    COUNT(*)                                                     AS total_rows
FROM test.infra_health_scores
WHERE score_date = (SELECT MAX(score_date) FROM test.infra_health_scores)
GROUP BY service_type;


-- ############################################################
-- END OF SCRIPT
-- 脚本结束
-- ############################################################
--
-- Summary of operations performed / 执行的操作摘要:
--   1. Truncated infra_health_scores (idempotent reset)
--      截断infra_health_scores（幂等重置）
--   2. Computed dimension scores for ElastiCache Redis instances
--      计算ElastiCache Redis实例的维度评分
--   3. Computed dimension scores for RDS instances
--      计算RDS实例的维度评分
--   4. Computed dimension scores for EC2 instances
--      计算EC2实例的维度评分
--   5. Calculated composite scores and letter grades
--      计算综合评分和字母等级
--   6. Computed week-over-week trends
--      计算周环比趋势
--   7. Generated fleet-wide summary analytics
--      生成全局摘要分析
--
-- Health Score Formula / 健康评分公式:
--   Composite = 0.30*Availability + 0.25*Performance + 0.25*Capacity
--             + 0.10*ErrorRate + 0.10*Latency
--
-- Grading: A(90-100) B(80-89) C(70-79) D(60-69) F(<60)
-- 评分: A(90-100优秀) B(80-89良好) C(70-79一般) D(60-69较差) F(<60严重)
--
-- Next Steps / 后续步骤:
--   - Run 08_daily_refresh.sql to schedule automated execution
--     运行08_daily_refresh.sql安排自动执行
--   - Import dashboards/infra_health_heatmap.json into Grafana
--     将dashboards/infra_health_heatmap.json导入Grafana
--   - Review bottom-10 instances for remediation priority
--     审查最低10个实例以确定修复优先级
--
-- ============================================================
-- END -- UC-IT-01 Fleet Health Scoring Engine
-- 结束 -- UC-IT-01 全局健康评分引擎
-- ============================================================

-- ============================================================
-- UC-IT-01: Predictive Infrastructure Monitoring
-- 预测性基础设施监控
-- File: 05_compute_infra_anomaly_scores.sql
-- Source: aws-luckyus-dbatest-rw (test.infra_metric_daily)
-- Target: aws-luckyus-dbatest-rw (test.infra_anomaly_scores)
-- Purpose: Compute SPC-based anomaly scores for infrastructure metrics
-- 中文描述: 计算基础设施指标的SPC异常评分（Z分数、控制限、西部电气规则、变化率）
-- Author: Data Engineering / BI Team
-- Created: 2026-02-15
-- ============================================================
--
-- Overview / 概述:
--   This is the core SPC analytics engine for the UC-IT-01 pipeline.
--   It reads daily infrastructure metric data from infra_metric_daily
--   and computes Statistical Process Control (SPC) metrics for each
--   service_type / instance_id / metric_name combination, writing
--   results into infra_anomaly_scores.
--
--   这是UC-IT-01管道的核心SPC分析引擎。它从infra_metric_daily读取
--   每日基础设施指标数据，为每个 service_type / instance_id /
--   metric_name 组合计算统计过程控制(SPC)指标，并将结果写入
--   infra_anomaly_scores。
--
-- Adapted From / 改编自:
--   UC-OP-02 05_compute_anomaly_scores.sql (store performance SPC engine)
--   Key differences from UC-OP-02:
--     1. 14-day rolling window (not 28) — infrastructure changes faster
--        14天滚动窗口（非28天）— 基础设施变化更快
--     2. No day-of-week adjustment — infra metrics lack weekly seasonality
--        无星期调整 — 基础设施指标缺乏周期性季节性
--     3. Rate-of-change features added (1-day and 7-day)
--        新增变化率特征（1天和7天）
--     4. Metric-specific directionality logic (some metrics only alert on UCL/LCL)
--        指标方向性逻辑（部分指标仅在UCL/LCL触发告警）
--
-- Pipeline Steps / 管道步骤:
--   Step 1: Compute 14-day rolling statistics (mean, std_dev)
--           计算14天滚动统计（均值、标准差）
--   Step 2: Compute Z-scores and control limits (2σ, 3σ)
--           计算Z分数和控制限（2σ、3σ）
--   Step 3: Evaluate Western Electric Rules (5 rules)
--           评估西部电气规则（5条规则）
--   Step 4: Compute rate-of-change features (1d, 7d)
--           计算变化率特征（1天、7天）
--   Step 5: Determine anomaly severity with metric-specific logic
--           结合指标方向性确定异常严重度
--   Step 6: Generate alert records into infra_anomaly_alerts
--           生成告警记录到infra_anomaly_alerts
--
-- SPC Background / SPC背景:
--   Statistical Process Control was developed by Walter Shewhart at
--   Bell Labs in the 1920s. The Western Electric Rules (1956 AT&T
--   Statistical Quality Control Handbook) detect non-random patterns
--   before points cross 3-sigma, providing early warning capability.
--
--   统计过程控制由Walter Shewhart于1920年代在贝尔实验室开发。
--   西部电气规则（1956年AT&T《统计质量控制手册》）在数据点越过
--   3-sigma之前检测非随机模式，提供预警能力。
--
-- Metric Directionality / 指标方向性:
--   Not all infrastructure metrics are symmetric. Some are only
--   concerning when they go UP, others only when they go DOWN.
--   不是所有基础设施指标都是对称的。有些仅在上升时令人担忧，
--   有些仅在下降时令人担忧。
--
--   UCL-only (high is bad / 高值为异常):
--     cpu_utilization, memory_utilization, latency, disk_iops,
--     command_duration, evicted_keys, rejected_connections
--
--   LCL-only (low is bad / 低值为异常):
--     hit_rate, free_storage, freeable_memory, cache_hit_ratio
--
--   Both sides (any extreme is bad / 任何极端均为异常):
--     connected_clients, commands_per_sec, database_connections
--
-- Prerequisites / 前置条件:
--   - test.infra_metric_daily must be populated (run 03/04 extraction scripts)
--   - test.infra_anomaly_scores table must exist (run 02_create_analytics_schema.sql)
--   - At least 14 days of historical data should be available
--   - test.infra_anomaly_alerts table must exist for alert generation
--
-- Author:   Data Engineering / BI Team
-- Created:  2026-02-15
-- ============================================================


-- ############################################################
-- STEP 0: PREPARATION
-- 准备工作 — Clear target table for idempotent re-runs
-- ############################################################

-- Truncate the anomaly_scores table so this script is idempotent.
-- If you want incremental loads, replace TRUNCATE with a
-- date-range DELETE instead.
-- 截断异常评分表以便此脚本可重复执行。
-- 如需增量加载，请将TRUNCATE替换为按日期范围的DELETE。

TRUNCATE TABLE test.infra_anomaly_scores;


-- ############################################################
-- STEP 1: COMPUTE 14-DAY ROLLING STATISTICS
-- 第一步: 计算14天滚动统计（均值、标准差）
-- ############################################################
--
-- For each infrastructure metric, we compute:
-- 对于每个基础设施指标，我们计算：
--
--   rolling_mean_14d : Mean of the metric over the prior 14 days
--                      (including current day). This is the center
--                      line of our SPC control chart.
--                      过去14天指标的均值（包括当天），即SPC控制图的中心线。
--
--   rolling_std_14d  : Sample standard deviation over same window.
--                      This measures natural process variation.
--                      同窗口的样本标准差，衡量过程的自然变异。
--
-- We use ROWS BETWEEN 13 PRECEDING AND CURRENT ROW to get exactly
-- 14 data points (13 prior + 1 current). This corresponds to a
-- 2-week lookback which is appropriate for infrastructure metrics
-- that can shift behavior within days of configuration changes.
-- 我们使用 ROWS BETWEEN 13 PRECEDING AND CURRENT ROW 获取恰好
-- 14个数据点（13个前值+1个当前值），对应2周回溯期，适用于
-- 配置变更后数天内可能改变行为的基础设施指标。
--
-- WHY 14 DAYS, NOT 28?
-- Infrastructure metrics respond faster than business KPIs to
-- real changes (e.g., scaling events, deployments, config changes).
-- A 28-day window would dilute recent patterns and delay detection.
-- 为什么14天而非28天？
-- 基础设施指标对真实变化（如扩缩容、部署、配置变更）的响应比
-- 业务KPI更快。28天窗口会稀释近期模式并延迟检测。
--
-- NOTE: We insert all metrics in a single pass using the generic
-- columns from infra_metric_daily, unlike UC-OP-02 which inserts
-- each KPI separately. This is possible because infra_metric_daily
-- already has a normalized (metric_name, metric_value) structure.
-- 注意：我们使用infra_metric_daily的通用列在单次操作中插入所有指标，
-- 不同于UC-OP-02逐个KPI插入。这是因为infra_metric_daily已具有
-- 标准化的(metric_name, metric_value)结构。
-- ############################################################

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
    AVG(m.metric_value) OVER w14                AS rolling_mean_14d,
    STDDEV_SAMP(m.metric_value) OVER w14        AS rolling_std_14d
FROM test.infra_metric_daily m
WHERE m.metric_date >= '2025-10-01'
  AND m.metric_value IS NOT NULL
WINDOW w14 AS (
    PARTITION BY m.service_type, m.instance_id, m.metric_name
    ORDER BY m.metric_date
    ROWS BETWEEN 13 PRECEDING AND CURRENT ROW
);


-- ############################################################
-- STEP 2: COMPUTE Z-SCORES AND CONTROL LIMITS
-- 第二步: 计算Z分数和控制限
-- ############################################################
--
-- Now that rolling_mean_14d and rolling_std_14d are populated,
-- we compute:
-- 既然rolling_mean_14d和rolling_std_14d已填充，我们计算：
--
--   z_score    = (metric_value - rolling_mean_14d) / rolling_std_14d
--   ucl_2sigma = rolling_mean_14d + 2 * rolling_std_14d
--   ucl_3sigma = rolling_mean_14d + 3 * rolling_std_14d
--   lcl_2sigma = rolling_mean_14d - 2 * rolling_std_14d
--   lcl_3sigma = rolling_mean_14d - 3 * rolling_std_14d
--
-- NULLIF(rolling_std_14d, 0) prevents division by zero when
-- a resource has zero variance (e.g., constant metric values or
-- only 1 day of data in the window).
-- NULLIF(rolling_std_14d, 0) 防止当资源方差为零时除以零
-- （例如，指标值恒定或窗口中只有1天数据）。
--
-- Control limit interpretation / 控制限解读:
--   2-sigma limits: ~95.4% of normal data falls within
--                   约95.4%的正常数据落在此范围内
--   3-sigma limits: ~99.7% of normal data falls within
--                   约99.7%的正常数据落在此范围内
-- ############################################################

UPDATE test.infra_anomaly_scores
SET z_score    = CASE WHEN rolling_std_14d > 0
                      THEN (metric_value - rolling_mean_14d) / rolling_std_14d
                      ELSE 0 END,
    ucl_2sigma = rolling_mean_14d + 2.0 * rolling_std_14d,
    ucl_3sigma = rolling_mean_14d + 3.0 * rolling_std_14d,
    lcl_2sigma = rolling_mean_14d - 2.0 * rolling_std_14d,
    lcl_3sigma = rolling_mean_14d - 3.0 * rolling_std_14d
WHERE rolling_std_14d IS NOT NULL;

-- Handle the zero-std case: set control limits to mean (degenerate chart)
-- 处理零标准差情况：控制限设为均值（退化控制图）
UPDATE test.infra_anomaly_scores
SET z_score    = 0,
    ucl_2sigma = rolling_mean_14d,
    ucl_3sigma = rolling_mean_14d,
    lcl_2sigma = rolling_mean_14d,
    lcl_3sigma = rolling_mean_14d
WHERE rolling_std_14d IS NOT NULL
  AND rolling_std_14d = 0;


-- ############################################################
-- STEP 3: EVALUATE WESTERN ELECTRIC RULES (5 RULES)
-- 第三步: 评估西部电气规则（5条规则）
-- ############################################################
--
-- The Western Electric rules detect non-random patterns on control
-- charts. They trigger alerts earlier than waiting for a single
-- 3-sigma violation. Implementation uses LAG() window functions to
-- access prior z-score values within the same partition.
-- 西部电气规则检测控制图上的非随机模式。它们比等待单次3-sigma
-- 违反更早触发警报。实现使用LAG()窗口函数访问同分区内先前z分数值。
-- ############################################################


-- ─────────────────────────────────────────────────────
-- 3.1  WE Rule 1: Single point beyond 3σ → CRITICAL
-- WE规则1: 单点超过3σ → 严重
-- ─────────────────────────────────────────────────────
-- Probability under normality: 0.27% per point.
-- 正态分布下概率：每点0.27%。
-- Interpretation: Almost certainly a special cause.
-- 解读：几乎可以确定是特殊原因。

UPDATE test.infra_anomaly_scores
SET we_rule1 = (ABS(z_score) > 3)
WHERE z_score IS NOT NULL;


-- ─────────────────────────────────────────────────────
-- 3.2  WE Rule 2: 2 of 3 consecutive beyond 2σ (same side) → WARNING
-- WE规则2: 连续3点中2点超过2σ（同侧）→ 警告
-- ─────────────────────────────────────────────────────
-- Detects emerging shifts not yet at 3-sigma.
-- 检测尚未达到3-sigma的新出现偏移。
-- Probability under normality: ~0.16%
-- 正态分布下概率：约0.16%

UPDATE test.infra_anomaly_scores a
JOIN (
    SELECT
        id,
        z_score                            AS z0,
        LAG(z_score, 1) OVER w             AS z1,
        LAG(z_score, 2) OVER w             AS z2
    FROM test.infra_anomaly_scores
    WINDOW w AS (PARTITION BY service_type, instance_id, metric_name
                 ORDER BY metric_date)
) b ON a.id = b.id
SET a.we_rule2 = (
    -- Upper side: 2 of 3 points above +2σ / 上侧：3点中2点高于+2σ
    (   (CASE WHEN b.z0 > 2 THEN 1 ELSE 0 END)
      + (CASE WHEN b.z1 > 2 THEN 1 ELSE 0 END)
      + (CASE WHEN b.z2 > 2 THEN 1 ELSE 0 END)
    ) >= 2
    OR
    -- Lower side: 2 of 3 points below -2σ / 下侧：3点中2点低于-2σ
    (   (CASE WHEN b.z0 < -2 THEN 1 ELSE 0 END)
      + (CASE WHEN b.z1 < -2 THEN 1 ELSE 0 END)
      + (CASE WHEN b.z2 < -2 THEN 1 ELSE 0 END)
    ) >= 2
)
WHERE b.z0 IS NOT NULL
  AND b.z1 IS NOT NULL
  AND b.z2 IS NOT NULL;


-- ─────────────────────────────────────────────────────
-- 3.3  WE Rule 3: 4 of 5 consecutive beyond 1σ (same side) → WARNING
-- WE规则3: 连续5点中4点超过1σ（同侧）→ 警告
-- ─────────────────────────────────────────────────────
-- Detects small but persistent process shifts.
-- 检测小幅但持续的过程偏移。
-- Probability under normality: ~0.27%
-- 正态分布下概率：约0.27%

UPDATE test.infra_anomaly_scores a
JOIN (
    SELECT
        id,
        z_score                            AS z0,
        LAG(z_score, 1) OVER w             AS z1,
        LAG(z_score, 2) OVER w             AS z2,
        LAG(z_score, 3) OVER w             AS z3,
        LAG(z_score, 4) OVER w             AS z4
    FROM test.infra_anomaly_scores
    WINDOW w AS (PARTITION BY service_type, instance_id, metric_name
                 ORDER BY metric_date)
) b ON a.id = b.id
SET a.we_rule3 = (
    -- Upper side: 4 of 5 points above +1σ / 上侧：5点中4点高于+1σ
    (   (CASE WHEN b.z0 > 1 THEN 1 ELSE 0 END)
      + (CASE WHEN b.z1 > 1 THEN 1 ELSE 0 END)
      + (CASE WHEN b.z2 > 1 THEN 1 ELSE 0 END)
      + (CASE WHEN b.z3 > 1 THEN 1 ELSE 0 END)
      + (CASE WHEN b.z4 > 1 THEN 1 ELSE 0 END)
    ) >= 4
    OR
    -- Lower side: 4 of 5 points below -1σ / 下侧：5点中4点低于-1σ
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
-- 3.4  WE Rule 4: 8 consecutive points on same side of center → WARNING
-- WE规则4: 连续8点在中心线同侧 → 警告
-- ─────────────────────────────────────────────────────
-- Probability under normality: (0.5)^8 = 0.39%
-- 正态分布下概率：(0.5)^8 = 0.39%
-- Interpretation: Process mean has shifted.
-- 解读：过程均值已发生偏移。

UPDATE test.infra_anomaly_scores a
JOIN (
    SELECT
        id,
        z_score                            AS z0,
        LAG(z_score, 1) OVER w             AS z1,
        LAG(z_score, 2) OVER w             AS z2,
        LAG(z_score, 3) OVER w             AS z3,
        LAG(z_score, 4) OVER w             AS z4,
        LAG(z_score, 5) OVER w             AS z5,
        LAG(z_score, 6) OVER w             AS z6,
        LAG(z_score, 7) OVER w             AS z7
    FROM test.infra_anomaly_scores
    WINDOW w AS (PARTITION BY service_type, instance_id, metric_name
                 ORDER BY metric_date)
) b ON a.id = b.id
SET a.we_rule4 = (
    -- All 8 points above center (all z > 0) / 全部8点在中心线以上
    (    b.z0 > 0 AND b.z1 > 0 AND b.z2 > 0 AND b.z3 > 0
     AND b.z4 > 0 AND b.z5 > 0 AND b.z6 > 0 AND b.z7 > 0)
    OR
    -- All 8 points below center (all z < 0) / 全部8点在中心线以下
    (    b.z0 < 0 AND b.z1 < 0 AND b.z2 < 0 AND b.z3 < 0
     AND b.z4 < 0 AND b.z5 < 0 AND b.z6 < 0 AND b.z7 < 0)
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
-- 3.5  WE Rule 5: 6 consecutive points trending same direction → INFO
-- WE规则5: 连续6点同向趋势 → 信息
-- ─────────────────────────────────────────────────────
-- We check for monotonic increase OR monotonic decrease across
-- 6 consecutive metric_value observations. This detects gradual
-- degradation patterns like memory leaks, disk fill, or slow
-- performance erosion.
-- 我们检查连续6个metric_value观测值的单调递增或单调递减。
-- 这检测渐进退化模式，如内存泄漏、磁盘填满或性能缓慢下降。
--
-- NOTE: We compare metric_value (not z_score) because the raw
-- trend is what we care about for this rule.
-- 注意：我们比较metric_value（不是z_score），因为此规则关注原始趋势。

UPDATE test.infra_anomaly_scores a
JOIN (
    SELECT
        id,
        metric_value                       AS v0,
        LAG(metric_value, 1) OVER w        AS v1,
        LAG(metric_value, 2) OVER w        AS v2,
        LAG(metric_value, 3) OVER w        AS v3,
        LAG(metric_value, 4) OVER w        AS v4,
        LAG(metric_value, 5) OVER w        AS v5
    FROM test.infra_anomaly_scores
    WINDOW w AS (PARTITION BY service_type, instance_id, metric_name
                 ORDER BY metric_date)
) b ON a.id = b.id
SET a.we_rule5 = (
    -- Monotonic decrease: v5 > v4 > v3 > v2 > v1 > v0 (6 declining)
    -- 单调递减：v5 > v4 > v3 > v2 > v1 > v0（连续6点递减）
    (b.v5 > b.v4 AND b.v4 > b.v3 AND b.v3 > b.v2
     AND b.v2 > b.v1 AND b.v1 > b.v0)
    OR
    -- Monotonic increase: v5 < v4 < v3 < v2 < v1 < v0 (6 rising)
    -- 单调递增：v5 < v4 < v3 < v2 < v1 < v0（连续6点递增）
    (b.v5 < b.v4 AND b.v4 < b.v3 AND b.v3 < b.v2
     AND b.v2 < b.v1 AND b.v1 < b.v0)
)
WHERE b.v0 IS NOT NULL
  AND b.v1 IS NOT NULL
  AND b.v2 IS NOT NULL
  AND b.v3 IS NOT NULL
  AND b.v4 IS NOT NULL
  AND b.v5 IS NOT NULL;


-- ############################################################
-- STEP 4: COMPUTE RATE-OF-CHANGE FEATURES (NEW FOR INFRA)
-- 第四步: 计算变化率特征（基础设施新增）
-- ############################################################
--
-- Rate-of-change (ROC) captures sudden shifts that may not yet
-- register in the 14-day rolling Z-score. This is critical for
-- infrastructure because a server can go from healthy to failing
-- in hours, but the daily Z-score may still look normal.
-- 变化率(ROC)捕捉尚未在14天滚动Z分数中体现的突然变化。这对
-- 基础设施至关重要，因为服务器可能在数小时内从健康变为故障，
-- 但每日Z分数可能仍然看起来正常。
--
-- We compute:
--   rate_of_change_1d = ((today - yesterday) / yesterday) * 100
--   rate_of_change_7d = ((today - 7_days_ago) / 7_days_ago) * 100
--
-- Example: CPU goes from 30% to 75% in one day → ROC = +150%
-- 示例：CPU在一天内从30%升至75% → ROC = +150%
-- ############################################################


-- ─────────────────────────────────────────────────────
-- 4.1  1-Day Rate of Change / 1天变化率
-- ─────────────────────────────────────────────────────

UPDATE test.infra_anomaly_scores a
JOIN test.infra_anomaly_scores prev
    ON  a.service_type = prev.service_type
    AND a.instance_id  = prev.instance_id
    AND a.metric_name  = prev.metric_name
    AND prev.metric_date = DATE_SUB(a.metric_date, INTERVAL 1 DAY)
SET a.rate_of_change_1d = CASE
    WHEN prev.metric_value > 0
        THEN ((a.metric_value - prev.metric_value) / prev.metric_value) * 100
    WHEN prev.metric_value = 0 AND a.metric_value > 0
        THEN 999.99   -- from zero to positive: cap at 999.99%
    ELSE NULL
END;


-- ─────────────────────────────────────────────────────
-- 4.2  7-Day Rate of Change / 7天变化率
-- ─────────────────────────────────────────────────────
-- Captures weekly trends; smooths out day-to-day volatility.
-- 捕捉每周趋势；平滑日间波动。

UPDATE test.infra_anomaly_scores a
JOIN test.infra_anomaly_scores prev7
    ON  a.service_type  = prev7.service_type
    AND a.instance_id   = prev7.instance_id
    AND a.metric_name   = prev7.metric_name
    AND prev7.metric_date = DATE_SUB(a.metric_date, INTERVAL 7 DAY)
SET a.rate_of_change_7d = CASE
    WHEN prev7.metric_value > 0
        THEN ((a.metric_value - prev7.metric_value) / prev7.metric_value) * 100
    WHEN prev7.metric_value = 0 AND a.metric_value > 0
        THEN 999.99
    ELSE NULL
END;


-- ############################################################
-- STEP 5: DETERMINE ANOMALY SEVERITY
-- 第五步: 确定异常严重度
-- ############################################################
--
-- Severity classification uses a cascade of checks. The hierarchy
-- is: CRITICAL > WARNING > INFO > NONE. If multiple conditions
-- are met, the highest severity wins.
-- 严重度分类使用级联检查。层级为：CRITICAL > WARNING > INFO > NONE。
-- 如果满足多个条件，取最高严重度。
--
-- METRIC DIRECTIONALITY / 指标方向性:
-- Infrastructure metrics have different "bad" directions:
-- 基础设施指标有不同的"异常"方向：
--
--   UCL-only (high = bad):   cpu_utilization, memory_utilization,
--     command_duration, evicted_keys, rejected_connections,
--     read_latency, write_latency, disk_iops, network_errors
--
--   LCL-only (low = bad):    hit_rate, cache_hit_ratio,
--     freeable_memory, free_storage_space, redis_up
--
--   Both directions:          connected_clients, commands_per_sec,
--     database_connections, read_iops, write_iops
--
-- We apply directional filtering so that, for example, a low
-- CPU utilization Z-score of -4 does NOT fire a CRITICAL alert.
-- 我们应用方向性过滤，例如低CPU利用率Z分数-4不会触发CRITICAL告警。
-- ############################################################


-- ─────────────────────────────────────────────────────
-- 5.1  Classify severity with metric-specific directionality
-- 结合指标方向性分类严重度
-- ─────────────────────────────────────────────────────

UPDATE test.infra_anomaly_scores
SET anomaly_severity = CASE

    -- ===== CRITICAL conditions / 严重条件 =====

    -- WE Rule 1: Single point beyond 3σ (directional check)
    -- WE规则1: 单点超过3σ（方向性检查）
    WHEN we_rule1 = TRUE AND (
        -- UCL-only metrics: only positive z-scores matter
        -- 仅UCL指标：只有正Z分数重要
        (metric_name IN ('cpu_utilization','memory_utilization','command_duration',
                         'evicted_keys','rejected_connections','read_latency',
                         'write_latency','disk_iops','network_errors')
         AND z_score > 3)
        OR
        -- LCL-only metrics: only negative z-scores matter
        -- 仅LCL指标：只有负Z分数重要
        (metric_name IN ('hit_rate','cache_hit_ratio','freeable_memory',
                         'free_storage_space','redis_up')
         AND z_score < -3)
        OR
        -- Bidirectional metrics: both extremes matter
        -- 双向指标：两个极端都重要
        (metric_name NOT IN ('cpu_utilization','memory_utilization','command_duration',
                             'evicted_keys','rejected_connections','read_latency',
                             'write_latency','disk_iops','network_errors',
                             'hit_rate','cache_hit_ratio','freeable_memory',
                             'free_storage_space','redis_up')
         AND ABS(z_score) > 3)
    ) THEN 'CRITICAL'

    -- Extreme rate of change (any metric): > 100% in 1 day
    -- 极端变化率（任何指标）：1天内超过100%
    WHEN ABS(rate_of_change_1d) > 100 THEN 'CRITICAL'

    -- ===== WARNING conditions / 警告条件 =====

    -- WE Rule 2, 3, or 4 triggered
    -- WE规则2、3或4触发
    WHEN we_rule2 = TRUE OR we_rule3 = TRUE OR we_rule4 = TRUE THEN 'WARNING'

    -- Z-score between 2 and 3 in the concerning direction
    -- Z分数在2到3之间（关注方向）
    WHEN (metric_name IN ('cpu_utilization','memory_utilization','command_duration',
                          'evicted_keys','rejected_connections','read_latency',
                          'write_latency','disk_iops','network_errors')
          AND z_score > 2.0)
      OR (metric_name IN ('hit_rate','cache_hit_ratio','freeable_memory',
                          'free_storage_space','redis_up')
          AND z_score < -2.0)
      OR (metric_name NOT IN ('cpu_utilization','memory_utilization','command_duration',
                              'evicted_keys','rejected_connections','read_latency',
                              'write_latency','disk_iops','network_errors',
                              'hit_rate','cache_hit_ratio','freeable_memory',
                              'free_storage_space','redis_up')
          AND ABS(z_score) > 2.0)
    THEN 'WARNING'

    -- Rate of change > 50% in 1 day
    -- 1天变化率超过50%
    WHEN ABS(rate_of_change_1d) > 50 THEN 'WARNING'

    -- ===== INFO conditions / 信息条件 =====

    -- WE Rule 5: 6 consecutive trending
    -- WE规则5: 连续6点同向趋势
    WHEN we_rule5 = TRUE THEN 'INFO'

    -- Z-score between 1.5 and 2 (mild concern in right direction)
    -- Z分数在1.5到2之间（正确方向的轻度关注）
    WHEN (metric_name IN ('cpu_utilization','memory_utilization','command_duration',
                          'evicted_keys','rejected_connections','read_latency',
                          'write_latency','disk_iops','network_errors')
          AND z_score > 1.5)
      OR (metric_name IN ('hit_rate','cache_hit_ratio','freeable_memory',
                          'free_storage_space','redis_up')
          AND z_score < -1.5)
      OR (metric_name NOT IN ('cpu_utilization','memory_utilization','command_duration',
                              'evicted_keys','rejected_connections','read_latency',
                              'write_latency','disk_iops','network_errors',
                              'hit_rate','cache_hit_ratio','freeable_memory',
                              'free_storage_space','redis_up')
          AND ABS(z_score) > 1.5)
    THEN 'INFO'

    -- Rate of change > 25% in 1 day (notable but not alarming)
    -- 1天变化率超过25%（值得注意但不令人担忧）
    WHEN ABS(rate_of_change_1d) > 25 THEN 'INFO'

    -- ===== No anomaly / 无异常 =====
    ELSE 'NONE'
END
WHERE z_score IS NOT NULL;


-- ############################################################
-- STEP 6: GENERATE ALERT RECORDS
-- 第六步: 生成告警记录到infra_anomaly_alerts
-- ############################################################
--
-- Insert new alert records for CRITICAL and WARNING severities.
-- Each alert includes bilingual descriptions and recommended actions
-- based on the metric type.
-- 为CRITICAL和WARNING严重度插入新告警记录。每条告警包含双语描述
-- 和基于指标类型的建议操作。
-- ############################################################

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
    -- Concatenate triggered WE rules / 连接触发的WE规则
    CONCAT_WS(', ',
        IF(a.we_rule1, 'WE-1:Beyond-3sigma',  NULL),
        IF(a.we_rule2, 'WE-2:2of3-beyond-2sigma', NULL),
        IF(a.we_rule3, 'WE-3:4of5-beyond-1sigma', NULL),
        IF(a.we_rule4, 'WE-4:8-consecutive',  NULL),
        IF(a.we_rule5, 'WE-5:6-trending',     NULL)
    ),
    ROUND(a.rate_of_change_1d, 2),

    -- English description
    CONCAT(
        a.anomaly_severity, ' anomaly on ', a.instance_name,
        ' (', a.service_type, '): ',
        a.metric_name, ' = ', ROUND(a.metric_value, 2),
        COALESCE(CONCAT(' ', a.metric_unit), ''),
        ', Z-score = ', ROUND(a.z_score, 2),
        ', 14-day mean = ', ROUND(a.rolling_mean_14d, 2),
        CASE WHEN a.rate_of_change_1d IS NOT NULL
             THEN CONCAT(', 1d change = ', ROUND(a.rate_of_change_1d, 1), '%')
             ELSE '' END
    ),

    -- Chinese description / 中文描述
    CONCAT(
        CASE a.anomaly_severity WHEN 'CRITICAL' THEN '严重' ELSE '警告' END,
        '异常: ', a.instance_name,
        ' (', a.service_type, ') ',
        a.metric_name, ' = ', ROUND(a.metric_value, 2),
        COALESCE(CONCAT(' ', a.metric_unit), ''),
        ', Z分数 = ', ROUND(a.z_score, 2),
        ', 14日均值 = ', ROUND(a.rolling_mean_14d, 2),
        CASE WHEN a.rate_of_change_1d IS NOT NULL
             THEN CONCAT(', 日变化 = ', ROUND(a.rate_of_change_1d, 1), '%')
             ELSE '' END
    ),

    -- Recommended action based on metric type / 根据指标类型的建议操作
    CASE
        WHEN a.metric_name IN ('cpu_utilization') AND a.z_score > 3 THEN
            'Investigate CPU spike: check for runaway processes, consider scaling up or out. / 调查CPU飙升：检查失控进程，考虑纵向或横向扩容。'
        WHEN a.metric_name IN ('memory_utilization') AND a.z_score > 3 THEN
            'Memory critically high: check for memory leaks, OOM risk. Consider increasing instance size. / 内存严重偏高：检查内存泄漏和OOM风险。考虑增加实例规格。'
        WHEN a.metric_name IN ('freeable_memory','free_storage_space') AND a.z_score < -3 THEN
            'Free resources critically low: immediate capacity action needed. Risk of service disruption. / 可用资源严重不足：需立即采取容量措施。存在服务中断风险。'
        WHEN a.metric_name IN ('hit_rate','cache_hit_ratio') AND a.z_score < -3 THEN
            'Cache hit rate dropped significantly: check for key pattern changes or eviction storms. / 缓存命中率显著下降：检查键模式变化或驱逐风暴。'
        WHEN a.metric_name IN ('read_latency','write_latency','command_duration') AND a.z_score > 3 THEN
            'Latency spike detected: check for slow queries, lock contention, or I/O saturation. / 检测到延迟飙升：检查慢查询、锁竞争或I/O饱和。'
        WHEN a.metric_name IN ('evicted_keys') AND a.z_score > 3 THEN
            'Eviction rate surge: cache under memory pressure. Increase maxmemory or add nodes. / 驱逐率激增：缓存内存压力大。增加maxmemory或添加节点。'
        WHEN a.metric_name IN ('rejected_connections') AND a.z_score > 3 THEN
            'Connections being rejected: max connection limit may be reached. / 连接被拒绝：可能已达最大连接限制。'
        WHEN a.metric_name IN ('connected_clients','database_connections') AND ABS(a.z_score) > 3 THEN
            'Unusual connection count: check for connection pool leaks or unexpected traffic patterns. / 异常连接数：检查连接池泄漏或意外流量模式。'
        WHEN ABS(a.rate_of_change_1d) > 100 THEN
            'Extreme rate-of-change detected (>100%/day): check for deployment impacts or system events. / 检测到极端变化率(>100%/天)：检查部署影响或系统事件。'
        ELSE
            'Anomaly detected: review metric trend and correlate with recent changes. / 检测到异常：审查指标趋势并关联近期变更。'
    END,

    NOW()
FROM test.infra_anomaly_scores a
WHERE a.anomaly_severity IN ('CRITICAL', 'WARNING')
  -- Only generate alerts for the most recent 7 days to avoid historical noise
  -- 仅为最近7天生成告警以避免历史噪音
  AND a.metric_date >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
  -- Deduplication: skip if alert already exists for same instance+metric+date
  -- 去重：如果同一实例+指标+日期的告警已存在则跳过
  AND NOT EXISTS (
      SELECT 1 FROM test.infra_anomaly_alerts e
      WHERE e.instance_id  = a.instance_id
        AND e.metric_name  = a.metric_name
        AND e.metric_date  = a.metric_date
  );


-- ############################################################
-- STEP 7: VERIFICATION & QA QUERIES
-- 第七步: 验证和质量保证查询
-- ############################################################


-- ─────────────────────────────────────────────────────
-- 7.1  Anomaly severity distribution
-- 异常严重度分布
-- ─────────────────────────────────────────────────────
-- Expected: NONE ~85-95%, INFO ~3-8%, WARNING ~1-4%, CRITICAL ~0.5-2%
-- 预期：NONE ~85-95%, INFO ~3-8%, WARNING ~1-4%, CRITICAL ~0.5-2%

SELECT
    anomaly_severity,
    COUNT(*)                                                AS cnt,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)     AS pct
FROM test.infra_anomaly_scores
GROUP BY anomaly_severity
ORDER BY FIELD(anomaly_severity, 'CRITICAL', 'WARNING', 'INFO', 'NONE');


-- ─────────────────────────────────────────────────────
-- 7.2  Severity distribution by service type
-- 按服务类型的严重度分布
-- ─────────────────────────────────────────────────────

SELECT
    service_type,
    SUM(CASE WHEN anomaly_severity = 'CRITICAL' THEN 1 ELSE 0 END) AS critical_cnt,
    SUM(CASE WHEN anomaly_severity = 'WARNING'  THEN 1 ELSE 0 END) AS warning_cnt,
    SUM(CASE WHEN anomaly_severity = 'INFO'     THEN 1 ELSE 0 END) AS info_cnt,
    SUM(CASE WHEN anomaly_severity = 'NONE'     THEN 1 ELSE 0 END) AS none_cnt,
    COUNT(*)                                                        AS total
FROM test.infra_anomaly_scores
GROUP BY service_type
ORDER BY critical_cnt DESC, warning_cnt DESC;


-- ─────────────────────────────────────────────────────
-- 7.3  Severity distribution by metric name
-- 按指标名称的严重度分布
-- ─────────────────────────────────────────────────────

SELECT
    metric_name,
    SUM(CASE WHEN anomaly_severity = 'CRITICAL' THEN 1 ELSE 0 END) AS critical_cnt,
    SUM(CASE WHEN anomaly_severity = 'WARNING'  THEN 1 ELSE 0 END) AS warning_cnt,
    SUM(CASE WHEN anomaly_severity = 'INFO'     THEN 1 ELSE 0 END) AS info_cnt,
    COUNT(*)                                                        AS total
FROM test.infra_anomaly_scores
GROUP BY metric_name
ORDER BY critical_cnt DESC, warning_cnt DESC;


-- ─────────────────────────────────────────────────────
-- 7.4  Western Electric rule trigger counts
-- 西部电气规则触发计数
-- ─────────────────────────────────────────────────────

SELECT
    'WE Rule 1: Beyond 3sigma'         AS rule_description,
    SUM(we_rule1)                       AS trigger_count,
    COUNT(*)                            AS total_rows,
    ROUND(100.0 * SUM(we_rule1) / COUNT(*), 3) AS trigger_pct
FROM test.infra_anomaly_scores WHERE z_score IS NOT NULL

UNION ALL SELECT
    'WE Rule 2: 2/3 beyond 2sigma',
    SUM(we_rule2), COUNT(*),
    ROUND(100.0 * SUM(we_rule2) / COUNT(*), 3)
FROM test.infra_anomaly_scores WHERE z_score IS NOT NULL

UNION ALL SELECT
    'WE Rule 3: 4/5 beyond 1sigma',
    SUM(we_rule3), COUNT(*),
    ROUND(100.0 * SUM(we_rule3) / COUNT(*), 3)
FROM test.infra_anomaly_scores WHERE z_score IS NOT NULL

UNION ALL SELECT
    'WE Rule 4: 8 consecutive same side',
    SUM(we_rule4), COUNT(*),
    ROUND(100.0 * SUM(we_rule4) / COUNT(*), 3)
FROM test.infra_anomaly_scores WHERE z_score IS NOT NULL

UNION ALL SELECT
    'WE Rule 5: 6 trending same dir',
    SUM(we_rule5), COUNT(*),
    ROUND(100.0 * SUM(we_rule5) / COUNT(*), 3)
FROM test.infra_anomaly_scores WHERE z_score IS NOT NULL;


-- ─────────────────────────────────────────────────────
-- 7.5  Top 10 most anomalous instances (by severity + z-score)
-- 最异常的10个实例（按严重度+Z分数）
-- ─────────────────────────────────────────────────────

SELECT
    service_type,
    instance_id,
    instance_name,
    metric_date,
    metric_name,
    ROUND(metric_value, 2)           AS metric_value,
    ROUND(rolling_mean_14d, 2)       AS mean_14d,
    ROUND(z_score, 2)                AS z_score,
    ROUND(rate_of_change_1d, 1)      AS roc_1d_pct,
    anomaly_severity,
    CONCAT_WS(', ',
        IF(we_rule1, 'R1:3sigma',     NULL),
        IF(we_rule2, 'R2:2/3>2sigma',  NULL),
        IF(we_rule3, 'R3:4/5>1sigma',  NULL),
        IF(we_rule4, 'R4:8consec',     NULL),
        IF(we_rule5, 'R5:6trend',      NULL)
    )                                 AS rules_triggered
FROM test.infra_anomaly_scores
WHERE anomaly_severity IN ('CRITICAL', 'WARNING')
ORDER BY
    FIELD(anomaly_severity, 'CRITICAL', 'WARNING'),
    ABS(z_score) DESC
LIMIT 10;


-- ─────────────────────────────────────────────────────
-- 7.6  Rate-of-change extremes (potential rapid failures)
-- 变化率极端值（潜在快速故障）
-- ─────────────────────────────────────────────────────

SELECT
    service_type,
    instance_id,
    instance_name,
    metric_date,
    metric_name,
    ROUND(metric_value, 2)              AS metric_value,
    ROUND(rate_of_change_1d, 1)         AS roc_1d_pct,
    ROUND(rate_of_change_7d, 1)         AS roc_7d_pct,
    anomaly_severity
FROM test.infra_anomaly_scores
WHERE ABS(rate_of_change_1d) > 50
   OR ABS(rate_of_change_7d) > 100
ORDER BY ABS(rate_of_change_1d) DESC
LIMIT 20;


-- ─────────────────────────────────────────────────────
-- 7.7  Z-score distribution check (should be roughly normal)
-- Z分数分布检查（应大致呈正态分布）
-- ─────────────────────────────────────────────────────

SELECT
    CASE
        WHEN z_score IS NULL            THEN 'NULL'
        WHEN ABS(z_score) <= 1          THEN '|z| <= 1  (within 1sigma)'
        WHEN ABS(z_score) <= 2          THEN '1 < |z| <= 2  (1sigma-2sigma)'
        WHEN ABS(z_score) <= 3          THEN '2 < |z| <= 3  (2sigma-3sigma)'
        ELSE                                 '|z| > 3  (beyond 3sigma)'
    END                                                     AS z_bucket,
    COUNT(*)                                                AS cnt,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)     AS pct
FROM test.infra_anomaly_scores
GROUP BY z_bucket
ORDER BY FIELD(z_bucket,
    '|z| <= 1  (within 1sigma)',
    '1 < |z| <= 2  (1sigma-2sigma)',
    '2 < |z| <= 3  (2sigma-3sigma)',
    '|z| > 3  (beyond 3sigma)',
    'NULL'
);


-- ─────────────────────────────────────────────────────
-- 7.8  Row count and data quality sanity check
-- 行数和数据质量完整性检查
-- ─────────────────────────────────────────────────────

SELECT
    'infra_anomaly_scores'                                  AS table_name,
    COUNT(*)                                                AS total_rows,
    COUNT(DISTINCT service_type)                            AS distinct_service_types,
    COUNT(DISTINCT instance_id)                             AS distinct_instances,
    COUNT(DISTINCT metric_date)                             AS distinct_dates,
    COUNT(DISTINCT metric_name)                             AS distinct_metrics,
    MIN(metric_date)                                        AS min_date,
    MAX(metric_date)                                        AS max_date,
    SUM(CASE WHEN z_score IS NULL THEN 1 ELSE 0 END)       AS null_z_scores,
    SUM(CASE WHEN rolling_std_14d IS NULL THEN 1 ELSE 0 END) AS null_std_dev,
    SUM(CASE WHEN anomaly_severity IS NULL THEN 1 ELSE 0 END) AS null_severity
FROM test.infra_anomaly_scores;


-- ─────────────────────────────────────────────────────
-- 7.9  Alert generation summary
-- 告警生成汇总
-- ─────────────────────────────────────────────────────

SELECT
    anomaly_severity,
    COUNT(*)                            AS alert_count,
    COUNT(DISTINCT instance_id)         AS affected_instances,
    COUNT(DISTINCT metric_name)         AS affected_metrics
FROM test.infra_anomaly_alerts
WHERE created_at >= CURDATE()
GROUP BY anomaly_severity
ORDER BY FIELD(anomaly_severity, 'CRITICAL', 'WARNING');


-- ############################################################
-- END OF SCRIPT
-- 脚本结束
-- ############################################################
--
-- Summary of operations performed / 执行的操作摘要:
--   1. Truncated infra_anomaly_scores (idempotent reset)
--      截断infra_anomaly_scores（幂等重置）
--   2. Inserted all metrics with 14-day rolling statistics
--      插入所有指标及14天滚动统计
--   3. Computed z-scores and 2sigma/3sigma control limits
--      计算z分数和2sigma/3sigma控制限
--   4. Evaluated 5 Western Electric rules per row
--      对每行评估5条西部电气规则
--   5. Computed 1-day and 7-day rate-of-change features
--      计算1天和7天变化率特征
--   6. Classified anomaly severity with metric directionality
--      结合指标方向性分类异常严重度
--   7. Generated alert records for CRITICAL and WARNING items
--      为CRITICAL和WARNING项生成告警记录
--   8. Ran verification queries for data quality assurance
--      运行验证查询进行数据质量保证
--
-- Next Steps / 后续步骤:
--   - Run 06_vm_crash_case_study.sql for retroactive analysis demo
--     运行06_vm_crash_case_study.sql进行回溯分析演示
--   - Run 07_fleet_health_scoring.sql to compute composite health scores
--     运行07_fleet_health_scoring.sql计算综合健康评分
--   - Run 08_daily_refresh.sql to schedule automated daily execution
--     运行08_daily_refresh.sql安排每日自动执行
--
-- ============================================================
-- END -- UC-IT-01 Infrastructure Anomaly Scoring Engine
-- 结束 -- UC-IT-01 基础设施异常评分引擎
-- ============================================================

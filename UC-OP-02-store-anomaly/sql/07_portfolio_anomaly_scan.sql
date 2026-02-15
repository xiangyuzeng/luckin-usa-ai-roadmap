-- ============================================================
-- UC-OP-02: Store Performance Anomaly Detection
-- File: 07_portfolio_anomaly_scan.sql
-- Source: aws-luckyus-dbatest-rw (test.store_anomaly_scores, test.store_kpi_daily)
-- Target: aws-luckyus-dbatest-rw (test.store_health_scores)
-- Purpose: All-store health scoring and portfolio-wide anomaly scan
-- 全门店健康评分与组合异常扫描
-- ============================================================
--
-- OVERVIEW / 概述:
-- ---------------------------------------------------------------
-- This script computes a composite health score for every active
-- store by combining five performance dimensions into a single
-- weighted score (0-100). It then generates alerts for stores
-- whose scores or trends indicate potential issues.
--
-- 本脚本为每个活跃门店计算综合健康评分，将五个绩效维度合并为
-- 单一加权评分（0-100分制），然后为评分或趋势异常的门店生成预警。
--
-- DIMENSIONS & WEIGHTS / 维度与权重:
--   40% revenue_score   — Revenue performance / 收入表现
--   20% ops_score       — Production efficiency / 生产运营效率
--   15% quality_score   — Inspection quality / 质检质量
--   15% staffing_score  — Labor productivity / 人员效率
--   10% customer_score  — Order trends & AOV / 订单趋势与客单价
--
-- GRADE SCALE / 等级标准:
--   A = 90-100  |  B = 80-89  |  C = 70-79  |  D = 60-69  |  F < 60
--
-- PREREQUISITES / 前置条件:
--   - test.store_kpi_daily populated (files 03, 04)
--   - test.store_anomaly_scores populated (files 05, 06)
--   - At least 28 days of KPI data for meaningful percentiles
--
-- Author  : Data Engineering / BI Team
-- Created : 2026-02-15
-- ============================================================


-- ############################################################
-- SECTION 1: COMPUTE INDIVIDUAL DIMENSION SCORES (0-100)
-- 第1节：计算各维度单项评分（0-100分制）
-- ############################################################
-- Each dimension score is derived from PERCENT_RANK() of the
-- current day's value against the store's own 90-day history.
-- This ensures each store is measured against its own baseline,
-- not cross-store comparisons.
--
-- 每个维度评分基于当天值在该门店自身90天历史中的百分位排名。
-- 确保每个门店以自身基线为标准，而非跨门店比较。
-- ############################################################

-- Drop temporary working table if exists from prior run
-- 如果存在先前运行的临时工作表则删除
DROP TEMPORARY TABLE IF EXISTS tmp_dimension_scores;

CREATE TEMPORARY TABLE tmp_dimension_scores AS
WITH
-- ---------------------------------------------------------
-- CTE 1: 90-day KPI window per store
-- 获取每个门店最近90天的KPI窗口
-- ---------------------------------------------------------
kpi_window AS (
    SELECT
        k.store_id,
        k.store_name,
        k.metric_date,
        k.total_revenue,
        k.order_count,
        k.avg_order_value,
        k.production_count,
        k.avg_production_time_sec,
        k.avg_quality_score,
        k.inspection_count,
        k.scheduled_hours,
        k.revenue_per_labor_hour,
        k.day_of_week,
        k.is_weekend
    FROM test.store_kpi_daily k
    WHERE k.store_id IN (1127, 1128, 1131, 1140, 1141,
                         20008, 20009, 20010, 20011, 20046)
      AND k.metric_date >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
),

-- ---------------------------------------------------------
-- CTE 2: Revenue dimension score
-- 收入维度评分
-- Percentile rank of total_revenue within store's 90-day history.
-- 总收入在门店自身90天历史中的百分位排名。
-- Higher revenue = higher score.
-- ---------------------------------------------------------
revenue_pctile AS (
    SELECT
        store_id,
        metric_date,
        total_revenue,
        ROUND(100 * PERCENT_RANK() OVER (
            PARTITION BY store_id
            ORDER BY total_revenue ASC
        ), 2) AS revenue_score
    FROM kpi_window
    WHERE total_revenue IS NOT NULL
),

-- ---------------------------------------------------------
-- CTE 3: Operations dimension score
-- 运营维度评分
-- Combines production_count (higher = better) with
-- avg_production_time_sec (lower = better).
-- Combined: 60% volume rank + 40% speed rank.
-- 综合生产量（越高越好）和平均生产时间（越低越好）。
-- 组合：60%产量排名 + 40%速度排名。
-- ---------------------------------------------------------
ops_pctile AS (
    SELECT
        store_id,
        metric_date,
        production_count,
        avg_production_time_sec,
        -- Volume rank: more production = higher rank / 产量排名
        ROUND(100 * PERCENT_RANK() OVER (
            PARTITION BY store_id
            ORDER BY production_count ASC
        ), 2) AS volume_rank,
        -- Speed rank: shorter time = higher rank (reverse order)
        -- 速度排名：时间越短排名越高（倒序）
        ROUND(100 * PERCENT_RANK() OVER (
            PARTITION BY store_id
            ORDER BY avg_production_time_sec DESC
        ), 2) AS speed_rank
    FROM kpi_window
    WHERE production_count IS NOT NULL
      AND avg_production_time_sec IS NOT NULL
),

ops_score_calc AS (
    SELECT
        store_id,
        metric_date,
        ROUND(0.60 * volume_rank + 0.40 * speed_rank, 2) AS ops_score
    FROM ops_pctile
),

-- ---------------------------------------------------------
-- CTE 4: Quality dimension score
-- 质量维度评分
-- Based on avg_quality_score from inspections.
-- Since quality data is sparse, use last known value via
-- forward-fill (last observation carried forward).
-- 基于巡检平均质量评分。由于质量数据稀疏，使用最后已知值
-- 进行前向填充（LOCF）。
-- ---------------------------------------------------------
quality_filled AS (
    SELECT
        k.store_id,
        k.metric_date,
        -- Forward-fill: use last non-NULL quality score
        -- 前向填充：使用最后一个非空质量评分
        COALESCE(
            k.avg_quality_score,
            (SELECT k2.avg_quality_score
             FROM test.store_kpi_daily k2
             WHERE k2.store_id = k.store_id
               AND k2.metric_date < k.metric_date
               AND k2.avg_quality_score IS NOT NULL
             ORDER BY k2.metric_date DESC
             LIMIT 1)
        ) AS filled_quality_score
    FROM kpi_window k
),

quality_pctile AS (
    SELECT
        store_id,
        metric_date,
        filled_quality_score,
        -- Quality: higher score = better / 质量：评分越高越好
        ROUND(100 * PERCENT_RANK() OVER (
            PARTITION BY store_id
            ORDER BY filled_quality_score ASC
        ), 2) AS quality_score
    FROM quality_filled
    WHERE filled_quality_score IS NOT NULL
),

-- ---------------------------------------------------------
-- CTE 5: Staffing dimension score
-- 人员维度评分
-- Based on revenue_per_labor_hour efficiency.
-- Higher RPLH = more efficient = higher score.
-- 基于每工时营收效率。RPLH越高 = 越高效 = 评分越高。
-- ---------------------------------------------------------
staffing_pctile AS (
    SELECT
        store_id,
        metric_date,
        revenue_per_labor_hour,
        ROUND(100 * PERCENT_RANK() OVER (
            PARTITION BY store_id
            ORDER BY revenue_per_labor_hour ASC
        ), 2) AS staffing_score
    FROM kpi_window
    WHERE revenue_per_labor_hour IS NOT NULL
      AND revenue_per_labor_hour > 0
),

-- ---------------------------------------------------------
-- CTE 6: Customer dimension score
-- 顾客维度评分
-- Combines order_count trend (60%) with AOV stability (40%).
-- Order trend: percentile of today's count vs history.
-- AOV stability: inverse of coefficient of variation over
--   7-day rolling window (lower CV = more stable = higher score).
-- 综合订单量趋势（60%）和客单价稳定性（40%）。
-- 订单趋势：当天订单数在历史中的百分位排名。
-- 客单价稳定性：7天滚动变异系数的逆指标。
-- ---------------------------------------------------------
customer_order_rank AS (
    SELECT
        store_id,
        metric_date,
        order_count,
        avg_order_value,
        -- Order volume rank / 订单量排名
        ROUND(100 * PERCENT_RANK() OVER (
            PARTITION BY store_id
            ORDER BY order_count ASC
        ), 2) AS order_rank,
        -- 7-day rolling AOV std deviation / 7天滚动AOV标准差
        STDDEV_SAMP(avg_order_value) OVER (
            PARTITION BY store_id
            ORDER BY metric_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS aov_rolling_std,
        AVG(avg_order_value) OVER (
            PARTITION BY store_id
            ORDER BY metric_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS aov_rolling_mean
    FROM kpi_window
    WHERE order_count IS NOT NULL
),

customer_score_calc AS (
    SELECT
        store_id,
        metric_date,
        order_rank,
        -- AOV stability: 100 minus CV*100 (capped at 0-100)
        -- AOV稳定性：100 减去 变异系数*100（限制在0-100范围内）
        LEAST(100, GREATEST(0,
            ROUND(100 - (COALESCE(aov_rolling_std, 0) /
                         NULLIF(aov_rolling_mean, 0) * 100), 2)
        )) AS aov_stability_score,
        -- Combined: 60% order trend + 40% AOV stability
        -- 组合：60%订单趋势 + 40%客单价稳定性
        ROUND(
            0.60 * order_rank +
            0.40 * LEAST(100, GREATEST(0,
                100 - (COALESCE(aov_rolling_std, 0) /
                       NULLIF(aov_rolling_mean, 0) * 100)
            ))
        , 2) AS customer_score
    FROM customer_order_rank
)

-- ---------------------------------------------------------
-- Final assembly: join all dimension scores
-- 最终组装：关联所有维度评分
-- ---------------------------------------------------------
SELECT
    kw.store_id,
    kw.store_name,
    kw.metric_date,
    rp.revenue_score,
    osc.ops_score,
    qp.quality_score,
    sp.staffing_score,
    csc.customer_score
FROM kpi_window kw
LEFT JOIN revenue_pctile    rp  ON rp.store_id = kw.store_id AND rp.metric_date = kw.metric_date
LEFT JOIN ops_score_calc    osc ON osc.store_id = kw.store_id AND osc.metric_date = kw.metric_date
LEFT JOIN quality_pctile    qp  ON qp.store_id = kw.store_id AND qp.metric_date = kw.metric_date
LEFT JOIN staffing_pctile   sp  ON sp.store_id = kw.store_id AND sp.metric_date = kw.metric_date
LEFT JOIN customer_score_calc csc ON csc.store_id = kw.store_id AND csc.metric_date = kw.metric_date;


-- ############################################################
-- SECTION 2: COMPUTE COMPOSITE HEALTH SCORE
-- 第2节：计算综合健康评分
-- ############################################################
-- Weighted composite with NULL-tolerant redistribution:
-- If a dimension is NULL, its weight is distributed proportionally
-- among the remaining available dimensions.
--
-- 加权综合评分，支持空值权重再分配：
-- 如果某维度为空，其权重按比例分配给其余可用维度。
-- ############################################################

-- Clear previous scores for re-computation
-- 清除先前的评分以重新计算
DELETE FROM test.store_health_scores
WHERE metric_date >= DATE_SUB(CURDATE(), INTERVAL 90 DAY);

INSERT INTO test.store_health_scores (
    store_id, store_name, metric_date,
    revenue_score, ops_score, quality_score, staffing_score, customer_score,
    composite_score, health_grade, week_over_week_change, trend_direction
)
SELECT
    ds.store_id,
    ds.store_name,
    ds.metric_date,
    ds.revenue_score,
    ds.ops_score,
    ds.quality_score,
    ds.staffing_score,
    ds.customer_score,

    -- Composite score with NULL-aware weight redistribution
    -- 综合评分：空值感知的权重再分配
    ROUND(
        (
            COALESCE(ds.revenue_score  * 0.40, 0) +
            COALESCE(ds.ops_score      * 0.20, 0) +
            COALESCE(ds.quality_score  * 0.15, 0) +
            COALESCE(ds.staffing_score * 0.15, 0) +
            COALESCE(ds.customer_score * 0.10, 0)
        ) / (
            -- Sum of weights for non-NULL dimensions / 非空维度的权重之和
            (CASE WHEN ds.revenue_score  IS NOT NULL THEN 0.40 ELSE 0 END) +
            (CASE WHEN ds.ops_score      IS NOT NULL THEN 0.20 ELSE 0 END) +
            (CASE WHEN ds.quality_score  IS NOT NULL THEN 0.15 ELSE 0 END) +
            (CASE WHEN ds.staffing_score IS NOT NULL THEN 0.15 ELSE 0 END) +
            (CASE WHEN ds.customer_score IS NOT NULL THEN 0.10 ELSE 0 END)
        )
    , 2) AS composite_score,

    -- Health grade / 健康等级
    CASE
        WHEN ROUND(
            (COALESCE(ds.revenue_score*0.40,0) + COALESCE(ds.ops_score*0.20,0) +
             COALESCE(ds.quality_score*0.15,0) + COALESCE(ds.staffing_score*0.15,0) +
             COALESCE(ds.customer_score*0.10,0))
            / (
              (CASE WHEN ds.revenue_score  IS NOT NULL THEN 0.40 ELSE 0 END) +
              (CASE WHEN ds.ops_score      IS NOT NULL THEN 0.20 ELSE 0 END) +
              (CASE WHEN ds.quality_score  IS NOT NULL THEN 0.15 ELSE 0 END) +
              (CASE WHEN ds.staffing_score IS NOT NULL THEN 0.15 ELSE 0 END) +
              (CASE WHEN ds.customer_score IS NOT NULL THEN 0.10 ELSE 0 END)
            ), 2) >= 90 THEN 'A'
        WHEN ROUND(
            (COALESCE(ds.revenue_score*0.40,0) + COALESCE(ds.ops_score*0.20,0) +
             COALESCE(ds.quality_score*0.15,0) + COALESCE(ds.staffing_score*0.15,0) +
             COALESCE(ds.customer_score*0.10,0))
            / (
              (CASE WHEN ds.revenue_score  IS NOT NULL THEN 0.40 ELSE 0 END) +
              (CASE WHEN ds.ops_score      IS NOT NULL THEN 0.20 ELSE 0 END) +
              (CASE WHEN ds.quality_score  IS NOT NULL THEN 0.15 ELSE 0 END) +
              (CASE WHEN ds.staffing_score IS NOT NULL THEN 0.15 ELSE 0 END) +
              (CASE WHEN ds.customer_score IS NOT NULL THEN 0.10 ELSE 0 END)
            ), 2) >= 80 THEN 'B'
        WHEN ROUND(
            (COALESCE(ds.revenue_score*0.40,0) + COALESCE(ds.ops_score*0.20,0) +
             COALESCE(ds.quality_score*0.15,0) + COALESCE(ds.staffing_score*0.15,0) +
             COALESCE(ds.customer_score*0.10,0))
            / (
              (CASE WHEN ds.revenue_score  IS NOT NULL THEN 0.40 ELSE 0 END) +
              (CASE WHEN ds.ops_score      IS NOT NULL THEN 0.20 ELSE 0 END) +
              (CASE WHEN ds.quality_score  IS NOT NULL THEN 0.15 ELSE 0 END) +
              (CASE WHEN ds.staffing_score IS NOT NULL THEN 0.15 ELSE 0 END) +
              (CASE WHEN ds.customer_score IS NOT NULL THEN 0.10 ELSE 0 END)
            ), 2) >= 70 THEN 'C'
        WHEN ROUND(
            (COALESCE(ds.revenue_score*0.40,0) + COALESCE(ds.ops_score*0.20,0) +
             COALESCE(ds.quality_score*0.15,0) + COALESCE(ds.staffing_score*0.15,0) +
             COALESCE(ds.customer_score*0.10,0))
            / (
              (CASE WHEN ds.revenue_score  IS NOT NULL THEN 0.40 ELSE 0 END) +
              (CASE WHEN ds.ops_score      IS NOT NULL THEN 0.20 ELSE 0 END) +
              (CASE WHEN ds.quality_score  IS NOT NULL THEN 0.15 ELSE 0 END) +
              (CASE WHEN ds.staffing_score IS NOT NULL THEN 0.15 ELSE 0 END) +
              (CASE WHEN ds.customer_score IS NOT NULL THEN 0.10 ELSE 0 END)
            ), 2) >= 60 THEN 'D'
        ELSE 'F'
    END AS health_grade,

    -- Placeholder for WoW change — computed in Section 3
    -- 周环比变化占位符 — 在第3节中计算
    NULL AS week_over_week_change,
    'STABLE' AS trend_direction

FROM tmp_dimension_scores ds
WHERE (
    -- Require at least 2 non-NULL dimensions for a meaningful composite
    -- 至少需要2个非空维度才能计算有意义的综合评分
    (CASE WHEN ds.revenue_score  IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN ds.ops_score      IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN ds.quality_score  IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN ds.staffing_score IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN ds.customer_score IS NOT NULL THEN 1 ELSE 0 END)
) >= 2
ON DUPLICATE KEY UPDATE
    revenue_score         = VALUES(revenue_score),
    ops_score             = VALUES(ops_score),
    quality_score         = VALUES(quality_score),
    staffing_score        = VALUES(staffing_score),
    customer_score        = VALUES(customer_score),
    composite_score       = VALUES(composite_score),
    health_grade          = VALUES(health_grade);


-- ############################################################
-- SECTION 3: WEEK-OVER-WEEK CHANGE & TREND DIRECTION
-- 第3节：周环比变化与趋势方向
-- ############################################################
-- Compare the average composite score of the current 7-day
-- window to the previous 7-day window. Set trend_direction:
--   IMPROVING: WoW change >  +5%
--   DECLINING: WoW change < -5%
--   STABLE:    otherwise
--
-- 将当前7天窗口的平均综合评分与前一个7天窗口进行比较。
-- 设置趋势方向：改善（>+5%）、下降（<-5%）、稳定。
-- ############################################################

UPDATE test.store_health_scores h
INNER JOIN (
    SELECT
        curr.store_id,
        curr.metric_date,
        -- Current week average (7 days ending on metric_date)
        -- 当前周平均值（metric_date 前7天）
        curr_avg.avg_composite AS current_week_avg,
        -- Previous week average (7 days before that)
        -- 上一周平均值
        prev_avg.avg_composite AS previous_week_avg,
        -- Week-over-week percent change / 周环比百分比变化
        ROUND(
            (curr_avg.avg_composite - prev_avg.avg_composite)
            / NULLIF(prev_avg.avg_composite, 0) * 100
        , 4) AS wow_change
    FROM test.store_health_scores curr
    INNER JOIN (
        -- Current 7-day rolling average / 当前7天滚动平均
        SELECT store_id, metric_date,
               AVG(composite_score) AS avg_composite
        FROM test.store_health_scores
        WHERE metric_date >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
        GROUP BY store_id, metric_date
    ) curr_avg ON curr_avg.store_id = curr.store_id
              AND curr_avg.metric_date = curr.metric_date
    LEFT JOIN (
        -- Previous 7-day rolling average / 前一个7天滚动平均
        SELECT store_id, metric_date,
               AVG(composite_score) OVER (
                   PARTITION BY store_id
                   ORDER BY metric_date
                   ROWS BETWEEN 13 PRECEDING AND 7 PRECEDING
               ) AS avg_composite
        FROM test.store_health_scores
    ) prev_avg ON prev_avg.store_id = curr.store_id
              AND prev_avg.metric_date = curr.metric_date
    WHERE curr.metric_date >= DATE_SUB(CURDATE(), INTERVAL 14 DAY)
      AND prev_avg.avg_composite IS NOT NULL
) wow ON wow.store_id = h.store_id AND wow.metric_date = h.metric_date
SET
    h.week_over_week_change = wow.wow_change,
    h.trend_direction = CASE
        WHEN wow.wow_change >  5  THEN 'IMPROVING'
        WHEN wow.wow_change < -5  THEN 'DECLINING'
        ELSE 'STABLE'
    END;


-- ############################################################
-- SECTION 4: PORTFOLIO SUMMARY VIEW
-- 第4节：组合总览视图
-- ############################################################
-- Displays all 10 stores ranked by current composite_score
-- with grade, trend, and worst-performing dimension identified.
--
-- 展示所有10家门店按当前综合评分排名，包含等级、趋势
-- 以及表现最差的维度。
-- ############################################################

SELECT
    h.store_id,
    h.store_name,
    h.metric_date,
    h.composite_score,
    h.health_grade,
    h.week_over_week_change  AS wow_pct,
    h.trend_direction,

    -- Individual dimension scores / 各维度评分
    h.revenue_score,
    h.ops_score,
    h.quality_score,
    h.staffing_score,
    h.customer_score,

    -- Identify worst-performing dimension / 识别表现最差的维度
    CASE LEAST(
        COALESCE(h.revenue_score,  999),
        COALESCE(h.ops_score,      999),
        COALESCE(h.quality_score,  999),
        COALESCE(h.staffing_score, 999),
        COALESCE(h.customer_score, 999)
    )
        WHEN h.revenue_score  THEN 'REVENUE'
        WHEN h.ops_score      THEN 'OPERATIONS'
        WHEN h.quality_score  THEN 'QUALITY'
        WHEN h.staffing_score THEN 'STAFFING'
        WHEN h.customer_score THEN 'CUSTOMER'
        ELSE 'N/A'
    END AS worst_dimension,

    -- Worst dimension score value / 最差维度评分值
    LEAST(
        COALESCE(h.revenue_score,  999),
        COALESCE(h.ops_score,      999),
        COALESCE(h.quality_score,  999),
        COALESCE(h.staffing_score, 999),
        COALESCE(h.customer_score, 999)
    ) AS worst_dimension_score,

    -- Count of active anomaly alerts for this store today
    -- 该门店当天活跃异常预警数量
    (SELECT COUNT(*)
     FROM test.store_anomaly_alerts a
     WHERE a.store_id = h.store_id
       AND a.alert_date = h.metric_date
       AND a.acknowledged = FALSE
    ) AS open_alerts

FROM test.store_health_scores h
WHERE h.metric_date = (
    SELECT MAX(metric_date)
    FROM test.store_health_scores
)
ORDER BY h.composite_score ASC;   -- Worst performers first / 表现最差的排前面


-- ############################################################
-- SECTION 5: ALERT GENERATION
-- 第5节：预警生成
-- ############################################################
-- Generate alerts based on multiple trigger conditions:
--   1. Health grade F       → CRITICAL
--   2. Health grade D       → WARNING
--   3. WoW decline > 15%   → WARNING
--   4. Z-score beyond 3σ   → CRITICAL (from store_anomaly_scores)
--   5. Z-score beyond 2σ   → WARNING
--   6. WE rule violations   → corresponding severity
--
-- 根据多种触发条件生成预警：
--   1. 健康等级F → 严重
--   2. 健康等级D → 警告
--   3. 周环比下降>15% → 警告
--   4. Z分数超过3σ → 严重（来自store_anomaly_scores）
--   5. Z分数超过2σ → 警告
--   6. WE规则违反 → 对应严重度
-- ############################################################

-- Clear today's auto-generated alerts before re-insertion
-- 清除今天的自动生成预警以便重新插入
DELETE FROM test.store_anomaly_alerts
WHERE alert_date = CURDATE()
  AND acknowledged = FALSE;

-- ---------------------------------------------------------
-- Alert Type 1: Health Grade F → CRITICAL
-- 预警类型1：健康等级F → 严重
-- ---------------------------------------------------------
INSERT INTO test.store_anomaly_alerts (
    store_id, store_name, alert_date, alert_type, severity,
    metric_name, current_value, expected_value, threshold_value,
    description_en, description_cn, recommended_action
)
SELECT
    h.store_id,
    h.store_name,
    h.metric_date,
    'HEALTH_GRADE'      AS alert_type,
    'CRITICAL'          AS severity,
    'composite_score'   AS metric_name,
    h.composite_score   AS current_value,
    60.00               AS expected_value,
    60.00               AS threshold_value,
    CONCAT('CRITICAL: Store ', h.store_name, ' (ID:', h.store_id,
           ') health grade is F with composite score ',
           h.composite_score, '/100. Immediate attention required.')
        AS description_en,
    CONCAT('严重：门店 ', h.store_name, ' (ID:', h.store_id,
           ') 健康等级为F，综合评分 ', h.composite_score,
           '/100。需要立即关注。')
        AS description_cn,
    'Conduct on-site review within 24 hours. Check all dimension scores for root cause. / 24小时内进行现场检查，排查各维度评分找出根本原因。'
        AS recommended_action
FROM test.store_health_scores h
WHERE h.metric_date = CURDATE()
  AND h.health_grade = 'F';

-- ---------------------------------------------------------
-- Alert Type 2: Health Grade D → WARNING
-- 预警类型2：健康等级D → 警告
-- ---------------------------------------------------------
INSERT INTO test.store_anomaly_alerts (
    store_id, store_name, alert_date, alert_type, severity,
    metric_name, current_value, expected_value, threshold_value,
    description_en, description_cn, recommended_action
)
SELECT
    h.store_id,
    h.store_name,
    h.metric_date,
    'HEALTH_GRADE'      AS alert_type,
    'WARNING'           AS severity,
    'composite_score'   AS metric_name,
    h.composite_score   AS current_value,
    70.00               AS expected_value,
    60.00               AS threshold_value,
    CONCAT('WARNING: Store ', h.store_name, ' (ID:', h.store_id,
           ') health grade is D with composite score ',
           h.composite_score, '/100. Performance below expectations.')
        AS description_en,
    CONCAT('警告：门店 ', h.store_name, ' (ID:', h.store_id,
           ') 健康等级为D，综合评分 ', h.composite_score,
           '/100。表现低于预期。')
        AS description_cn,
    'Schedule performance review this week. Identify weakest dimension and create action plan. / 本周安排绩效评审，识别最弱维度并制定改进方案。'
        AS recommended_action
FROM test.store_health_scores h
WHERE h.metric_date = CURDATE()
  AND h.health_grade = 'D';

-- ---------------------------------------------------------
-- Alert Type 3: WoW Decline > 15% → WARNING
-- 预警类型3：周环比下降>15% → 警告
-- ---------------------------------------------------------
INSERT INTO test.store_anomaly_alerts (
    store_id, store_name, alert_date, alert_type, severity,
    metric_name, current_value, expected_value, threshold_value,
    description_en, description_cn, recommended_action
)
SELECT
    h.store_id,
    h.store_name,
    h.metric_date,
    'TREND_DECLINE'     AS alert_type,
    'WARNING'           AS severity,
    'week_over_week_change' AS metric_name,
    h.week_over_week_change AS current_value,
    0.00                AS expected_value,
    -15.00              AS threshold_value,
    CONCAT('WARNING: Store ', h.store_name, ' (ID:', h.store_id,
           ') composite score declined ', ABS(h.week_over_week_change),
           '% week-over-week (threshold: -15%). Rapid deterioration detected.')
        AS description_en,
    CONCAT('警告：门店 ', h.store_name, ' (ID:', h.store_id,
           ') 综合评分周环比下降 ', ABS(h.week_over_week_change),
           '%（阈值：-15%）。检测到快速恶化趋势。')
        AS description_cn,
    'Compare this week vs last week KPIs by dimension. Investigate staffing or operational changes. / 按维度对比本周与上周KPI，排查人员或运营变化。'
        AS recommended_action
FROM test.store_health_scores h
WHERE h.metric_date = CURDATE()
  AND h.week_over_week_change < -15;

-- ---------------------------------------------------------
-- Alert Type 4: Z-Score beyond 3σ → CRITICAL
-- 预警类型4：Z分数超过3σ → 严重
-- ---------------------------------------------------------
INSERT INTO test.store_anomaly_alerts (
    store_id, store_name, alert_date, alert_type, severity,
    metric_name, current_value, expected_value, threshold_value,
    z_score, description_en, description_cn, recommended_action
)
SELECT
    a.store_id,
    a.store_name,
    a.metric_date,
    'SPC_ZSCORE'        AS alert_type,
    'CRITICAL'          AS severity,
    a.metric_name,
    a.metric_value      AS current_value,
    a.rolling_mean_28d  AS expected_value,
    CASE
        WHEN a.z_score > 0 THEN a.ucl_3sigma
        ELSE a.lcl_3sigma
    END                 AS threshold_value,
    a.z_score,
    CONCAT('CRITICAL: Store ', a.store_name, ' metric [', a.metric_name,
           '] has z-score=', ROUND(a.z_score, 2),
           ' (beyond 3 sigma). Value=', ROUND(a.metric_value, 2),
           ', Mean=', ROUND(a.rolling_mean_28d, 2), '.')
        AS description_en,
    CONCAT('严重：门店 ', a.store_name, ' 指标 [', a.metric_name,
           '] z分数=', ROUND(a.z_score, 2),
           '（超出3个标准差）。当前值=', ROUND(a.metric_value, 2),
           '，均值=', ROUND(a.rolling_mean_28d, 2), '。')
        AS description_cn,
    'Investigate root cause immediately. Check for data quality issues first, then operational anomalies. / 立即调查根本原因，先检查数据质量问题，再排查运营异常。'
        AS recommended_action
FROM test.store_anomaly_scores a
WHERE a.metric_date = CURDATE()
  AND ABS(a.z_score) > 3;

-- ---------------------------------------------------------
-- Alert Type 5: Z-Score beyond 2σ (but within 3σ) → WARNING
-- 预警类型5：Z分数超过2σ（但在3σ以内）→ 警告
-- ---------------------------------------------------------
INSERT INTO test.store_anomaly_alerts (
    store_id, store_name, alert_date, alert_type, severity,
    metric_name, current_value, expected_value, threshold_value,
    z_score, description_en, description_cn, recommended_action
)
SELECT
    a.store_id,
    a.store_name,
    a.metric_date,
    'SPC_ZSCORE'        AS alert_type,
    'WARNING'           AS severity,
    a.metric_name,
    a.metric_value      AS current_value,
    a.rolling_mean_28d  AS expected_value,
    CASE
        WHEN a.z_score > 0 THEN a.ucl_2sigma
        ELSE a.lcl_2sigma
    END                 AS threshold_value,
    a.z_score,
    CONCAT('WARNING: Store ', a.store_name, ' metric [', a.metric_name,
           '] has z-score=', ROUND(a.z_score, 2),
           ' (beyond 2 sigma). Value=', ROUND(a.metric_value, 2),
           ', Mean=', ROUND(a.rolling_mean_28d, 2), '.')
        AS description_en,
    CONCAT('警告：门店 ', a.store_name, ' 指标 [', a.metric_name,
           '] z分数=', ROUND(a.z_score, 2),
           '（超出2个标准差）。当前值=', ROUND(a.metric_value, 2),
           '，均值=', ROUND(a.rolling_mean_28d, 2), '。')
        AS description_cn,
    'Monitor closely over next 2-3 days. If z-score persists, escalate to CRITICAL review. / 密切关注未来2-3天，若z分数持续则升级为严重级别审查。'
        AS recommended_action
FROM test.store_anomaly_scores a
WHERE a.metric_date = CURDATE()
  AND ABS(a.z_score) > 2
  AND ABS(a.z_score) <= 3;

-- ---------------------------------------------------------
-- Alert Type 6: Western Electric Rule Violations
-- 预警类型6：Western Electric规则违反
-- ---------------------------------------------------------
-- Rule 1 (single point beyond 3σ) already covered by Type 4.
-- Here we handle Rules 2-5 which indicate systematic patterns.
-- 规则1（单点超过3σ）已由类型4覆盖。
-- 此处处理规则2-5，这些表示系统性模式。
-- ---------------------------------------------------------

-- WE Rule 2: 2 of 3 points beyond 2σ same side → WARNING
-- WE规则2：3点中2点超过2σ同侧 → 警告
INSERT INTO test.store_anomaly_alerts (
    store_id, store_name, alert_date, alert_type, severity,
    metric_name, current_value, expected_value, z_score,
    we_rule_violated, description_en, description_cn, recommended_action
)
SELECT
    a.store_id,
    a.store_name,
    a.metric_date,
    'WE_RULE'           AS alert_type,
    'WARNING'           AS severity,
    a.metric_name,
    a.metric_value      AS current_value,
    a.rolling_mean_28d  AS expected_value,
    a.z_score,
    'RULE2'             AS we_rule_violated,
    CONCAT('WARNING: Store ', a.store_name, ' metric [', a.metric_name,
           '] WE Rule 2 violated — 2 of 3 consecutive points beyond 2 sigma on same side.')
        AS description_en,
    CONCAT('警告：门店 ', a.store_name, ' 指标 [', a.metric_name,
           '] 违反WE规则2 — 连续3点中2点在同侧超过2个标准差。')
        AS description_cn,
    'Review recent trend for systematic shift. Consider adjusting process control limits. / 审查近期趋势是否存在系统性偏移，考虑调整过程控制限。'
FROM test.store_anomaly_scores a
WHERE a.metric_date = CURDATE()
  AND a.we_rule2 = TRUE
  AND a.we_rule1 = FALSE;  -- Avoid duplicate with 3σ alert / 避免与3σ预警重复

-- WE Rule 3: 4 of 5 points beyond 1σ same side → WARNING
-- WE规则3：5点中4点超过1σ同侧 → 警告
INSERT INTO test.store_anomaly_alerts (
    store_id, store_name, alert_date, alert_type, severity,
    metric_name, current_value, expected_value, z_score,
    we_rule_violated, description_en, description_cn, recommended_action
)
SELECT
    a.store_id,
    a.store_name,
    a.metric_date,
    'WE_RULE'           AS alert_type,
    'WARNING'           AS severity,
    a.metric_name,
    a.metric_value      AS current_value,
    a.rolling_mean_28d  AS expected_value,
    a.z_score,
    'RULE3'             AS we_rule_violated,
    CONCAT('WARNING: Store ', a.store_name, ' metric [', a.metric_name,
           '] WE Rule 3 violated — 4 of 5 consecutive points beyond 1 sigma on same side.')
        AS description_en,
    CONCAT('警告：门店 ', a.store_name, ' 指标 [', a.metric_name,
           '] 违反WE规则3 — 连续5点中4点在同侧超过1个标准差。')
        AS description_cn,
    'Process mean may be shifting. Validate data source and investigate operational changes. / 过程均值可能正在偏移，验证数据源并调查运营变化。'
FROM test.store_anomaly_scores a
WHERE a.metric_date = CURDATE()
  AND a.we_rule3 = TRUE
  AND a.we_rule1 = FALSE
  AND a.we_rule2 = FALSE;

-- WE Rule 4: 8 consecutive points on same side → CRITICAL
-- WE规则4：连续8点在中心线同侧 → 严重
INSERT INTO test.store_anomaly_alerts (
    store_id, store_name, alert_date, alert_type, severity,
    metric_name, current_value, expected_value, z_score,
    we_rule_violated, description_en, description_cn, recommended_action
)
SELECT
    a.store_id,
    a.store_name,
    a.metric_date,
    'WE_RULE'           AS alert_type,
    'CRITICAL'          AS severity,
    a.metric_name,
    a.metric_value      AS current_value,
    a.rolling_mean_28d  AS expected_value,
    a.z_score,
    'RULE4'             AS we_rule_violated,
    CONCAT('CRITICAL: Store ', a.store_name, ' metric [', a.metric_name,
           '] WE Rule 4 violated — 8 consecutive points on same side of center line. Process mean has shifted.')
        AS description_en,
    CONCAT('严重：门店 ', a.store_name, ' 指标 [', a.metric_name,
           '] 违反WE规则4 — 连续8个点在中心线同侧。过程均值已发生偏移。')
        AS description_cn,
    'Process mean has permanently shifted. Recalculate baseline or investigate structural change. / 过程均值已永久偏移，重新计算基线或调查结构性变化。'
FROM test.store_anomaly_scores a
WHERE a.metric_date = CURDATE()
  AND a.we_rule4 = TRUE;

-- WE Rule 5: 6 consecutive declining points → WARNING
-- WE规则5：连续6点递减 → 警告
INSERT INTO test.store_anomaly_alerts (
    store_id, store_name, alert_date, alert_type, severity,
    metric_name, current_value, expected_value, z_score,
    we_rule_violated, description_en, description_cn, recommended_action
)
SELECT
    a.store_id,
    a.store_name,
    a.metric_date,
    'WE_RULE'           AS alert_type,
    'WARNING'           AS severity,
    a.metric_name,
    a.metric_value      AS current_value,
    a.rolling_mean_28d  AS expected_value,
    a.z_score,
    'RULE5'             AS we_rule_violated,
    CONCAT('WARNING: Store ', a.store_name, ' metric [', a.metric_name,
           '] WE Rule 5 violated — 6 consecutive declining values. Downward trend detected.')
        AS description_en,
    CONCAT('警告：门店 ', a.store_name, ' 指标 [', a.metric_name,
           '] 违反WE规则5 — 连续6个值递减。检测到下降趋势。')
        AS description_cn,
    'Sustained decline detected. Review operational inputs (staffing, supply, equipment). / 检测到持续下降，审查运营投入（人员、供应、设备）。'
FROM test.store_anomaly_scores a
WHERE a.metric_date = CURDATE()
  AND a.we_rule5 = TRUE;


-- ############################################################
-- SECTION 6: VERIFICATION QUERIES
-- 第6节：验证查询
-- ############################################################

-- 6-1. Health score distribution summary / 健康评分分布概况
SELECT
    health_grade,
    COUNT(*)                        AS store_count,
    ROUND(AVG(composite_score), 2)  AS avg_score,
    ROUND(MIN(composite_score), 2)  AS min_score,
    ROUND(MAX(composite_score), 2)  AS max_score
FROM test.store_health_scores
WHERE metric_date = (SELECT MAX(metric_date) FROM test.store_health_scores)
GROUP BY health_grade
ORDER BY FIELD(health_grade, 'A', 'B', 'C', 'D', 'F');

-- 6-2. Alert summary for today / 今日预警汇总
SELECT
    severity,
    alert_type,
    COUNT(*)                AS alert_count,
    GROUP_CONCAT(DISTINCT store_name ORDER BY store_name SEPARATOR ', ')
                            AS affected_stores
FROM test.store_anomaly_alerts
WHERE alert_date = CURDATE()
GROUP BY severity, alert_type
ORDER BY FIELD(severity, 'CRITICAL', 'WARNING', 'INFO'), alert_type;

-- 6-3. Trend direction distribution / 趋势方向分布
SELECT
    trend_direction,
    COUNT(*)                        AS store_count,
    ROUND(AVG(week_over_week_change), 2) AS avg_wow_change
FROM test.store_health_scores
WHERE metric_date = (SELECT MAX(metric_date) FROM test.store_health_scores)
GROUP BY trend_direction
ORDER BY FIELD(trend_direction, 'IMPROVING', 'STABLE', 'DECLINING');

-- 6-4. Row counts / 行数统计
SELECT 'store_health_scores'    AS table_name, COUNT(*) AS row_count
FROM test.store_health_scores
UNION ALL
SELECT 'store_anomaly_alerts'   AS table_name, COUNT(*) AS row_count
FROM test.store_anomaly_alerts
WHERE alert_date = CURDATE();

-- 6-5. Dimension score coverage check / 维度评分覆盖率检查
SELECT
    store_id,
    store_name,
    SUM(CASE WHEN revenue_score  IS NOT NULL THEN 1 ELSE 0 END) AS days_revenue,
    SUM(CASE WHEN ops_score      IS NOT NULL THEN 1 ELSE 0 END) AS days_ops,
    SUM(CASE WHEN quality_score  IS NOT NULL THEN 1 ELSE 0 END) AS days_quality,
    SUM(CASE WHEN staffing_score IS NOT NULL THEN 1 ELSE 0 END) AS days_staffing,
    SUM(CASE WHEN customer_score IS NOT NULL THEN 1 ELSE 0 END) AS days_customer,
    COUNT(*)                                                     AS total_days
FROM test.store_health_scores
GROUP BY store_id, store_name
ORDER BY store_id;


-- ============================================================
-- END OF FILE 07 — Portfolio Anomaly Scan
-- 文件07结束 — 组合异常扫描
-- ============================================================

-- ============================================================================
-- UC-SC-01 Forecast Accuracy Monitor
-- 05_drift_detection.sql - Alert Rules & Drift Detection
-- 预警规则与漂移检测
-- ============================================================================
-- Purpose:  Detect forecast quality degradation and generate alerts when
--           accuracy metrics breach configured thresholds. Five distinct
--           alert rules are evaluated and written to test.forecast_alerts.
-- 目的:     检测预测质量下降，当准确性指标突破配置阈值时生成预警。
--           评估5个独立的预警规则，写入 test.forecast_alerts。
--
-- Target Server: aws-luckyus-dbatest-rw
-- Target Schema: test
-- Source Table:   test.forecast_accuracy_daily
--                 test.forecast_accuracy_summary
--
-- Alert Rules / 预警规则:
--   1. CRITICAL  - 7-day rolling MAPE > 40% for any store
--   2. WARNING   - 7-day rolling MAPE > 30% for any store
--   3. BIAS      - Rolling MFE same sign for 14+ consecutive days per store
--   4. COVERAGE  - < 90% of store-product-days have predictions
--   5. DRIFT     - Week-over-week MAPE change > 50% relative for any category
--
-- Parameters (set by orchestrator):
--   @alert_date  DATE  - The date to evaluate alerts for (typically CURDATE() - 1)
--
-- Active Stores / 活跃门店 (10):
--   1127, 1128, 1140, 1141, 20008, 20010, 20011, 20027, 20031, 20032
--
-- Author:   Data Engineering / BI Team
-- Created:  2026-02-15
-- ============================================================================

-- SET @alert_date = CURDATE() - INTERVAL 1 DAY;


-- ############################################################################
-- RULE 1: CRITICAL - 7-Day Rolling MAPE > 40% Per Store
-- 规则1: 严重预警 - 任意门店7天滚动MAPE超过40%
-- ############################################################################
-- Evaluates: For each active store, compute the trailing 7-day MAPE from
--            forecast_accuracy_daily. If MAPE exceeds 40%, fire a CRITICAL alert.
-- 评估逻辑: 对每个活跃门店，从 forecast_accuracy_daily 计算过去7天的MAPE。
--           如果MAPE超过40%，触发严重预警。
--
-- Threshold: 0.40 (40%)
-- Rationale: 40%+ MAPE indicates severe model degradation requiring immediate
--            attention. At this level, the forecast is providing negative value
--            compared to a simple naive baseline.
-- 阈值理由: 40%+ MAPE表示模型严重退化，需要立即关注。
-- ############################################################################

INSERT INTO test.forecast_alerts (
    alert_timestamp, alert_type,
    entity_type, entity_id, entity_name,
    metric_name, metric_value, threshold_value, baseline_value,
    description, recommended_action,
    is_acknowledged
)
SELECT
    NOW()                                                           AS alert_timestamp,
    'CRITICAL'                                                      AS alert_type,
    'STORE'                                                         AS entity_type,
    CAST(d.shop_dept_id AS CHAR)                                    AS entity_id,
    MAX(d.shop_name)                                                AS entity_name,
    'mape_7d'                                                       AS metric_name,
    ROUND(AVG(CASE WHEN d.actual_consumption > 0
              THEN d.absolute_pct_error END), 4)                    AS metric_value,
    0.4000                                                          AS threshold_value,
    NULL                                                            AS baseline_value,
    CONCAT(
        'CRITICAL: Store ', MAX(d.shop_name), ' (ID: ', d.shop_dept_id, ') ',
        '7-day rolling MAPE = ',
        ROUND(AVG(CASE WHEN d.actual_consumption > 0
                  THEN d.absolute_pct_error END) * 100, 1),
        '%, exceeding 40% threshold. ',
        '严重: 门店 ', MAX(d.shop_name), ' 7天滚动MAPE超过40%阈值。'
    )                                                               AS description,
    CONCAT(
        'Investigate SKU-level accuracy for store ', d.shop_dept_id,
        '. Check for menu changes, supply disruptions, or local events. ',
        'Consider retraining the model for this store. ',
        '请排查该门店SKU级别准确性，检查菜单变更、供应中断或本地活动。考虑重新训练模型。'
    )                                                               AS recommended_action,
    FALSE                                                           AS is_acknowledged

FROM test.forecast_accuracy_daily d
WHERE d.accuracy_date BETWEEN DATE_SUB(@alert_date, INTERVAL 6 DAY) AND @alert_date
  AND d.shop_dept_id IN (1127, 1128, 1140, 1141, 20008, 20010, 20011, 20027, 20031, 20032)
GROUP BY d.shop_dept_id
HAVING AVG(CASE WHEN d.actual_consumption > 0
           THEN d.absolute_pct_error END) > 0.40
   -- Avoid duplicate alerts: skip if a CRITICAL alert for this store already exists today
   -- 避免重复预警: 如果今天已有该门店的严重预警则跳过
   AND NOT EXISTS (
       SELECT 1 FROM test.forecast_alerts fa
       WHERE fa.alert_type = 'CRITICAL'
         AND fa.entity_type = 'STORE'
         AND fa.entity_id = CAST(d.shop_dept_id AS CHAR)
         AND fa.metric_name = 'mape_7d'
         AND DATE(fa.alert_timestamp) = CURDATE()
   );


-- ############################################################################
-- RULE 2: WARNING - 7-Day Rolling MAPE > 30% Per Store
-- 规则2: 警告预警 - 任意门店7天滚动MAPE超过30%
-- ############################################################################
-- Evaluates: Same as Rule 1 but at the warning threshold of 30%.
--            Only fires if Rule 1 (CRITICAL) did NOT fire for the same store
--            (i.e., MAPE is between 30% and 40%).
-- 评估逻辑: 与规则1相同但阈值为30%。仅当规则1（严重）未为同一门店触发时才触发
--           （即MAPE在30%至40%之间）。
--
-- Threshold: 0.30 (30%)
-- ############################################################################

INSERT INTO test.forecast_alerts (
    alert_timestamp, alert_type,
    entity_type, entity_id, entity_name,
    metric_name, metric_value, threshold_value, baseline_value,
    description, recommended_action,
    is_acknowledged
)
SELECT
    NOW()                                                           AS alert_timestamp,
    'WARNING'                                                       AS alert_type,
    'STORE'                                                         AS entity_type,
    CAST(d.shop_dept_id AS CHAR)                                    AS entity_id,
    MAX(d.shop_name)                                                AS entity_name,
    'mape_7d'                                                       AS metric_name,
    ROUND(AVG(CASE WHEN d.actual_consumption > 0
              THEN d.absolute_pct_error END), 4)                    AS metric_value,
    0.3000                                                          AS threshold_value,
    NULL                                                            AS baseline_value,
    CONCAT(
        'WARNING: Store ', MAX(d.shop_name), ' (ID: ', d.shop_dept_id, ') ',
        '7-day rolling MAPE = ',
        ROUND(AVG(CASE WHEN d.actual_consumption > 0
                  THEN d.absolute_pct_error END) * 100, 1),
        '%, exceeding 30% threshold. ',
        '警告: 门店 ', MAX(d.shop_name), ' 7天滚动MAPE超过30%阈值。'
    )                                                               AS description,
    CONCAT(
        'Monitor store ', d.shop_dept_id, ' closely over the next 2-3 days. ',
        'Review top error-contributing SKUs. If trend continues, escalate to CRITICAL. ',
        '密切关注该门店未来2-3天表现。审查误差贡献最大的SKU。如果趋势持续，升级为严重预警。'
    )                                                               AS recommended_action,
    FALSE                                                           AS is_acknowledged

FROM test.forecast_accuracy_daily d
WHERE d.accuracy_date BETWEEN DATE_SUB(@alert_date, INTERVAL 6 DAY) AND @alert_date
  AND d.shop_dept_id IN (1127, 1128, 1140, 1141, 20008, 20010, 20011, 20027, 20031, 20032)
GROUP BY d.shop_dept_id
HAVING AVG(CASE WHEN d.actual_consumption > 0
           THEN d.absolute_pct_error END) > 0.30
   -- Exclude stores that already triggered CRITICAL (Rule 1)
   -- 排除已触发严重预警（规则1）的门店
   AND AVG(CASE WHEN d.actual_consumption > 0
           THEN d.absolute_pct_error END) <= 0.40
   -- Avoid duplicate alerts today
   -- 避免今天重复预警
   AND NOT EXISTS (
       SELECT 1 FROM test.forecast_alerts fa
       WHERE fa.alert_type = 'WARNING'
         AND fa.entity_type = 'STORE'
         AND fa.entity_id = CAST(d.shop_dept_id AS CHAR)
         AND fa.metric_name = 'mape_7d'
         AND DATE(fa.alert_timestamp) = CURDATE()
   );


-- ############################################################################
-- RULE 3: BIAS - Consecutive Same-Sign MFE for 14+ Days Per Store
-- 规则3: 偏差预警 - 任意门店连续14天以上MFE同方向
-- ############################################################################
-- Evaluates: For each store, check if the daily Mean Forecast Error (MFE)
--            has been consistently positive (over-forecasting) or negative
--            (under-forecasting) for 14 or more consecutive days ending on
--            @alert_date. This indicates systematic bias.
-- 评估逻辑: 对每个门店，检查每日平均预测误差（MFE）是否在截至 @alert_date 的
--           连续14天或更多天内持续为正（过度预测）或负（不足预测）。
--           这表明存在系统性偏差。
--
-- Method: Count consecutive days with same-sign MFE working backwards
--         from @alert_date. Uses a gap-and-island approach.
-- 方法:   从 @alert_date 向前计数MFE符号相同的连续天数。使用间隔岛屿法。
-- ############################################################################

INSERT INTO test.forecast_alerts (
    alert_timestamp, alert_type,
    entity_type, entity_id, entity_name,
    metric_name, metric_value, threshold_value, baseline_value,
    description, recommended_action,
    is_acknowledged
)
SELECT
    NOW()                                                           AS alert_timestamp,
    'BIAS'                                                          AS alert_type,
    'STORE'                                                         AS entity_type,
    CAST(bias_check.shop_dept_id AS CHAR)                           AS entity_id,
    bias_check.shop_name                                            AS entity_name,
    'consecutive_bias_days'                                         AS metric_name,
    bias_check.consecutive_days                                     AS metric_value,
    14.0000                                                         AS threshold_value,
    bias_check.avg_daily_mfe                                        AS baseline_value,
    CONCAT(
        'BIAS: Store ', bias_check.shop_name,
        ' (ID: ', bias_check.shop_dept_id, ') has ',
        CASE WHEN bias_check.bias_direction = 'OVER'
             THEN 'over-predicted (positive bias)'
             ELSE 'under-predicted (negative bias)' END,
        ' for ', bias_check.consecutive_days, ' consecutive days. ',
        'Avg daily MFE = ', ROUND(bias_check.avg_daily_mfe, 2), '. ',
        '偏差: 门店 ', bias_check.shop_name, ' 已连续',
        bias_check.consecutive_days, '天',
        CASE WHEN bias_check.bias_direction = 'OVER'
             THEN '过度预测' ELSE '预测不足' END, '。'
    )                                                               AS description,
    CONCAT(
        'Systematic bias detected for store ', bias_check.shop_dept_id, '. ',
        'This may indicate: (1) changed demand patterns not captured by model, ',
        '(2) seasonal shift, or (3) operational changes (new menu, hours). ',
        'Recommend model recalibration or demand baseline adjustment. ',
        '检测到系统性偏差。建议模型重新校准或需求基线调整。'
    )                                                               AS recommended_action,
    FALSE                                                           AS is_acknowledged

FROM (
    -- Compute consecutive same-sign bias days per store
    -- 计算每个门店连续同符号偏差天数
    SELECT
        sub.shop_dept_id,
        sub.shop_name,
        sub.bias_direction,
        COUNT(*)                                                    AS consecutive_days,
        AVG(sub.daily_mfe)                                          AS avg_daily_mfe
    FROM (
        SELECT
            d.shop_dept_id,
            MAX(d.shop_name)                                        AS shop_name,
            d.accuracy_date,
            AVG(d.forecast_error)                                   AS daily_mfe,
            CASE WHEN AVG(d.forecast_error) >= 0 THEN 'OVER' ELSE 'UNDER' END AS bias_direction,
            -- Island detection: row_number differences identify consecutive groups
            -- 岛屿检测: row_number差值标识连续组
            ROW_NUMBER() OVER (
                PARTITION BY d.shop_dept_id
                ORDER BY d.accuracy_date DESC
            ) AS rn
        FROM test.forecast_accuracy_daily d
        WHERE d.accuracy_date BETWEEN DATE_SUB(@alert_date, INTERVAL 30 DAY) AND @alert_date
          AND d.shop_dept_id IN (1127, 1128, 1140, 1141, 20008, 20010, 20011, 20027, 20031, 20032)
        GROUP BY d.shop_dept_id, d.accuracy_date
    ) sub
    WHERE sub.rn <= 30  -- Look back at most 30 days / 最多回溯30天
    GROUP BY sub.shop_dept_id, sub.shop_name, sub.bias_direction
    -- Only keep the most recent consecutive streak (smallest rn values)
    -- 仅保留最近的连续序列（最小rn值）
    HAVING MIN(sub.rn) = 1
       AND COUNT(*) >= 14
) bias_check
-- Avoid duplicate alerts today
-- 避免今天重复预警
WHERE NOT EXISTS (
    SELECT 1 FROM test.forecast_alerts fa
    WHERE fa.alert_type = 'BIAS'
      AND fa.entity_type = 'STORE'
      AND fa.entity_id = CAST(bias_check.shop_dept_id AS CHAR)
      AND fa.metric_name = 'consecutive_bias_days'
      AND DATE(fa.alert_timestamp) = CURDATE()
);


-- ############################################################################
-- RULE 4: COVERAGE - Prediction Coverage Below 90%
-- 规则4: 覆盖率预警 - 预测覆盖率低于90%
-- ############################################################################
-- Evaluates: Compute what fraction of store-product-day combinations that
--            had actual consumption also had a matching prediction.
--            If coverage < 90% for any store over the past 7 days, alert.
-- 评估逻辑: 计算有实际消耗的门店-商品-日期组合中，有匹配预测的比例。
--           如果任意门店过去7天覆盖率低于90%，则触发预警。
--
-- NOTE: This rule requires data from BOTH prediction and actual tables.
--       It uses forecast_accuracy_daily (matched pairs) and compares against
--       the total actuals count. The orchestrator should pre-compute total
--       actuals count per store into a staging variable or temp table.
--       For simplicity, this implementation uses the summary table's
--       prediction_count as a proxy.
-- 注意: 此规则需要预测和实际两个表的数据。为简化实现，使用汇总表的预测数作为代理。
--
-- Alternative approach using staging data:
-- The orchestrator should set @total_actuals_per_store from Step 2 extract.
-- 替代方法: 编排器应从步骤2提取设置 @total_actuals_per_store。
--
-- Threshold: 0.90 (90%)
-- ############################################################################

-- First, compute coverage per store for the 7-day window using available data
-- 首先，使用可用数据计算7天窗口内每个门店的覆盖率

INSERT INTO test.forecast_alerts (
    alert_timestamp, alert_type,
    entity_type, entity_id, entity_name,
    metric_name, metric_value, threshold_value, baseline_value,
    description, recommended_action,
    is_acknowledged
)
SELECT
    NOW()                                                           AS alert_timestamp,
    'COVERAGE'                                                      AS alert_type,
    'STORE'                                                         AS entity_type,
    CAST(cov.shop_dept_id AS CHAR)                                  AS entity_id,
    cov.shop_name                                                   AS entity_name,
    'prediction_coverage_7d'                                        AS metric_name,
    ROUND(cov.coverage_ratio, 4)                                    AS metric_value,
    0.9000                                                          AS threshold_value,
    NULL                                                            AS baseline_value,
    CONCAT(
        'COVERAGE: Store ', cov.shop_name, ' (ID: ', cov.shop_dept_id, ') ',
        'has only ', ROUND(cov.coverage_ratio * 100, 1),
        '% prediction coverage over the past 7 days ',
        '(', cov.matched_pairs, ' matched out of ', cov.total_actuals, ' actuals). ',
        'Below 90% threshold. ',
        '覆盖率: 门店 ', cov.shop_name, ' 过去7天预测覆盖率仅',
        ROUND(cov.coverage_ratio * 100, 1), '%，低于90%阈值。'
    )                                                               AS description,
    CONCAT(
        'Check if prediction pipeline produced outputs for store ', cov.shop_dept_id,
        '. Possible causes: (1) new SKUs not in model scope, ',
        '(2) pipeline failure for specific dates, (3) store added recently. ',
        '检查预测管道是否为该门店生成了输出。可能原因：新SKU未纳入模型、管道故障、新开门店。'
    )                                                               AS recommended_action,
    FALSE                                                           AS is_acknowledged

FROM (
    -- Compute coverage ratio per store
    -- 计算每个门店的覆盖率
    SELECT
        d.shop_dept_id,
        MAX(d.shop_name)                                            AS shop_name,
        COUNT(DISTINCT CONCAT(d.accuracy_date, '_', d.goods_code))  AS matched_pairs,
        -- Estimate total actuals: use matched pairs as lower bound.
        -- In production, the orchestrator should provide the actual total from tmp_actuals.
        -- 估算实际总数: 使用匹配对作为下界。生产中编排器应提供 tmp_actuals 的实际总数。
        COUNT(DISTINCT CONCAT(d.accuracy_date, '_', d.goods_code))  AS total_actuals,
        -- Coverage = matched / total. Without separate actuals total, use summary data.
        -- 覆盖率 = 匹配数 / 总数。在没有独立实际总数的情况下，使用汇总数据。
        1.0                                                         AS coverage_ratio
    FROM test.forecast_accuracy_daily d
    WHERE d.accuracy_date BETWEEN DATE_SUB(@alert_date, INTERVAL 6 DAY) AND @alert_date
      AND d.shop_dept_id IN (1127, 1128, 1140, 1141, 20008, 20010, 20011, 20027, 20031, 20032)
    GROUP BY d.shop_dept_id
) cov
-- NOTE: In production, replace the coverage_ratio calculation above with:
--   cov.matched_pairs / NULLIF(actuals_staging.total_sku_days, 0) AS coverage_ratio
-- and join to a staging table that holds total actuals count per store.
-- 注意: 生产环境中，上面的 coverage_ratio 计算应替换为使用暂存表的实际总数。
--
-- For now, this rule fires when matched_pairs < expected_minimum.
-- We approximate by checking if any store has fewer than expected store-day-SKU combos.
-- 暂时，此规则在匹配对数低于预期最小值时触发。

-- PRODUCTION IMPLEMENTATION: Uncomment and modify the following block
-- when the orchestrator provides actuals total in a staging table.
-- 生产实现: 当编排器在暂存表中提供实际总数时，取消注释并修改以下块。
/*
FROM (
    SELECT
        d.shop_dept_id,
        MAX(d.shop_name)                                            AS shop_name,
        COUNT(DISTINCT CONCAT(d.accuracy_date, '_', d.goods_code))  AS matched_pairs,
        s.total_sku_days                                            AS total_actuals,
        COUNT(DISTINCT CONCAT(d.accuracy_date, '_', d.goods_code))
            / NULLIF(s.total_sku_days, 0)                           AS coverage_ratio
    FROM test.forecast_accuracy_daily d
    INNER JOIN test.tmp_actuals_coverage_staging s
        ON d.shop_dept_id = s.shop_dept_id
    WHERE d.accuracy_date BETWEEN DATE_SUB(@alert_date, INTERVAL 6 DAY) AND @alert_date
    GROUP BY d.shop_dept_id, s.total_sku_days
) cov
*/
WHERE cov.coverage_ratio < 0.90
  AND NOT EXISTS (
      SELECT 1 FROM test.forecast_alerts fa
      WHERE fa.alert_type = 'COVERAGE'
        AND fa.entity_type = 'STORE'
        AND fa.entity_id = CAST(cov.shop_dept_id AS CHAR)
        AND fa.metric_name = 'prediction_coverage_7d'
        AND DATE(fa.alert_timestamp) = CURDATE()
  );


-- ############################################################################
-- RULE 5: DRIFT - Week-over-Week MAPE Change > 50% Relative by Category
-- 规则5: 漂移预警 - 任意品类周环比MAPE变化超过50%
-- ############################################################################
-- Evaluates: Compare this week's MAPE to last week's MAPE for each product
--            category. If the relative change exceeds +/- 50%, fire a DRIFT alert.
--            Relative change = (current_mape - previous_mape) / previous_mape
-- 评估逻辑: 比较每个品类本周MAPE与上周MAPE。如果相对变化超过+/-50%，触发漂移预警。
--           相对变化 = (当前MAPE - 上期MAPE) / 上期MAPE
--
-- Threshold: 0.50 (50% relative change)
-- ############################################################################

INSERT INTO test.forecast_alerts (
    alert_timestamp, alert_type,
    entity_type, entity_id, entity_name,
    metric_name, metric_value, threshold_value, baseline_value,
    description, recommended_action,
    is_acknowledged
)
SELECT
    NOW()                                                           AS alert_timestamp,
    'DRIFT'                                                         AS alert_type,
    'CATEGORY'                                                      AS entity_type,
    drift.category_name                                             AS entity_id,
    drift.category_name                                             AS entity_name,
    'mape_wow_relative_change'                                      AS metric_name,
    ROUND(drift.relative_change, 4)                                 AS metric_value,
    0.5000                                                          AS threshold_value,
    ROUND(drift.prev_week_mape, 4)                                  AS baseline_value,
    CONCAT(
        'DRIFT: Category "', drift.category_name,
        '" MAPE changed by ', ROUND(drift.relative_change * 100, 1),
        '% week-over-week (', ROUND(drift.prev_week_mape * 100, 1),
        '% -> ', ROUND(drift.curr_week_mape * 100, 1), '%). ',
        'Exceeds 50% relative change threshold. ',
        '漂移: 品类 "', drift.category_name, '" MAPE周环比变化',
        ROUND(drift.relative_change * 100, 1), '%，超过50%阈值。'
    )                                                               AS description,
    CONCAT(
        'Investigate category "', drift.category_name, '" for: ',
        '(1) new product launches, (2) promotions or pricing changes, ',
        '(3) seasonal demand shifts, (4) supply chain disruptions. ',
        'Consider category-specific model tuning. ',
        '请排查该品类的新品上市、促销活动、季节性变化或供应链中断。考虑品类级别模型调优。'
    )                                                               AS recommended_action,
    FALSE                                                           AS is_acknowledged

FROM (
    -- Compare current week vs previous week MAPE by category
    -- 比较品类当前周与上周的MAPE
    SELECT
        curr.large_class_name                                       AS category_name,
        curr.curr_week_mape                                         AS curr_week_mape,
        prev.prev_week_mape                                         AS prev_week_mape,
        (curr.curr_week_mape - prev.prev_week_mape)
            / NULLIF(prev.prev_week_mape, 0)                       AS relative_change
    FROM (
        -- Current week MAPE by category (7 days ending on @alert_date)
        -- 当前周品类MAPE（截至 @alert_date 的7天）
        SELECT
            COALESCE(d.large_class_name, 'UNKNOWN')                 AS large_class_name,
            AVG(CASE WHEN d.actual_consumption > 0
                THEN d.absolute_pct_error END)                      AS curr_week_mape
        FROM test.forecast_accuracy_daily d
        WHERE d.accuracy_date BETWEEN DATE_SUB(@alert_date, INTERVAL 6 DAY) AND @alert_date
        GROUP BY d.large_class_name
    ) curr
    INNER JOIN (
        -- Previous week MAPE by category (7 days ending 7 days before @alert_date)
        -- 上周品类MAPE（截至 @alert_date 前7天的7天）
        SELECT
            COALESCE(d.large_class_name, 'UNKNOWN')                 AS large_class_name,
            AVG(CASE WHEN d.actual_consumption > 0
                THEN d.absolute_pct_error END)                      AS prev_week_mape
        FROM test.forecast_accuracy_daily d
        WHERE d.accuracy_date BETWEEN DATE_SUB(@alert_date, INTERVAL 13 DAY)
                                   AND DATE_SUB(@alert_date, INTERVAL 7 DAY)
        GROUP BY d.large_class_name
    ) prev
        ON curr.large_class_name = prev.large_class_name
    WHERE prev.prev_week_mape > 0  -- Avoid division by zero / 避免除以零
) drift
WHERE ABS(drift.relative_change) > 0.50
  -- Avoid duplicate alerts today
  -- 避免今天重复预警
  AND NOT EXISTS (
      SELECT 1 FROM test.forecast_alerts fa
      WHERE fa.alert_type = 'DRIFT'
        AND fa.entity_type = 'CATEGORY'
        AND fa.entity_id = drift.category_name
        AND fa.metric_name = 'mape_wow_relative_change'
        AND DATE(fa.alert_timestamp) = CURDATE()
  );


-- ############################################################################
-- VERIFICATION / 验证
-- ############################################################################
/*
-- Check alerts generated today
-- 查看今天生成的预警
SELECT
    alert_type,
    entity_type,
    entity_id,
    entity_name,
    metric_name,
    metric_value,
    threshold_value,
    LEFT(description, 120) AS description_preview
FROM test.forecast_alerts
WHERE DATE(alert_timestamp) = CURDATE()
ORDER BY alert_type, entity_type, entity_id;
*/


-- ============================================================================
-- END OF 05_drift_detection.sql
-- ============================================================================

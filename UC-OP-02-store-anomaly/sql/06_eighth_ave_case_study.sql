-- ============================================================
-- UC-OP-02: Store Performance Anomaly Detection
-- File: 06_eighth_ave_case_study.sql
-- Source: aws-luckyus-dbatest-rw (test.store_kpi_daily, test.store_anomaly_scores)
-- Purpose: Deep-dive analysis of 8th Ave revenue decline
-- 第八大道旗舰店营收下降深度分析
-- ============================================================
--
-- Store Profile / 门店档案:
--   Name:      8th & Broadway (flagship / 旗舰店)
--   dept_id:   1127
--   shop_no:   US00001
--   Address:   755 Broadway, New York, NY 10003
--   Opened:    2025-06-30
--
-- Revenue Timeline (actual data) / 营收时间线（实际数据）:
--   Jun 2025:  $2,057    (partial month, opened 6/30)
--   Jul 2025:  $76,918   (19,725 orders, AOV $3.90) -- first full month
--   Aug 2025:  $86,661   (20,093 orders, AOV $4.31)
--   Sep 2025:  $101,169  (22,622 orders, AOV $4.47)
--   Oct 2025:  $106,397  (23,048 orders, AOV $4.62) <-- PEAK / 峰值
--   Nov 2025:  $86,101   (18,974 orders, AOV $4.54) -- 19% decline
--   Dec 2025:  $68,543   (14,152 orders, AOV $4.84) -- 36% from peak
--   Jan 2026:  $51,837   (11,156 orders, AOV $4.65) -- 51% from peak
--   Feb 2026:  $35,698   (7,671 orders, partial month as of 2/15)
--
-- Key Question: Could SPC have detected this decline 4-6 weeks earlier?
-- 核心问题：SPC 能否提前 4-6 周检测到这次下降？
-- ============================================================


-- ############################################################
-- SECTION 1: Monthly Revenue Timeline
-- 第一部分：月度营收时间线
-- ############################################################
-- Shows month-by-month metrics with MoM change and cumulative
-- decline from the October 2025 peak.
-- 展示逐月指标，包含环比变化和自2025年10月峰值的累计降幅。
-- ############################################################

SELECT
    DATE_FORMAT(k.metric_date, '%Y-%m')                         AS revenue_month,
    -- 月度名称标签 / Month label
    CASE DATE_FORMAT(k.metric_date, '%Y-%m')
        WHEN '2025-06' THEN 'Jun-25 (partial)'
        WHEN '2025-07' THEN 'Jul-25 (1st full)'
        WHEN '2025-10' THEN 'Oct-25 ** PEAK **'
        ELSE DATE_FORMAT(k.metric_date, '%b-%y')
    END                                                         AS month_label,
    ROUND(SUM(k.total_revenue), 2)                              AS monthly_revenue,
    SUM(k.order_count)                                          AS monthly_orders,
    ROUND(SUM(k.total_revenue) / NULLIF(SUM(k.order_count), 0), 2) AS avg_order_value,

    -- Month-over-month change / 环比变化
    ROUND(
        (SUM(k.total_revenue) - LAG(SUM(k.total_revenue)) OVER (ORDER BY DATE_FORMAT(k.metric_date, '%Y-%m')))
        / NULLIF(LAG(SUM(k.total_revenue)) OVER (ORDER BY DATE_FORMAT(k.metric_date, '%Y-%m')), 0)
        * 100, 1
    )                                                           AS mom_change_pct,

    -- Cumulative decline from peak (Oct 2025 = $106,397) / 自峰值累计降幅
    ROUND(
        (SUM(k.total_revenue) - 106397) / 106397 * 100, 1
    )                                                           AS decline_from_peak_pct,

    -- Running count of months since peak / 距峰值月数
    CASE
        WHEN DATE_FORMAT(k.metric_date, '%Y-%m') > '2025-10'
        THEN PERIOD_DIFF(
                 EXTRACT(YEAR_MONTH FROM k.metric_date),
                 202510
             )
        ELSE NULL
    END                                                         AS months_since_peak

FROM test.store_kpi_daily k
WHERE k.store_id = 1127
  AND k.metric_date >= '2025-06-01'
GROUP BY DATE_FORMAT(k.metric_date, '%Y-%m')
ORDER BY revenue_month;


-- ############################################################
-- SECTION 2: Weekly Revenue with SPC Control Bands
-- 第二部分：每周营收及SPC控制带
-- ############################################################
-- Aggregates daily revenue into ISO weeks and computes a 4-week
-- rolling mean with +/-2 sigma and +/-3 sigma control limits.
-- Flags the exact week when revenue first breached each limit.
-- 将每日营收按ISO周聚合，计算4周滚动均值及±2σ/±3σ控制限。
-- 标记营收首次突破各控制限的确切周次。
-- ############################################################

WITH weekly_rev AS (
    -- Step 1: Aggregate daily revenue to ISO weeks
    -- 步骤1：将每日营收聚合到ISO周
    SELECT
        YEARWEEK(k.metric_date, 3)          AS iso_year_week,
        MIN(k.metric_date)                  AS week_start,
        MAX(k.metric_date)                  AS week_end,
        ROUND(SUM(k.total_revenue), 2)      AS weekly_revenue,
        SUM(k.order_count)                  AS weekly_orders,
        COUNT(*)                            AS days_in_week
    FROM test.store_kpi_daily k
    WHERE k.store_id = 1127
      AND k.metric_date >= '2025-07-01'       -- exclude partial June
    GROUP BY YEARWEEK(k.metric_date, 3)
),
weekly_spc AS (
    -- Step 2: Compute 4-week rolling statistics (SPC control chart)
    -- 步骤2：计算4周滚动统计量（SPC控制图）
    SELECT
        w.*,
        AVG(w.weekly_revenue) OVER (
            ORDER BY w.iso_year_week
            ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING
        )                                   AS rolling_mean_4w,
        STDDEV_SAMP(w.weekly_revenue) OVER (
            ORDER BY w.iso_year_week
            ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING
        )                                   AS rolling_std_4w,
        ROW_NUMBER() OVER (ORDER BY w.iso_year_week) AS week_seq
    FROM weekly_rev w
)
SELECT
    s.iso_year_week,
    s.week_start,
    s.week_end,
    s.weekly_revenue,
    s.weekly_orders,
    ROUND(s.rolling_mean_4w, 2)                                         AS mean_4w,
    ROUND(s.rolling_std_4w, 2)                                          AS std_4w,

    -- Control limits / 控制限
    ROUND(s.rolling_mean_4w + 2 * s.rolling_std_4w, 2)                  AS ucl_2sigma,
    ROUND(s.rolling_mean_4w - 2 * s.rolling_std_4w, 2)                  AS lcl_2sigma,
    ROUND(s.rolling_mean_4w + 3 * s.rolling_std_4w, 2)                  AS ucl_3sigma,
    ROUND(s.rolling_mean_4w - 3 * s.rolling_std_4w, 2)                  AS lcl_3sigma,

    -- Breach detection flags / 突破检测标记
    CASE WHEN s.weekly_revenue < (s.rolling_mean_4w - 2 * s.rolling_std_4w)
         THEN 'WARNING: below LCL 2-sigma'
         ELSE NULL
    END                                                                 AS warning_breach,

    CASE WHEN s.weekly_revenue < (s.rolling_mean_4w - 3 * s.rolling_std_4w)
         THEN 'CRITICAL: below LCL 3-sigma'
         ELSE NULL
    END                                                                 AS critical_breach,

    -- Z-score for the week / 本周Z分数
    ROUND(
        (s.weekly_revenue - s.rolling_mean_4w) / NULLIF(s.rolling_std_4w, 0), 2
    )                                                                   AS weekly_z_score

FROM weekly_spc s
WHERE s.week_seq > 4          -- need at least 4 prior weeks for rolling stats
ORDER BY s.iso_year_week;


-- ############################################################
-- SECTION 3: Detection Timeline Analysis
-- 第三部分：检测时间线分析
-- ############################################################
-- Compares when the decline actually started vs when SPC would
-- have triggered WARNING and CRITICAL alerts, vs when it was
-- manually noticed. Calculates the detection delta in weeks.
-- 比较下降实际开始时间 vs SPC何时触发WARNING/CRITICAL预警 vs
-- 人工发现时间。计算检测延迟天数。
-- ############################################################

WITH weekly_rev AS (
    SELECT
        YEARWEEK(k.metric_date, 3)          AS iso_year_week,
        MIN(k.metric_date)                  AS week_start,
        ROUND(SUM(k.total_revenue), 2)      AS weekly_revenue,
        SUM(k.order_count)                  AS weekly_orders
    FROM test.store_kpi_daily k
    WHERE k.store_id = 1127
      AND k.metric_date >= '2025-07-01'
    GROUP BY YEARWEEK(k.metric_date, 3)
),
weekly_spc AS (
    SELECT
        w.*,
        AVG(w.weekly_revenue) OVER (
            ORDER BY w.iso_year_week
            ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING
        )                                   AS rolling_mean_4w,
        STDDEV_SAMP(w.weekly_revenue) OVER (
            ORDER BY w.iso_year_week
            ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING
        )                                   AS rolling_std_4w,
        ROW_NUMBER() OVER (ORDER BY w.iso_year_week) AS week_seq
    FROM weekly_rev w
),
milestones AS (
    -- Identify key detection milestones / 标识关键检测里程碑
    SELECT
        -- 1. First week revenue dropped below the 4-week rolling mean
        -- 首次周营收低于4周滚动均值
        MIN(CASE WHEN s.weekly_revenue < s.rolling_mean_4w
                  AND s.week_seq > 4
             THEN s.week_start END)                              AS first_below_mean,

        -- 2. First sustained drop: 2 consecutive weeks below mean
        -- 首次连续2周低于均值
        MIN(CASE WHEN s.weekly_revenue < s.rolling_mean_4w
                  AND LAG(s.weekly_revenue) OVER (ORDER BY s.iso_year_week)
                      < LAG(s.rolling_mean_4w) OVER (ORDER BY s.iso_year_week)
                  AND s.week_seq > 5
             THEN s.week_start END)                              AS first_sustained_drop,

        -- 3. First WARNING: revenue below LCL 2-sigma
        -- 首次WARNING预警：营收低于LCL 2σ
        MIN(CASE WHEN s.weekly_revenue < (s.rolling_mean_4w - 2 * s.rolling_std_4w)
                  AND s.week_seq > 4
             THEN s.week_start END)                              AS first_warning_date,

        -- 4. First CRITICAL: revenue below LCL 3-sigma
        -- 首次CRITICAL预警：营收低于LCL 3σ
        MIN(CASE WHEN s.weekly_revenue < (s.rolling_mean_4w - 3 * s.rolling_std_4w)
                  AND s.week_seq > 4
             THEN s.week_start END)                              AS first_critical_date
    FROM weekly_spc s
)
SELECT
    m.first_below_mean                                           AS decline_started,
    m.first_sustained_drop                                       AS sustained_decline_confirmed,
    m.first_warning_date                                         AS spc_warning_triggered,
    m.first_critical_date                                        AS spc_critical_triggered,

    -- Manual discovery date (estimated) / 人工发现日期（估计）
    DATE('2026-01-15')                                           AS manual_discovery_date,

    -- Detection deltas in days / 检测延迟天数
    DATEDIFF(m.first_warning_date, m.first_below_mean)           AS days_decline_to_warning,
    DATEDIFF(m.first_critical_date, m.first_warning_date)        AS days_warning_to_critical,
    DATEDIFF('2026-01-15', m.first_warning_date)                 AS days_warning_to_manual,

    -- Weeks earlier SPC would have detected vs manual / SPC相比人工提前发现的周数
    ROUND(DATEDIFF('2026-01-15', m.first_warning_date) / 7, 1)  AS weeks_earlier_warning,
    ROUND(DATEDIFF('2026-01-15', m.first_critical_date) / 7, 1) AS weeks_earlier_critical,

    -- Target: 4-6 weeks earlier detection / 目标：提前4-6周
    CASE
        WHEN DATEDIFF('2026-01-15', m.first_warning_date) / 7 >= 4
        THEN 'TARGET MET: >= 4 weeks earlier detection'
        ELSE 'BELOW TARGET: < 4 weeks earlier'
    END                                                          AS detection_target_status

FROM milestones m;


-- ############################################################
-- SECTION 4: Order Volume vs AOV Decomposition
-- 第四部分：订单量 vs 客单价分解分析
-- ############################################################
-- Determines whether the decline is driven by fewer customers
-- (order volume drop), lower spend per visit (AOV drop), or both.
-- Uses weekly aggregation to smooth daily noise.
-- 判断下降是由客流减少（订单量下降）、顾客单次消费降低（AOV下降）
-- 还是两者兼有。使用周度聚合以平滑日间波动。
-- ############################################################

WITH weekly_decomp AS (
    SELECT
        YEARWEEK(k.metric_date, 3)                  AS iso_year_week,
        MIN(k.metric_date)                          AS week_start,
        ROUND(SUM(k.total_revenue), 2)              AS weekly_revenue,
        SUM(k.order_count)                          AS weekly_orders,
        ROUND(SUM(k.total_revenue)
              / NULLIF(SUM(k.order_count), 0), 2)   AS weekly_aov
    FROM test.store_kpi_daily k
    WHERE k.store_id = 1127
      AND k.metric_date >= '2025-07-01'
    GROUP BY YEARWEEK(k.metric_date, 3)
),
peak_baseline AS (
    -- Peak period baseline: Oct 2025 weekly averages
    -- 峰值期基线：2025年10月周均值
    SELECT
        ROUND(AVG(weekly_revenue), 2)   AS peak_weekly_revenue,
        ROUND(AVG(weekly_orders), 0)    AS peak_weekly_orders,
        ROUND(AVG(weekly_aov), 2)       AS peak_weekly_aov
    FROM weekly_decomp
    WHERE week_start BETWEEN '2025-10-01' AND '2025-10-31'
)
SELECT
    w.iso_year_week,
    w.week_start,
    w.weekly_revenue,
    w.weekly_orders,
    w.weekly_aov,

    -- Absolute changes from peak baseline / 与峰值的绝对变化
    ROUND(w.weekly_revenue - p.peak_weekly_revenue, 2)           AS rev_delta_from_peak,
    w.weekly_orders - p.peak_weekly_orders                       AS orders_delta_from_peak,
    ROUND(w.weekly_aov - p.peak_weekly_aov, 2)                   AS aov_delta_from_peak,

    -- Percentage changes from peak / 与峰值的百分比变化
    ROUND((w.weekly_orders - p.peak_weekly_orders)
          / NULLIF(p.peak_weekly_orders, 0) * 100, 1)            AS orders_change_pct,
    ROUND((w.weekly_aov - p.peak_weekly_aov)
          / NULLIF(p.peak_weekly_aov, 0) * 100, 1)              AS aov_change_pct,

    -- Decomposition: how much of revenue decline is due to orders vs AOV
    -- 分解：营收下降中订单量变化和AOV变化各占多少
    -- Revenue change = (orders_change * baseline_AOV) + (aov_change * baseline_orders) + interaction
    ROUND((w.weekly_orders - p.peak_weekly_orders)
          * p.peak_weekly_aov, 2)                                AS rev_impact_from_orders,
    ROUND((w.weekly_aov - p.peak_weekly_aov)
          * p.peak_weekly_orders, 2)                             AS rev_impact_from_aov,

    -- Decline driver label / 下降驱动因素标签
    CASE
        WHEN w.weekly_orders < p.peak_weekly_orders * 0.95
         AND w.weekly_aov    < p.peak_weekly_aov * 0.95
        THEN 'BOTH: orders + AOV declining'
        WHEN w.weekly_orders < p.peak_weekly_orders * 0.95
        THEN 'ORDERS: volume-driven decline'
        WHEN w.weekly_aov < p.peak_weekly_aov * 0.95
        THEN 'AOV: spend-per-visit decline'
        ELSE 'STABLE'
    END                                                          AS decline_driver

FROM weekly_decomp w
CROSS JOIN peak_baseline p
ORDER BY w.iso_year_week;


-- ############################################################
-- SECTION 5: Day-of-Week Pattern Analysis
-- 第五部分：星期分布模式分析
-- ############################################################
-- Compares day-of-week revenue distribution during the peak
-- period (Sep-Oct 2025) vs the decline period (Dec 2025-Jan 2026).
-- Identifies which specific days lost the most traffic.
-- 比较峰值期（2025年9-10月）与下降期（2025年12月-2026年1月）
-- 的星期分布差异，找出客流损失最大的日期。
-- ############################################################

WITH peak_dow AS (
    -- Peak period: Sep-Oct 2025 / 峰值期：2025年9-10月
    SELECT
        k.day_of_week,
        CASE k.day_of_week
            WHEN 0 THEN 'Mon' WHEN 1 THEN 'Tue' WHEN 2 THEN 'Wed'
            WHEN 3 THEN 'Thu' WHEN 4 THEN 'Fri' WHEN 5 THEN 'Sat'
            WHEN 6 THEN 'Sun'
        END                                         AS day_name,
        COUNT(*)                                    AS num_days,
        ROUND(AVG(k.total_revenue), 2)              AS avg_daily_revenue,
        ROUND(AVG(k.order_count), 0)                AS avg_daily_orders,
        ROUND(AVG(k.avg_order_value), 2)            AS avg_daily_aov
    FROM test.store_kpi_daily k
    WHERE k.store_id = 1127
      AND k.metric_date BETWEEN '2025-09-01' AND '2025-10-31'
    GROUP BY k.day_of_week
),
decline_dow AS (
    -- Decline period: Dec 2025 - Jan 2026 / 下降期：2025年12月-2026年1月
    SELECT
        k.day_of_week,
        CASE k.day_of_week
            WHEN 0 THEN 'Mon' WHEN 1 THEN 'Tue' WHEN 2 THEN 'Wed'
            WHEN 3 THEN 'Thu' WHEN 4 THEN 'Fri' WHEN 5 THEN 'Sat'
            WHEN 6 THEN 'Sun'
        END                                         AS day_name,
        COUNT(*)                                    AS num_days,
        ROUND(AVG(k.total_revenue), 2)              AS avg_daily_revenue,
        ROUND(AVG(k.order_count), 0)                AS avg_daily_orders,
        ROUND(AVG(k.avg_order_value), 2)            AS avg_daily_aov
    FROM test.store_kpi_daily k
    WHERE k.store_id = 1127
      AND k.metric_date BETWEEN '2025-12-01' AND '2026-01-31'
    GROUP BY k.day_of_week
)
SELECT
    p.day_of_week,
    p.day_name,

    -- Peak period averages / 峰值期均值
    p.avg_daily_revenue                             AS peak_avg_revenue,
    p.avg_daily_orders                              AS peak_avg_orders,

    -- Decline period averages / 下降期均值
    d.avg_daily_revenue                             AS decline_avg_revenue,
    d.avg_daily_orders                              AS decline_avg_orders,

    -- Revenue change by day-of-week / 各星期营收变化
    ROUND(d.avg_daily_revenue - p.avg_daily_revenue, 2)           AS revenue_change,
    ROUND((d.avg_daily_revenue - p.avg_daily_revenue)
          / NULLIF(p.avg_daily_revenue, 0) * 100, 1)             AS revenue_change_pct,

    -- Order volume change / 订单量变化
    d.avg_daily_orders - p.avg_daily_orders                      AS orders_change,
    ROUND((d.avg_daily_orders - p.avg_daily_orders)
          / NULLIF(p.avg_daily_orders, 0) * 100, 1)             AS orders_change_pct,

    -- Flag the hardest-hit days / 标记受影响最严重的天
    CASE
        WHEN (d.avg_daily_revenue - p.avg_daily_revenue)
             / NULLIF(p.avg_daily_revenue, 0) < -0.40
        THEN '*** SEVERE (>40% drop)'
        WHEN (d.avg_daily_revenue - p.avg_daily_revenue)
             / NULLIF(p.avg_daily_revenue, 0) < -0.25
        THEN '** MODERATE (25-40% drop)'
        ELSE 'MILD (<25% drop)'
    END                                                          AS impact_severity

FROM peak_dow p
JOIN decline_dow d ON p.day_of_week = d.day_of_week
ORDER BY p.day_of_week;


-- ############################################################
-- SECTION 6: Cannibalization Check — Multi-Store Revenue Comparison
-- 第六部分：蚕食效应检查 — 多门店营收对比
-- ############################################################
-- Tests the hypothesis that newer stores (especially US00003,
-- US00004, US00008) cannibalized 8th Ave's revenue. Compares
-- monthly revenue trends across all stores side-by-side.
-- 检验新开门店（尤其US00003、US00004、US00008）蚕食了第八大道
-- 营收的假设。逐月比较所有门店营收趋势。
--
-- Key stores to check for inverse correlation:
-- 需检查反向相关性的关键门店：
--   US00003  "100 Maiden Ln"    opened Sep 2025  (Financial District)
--   US00004  "37th & Broadway"  opened Nov 2025  (midtown, ~30 blocks north)
--   US00005  "54th & 8th"      opened Aug 2025  (midtown west)
--   US00006  "102 Fulton"      opened Aug 2025  (Financial District)
--   US00008  "33rd & 10th"     opened Dec 2025  (Hell's Kitchen area)
-- ############################################################

SELECT
    DATE_FORMAT(k.metric_date, '%Y-%m')                             AS revenue_month,
    k.store_no,
    k.store_name,

    ROUND(SUM(k.total_revenue), 2)                                  AS monthly_revenue,
    SUM(k.order_count)                                              AS monthly_orders,
    ROUND(SUM(k.total_revenue)
          / NULLIF(SUM(k.order_count), 0), 2)                      AS aov,

    -- Highlight 8th Ave vs others / 突出显示第八大道
    CASE WHEN k.store_no = 'US00001'
         THEN '>>> FLAGSHIP <<<'
         ELSE ''
    END                                                             AS store_flag,

    -- Month-over-month revenue change per store / 各门店环比营收变化
    ROUND(
        (SUM(k.total_revenue) - LAG(SUM(k.total_revenue)) OVER (
            PARTITION BY k.store_no
            ORDER BY DATE_FORMAT(k.metric_date, '%Y-%m')
        ))
        / NULLIF(LAG(SUM(k.total_revenue)) OVER (
            PARTITION BY k.store_no
            ORDER BY DATE_FORMAT(k.metric_date, '%Y-%m')
        ), 0) * 100, 1
    )                                                               AS mom_change_pct

FROM test.store_kpi_daily k
WHERE k.store_no IN ('US00001', 'US00003', 'US00004', 'US00005', 'US00006', 'US00008')
  AND k.metric_date >= '2025-07-01'
GROUP BY DATE_FORMAT(k.metric_date, '%Y-%m'), k.store_no, k.store_name
ORDER BY revenue_month, k.store_no;


-- ############################################################
-- SECTION 6b: Cannibalization Correlation Matrix
-- 第六部分(b)：蚕食相关性矩阵
-- ############################################################
-- Pivots monthly revenue into columns for visual correlation.
-- If 8th Ave revenue falls while nearby stores rise, this
-- supports the cannibalization hypothesis.
-- 将月度营收转成列式布局，便于视觉相关性分析。
-- 若第八大道营收下降而附近门店上升，则支持蚕食假设。
-- ############################################################

SELECT
    DATE_FORMAT(k.metric_date, '%Y-%m')                             AS month,

    -- 8th & Broadway (flagship) / 第八大道（旗舰店）
    ROUND(SUM(CASE WHEN k.store_no = 'US00001'
                   THEN k.total_revenue ELSE 0 END), 0)             AS `US00001_8th_Broadway`,

    -- Potential cannibalization stores / 可能的蚕食门店
    ROUND(SUM(CASE WHEN k.store_no = 'US00003'
                   THEN k.total_revenue ELSE 0 END), 0)             AS `US00003_100_Maiden`,
    ROUND(SUM(CASE WHEN k.store_no = 'US00004'
                   THEN k.total_revenue ELSE 0 END), 0)             AS `US00004_37th_Bway`,
    ROUND(SUM(CASE WHEN k.store_no = 'US00005'
                   THEN k.total_revenue ELSE 0 END), 0)             AS `US00005_54th_8th`,
    ROUND(SUM(CASE WHEN k.store_no = 'US00006'
                   THEN k.total_revenue ELSE 0 END), 0)             AS `US00006_102_Fulton`,
    ROUND(SUM(CASE WHEN k.store_no = 'US00008'
                   THEN k.total_revenue ELSE 0 END), 0)             AS `US00008_33rd_10th`,

    -- Network total (all 6 stores) / 网络总计（6家门店）
    ROUND(SUM(k.total_revenue), 0)                                  AS network_total,

    -- 8th Ave share of network / 第八大道占网络比重
    ROUND(
        SUM(CASE WHEN k.store_no = 'US00001' THEN k.total_revenue ELSE 0 END)
        / NULLIF(SUM(k.total_revenue), 0) * 100, 1
    )                                                               AS eighth_ave_share_pct

FROM test.store_kpi_daily k
WHERE k.store_no IN ('US00001', 'US00003', 'US00004', 'US00005', 'US00006', 'US00008')
  AND k.metric_date >= '2025-07-01'
GROUP BY DATE_FORMAT(k.metric_date, '%Y-%m')
ORDER BY month;


-- ############################################################
-- SECTION 7: Financial Impact Quantification
-- 第七部分：财务影响量化
-- ############################################################
-- Calculates the concrete dollar value of earlier detection:
--   - Weekly revenue loss rate during the decline
--   - Weeks of earlier detection SPC would have provided
--   - Potential savings = weeks_earlier x weekly_loss_rate
--   - Annualized impact estimate
-- 计算提前检测的具体美元价值：
--   - 下降期间每周营收损失率
--   - SPC能提前检测的周数
--   - 潜在节省 = 提前周数 × 每周损失率
--   - 年化影响估算
-- ############################################################

WITH weekly_revenue AS (
    -- Weekly revenue for 8th Ave / 第八大道周营收
    SELECT
        YEARWEEK(k.metric_date, 3)          AS iso_year_week,
        MIN(k.metric_date)                  AS week_start,
        ROUND(SUM(k.total_revenue), 2)      AS weekly_revenue
    FROM test.store_kpi_daily k
    WHERE k.store_id = 1127
      AND k.metric_date >= '2025-07-01'
    GROUP BY YEARWEEK(k.metric_date, 3)
),
peak_revenue AS (
    -- Peak weekly average (Oct 2025) / 峰值周均营收（2025年10月）
    SELECT ROUND(AVG(weekly_revenue), 2) AS peak_weekly_avg
    FROM weekly_revenue
    WHERE week_start BETWEEN '2025-10-01' AND '2025-10-31'
),
decline_period AS (
    -- Decline period: Nov 2025 through Jan 2026 / 下降期：2025年11月至2026年1月
    SELECT
        w.iso_year_week,
        w.week_start,
        w.weekly_revenue,
        p.peak_weekly_avg,
        ROUND(p.peak_weekly_avg - w.weekly_revenue, 2)              AS weekly_loss,
        ROUND((p.peak_weekly_avg - w.weekly_revenue)
              / NULLIF(p.peak_weekly_avg, 0) * 100, 1)             AS weekly_loss_pct
    FROM weekly_revenue w
    CROSS JOIN peak_revenue p
    WHERE w.week_start >= '2025-11-01'
      AND w.week_start <= '2026-01-31'
),
impact_summary AS (
    SELECT
        COUNT(*)                                    AS weeks_in_decline,
        ROUND(SUM(weekly_loss), 2)                  AS total_revenue_lost,
        ROUND(AVG(weekly_loss), 2)                  AS avg_weekly_loss,
        ROUND(MIN(weekly_loss), 2)                  AS min_weekly_loss,
        ROUND(MAX(weekly_loss), 2)                  AS max_weekly_loss,
        ROUND(AVG(weekly_loss_pct), 1)              AS avg_weekly_loss_pct
    FROM decline_period
    WHERE weekly_loss > 0
)
SELECT
    '8th & Broadway (US00001)'                      AS store,
    i.weeks_in_decline,
    i.total_revenue_lost                            AS total_lost_vs_peak,
    i.avg_weekly_loss,
    i.avg_weekly_loss_pct                           AS avg_weekly_decline_pct,

    -- Estimated earlier detection with SPC (target: 4-6 weeks) / SPC预估提前检测周数
    5                                               AS estimated_weeks_earlier,

    -- Potential savings: weeks_earlier * avg_weekly_loss
    -- 潜在节省：提前周数 × 每周平均损失
    ROUND(5 * i.avg_weekly_loss, 2)                 AS potential_savings_5wk,
    ROUND(4 * i.avg_weekly_loss, 2)                 AS potential_savings_4wk,
    ROUND(6 * i.avg_weekly_loss, 2)                 AS potential_savings_6wk,

    -- Annualized impact: if this pattern recurs at 1 store/year
    -- 年化影响：假设此模式每年在1家门店发生
    ROUND(i.total_revenue_lost * 4, 2)              AS annualized_if_4_stores,

    -- ROI note / 投资回报说明
    CONCAT(
        'Monitoring system cost ~$500/yr; potential savings $',
        FORMAT(ROUND(5 * i.avg_weekly_loss, 0), 0),
        '/incident; ROI = ',
        ROUND(5 * i.avg_weekly_loss / 500, 0),
        'x'
    )                                               AS roi_estimate

FROM impact_summary i;


-- ############################################################
-- SECTION 8: Anomaly Score Deep-Dive
-- 第八部分：异常评分深度分析
-- ############################################################
-- Pulls all anomaly scores for store 1127, metric=total_revenue,
-- showing z_score, Western Electric rule violations, severity
-- over time. Identifies the first CRITICAL alert date.
-- 提取门店1127的所有异常评分（指标=total_revenue），
-- 展示z分数、Western Electric规则违反、严重度随时间变化。
-- 标识首次CRITICAL预警日期。
-- ############################################################

-- 8a. Full anomaly score timeline / 完整异常评分时间线
SELECT
    a.metric_date,
    ROUND(a.metric_value, 2)                        AS daily_revenue,
    ROUND(a.rolling_mean_28d, 2)                    AS mean_28d,
    ROUND(a.rolling_std_28d, 2)                     AS std_28d,
    ROUND(a.z_score, 2)                             AS z_score,

    -- Control limits / 控制限
    ROUND(a.lcl_2sigma, 2)                          AS lcl_2sigma,
    ROUND(a.lcl_3sigma, 2)                          AS lcl_3sigma,
    ROUND(a.ucl_2sigma, 2)                          AS ucl_2sigma,
    ROUND(a.ucl_3sigma, 2)                          AS ucl_3sigma,

    -- Day-of-week adjusted score / 星期调整分数
    ROUND(a.dow_z_score, 2)                         AS dow_z_score,

    -- Western Electric rule violations / WE规则违反
    a.we_rule1                                      AS `WE1_3sigma`,
    a.we_rule2                                      AS `WE2_2of3_2sigma`,
    a.we_rule3                                      AS `WE3_4of5_1sigma`,
    a.we_rule4                                      AS `WE4_8_consec`,
    a.we_rule5                                      AS `WE5_6_decline`,

    -- Overall severity / 综合严重度
    a.anomaly_severity,

    -- Count of rules violated on this day / 当日违反规则数
    (IFNULL(a.we_rule1, 0) + IFNULL(a.we_rule2, 0) + IFNULL(a.we_rule3, 0)
     + IFNULL(a.we_rule4, 0) + IFNULL(a.we_rule5, 0))  AS rules_violated_count

FROM test.store_anomaly_scores a
WHERE a.store_id = 1127
  AND a.metric_name = 'total_revenue'
  AND a.metric_date >= '2025-09-01'           -- start from pre-decline peak period
ORDER BY a.metric_date;


-- 8b. First occurrence of each severity level / 各严重等级首次出现
-- Answers: "When would the SPC system have first flagged this store?"
-- 回答："SPC系统何时首次标记该门店？"

SELECT
    a.anomaly_severity,
    MIN(a.metric_date)                              AS first_occurrence,
    MAX(a.metric_date)                              AS most_recent,
    COUNT(*)                                        AS total_days_flagged,
    ROUND(AVG(a.z_score), 2)                        AS avg_z_score,
    ROUND(MIN(a.z_score), 2)                        AS worst_z_score
FROM test.store_anomaly_scores a
WHERE a.store_id = 1127
  AND a.metric_name = 'total_revenue'
  AND a.anomaly_severity <> 'NONE'
GROUP BY a.anomaly_severity
ORDER BY FIELD(a.anomaly_severity, 'INFO', 'WARNING', 'CRITICAL');


-- 8c. Western Electric Rule Activation Summary / WE规则触发汇总
-- Shows which rules fired first and how frequently, confirming
-- the expected pattern: Rule 4 (8 consecutive same side) should
-- fire early due to the sustained declining trend.
-- 展示各规则首次触发时间和频率，验证预期模式：
-- 规则4（连续8点同侧）应因持续下降趋势最早触发。

SELECT
    'WE Rule 1: Single point > 3-sigma'             AS rule_description,
    '单点超过3σ'                                      AS rule_cn,
    MIN(CASE WHEN a.we_rule1 = 1 THEN a.metric_date END) AS first_triggered,
    SUM(IFNULL(a.we_rule1, 0))                       AS days_triggered
FROM test.store_anomaly_scores a
WHERE a.store_id = 1127 AND a.metric_name = 'total_revenue'

UNION ALL

SELECT
    'WE Rule 2: 2 of 3 > 2-sigma (same side)',
    '3点中2点超过2σ（同侧）',
    MIN(CASE WHEN a.we_rule2 = 1 THEN a.metric_date END),
    SUM(IFNULL(a.we_rule2, 0))
FROM test.store_anomaly_scores a
WHERE a.store_id = 1127 AND a.metric_name = 'total_revenue'

UNION ALL

SELECT
    'WE Rule 3: 4 of 5 > 1-sigma (same side)',
    '5点中4点超过1σ（同侧）',
    MIN(CASE WHEN a.we_rule3 = 1 THEN a.metric_date END),
    SUM(IFNULL(a.we_rule3, 0))
FROM test.store_anomaly_scores a
WHERE a.store_id = 1127 AND a.metric_name = 'total_revenue'

UNION ALL

SELECT
    'WE Rule 4: 8 consecutive same side of center',
    '连续8点在中心线同侧',
    MIN(CASE WHEN a.we_rule4 = 1 THEN a.metric_date END),
    SUM(IFNULL(a.we_rule4, 0))
FROM test.store_anomaly_scores a
WHERE a.store_id = 1127 AND a.metric_name = 'total_revenue'

UNION ALL

SELECT
    'WE Rule 5: 6 consecutive declining',
    '连续6点递减',
    MIN(CASE WHEN a.we_rule5 = 1 THEN a.metric_date END),
    SUM(IFNULL(a.we_rule5, 0))
FROM test.store_anomaly_scores a
WHERE a.store_id = 1127 AND a.metric_name = 'total_revenue';


-- ############################################################
-- EXECUTIVE SUMMARY VIEW / 高管摘要视图
-- ############################################################
-- A single-row summary combining the key findings from all
-- sections above. Designed for inclusion in the management
-- proposal and Grafana annotation.
-- 单行摘要，汇总以上所有部分的关键发现。
-- 设计用于管理提案和Grafana标注。
-- ############################################################

SELECT
    -- Store identity / 门店信息
    '8th & Broadway'                                AS store_name,
    'US00001'                                       AS shop_no,
    1127                                            AS dept_id,
    '755 Broadway, New York, NY 10003'              AS address,

    -- Timeline / 时间线
    '2025-06-30'                                    AS opened_date,
    '2025-10'                                       AS peak_month,
    106397                                          AS peak_monthly_revenue,
    51837                                           AS jan_2026_revenue,
    ROUND((106397 - 51837) / 106397 * 100, 1)      AS peak_to_jan_decline_pct,

    -- SPC detection capability / SPC检测能力
    'TBD (run sections 2-3 for exact dates)'        AS spc_first_warning,
    'TBD (run sections 2-3 for exact dates)'        AS spc_first_critical,
    '~2026-01-15'                                   AS manual_discovery_date,
    '4-6 weeks (estimated)'                         AS earlier_detection_target,

    -- Financial impact / 财务影响
    ROUND((106397 - 51837) / 4.33, 2)              AS approx_weekly_loss_at_nadir,
    'Run Section 7 for precise calculation'         AS savings_calculation,

    -- Root cause hypothesis / 根因假设
    'Order volume decline (primary) + seasonal (contributing)'
                                                    AS primary_hypothesis,
    'US00004 37th & Broadway (opened Nov 2025) -- proximity cannibalization'
                                                    AS cannibalization_suspect,

    -- Action items / 行动项
    'Deploy UC-OP-02 SPC monitoring for all 10 stores'
                                                    AS recommended_action;


-- ============================================================
-- END OF CASE STUDY
-- 案例研究结束
-- ============================================================
-- Next Steps / 下一步:
--   1. Run each section above against aws-luckyus-dbatest-rw
--   2. Populate test.store_kpi_daily if not already done (see 05_daily_metrics_etl.sql)
--   3. Populate test.store_anomaly_scores (see 06_spc_control_limits.sql)
--   4. Update the Executive Summary with actual computed dates
--   5. Include results in the management proposal (proposal/ directory)
--
-- 使用说明：
--   1. 在 aws-luckyus-dbatest-rw 上逐段运行以上各部分
--   2. 如尚未填充 test.store_kpi_daily，先运行 05_daily_metrics_etl.sql
--   3. 填充 test.store_anomaly_scores（参见 06_spc_control_limits.sql）
--   4. 用实际计算日期更新高管摘要
--   5. 将结果纳入管理提案（proposal/ 目录）
-- ============================================================

-- ============================================================
-- UC-OP-02: Store Performance Anomaly Detection
-- File: 03_extract_revenue_kpis.sql
-- Source: aws-luckyus-salesorder-rw (luckyus_sales_order.t_order)
-- Target: aws-luckyus-dbatest-rw (test.store_kpi_daily)
-- Purpose: Extract daily revenue, order count, AOV per store
-- 提取每店每日营收、订单数、客单价
-- ============================================================
--
-- ARCHITECTURE NOTE / 架构说明:
--   Source and target live on DIFFERENT MySQL servers.
--   Cross-server JOINs are NOT possible.
--   The Python orchestrator handles data movement between servers:
--     1. Query source (salesorder-rw) -> pandas DataFrame
--     2. Enrich with store metadata (opshop-rw) -> merge in Python
--     3. Write results to target (dbatest-rw) -> INSERT/UPSERT
--
-- DATA NOTES / 数据说明:
--   - pay_money is in US dollars (NOT cents): typical values $3.60, $7.97
--   - status >= 20 means completed/paid orders
--   - 10 active US stores, dept_ids: 1127-1141, 20008-20011, 20046
--   - Data range: 2025-03-24 to present (~520K total orders)
--   - pay_money 字段单位为美元（非美分），典型值如 $3.60, $7.97
--   - status >= 20 表示已完成/已支付订单
--   - 共10家活跃美国门店
--   - 数据范围：2025-03-24 至今，约52万笔订单
--
-- COLUMN REFERENCE (t_order) / 字段参考:
--   shop_id      BIGINT       -- maps to dept_id in t_shop_info / 对应 t_shop_info.dept_id
--   shop_name    VARCHAR      -- store display name / 门店显示名称
--   total_money  DECIMAL(12,4)-- list price total / 标价总额
--   payable_money DECIMAL(12,4)-- amount due after discounts / 折后应付
--   pay_money    DECIMAL(12,4)-- actual USD paid / 实付金额（美元）
--   status       INT          -- 20 = completed/paid / 20=已完成/已支付
--   create_time  DATETIME     -- order creation time / 下单时间
--   pay_time     DATETIME     -- payment time / 支付时间
--   finish_time  DATETIME     -- completion time / 完成时间
--   refund_status INT         -- >0 means refund initiated / >0表示已发起退款
--   refund_time  DATETIME     -- refund timestamp / 退款时间
-- ============================================================


-- ############################################################
-- STEP 0: Create target table (run once on dbatest-rw)
-- 第0步：创建目标表（在 dbatest-rw 上执行一次）
-- ############################################################

CREATE TABLE IF NOT EXISTS test.store_kpi_daily (
    id              BIGINT AUTO_INCREMENT PRIMARY KEY,
    store_id        BIGINT        NOT NULL COMMENT 'shop_id from t_order / t_order中的shop_id',
    store_name      VARCHAR(100)  DEFAULT NULL COMMENT 'Store display name / 门店显示名称',
    store_no        VARCHAR(20)   DEFAULT NULL COMMENT 'Store number e.g. US00001 / 门店编号',
    metric_date     DATE          NOT NULL COMMENT 'Aggregation date / 汇总日期',
    total_revenue   DECIMAL(14,4) DEFAULT 0 COMMENT 'Sum of pay_money in USD / 实付总额（美元）',
    order_count     INT           DEFAULT 0 COMMENT 'Number of completed orders / 已完成订单数',
    avg_order_value DECIMAL(10,4) DEFAULT 0 COMMENT 'Average order value USD / 客单价（美元）',
    refund_count    INT           DEFAULT 0 COMMENT 'Orders with refund_status>0 / 有退款的订单数',
    refund_amount   DECIMAL(14,4) DEFAULT 0 COMMENT 'Total refund amount USD / 退款总额（美元）',
    day_of_week     TINYINT       DEFAULT NULL COMMENT '0=Mon..6=Sun (MySQL WEEKDAY) / 0=周一..6=周日',
    is_weekend      TINYINT(1)    DEFAULT 0 COMMENT '1 if Sat/Sun / 是否周末',
    created_at      DATETIME      DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME      DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_store_date (store_id, metric_date),
    KEY idx_metric_date (metric_date),
    KEY idx_store_id (store_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='UC-OP-02: Daily store revenue KPIs / 每日门店营收指标';


-- ############################################################
-- STEP 1: Verify source data / 验证源数据
-- Run on: aws-luckyus-salesorder-rw
-- 执行服务器：aws-luckyus-salesorder-rw
-- ############################################################

-- 1a. Overall data range and volume
-- 1a. 整体数据范围与数据量
SELECT
    MIN(create_time) AS earliest_order,
    MAX(create_time) AS latest_order,
    COUNT(*)         AS total_rows,
    COUNT(DISTINCT shop_id) AS distinct_stores
FROM luckyus_sales_order.t_order
WHERE status >= 20
  AND shop_id IN (1127, 1128, 1131, 1140, 1141, 20008, 20009, 20010, 20011, 20046);


-- 1b. Monthly order counts per store (spot-check volumes)
-- 1b. 每店每月订单量（抽查数据量）
SELECT
    shop_id,
    shop_name,
    DATE_FORMAT(create_time, '%Y-%m') AS order_month,
    COUNT(*)                          AS order_count,
    ROUND(SUM(pay_money), 2)          AS monthly_revenue,
    ROUND(AVG(pay_money), 2)          AS avg_order_value
FROM luckyus_sales_order.t_order
WHERE status >= 20
  AND shop_id IN (1127, 1128, 1131, 1140, 1141, 20008, 20009, 20010, 20011, 20046)
GROUP BY shop_id, shop_name, DATE_FORMAT(create_time, '%Y-%m')
ORDER BY shop_id, order_month;


-- 1c. Verify pay_money is in dollars (not cents) - sample values
-- 1c. 确认 pay_money 单位为美元（非美分）—— 抽样检查
SELECT
    shop_id,
    shop_name,
    pay_money,
    total_money,
    payable_money,
    create_time
FROM luckyus_sales_order.t_order
WHERE status >= 20
  AND shop_id = 1127
  AND pay_money > 0
ORDER BY create_time DESC
LIMIT 20;


-- ############################################################
-- STEP 2: Full historical extraction / 全量历史提取
-- Run on: aws-luckyus-salesorder-rw (read), result written to dbatest-rw
-- 执行：从 salesorder-rw 读取，结果写入 dbatest-rw
--
-- NOTE: This query is executed by the Python orchestrator.
-- The orchestrator fetches the result set, enriches with store_no
-- from opshop, then writes to test.store_kpi_daily via UPSERT.
-- 注意：此查询由 Python 编排器执行。编排器获取结果集后，
-- 从 opshop 补充 store_no，再通过 UPSERT 写入 test.store_kpi_daily。
-- ############################################################

-- 2a. Source extraction query (run on salesorder-rw)
-- 2a. 源数据提取查询（在 salesorder-rw 上执行）
SELECT
    o.shop_id                                        AS store_id,
    o.shop_name                                      AS store_name,
    -- store_no is joined in Python from opshop / store_no 由 Python 从 opshop 关联
    DATE(o.create_time)                              AS metric_date,
    ROUND(SUM(o.pay_money), 4)                       AS total_revenue,
    COUNT(*)                                         AS order_count,
    ROUND(AVG(o.pay_money), 4)                       AS avg_order_value,
    SUM(CASE WHEN o.refund_status > 0 THEN 1 ELSE 0 END) AS refund_count,
    WEEKDAY(DATE(o.create_time))                     AS day_of_week,
    CASE WHEN WEEKDAY(DATE(o.create_time)) >= 5
         THEN 1 ELSE 0 END                          AS is_weekend
FROM luckyus_sales_order.t_order o
WHERE o.status >= 20                               -- completed orders only / 仅已完成订单
  AND o.shop_id IN (
      1127,   -- US00001 "8th & Broadway"
      1128,   -- US00002
      1131,   -- US00000
      1140,   -- US00003
      1141,   -- US00005
      20008,  -- US00008
      20009,  -- US00007
      20010,  -- US00006
      20011,  -- US00004
      20046   -- US99998
  )
  AND o.pay_money > 0                              -- exclude zero-amount orders / 排除零金额订单
GROUP BY
    o.shop_id,
    o.shop_name,
    DATE(o.create_time)
ORDER BY
    o.shop_id,
    DATE(o.create_time);


-- 2b. UPSERT into target (run on dbatest-rw by orchestrator)
-- 2b. 写入目标表（由编排器在 dbatest-rw 上执行）
-- The orchestrator builds this INSERT from the DataFrame rows.
-- 编排器根据 DataFrame 行构建此 INSERT 语句。
INSERT INTO test.store_kpi_daily (
    store_id,
    store_name,
    store_no,
    metric_date,
    total_revenue,
    order_count,
    avg_order_value,
    refund_count,
    day_of_week,
    is_weekend
)
VALUES
    (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    -- Parameterized placeholders; orchestrator iterates DataFrame rows
    -- 参数化占位符；编排器遍历 DataFrame 行逐条插入
ON DUPLICATE KEY UPDATE
    store_name      = VALUES(store_name),
    store_no        = VALUES(store_no),
    total_revenue   = VALUES(total_revenue),
    order_count     = VALUES(order_count),
    avg_order_value = VALUES(avg_order_value),
    refund_count    = VALUES(refund_count),
    day_of_week     = VALUES(day_of_week),
    is_weekend      = VALUES(is_weekend),
    updated_at      = NOW();


-- ############################################################
-- STEP 3: Incremental update / 增量更新
-- Only extract data since last successful run.
-- 仅提取上次成功运行以来的新数据。
-- The orchestrator determines @last_run_date from:
--   SELECT MAX(metric_date) FROM test.store_kpi_daily
-- 编排器通过以下查询确定 @last_run_date：
--   SELECT MAX(metric_date) FROM test.store_kpi_daily
-- ############################################################

-- 3a. Get last loaded date (run on dbatest-rw)
-- 3a. 获取最后加载日期（在 dbatest-rw 上执行）
SELECT
    COALESCE(MAX(metric_date), '2025-03-01') AS last_loaded_date
FROM test.store_kpi_daily;


-- 3b. Incremental extraction (run on salesorder-rw)
-- 3b. 增量提取（在 salesorder-rw 上执行）
-- The orchestrator substitutes :last_loaded_date from step 3a.
-- 编排器将步骤 3a 的结果替换 :last_loaded_date 参数。
SELECT
    o.shop_id                                        AS store_id,
    o.shop_name                                      AS store_name,
    DATE(o.create_time)                              AS metric_date,
    ROUND(SUM(o.pay_money), 4)                       AS total_revenue,
    COUNT(*)                                         AS order_count,
    ROUND(AVG(o.pay_money), 4)                       AS avg_order_value,
    SUM(CASE WHEN o.refund_status > 0 THEN 1 ELSE 0 END) AS refund_count,
    WEEKDAY(DATE(o.create_time))                     AS day_of_week,
    CASE WHEN WEEKDAY(DATE(o.create_time)) >= 5
         THEN 1 ELSE 0 END                          AS is_weekend
FROM luckyus_sales_order.t_order o
WHERE o.status >= 20
  AND o.shop_id IN (1127, 1128, 1131, 1140, 1141, 20008, 20009, 20010, 20011, 20046)
  AND o.pay_money > 0
  AND DATE(o.create_time) >= :last_loaded_date       -- incremental filter / 增量过滤条件
GROUP BY
    o.shop_id,
    o.shop_name,
    DATE(o.create_time)
ORDER BY
    o.shop_id,
    DATE(o.create_time);

-- 3c. Re-process yesterday and today to capture late-arriving orders
-- 3c. 重新处理昨天和今天的数据以捕获延迟到达的订单
-- Late orders may have create_time slightly before midnight but settle later.
-- UPSERT handles idempotent re-load safely.
-- 延迟订单的 create_time 可能略早于午夜但稍后才结算。
-- UPSERT 确保重复加载的幂等性。
SELECT
    o.shop_id                                        AS store_id,
    o.shop_name                                      AS store_name,
    DATE(o.create_time)                              AS metric_date,
    ROUND(SUM(o.pay_money), 4)                       AS total_revenue,
    COUNT(*)                                         AS order_count,
    ROUND(AVG(o.pay_money), 4)                       AS avg_order_value,
    SUM(CASE WHEN o.refund_status > 0 THEN 1 ELSE 0 END) AS refund_count,
    WEEKDAY(DATE(o.create_time))                     AS day_of_week,
    CASE WHEN WEEKDAY(DATE(o.create_time)) >= 5
         THEN 1 ELSE 0 END                          AS is_weekend
FROM luckyus_sales_order.t_order o
WHERE o.status >= 20
  AND o.shop_id IN (1127, 1128, 1131, 1140, 1141, 20008, 20009, 20010, 20011, 20046)
  AND o.pay_money > 0
  AND DATE(o.create_time) >= DATE_SUB(CURDATE(), INTERVAL 1 DAY)
GROUP BY
    o.shop_id,
    o.shop_name,
    DATE(o.create_time)
ORDER BY
    o.shop_id,
    DATE(o.create_time);


-- ############################################################
-- STEP 4: Refund extraction / 退款数据提取
-- Separate query for refund amounts when refund details are needed.
-- 当需要退款详情时使用的独立查询。
-- ############################################################

-- 4a. Daily refund summary per store (run on salesorder-rw)
-- 4a. 每店每日退款汇总（在 salesorder-rw 上执行）
SELECT
    o.shop_id                                        AS store_id,
    o.shop_name                                      AS store_name,
    DATE(o.refund_time)                              AS refund_date,
    COUNT(*)                                         AS refund_count,
    ROUND(SUM(o.pay_money), 4)                       AS refund_amount,
    ROUND(AVG(o.pay_money), 4)                       AS avg_refund_value
FROM luckyus_sales_order.t_order o
WHERE o.refund_status > 0
  AND o.refund_time IS NOT NULL
  AND o.shop_id IN (1127, 1128, 1131, 1140, 1141, 20008, 20009, 20010, 20011, 20046)
GROUP BY
    o.shop_id,
    o.shop_name,
    DATE(o.refund_time)
ORDER BY
    o.shop_id,
    DATE(o.refund_time);


-- 4b. Update refund_amount in target table (run on dbatest-rw)
-- 4b. 更新目标表中的退款金额（在 dbatest-rw 上执行）
-- The orchestrator matches refund_date to metric_date and updates.
-- 编排器将 refund_date 匹配到 metric_date 并更新。
UPDATE test.store_kpi_daily
SET refund_amount = %s,
    updated_at    = NOW()
WHERE store_id    = %s
  AND metric_date = %s;


-- 4c. Refund rate analysis (diagnostic, run on dbatest-rw after load)
-- 4c. 退款率分析（诊断用，数据加载完成后在 dbatest-rw 上执行）
SELECT
    store_id,
    store_name,
    DATE_FORMAT(metric_date, '%Y-%m') AS month,
    SUM(order_count)                  AS total_orders,
    SUM(refund_count)                 AS total_refunds,
    ROUND(SUM(refund_count) / SUM(order_count) * 100, 2) AS refund_rate_pct,
    ROUND(SUM(refund_amount), 2)      AS total_refund_amount,
    ROUND(SUM(total_revenue), 2)      AS total_revenue,
    ROUND(SUM(refund_amount) / NULLIF(SUM(total_revenue), 0) * 100, 2) AS refund_value_pct
FROM test.store_kpi_daily
GROUP BY store_id, store_name, DATE_FORMAT(metric_date, '%Y-%m')
ORDER BY store_id, month;


-- ############################################################
-- STEP 5: Data quality checks / 数据质量检查
-- Run on: aws-luckyus-dbatest-rw (after data load)
-- 执行服务器：aws-luckyus-dbatest-rw（数据加载完成后）
-- ############################################################

-- 5a. Check for date gaps per store
-- 5a. 检查每店是否存在日期缺口
-- A gap means the store had zero completed orders that day (possible)
-- or data was not extracted (problem). Compare with known open dates.
-- 缺口可能表示当天该店无已完成订单（正常情况）或数据未提取（异常）。
-- 需与已知营业日期对比确认。
SELECT
    a.store_id,
    a.store_name,
    a.metric_date                              AS last_date_before_gap,
    b.metric_date                              AS first_date_after_gap,
    DATEDIFF(b.metric_date, a.metric_date) - 1 AS gap_days
FROM test.store_kpi_daily a
JOIN test.store_kpi_daily b
    ON  a.store_id = b.store_id
    AND b.metric_date = (
        SELECT MIN(c.metric_date)
        FROM test.store_kpi_daily c
        WHERE c.store_id = a.store_id
          AND c.metric_date > a.metric_date
    )
WHERE DATEDIFF(b.metric_date, a.metric_date) > 1
ORDER BY a.store_id, a.metric_date;


-- 5b. Check for zero-revenue days (should not happen for open stores)
-- 5b. 检查零营收日（营业门店不应出现）
SELECT
    store_id,
    store_name,
    metric_date,
    total_revenue,
    order_count
FROM test.store_kpi_daily
WHERE total_revenue <= 0
   OR order_count   <= 0
ORDER BY store_id, metric_date;


-- 5c. Check AOV is in reasonable range ($2 - $15 for Lucky stores)
-- 5c. 检查客单价是否在合理范围内（Lucky门店 $2-$15）
-- Values outside this range suggest data issues or unusual events.
-- 超出此范围的值可能提示数据问题或异常事件。
SELECT
    store_id,
    store_name,
    metric_date,
    avg_order_value,
    order_count,
    total_revenue,
    CASE
        WHEN avg_order_value < 2.00 THEN 'TOO_LOW: AOV < $2 / 客单价过低'
        WHEN avg_order_value > 15.00 THEN 'TOO_HIGH: AOV > $15 / 客单价过高'
        ELSE 'OK'
    END AS aov_check
FROM test.store_kpi_daily
WHERE avg_order_value < 2.00
   OR avg_order_value > 15.00
ORDER BY store_id, metric_date;


-- 5d. Row count summary by store (sanity check)
-- 5d. 每店行数汇总（合理性检查）
SELECT
    store_id,
    store_name,
    store_no,
    MIN(metric_date)     AS first_date,
    MAX(metric_date)     AS last_date,
    COUNT(*)             AS total_days,
    DATEDIFF(MAX(metric_date), MIN(metric_date)) + 1 AS expected_days,
    COUNT(*) - (DATEDIFF(MAX(metric_date), MIN(metric_date)) + 1) AS day_diff,
    ROUND(SUM(total_revenue), 2)  AS lifetime_revenue,
    SUM(order_count)              AS lifetime_orders,
    ROUND(SUM(total_revenue) / NULLIF(SUM(order_count), 0), 2) AS lifetime_aov
FROM test.store_kpi_daily
GROUP BY store_id, store_name, store_no
ORDER BY store_id;


-- 5e. Compare source vs target counts (cross-check)
-- 5e. 源表与目标表计数对比（交叉验证）
-- Run this on salesorder-rw, compare output with 5d above.
-- 在 salesorder-rw 上执行，将输出与上方 5d 对比。
SELECT
    shop_id                    AS store_id,
    shop_name                  AS store_name,
    MIN(DATE(create_time))     AS first_date,
    MAX(DATE(create_time))     AS last_date,
    COUNT(DISTINCT DATE(create_time)) AS total_days,
    COUNT(*)                   AS total_orders,
    ROUND(SUM(pay_money), 2)   AS total_revenue
FROM luckyus_sales_order.t_order
WHERE status >= 20
  AND shop_id IN (1127, 1128, 1131, 1140, 1141, 20008, 20009, 20010, 20011, 20046)
  AND pay_money > 0
GROUP BY shop_id, shop_name
ORDER BY shop_id;


-- ############################################################
-- STEP 6: 8th Avenue Spotlight / 第8大道门店专题分析
-- Store 1127 (US00001 "8th & Broadway") monthly revenue trend.
-- 门店 1127 (US00001 "8th & Broadway") 月度营收趋势。
--
-- Key finding: 51% decline from Oct 2025 peak to Jan 2026.
-- 关键发现：从2025年10月峰值到2026年1月下降了51%。
--
-- Expected output / 预期输出:
--   Jul 2025:  $76,918  (19,725 orders)
--   Aug 2025:  $86,661  (20,093 orders)
--   Sep 2025: $101,169  (22,622 orders)
--   Oct 2025: $106,397  (23,048 orders) <-- PEAK / 峰值
--   Nov 2025:  $86,101  (18,974 orders)  -19% from peak
--   Dec 2025:  $68,543  (14,152 orders)  -36% from peak
--   Jan 2026:  $51,837  (11,156 orders)  -51% from peak / 较峰值下降51%
-- ############################################################

-- 6a. Monthly trend for store 1127 (run on salesorder-rw)
-- 6a. 门店1127月度趋势（在 salesorder-rw 上执行）
SELECT
    o.shop_id,
    o.shop_name,
    DATE_FORMAT(o.create_time, '%Y-%m')               AS order_month,
    ROUND(SUM(o.pay_money), 2)                        AS monthly_revenue,
    COUNT(*)                                          AS order_count,
    ROUND(AVG(o.pay_money), 2)                        AS avg_order_value,
    SUM(CASE WHEN o.refund_status > 0 THEN 1 ELSE 0 END) AS refund_count
FROM luckyus_sales_order.t_order o
WHERE o.status >= 20
  AND o.shop_id = 1127
  AND o.pay_money > 0
GROUP BY o.shop_id, o.shop_name, DATE_FORMAT(o.create_time, '%Y-%m')
ORDER BY order_month;


-- 6b. Month-over-month change analysis (run on dbatest-rw after load)
-- 6b. 月环比变化分析（数据加载完成后在 dbatest-rw 上执行）
SELECT
    curr.month                                        AS current_month,
    curr.monthly_revenue,
    prev.monthly_revenue                              AS prev_month_revenue,
    ROUND(curr.monthly_revenue - prev.monthly_revenue, 2) AS revenue_change,
    ROUND((curr.monthly_revenue - prev.monthly_revenue)
          / NULLIF(prev.monthly_revenue, 0) * 100, 1) AS mom_change_pct,
    curr.order_count,
    prev.order_count                                  AS prev_order_count,
    ROUND((curr.order_count - prev.order_count)
          / NULLIF(prev.order_count, 0) * 100, 1)    AS order_mom_change_pct
FROM (
    SELECT
        DATE_FORMAT(metric_date, '%Y-%m') AS month,
        SUM(total_revenue)                AS monthly_revenue,
        SUM(order_count)                  AS order_count
    FROM test.store_kpi_daily
    WHERE store_id = 1127
    GROUP BY DATE_FORMAT(metric_date, '%Y-%m')
) curr
LEFT JOIN (
    SELECT
        DATE_FORMAT(metric_date, '%Y-%m') AS month,
        SUM(total_revenue)                AS monthly_revenue,
        SUM(order_count)                  AS order_count
    FROM test.store_kpi_daily
    WHERE store_id = 1127
    GROUP BY DATE_FORMAT(metric_date, '%Y-%m')
) prev
    ON prev.month = DATE_FORMAT(DATE_SUB(
           STR_TO_DATE(CONCAT(curr.month, '-01'), '%Y-%m-%d'),
           INTERVAL 1 MONTH), '%Y-%m')
ORDER BY curr.month;


-- 6c. Decline from peak calculation (run on dbatest-rw)
-- 6c. 较峰值下降幅度计算（在 dbatest-rw 上执行）
-- Compares each month to the Oct 2025 peak ($106,397)
-- 将每月与2025年10月峰值（$106,397）对比
SELECT
    DATE_FORMAT(metric_date, '%Y-%m')               AS month,
    ROUND(SUM(total_revenue), 2)                    AS monthly_revenue,
    SUM(order_count)                                AS order_count,
    ROUND(SUM(total_revenue) / NULLIF(SUM(order_count), 0), 2) AS avg_order_value,
    -- Compare to peak month / 与峰值月对比
    ROUND(SUM(total_revenue) - 106397, 2)           AS diff_from_peak,
    ROUND((SUM(total_revenue) - 106397)
          / 106397 * 100, 1)                        AS pct_from_peak
FROM test.store_kpi_daily
WHERE store_id = 1127
  AND metric_date >= '2025-07-01'
GROUP BY DATE_FORMAT(metric_date, '%Y-%m')
ORDER BY month;


-- 6d. Weekly granularity for recent decline investigation (salesorder-rw)
-- 6d. 近期下滑趋势的周粒度分析（在 salesorder-rw 上执行）
-- Helps identify if decline is gradual or has sharp drop-offs.
-- 帮助判断下滑是渐进式还是存在断崖式下跌。
SELECT
    o.shop_id,
    YEAR(o.create_time)                               AS yr,
    WEEK(o.create_time, 1)                            AS wk,
    MIN(DATE(o.create_time))                          AS week_start,
    MAX(DATE(o.create_time))                          AS week_end,
    ROUND(SUM(o.pay_money), 2)                        AS weekly_revenue,
    COUNT(*)                                          AS order_count,
    ROUND(AVG(o.pay_money), 2)                        AS avg_order_value
FROM luckyus_sales_order.t_order o
WHERE o.status >= 20
  AND o.shop_id = 1127
  AND o.pay_money > 0
  AND o.create_time >= '2025-10-01'
GROUP BY o.shop_id, YEAR(o.create_time), WEEK(o.create_time, 1)
ORDER BY yr, wk;


-- 6e. Weekday vs Weekend comparison for 1127 (dbatest-rw)
-- 6e. 门店1127工作日与周末对比分析（在 dbatest-rw 上执行）
-- Check if decline is uniform or concentrated on specific days.
-- 检查下滑是否均匀分布或集中在特定日期。
SELECT
    DATE_FORMAT(metric_date, '%Y-%m') AS month,
    is_weekend,
    CASE WHEN is_weekend = 1 THEN 'Weekend / 周末'
         ELSE 'Weekday / 工作日' END AS day_type,
    COUNT(*)                          AS num_days,
    ROUND(SUM(total_revenue), 2)      AS total_revenue,
    ROUND(AVG(total_revenue), 2)      AS avg_daily_revenue,
    SUM(order_count)                  AS total_orders,
    ROUND(AVG(order_count), 0)        AS avg_daily_orders
FROM test.store_kpi_daily
WHERE store_id = 1127
  AND metric_date >= '2025-07-01'
GROUP BY DATE_FORMAT(metric_date, '%Y-%m'), is_weekend
ORDER BY month, is_weekend;


-- ############################################################
-- USAGE NOTES / 使用说明
-- ############################################################
--
-- Execution order in Python orchestrator / Python 编排器执行顺序:
--   1. Run Step 0 (CREATE TABLE) on dbatest-rw if first run
--      第一次运行时在 dbatest-rw 上执行第0步（建表）
--   2. Run Step 3a on dbatest-rw to get last_loaded_date
--      在 dbatest-rw 上执行第3a步获取 last_loaded_date
--   3. Run Step 3b on salesorder-rw with last_loaded_date param
--      使用 last_loaded_date 参数在 salesorder-rw 上执行第3b步
--   4. Enrich with store_no from opshop server in Python
--      在 Python 中从 opshop 服务器补充 store_no
--   5. Run Step 2b UPSERT on dbatest-rw for each row
--      在 dbatest-rw 上对每行执行第2b步 UPSERT
--   6. Run Step 4a on salesorder-rw for refund data
--      在 salesorder-rw 上执行第4a步获取退款数据
--   7. Run Step 4b on dbatest-rw to update refund amounts
--      在 dbatest-rw 上执行第4b步更新退款金额
--   8. Run Step 5 quality checks on dbatest-rw
--      在 dbatest-rw 上执行第5步质量检查
--
-- Schedule: Daily at 06:00 UTC (after overnight order settlement)
-- 调度：每日 UTC 06:00（隔夜订单结算完成后）
--
-- Dependencies / 依赖:
--   - 01_create_tables.sql must have run (test.store_kpi_daily exists)
--     01_create_tables.sql 必须已执行（test.store_kpi_daily 已存在）
--   - Store metadata available from opshop server
--     门店元数据可从 opshop 服务器获取
--
-- ============================================================
-- END OF FILE / 文件结束
-- ============================================================

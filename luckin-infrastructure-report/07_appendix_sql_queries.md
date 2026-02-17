# Luckin Coffee USA - Database Infrastructure & AI Transformation Report

**Report:** Appendix — Reference SQL Queries for All 24 Tools
**Date:** February 13, 2026
**Prepared for:** Luckin Coffee USA Leadership Team

---

## 7. Appendix: Reference SQL Queries

> **Usage Notes:**
> - All queries target **read replicas** or read-only connections. Never run against `-rw` primary writers in production.
> - Default `LIMIT 100` applied per safety conventions. Remove or increase for full datasets.
> - Replace `CURDATE()` / `NOW()` with specific dates for historical analysis.
> - Timestamps are in server timezone (UTC) unless noted. Apply timezone conversion for local store reporting.
> - PII fields (phone, email) must be masked in application-layer output.

---

### Tool 1: Database Health Monitor

**Server:** All MySQL servers via `information_schema`

```sql
-- 1a. Table sizes across all databases on a given server
SELECT
    table_schema AS db_name,
    table_name,
    table_rows AS estimated_rows,
    ROUND(data_length / 1024 / 1024, 2) AS data_mb,
    ROUND(index_length / 1024 / 1024, 2) AS index_mb,
    ROUND((data_length + index_length) / 1024 / 1024, 2) AS total_mb,
    ROUND(data_free / 1024 / 1024, 2) AS fragmented_mb
FROM information_schema.tables
WHERE table_schema NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
ORDER BY (data_length + index_length) DESC
LIMIT 100;

-- 1b. Current active connections and long-running queries
SELECT
    id, user, host, db, command, time AS seconds,
    LEFT(info, 200) AS query_preview,
    state
FROM information_schema.processlist
WHERE command != 'Sleep'
  AND time > 5
ORDER BY time DESC
LIMIT 50;

-- 1c. Replication lag check (run on read replica)
SHOW SLAVE STATUS;

-- 1d. InnoDB buffer pool hit ratio
SELECT
    variable_name,
    variable_value
FROM performance_schema.global_status
WHERE variable_name IN (
    'Innodb_buffer_pool_read_requests',
    'Innodb_buffer_pool_reads',
    'Innodb_buffer_pool_pages_total',
    'Innodb_buffer_pool_pages_free',
    'Threads_connected',
    'Threads_running',
    'Slow_queries',
    'Questions'
);
```

---

### Tool 2: Multi-Tenant Data Isolation Auditor

**Server:** All MySQL servers

```sql
-- 2a. Identify tables lacking tenant isolation columns
SELECT
    table_schema,
    table_name,
    column_name
FROM information_schema.columns
WHERE table_schema LIKE 'luckyus_%'
  AND column_name IN ('tenant_id', 'org_id', 'company_id', 'brand_id')
ORDER BY table_schema, table_name
LIMIT 100;

-- 2b. Check for cross-tenant data leakage — NZD orders in USD context
SELECT
    currency,
    COUNT(*) AS order_count,
    ROUND(SUM(actual_amount) / 100, 2) AS total_revenue
FROM luckyus_sales_order.t_order
WHERE order_status IN (4, 5)
GROUP BY currency
LIMIT 10;

-- 2c. Detect non-US store data presence
SELECT
    s.shop_name,
    s.time_zone,
    COUNT(o.id) AS order_count
FROM luckyus_opshop.t_shop_info s
LEFT JOIN luckyus_sales_order.t_order o ON o.shop_id = s.id
WHERE s.time_zone NOT LIKE '%New_York%'
GROUP BY s.shop_name, s.time_zone
LIMIT 20;
```

---

### Tool 3: Redis Cluster Intelligence Console

**Redis Commands** (via `mcp-db-gateway` redis_command):

```
-- 3a. Check memory usage per Redis instance
INFO memory

-- 3b. Get key count and TTL distribution
DBSIZE

-- 3c. Scan for keys without TTL (memory leak candidates)
-- Run iteratively with SCAN cursor
SCAN 0 COUNT 100

-- 3d. Check specific key TTL
TTL <key_name>

-- 3e. Cluster info and connected clients
INFO clients
INFO stats
```

---

### Tool 4: Customer 360 Profile

**Servers:** `aws-luckyus-salescrm-rw`, `aws-luckyus-isalescdp-rw`, `aws-luckyus-salesorder-rw`

```sql
-- 4a. Customer profile with order history summary
SELECT
    u.id AS user_id,
    CONCAT('***', RIGHT(u.phone, 4)) AS masked_phone,
    u.create_time AS registered_at,
    us.user_state,
    COUNT(DISTINCT o.id) AS total_orders,
    ROUND(SUM(o.actual_amount) / 100, 2) AS lifetime_value,
    ROUND(AVG(o.actual_amount) / 100, 2) AS avg_order_value,
    MIN(o.create_time) AS first_order,
    MAX(o.create_time) AS last_order,
    DATEDIFF(NOW(), MAX(o.create_time)) AS days_since_last_order
FROM luckyus_sales_crm.t_user u
LEFT JOIN luckyus_isales_cdp.t_user_state us ON us.user_id = u.id
LEFT JOIN luckyus_sales_order.t_order o
    ON o.user_id = u.id
    AND o.order_status IN (4, 5)
    AND o.currency = 'USD'
WHERE u.id = ?  -- parameterized user_id
GROUP BY u.id, u.phone, u.create_time, us.user_state
LIMIT 1;

-- 4b. Customer segmentation by RFM (Recency, Frequency, Monetary)
SELECT
    CASE
        WHEN days_since < 7 AND order_count >= 10 THEN 'Champion'
        WHEN days_since < 14 AND order_count >= 5 THEN 'Loyal'
        WHEN days_since < 30 AND order_count >= 2 THEN 'Potential'
        WHEN days_since < 60 THEN 'At Risk'
        ELSE 'Lost'
    END AS segment,
    COUNT(*) AS user_count
FROM (
    SELECT
        o.user_id,
        DATEDIFF(NOW(), MAX(o.create_time)) AS days_since,
        COUNT(*) AS order_count,
        SUM(o.actual_amount) / 100 AS total_spend
    FROM luckyus_sales_order.t_order o
    WHERE o.order_status IN (4, 5)
      AND o.currency = 'USD'
    GROUP BY o.user_id
) rfm
GROUP BY segment
ORDER BY user_count DESC;
```

---

### Tool 5: Campaign Performance Analyzer

**Server:** `aws-luckyus-salesmarketing-rw`, `aws-luckyus-salesorder-rw`

```sql
-- 5a. Campaign/coupon template performance summary
SELECT
    ct.id AS template_id,
    ct.coupon_name,
    ct.coupon_type,
    COUNT(cr.id) AS coupons_issued,
    SUM(CASE WHEN cr.coupon_status = 2 THEN 1 ELSE 0 END) AS coupons_used,
    ROUND(SUM(CASE WHEN cr.coupon_status = 2 THEN 1 ELSE 0 END) / COUNT(cr.id) * 100, 2) AS redemption_rate_pct,
    ROUND(SUM(cr.coupon_amount) / 100, 2) AS total_discount_given
FROM luckyus_sales_marketing.t_coupon_template ct
JOIN luckyus_sales_marketing.t_coupon_record cr ON cr.template_id = ct.id
GROUP BY ct.id, ct.coupon_name, ct.coupon_type
ORDER BY coupons_issued DESC
LIMIT 50;

-- 5b. Coupon ROI — revenue influenced vs. discount cost
SELECT
    cr.template_id,
    COUNT(DISTINCT o.id) AS orders_with_coupon,
    ROUND(SUM(o.actual_amount) / 100, 2) AS revenue_with_coupon,
    ROUND(SUM(cr.coupon_amount) / 100, 2) AS discount_cost,
    ROUND(SUM(o.actual_amount) / 100 - SUM(cr.coupon_amount) / 100, 2) AS net_revenue
FROM luckyus_sales_marketing.t_coupon_record cr
JOIN luckyus_sales_order.t_order o ON o.coupon_id = cr.id
WHERE o.order_status IN (4, 5)
  AND o.currency = 'USD'
  AND cr.coupon_status = 2
GROUP BY cr.template_id
ORDER BY net_revenue DESC
LIMIT 30;
```

---

### Tool 6: Customer Acquisition Channel Tracker

**Server:** `aws-luckyus-salescrm-rw`, `aws-luckyus-salesorder-rw`

```sql
-- 6a. User registration by platform/channel
SELECT
    CASE
        WHEN register_source LIKE '%ios%' OR register_source LIKE '%iPhone%' THEN 'iOS'
        WHEN register_source LIKE '%android%' THEN 'Android'
        WHEN register_source LIKE '%web%' THEN 'Web'
        ELSE COALESCE(register_source, 'Unknown')
    END AS channel,
    COUNT(*) AS registrations,
    DATE(create_time) AS reg_date
FROM luckyus_sales_crm.t_user
WHERE create_time >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY channel, reg_date
ORDER BY reg_date DESC, registrations DESC
LIMIT 100;

-- 6b. Channel conversion — registration to first order
SELECT
    channel,
    registrations,
    first_orders,
    ROUND(first_orders / registrations * 100, 2) AS conversion_rate_pct
FROM (
    SELECT
        CASE
            WHEN u.register_source LIKE '%ios%' THEN 'iOS'
            WHEN u.register_source LIKE '%android%' THEN 'Android'
            ELSE 'Other'
        END AS channel,
        COUNT(DISTINCT u.id) AS registrations,
        COUNT(DISTINCT o.user_id) AS first_orders
    FROM luckyus_sales_crm.t_user u
    LEFT JOIN luckyus_sales_order.t_order o
        ON o.user_id = u.id
        AND o.order_status IN (4, 5)
        AND o.currency = 'USD'
    WHERE u.create_time >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
    GROUP BY channel
) sub
ORDER BY registrations DESC;
```

---

### Tool 7: Daily Revenue Reconciliation

**Servers:** `aws-luckyus-salesorder-rw`, `aws-luckyus-salespayment-rw`, `aws-luckyus-ifiaccounting-rw`

```sql
-- 7a. Three-way match: Orders ↔ Payments ↔ Accounting
SELECT
    'Orders' AS source,
    DATE(create_time) AS biz_date,
    COUNT(*) AS record_count,
    ROUND(SUM(actual_amount) / 100, 2) AS total_amount
FROM luckyus_sales_order.t_order
WHERE order_status IN (4, 5)
  AND currency = 'USD'
  AND DATE(create_time) = CURDATE() - INTERVAL 1 DAY
GROUP BY DATE(create_time)

UNION ALL

SELECT
    'Payments' AS source,
    DATE(create_time) AS biz_date,
    COUNT(*) AS record_count,
    ROUND(SUM(trade_amount) / 100, 2) AS total_amount
FROM luckyus_sales_payment.t_trade
WHERE trade_status = 1
  AND DATE(create_time) = CURDATE() - INTERVAL 1 DAY
GROUP BY DATE(create_time)

UNION ALL

SELECT
    'Accounting' AS source,
    DATE(create_time) AS biz_date,
    COUNT(*) AS record_count,
    ROUND(SUM(amount) / 100, 2) AS total_amount
FROM luckyus_ifiaccounting.t_acc_income_bill
WHERE DATE(create_time) = CURDATE() - INTERVAL 1 DAY
GROUP BY DATE(create_time);

-- 7b. Orphaned payments — trades with no matching order
SELECT
    t.id AS trade_id,
    t.order_no,
    ROUND(t.trade_amount / 100, 2) AS amount,
    t.create_time
FROM luckyus_sales_payment.t_trade t
LEFT JOIN luckyus_sales_order.t_order o ON o.order_no = t.order_no
WHERE o.id IS NULL
  AND t.trade_status = 1
  AND t.create_time >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
ORDER BY t.create_time DESC
LIMIT 50;
```

---

### Tool 8: Payment Channel Cost Optimizer

**Server:** `aws-luckyus-salespayment-rw`

```sql
-- 8a. Payment channel fee analysis
SELECT
    uc.channel_name,
    COUNT(t.id) AS transactions,
    ROUND(SUM(t.trade_amount) / 100, 2) AS total_volume,
    ROUND(SUM(cf.fee_amount) / 100, 2) AS total_fees,
    ROUND(SUM(cf.fee_amount) / SUM(t.trade_amount) * 100, 4) AS effective_rate_pct
FROM luckyus_sales_payment.t_trade t
JOIN luckyus_sales_payment.t_channel_fee cf ON cf.trade_id = t.id
JOIN luckyus_sales_payment.t_user_channel uc ON uc.id = t.channel_id
WHERE t.trade_status = 1
  AND t.create_time >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY uc.channel_name
ORDER BY total_fees DESC
LIMIT 20;

-- 8b. Fee anomalies — transactions where fee rate deviates from expected
SELECT
    t.id AS trade_id,
    t.order_no,
    ROUND(t.trade_amount / 100, 2) AS amount,
    ROUND(cf.fee_amount / 100, 2) AS fee,
    ROUND(cf.fee_amount / t.trade_amount * 100, 4) AS actual_rate_pct,
    t.create_time
FROM luckyus_sales_payment.t_trade t
JOIN luckyus_sales_payment.t_channel_fee cf ON cf.trade_id = t.id
WHERE t.trade_status = 1
  AND t.create_time >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
  AND (cf.fee_amount / t.trade_amount) > 0.035  -- flag rates above 3.5%
ORDER BY actual_rate_pct DESC
LIMIT 30;
```

---

### Tool 9: Tax Compliance Gap Tracker

**Server:** `aws-luckyus-fitax-rw`, `aws-luckyus-salesorder-rw`

```sql
-- 9a. Confirm tax tables are empty (critical compliance gap)
SELECT
    table_name,
    table_rows
FROM information_schema.tables
WHERE table_schema = 'luckyus_fi_tax'
ORDER BY table_name;

-- 9b. Tax amounts recorded in order data (check if tax is tracked at order level)
SELECT
    DATE(o.create_time) AS order_date,
    COUNT(*) AS orders,
    ROUND(SUM(oa.tax_amount) / 100, 2) AS total_tax_collected,
    ROUND(SUM(o.actual_amount) / 100, 2) AS total_revenue,
    ROUND(SUM(oa.tax_amount) / SUM(o.actual_amount) * 100, 2) AS effective_tax_rate_pct
FROM luckyus_sales_order.t_order o
JOIN luckyus_sales_order.t_order_amount oa ON oa.order_id = o.id
WHERE o.order_status IN (4, 5)
  AND o.currency = 'USD'
  AND o.create_time >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY DATE(o.create_time)
ORDER BY order_date DESC
LIMIT 31;

-- 9c. NYC sales tax compliance check (expected ~8.875%)
SELECT
    s.shop_name,
    COUNT(o.id) AS orders,
    ROUND(SUM(o.actual_amount) / 100, 2) AS revenue,
    ROUND(SUM(oa.tax_amount) / 100, 2) AS tax_collected,
    ROUND(SUM(oa.tax_amount) / SUM(o.actual_amount) * 100, 3) AS tax_rate_pct,
    ROUND(8.875 - SUM(oa.tax_amount) / SUM(o.actual_amount) * 100, 3) AS rate_gap_pct
FROM luckyus_sales_order.t_order o
JOIN luckyus_sales_order.t_order_amount oa ON oa.order_id = o.id
JOIN luckyus_opshop.t_shop_info s ON s.id = o.shop_id
WHERE o.order_status IN (4, 5)
  AND o.currency = 'USD'
  AND o.create_time >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY s.shop_name
ORDER BY rate_gap_pct DESC
LIMIT 20;
```

---

### Tool 10: Product Performance & Menu Analytics

**Server:** `aws-luckyus-salesorder-rw`, `aws-luckyus-scmcommodity-rw`

```sql
-- 10a. Product performance ranking with margin indicators
SELECT
    oi.spu_name AS product_name,
    c.category_name,
    COUNT(DISTINCT oi.order_id) AS orders,
    SUM(oi.item_count) AS units_sold,
    ROUND(SUM(oi.actual_amount) / 100, 2) AS revenue,
    ROUND(AVG(oi.actual_amount / oi.item_count) / 100, 2) AS avg_unit_price,
    ROUND(SUM(oi.original_amount - oi.actual_amount) / 100, 2) AS total_discounts
FROM luckyus_sales_order.t_order_item oi
JOIN luckyus_sales_order.t_order o ON o.id = oi.order_id
LEFT JOIN luckyus_scm_commodity.t_commodity_base_info c ON c.spu_code = oi.spu_code
WHERE o.order_status IN (4, 5)
  AND o.currency = 'USD'
  AND o.create_time >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY oi.spu_name, c.category_name
ORDER BY orders DESC
LIMIT 50;

-- 10b. Menu engineering matrix — stars, plowhorses, puzzles, dogs
SELECT
    product_name,
    orders,
    revenue,
    CASE
        WHEN orders >= avg_orders AND revenue / orders >= avg_price THEN 'Star'
        WHEN orders >= avg_orders AND revenue / orders < avg_price THEN 'Plowhorse'
        WHEN orders < avg_orders AND revenue / orders >= avg_price THEN 'Puzzle'
        ELSE 'Dog'
    END AS menu_category
FROM (
    SELECT
        oi.spu_name AS product_name,
        COUNT(DISTINCT oi.order_id) AS orders,
        ROUND(SUM(oi.actual_amount) / 100, 2) AS revenue,
        AVG(COUNT(DISTINCT oi.order_id)) OVER () AS avg_orders,
        AVG(SUM(oi.actual_amount) / COUNT(DISTINCT oi.order_id)) OVER () AS avg_price
    FROM luckyus_sales_order.t_order_item oi
    JOIN luckyus_sales_order.t_order o ON o.id = oi.order_id
    WHERE o.order_status IN (4, 5) AND o.currency = 'USD'
      AND o.create_time >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
    GROUP BY oi.spu_name
) scored
ORDER BY orders DESC
LIMIT 50;
```

---

### Tool 11: Customer Taste Profile & Recommendations

**Server:** `aws-luckyus-salesorder-rw`, `aws-luckyus-scmcommodity-rw`

```sql
-- 11a. Individual customer taste profile (ingredients/categories preferred)
SELECT
    o.user_id,
    c.category_name,
    oi.spu_name,
    COUNT(*) AS order_count,
    ROUND(COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY o.user_id) * 100, 1) AS pct_of_orders
FROM luckyus_sales_order.t_order o
JOIN luckyus_sales_order.t_order_item oi ON oi.order_id = o.id
LEFT JOIN luckyus_scm_commodity.t_commodity_base_info c ON c.spu_code = oi.spu_code
WHERE o.order_status IN (4, 5)
  AND o.currency = 'USD'
  AND o.user_id = ?  -- parameterized
GROUP BY o.user_id, c.category_name, oi.spu_name
ORDER BY order_count DESC
LIMIT 20;

-- 11b. Collaborative filtering — users who ordered X also ordered Y
SELECT
    oi2.spu_name AS also_ordered,
    COUNT(DISTINCT oi2.order_id) AS co_occurrence,
    COUNT(DISTINCT o2.user_id) AS unique_users
FROM luckyus_sales_order.t_order_item oi1
JOIN luckyus_sales_order.t_order o1 ON o1.id = oi1.order_id
JOIN luckyus_sales_order.t_order o2 ON o2.user_id = o1.user_id AND o2.id != o1.id
JOIN luckyus_sales_order.t_order_item oi2 ON oi2.order_id = o2.id
WHERE oi1.spu_name = 'Iced Coconut Latte'  -- anchor product
  AND o1.order_status IN (4, 5)
  AND o2.order_status IN (4, 5)
  AND o1.currency = 'USD'
  AND oi2.spu_name != oi1.spu_name
GROUP BY oi2.spu_name
ORDER BY co_occurrence DESC
LIMIT 15;
```

---

### Tool 12: Production Time Optimizer

**Server:** `aws-luckyus-opproduction-rw`

```sql
-- 12a. Average production time by store and product
SELECT
    p.shop_id,
    s.shop_name,
    p.commodity_name,
    COUNT(*) AS orders,
    ROUND(AVG(TIMESTAMPDIFF(SECOND, p.accept_time, p.done_time)), 1) AS avg_seconds,
    ROUND(MIN(TIMESTAMPDIFF(SECOND, p.accept_time, p.done_time)), 1) AS min_seconds,
    ROUND(MAX(TIMESTAMPDIFF(SECOND, p.accept_time, p.done_time)), 1) AS max_seconds,
    ROUND(STDDEV(TIMESTAMPDIFF(SECOND, p.accept_time, p.done_time)), 1) AS stddev_seconds
FROM luckyus_opproduction.t_production p
JOIN luckyus_opshop.t_shop_info s ON s.id = p.shop_id
WHERE p.accept_time IS NOT NULL
  AND p.done_time IS NOT NULL
  AND TIMESTAMPDIFF(SECOND, p.accept_time, p.done_time) BETWEEN 10 AND 1800  -- filter outliers
  AND p.create_time >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
GROUP BY p.shop_id, s.shop_name, p.commodity_name
ORDER BY avg_seconds DESC
LIMIT 50;

-- 12b. Production time outliers — potential quality/training issues
SELECT
    p.shop_id,
    s.shop_name,
    p.commodity_name,
    p.order_no,
    TIMESTAMPDIFF(SECOND, p.accept_time, p.done_time) AS production_seconds,
    p.accept_time,
    p.done_time
FROM luckyus_opproduction.t_production p
JOIN luckyus_opshop.t_shop_info s ON s.id = p.shop_id
WHERE TIMESTAMPDIFF(SECOND, p.accept_time, p.done_time) > 600  -- over 10 minutes
  AND p.accept_time IS NOT NULL
  AND p.done_time IS NOT NULL
  AND p.create_time >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
ORDER BY production_seconds DESC
LIMIT 30;
```

---

### Tool 13: Store Performance Command Center

**Servers:** `aws-luckyus-salesorder-rw`, `aws-luckyus-opshop-rw`, `aws-luckyus-opproduction-rw`

```sql
-- 13a. Daily store scoreboard
SELECT
    s.shop_name,
    DATE(o.create_time) AS biz_date,
    COUNT(DISTINCT o.id) AS orders,
    ROUND(SUM(o.actual_amount) / 100, 2) AS revenue,
    ROUND(AVG(o.actual_amount) / 100, 2) AS aov,
    COUNT(DISTINCT o.user_id) AS unique_customers,
    ROUND(AVG(TIMESTAMPDIFF(SECOND, p.accept_time, p.done_time)), 0) AS avg_prod_seconds
FROM luckyus_sales_order.t_order o
JOIN luckyus_opshop.t_shop_info s ON s.id = o.shop_id
LEFT JOIN luckyus_opproduction.t_production p ON p.order_no = o.order_no
WHERE o.order_status IN (4, 5)
  AND o.currency = 'USD'
  AND o.create_time >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
  AND (p.accept_time IS NULL OR TIMESTAMPDIFF(SECOND, p.accept_time, p.done_time) BETWEEN 10 AND 1800)
GROUP BY s.shop_name, DATE(o.create_time)
ORDER BY biz_date DESC, revenue DESC
LIMIT 100;

-- 13b. Hourly order heatmap by store (for staffing decisions)
SELECT
    s.shop_name,
    HOUR(o.create_time) AS hour_of_day,
    DAYNAME(o.create_time) AS day_name,
    COUNT(*) AS orders,
    ROUND(SUM(o.actual_amount) / 100, 2) AS revenue
FROM luckyus_sales_order.t_order o
JOIN luckyus_opshop.t_shop_info s ON s.id = o.shop_id
WHERE o.order_status IN (4, 5)
  AND o.currency = 'USD'
  AND o.create_time >= DATE_SUB(CURDATE(), INTERVAL 14 DAY)
GROUP BY s.shop_name, HOUR(o.create_time), DAYNAME(o.create_time)
ORDER BY s.shop_name, hour_of_day
LIMIT 100;
```

---

### Tool 14: IoT Machine Fleet Manager

**Server:** `aws-luckyus-iotplatform-rw`

```sql
-- 14a. Machine fleet status overview
SELECT
    d.device_name,
    d.shop_id,
    s.shop_name,
    d.device_type,
    d.online_status,
    d.last_online_time,
    TIMESTAMPDIFF(HOUR, d.last_online_time, NOW()) AS hours_since_online,
    d.create_time AS installed_date
FROM luckyus_iot_platform.t_device d
LEFT JOIN luckyus_opshop.t_shop_info s ON s.id = d.shop_id
ORDER BY hours_since_online DESC
LIMIT 100;

-- 14b. Cup order throughput by machine (production efficiency)
SELECT
    c.device_id,
    d.device_name,
    s.shop_name,
    DATE(c.create_time) AS biz_date,
    COUNT(*) AS cups_produced,
    ROUND(AVG(c.brew_time), 1) AS avg_brew_seconds
FROM luckyus_iot_platform.t_cup_order_info c
JOIN luckyus_iot_platform.t_device d ON d.id = c.device_id
LEFT JOIN luckyus_opshop.t_shop_info s ON s.id = d.shop_id
WHERE c.create_time >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
GROUP BY c.device_id, d.device_name, s.shop_name, DATE(c.create_time)
ORDER BY biz_date DESC, cups_produced DESC
LIMIT 100;
```

---

### Tool 15: Dynamic Staffing Optimizer

**Server:** `aws-luckyus-salesorder-rw`, `aws-luckyus-opproduction-rw`

```sql
-- 15a. Order volume patterns by store/hour/day for labor modeling
SELECT
    o.shop_id,
    s.shop_name,
    DAYOFWEEK(o.create_time) AS dow,
    HOUR(o.create_time) AS hour_of_day,
    COUNT(*) AS avg_orders,
    ROUND(AVG(TIMESTAMPDIFF(SECOND, p.accept_time, p.done_time)), 0) AS avg_prod_time
FROM luckyus_sales_order.t_order o
JOIN luckyus_opshop.t_shop_info s ON s.id = o.shop_id
LEFT JOIN luckyus_opproduction.t_production p ON p.order_no = o.order_no
WHERE o.order_status IN (4, 5)
  AND o.currency = 'USD'
  AND o.create_time >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
  AND (p.accept_time IS NULL OR TIMESTAMPDIFF(SECOND, p.accept_time, p.done_time) BETWEEN 10 AND 1800)
GROUP BY o.shop_id, s.shop_name, DAYOFWEEK(o.create_time), HOUR(o.create_time)
ORDER BY o.shop_id, dow, hour_of_day
LIMIT 100;

-- 15b. Peak vs. off-peak staffing need indicator
SELECT
    shop_name,
    hour_of_day,
    avg_orders,
    CASE
        WHEN avg_orders >= 50 THEN 'Peak — 3+ staff'
        WHEN avg_orders >= 25 THEN 'Medium — 2 staff'
        WHEN avg_orders >= 10 THEN 'Low — 1 staff'
        ELSE 'Minimal'
    END AS staffing_recommendation
FROM (
    SELECT
        s.shop_name,
        HOUR(o.create_time) AS hour_of_day,
        ROUND(COUNT(*) / COUNT(DISTINCT DATE(o.create_time)), 0) AS avg_orders
    FROM luckyus_sales_order.t_order o
    JOIN luckyus_opshop.t_shop_info s ON s.id = o.shop_id
    WHERE o.order_status IN (4, 5) AND o.currency = 'USD'
      AND o.create_time >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
    GROUP BY s.shop_name, HOUR(o.create_time)
) hourly
ORDER BY shop_name, hour_of_day
LIMIT 100;
```

---

### Tool 16: Intelligent Inventory Command Center

**Server:** `aws-luckyus-scm-shopstock-rw`

```sql
-- 16a. Current stock levels with low-stock alerts
SELECT
    gs.shop_id,
    s.shop_name,
    gs.goods_name,
    gs.current_stock,
    gs.safety_stock,
    CASE
        WHEN gs.current_stock <= 0 THEN 'STOCKOUT'
        WHEN gs.current_stock <= gs.safety_stock THEN 'LOW'
        WHEN gs.current_stock <= gs.safety_stock * 1.5 THEN 'WARNING'
        ELSE 'OK'
    END AS stock_status,
    gs.update_time AS last_updated
FROM luckyus_scm_shopstock.t_shop_goods_stock gs
JOIN luckyus_opshop.t_shop_info s ON s.id = gs.shop_id
WHERE gs.current_stock <= gs.safety_stock
ORDER BY stock_status, gs.current_stock ASC
LIMIT 100;

-- 16b. Daily consumption trend per item per store
SELECT
    shop_id,
    goods_name,
    DATE(create_time) AS consumption_date,
    SUM(change_quantity) AS daily_consumption
FROM luckyus_scm_shopstock.t_stock_change_mon  -- or appropriate day table
WHERE create_time >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
GROUP BY shop_id, goods_name, DATE(create_time)
ORDER BY shop_id, goods_name, consumption_date
LIMIT 100;
```

---

### Tool 17: Supplier Performance Tracker

**Server:** `aws-luckyus-scm-purchase-rw`

```sql
-- 17a. Supplier delivery performance
SELECT
    so.supplier_id,
    so.supplier_name,
    COUNT(so.id) AS total_orders,
    SUM(CASE WHEN so.ship_status = 3 THEN 1 ELSE 0 END) AS delivered,
    ROUND(AVG(DATEDIFF(so.actual_arrive_time, so.create_time)), 1) AS avg_delivery_days,
    SUM(CASE WHEN so.actual_arrive_time > so.expected_arrive_time THEN 1 ELSE 0 END) AS late_deliveries,
    ROUND(SUM(CASE WHEN so.actual_arrive_time > so.expected_arrive_time THEN 1 ELSE 0 END) /
          COUNT(so.id) * 100, 1) AS late_pct
FROM luckyus_scm_purchase.t_ship_order so
WHERE so.create_time >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
GROUP BY so.supplier_id, so.supplier_name
ORDER BY late_pct DESC
LIMIT 30;

-- 17b. Purchase order volume and cost by supplier
SELECT
    po.supplier_id,
    po.supplier_name,
    COUNT(po.id) AS purchase_orders,
    ROUND(SUM(po.total_amount) / 100, 2) AS total_spend,
    ROUND(AVG(po.total_amount) / 100, 2) AS avg_po_value
FROM luckyus_scm_purchase.t_purchase_order po
WHERE po.create_time >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
GROUP BY po.supplier_id, po.supplier_name
ORDER BY total_spend DESC
LIMIT 20;
```

---

### Tool 18: Demand Forecasting Accuracy Monitor

**Server:** `aws-luckyus-ireplenishment-rw`, `aws-luckyus-salesorder-rw`

```sql
-- 18a. Forecast accuracy — predicted vs. actual daily demand
SELECT
    pred.shop_id,
    s.shop_name,
    pred.goods_code,
    pred.predict_date,
    pred.predict_demand AS forecasted,
    COALESCE(actual.actual_demand, 0) AS actual,
    ABS(pred.predict_demand - COALESCE(actual.actual_demand, 0)) AS abs_error,
    CASE
        WHEN COALESCE(actual.actual_demand, 0) = 0 THEN NULL
        ELSE ROUND(ABS(pred.predict_demand - actual.actual_demand)
                   / actual.actual_demand * 100, 2)
    END AS mape_pct
FROM luckyus_ireplenishment.wh_goods_daily_demand_pred pred
JOIN luckyus_opshop.t_shop_info s ON s.id = pred.shop_id
LEFT JOIN (
    SELECT
        shop_id,
        spu_code AS goods_code,
        DATE(create_time) AS order_date,
        SUM(item_count) AS actual_demand
    FROM luckyus_sales_order.t_order_item oi
    JOIN luckyus_sales_order.t_order o ON o.id = oi.order_id
    WHERE o.order_status IN (4, 5) AND o.currency = 'USD'
    GROUP BY shop_id, spu_code, DATE(create_time)
) actual ON actual.shop_id = pred.shop_id
         AND actual.goods_code = pred.goods_code
         AND actual.order_date = pred.predict_date
WHERE pred.predict_date BETWEEN DATE_SUB(CURDATE(), INTERVAL 7 DAY) AND CURDATE() - INTERVAL 1 DAY
ORDER BY mape_pct DESC
LIMIT 100;

-- 18b. Aggregate forecast accuracy by store (MAPE)
SELECT
    pred.shop_id,
    s.shop_name,
    COUNT(*) AS predictions,
    ROUND(AVG(CASE
        WHEN COALESCE(actual.actual_demand, 0) = 0 THEN NULL
        ELSE ABS(pred.predict_demand - actual.actual_demand) / actual.actual_demand * 100
    END), 2) AS mape_pct,
    ROUND(AVG(pred.predict_demand - COALESCE(actual.actual_demand, 0)), 2) AS avg_bias
FROM luckyus_ireplenishment.wh_goods_daily_demand_pred pred
JOIN luckyus_opshop.t_shop_info s ON s.id = pred.shop_id
LEFT JOIN (
    SELECT shop_id, spu_code, DATE(create_time) AS d,
           SUM(item_count) AS actual_demand
    FROM luckyus_sales_order.t_order_item oi
    JOIN luckyus_sales_order.t_order o ON o.id = oi.order_id
    WHERE o.order_status IN (4, 5) AND o.currency = 'USD'
    GROUP BY shop_id, spu_code, DATE(create_time)
) actual ON actual.shop_id = pred.shop_id
         AND actual.spu_code = pred.goods_code
         AND actual.d = pred.predict_date
WHERE pred.predict_date BETWEEN DATE_SUB(CURDATE(), INTERVAL 30 DAY) AND CURDATE() - INTERVAL 1 DAY
GROUP BY pred.shop_id, s.shop_name
ORDER BY mape_pct DESC
LIMIT 20;
```

---

### Tool 19: Natural Language Data Query Interface ("Ask Lucky")

**Infrastructure queries — not end-user SQL. These support the text-to-SQL engine.**

```sql
-- 19a. Schema metadata export for LLM context (used by text-to-SQL)
SELECT
    table_schema AS db_name,
    table_name,
    column_name,
    data_type,
    column_comment,
    is_nullable,
    column_key
FROM information_schema.columns
WHERE table_schema LIKE 'luckyus_%'
  AND table_schema NOT IN ('luckyus_fi_tax', 'luckyus_isalesmembermarketing')
ORDER BY table_schema, table_name, ordinal_position
LIMIT 5000;

-- 19b. Table row counts for query planner hints
SELECT
    table_schema,
    table_name,
    table_rows AS estimated_rows,
    table_comment
FROM information_schema.tables
WHERE table_schema LIKE 'luckyus_%'
  AND table_rows > 0
ORDER BY table_rows DESC
LIMIT 200;

-- 19c. Sample question → generated SQL mapping (template library)
-- "How many orders did 8th & Broadway do yesterday?"
SELECT COUNT(*) AS order_count
FROM luckyus_sales_order.t_order o
JOIN luckyus_opshop.t_shop_info s ON s.id = o.shop_id
WHERE s.shop_name LIKE '%8th%Broadway%'
  AND o.order_status IN (4, 5) AND o.currency = 'USD'
  AND DATE(o.create_time) = CURDATE() - INTERVAL 1 DAY;
```

---

### Tool 20: Executive Daily Briefing AI

**Servers:** Multiple — aggregated pipeline queries

```sql
-- 20a. Yesterday's KPI snapshot (core briefing data)
SELECT
    -- Revenue
    (SELECT ROUND(SUM(actual_amount) / 100, 2)
     FROM luckyus_sales_order.t_order
     WHERE order_status IN (4, 5) AND currency = 'USD'
       AND DATE(create_time) = CURDATE() - INTERVAL 1 DAY) AS yesterday_revenue,

    -- Orders
    (SELECT COUNT(*)
     FROM luckyus_sales_order.t_order
     WHERE order_status IN (4, 5) AND currency = 'USD'
       AND DATE(create_time) = CURDATE() - INTERVAL 1 DAY) AS yesterday_orders,

    -- New users
    (SELECT COUNT(*)
     FROM luckyus_sales_crm.t_user
     WHERE DATE(create_time) = CURDATE() - INTERVAL 1 DAY) AS new_registrations,

    -- Machine alerts
    (SELECT COUNT(*)
     FROM luckyus_iot_platform.t_device
     WHERE online_status = 0) AS offline_machines,

    -- Stockout items
    (SELECT COUNT(DISTINCT CONCAT(shop_id, '-', goods_code))
     FROM luckyus_scm_shopstock.t_shop_goods_stock
     WHERE current_stock <= 0) AS stockout_items;

-- 20b. Yesterday vs. same day last week comparison
SELECT
    'Yesterday' AS period,
    COUNT(*) AS orders,
    ROUND(SUM(actual_amount) / 100, 2) AS revenue,
    ROUND(AVG(actual_amount) / 100, 2) AS aov
FROM luckyus_sales_order.t_order
WHERE order_status IN (4, 5) AND currency = 'USD'
  AND DATE(create_time) = CURDATE() - INTERVAL 1 DAY

UNION ALL

SELECT
    'Same Day Last Week' AS period,
    COUNT(*) AS orders,
    ROUND(SUM(actual_amount) / 100, 2) AS revenue,
    ROUND(AVG(actual_amount) / 100, 2) AS aov
FROM luckyus_sales_order.t_order
WHERE order_status IN (4, 5) AND currency = 'USD'
  AND DATE(create_time) = CURDATE() - INTERVAL 8 DAY;
```

---

### Tool 21: Expansion Site Scoring Simulator

**Servers:** `aws-luckyus-opshop-rw`, `aws-luckyus-salesorder-rw`

```sql
-- 21a. Existing store performance benchmarks for model calibration
SELECT
    s.id AS shop_id,
    s.shop_name,
    s.latitude,
    s.longitude,
    s.create_time AS opened_date,
    DATEDIFF(NOW(), s.create_time) AS days_open,
    COUNT(o.id) AS total_orders,
    ROUND(SUM(o.actual_amount) / 100, 2) AS total_revenue,
    ROUND(SUM(o.actual_amount) / 100 / GREATEST(DATEDIFF(NOW(), s.create_time), 1), 2)
        AS daily_revenue,
    COUNT(DISTINCT o.user_id) AS unique_customers,
    ROUND(AVG(o.actual_amount) / 100, 2) AS aov
FROM luckyus_opshop.t_shop_info s
LEFT JOIN luckyus_sales_order.t_order o
    ON o.shop_id = s.id
    AND o.order_status IN (4, 5) AND o.currency = 'USD'
WHERE s.shop_status = 1  -- active stores
GROUP BY s.id, s.shop_name, s.latitude, s.longitude, s.create_time
ORDER BY total_revenue DESC
LIMIT 20;

-- 21b. Revenue ramp curve — monthly revenue by store age
SELECT
    s.shop_name,
    TIMESTAMPDIFF(MONTH, s.create_time, o.create_time) AS months_since_open,
    COUNT(o.id) AS orders,
    ROUND(SUM(o.actual_amount) / 100, 2) AS monthly_revenue
FROM luckyus_sales_order.t_order o
JOIN luckyus_opshop.t_shop_info s ON s.id = o.shop_id
WHERE o.order_status IN (4, 5) AND o.currency = 'USD'
GROUP BY s.shop_name, TIMESTAMPDIFF(MONTH, s.create_time, o.create_time)
ORDER BY s.shop_name, months_since_open
LIMIT 100;
```

---

### Tool 22: Unified Compliance & Audit Platform

**Servers:** Multiple databases

```sql
-- 22a. Compliance scorecard — data completeness checks
SELECT
    'Tax Records' AS check_name,
    (SELECT COUNT(*) FROM information_schema.tables
     WHERE table_schema = 'luckyus_fi_tax' AND table_rows > 0) AS tables_with_data,
    CASE WHEN (SELECT COUNT(*) FROM information_schema.tables
               WHERE table_schema = 'luckyus_fi_tax' AND table_rows > 0) = 0
         THEN 'FAIL' ELSE 'PASS' END AS status

UNION ALL

SELECT
    'Payment-Order Match' AS check_name,
    (SELECT COUNT(*) FROM luckyus_sales_payment.t_trade t
     LEFT JOIN luckyus_sales_order.t_order o ON o.order_no = t.order_no
     WHERE o.id IS NULL AND t.trade_status = 1
       AND t.create_time >= DATE_SUB(CURDATE(), INTERVAL 1 DAY)) AS orphan_count,
    CASE WHEN (SELECT COUNT(*) FROM luckyus_sales_payment.t_trade t
               LEFT JOIN luckyus_sales_order.t_order o ON o.order_no = t.order_no
               WHERE o.id IS NULL AND t.trade_status = 1
                 AND t.create_time >= DATE_SUB(CURDATE(), INTERVAL 1 DAY)) = 0
         THEN 'PASS' ELSE 'FAIL' END AS status

UNION ALL

SELECT
    'Production Time Outliers' AS check_name,
    (SELECT COUNT(*) FROM luckyus_opproduction.t_production
     WHERE TIMESTAMPDIFF(SECOND, accept_time, done_time) > 1800
       AND create_time >= DATE_SUB(CURDATE(), INTERVAL 1 DAY)) AS outlier_count,
    CASE WHEN (SELECT COUNT(*) FROM luckyus_opproduction.t_production
               WHERE TIMESTAMPDIFF(SECOND, accept_time, done_time) > 1800
                 AND create_time >= DATE_SUB(CURDATE(), INTERVAL 1 DAY)) <= 5
         THEN 'PASS' ELSE 'WARNING' END AS status;

-- 22b. Financial three-way match audit
SELECT
    o.order_no,
    ROUND(o.actual_amount / 100, 2) AS order_amount,
    ROUND(t.trade_amount / 100, 2) AS payment_amount,
    ROUND(a.amount / 100, 2) AS accounting_amount,
    CASE
        WHEN t.id IS NULL THEN 'MISSING PAYMENT'
        WHEN a.id IS NULL THEN 'MISSING ACCOUNTING'
        WHEN ABS(o.actual_amount - t.trade_amount) > 1 THEN 'AMOUNT MISMATCH'
        ELSE 'MATCHED'
    END AS match_status
FROM luckyus_sales_order.t_order o
LEFT JOIN luckyus_sales_payment.t_trade t ON t.order_no = o.order_no AND t.trade_status = 1
LEFT JOIN luckyus_ifiaccounting.t_acc_income_bill a ON a.order_no = o.order_no
WHERE o.order_status IN (4, 5) AND o.currency = 'USD'
  AND o.create_time >= DATE_SUB(CURDATE(), INTERVAL 1 DAY)
  AND (t.id IS NULL OR a.id IS NULL OR ABS(o.actual_amount - t.trade_amount) > 1)
ORDER BY o.create_time DESC
LIMIT 50;
```

---

### Tool 23: Cross-Timezone Operations Hub

**Servers:** `aws-luckyus-opshop-rw`, `aws-luckyus-salesorder-rw`

```sql
-- 23a. Identify timezone distribution across stores
SELECT
    s.shop_name,
    s.time_zone,
    s.shop_status,
    COUNT(o.id) AS total_orders,
    o.currency
FROM luckyus_opshop.t_shop_info s
LEFT JOIN luckyus_sales_order.t_order o ON o.shop_id = s.id AND o.order_status IN (4, 5)
GROUP BY s.shop_name, s.time_zone, s.shop_status, o.currency
ORDER BY s.time_zone, s.shop_name
LIMIT 30;

-- 23b. Timezone-normalized daily reporting (UTC to local)
SELECT
    s.shop_name,
    s.time_zone,
    DATE(CONVERT_TZ(o.create_time, '+00:00',
        CASE
            WHEN s.time_zone LIKE '%New_York%' THEN '-05:00'
            WHEN s.time_zone LIKE '%Rarotonga%' THEN '-10:00'
            ELSE '+00:00'
        END
    )) AS local_biz_date,
    COUNT(*) AS orders,
    ROUND(SUM(o.actual_amount) / 100, 2) AS revenue,
    o.currency
FROM luckyus_sales_order.t_order o
JOIN luckyus_opshop.t_shop_info s ON s.id = o.shop_id
WHERE o.order_status IN (4, 5)
  AND o.create_time >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
GROUP BY s.shop_name, s.time_zone, local_biz_date, o.currency
ORDER BY local_biz_date DESC, s.shop_name
LIMIT 100;
```

---

### Tool 24: AI-Powered Anomaly Detection System

**Servers:** Multiple — baseline and deviation queries

```sql
-- 24a. Revenue anomaly detection — z-score per store per day
SELECT
    shop_name,
    biz_date,
    daily_revenue,
    avg_30d,
    stddev_30d,
    ROUND((daily_revenue - avg_30d) / NULLIF(stddev_30d, 0), 2) AS z_score,
    CASE
        WHEN ABS((daily_revenue - avg_30d) / NULLIF(stddev_30d, 0)) > 3 THEN 'CRITICAL'
        WHEN ABS((daily_revenue - avg_30d) / NULLIF(stddev_30d, 0)) > 2 THEN 'WARNING'
        ELSE 'NORMAL'
    END AS anomaly_status
FROM (
    SELECT
        s.shop_name,
        DATE(o.create_time) AS biz_date,
        ROUND(SUM(o.actual_amount) / 100, 2) AS daily_revenue,
        ROUND(AVG(SUM(o.actual_amount) / 100) OVER (
            PARTITION BY s.shop_name
            ORDER BY DATE(o.create_time)
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ), 2) AS avg_30d,
        ROUND(STDDEV(SUM(o.actual_amount) / 100) OVER (
            PARTITION BY s.shop_name
            ORDER BY DATE(o.create_time)
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ), 2) AS stddev_30d
    FROM luckyus_sales_order.t_order o
    JOIN luckyus_opshop.t_shop_info s ON s.id = o.shop_id
    WHERE o.order_status IN (4, 5) AND o.currency = 'USD'
      AND o.create_time >= DATE_SUB(CURDATE(), INTERVAL 60 DAY)
    GROUP BY s.shop_name, DATE(o.create_time)
) scored
WHERE biz_date >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
ORDER BY ABS(z_score) DESC
LIMIT 50;

-- 24b. Refund rate anomaly — flag spikes in refund activity
SELECT
    DATE(o.create_time) AS biz_date,
    s.shop_name,
    COUNT(*) AS total_orders,
    SUM(CASE WHEN o.order_status = 6 THEN 1 ELSE 0 END) AS refunded_orders,
    ROUND(SUM(CASE WHEN o.order_status = 6 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2)
        AS refund_rate_pct
FROM luckyus_sales_order.t_order o
JOIN luckyus_opshop.t_shop_info s ON s.id = o.shop_id
WHERE o.currency = 'USD'
  AND o.create_time >= DATE_SUB(CURDATE(), INTERVAL 14 DAY)
GROUP BY DATE(o.create_time), s.shop_name
HAVING refund_rate_pct > 5  -- flag when refund rate exceeds 5%
ORDER BY refund_rate_pct DESC
LIMIT 30;

-- 24c. Production time anomaly — sudden slowdown detection
SELECT
    s.shop_name,
    DATE(p.create_time) AS biz_date,
    ROUND(AVG(TIMESTAMPDIFF(SECOND, p.accept_time, p.done_time)), 0) AS avg_prod_seconds,
    COUNT(*) AS items_produced,
    CASE
        WHEN AVG(TIMESTAMPDIFF(SECOND, p.accept_time, p.done_time)) > 400 THEN 'CRITICAL'
        WHEN AVG(TIMESTAMPDIFF(SECOND, p.accept_time, p.done_time)) > 300 THEN 'WARNING'
        ELSE 'NORMAL'
    END AS status
FROM luckyus_opproduction.t_production p
JOIN luckyus_opshop.t_shop_info s ON s.id = p.shop_id
WHERE p.accept_time IS NOT NULL AND p.done_time IS NOT NULL
  AND TIMESTAMPDIFF(SECOND, p.accept_time, p.done_time) BETWEEN 10 AND 1800
  AND p.create_time >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
GROUP BY s.shop_name, DATE(p.create_time)
HAVING avg_prod_seconds > 300
ORDER BY avg_prod_seconds DESC
LIMIT 30;

-- 24d. Inventory consumption anomaly — sales vs. stock usage mismatch
SELECT
    gs.shop_id,
    s.shop_name,
    gs.goods_name,
    gs.current_stock,
    COALESCE(sales.units_sold, 0) AS units_sold_yesterday,
    CASE
        WHEN gs.current_stock > 0 AND COALESCE(sales.units_sold, 0) = 0
             AND gs.current_stock < gs.safety_stock THEN 'LOW STOCK NO SALES'
        WHEN COALESCE(sales.units_sold, 0) > gs.current_stock * 2 THEN 'CONSUMPTION SPIKE'
        ELSE 'NORMAL'
    END AS anomaly_type
FROM luckyus_scm_shopstock.t_shop_goods_stock gs
JOIN luckyus_opshop.t_shop_info s ON s.id = gs.shop_id
LEFT JOIN (
    SELECT o.shop_id, oi.spu_code, SUM(oi.item_count) AS units_sold
    FROM luckyus_sales_order.t_order_item oi
    JOIN luckyus_sales_order.t_order o ON o.id = oi.order_id
    WHERE o.order_status IN (4, 5) AND o.currency = 'USD'
      AND DATE(o.create_time) = CURDATE() - INTERVAL 1 DAY
    GROUP BY o.shop_id, oi.spu_code
) sales ON sales.shop_id = gs.shop_id AND sales.spu_code = gs.goods_code
WHERE anomaly_type != 'NORMAL'
ORDER BY anomaly_type
LIMIT 50;
```

---

## Quick Reference: Database → Server Mapping

| Database | MySQL Server Name |
|----------|------------------|
| `luckyus_sales_order` | `aws-luckyus-salesorder-rw` |
| `luckyus_sales_payment` | `aws-luckyus-salespayment-rw` |
| `luckyus_sales_crm` | `aws-luckyus-salescrm-rw` |
| `luckyus_sales_marketing` | `aws-luckyus-salesmarketing-rw` |
| `luckyus_isales_cdp` | `aws-luckyus-isalescdp-rw` |
| `luckyus_isalesdatamarketing` | `aws-luckyus-isalesdatamarketing-rw` |
| `luckyus_opshop` | `aws-luckyus-opshop-rw` |
| `luckyus_opproduction` | `aws-luckyus-opproduction-rw` |
| `luckyus_iot_platform` | `aws-luckyus-iotplatform-rw` |
| `luckyus_scm_commodity` | `aws-luckyus-scmcommodity-rw` |
| `luckyus_scm_shopstock` | `aws-luckyus-scm-shopstock-rw` |
| `luckyus_scm_purchase` | `aws-luckyus-scm-purchase-rw` |
| `luckyus_ireplenishment` | `aws-luckyus-ireplenishment-rw` |
| `luckyus_ifiaccounting` | `aws-luckyus-ifiaccounting-rw` |
| `luckyus_fi_tax` | `aws-luckyus-fitax-rw` |
| `luckyus_dify_api` | `aws-luckyus-dify-rw` (PostgreSQL) |
| `luckyus_ilkmap` | `aws-luckyus-pgilkmap-rw` (PostgreSQL) |

---

## Common Query Patterns

### Date Filtering
```sql
-- Yesterday
WHERE DATE(create_time) = CURDATE() - INTERVAL 1 DAY

-- Last 7 days
WHERE create_time >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)

-- Last 30 days
WHERE create_time >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)

-- Specific month
WHERE create_time >= '2026-01-01' AND create_time < '2026-02-01'
```

### USD-Only Order Filtering
```sql
-- Always filter out NZD test data
WHERE o.order_status IN (4, 5)   -- completed orders
  AND o.currency = 'USD'          -- exclude NZD Cook Islands data
```

### Amount Conversion
```sql
-- All monetary amounts stored in cents (integer)
-- Divide by 100 for dollar display
ROUND(SUM(actual_amount) / 100, 2) AS revenue_usd
```

### Timezone Conversion
```sql
-- Server stores UTC; convert to ET for NYC stores
CONVERT_TZ(create_time, '+00:00', '-05:00') AS local_time  -- EST
CONVERT_TZ(create_time, '+00:00', '-04:00') AS local_time  -- EDT
```

### PII Masking
```sql
-- Phone: show last 4 only
CONCAT('***-***-', RIGHT(phone, 4)) AS masked_phone

-- Email: show domain only
CONCAT('***@', SUBSTRING_INDEX(email, '@', -1)) AS masked_email
```

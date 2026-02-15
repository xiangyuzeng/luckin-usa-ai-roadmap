-- ============================================================================
-- UC-SC-01 Forecast Accuracy Monitor
-- 01_schema_discovery.sql - Source Table Documentation
-- ============================================================================
-- Purpose:  Document the key source tables used for forecast accuracy analysis.
--           This file is READ-ONLY reference; it does NOT create or alter any
--           objects. Run SELECT statements here against the read-replica for
--           discovery only.
--
-- Target DB:  aws-luckyus-dbatest-rw  (analytics workspace)
-- Source DBs: luckyus_ireplenishment, luckyus_scm_shopstock,
--             luckyus_pub_dm, luckyus_opshop,
--             luckyus_scm_commodity, luckyus_sales_order
--
-- Author:     Data Engineering / BI Team
-- Created:    2026-02-15
-- ============================================================================


-- ############################################################################
-- 1. PREDICTION SOURCE  /  预测数据源
-- ############################################################################
-- Table: luckyus_ireplenishment.t_order_predict_alg_v2
-- Description (EN): Core prediction output from the ML replenishment model.
--                   Each row is a per-SKU, per-store daily prediction produced
--                   by the algorithm. Partitioned by dt (prediction date).
-- Description (CN): 智能补货算法核心预测输出表。每行代表算法为某个门店+SKU
--                   生成的日级预测结果，按 dt（预测日期）分区。
--
-- Key columns:
--   shop_dept_id    BIGINT       -- 门店ID / Store ID (join to t_shop_info)
--   goods_code      VARCHAR(32)  -- 货物编号 / Goods code (GS-level SKU, join to t_mdm_goods)
--   vlt_avg_demand  DECIMAL      -- 预测日均需求 / Predicted average daily demand (VLT window)
--   order_num       DECIMAL      -- 建议订货量 / Suggested order quantity from algorithm
--   dt              VARCHAR(32)  -- 预测日期分区 / Prediction date partition (YYYYMMDD or YYYY-MM-DD)
--   task_version_id BIGINT       -- 任务版本号 / Task version ID (links to algorithm run batch)
--   create_time     DATETIME     -- 记录创建时间 / Row creation timestamp
--
-- Notes:
--   - Multiple task_version_id values may exist per dt; use the latest version
--     for a given (shop_dept_id, goods_code, dt) combination.
--   - vlt_avg_demand represents the smoothed demand forecast over the vendor
--     lead time (VLT) window, while order_num is the discrete order suggestion.
--   - Historical data available from ~2025-07 onwards.
--
-- Sample discovery query (DO NOT RUN in production; use read replica):
/*
SELECT dt,
       COUNT(*)                     AS row_cnt,
       COUNT(DISTINCT shop_dept_id) AS store_cnt,
       COUNT(DISTINCT goods_code)   AS sku_cnt,
       MIN(create_time)             AS earliest,
       MAX(create_time)             AS latest
FROM   luckyus_ireplenishment.t_order_predict_alg_v2
WHERE  dt >= '20250701'
GROUP  BY dt
ORDER  BY dt DESC
LIMIT  30;
*/


-- ############################################################################
-- 2. ACTUAL CONSUMPTION  /  实际消耗数据
-- ############################################################################
-- Table: luckyus_scm_shopstock.t_shop_goods_stock_change_record
-- Description (EN): Stock change journal for every inventory movement at the
--                   store-SKU level. Each row records a single stock event
--                   (consumption, receiving, adjustment, etc.) with a reason
--                   code that classifies the movement type.
-- Description (CN): 门店商品库存变动明细表。每行记录一次库存变动事件（消耗、
--                   收货、盘点调整等），通过 reason_code + reason_type 区分
--                   变动类型。
--
-- Key columns:
--   shop_dept_id            BIGINT       -- 门店ID / Store ID
--   goods_code              VARCHAR(32)  -- 货物编号 / Goods code (GS-level)
--   reason_code             VARCHAR(10)  -- 变动原因编码 / Movement reason code
--   reason_type             INT          -- 变动原因类型 / Movement reason type
--   theory_total_adjust_num DECIMAL      -- 理论调整数量 / Theoretical adjustment qty
--   total_adjust_num        DECIMAL      -- 实际调整数量 / Actual adjustment qty
--   adjust_time             DATETIME     -- 变动时间 / Movement timestamp
--   create_time             DATETIME     -- 记录创建时间 / Row creation time
--
-- ---- REASON CODE MAPPING (变动原因编码映射) ----
--
-- Code  | reason_type | Description (EN)               | Description (CN)     | Sign  | Consumption?
-- ------|-------------|--------------------------------|----------------------|-------|----------------------------
-- 025   | 1002        | Physical consumption deduction | 实物消耗扣减         | (-)   | YES - use total_adjust_num
-- 1001  | 20001       | Production consumption         | 生产消耗             | (-)   | YES - use total_adjust_num
-- 1002  | 2001        | Inventory adjustment (consumption)| 盘点/库存调整(消耗) | (-)   | YES - use total_adjust_num (captures ~97% of actual consumption)
-- 019   | 1           | Theoretical auto-deduction     | 理论自动扣减         | (-)   | NO  - theory_total_adjust_num only, values too low vs physical
-- 1000  | 2002        | Receiving / delivery (inbound) | 收货/配送(正向)      | (+)   | NO  - inbound, not consumption
-- 013   | 1           | Theoretical consumption        | 理论消耗             | (-)   | NO  - overlaps with 019, double-counting risk
--
-- VALIDATED Consumption formula (actual daily consumption per store-SKU):
--   actual_consumption = SUM(ABS(total_adjust_num))
--     WHERE reason_code IN ('025','1001','1002')
--       AND total_adjust_num < 0          -- only outbound/consumption records
--     GROUP BY DATE(operated_time), shop_dept_id, goods_mid
--
-- Notes:
--   - reason_code '1002' (inventory adjustments with negative total_adjust_num)
--     captures ~97% of actual physical consumption volume.
--   - reason_codes '025' and '1001' capture additional physical/production consumption.
--   - reason_code '019' uses theory_total_adjust_num which provides theoretical values
--     10-40x lower than actual physical consumption -- NOT suitable for accuracy comparison.
--   - ALWAYS filter total_adjust_num < 0 to isolate consumption (outbound) movements.
--   - Records may arrive with slight delay; allow T+1 buffer for completeness.
--   - Data volume is high (~millions of rows/day across all stores).
--
-- Sample discovery query:
/*
SELECT reason_code,
       reason_type,
       COUNT(*)                                       AS row_cnt,
       SUM(ABS(IFNULL(theory_total_adjust_num, 0)))   AS sum_theory,
       SUM(ABS(IFNULL(total_adjust_num, 0)))           AS sum_actual
FROM   luckyus_scm_shopstock.t_shop_goods_stock_change_record
WHERE  adjust_time >= '2025-12-01'
  AND  adjust_time <  '2025-12-02'
GROUP  BY reason_code, reason_type
ORDER  BY row_cnt DESC;
*/


-- ############################################################################
-- 3. PRODUCT MASTER DATA  /  商品主数据
-- ############################################################################
-- Table: luckyus_pub_dm.t_mdm_goods
-- Description (EN): Enterprise product master (MDM). Contains the full goods
--                   hierarchy, naming, category classification, status flags,
--                   and UOM information for every SKU in the system.
-- Description (CN): 企业商品主数据（MDM）。包含完整的商品层级、名称、品类分类、
--                   状态标记和计量单位等信息。
--
-- Key columns:
--   goods_code       VARCHAR(32)   -- 货物编号 / Goods code (primary key for joins)
--   goods_name       VARCHAR(200)  -- 货物名称 / Goods name
--   large_class_code VARCHAR(32)   -- 大类编码 / Large category code
--   large_class_name VARCHAR(100)  -- 大类名称 / Large category name (e.g., '咖啡','茶饮')
--   mid_class_code   VARCHAR(32)   -- 中类编码 / Middle category code
--   mid_class_name   VARCHAR(100)  -- 中类名称 / Middle category name
--   small_class_code VARCHAR(32)   -- 小类编码 / Small category code
--   small_class_name VARCHAR(100)  -- 小类名称 / Small category name
--   goods_status     TINYINT       -- 商品状态 / Goods status (1=active)
--   unit_name        VARCHAR(20)   -- 基本单位 / Base unit of measure
--
-- Notes:
--   - Join on goods_code to both prediction and consumption tables.
--   - Use large_class_name as the primary aggregation dimension for category-level
--     accuracy reporting.
--   - Filter goods_status = 1 for active products only in standard reports.
--
-- Sample discovery query:
/*
SELECT large_class_name,
       COUNT(*)                                    AS total_sku,
       SUM(CASE WHEN goods_status = 1 THEN 1 END) AS active_sku
FROM   luckyus_pub_dm.t_mdm_goods
GROUP  BY large_class_name
ORDER  BY total_sku DESC;
*/


-- ############################################################################
-- 4. STORE MASTER DATA  /  门店主数据
-- ############################################################################
-- Table: luckyus_opshop.t_shop_info
-- Description (EN): Store master data with location, operating attributes,
--                   and status information for all Luckin Coffee US locations.
-- Description (CN): 门店主数据，包含所有瑞幸咖啡美国门店的位置、运营属性和
--                   状态信息。
--
-- Key columns:
--   shop_dept_id     BIGINT        -- 门店ID / Store ID (primary key for joins)
--   shop_name        VARCHAR(100)  -- 门店名称 / Store name
--   shop_code        VARCHAR(32)   -- 门店编码 / Store code
--   shop_status      TINYINT       -- 门店状态 / Store status (1=open/operating)
--   province_name    VARCHAR(50)   -- 州/省 / State/Province
--   city_name        VARCHAR(50)   -- 城市 / City
--   area_name        VARCHAR(100)  -- 区域 / Area/District
--   open_time        DATE          -- 开业日期 / Opening date
--   shop_type        TINYINT       -- 门店类型 / Store type
--
-- Notes:
--   - Join on shop_dept_id to prediction and consumption tables.
--   - Filter shop_status = 1 for open/operating stores in standard reports.
--   - Newly opened stores (< 30 days since open_time) should be excluded from
--     accuracy benchmarking as they lack stable demand patterns.
--
-- Sample discovery query:
/*
SELECT shop_status,
       COUNT(*) AS store_cnt,
       MIN(open_time) AS earliest_open,
       MAX(open_time) AS latest_open
FROM   luckyus_opshop.t_shop_info
GROUP  BY shop_status;
*/


-- ############################################################################
-- 5. BILL OF MATERIALS (BOM)  /  配方/BOM
-- ############################################################################
-- Table: luckyus_scm_commodity.t_formula_spu
-- Description (EN): Bill of Materials (BOM) / recipe table linking finished
--                   products (SPU level) to their raw material components
--                   (GS-level goods). Used to translate sales of finished
--                   products into raw material demand.
-- Description (CN): 配方/BOM表，将成品（SPU级别）与其原料组件（GS级货物）关联。
--                   用于将成品销售转换为原料需求量。
--
-- Key columns:
--   spu_code         VARCHAR(32)   -- 成品SPU编码 / Finished product SPU code
--   goods_code       VARCHAR(32)   -- 原料货物编码 / Raw material goods code (GS)
--   dosage           DECIMAL       -- 用量 / Dosage per unit of finished product
--   unit_name        VARCHAR(20)   -- 单位 / Unit of measure for dosage
--   formula_status   TINYINT       -- 配方状态 / Formula status (1=active)
--
-- Notes:
--   - This is the critical link between what customers order (finished drinks)
--     and what the prediction algorithm forecasts (raw materials/ingredients).
--   - A single finished product (SPU) can have multiple raw material components.
--   - A single raw material (goods_code) can appear in multiple finished products.
--   - The prediction model operates at the GS (raw material) level, so BOM is
--     needed primarily for explainability and drill-down from sales to materials.
--   - Filter formula_status = 1 for current active formulas.
--
-- Sample discovery query:
/*
SELECT COUNT(DISTINCT spu_code)   AS spu_count,
       COUNT(DISTINCT goods_code) AS gs_count,
       COUNT(*)                   AS formula_lines,
       AVG(dosage)                AS avg_dosage
FROM   luckyus_scm_commodity.t_formula_spu
WHERE  formula_status = 1;
*/


-- ############################################################################
-- 6. SALES / ORDER DATA  /  销售订单数据
-- ############################################################################
-- Table: luckyus_sales_order.t_order
-- Description (EN): Order header table capturing each customer transaction.
--                   Contains order-level metadata (timestamps, store, totals,
--                   status, payment info).
-- Description (CN): 订单头表，记录每笔客户交易的订单级元数据（时间戳、门店、
--                   合计、状态、支付信息等）。
--
-- Key columns:
--   order_id         BIGINT        -- 订单ID / Order ID (primary key)
--   shop_dept_id     BIGINT        -- 门店ID / Store ID
--   order_time       DATETIME      -- 下单时间 / Order placement time
--   pay_time         DATETIME      -- 支付时间 / Payment time
--   order_status     TINYINT       -- 订单状态 / Order status
--   total_amount     DECIMAL       -- 订单总金额 / Order total amount
--
-- Table: luckyus_sales_order.t_order_item
-- Description (EN): Order line-item detail. Each row represents a single
--                   product (SPU) within an order, with quantity, pricing,
--                   and product attributes.
-- Description (CN): 订单明细行表。每行代表一个订单中的单个产品（SPU），包含
--                   数量、价格和产品属性。
--
-- Key columns:
--   order_id         BIGINT        -- 订单ID / Order ID (FK to t_order)
--   item_id          BIGINT        -- 明细ID / Line item ID
--   spu_code         VARCHAR(32)   -- 成品SPU编码 / Product SPU code
--   goods_name       VARCHAR(200)  -- 商品名称 / Product name
--   quantity         INT           -- 数量 / Quantity ordered
--   unit_price       DECIMAL       -- 单价 / Unit price
--   shop_dept_id     BIGINT        -- 门店ID / Store ID
--
-- Notes:
--   - Sales data serves as a secondary validation source. The primary forecast
--     comparison is prediction vs. inventory consumption (stock change records).
--   - To link sales to raw material consumption, join t_order_item.spu_code to
--     t_formula_spu.spu_code, then multiply quantity * dosage for each component.
--   - Filter order_status for completed/paid orders only when analyzing actual
--     sales volumes.
--   - Data volume is very high; always filter by date range for queries.
--
-- Sample discovery query:
/*
SELECT DATE(o.order_time)            AS order_date,
       COUNT(DISTINCT o.order_id)    AS order_cnt,
       SUM(oi.quantity)              AS total_items,
       COUNT(DISTINCT o.shop_dept_id) AS store_cnt
FROM   luckyus_sales_order.t_order o
       JOIN luckyus_sales_order.t_order_item oi ON o.order_id = oi.order_id
WHERE  o.order_time >= '2025-12-01'
  AND  o.order_time <  '2025-12-08'
GROUP  BY DATE(o.order_time)
ORDER  BY order_date;
*/


-- ############################################################################
-- DATA LINEAGE SUMMARY  /  数据血缘关系总结
-- ############################################################################
--
-- The forecast accuracy pipeline joins data as follows:
--
--   [Predictions]                          [Actuals]
--   t_order_predict_alg_v2                 t_shop_goods_stock_change_record
--         |                                       |
--         |  (shop_dept_id, goods_code, date)      |  (shop_dept_id, goods_code, date)
--         |                                       |  (reason_code IN ('025','1001','1002') AND total_adjust_num < 0)
--         +------- INNER JOIN on date/store/sku --+
--                          |
--                          v
--                 forecast_accuracy_daily
--                          |
--                 +--------+--------+
--                 |                 |
--          [Enrich with]     [Enrich with]
--          t_mdm_goods       t_shop_info
--        (goods_name,       (shop_name,
--         category)          location)
--
--   Secondary linkage for sales-based validation:
--     t_order + t_order_item  --(spu_code)--> t_formula_spu --(goods_code)--> predictions
--
-- ############################################################################
-- END OF SCHEMA DISCOVERY
-- ############################################################################

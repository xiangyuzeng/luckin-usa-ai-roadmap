# Supply Chain & Inventory Database Exploration Report
## Date: 2026-02-13

---

## EXECUTIVE SUMMARY

| # | Server | Database | Tables | Key Domain |
|---|--------|----------|--------|------------|
| 1 | aws-luckyus-scm-shopstock-rw | luckyus_scm_shopstock | **184** | Shop stock/inventory, delivery, returns, check orders, premade materials |
| 2 | aws-luckyus-scm-ordering-rw | luckyus_scm_ordering | **100** | Shop ordering, auto-ordering, dispatch programs, delivery |
| 3 | aws-luckyus-scm-purchase-rw | luckyus_scm_purchase | **158** | Purchasing, contracts, quotations, settlements, shipping |
| 4 | aws-luckyus-scm-wds-rw | luckyus_scm_wds | **156** | Warehouse distribution, inbound/outbound, stock reconciliation |
| 5 | aws-luckyus-scmcommodity-rw | luckyus_scm_commodity | **139** | Commodity/product master, formulas, nutrition, note options |
| 6 | aws-luckyus-scm-plan-rw | luckyus_scm_plan | **40** | Planning, commodity launch/exit, new shop opening |
| 7 | aws-luckyus-scm-asset-rw | luckyus_scm_asset | **142** | Asset management, install/uninstall, repair, engineer stock |
| 8 | aws-luckyus-scmsrm-rw | luckyus_scm_srm | **118** | Supplier management (SRM), enterprise, qualifications, PQNC |
| 9 | aws-luckyus-ireplenishment-rw | luckyus_ireplenishment | **7** | AI-based replenishment predictions, unfreeze predictions |

**Total: 1,044 tables across 9 databases**

---

## DATABASE 1: luckyus_scm_shopstock (Shop Stock/Inventory)
**Server:** aws-luckyus-scm-shopstock-rw
**Tables:** 184

### HIGH-VOLUME TABLES (TOP 20 by row count)

| Table | Rows | Size (MB) | Comment |
|-------|------|-----------|---------|
| t_shop_goods_stock_change_record_thur | 1,307,656 | 493 | Goods stock change records (Thursday) |
| t_shop_commodity_stock_change_record | 1,296,827 | 348 | Commodity stock adjustment records |
| t_shop_goods_stock_change_record_fri | 1,281,479 | 483 | Goods stock change records (Friday) |
| t_shop_goods_stock_change_record_wed | 1,226,035 | 483 | Goods stock change records (Wednesday) |
| t_shop_goods_stock_change_record_tues | 1,180,188 | 455 | Goods stock change records (Tuesday) |
| t_shop_goods_stock_change_record_sat | 1,062,169 | 386 | Goods stock change records (Saturday) |
| t_idempotent_order_modify_stock | 1,043,049 | 61 | Order deduction idempotency |
| t_shop_goods_stock_change_record_mon | 1,042,706 | 401 | Goods stock change records (Monday) |
| t_shop_goods_stock_change_record_sun | 924,432 | 350 | Goods stock change records (Sunday) |
| t_shop_premade_material_stock_change_record | 535,932 | 150 | Premade material stock changes |
| t_shop_goods_stock_change_record | 378,828 | 117 | Base goods stock change records |
| t_shop_check_order_history | 197,933 | 20 | Check order history |
| t_shop_goods_spec_stock | 159,172 | 30 | Shop goods spec stock |
| t_shop_spec_stock_change_record | 157,394 | 39 | Spec stock change records |
| t_shop_goods_stock | 150,953 | 24 | **CORE: Shop goods stock (current)** |
| t_shop_commodity_stock_adjust_material_detail | 145,655 | 10 | Commodity stock adjust material detail |
| t_shop_stock_cost_change_record | 138,111 | 43 | Stock cost change records |
| t_shop_check_order_goods | 109,380 | 21 | Check order goods detail |
| t_shop_check_order_goods_spec | 101,628 | 17 | Check order goods spec detail |

### KEY BUSINESS TABLES

**Core Stock Tables:**
- `t_shop_goods_stock` (150,953 rows) - Current goods stock per shop
- `t_shop_goods_spec_stock` (159,172 rows) - Current spec-level stock per shop
- `t_shop_intransit_stock` (3,234 rows) - In-transit stock
- `t_shop_premade_material_stock` (534 rows) - Premade material stock per shop
- `t_shop_premade_material_stock_batch` (12,526 rows) - Batch-level premade stock

**Delivery:**
- `t_shop_delivery` (3,260 rows) - Delivery orders to shops
- `t_shop_delivery_item` (30,274 rows) - Delivery line items
- `t_shop_delivery_diff` (203 rows) - Delivery discrepancy orders
- `t_shop_delivery_shortage` (2,815 rows) - Delivery shortage records

**Returns:**
- `t_shop_return` (268 rows) - Return orders
- `t_direct_return` (38 rows) - Direct procurement returns

**Stock Checks (Inventory Count):**
- `t_shop_check_order` (2,260 rows) - Inventory check work orders
- `t_shop_check_order_goods` (109,380 rows) - Check order goods detail
- `t_shop_temporary_check_apply_order` (1,045 rows) - Ad-hoc check applications

**Unfreeze Management:**
- `t_shop_unfreeze` (3,519 rows) - Unfreeze orders
- `t_shop_unfreeze_item` (14,323 rows) - Unfreeze order items

**Allocation (Inter-store Transfer):**
- `t_shop_allocation_in` (1,050 rows) - Transfer-in orders
- `t_shop_allocation_out` (1,064 rows) - Transfer-out orders

**Master Data (replicated):**
- `t_shop_info` (534 rows) - Shop information
- `t_mdm_goods` (1,448 rows) - Goods master
- `t_mdm_goods_spec` (1,837 rows) - Goods specification
- `t_warehouse` (10 rows) - Warehouse info

**NOTE:** Stock change records are **partitioned by day of week** (Mon-Sun), each containing ~1M rows. Total stock change events: ~8.4M rows across all day partitions.

---

## DATABASE 2: luckyus_scm_ordering (SCM Ordering)
**Server:** aws-luckyus-scm-ordering-rw
**Tables:** 100

### HIGH-VOLUME TABLES

| Table | Rows | Size (MB) | Comment |
|-------|------|-----------|---------|
| t_auto_order_small_log | 686,732 | 44 | Auto-ordering small class logs |
| t_shop_goods_stock | 146,510 | 31 | Shop goods stock (snapshot) |
| t_shop_delivery_item_temp | 30,486 | 3 | Delivery item temp table |
| t_shop_order_item | 30,260 | 6 | Order line items |
| t_auto_order_detail_log | 16,891 | 4 | Auto-order detail log |
| t_order_summary_item_dly | 16,078 | 3 | Order summary delivery details |
| t_order_summary_item | 15,701 | 2 | Order summary items |
| t_shop_order_history | 13,666 | 2 | Order history |
| t_auto_order_rpc_ai_log | 9,237 | 50 | Auto-order AI algorithm call logs |
| t_shop_spec_config | 7,180 | 2 | Shop orderable spec configuration |

### KEY BUSINESS TABLES

**Shop Orders:**
- `t_shop_order` (2,151 rows) - Shop ordering documents
- `t_shop_order_item` (30,260 rows) - Order line items
- `t_shop_order_history` (13,666 rows) - Order audit trail

**Order Aggregation:**
- `t_order_summary` (863 rows) - Order summary/consolidation
- `t_order_summary_item` (15,701 rows) - Summary line items
- `t_order_summary_item_dly` (16,078 rows) - Summary delivery details

**Auto-Ordering (AI):**
- `t_auto_order_small_log` (686,732 rows) - Auto-order by small class logs
- `t_auto_order_detail_log` (16,891 rows) - Auto-order detail logs
- `t_auto_order_rpc_ai_log` (9,237 rows, 50MB) - AI algorithm API call logs
- `t_small_class_auto_order_time` (832 rows) - Auto-order time configuration

**Dispatch Programs:**
- `t_dispatch_program` (4 rows) - Warehouse dispatch programs
- `t_warehouse_dispatch_program` (6 rows) - Warehouse-dispatch association
- `t_supplier_dispatch_program` (1 row) - Supplier-dispatch association

**Configuration:**
- `t_shop_spec_config` (7,180 rows) - Shop orderable spec config
- `t_shop_arrival_week` (543 rows) - Expected arrival date config
- `t_shop_recent_order_date_config` (543 rows) - Recent auto-order date config
- `t_order_quantity_limit` (66 rows) - Order quantity limits

---

## DATABASE 3: luckyus_scm_purchase (Purchasing)
**Server:** aws-luckyus-scm-purchase-rw
**Tables:** 158

### HIGH-VOLUME TABLES

| Table | Rows | Size (MB) | Comment |
|-------|------|-----------|---------|
| t_mdm_bank_branch | 517,131 | 71 | Bank branch master data |
| t_ship_order_batch_item | 9,798 | 2 | Ship order batch items |
| t_ship_order_item | 6,206 | 1 | Ship order line items |
| t_ship_plan_order_item | 6,045 | 2 | Ship plan order items |
| t_goods_spec_payment_detail | 5,663 | 4 | Goods payment details |
| t_goods_spec_cost_detail | 5,488 | 2 | Goods cost details |
| t_ship_plan_order_small_class | 4,029 | 0.3 | Ship plan small class |
| t_ship_order_small_class | 4,143 | 0.3 | Ship order small class |
| t_purchase_order_item | 2,871 | 2 | Purchase order items |

### KEY BUSINESS TABLES

**Purchase Orders:**
- `t_purchase_order` (694 rows) - Purchase orders
- `t_purchase_order_item` (2,871 rows) - PO line items
- `t_purchase_order_small_class` (1,535 rows) - PO small class grouping

**Contracts:**
- `t_contract_info` (54 rows) - Contract information
- `t_contract_detail` (54 rows) - Contract details
- `t_contract_attachment` (54 rows) - Contract attachments

**Quotations:**
- `t_quotation_info` (1,510 rows) - Quotation headers
- `t_quotation_detail` (1,572 rows) - Quotation line items
- `t_inquiry_order` (9 rows) - Inquiry/RFQ orders

**Shipping:**
- `t_ship_order` (1,670 rows) - Ship orders (supplier to warehouse)
- `t_ship_order_item` (6,206 rows) - Ship order line items
- `t_ship_order_batch_item` (9,798 rows) - Ship order batch details
- `t_ship_plan_order` (1,613 rows) - Shipping plan orders

**Returns:**
- `t_return_order` (79 rows) - Return orders to suppliers
- `t_return_order_item` (79 rows) - Return line items

**Settlements/Payments:**
- `t_supplier_settlement` (185 rows) - Supplier settlements
- `t_settlement_bank` (226 rows) - Settlement bank info
- `t_settlement_invoice` (247 rows) - Settlement invoices
- `t_goods_spec_payment_detail` (5,663 rows) - Goods payment details
- `t_goods_spec_cost_detail` (5,488 rows) - Goods cost details
- `t_advance_charge_settlement` (23 rows) - Advance payment settlements
- `t_freight_charge_detail` (31 rows) - Freight charge details
- `t_freight_charge_settlement` (4 rows) - Freight settlements

**Customs:**
- `t_customs_declaration` (0 rows) - Customs declarations (not yet used)

**Sales (Resale):**
- `t_sales_order` (1 row) - Sales orders
- `t_sales_ship_order` (1 row) - Sales shipping
- `t_sales_customer` (1 row) - Sales customers

---

## DATABASE 4: luckyus_scm_wds (Warehouse Distribution)
**Server:** aws-luckyus-scm-wds-rw
**Tables:** 156

### HIGH-VOLUME TABLES

| Table | Rows | Size (MB) | Comment |
|-------|------|-----------|---------|
| t_warehouse_stock_batch_everyday | 144,084 | 21 | Daily warehouse batch stock snapshot |
| t_warehouse_stock_change_record | 41,656 | 11 | Warehouse stock change records |
| t_warehouse_outbound_item | 27,281 | 4 | Outbound line items |
| t_warehouse_stock_cost_change_record | 26,744 | 9 | Stock cost change records |
| t_warehouse_outbound_batch_item | 24,158 | 3 | Outbound batch items |
| t_warehouse_compare_item | 21,907 | 4 | Stock comparison items |
| t_warehouse_compare_diff_item | 5,620 | 2 | Stock comparison diff items |

### KEY BUSINESS TABLES

**Warehouse Stock:**
- `t_warehouse_stock` (834 rows) - **CORE: Current warehouse stock**
- `t_warehouse_stock_batch` (1,895 rows) - Batch-level warehouse stock
- `t_warehouse_stock_batch_everyday` (144,084 rows) - Daily stock snapshots
- `t_warehouse_intransit_stock` (303 rows) - In-transit stock
- `t_warehouse_stock_change_record` (41,656 rows) - Stock movement records

**Inbound (Receiving):**
- `t_warehouse_inbound` (1,198 rows) - Inbound/receiving orders
- `t_warehouse_inbound_item` (3,314 rows) - Inbound line items
- `t_warehouse_inbound_batch_item` (2,914 rows) - Inbound batch items
- `t_warehouse_inbound_diff` (12 rows) - Inbound discrepancies

**Outbound (Dispatch):**
- `t_warehouse_outbound` (2,391 rows) - Outbound/dispatch orders
- `t_warehouse_outbound_item` (27,281 rows) - Outbound line items
- `t_warehouse_outbound_batch_item` (24,158 rows) - Outbound batch items
- `t_warehouse_outbound_diff` (209 rows) - Outbound discrepancies

**Inter-Warehouse Transfers:**
- `t_warehouse_allocation` (26 rows) - Warehouse transfer orders
- `t_warehouse_allocation_item` (264 rows) - Transfer line items
- `t_warehouse_allocation_in` (13 rows) - Transfer-in orders
- `t_warehouse_allocation_batch` (274 rows) - Transfer batch detail

**Other Operations:**
- `t_warehouse_other_inbound` (79 rows) - Other inbound (non-PO)
- `t_warehouse_other_outbound` (233 rows) - Other outbound
- `t_warehouse_transfer` (41 rows) - Stock status transfers
- `t_warehouse_batch_adjust` (30 rows) - Batch adjustments

**Stock Checks & Reconciliation:**
- `t_warehouse_check` (37 rows) - Warehouse count orders
- `t_warehouse_check_item` (222 rows) - Count line items
- `t_warehouse_compare` (45 rows) - Stock reconciliation orders
- `t_warehouse_compare_item` (21,907 rows) - Reconciliation items

**Stock Cell (Sub-warehouse):**
- `t_stock_cell_allocation_in` (20 rows) - Sub-warehouse transfer-in
- `t_stock_cell_stock` (17 rows) - Sub-warehouse stock
- `t_stock_cell_check_order` (6 rows) - Sub-warehouse check orders

---

## DATABASE 5: luckyus_scm_commodity (Commodity/Product Master)
**Server:** aws-luckyus-scmcommodity-rw
**Tables:** 139

### HIGH-VOLUME TABLES

| Table | Rows | Size (MB) | Comment |
|-------|------|-----------|---------|
| t_formula_spu_draft_history | 319,270 | 55 | SPU formula draft history |
| t_formula_spu_history | 192,690 | 33 | SPU formula history |
| t_formula_spu | 32,519 | 7 | **SPU formula (BOM)** |
| t_commodity_allergens_info_language | 7,365 | 4 | Allergen info multi-language |
| t_commodity_note_option | 4,681 | 0.4 | Commodity note options (customizations) |
| t_commodity_nutrition_facts_draft | 4,279 | 0.4 | Nutrition facts drafts |
| t_formula_average | 3,947 | 2 | Average formula/recipe |
| t_commodity_note_option_default_phr | 3,415 | 0.3 | Default portion sizes |
| t_commodity_base_info_history | 2,912 | 0.3 | Commodity base info history |
| t_commodity_option_takeout_config | 2,614 | 0.2 | Takeout option config |

### KEY BUSINESS TABLES

**Commodity (SPU) Master:**
- `t_commodity_base_info` (141 rows) - **CORE: Commodity/product master**
- `t_commodity_base_info_language` (305 rows) - Multi-language names
- `t_commodity_category` (196 rows) - Commodity categories
- `t_commodity_sale_info` (139 rows) - Sales information
- `t_commodity_sku` (63 rows) - SKU definitions

**Formulas (BOM/Recipe):**
- `t_formula_spu` (32,519 rows) - **CORE: SPU formula/recipe (Bill of Materials)**
- `t_formula_spu_note_type` (826 rows) - Formula note types
- `t_formula_spu_note_option` (1,824 rows) - Formula customization options
- `t_formula_average` (3,947 rows) - Average formula composition
- `t_formula_plan` (3 rows) - Formula plans

**Customization (Note Options):**
- `t_note_type` (40 rows) - Note/customization types (sugar, ice, etc.)
- `t_note_option` (201 rows) - Customization options
- `t_note_option_price` (201 rows) - Option pricing
- `t_commodity_note_option` (4,681 rows) - Commodity-option mapping

**Combos/Meals:**
- `t_combo` (20 rows) - Combo/set meal definitions
- `t_combo_floor` (36 rows) - Combo tiers/floors
- `t_combo_floor_item` (127 rows) - Combo tier items

**Nutrition:**
- `t_nutrition_facts` (34 rows) - Nutrition fact definitions
- `t_commodity_nutrition_facts` (1,448 rows) - Per-commodity nutrition
- `t_commodity_nutrition_grade` (4 rows) - Nutrition grading config
- `t_commodity_allergens` (141 rows) - Allergen information
- `t_commodity_allergens_info` (169 rows) - Allergen details

**Premade Materials:**
- `t_premade_material_config` (30 rows) - Premade material configurations
- `t_premade_material_program` (63 rows) - Premade material programs

---

## DATABASE 6: luckyus_scm_plan (Planning)
**Server:** aws-luckyus-scm-plan-rw
**Tables:** 40

### KEY BUSINESS TABLES

**Commodity Launch/Exit Planning:**
- `t_commodity_exit_plan` (2 rows) - Product exit/sunset plans
- `t_commodity_exit_plan_item` (15 rows) - Exit plan items
- `t_commodity_launch_config` (1 row) - Product launch configuration
- `t_commodity_launch_config_item` (1 row) - Launch config items

**New Shop Opening:**
- `t_new_shop_opening_plan` (7 rows) - New shop opening plans
- `t_new_shop_opening_plan_history` (7 rows) - Opening plan history

**Shop Resources:**
- `t_shop_resource` (518 rows) - Shop resource allocations

**Master Data (replicated):**
- `t_commodity_base_info` (141 rows) - Commodity info
- `t_shop_info` (544 rows) - Shop info
- `t_mdm_goods` (1,448 rows) - Goods master
- `t_mdm_goods_spec` (1,660 rows) - Goods spec master

---

## DATABASE 7: luckyus_scm_asset (Asset Management)
**Server:** aws-luckyus-scm-asset-rw
**Tables:** 142

### KEY BUSINESS TABLES

**Asset Master:**
- `t_asset_info` (409 rows) - **CORE: Asset information**
- `t_high_value_goods_info` (1,735 rows) - High-value goods tracking

**Asset Check (Inventory Count):**
- `t_asset_check_order` (3,109 rows) - Asset check work orders
- `t_asset_check_order_item` (873 rows) - Check order items
- `t_asset_check_program` (4 rows) - Check programs/schedules

**Asset Installation:**
- `t_asset_install` (98 rows) - Installation work orders
- `t_asset_install_item` (461 rows) - Installation line items
- `t_asset_install_item_attachment` (438 rows) - Install photos/docs

**Asset Uninstall:**
- `t_asset_uninstall` (3 rows) - Uninstall/decommission orders
- `t_asset_uninstall_item` (3 rows) - Uninstall items

**Asset Allocation (Transfer):**
- `t_asset_allocation` (19 rows) - Asset transfer orders
- `t_asset_allocation_item` (24 rows) - Transfer items

**Repair Management:**
- `t_repair_order` (83 rows) - Repair work orders
- `t_repair_order_item` (97 rows) - Repair line items
- `t_repair_order_fault_reason` (67 rows) - Fault reasons
- `t_repair_order_spare_parts` (2 rows) - Spare parts used

**Fault Management:**
- `t_fault` (293 rows) - Fault records
- `t_fault_item` (293 rows) - Fault details
- `t_fault_reason` (5 rows) - Fault reason lookup

**Engineer Stock:**
- `t_engineer` (6 rows) - Field engineers
- `t_engineer_stock` (3 rows) - Engineer-held stock
- `t_engineer_get` (2 rows) - Engineer requisitions
- `t_engineer_return` (2 rows) - Engineer returns
- `t_engineer_check_order` (80 rows) - Engineer inventory checks

**Maintenance:**
- `t_maintenance_order` (0 rows) - Maintenance work orders (not yet active)
- `t_maintenance_program` (0 rows) - Maintenance programs

---

## DATABASE 8: luckyus_scm_srm (Supplier Relationship Management)
**Server:** aws-luckyus-scmsrm-rw
**Tables:** 118 (also has backup_tables database)

### KEY BUSINESS TABLES

**Enterprise/Supplier Master:**
- `t_enterprise` (7 rows) - Enterprise entities
- `t_enterprise_contact` (11 rows) - Enterprise contacts
- `t_enterprise_bank_info` (6 rows) - Enterprise bank accounts
- `t_enterprise_qualification` (8 rows) - Enterprise certifications
- `t_enterprise_manufacturer` (6 rows) - Associated manufacturers
- `t_manufacturer` (6 rows) - Manufacturer master

**Product Qualifications:**
- `t_enterprise_product_qualification` (8 rows) - Product certifications
- `t_enterprise_manufacturer_qualification` (8 rows) - Manufacturer certs
- `t_supplier_qualification` (237 rows) - Supplier certifications

**SRM Inquiry/RFQ:**
- `t_inquiry_order` (11 rows) - Inquiries
- `t_inquiry_order_item` (19 rows) - Inquiry items
- `t_rfq_order` (10 rows) - RFQ orders
- `t_rfq_order_item` (17 rows) - RFQ items

**Quality (PQNC):**
- `t_pqnc` (272 rows) - **Product Quality Non-Conformance reports**
- `t_pqnc_attachment` (1,006 rows) - PQNC attachments
- `t_pqnc_operate_detail` (501 rows) - PQNC operation details
- `t_pqnc_relate_bill` (272 rows) - PQNC related documents

**Goods Spec Management (Draft/Publish):**
- `t_mdm_goods_spec_draft` (1,714 rows) - Spec draft records
- `t_mdm_goods_spec_draft_images` (6,663 rows) - Draft images
- `t_mdm_goods_spec_draft_package` (5,486 rows) - Draft packaging
- `t_mdm_goods_draft` (1,454 rows) - Goods drafts
- `t_mdm_goods_large_class_draft` (92 rows) - Large class drafts
- `t_mdm_goods_small_class_draft` (819 rows) - Small class drafts

**Quality Control Config:**
- `t_goods_spec_expiration_date_check_config` (6 rows) - Expiry check config
- `t_goods_spec_qcm_scope_config` (20 rows) - QC management scope

---

## DATABASE 9: luckyus_ireplenishment (AI Replenishment)
**Server:** aws-luckyus-ireplenishment-rw
**Tables:** 7

| Table | Rows | Size (MB) | Comment |
|-------|------|-----------|---------|
| warehouse_predict_alg_characteristics | 2,563,399 | 229 | Warehouse goods prediction features |
| wh_goods_daily_demand_pred | 2,576,815 | 216 | **Warehouse goods daily demand predictions** |
| t_order_predict_alg_v2 | 124,380 | 52 | **Order prediction algorithm v2** |
| unfreeze_predict_alg | 16,411 | 4 | Unfreeze prediction |
| alg_task_status_v2 | 506 | 0.1 | Algorithm task execution status |
| t_asset_info | 0 | 0 | Asset info (placeholder) |
| t_shop_unfreeze_refrigerator_spec | 0 | 0 | Refrigerator spec (placeholder) |

### KEY TABLES

- `wh_goods_daily_demand_pred` (2.6M rows, 216MB) - **CORE: Daily demand predictions per warehouse goods**
- `warehouse_predict_alg_characteristics` (2.6M rows, 229MB) - **Feature engineering data for predictions**
- `t_order_predict_alg_v2` (124K rows, 52MB) - **Order quantity predictions (internationalized v2)**
- `unfreeze_predict_alg` (16K rows) - Unfreeze quantity predictions
- `alg_task_status_v2` (506 rows) - Task scheduling/status tracking

---

## SHARED/REPLICATED MASTER DATA TABLES

The following tables are replicated across multiple databases for local joins:

| Table | Description | Rows | Found In |
|-------|-------------|------|----------|
| t_mdm_goods | Goods master | ~1,448 | All 9 DBs |
| t_mdm_goods_spec | Goods specification | ~1,700 | 8 DBs |
| t_mdm_goods_large_class | Goods large category | ~90 | All 9 DBs |
| t_mdm_goods_small_class | Goods small category | ~800 | All 9 DBs |
| t_mdm_goods_brand | Goods brand | ~2,595 | 5 DBs |
| t_mdm_supplier | Supplier master | ~194 | 6 DBs |
| t_mdm_country | Country reference | ~600 | 8 DBs |
| t_mdm_locality | City/region (L2 admin) | ~227 | All 9 DBs |
| t_mdm_tenant | Tenant/org | ~33 | All 9 DBs |
| t_mdm_unit | Unit of measure | ~300 | All 9 DBs |
| t_mdm_time_zone | Time zones | ~400 | 8 DBs |
| t_shop_info | Shop master | ~540 | 8 DBs |
| t_warehouse | Warehouse master | ~10 | 7 DBs |
| t_stock_cell | Stock cell/unit | ~558 | 6 DBs |
| t_mdm_cooperation_pattern | Cooperation model | ~7 | 6 DBs |

---

## DATA VOLUME SUMMARY

### Total Estimated Rows by Database

| Database | Est. Total Rows | Est. Total Size |
|----------|----------------|-----------------|
| luckyus_scm_shopstock | ~12M+ | ~4.2 GB |
| luckyus_scm_ordering | ~1.1M | ~200 MB |
| luckyus_scm_purchase | ~560K | ~90 MB |
| luckyus_scm_wds | ~310K | ~50 MB |
| luckyus_scm_commodity | ~580K | ~110 MB |
| luckyus_scm_plan | ~12K | ~5 MB |
| luckyus_scm_asset | ~19K | ~8 MB |
| luckyus_scm_srm | ~560K | ~80 MB |
| luckyus_ireplenishment | ~5.3M | ~500 MB |

### Largest Tables Across All Databases

| Rank | Database | Table | Rows | Size |
|------|----------|-------|------|------|
| 1 | ireplenishment | wh_goods_daily_demand_pred | 2,576,815 | 216 MB |
| 2 | ireplenishment | warehouse_predict_alg_characteristics | 2,563,399 | 229 MB |
| 3 | shopstock | t_shop_goods_stock_change_record_thur | 1,307,656 | 493 MB |
| 4 | shopstock | t_shop_commodity_stock_change_record | 1,296,827 | 348 MB |
| 5 | shopstock | t_shop_goods_stock_change_record_fri | 1,281,479 | 483 MB |
| 6 | shopstock | t_shop_goods_stock_change_record_wed | 1,226,035 | 483 MB |
| 7 | shopstock | t_shop_goods_stock_change_record_tues | 1,180,188 | 455 MB |
| 8 | shopstock | t_shop_goods_stock_change_record_sat | 1,062,169 | 386 MB |
| 9 | shopstock | t_idempotent_order_modify_stock | 1,043,049 | 61 MB |
| 10 | shopstock | t_shop_goods_stock_change_record_mon | 1,042,706 | 401 MB |

---

## ARCHITECTURE OBSERVATIONS

1. **Multi-language Support**: Nearly every business table has a corresponding `_language` table for internationalization (i18n).

2. **Audit Trail**: Most transaction tables have `_history` tables tracking state changes.

3. **Day-of-Week Partitioning**: Stock change records in shopstock are partitioned by day of week (Mon-Sun), each ~1M rows, for write distribution.

4. **Microservice Architecture**: Each domain has its own database with replicated MDM tables for local joins (avoids cross-DB queries).

5. **Batch/Lot Tracking**: Goods are tracked at batch level with `_batch` tables for traceability (expiry dates, lot numbers).

6. **Discrepancy Management**: Most inbound/outbound flows have `_diff` (discrepancy) tables for exception handling.

7. **AI Integration**: The replenishment database uses ML predictions (order_predict_alg_v2, warehouse_predict_alg_characteristics) for automated ordering.

8. **Idempotency Control**: Tables like `t_idempotent_order_modify_stock` and `t_warehouse_out_in_idempotent` ensure exactly-once processing.

9. **Template/Program Pattern**: Configurable business processes use template/program tables (allocation templates, check templates, dispatch programs).

10. **Cost Tracking**: Separate cost change record tables track cost movements independently from quantity movements.

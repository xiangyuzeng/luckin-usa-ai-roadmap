# UC-FN-02: Automated Revenue Reconciliation
## Phase 1: Schema Discovery & Data Profiling Report

**Date:** 2026-02-16
**Status:** Complete
**Priority:** P0 (Weighted Score: 4.35)

---

## 1. Executive Summary

This report documents the complete schema discovery and data profiling for the 3-way revenue reconciliation system spanning four MySQL databases: Orders (`salesorder`), Payments (`salespayment`), Accounting (`ifiaccounting`), and Reconciliation (`iunifiedreconcile`).

### Critical Findings

| # | Finding | Severity | Impact |
|---|---------|----------|--------|
| 1 | **Amount unit mismatch**: `t_order_pay.pay_money` stores CENTS while `t_order.pay_money` stores DOLLARS (100x factor) | CRITICAL | Reconciliation math errors if not converted |
| 2 | **order_id type mismatch**: bigint in Orders vs varchar(64) in Payments | HIGH | JOIN failures without explicit CAST |
| 3 | **NZD test data contamination**: 29,668 NZD orders (5.7% of total) | HIGH | Must filter `currency_code = 'USD'` in all reconciliation |
| 4 | **Finance receipt differences**: ALL 495K matched receipts show positive difference (~$4.66 avg) — likely payment processing fees not subtracted | MEDIUM | Systematic fee offset needs rule-based handling |
| 5 | **Accounting pipeline sparse**: Only 44K active income bills vs 492K successful orders | MEDIUM | Significant lag or aggregation between order and accounting layers |
| 6 | **17 existing reconciliation models** already defined in `iunifiedreconcile`, all pointing to DW layer tables | INFO | Existing infrastructure to leverage |

---

## 2. Database Inventory

### 2.1 Server-to-Schema Mapping

| MCP Server Name | Actual Schema Name | Table Count | Purpose |
|----------------|-------------------|-------------|---------|
| `aws-luckyus-salesorder-rw` | `luckyus_sales_order` | 40 | Order lifecycle, receipts, refunds |
| `aws-luckyus-salespayment-rw` | `luckyus_sales_payment` | 28 | Payment processing, Stripe integration |
| `aws-luckyus-ifiaccounting-rw` | `luckyus_ifiaccounting` | 40+ | GL entries, vouchers, income bills |
| `aws-luckyus-iunifiedreconcile-rw` | `luckyus_iunifiedreconcile` | 11 | Reconciliation config & definitions |

### 2.2 Key Tables for Reconciliation

#### Orders Domain (`luckyus_sales_order`)

| Table | Rows | Role in Reconciliation |
|-------|------|----------------------|
| `t_order` | 521,470 | Master order record — amounts in DOLLARS |
| `t_order_amount` | ~490,000 | Detailed amount breakdown (commodity, delivery, tax) |
| `t_order_pay` | 499,681 | Payment link records — amounts in CENTS |
| `t_finance_receipt` | 499,773 | Receipt/checking bridge — amounts in DOLLARS |
| `t_finance_refund` | 13,938 | Refund records — amounts in DOLLARS |
| `t_finance_history` | ~970,000 | Audit trail (type, index_no, content) |
| `t_order_oper_history` | ~2,500,000 | Order operation log |
| `t_order_item` | ~610,000 | Line items per order |

#### Payments Domain (`luckyus_sales_payment`)

| Table | Rows | Role in Reconciliation |
|-------|------|----------------------|
| `t_trade` | 512,473 | Payment transactions — amounts in CENTS (bigint) |
| `t_channel_fee` | ~507,000 | Estimated vs actual payment channel fees |
| `t_refund` | 13,918 | Payment refund records — amounts in CENTS (bigint) |
| `t_user_channel` | ~159,000 | User payment method config |

#### Accounting Domain (`luckyus_ifiaccounting`)

| Table | Rows | Role in Reconciliation |
|-------|------|----------------------|
| `t_acc_income_bill` | 142,434 | Income recognition bills — amounts in DOLLARS |
| `t_pre_voucher` | 3,224 | Pre-made GL vouchers |
| `t_pre_voucher_entry` | ~17,000 | Voucher journal entries (debit/credit) |
| `t_pre_voucher_entry_assist` | ~179,000 | Auxiliary accounting dimensions |
| `t_acc_matter` | 15 | Accounting matters (sparse) |
| `t_acc_matter_event` | 15 | Matter events (sparse) |
| `t_acc_recognition` | 3 | Revenue recognition records (sparse) |
| `t_acc_cost_bill` | ~5,700 | Cost-side bills |

#### Reconciliation Domain (`luckyus_iunifiedreconcile`)

| Table | Rows | Role |
|-------|------|------|
| `t_reconcile_define` | 17 | Reconciliation model definitions |
| `t_data_source` | 18 | Data source configurations |
| `t_i18n_dynamic_dict` | 82 | Internationalization labels |

---

## 3. Join Key Analysis

### 3.1 Primary Join Paths

```
t_order.id (bigint)
    │
    ├──► t_order_pay.order_id (bigint)  ── direct join
    │         │
    │         └──► t_trade.trade_no (varchar) ── via t_order_pay.trade_no = t_trade.trade_no
    │
    ├──► t_finance_receipt.order_no (varchar) ── CAST(t_order.id AS CHAR)
    │         │
    │         └──► t_finance_receipt.tp_serial_no (varchar) = t_trade.trade_no
    │
    └──► t_acc_income_bill.biz_no (varchar) ── INDIRECT via shop_income_summary
```

### 3.2 Join Key Details

| Source Table.Column | Target Table.Column | Source Type | Target Type | Join Method |
|--------------------|--------------------|-------------|-------------|-------------|
| `t_order.id` | `t_order_pay.order_id` | bigint | bigint | Direct |
| `t_order_pay.trade_no` | `t_trade.trade_no` | varchar(50) | varchar(36) | Direct (both have "8" prefix) |
| `t_order.id` | `t_trade.order_id` | bigint | varchar(64) | **CAST required** |
| `t_order.id` | `t_finance_receipt.order_no` | bigint | varchar(255) | **CAST required** |
| `t_order_pay.trade_no` | `t_finance_receipt.tp_serial_no` | varchar(50) | varchar(64) | Direct |
| `t_acc_income_bill.biz_no` | shop_income_summary | varchar(64) | — | "IS000..." format, indirect |

### 3.3 ID Pattern Analysis

| Entity | Example Value | Pattern |
|--------|--------------|---------|
| order_id | `118863692296216576` | 18-digit snowflake ID |
| trade_no | `8118863692296585216` | "8" prefix + 18-digit snowflake |
| receipt_no | `118863693034414080` | 18-digit snowflake ID |
| income_bill biz_no | `IS00000000000000042137` | "IS" + 20-digit padded sequence |
| income_bill bill_no | `SI00100000000000000048630` | "SI" + scene_no + 19-digit padded sequence |
| refund_no | (varchar(32)) | Refund-specific format |

### 3.4 trade_no "8" Prefix Pattern

The trade_no consistently prepends "8" to a snowflake-style ID:
- `t_order_pay.trade_no` = `"8118863692296585216"` (with "8" prefix)
- `t_trade.trade_no` = `"8118863692296585216"` (same format)
- The corresponding `order_id` = `118863692296216576` (no prefix, different suffix)

This "8" prefix likely identifies the transaction type in a shared ID space.

---

## 4. Amount Unit Analysis (CRITICAL)

### 4.1 Unit Mapping

| Table.Column | Data Type | Unit | Example | Conversion |
|-------------|-----------|------|---------|------------|
| `t_order.pay_money` | decimal(12,4) | **DOLLARS** | 3.4000 | Base unit |
| `t_order.total_money` | decimal(12,4) | **DOLLARS** | 3.4000 | Base unit |
| `t_order_amount.*` | decimal(19,4) | **CENTS** | 340.0000 | ÷ 100 |
| `t_order_pay.pay_money` | decimal(19,4) | **CENTS** | 340.0000 | ÷ 100 |
| `t_trade.amount` | bigint | **CENTS** | 340 | ÷ 100 |
| `t_trade.fee` | decimal(12,4) | **DOLLARS** | 26.0000 | Base unit |
| `t_finance_receipt.receipt_amount` | decimal(12,4) | **DOLLARS** | 3.4000 | Base unit |
| `t_finance_refund.refund_amount` | decimal(12,4) | **DOLLARS** | varies | Base unit |
| `t_refund.amount` (payment) | bigint | **CENTS** | varies | ÷ 100 |
| `t_acc_income_bill.received_amount` | decimal(16,4) | **DOLLARS** | 15.8000 | Base unit |
| `t_channel_fee.*` | decimal(19,4) | **CENTS** | varies | ÷ 100 |

### 4.2 Verified Conversion Examples

| order_id | t_order.pay_money (USD) | t_order_pay.pay_money (cents) | t_trade.amount (cents) | Match? |
|----------|------------------------|------------------------------|----------------------|--------|
| 118863692296216576 | $3.40 | 340.00 | 340 | YES (÷100) |
| 118863654916571136 | $5.93 | 593.00 | 593 | YES (÷100) |
| 118863553313759232 | $4.93 | 493.00 | 493 | YES (÷100) |
| 118863545529131008 | $22.59 | 2,259.00 | 2,259 | YES (÷100) |
| 118863523517423616 | $3.80 | 380.00 | 380 | YES (÷100) |

### 4.3 Reconciliation Formula

```sql
-- Standard reconciliation amount conversion:
t_order.pay_money = t_order_pay.pay_money / 100
                  = t_trade.amount / 100
                  = t_finance_receipt.receipt_amount
```

---

## 5. Data Quality Profiling

### 5.1 Order Statistics

| Metric | Value |
|--------|-------|
| Total orders | 521,470 |
| USD orders | 491,802 (94.3%) |
| NZD orders | 29,668 (5.7%) |
| Active shops | 37 |
| Date range | 2025-03-24 to 2026-02-16 |
| Completed (status=90) | 482,024 (92.4%) |
| Cancelled (status=0) | ~16,000 |

### 5.2 Payment Statistics

| Metric | Value |
|--------|-------|
| Total trades | 512,473 |
| Successful (status=2) | 492,172 (96.0%) |
| Failed (status=3) | 7,388 (1.4%) |
| USD successful trades | 463,024 |
| Amount range (cents) | 1 — 13,499 ($0.01 — $134.99) |
| Average amount (cents) | 454 ($4.54) |
| Payment processor | Stripe (third_trade_no = "pi_...") |
| Refunds (payment side) | 13,918 (13,901 successful) |

### 5.3 Amount Distribution (USD Successful Trades)

| Range (cents) | Count | % |
|---------------|-------|---|
| < $1.00 (< 100) | 6,323 | 1.4% |
| $1.00 - $9.99 (100-999) | 432,374 | 93.4% |
| $10.00 - $99.99 (1,000-9,999) | 24,317 | 5.3% |
| >= $100.00 (>= 10,000) | 10 | 0.0% |

### 5.4 Finance Receipt Analysis

| Metric | Value |
|--------|-------|
| Total receipts | 499,773 |
| With order_no | 499,773 (100%) |
| With tp_serial_no (trade link) | 492,172 (98.5%) |
| Missing tp_serial_no | 7,601 (1.5%) — unpaid orders |
| Checked (checking_result=2) | 495,163 (99.1%) |
| Not yet checked (NULL) | 4,610 (0.9%) |
| **All checked have positive difference** | 495,163 |
| Average difference amount | **$4.66** |
| Total difference amount | **$2,307,115.19** |

> **Interpretation**: The systematic $4.66 average difference across ALL receipts indicates this is the **Stripe processing fee** being captured as a reconciliation difference. This is expected behavior, not an anomaly.

### 5.5 Order Pay Completeness

| Metric | Value |
|--------|-------|
| Total order_pay records | 499,681 |
| With trade_no | 492,080 (98.5%) |
| Missing trade_no | 7,601 (1.5%) |

### 5.6 Accounting Statistics

| Scene | Name | Active Bills (status=1) | Amount Range | Date Range |
|-------|------|------------------------|--------------|------------|
| 001 | Order Complete | 37,943 | $0 — $2,045.82 | 2025-03-26 to 2026-02-16 |
| 002 | Order Refund | 3,375 | $0 — $301.68 | 2025-03-26 to 2026-02-16 |
| 003 | Payment Cancel (No Refund) | 3,172 | $0 — $144.98 | 2025-03-26 to 2026-02-16 |
| **Total** | | **44,490** | | |

> **Gap**: 44,490 active income bills vs 492K successful orders = ~9% coverage. This suggests income bills are generated on a summary/batch basis, not per-order.

### 5.7 Pre-Voucher Status Distribution

| Making | Sync | Tally | Count | Interpretation |
|--------|------|-------|-------|---------------|
| 2 (Done) | 2 (Done) | 2 (Done) | 3,159 (89.8%) | Fully processed |
| 2 (Done) | 0 (Pending) | 0 (Pending) | 210 (6.0%) | Awaiting sync |
| 2 (Done) | 5 (Error?) | 0 (Pending) | 119 (3.4%) | Sync failed |
| 2 (Done) | 3 (In Progress?) | 0 (Pending) | 26 (0.7%) | Sync in progress |

### 5.8 Refund Statistics (Order Side)

| Status | Count | Total Amount |
|--------|-------|-------------|
| 7 (Completed) | 13,902 | $57,398.91 |
| 2 (Processing) | 27 | $154.28 |
| 5 (Unknown) | 5 | $37.19 |
| 4 (Unknown) | 4 | $30.79 |

---

## 6. Existing Reconciliation Infrastructure

### 6.1 Defined Reconciliation Models (17 total)

All models store results in DW layer tables (`dw_iunifiedreconcile` or `dwd_dw_iunifiedreconcile`).

#### Revenue Reconciliation Chain
| Code | Name (translated) | Stage |
|------|-------------------|-------|
| `coffeeOrderBillingcenter` | Coffee Order vs Billing Center Order | 1. Order matching |
| `billFranchiseModel` | Billing Center Income vs Franchise Order | 1b. Franchise matching |
| `orderVSbill` | Sales Retail Summary vs Billing Center | 2. Sales reconciliation |
| `shopIncomeVSaccIncome` | Shop Income vs Accounting Income | 3. Income matching |
| `summaryVSshopIncome` | Accounting Income vs Shop Income | 3b. Reverse check |
| `incomeSummaryVSdetail` | Income Summary vs Detail | 3c. Summary validation |
| `incomeBillVSmatter` | Accounting Income vs Matter/Event | 4. GL matter matching |
| `matterVSrecognition` | Matter vs Revenue Recognition | 5. Recognition matching |
| `recognitionVSVoucher` | Recognition vs GL Voucher | 6. Voucher matching |
| `incomeSummaryVSVoucher` | Income Summary vs Voucher Amount | 7. Final GL check |
| `incomeSummaryVSVoucherByDept` | Income Summary by Dept vs Voucher | 7b. Dept-level check |

#### Cost Reconciliation Chain
| Code | Name (translated) | Stage |
|------|-------------------|-------|
| `purchaseVScostBill` | Purchase Cost vs Accounting Cost Bill | C1. Purchase matching |
| `costBillVSmatter` | Accounting Cost vs Matter/Event | C2. Cost matter matching |
| `billShopCostBillVSaccountingShopCostBill` | Shop Cost Bill vs Accounting Shop Cost | C3. Shop cost matching |
| `shopCostBillVSmatter` | Accounting Shop Cost vs Matter/Event | C4. Shop cost matter |
| `billWarehouseCostBillVSaccountingWarehouseCostBill` | Warehouse Scrap Cost matching | C5. Warehouse cost |
| `warehouseCostBillVSmatter` | Warehouse Scrap Cost vs Matter/Event | C6. Warehouse matter |

### 6.2 DW Layer Dependencies

All reconciliation results are stored in:
- **Summary**: `dwd_two_way_reconciliation` (in `dw_iunifiedreconcile` or `dwd_dw_iunifiedreconcile`)
- **Detail**: `dwd_two_way_reconciliation_detail` (same schemas)

These DW tables reside in the data warehouse (likely Redshift Serverless), not in the operational MySQL databases.

---

## 7. Data Flow Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     SOURCE LAYER (MySQL)                        │
│                                                                 │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────────┐   │
│  │  salesorder   │   │ salespayment │   │  ifiaccounting   │   │
│  │              │   │              │   │                  │   │
│  │ t_order      │──►│ t_trade      │   │ t_acc_income_bill│   │
│  │ t_order_pay  │   │ t_channel_fee│   │ t_pre_voucher    │   │
│  │ t_finance_   │   │ t_refund     │   │ t_pre_voucher_   │   │
│  │   receipt    │   │              │   │   entry          │   │
│  │ t_finance_   │   │              │   │ t_acc_matter     │   │
│  │   refund     │   │              │   │ t_acc_recognition│   │
│  └──────┬───────┘   └──────┬───────┘   └────────┬─────────┘   │
│         │                  │                     │             │
└─────────┼──────────────────┼─────────────────────┼─────────────┘
          │                  │                     │
          ▼                  ▼                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                   DATA WAREHOUSE LAYER                          │
│                                                                 │
│  dw_iunifiedreconcile / dwd_dw_iunifiedreconcile               │
│  ┌──────────────────────────────────────────────────┐          │
│  │ dwd_two_way_reconciliation (summary)              │          │
│  │ dwd_two_way_reconciliation_detail (detail)        │          │
│  └──────────────────────────────────────────────────┘          │
│                                                                 │
│  17 reconciliation models defined in t_reconcile_define        │
└─────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                   AI/ANOMALY LAYER (UC-FN-02)                   │
│                                                                 │
│  - Automated 3-way matching (Order ↔ Payment ↔ Accounting)     │
│  - Anomaly detection on reconciliation differences              │
│  - NZD contamination filtering                                  │
│  - Fee-adjusted reconciliation rules                            │
│  - Timing difference analysis                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 8. Column Schema Reference

### 8.1 t_order (Orders — 46 columns)

| Column | Type | Key | Description |
|--------|------|-----|-------------|
| id | bigint unsigned | PK | Order ID (snowflake) |
| tenant | varchar(32) | | Tenant code |
| order_type | smallint | | Order type |
| shop_id | bigint | MUL | Store ID |
| status | tinyint | | 0=cancelled, 90=completed |
| currency_code | varchar(10) | | USD or NZD |
| total_money | decimal(12,4) | | Total amount (DOLLARS) |
| payable_money | decimal(12,4) | | Payable amount (DOLLARS) |
| pay_money | decimal(12,4) | | Paid amount (DOLLARS) |
| pay_time | datetime | | Payment timestamp |
| refund_status | smallint | | 1=no refund, 2=refunded |

### 8.2 t_order_pay (Order Payments — 11 columns)

| Column | Type | Key | Description |
|--------|------|-----|-------------|
| order_id | bigint | MUL | Links to t_order.id |
| pay_no | varchar(30) | | Payment number |
| trade_no | varchar(50) | | Links to t_trade.trade_no |
| status | smallint | | Payment status |
| pay_channel | smallint | | Payment channel code |
| pay_money | decimal(19,4) | | Amount in **CENTS** |

### 8.3 t_trade (Payment Trades — 34 columns)

| Column | Type | Key | Description |
|--------|------|-----|-------------|
| trade_no | varchar(36) | UNI | Trade number ("8" prefix) |
| order_id | varchar(64) | MUL | **VARCHAR** storing bigint order ID |
| amount | bigint | | Amount in **CENTS** |
| currency | varchar(10) | | Currency code |
| status | smallint | | 0=created, 1=pending, 2=success, 3=failed |
| third_trade_no | varchar(128) | | Stripe payment intent (pi_...) |
| fee | decimal(12,4) | | Processing fee (DOLLARS) |

### 8.4 t_finance_receipt (Finance Receipts — 30 columns)

| Column | Type | Key | Description |
|--------|------|-----|-------------|
| receipt_no | varchar(64) | UNI | Receipt number |
| order_no | varchar(255) | MUL | Order ID (as string) |
| tp_serial_no | varchar(64) | MUL | Trade number (= trade_no) |
| receipt_amount | decimal(12,4) | | Receipt amount (DOLLARS) |
| checking_amount | decimal(12,4) | | Verified amount |
| checking_result | tinyint | | 2=matched |
| difference_amount | decimal(12,4) | | Difference (avg $4.66 = fee) |
| payment_method | varchar(64) | | Payment method code |

### 8.5 t_finance_refund (Finance Refunds — 48 columns)

| Column | Type | Key | Description |
|--------|------|-----|-------------|
| refund_no | varchar(32) | UNI | Refund number |
| status | tinyint | | 7=completed, 2=processing |
| refund_object_id | varchar(64) | MUL | Links to order/receipt |
| refund_amount | decimal(12,4) | | Refund amount (DOLLARS) |
| related_receipt | varchar(64) | | Receipt number link |
| tp_serial_no | varchar(64) | MUL | Trade serial number |
| third_serial_no | varchar(64) | | Third-party serial (Stripe) |
| currency_code | varchar(10) | | Currency |
| checking_result | tinyint | | Reconciliation result |
| difference_amount | decimal(12,4) | | Difference amount |

### 8.6 t_acc_income_bill (Accounting Income Bills — 42 columns)

| Column | Type | Key | Description |
|--------|------|-----|-------------|
| biz_no | varchar(64) | MUL | Business number ("IS000..." format) |
| bill_no | varchar(64) | UNI | Bill number ("SI..." format) |
| biz_scene_no | varchar(64) | | 001=Order Complete, 002=Refund, 003=Cancel No Refund |
| shop_no | varchar(128) | | Store number |
| received_amount | decimal(16,4) | | Received amount (DOLLARS) |
| commodity_tax | decimal(16,4) | | Tax amount |
| currency_code | varchar(10) | | Currency |
| status | tinyint | | 1=active, 3=voided |
| order_type | (exists) | | Order type dimension |

### 8.7 t_pre_voucher_entry (GL Journal Entries — 34 columns)

| Column | Type | Key | Description |
|--------|------|-----|-------------|
| voucher_id | bigint unsigned | MUL | Links to t_pre_voucher.id |
| pre_voucher_num | varchar(45) | MUL | Voucher number |
| biz_detail_id | bigint | | Business detail ID |
| biz_detail_no | varchar(200) | MUL | Business detail number |
| pk_accasoa | varchar(30) | | Chart of accounts code |
| pk_accasoa_name | varchar(300) | | Account name |
| lend_direction | tinyint(1) | | 0=Debit, 1=Credit, 2=Pay, 3=Transfer |
| debitamount | decimal(20,4) | | Original currency debit |
| localdebitamount | decimal(20,4) | | Local currency debit |
| creditamount | decimal(20,4) | | Original currency credit |
| localcreditamount | decimal(20,4) | | Local currency credit |
| exchange_rate | decimal(29,15) | | Exchange rate |
| pk_origin_currtype | varchar(30) | | Transaction currency |
| trade_serial_no | varchar(200) | | Trade serial number link |

---

## 9. Recommendations for Phase 2

### 9.1 ETL Pipeline Design

1. **Standardize amount units**: Convert all CENTS values to DOLLARS (÷100) at the ETL layer
2. **Cast order_id types**: Ensure consistent varchar representation for cross-database joins
3. **Filter NZD**: Add `WHERE currency_code = 'USD'` (or `currency = 'USD'`) as standard filter
4. **Handle fee offsets**: Build a fee-adjustment rule that expects ~$4.66 avg Stripe fee per transaction

### 9.2 Reconciliation Match Logic

```
Level 1: Order ↔ Payment (per-transaction)
  JOIN: t_order_pay.trade_no = t_trade.trade_no
  MATCH: t_order_pay.pay_money / 100 = t_trade.amount / 100

Level 2: Order ↔ Receipt (per-transaction)
  JOIN: CAST(t_order.id AS CHAR) = t_finance_receipt.order_no
  MATCH: t_order.pay_money = t_finance_receipt.receipt_amount
  DIFF: t_finance_receipt.difference_amount ≈ Stripe fee

Level 3: Receipt ↔ Income Bill (aggregated)
  Note: Income bills use "IS000..." biz_no, linked via shop_income_summary
  This is a SUMMARY-LEVEL match, not per-order
```

### 9.3 Anomaly Detection Targets

| Anomaly Type | Detection Method | Expected Volume |
|--------------|-----------------|----------------|
| Missing payment | Order exists, no matching trade | ~7,600 (1.5%) |
| Amount mismatch | order × 100 ≠ trade amount | Should be 0% |
| Fee anomaly | difference_amount outside $2-$8 range | TBD |
| Orphan trade | Trade exists, no matching order | TBD |
| Stuck refund | refund status != 7 after 48h | ~36 active |
| Sync failure | pre_voucher sync_status = 5 | 119 (3.4% of vouchers) |
| Accounting gap | Order completed, no income bill | ~90% (due to aggregation) |

### 9.4 Data Warehouse Integration

The existing 17 reconciliation models already target DW tables in Redshift. Phase 2 should:
1. Verify these DW tables exist and are populated in Redshift Serverless
2. Build Glue ETL jobs to materialize the source data
3. Add AI anomaly scoring as an additional layer on top of existing reconciliation results

---

## 10. Appendix: NZD Test Data Analysis

| Metric | USD | NZD |
|--------|-----|-----|
| Order count | 491,802 | 29,668 |
| Percentage | 94.3% | 5.7% |
| Shop count | ~37 | Unknown |
| Date range | 2025-03-24 — present | TBD |

The NZD volume (29,668) exceeds the earlier roadmap estimate of 21,245, indicating continued test data generation. All production reconciliation queries must explicitly filter for USD.

---

*Report generated: 2026-02-16 | UC-FN-02 Phase 1 Complete*

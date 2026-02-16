# UC-FN-02 Phase 3: Anomaly Detection Rules & Engine Design

> **Project**: Revenue Reconciliation Automation
> **Phase**: 3 of 4 — Anomaly Detection Rules
> **Status**: DRAFT
> **Created**: 2026-02-16
> **Depends on**: Phase 2 ETL Pipeline & Reconciliation Design
> **Glue Workflow Slot**: PHASE 6 (`recon-anomaly-scan`)
> **SLA**: 10 min execution (alert at >15 min)

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Overview](#2-architecture-overview)
3. [Anomaly Type Catalog](#3-anomaly-type-catalog)
4. [Detection Rule Definitions](#4-detection-rule-definitions)
   - 4.1 [ANO-01: Missing Payment](#41-ano-01-missing-payment)
   - 4.2 [ANO-02: Amount Mismatch](#42-ano-02-amount-mismatch)
   - 4.3 [ANO-03: Fee Anomaly](#43-ano-03-fee-anomaly)
   - 4.4 [ANO-04: Orphan Trade](#44-ano-04-orphan-trade)
   - 4.5 [ANO-05: Stuck Refund](#45-ano-05-stuck-refund)
   - 4.6 [ANO-06: Sync Failure](#46-ano-06-sync-failure)
   - 4.7 [ANO-07: Accounting Gap](#47-ano-07-accounting-gap)
5. [Severity Scoring Framework](#5-severity-scoring-framework)
6. [Glue Job Implementation](#6-glue-job-implementation)
7. [Result Storage Schema](#7-result-storage-schema)
8. [Alerting & Escalation](#8-alerting--escalation)
9. [AI Anomaly Scoring Layer](#9-ai-anomaly-scoring-layer)
10. [Operational Procedures](#10-operational-procedures)
11. [Appendix A: Threshold Configuration Reference](#appendix-a-threshold-configuration-reference)

---

## 1. Executive Summary

Phase 3 defines the anomaly detection engine that operates as **PHASE 6 (`recon-anomaly-scan`)** in the daily Glue Workflow pipeline `recon-daily-pipeline`. The engine scans reconciliation results from Phase 2's three match levels and flags transactions exhibiting one or more of seven anomaly types identified during Phase 1 schema discovery.

**Key design decisions:**
- **Rule-based engine first**: deterministic SQL/PySpark rules for all 7 anomaly types
- **AI scoring overlay**: ML-based anomaly scoring as a secondary enrichment layer (Phase 1 §9.4 recommendation)
- **Severity tiering**: 4-level severity (CRITICAL / HIGH / MEDIUM / LOW) driving WeCom alert routing
- **SLA-constrained**: entire anomaly scan must complete within 10 minutes on daily volume (~4,000-6,000 orders/day)
- **Idempotent**: re-runnable for any date partition without duplicate anomaly records

**Expected daily anomaly volumes (based on Phase 1 profiling):**

| Anomaly Type | Expected Daily Count | Severity |
|---|---|---|
| Missing payment | ~90-115 (1.5% of ~6,000) | HIGH |
| Amount mismatch (L1) | ~0 (should be 0%) | CRITICAL |
| Fee anomaly | ~10-30 | MEDIUM |
| Orphan trade | ~5-15 | MEDIUM |
| Stuck refund | ~1-3 new/day | HIGH |
| Sync failure | ~5-10 | MEDIUM |
| Accounting gap (L3) | ~80% of L3 results | LOW (expected) |

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    recon-daily-pipeline (Glue Workflow)              │
│                                                                     │
│  PHASE 1-4    PHASE 5           PHASE 6              PHASE 7        │
│  ┌────────┐  ┌──────────────┐  ┌──────────────────┐  ┌───────────┐ │
│  │Extract │→ │Match Engine  │→ │recon-anomaly-scan│→ │Alerting & │ │
│  │& Stage │  │(L1, L2, L3)  │  │(this document)   │  │Reporting  │ │
│  └────────┘  └──────────────┘  └──────────────────┘  └───────────┘ │
│                     │                    │                  │        │
│                     ▼                    ▼                  ▼        │
│              ┌──────────────┐  ┌──────────────────┐  ┌───────────┐ │
│              │Redshift:     │  │Redshift:          │  │WeCom      │ │
│              │stg_recon_    │  │dwd_recon_         │  │Alerts     │ │
│              │level{1,2,3}_ │  │anomalies          │  │           │ │
│              │results       │  │dwd_recon_         │  │           │ │
│              │              │  │anomaly_summary    │  │           │ │
│              └──────────────┘  └──────────────────┘  └───────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

**Data flow:**
1. Read reconciliation results from `stg_recon_level1_results`, `stg_recon_level2_results`, `stg_recon_level3_results` (Redshift)
2. Apply 7 anomaly detection rules as SQL queries
3. Score each anomaly with severity (CRITICAL/HIGH/MEDIUM/LOW) and confidence (0.0-1.0)
4. Write results to `dwd_recon_anomalies` and `dwd_recon_anomaly_summary`
5. Trigger WeCom alerts for HIGH/CRITICAL anomalies
6. Optionally invoke AI anomaly scoring for MEDIUM-severity anomalies

**Input tables** (from Phase 2):
- `stg_recon_level1_results` — Order↔Payment per-transaction match
- `stg_recon_level2_results` — Order↔Receipt per-transaction match with Stripe fees
- `stg_recon_level3_results` — Receipt↔Income Bill aggregated by shop/day
- `stg_recon_orders` — Standardized order staging
- `stg_recon_payments` — Standardized payment staging
- `stg_recon_trades` — Standardized trade staging
- `stg_recon_receipts` — Standardized receipt staging
- `stg_recon_income_bills` — Standardized income bill staging

---

## 3. Anomaly Type Catalog

| ID | Anomaly Type | Source Level | Detection Basis | Business Impact |
|---|---|---|---|---|
| ANO-01 | Missing Payment | Level 1 | Order exists with `pay_status=1`, no matching trade record | Revenue leakage — customer charged but payment not recorded in payment system |
| ANO-02 | Amount Mismatch | Level 1 | `order.pay_money ≠ trade.amount/100` (after CENTS→DOLLARS conversion) | Incorrect revenue recording — discrepancy between order and payment amounts |
| ANO-03 | Fee Anomaly | Level 2 | `difference_amount` (Stripe fee) outside $2.00-$8.00 range | Potential overcharge or processing error |
| ANO-04 | Orphan Trade | Level 1 | Trade record exists with no matching order | Unattributed payment — money received but no order context |
| ANO-05 | Stuck Refund | Source | `t_trade.refund_status NOT IN (0, 7)` AND `created > NOW() - 48h` | Customer experience — refund initiated but not completed |
| ANO-06 | Sync Failure | Source | `t_pre_voucher_entry.sync_status = 5` (sync failed) | Accounting gap — voucher not synced to accounting system |
| ANO-07 | Accounting Gap | Level 3 | Daily shop totals: receipts exist but no income bill, or amount mismatch >$1.00 | Financial reporting gap — revenue not reflected in accounting |

---

## 4. Detection Rule Definitions

### 4.1 ANO-01: Missing Payment

**Business definition**: An order has been marked as paid (`pay_status = 1`) but no corresponding trade record exists in the payment system.

**Detection SQL (Redshift):**

```sql
-- ANO-01: Missing Payment Detection
-- Runs against Level 1 results + source staging tables
-- Expected: ~1.5% of daily orders (~90-115 per day)

INSERT INTO recon.dwd_recon_anomalies (
    anomaly_id, anomaly_type, detection_date, severity, confidence_score,
    order_id, order_id_str, shop_id, shop_name, order_date,
    expected_amount_usd, actual_amount_usd, difference_usd,
    source_system, detail_json, created_at
)
SELECT
    'ANO01-' || o.order_id_str || '-' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD')
        AS anomaly_id,
    'MISSING_PAYMENT' AS anomaly_type,
    CURRENT_DATE AS detection_date,
    CASE
        WHEN o.pay_amount_usd >= 50.00 THEN 'CRITICAL'
        WHEN o.pay_amount_usd >= 20.00 THEN 'HIGH'
        ELSE 'MEDIUM'
    END AS severity,
    0.95 AS confidence_score,  -- high confidence (deterministic rule)
    o.order_id,
    o.order_id_str,
    o.shop_id,
    o.shop_name,
    o.order_date,
    o.pay_amount_usd AS expected_amount_usd,
    0.00 AS actual_amount_usd,
    o.pay_amount_usd AS difference_usd,
    'salesorder.t_order + salespayment.t_trade' AS source_system,
    JSON_SERIALIZE(
        JSON_OBJECT(
            'pay_status': o.pay_status,
            'order_status': o.order_status,
            'payment_type': o.payment_type,
            'order_created_at': o.created_at
        )
    ) AS detail_json,
    GETDATE() AS created_at
FROM recon.stg_recon_orders o
LEFT JOIN recon.stg_recon_trades t
    ON o.order_id_str = t.order_id_str
WHERE o.dt = '{processing_date}'
  AND o.pay_status = 1
  AND o.currency = 'USD'
  AND t.order_id_str IS NULL
  -- Exclude very recent orders (< 2 hours) to allow for async payment processing
  AND o.created_at < DATEADD(hour, -2, GETDATE());
```

**Thresholds:**

| Parameter | Value | Rationale |
|---|---|---|
| Grace period | 2 hours | Allow async payment processing to complete |
| Amount ≥ $50 | CRITICAL | Large missing payments require immediate attention |
| Amount ≥ $20 | HIGH | Moderate missing payments |
| Amount < $20 | MEDIUM | Small amounts, batch review |
| Expected rate | ≤ 2.0% | Alert if missing payment rate exceeds 2% |

---

### 4.2 ANO-02: Amount Mismatch

**Business definition**: Order and trade records both exist but the amounts don't match after CENTS→DOLLARS normalization. This should be 0% under normal conditions.

**Detection SQL (Redshift):**

```sql
-- ANO-02: Amount Mismatch Detection
-- Runs against Level 1 match results where match_status = 'AMOUNT_MISMATCH'
-- Expected: 0% — any occurrence is CRITICAL

INSERT INTO recon.dwd_recon_anomalies (
    anomaly_id, anomaly_type, detection_date, severity, confidence_score,
    order_id, order_id_str, shop_id, shop_name, order_date,
    expected_amount_usd, actual_amount_usd, difference_usd,
    source_system, detail_json, created_at
)
SELECT
    'ANO02-' || l1.order_id_str || '-' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD')
        AS anomaly_id,
    'AMOUNT_MISMATCH' AS anomaly_type,
    CURRENT_DATE AS detection_date,
    'CRITICAL' AS severity,  -- any L1 mismatch is critical
    0.99 AS confidence_score,
    l1.order_id,
    l1.order_id_str,
    l1.shop_id,
    l1.shop_name,
    l1.order_date,
    l1.order_pay_amount_usd AS expected_amount_usd,
    l1.trade_amount_usd AS actual_amount_usd,
    ABS(l1.order_pay_amount_usd - l1.trade_amount_usd) AS difference_usd,
    'stg_recon_level1_results' AS source_system,
    JSON_SERIALIZE(
        JSON_OBJECT(
            'order_pay_money_raw': l1.order_pay_amount_usd,
            'trade_amount_raw_cents': l1.trade_amount_usd * 100,
            'match_status': l1.match_status,
            'trade_no': l1.trade_no
        )
    ) AS detail_json,
    GETDATE() AS created_at
FROM recon.stg_recon_level1_results l1
WHERE l1.dt = '{processing_date}'
  AND l1.match_status = 'AMOUNT_MISMATCH'
  AND ABS(l1.order_pay_amount_usd - l1.trade_amount_usd) > 0.01;
  -- tolerance: $0.01 for rounding
```

**Thresholds:**

| Parameter | Value | Rationale |
|---|---|---|
| Tolerance | $0.01 | Allow for floating-point rounding after CENTS÷100 |
| Any occurrence | CRITICAL | L1 amount mismatches indicate data corruption or conversion bugs |
| Rate threshold | 0.0% | Alert if ANY amount mismatch is found |
| Batch alert | Immediate | Every individual mismatch triggers alert |

---

### 4.3 ANO-03: Fee Anomaly

**Business definition**: Stripe processing fee (`difference_amount` in `t_finance_receipt`) is outside the normal range. Average fee is ~$4.66; normal range is $2.00-$8.00.

**Detection SQL (Redshift):**

```sql
-- ANO-03: Fee Anomaly Detection
-- Runs against Level 2 results examining Stripe fee column
-- Expected: ~10-30 per day (outlier fees)

INSERT INTO recon.dwd_recon_anomalies (
    anomaly_id, anomaly_type, detection_date, severity, confidence_score,
    order_id, order_id_str, shop_id, shop_name, order_date,
    expected_amount_usd, actual_amount_usd, difference_usd,
    source_system, detail_json, created_at
)
SELECT
    'ANO03-' || l2.order_id_str || '-' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD')
        AS anomaly_id,
    'FEE_ANOMALY' AS anomaly_type,
    CURRENT_DATE AS detection_date,
    CASE
        WHEN l2.stripe_fee_usd < 0 THEN 'CRITICAL'       -- negative fee
        WHEN l2.stripe_fee_usd > 20.00 THEN 'HIGH'        -- extremely high fee
        WHEN l2.stripe_fee_usd > 8.00 THEN 'MEDIUM'       -- above normal range
        WHEN l2.stripe_fee_usd < 2.00 AND l2.stripe_fee_usd > 0 THEN 'MEDIUM'  -- below normal range
        ELSE 'LOW'
    END AS severity,
    CASE
        WHEN l2.stripe_fee_usd < 0 THEN 0.99
        WHEN l2.stripe_fee_usd > 20.00 THEN 0.95
        ELSE 0.80
    END AS confidence_score,
    l2.order_id,
    l2.order_id_str,
    l2.shop_id,
    l2.shop_name,
    l2.order_date,
    4.66 AS expected_amount_usd,  -- average Stripe fee
    l2.stripe_fee_usd AS actual_amount_usd,
    ABS(l2.stripe_fee_usd - 4.66) AS difference_usd,
    'stg_recon_level2_results' AS source_system,
    JSON_SERIALIZE(
        JSON_OBJECT(
            'receipt_amount_usd': l2.receipt_amount_usd,
            'net_receipt_usd': l2.net_receipt_usd,
            'fee_pct': ROUND(l2.stripe_fee_usd / NULLIF(l2.receipt_amount_usd, 0) * 100, 2),
            'match_status': l2.match_status
        )
    ) AS detail_json,
    GETDATE() AS created_at
FROM recon.stg_recon_level2_results l2
WHERE l2.dt = '{processing_date}'
  AND l2.stripe_fee_usd IS NOT NULL
  AND (l2.stripe_fee_usd < 2.00 OR l2.stripe_fee_usd > 8.00);
```

**Thresholds:**

| Parameter | Value | Rationale |
|---|---|---|
| Normal range | $2.00 — $8.00 | Based on Phase 1 profiling: avg $4.66, typical Stripe rate 2.9% + $0.30 |
| Negative fee | CRITICAL | Indicates data error or fraudulent adjustment |
| Fee > $20 | HIGH | Fee exceeding ~4x average is highly abnormal |
| Fee outside range | MEDIUM | Worth investigation but not urgent |
| Fee % sanity | > 15% of receipt | Additional check: fee as % of transaction amount |

---

### 4.4 ANO-04: Orphan Trade

**Business definition**: A trade (payment) record exists in `salespayment.t_trade` but has no corresponding order in `salesorder.t_order`. Indicates unattributed payments.

**Detection SQL (Redshift):**

```sql
-- ANO-04: Orphan Trade Detection
-- Inverse of ANO-01: trade exists but no order
-- Expected: ~5-15 per day

INSERT INTO recon.dwd_recon_anomalies (
    anomaly_id, anomaly_type, detection_date, severity, confidence_score,
    order_id, order_id_str, shop_id, shop_name, order_date,
    expected_amount_usd, actual_amount_usd, difference_usd,
    source_system, detail_json, created_at
)
SELECT
    'ANO04-' || t.trade_no || '-' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD')
        AS anomaly_id,
    'ORPHAN_TRADE' AS anomaly_type,
    CURRENT_DATE AS detection_date,
    CASE
        WHEN t.trade_amount_usd >= 50.00 THEN 'HIGH'
        WHEN t.trade_amount_usd >= 20.00 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS severity,
    0.90 AS confidence_score,
    NULL AS order_id,  -- no matching order
    t.order_id_str,     -- order_id reference from trade record
    NULL AS shop_id,
    NULL AS shop_name,
    DATE(t.created_at) AS order_date,
    0.00 AS expected_amount_usd,
    t.trade_amount_usd AS actual_amount_usd,
    t.trade_amount_usd AS difference_usd,
    'salespayment.t_trade' AS source_system,
    JSON_SERIALIZE(
        JSON_OBJECT(
            'trade_no': t.trade_no,
            'trade_type': t.trade_type,
            'trade_status': t.trade_status,
            'refund_status': t.refund_status,
            'trade_created_at': t.created_at
        )
    ) AS detail_json,
    GETDATE() AS created_at
FROM recon.stg_recon_trades t
LEFT JOIN recon.stg_recon_orders o
    ON t.order_id_str = o.order_id_str
WHERE t.dt = '{processing_date}'
  AND o.order_id_str IS NULL
  AND t.trade_status = 1  -- only completed trades
  -- Exclude very recent trades (< 2 hours)
  AND t.created_at < DATEADD(hour, -2, GETDATE());
```

**Thresholds:**

| Parameter | Value | Rationale |
|---|---|---|
| Grace period | 2 hours | Allow for order creation latency |
| Amount ≥ $50 | HIGH | Large unattributed payment |
| Amount ≥ $20 | MEDIUM | Moderate unattributed payment |
| Amount < $20 | LOW | Small amount, batch review |
| Daily rate threshold | > 0.5% of trades | Alert if orphan rate is abnormally high |

---

### 4.5 ANO-05: Stuck Refund

**Business definition**: Refund has been initiated (`refund_status NOT IN (0, 7)`) but not completed or cancelled after 48 hours. Status 0 = no refund, 7 = refund completed.

**Detection SQL (Redshift):**

```sql
-- ANO-05: Stuck Refund Detection
-- Runs against source trade staging table
-- Expected: ~1-3 new per day, ~36 active at any time

INSERT INTO recon.dwd_recon_anomalies (
    anomaly_id, anomaly_type, detection_date, severity, confidence_score,
    order_id, order_id_str, shop_id, shop_name, order_date,
    expected_amount_usd, actual_amount_usd, difference_usd,
    source_system, detail_json, created_at
)
SELECT
    'ANO05-' || t.trade_no || '-' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD')
        AS anomaly_id,
    'STUCK_REFUND' AS anomaly_type,
    CURRENT_DATE AS detection_date,
    CASE
        WHEN DATEDIFF(hour, t.updated_at, GETDATE()) > 168 THEN 'CRITICAL'  -- > 7 days
        WHEN DATEDIFF(hour, t.updated_at, GETDATE()) > 96 THEN 'HIGH'      -- > 4 days
        ELSE 'HIGH'                                                          -- > 48h baseline
    END AS severity,
    0.95 AS confidence_score,
    NULL AS order_id,
    t.order_id_str,
    NULL AS shop_id,
    NULL AS shop_name,
    DATE(t.created_at) AS order_date,
    t.refund_amount_usd AS expected_amount_usd,  -- expected refund
    0.00 AS actual_amount_usd,                    -- refund not completed
    t.refund_amount_usd AS difference_usd,
    'salespayment.t_trade' AS source_system,
    JSON_SERIALIZE(
        JSON_OBJECT(
            'trade_no': t.trade_no,
            'refund_status': t.refund_status,
            'refund_amount_usd': t.refund_amount_usd,
            'hours_stuck': DATEDIFF(hour, t.updated_at, GETDATE()),
            'last_updated': t.updated_at
        )
    ) AS detail_json,
    GETDATE() AS created_at
FROM recon.stg_recon_trades t
WHERE t.dt = '{processing_date}'
  AND t.refund_status NOT IN (0, 7)  -- not "no refund" and not "completed"
  AND DATEDIFF(hour, t.updated_at, GETDATE()) > 48
  -- Deduplicate: only insert if not already flagged today
  AND NOT EXISTS (
      SELECT 1 FROM recon.dwd_recon_anomalies a
      WHERE a.anomaly_type = 'STUCK_REFUND'
        AND a.order_id_str = t.order_id_str
        AND a.detection_date = CURRENT_DATE
  );
```

**Thresholds:**

| Parameter | Value | Rationale |
|---|---|---|
| Stuck threshold | 48 hours | Industry standard for payment processing |
| > 7 days | CRITICAL | Likely requires manual Stripe intervention |
| > 4 days | HIGH | Escalate to payment operations team |
| 48h-96h | HIGH | Initial stuck alert |
| Active count > 50 | CRITICAL batch | Systemic refund processing issue |

---

### 4.6 ANO-06: Sync Failure

**Business definition**: Pre-voucher entries with `sync_status = 5` (sync failed) in `ifiaccounting.t_pre_voucher_entry`, indicating accounting vouchers that failed to sync to the accounting system.

**Detection SQL (Redshift):**

```sql
-- ANO-06: Sync Failure Detection
-- Runs against accounting staging data
-- Expected: ~5-10 per day (3.4% historical rate across all vouchers)

INSERT INTO recon.dwd_recon_anomalies (
    anomaly_id, anomaly_type, detection_date, severity, confidence_score,
    order_id, order_id_str, shop_id, shop_name, order_date,
    expected_amount_usd, actual_amount_usd, difference_usd,
    source_system, detail_json, created_at
)
SELECT
    'ANO06-' || CAST(pv.id AS VARCHAR) || '-' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD')
        AS anomaly_id,
    'SYNC_FAILURE' AS anomaly_type,
    CURRENT_DATE AS detection_date,
    CASE
        WHEN pv.retry_count >= 3 THEN 'HIGH'       -- exhausted retries
        WHEN pv.amount_usd >= 100.00 THEN 'HIGH'   -- large amount
        ELSE 'MEDIUM'
    END AS severity,
    0.99 AS confidence_score,  -- deterministic: sync_status = 5
    NULL AS order_id,
    NULL AS order_id_str,
    pv.shop_id,
    pv.shop_name,
    DATE(pv.voucher_date) AS order_date,
    pv.amount_usd AS expected_amount_usd,
    0.00 AS actual_amount_usd,
    pv.amount_usd AS difference_usd,
    'ifiaccounting.t_pre_voucher_entry' AS source_system,
    JSON_SERIALIZE(
        JSON_OBJECT(
            'voucher_id': pv.id,
            'sync_status': 5,
            'retry_count': pv.retry_count,
            'voucher_type': pv.voucher_type,
            'error_message': pv.error_message,
            'last_sync_attempt': pv.updated_at
        )
    ) AS detail_json,
    GETDATE() AS created_at
FROM recon.stg_recon_vouchers pv
WHERE pv.dt = '{processing_date}'
  AND pv.sync_status = 5;
```

> **Note**: This rule requires adding `stg_recon_vouchers` as a new staging table. See [Section 6.2](#62-additional-staging-table) for the extraction job definition.

**Thresholds:**

| Parameter | Value | Rationale |
|---|---|---|
| sync_status = 5 | Detect all | Every failed sync needs attention |
| Retry exhausted (≥3) | HIGH | Auto-retry failed, needs manual intervention |
| Large amount (≥$100) | HIGH | Financial materiality |
| Daily count > 20 | CRITICAL batch | Systemic sync issue |
| Rate > 5% | CRITICAL batch | Exceeds historical 3.4% baseline |

---

### 4.7 ANO-07: Accounting Gap

**Business definition**: At Level 3, daily shop-level receipts exist but corresponding income bills are missing or amount mismatch exceeds $1.00. Due to aggregation differences, ~80% mismatch is expected at L3 — this rule focuses on **structurally missing** income bills and **large** mismatches.

**Detection SQL (Redshift):**

```sql
-- ANO-07: Accounting Gap Detection
-- Runs against Level 3 results
-- Focus on MISSING_INCOME_BILL and large AMOUNT_MISMATCH (>$50)
-- Note: ~80% of L3 results show AMOUNT_MISMATCH due to aggregation
--   differences; only flag significant gaps

INSERT INTO recon.dwd_recon_anomalies (
    anomaly_id, anomaly_type, detection_date, severity, confidence_score,
    order_id, order_id_str, shop_id, shop_name, order_date,
    expected_amount_usd, actual_amount_usd, difference_usd,
    source_system, detail_json, created_at
)
SELECT
    'ANO07-' || l3.shop_id || '-' || TO_CHAR(l3.business_date, 'YYYYMMDD')
        || '-' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD')
        AS anomaly_id,
    'ACCOUNTING_GAP' AS anomaly_type,
    CURRENT_DATE AS detection_date,
    CASE
        WHEN l3.match_status = 'MISSING_INCOME_BILL'
             AND l3.total_receipt_amount > 500.00 THEN 'HIGH'
        WHEN l3.match_status = 'MISSING_INCOME_BILL' THEN 'MEDIUM'
        WHEN l3.match_status = 'AMOUNT_MISMATCH'
             AND ABS(l3.amount_difference_usd) > 100.00 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS severity,
    CASE
        WHEN l3.match_status = 'MISSING_INCOME_BILL' THEN 0.95
        WHEN l3.match_status = 'AMOUNT_MISMATCH' THEN 0.70  -- lower confidence due to aggregation
        ELSE 0.50
    END AS confidence_score,
    NULL AS order_id,
    NULL AS order_id_str,
    l3.shop_id,
    l3.shop_name,
    l3.business_date AS order_date,
    l3.total_receipt_amount AS expected_amount_usd,
    COALESCE(l3.total_income_amount, 0.00) AS actual_amount_usd,
    ABS(l3.amount_difference_usd) AS difference_usd,
    'stg_recon_level3_results' AS source_system,
    JSON_SERIALIZE(
        JSON_OBJECT(
            'match_status': l3.match_status,
            'receipt_count': l3.receipt_count,
            'income_bill_count': l3.income_bill_count,
            'total_receipt_net': l3.total_net_receipt,
            'total_income': l3.total_income_amount,
            'business_date': l3.business_date
        )
    ) AS detail_json,
    GETDATE() AS created_at
FROM recon.stg_recon_level3_results l3
WHERE l3.dt = '{processing_date}'
  AND (
      -- Structurally missing income bills (always flag)
      l3.match_status = 'MISSING_INCOME_BILL'
      OR
      -- Large amount mismatches only (>$50 to filter noise)
      (l3.match_status = 'AMOUNT_MISMATCH' AND ABS(l3.amount_difference_usd) > 50.00)
  );
```

**Thresholds:**

| Parameter | Value | Rationale |
|---|---|---|
| Missing income bill (any) | Flag all | Structurally missing data always needs investigation |
| Missing + receipt > $500 | HIGH | Large daily revenue not reflected in accounting |
| Amount mismatch > $50 | Flag | Filter out small aggregation differences |
| Amount mismatch > $100 | MEDIUM | Significant daily difference warrants review |
| L3 mismatch < $50 | Suppress | Expected noise from aggregation timing |

---

## 5. Severity Scoring Framework

### 5.1 Severity Levels

| Level | Code | Description | Response Time | Alert Channel |
|---|---|---|---|---|
| CRITICAL | 1 | Data integrity breach, potential revenue loss >$50, or systemic failure | < 30 min | `wecom-critical` (Tier 3) |
| HIGH | 2 | Significant anomaly requiring same-day investigation | < 4 hours | `wecom-warning` (Tier 2) |
| MEDIUM | 3 | Notable pattern requiring review within 24 hours | < 24 hours | Daily digest only |
| LOW | 4 | Informational, expected patterns or small amounts | Next business day | Dashboard only |

### 5.2 Composite Severity Score

When multiple anomalies affect the same order or shop-day, calculate a composite score:

```python
def compute_composite_severity(anomalies: list) -> str:
    """
    Composite severity from multiple anomalies on same entity.
    Any CRITICAL → CRITICAL
    2+ HIGH → CRITICAL
    Any HIGH → HIGH
    3+ MEDIUM → HIGH
    Otherwise → max individual severity
    """
    severity_counts = {'CRITICAL': 0, 'HIGH': 0, 'MEDIUM': 0, 'LOW': 0}
    for a in anomalies:
        severity_counts[a['severity']] += 1

    if severity_counts['CRITICAL'] > 0:
        return 'CRITICAL'
    if severity_counts['HIGH'] >= 2:
        return 'CRITICAL'
    if severity_counts['HIGH'] > 0:
        return 'HIGH'
    if severity_counts['MEDIUM'] >= 3:
        return 'HIGH'
    if severity_counts['MEDIUM'] > 0:
        return 'MEDIUM'
    return 'LOW'
```

### 5.3 Batch-Level Alerts

Beyond individual anomaly severity, batch-level conditions trigger alerts:

| Condition | Severity | Alert |
|---|---|---|
| L1 match rate < 90% | CRITICAL | Immediate — systemic matching failure |
| L2 match rate < 95% | HIGH | Same day — receipt matching degraded |
| Total anomaly count > 2× 30-day average | HIGH | Anomaly spike |
| Any ANO-02 (amount mismatch) detected | CRITICAL | Data integrity |
| Stuck refund active count > 50 | CRITICAL | Payment processing failure |
| Sync failure rate > 5% | CRITICAL | Accounting system issue |
| Pipeline SLA exceeded (>15 min for anomaly phase) | HIGH | Performance degradation |

---

## 6. Glue Job Implementation

### 6.1 Job: `recon-anomaly-scan`

**Configuration:**

| Parameter | Value |
|---|---|
| Job name | `recon-anomaly-scan` |
| Type | PySpark (Glue 4.0) |
| Worker type | G.1X |
| Number of workers | 4 |
| Timeout | 15 minutes |
| Max retries | 1 |
| Max concurrent runs | 1 |
| Trigger | Glue Workflow `recon-daily-pipeline` PHASE 6 (after PHASE 5 match engine completes) |
| Bookmark | Disabled (date-partitioned, idempotent) |
| Connections | `redshift-serverless-recon` |
| Script location | `s3://luckyus-data-lake/scripts/recon/recon_anomaly_scan.py` |

**PySpark implementation:**

```python
"""
recon_anomaly_scan.py
Glue Job: PHASE 6 of recon-daily-pipeline
Anomaly detection engine for revenue reconciliation.

Reads reconciliation results from Redshift, applies 7 detection rules,
writes anomaly records and summary back to Redshift,
triggers WeCom alerts for HIGH/CRITICAL severity.
"""

import sys
import json
import urllib.request
from datetime import datetime, timedelta

from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.types import StringType

# ── Init ─────────────────────────────────────────────────────────────
args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'processing_date',       # YYYY-MM-DD
    'redshift_connection',   # Glue connection name
    'redshift_schema',       # recon
    'wecom_warning_url',     # WeCom Tier 2 webhook
    'wecom_critical_url',    # WeCom Tier 3 webhook
])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

PROCESSING_DATE = args['processing_date']
SCHEMA = args['redshift_schema']
REDSHIFT_CONN = args['redshift_connection']
WECOM_WARNING = args['wecom_warning_url']
WECOM_CRITICAL = args['wecom_critical_url']

start_time = datetime.utcnow()
print(f"[INFO] Anomaly scan started for {PROCESSING_DATE} at {start_time.isoformat()}")


# ── Helpers ──────────────────────────────────────────────────────────

def read_redshift_table(table_name, predicate=None):
    """Read a Redshift table via Glue connection."""
    options = {
        "redshiftTmpDir": "s3://luckyus-data-lake/tmp/redshift/",
        "useConnectionProperties": "true",
        "connectionName": REDSHIFT_CONN,
        "dbtable": f"{SCHEMA}.{table_name}",
    }
    df = glueContext.create_dynamic_frame.from_options(
        connection_type="redshift",
        connection_options=options,
    ).toDF()
    if predicate:
        df = df.filter(predicate)
    return df


def write_redshift_table(df, table_name, mode="append"):
    """Write DataFrame to Redshift table."""
    if df.count() == 0:
        print(f"[INFO] No records to write to {table_name}")
        return
    glueContext.write_dynamic_frame.from_options(
        frame=glueContext.create_dynamic_frame.from_dataframe(df, glueContext, table_name),
        connection_type="redshift",
        connection_options={
            "redshiftTmpDir": "s3://luckyus-data-lake/tmp/redshift/",
            "useConnectionProperties": "true",
            "connectionName": REDSHIFT_CONN,
            "dbtable": f"{SCHEMA}.{table_name}",
            "preactions": f"DELETE FROM {SCHEMA}.{table_name} WHERE detection_date = '{PROCESSING_DATE}'" if mode == "overwrite_partition" else "",
        },
    )
    print(f"[INFO] Wrote {df.count()} records to {table_name}")


def send_wecom_alert(url, title, content, mentioned_list=None):
    """Send alert to WeCom webhook."""
    payload = {
        "msgtype": "markdown",
        "markdown": {
            "content": f"## {title}\n{content}"
        }
    }
    if mentioned_list:
        payload["markdown"]["content"] += f"\n<@{'|@'.join(mentioned_list)}>"
    try:
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode('utf-8'),
            headers={'Content-Type': 'application/json'},
        )
        urllib.request.urlopen(req, timeout=10)
        print(f"[INFO] WeCom alert sent: {title}")
    except Exception as e:
        print(f"[WARN] WeCom alert failed: {e}")


# ── Load source data ────────────────────────────────────────────────

print("[INFO] Loading reconciliation results...")

dt_filter = F.col("dt") == PROCESSING_DATE

l1_results = read_redshift_table("stg_recon_level1_results", dt_filter)
l2_results = read_redshift_table("stg_recon_level2_results", dt_filter)
l3_results = read_redshift_table("stg_recon_level3_results", dt_filter)
orders = read_redshift_table("stg_recon_orders", dt_filter)
trades = read_redshift_table("stg_recon_trades", dt_filter)

l1_results.cache()
l2_results.cache()
l3_results.cache()
orders.cache()
trades.cache()

print(f"[INFO] Loaded: L1={l1_results.count()}, L2={l2_results.count()}, "
      f"L3={l3_results.count()}, Orders={orders.count()}, Trades={trades.count()}")


# ── Anomaly detection rules ─────────────────────────────────────────

anomaly_frames = []

# ── ANO-01: Missing Payment ────────────────────────────────────────
print("[INFO] Running ANO-01: Missing Payment...")
grace_cutoff = (datetime.utcnow() - timedelta(hours=2)).strftime("%Y-%m-%d %H:%M:%S")

missing_payment = (
    orders
    .filter(
        (F.col("pay_status") == 1) &
        (F.col("currency") == "USD") &
        (F.col("created_at") < grace_cutoff)
    )
    .join(trades, orders["order_id_str"] == trades["order_id_str"], "left_anti")
    .withColumn("anomaly_id",
        F.concat(F.lit("ANO01-"), F.col("order_id_str"), F.lit(f"-{PROCESSING_DATE.replace('-','')}")))
    .withColumn("anomaly_type", F.lit("MISSING_PAYMENT"))
    .withColumn("detection_date", F.lit(PROCESSING_DATE))
    .withColumn("severity",
        F.when(F.col("pay_amount_usd") >= 50.0, "CRITICAL")
         .when(F.col("pay_amount_usd") >= 20.0, "HIGH")
         .otherwise("MEDIUM"))
    .withColumn("confidence_score", F.lit(0.95))
    .withColumn("expected_amount_usd", F.col("pay_amount_usd"))
    .withColumn("actual_amount_usd", F.lit(0.0))
    .withColumn("difference_usd", F.col("pay_amount_usd"))
    .withColumn("source_system", F.lit("salesorder.t_order + salespayment.t_trade"))
    .withColumn("created_at", F.current_timestamp())
    .select(
        "anomaly_id", "anomaly_type", "detection_date", "severity",
        "confidence_score", "order_id", "order_id_str", "shop_id",
        "shop_name", "order_date", "expected_amount_usd",
        "actual_amount_usd", "difference_usd", "source_system", "created_at"
    )
)
ano01_count = missing_payment.count()
print(f"[INFO] ANO-01 found: {ano01_count}")
if ano01_count > 0:
    anomaly_frames.append(missing_payment)


# ── ANO-02: Amount Mismatch ────────────────────────────────────────
print("[INFO] Running ANO-02: Amount Mismatch...")
amount_mismatch = (
    l1_results
    .filter(
        (F.col("match_status") == "AMOUNT_MISMATCH") &
        (F.abs(F.col("order_pay_amount_usd") - F.col("trade_amount_usd")) > 0.01)
    )
    .withColumn("anomaly_id",
        F.concat(F.lit("ANO02-"), F.col("order_id_str"), F.lit(f"-{PROCESSING_DATE.replace('-','')}")))
    .withColumn("anomaly_type", F.lit("AMOUNT_MISMATCH"))
    .withColumn("detection_date", F.lit(PROCESSING_DATE))
    .withColumn("severity", F.lit("CRITICAL"))
    .withColumn("confidence_score", F.lit(0.99))
    .withColumn("expected_amount_usd", F.col("order_pay_amount_usd"))
    .withColumn("actual_amount_usd", F.col("trade_amount_usd"))
    .withColumn("difference_usd",
        F.abs(F.col("order_pay_amount_usd") - F.col("trade_amount_usd")))
    .withColumn("source_system", F.lit("stg_recon_level1_results"))
    .withColumn("created_at", F.current_timestamp())
    .select(
        "anomaly_id", "anomaly_type", "detection_date", "severity",
        "confidence_score", "order_id", "order_id_str", "shop_id",
        "shop_name", "order_date", "expected_amount_usd",
        "actual_amount_usd", "difference_usd", "source_system", "created_at"
    )
)
ano02_count = amount_mismatch.count()
print(f"[INFO] ANO-02 found: {ano02_count}")
if ano02_count > 0:
    anomaly_frames.append(amount_mismatch)


# ── ANO-03: Fee Anomaly ────────────────────────────────────────────
print("[INFO] Running ANO-03: Fee Anomaly...")
fee_anomaly = (
    l2_results
    .filter(
        F.col("stripe_fee_usd").isNotNull() &
        ((F.col("stripe_fee_usd") < 2.0) | (F.col("stripe_fee_usd") > 8.0))
    )
    .withColumn("anomaly_id",
        F.concat(F.lit("ANO03-"), F.col("order_id_str"), F.lit(f"-{PROCESSING_DATE.replace('-','')}")))
    .withColumn("anomaly_type", F.lit("FEE_ANOMALY"))
    .withColumn("detection_date", F.lit(PROCESSING_DATE))
    .withColumn("severity",
        F.when(F.col("stripe_fee_usd") < 0, "CRITICAL")
         .when(F.col("stripe_fee_usd") > 20.0, "HIGH")
         .when((F.col("stripe_fee_usd") > 8.0) | (F.col("stripe_fee_usd") < 2.0), "MEDIUM")
         .otherwise("LOW"))
    .withColumn("confidence_score",
        F.when(F.col("stripe_fee_usd") < 0, F.lit(0.99))
         .when(F.col("stripe_fee_usd") > 20.0, F.lit(0.95))
         .otherwise(F.lit(0.80)))
    .withColumn("expected_amount_usd", F.lit(4.66))
    .withColumn("actual_amount_usd", F.col("stripe_fee_usd"))
    .withColumn("difference_usd", F.abs(F.col("stripe_fee_usd") - F.lit(4.66)))
    .withColumn("source_system", F.lit("stg_recon_level2_results"))
    .withColumn("created_at", F.current_timestamp())
    .select(
        "anomaly_id", "anomaly_type", "detection_date", "severity",
        "confidence_score", "order_id", "order_id_str", "shop_id",
        "shop_name", "order_date", "expected_amount_usd",
        "actual_amount_usd", "difference_usd", "source_system", "created_at"
    )
)
ano03_count = fee_anomaly.count()
print(f"[INFO] ANO-03 found: {ano03_count}")
if ano03_count > 0:
    anomaly_frames.append(fee_anomaly)


# ── ANO-04: Orphan Trade ──────────────────────────────────────────
print("[INFO] Running ANO-04: Orphan Trade...")
orphan_trade = (
    trades
    .filter(
        (F.col("trade_status") == 1) &
        (F.col("created_at") < grace_cutoff)
    )
    .join(orders, trades["order_id_str"] == orders["order_id_str"], "left_anti")
    .withColumn("anomaly_id",
        F.concat(F.lit("ANO04-"), F.col("trade_no"), F.lit(f"-{PROCESSING_DATE.replace('-','')}")))
    .withColumn("anomaly_type", F.lit("ORPHAN_TRADE"))
    .withColumn("detection_date", F.lit(PROCESSING_DATE))
    .withColumn("severity",
        F.when(F.col("trade_amount_usd") >= 50.0, "HIGH")
         .when(F.col("trade_amount_usd") >= 20.0, "MEDIUM")
         .otherwise("LOW"))
    .withColumn("confidence_score", F.lit(0.90))
    .withColumn("order_id", F.lit(None).cast("bigint"))
    .withColumn("expected_amount_usd", F.lit(0.0))
    .withColumn("actual_amount_usd", F.col("trade_amount_usd"))
    .withColumn("difference_usd", F.col("trade_amount_usd"))
    .withColumn("source_system", F.lit("salespayment.t_trade"))
    .withColumn("shop_id", F.lit(None).cast("bigint"))
    .withColumn("shop_name", F.lit(None).cast("string"))
    .withColumn("order_date", F.to_date(F.col("created_at")))
    .withColumn("created_at_ts", F.current_timestamp())
    .select(
        "anomaly_id", "anomaly_type", "detection_date", "severity",
        "confidence_score", "order_id", "order_id_str", "shop_id",
        "shop_name", "order_date", "expected_amount_usd",
        "actual_amount_usd", "difference_usd", "source_system",
        F.col("created_at_ts").alias("created_at")
    )
)
ano04_count = orphan_trade.count()
print(f"[INFO] ANO-04 found: {ano04_count}")
if ano04_count > 0:
    anomaly_frames.append(orphan_trade)


# ── ANO-05: Stuck Refund ──────────────────────────────────────────
print("[INFO] Running ANO-05: Stuck Refund...")
stuck_cutoff = (datetime.utcnow() - timedelta(hours=48)).strftime("%Y-%m-%d %H:%M:%S")

stuck_refund = (
    trades
    .filter(
        ~F.col("refund_status").isin(0, 7) &
        (F.col("updated_at") < stuck_cutoff)
    )
    .withColumn("hours_stuck",
        F.round((F.unix_timestamp(F.current_timestamp()) - F.unix_timestamp(F.col("updated_at"))) / 3600, 1))
    .withColumn("anomaly_id",
        F.concat(F.lit("ANO05-"), F.col("trade_no"), F.lit(f"-{PROCESSING_DATE.replace('-','')}")))
    .withColumn("anomaly_type", F.lit("STUCK_REFUND"))
    .withColumn("detection_date", F.lit(PROCESSING_DATE))
    .withColumn("severity",
        F.when(F.col("hours_stuck") > 168, "CRITICAL")  # > 7 days
         .when(F.col("hours_stuck") > 96, "HIGH")        # > 4 days
         .otherwise("HIGH"))                               # > 48h
    .withColumn("confidence_score", F.lit(0.95))
    .withColumn("order_id", F.lit(None).cast("bigint"))
    .withColumn("expected_amount_usd", F.col("refund_amount_usd"))
    .withColumn("actual_amount_usd", F.lit(0.0))
    .withColumn("difference_usd", F.col("refund_amount_usd"))
    .withColumn("source_system", F.lit("salespayment.t_trade"))
    .withColumn("shop_id", F.lit(None).cast("bigint"))
    .withColumn("shop_name", F.lit(None).cast("string"))
    .withColumn("order_date", F.to_date(F.col("created_at")))
    .withColumn("created_at_ts", F.current_timestamp())
    .select(
        "anomaly_id", "anomaly_type", "detection_date", "severity",
        "confidence_score", "order_id", "order_id_str", "shop_id",
        "shop_name", "order_date", "expected_amount_usd",
        "actual_amount_usd", "difference_usd", "source_system",
        F.col("created_at_ts").alias("created_at")
    )
)
ano05_count = stuck_refund.count()
print(f"[INFO] ANO-05 found: {ano05_count}")
if ano05_count > 0:
    anomaly_frames.append(stuck_refund)


# ── ANO-07: Accounting Gap ────────────────────────────────────────
# (ANO-06 Sync Failure requires stg_recon_vouchers — implemented
#  when voucher extraction is added per Section 6.2)
print("[INFO] Running ANO-07: Accounting Gap...")
accounting_gap = (
    l3_results
    .filter(
        (F.col("match_status") == "MISSING_INCOME_BILL") |
        ((F.col("match_status") == "AMOUNT_MISMATCH") &
         (F.abs(F.col("amount_difference_usd")) > 50.0))
    )
    .withColumn("anomaly_id",
        F.concat(
            F.lit("ANO07-"),
            F.col("shop_id").cast("string"),
            F.lit("-"),
            F.date_format(F.col("business_date"), "yyyyMMdd"),
            F.lit(f"-{PROCESSING_DATE.replace('-','')}")
        ))
    .withColumn("anomaly_type", F.lit("ACCOUNTING_GAP"))
    .withColumn("detection_date", F.lit(PROCESSING_DATE))
    .withColumn("severity",
        F.when(
            (F.col("match_status") == "MISSING_INCOME_BILL") &
            (F.col("total_receipt_amount") > 500.0), "HIGH")
         .when(F.col("match_status") == "MISSING_INCOME_BILL", "MEDIUM")
         .when(F.abs(F.col("amount_difference_usd")) > 100.0, "MEDIUM")
         .otherwise("LOW"))
    .withColumn("confidence_score",
        F.when(F.col("match_status") == "MISSING_INCOME_BILL", F.lit(0.95))
         .otherwise(F.lit(0.70)))
    .withColumn("order_id", F.lit(None).cast("bigint"))
    .withColumn("order_id_str", F.lit(None).cast("string"))
    .withColumn("expected_amount_usd", F.col("total_receipt_amount"))
    .withColumn("actual_amount_usd",
        F.coalesce(F.col("total_income_amount"), F.lit(0.0)))
    .withColumn("difference_usd", F.abs(F.col("amount_difference_usd")))
    .withColumn("source_system", F.lit("stg_recon_level3_results"))
    .withColumn("created_at", F.current_timestamp())
    .select(
        "anomaly_id", "anomaly_type", "detection_date", "severity",
        "confidence_score", "order_id", "order_id_str", "shop_id",
        "shop_name", "order_date", "expected_amount_usd",
        "actual_amount_usd", "difference_usd", "source_system", "created_at"
    )
)
# Fix: L3 has business_date not order_date
accounting_gap = accounting_gap.drop("order_date").withColumnRenamed("business_date", "order_date") \
    if "business_date" in accounting_gap.columns else accounting_gap
ano07_count = accounting_gap.count()
print(f"[INFO] ANO-07 found: {ano07_count}")
if ano07_count > 0:
    anomaly_frames.append(accounting_gap)


# ── Combine & Write ──────────────────────────────────────────────
print("[INFO] Combining anomaly results...")

if anomaly_frames:
    from functools import reduce
    all_anomalies = reduce(lambda a, b: a.unionByName(b, allowMissingColumns=True), anomaly_frames)
    total_count = all_anomalies.count()
    print(f"[INFO] Total anomalies detected: {total_count}")

    # Delete existing records for this date (idempotent)
    write_redshift_table(all_anomalies, "dwd_recon_anomalies", mode="overwrite_partition")

    # ── Build summary ────────────────────────────────────────────
    summary = (
        all_anomalies
        .groupBy("detection_date", "anomaly_type", "severity")
        .agg(
            F.count("*").alias("anomaly_count"),
            F.sum("difference_usd").alias("total_difference_usd"),
            F.avg("confidence_score").alias("avg_confidence"),
            F.min("difference_usd").alias("min_difference_usd"),
            F.max("difference_usd").alias("max_difference_usd"),
        )
        .withColumn("created_at", F.current_timestamp())
    )
    write_redshift_table(summary, "dwd_recon_anomaly_summary", mode="overwrite_partition")

    # ── Alerting ─────────────────────────────────────────────────
    critical_count = all_anomalies.filter(F.col("severity") == "CRITICAL").count()
    high_count = all_anomalies.filter(F.col("severity") == "HIGH").count()

    # Batch-level checks
    l1_total = l1_results.count()
    l1_matched = l1_results.filter(F.col("match_status") == "MATCHED").count()
    l1_rate = (l1_matched / l1_total * 100) if l1_total > 0 else 0

    if critical_count > 0 or ano02_count > 0 or l1_rate < 90:
        alert_body = (
            f"**Date**: {PROCESSING_DATE}\n"
            f"**CRITICAL anomalies**: {critical_count}\n"
            f"**HIGH anomalies**: {high_count}\n"
            f"**Total anomalies**: {total_count}\n"
            f"**L1 match rate**: {l1_rate:.1f}%\n\n"
        )
        if ano02_count > 0:
            alert_body += f"⚠️ **{ano02_count} amount mismatches detected** — data integrity issue\n"
        if l1_rate < 90:
            alert_body += f"⚠️ **L1 match rate {l1_rate:.1f}% < 90%** — systemic failure\n"

        send_wecom_alert(
            WECOM_CRITICAL,
            "🚨 Revenue Recon: CRITICAL Anomalies",
            alert_body
        )

    elif high_count > 0:
        alert_body = (
            f"**Date**: {PROCESSING_DATE}\n"
            f"**HIGH anomalies**: {high_count}\n"
            f"**Total anomalies**: {total_count}\n"
            f"**L1 match rate**: {l1_rate:.1f}%\n"
        )
        send_wecom_alert(
            WECOM_WARNING,
            "⚠️ Revenue Recon: HIGH Anomalies",
            alert_body
        )

    print(f"[INFO] Alerting complete. CRITICAL={critical_count}, HIGH={high_count}")

else:
    print("[INFO] No anomalies detected.")
    total_count = 0


# ── SLA check ────────────────────────────────────────────────────
elapsed = (datetime.utcnow() - start_time).total_seconds() / 60
print(f"[INFO] Anomaly scan completed in {elapsed:.1f} minutes")

if elapsed > 15:
    send_wecom_alert(
        WECOM_WARNING,
        "⚠️ Revenue Recon: SLA Exceeded",
        f"Anomaly scan took {elapsed:.1f} min (SLA: 10 min, alert: 15 min)\n"
        f"Date: {PROCESSING_DATE}"
    )
elif elapsed > 10:
    print(f"[WARN] Anomaly scan approaching SLA: {elapsed:.1f} min (target: 10 min)")

job.commit()
print(f"[INFO] Job complete. {total_count} anomalies written.")
```

### 6.2 Additional Staging Table: `stg_recon_vouchers`

ANO-06 (Sync Failure) requires pre-voucher data not covered by Phase 2's existing 5 staging tables. Add a new extraction job:

**Extraction job**: `recon-extract-vouchers`

| Parameter | Value |
|---|---|
| Source | `aws-luckyus-ifiaccounting-rw` / `ifiaccounting.t_pre_voucher_entry` |
| Target | `s3://luckyus-data-lake/staging/reconciliation/vouchers/dt={date}/` |
| Redshift table | `recon.stg_recon_vouchers` |
| Schedule | PHASE 1 of `recon-daily-pipeline` (parallel with other extractions) |

**Column mapping:**

| Staging Column | Source Column | Transformation |
|---|---|---|
| id | id | Direct (bigint) |
| shop_id | shop_id | Direct |
| shop_name | shop_name | Direct |
| voucher_date | voucher_date | Direct (date) |
| voucher_type | voucher_type | Direct |
| amount_usd | amount | Direct (already DOLLARS) |
| sync_status | sync_status | Direct (int: 0=pending, 1=synced, 5=failed) |
| retry_count | retry_count | Direct |
| error_message | error_message | Direct (varchar) |
| created_at | create_time | Direct |
| updated_at | update_time | Direct |
| dt | — | Partition key: `DATE(update_time)` |

**Extraction SQL:**

```sql
SELECT
    id,
    shop_id,
    shop_name,
    voucher_date,
    voucher_type,
    amount AS amount_usd,
    sync_status,
    retry_count,
    error_message,
    create_time AS created_at,
    update_time AS updated_at
FROM t_pre_voucher_entry
WHERE update_time >= '{start_watermark}'
  AND update_time < '{end_watermark}'
  AND is_deleted = 0;
```

---

## 7. Result Storage Schema

### 7.1 `dwd_recon_anomalies` (Redshift)

```sql
CREATE TABLE IF NOT EXISTS recon.dwd_recon_anomalies (
    anomaly_id          VARCHAR(128)   NOT NULL,   -- e.g., ANO01-123456-20260216
    anomaly_type        VARCHAR(32)    NOT NULL,   -- MISSING_PAYMENT, AMOUNT_MISMATCH, etc.
    detection_date      DATE           NOT NULL,   -- processing date
    severity            VARCHAR(16)    NOT NULL,   -- CRITICAL, HIGH, MEDIUM, LOW
    confidence_score    DECIMAL(3,2)   NOT NULL,   -- 0.00 - 1.00
    order_id            BIGINT,                     -- may be NULL for orphan/sync anomalies
    order_id_str        VARCHAR(32),                -- string version of order_id
    shop_id             BIGINT,
    shop_name           VARCHAR(128),
    order_date          DATE,
    expected_amount_usd DECIMAL(12,2),
    actual_amount_usd   DECIMAL(12,2),
    difference_usd      DECIMAL(12,2),
    source_system       VARCHAR(128),
    detail_json         VARCHAR(4096),              -- JSON with anomaly-specific details
    ai_score            DECIMAL(5,4),               -- ML anomaly score (NULL until AI layer runs)
    ai_recommendation   VARCHAR(512),               -- ML recommended action (NULL until AI layer)
    resolution_status   VARCHAR(32)    DEFAULT 'OPEN',  -- OPEN, INVESTIGATING, RESOLVED, FALSE_POSITIVE
    resolved_by         VARCHAR(64),
    resolved_at         TIMESTAMP,
    resolution_notes    VARCHAR(1024),
    created_at          TIMESTAMP      NOT NULL DEFAULT GETDATE(),
    updated_at          TIMESTAMP      DEFAULT GETDATE(),

    PRIMARY KEY (anomaly_id)
)
DISTSTYLE KEY
DISTKEY (shop_id)
SORTKEY (detection_date, anomaly_type, severity);

COMMENT ON TABLE recon.dwd_recon_anomalies IS 'Revenue reconciliation anomaly detail records';
```

### 7.2 `dwd_recon_anomaly_summary` (Redshift)

```sql
CREATE TABLE IF NOT EXISTS recon.dwd_recon_anomaly_summary (
    detection_date      DATE           NOT NULL,
    anomaly_type        VARCHAR(32)    NOT NULL,
    severity            VARCHAR(16)    NOT NULL,
    anomaly_count       INTEGER        NOT NULL,
    total_difference_usd DECIMAL(14,2),
    avg_confidence      DECIMAL(3,2),
    min_difference_usd  DECIMAL(12,2),
    max_difference_usd  DECIMAL(12,2),
    created_at          TIMESTAMP      NOT NULL DEFAULT GETDATE(),

    PRIMARY KEY (detection_date, anomaly_type, severity)
)
DISTSTYLE ALL
SORTKEY (detection_date, anomaly_type);

COMMENT ON TABLE recon.dwd_recon_anomaly_summary IS 'Daily anomaly count summary by type and severity';
```

### 7.3 `dwd_recon_anomaly_metrics` (Redshift)

```sql
CREATE TABLE IF NOT EXISTS recon.dwd_recon_anomaly_metrics (
    metric_date         DATE           NOT NULL,
    total_orders        INTEGER,
    total_trades        INTEGER,
    l1_match_rate       DECIMAL(5,2),       -- %
    l2_match_rate       DECIMAL(5,2),       -- %
    l3_match_rate       DECIMAL(5,2),       -- %
    total_anomalies     INTEGER,
    critical_count      INTEGER,
    high_count          INTEGER,
    medium_count        INTEGER,
    low_count           INTEGER,
    total_difference_usd DECIMAL(14,2),
    missing_payment_count INTEGER,
    amount_mismatch_count INTEGER,
    fee_anomaly_count   INTEGER,
    orphan_trade_count  INTEGER,
    stuck_refund_count  INTEGER,
    sync_failure_count  INTEGER,
    accounting_gap_count INTEGER,
    scan_duration_sec   INTEGER,
    created_at          TIMESTAMP      NOT NULL DEFAULT GETDATE(),

    PRIMARY KEY (metric_date)
)
DISTSTYLE ALL
SORTKEY (metric_date);

COMMENT ON TABLE recon.dwd_recon_anomaly_metrics IS 'Daily pipeline and anomaly detection metrics';
```

---

## 8. Alerting & Escalation

### 8.1 Alert Routing Matrix

| Condition | Channel | Tier | Template |
|---|---|---|---|
| Any ANO-02 (amount mismatch) | `wecom-critical` | Tier 3 | `RECON_AMOUNT_MISMATCH` |
| L1 match rate < 90% | `wecom-critical` | Tier 3 | `RECON_MATCH_RATE_CRITICAL` |
| Stuck refund active > 50 | `wecom-critical` | Tier 3 | `RECON_STUCK_REFUND_BATCH` |
| CRITICAL severity anomalies > 0 | `wecom-critical` | Tier 3 | `RECON_CRITICAL_ANOMALY` |
| HIGH severity anomalies > 0 | `wecom-warning` | Tier 2 | `RECON_HIGH_ANOMALY` |
| Anomaly count > 2× 30-day avg | `wecom-warning` | Tier 2 | `RECON_ANOMALY_SPIKE` |
| Scan SLA exceeded (>15 min) | `wecom-warning` | Tier 2 | `RECON_SLA_EXCEEDED` |
| Pipeline failure | `wecom-warning` | Tier 2 | `RECON_PIPELINE_FAIL` |
| No anomalies (all clear) | — | — | Log only |
| MEDIUM/LOW anomalies only | — | — | Daily digest email |

### 8.2 WeCom Alert Templates

**RECON_CRITICAL_ANOMALY:**
```
## 🚨 Revenue Recon: CRITICAL Anomalies
**Date**: {processing_date}
**CRITICAL**: {critical_count} | **HIGH**: {high_count} | **Total**: {total_count}
**L1 Match Rate**: {l1_rate}%
**Total Difference**: ${total_difference:,.2f}

### Breakdown
{anomaly_type_summary}

**Action Required**: Investigate immediately. Dashboard: {dashboard_url}
```

**RECON_HIGH_ANOMALY:**
```
## ⚠️ Revenue Recon: HIGH Anomalies
**Date**: {processing_date}
**HIGH**: {high_count} | **MEDIUM**: {medium_count} | **Total**: {total_count}
**L1 Match Rate**: {l1_rate}%

### Top Anomalies
{top_5_anomalies}

**Action**: Review within 4 hours. Dashboard: {dashboard_url}
```

### 8.3 Escalation Policy

```
Level 1 (0-30 min):     Finance Ops team via WeCom
Level 2 (30 min-2 hr):  Finance Manager + DBA team
Level 3 (2 hr-4 hr):    Finance Director + Engineering Lead
Level 4 (>4 hr):        CFO notification
```

---

## 9. AI Anomaly Scoring Layer

Per Phase 1 §9.4 recommendation, an AI/ML scoring layer provides:
1. **False positive reduction** — learn from historical resolution data
2. **Anomaly clustering** — group related anomalies by root cause
3. **Severity refinement** — adjust rule-based severity using context
4. **Trend detection** — identify emerging patterns before they breach thresholds

### 9.1 Model Design

| Component | Specification |
|---|---|
| Model type | Isolation Forest + gradient-boosted classifier ensemble |
| MLflow name | `finance-uc-fn-02-anomaly-scorer` |
| Training data | Historical anomalies with resolution labels (min 90 days) |
| Features | Amount, fee %, time-of-day, shop volume, day-of-week, anomaly type, L1/L2/L3 match rates |
| Target | Binary: TRUE_ANOMALY vs FALSE_POSITIVE |
| Output | `ai_score` (0.0-1.0), `ai_recommendation` (text) |
| Retraining | Weekly on Sundays using resolved anomaly data |
| Inference SLA | < 2 min for daily batch (included in 10-min budget) |

### 9.2 Feature Engineering

```python
# Feature vector for each anomaly record
features = {
    # Transaction features
    'amount_usd': float,              # transaction amount
    'fee_pct': float,                 # Stripe fee as % of amount
    'amount_z_score': float,          # z-score vs shop daily average

    # Temporal features
    'hour_of_day': int,               # 0-23
    'day_of_week': int,               # 0-6 (Mon=0)
    'is_weekend': bool,
    'days_since_last_anomaly': int,   # same type, same shop

    # Shop context
    'shop_daily_order_count': int,
    'shop_daily_revenue_usd': float,
    'shop_anomaly_rate_30d': float,   # rolling 30-day anomaly rate

    # Match context
    'l1_match_rate_today': float,
    'l2_match_rate_today': float,
    'l3_match_rate_today': float,

    # Anomaly type encoding
    'anomaly_type_encoded': int,      # one-hot or ordinal
    'rule_confidence': float,         # from detection rule
}
```

### 9.3 Integration Point

The AI scoring runs **after** rule-based detection within the same Glue job:

```python
# In recon_anomaly_scan.py, after writing rule-based anomalies:

if ENABLE_AI_SCORING and total_count > 0:
    print("[INFO] Running AI anomaly scoring...")

    # Load model from MLflow
    import mlflow
    model = mlflow.pyfunc.load_model(
        f"models:/finance-uc-fn-02-anomaly-scorer/Production"
    )

    # Prepare features (broadcast for Spark UDF)
    # Score each anomaly
    # Update ai_score and ai_recommendation columns in dwd_recon_anomalies

    # Reclassify: if ai_score < 0.3 AND rule severity <= MEDIUM,
    # downgrade to LOW (likely false positive)
```

### 9.4 Implementation Timeline

| Phase | Timeline | Description |
|---|---|---|
| Phase 3a (now) | Immediate | Rule-based detection (this document) — deploy first |
| Phase 3b | After 90 days of data | Train initial AI model on resolved anomaly data |
| Phase 3c | Ongoing | Weekly retraining, feedback loop from resolution_status |

> **Note**: AI scoring is **not required** for initial deployment. The rule-based engine operates independently. AI scoring is an enrichment layer added once sufficient historical data (90+ days of resolved anomalies) is available.

---

## 10. Operational Procedures

### 10.1 Daily Operations Checklist

| Time (ET) | Action | Tool |
|---|---|---|
| 01:00 | Pipeline triggers (UTC 06:00) | Automatic — Glue Workflow |
| 02:15 | Verify anomaly scan completed | Glue console / CloudWatch |
| 02:30 | Review CRITICAL/HIGH alerts | WeCom |
| 09:00 | Review daily anomaly summary | Redshift dashboard |
| 09:30 | Triage MEDIUM anomalies | Redshift query |
| EOD | Update resolution_status for investigated anomalies | Redshift UPDATE |

### 10.2 Anomaly Resolution Workflow

```
1. Anomaly detected → dwd_recon_anomalies (status=OPEN)
2. Alert sent → WeCom (CRITICAL/HIGH) or digest (MEDIUM/LOW)
3. Analyst investigates → UPDATE resolution_status = 'INVESTIGATING'
4. Root cause found → UPDATE resolution_notes, resolved_by
5. Fixed or classified → UPDATE resolution_status = 'RESOLVED' or 'FALSE_POSITIVE'
6. AI model consumes resolution data → weekly retraining
```

### 10.3 Resolution Status Values

| Status | Description |
|---|---|
| OPEN | Newly detected, pending investigation |
| INVESTIGATING | Analyst actively reviewing |
| RESOLVED | Root cause identified and addressed |
| FALSE_POSITIVE | Detection was incorrect — feeds AI training |
| WONT_FIX | Known issue, accepted risk |

### 10.4 Backfill Procedure

To run anomaly detection on historical data:

```bash
# Run for a single date
aws glue start-job-run \
  --job-name recon-anomaly-scan \
  --arguments '{
    "--processing_date": "2025-12-15",
    "--redshift_connection": "redshift-serverless-recon",
    "--redshift_schema": "recon",
    "--wecom_warning_url": "DISABLED",
    "--wecom_critical_url": "DISABLED"
  }'

# Backfill range (use Phase 2 backfill script pattern)
for dt in $(seq -f "%02g" 1 31); do
  aws glue start-job-run \
    --job-name recon-anomaly-scan \
    --arguments "{
      \"--processing_date\": \"2026-01-${dt}\",
      \"--redshift_connection\": \"redshift-serverless-recon\",
      \"--redshift_schema\": \"recon\",
      \"--wecom_warning_url\": \"DISABLED\",
      \"--wecom_critical_url\": \"DISABLED\"
    }"
  sleep 30  # avoid concurrent run conflicts
done
```

> **Note**: Set WeCom URLs to `DISABLED` during backfill to suppress historical alerts.

---

## Appendix A: Threshold Configuration Reference

All thresholds are parameterized for runtime adjustment without code changes. Store in DynamoDB or SSM Parameter Store.

| Parameter Path | Default | Description |
|---|---|---|
| `/recon/ano01/grace_period_hours` | 2 | Hours before flagging missing payment |
| `/recon/ano01/critical_amount_usd` | 50.00 | Amount threshold for CRITICAL severity |
| `/recon/ano01/high_amount_usd` | 20.00 | Amount threshold for HIGH severity |
| `/recon/ano01/rate_alert_pct` | 2.0 | Missing payment % triggering batch alert |
| `/recon/ano02/tolerance_usd` | 0.01 | Rounding tolerance for amount match |
| `/recon/ano03/fee_min_usd` | 2.00 | Lower bound of normal Stripe fee |
| `/recon/ano03/fee_max_usd` | 8.00 | Upper bound of normal Stripe fee |
| `/recon/ano03/fee_critical_usd` | 20.00 | Fee threshold for HIGH severity |
| `/recon/ano04/grace_period_hours` | 2 | Hours before flagging orphan trade |
| `/recon/ano04/high_amount_usd` | 50.00 | Amount threshold for HIGH severity |
| `/recon/ano05/stuck_threshold_hours` | 48 | Hours before refund considered stuck |
| `/recon/ano05/critical_hours` | 168 | Hours (7 days) for CRITICAL stuck refund |
| `/recon/ano05/batch_critical_count` | 50 | Active stuck refunds triggering CRITICAL |
| `/recon/ano06/rate_critical_pct` | 5.0 | Sync failure % triggering CRITICAL |
| `/recon/ano06/daily_critical_count` | 20 | Daily sync failures triggering CRITICAL |
| `/recon/ano07/mismatch_threshold_usd` | 50.00 | L3 mismatch to flag (filter noise) |
| `/recon/ano07/high_receipt_usd` | 500.00 | Missing bill + receipt > $500 = HIGH |
| `/recon/batch/l1_critical_rate_pct` | 90.0 | L1 match rate below = CRITICAL |
| `/recon/batch/l2_alert_rate_pct` | 95.0 | L2 match rate below = HIGH |
| `/recon/batch/anomaly_spike_multiplier` | 2.0 | Anomaly count vs 30-day avg multiplier |
| `/recon/sla/anomaly_scan_target_min` | 10 | Target SLA in minutes |
| `/recon/sla/anomaly_scan_alert_min` | 15 | SLA alert threshold in minutes |
| `/recon/ai/enable_scoring` | false | Enable AI anomaly scoring layer |
| `/recon/ai/false_positive_threshold` | 0.3 | AI score below = likely false positive |

---

*End of Phase 3: Anomaly Detection Rules & Engine Design*
*Next: Phase 4 — Dashboard, Reporting & Deployment Guide*

# UC-FN-02 Phase 2: ETL Pipeline & Reconciliation Design

> **Use Case:** UC-FN-02 Revenue Reconciliation Automation
> **Phase:** 2 of 4 — ETL Pipeline & Reconciliation Match Logic
> **Date:** 2026-02-16 | **Status:** Complete
> **Depends On:** Phase 1 Schema Discovery Report
> **Author:** Claude Code (DBA/Infrastructure Team)

---

## Table of Contents

1. [ETL Architecture Overview](#1-etl-architecture-overview)
2. [Source Extraction Layer](#2-source-extraction-layer)
3. [Data Standardization Rules](#3-data-standardization-rules)
4. [Staging Table Designs](#4-staging-table-designs)
5. [Reconciliation Match Logic — Level 1](#5-reconciliation-match-logic--level-1)
6. [Reconciliation Match Logic — Level 2](#6-reconciliation-match-logic--level-2)
7. [Reconciliation Match Logic — Level 3](#7-reconciliation-match-logic--level-3)
8. [Data Quality Validation Rules](#8-data-quality-validation-rules)
9. [ETL Scheduling & Dependencies](#9-etl-scheduling--dependencies)
10. [Error Handling & Recovery](#10-error-handling--recovery)

---

## 1. ETL Architecture Overview

### Pipeline Topology

```
┌─────────────────────────────────────────────────────────────────────┐
│                     SOURCE EXTRACTION LAYER                        │
│                                                                     │
│  salesorder-rw ──┐                                                  │
│  salespayment-rw ┼──► Glue ETL Jobs ──► S3 Staging (Parquet)       │
│  ifiaccounting-rw┤                          │                       │
│  iunifiedreconcile-rw                       │                       │
│                                              ▼                      │
│                              ┌──────────────────────────┐           │
│                              │  STANDARDIZATION LAYER    │           │
│                              │  • CENTS → DOLLARS (÷100) │           │
│                              │  • order_id CAST          │           │
│                              │  • NZD filter             │           │
│                              │  • Stripe fee normalize   │           │
│                              │  • Timezone UTC align     │           │
│                              └──────────┬───────────────┘           │
│                                          │                          │
│                                          ▼                          │
│                    ┌────────────────────────────────────┐            │
│                    │    RECONCILIATION MATCH ENGINE      │            │
│                    │                                      │            │
│                    │  Level 1: Order ↔ Payment (per-tx)  │            │
│                    │  Level 2: Order ↔ Receipt (per-tx)  │            │
│                    │  Level 3: Receipt ↔ Income (agg)    │            │
│                    └──────────┬─────────────────────────┘            │
│                               │                                      │
│                               ▼                                      │
│              ┌──────────────────────────────────┐                    │
│              │   RESULTS → Redshift Serverless   │                    │
│              │   dwd_two_way_reconciliation       │                    │
│              │   dwd_two_way_reconciliation_detail│                    │
│              └──────────────────────────────────┘                    │
└─────────────────────────────────────────────────────────────────────┘
```

### Technology Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Extraction | AWS Glue (PySpark) | Read from 4 MySQL sources |
| Staging | S3 `s3://luckyus-data-lake/staging/reconciliation/` | Parquet intermediate storage |
| Standardization | Glue ETL transforms | Unit conversion, type casting, filtering |
| Match Engine | Glue ETL / Redshift SQL | 3-level reconciliation logic |
| Results Store | Redshift Serverless | DW tables for reporting & anomaly detection |
| Orchestration | Glue Workflows + Triggers | Scheduling, dependency management |
| Monitoring | CloudWatch + Grafana | Pipeline health, SLA tracking |

---

## 2. Source Extraction Layer

### 2.1 Extraction Jobs

Each source database has a dedicated Glue extraction job reading via JDBC.

#### Job: `recon-extract-salesorder`

```python
# Glue ETL Job: recon-extract-salesorder
# Source: aws-luckyus-salesorder-rw / luckyus_sales_order
# Target: s3://luckyus-data-lake/staging/reconciliation/orders/

import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql import functions as F

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'run_date'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

run_date = args['run_date']  # YYYY-MM-DD

# --- Extract t_order ---
order_query = f"""
(SELECT
    id AS order_id,
    order_no,
    shop_id,
    user_id,
    pay_money,           -- DOLLARS (no conversion needed)
    discount_money,
    order_status,
    pay_status,
    currency_code,
    order_type,
    order_source,
    create_time,
    update_time,
    pay_time,
    complete_time
FROM t_order
WHERE DATE(create_time) = '{run_date}'
  AND currency_code = 'USD'
  AND is_del = 0
) AS t_order_extract
"""

df_order = spark.read.format("jdbc") \
    .option("url", "jdbc:mysql://aws-luckyus-salesorder-rw:3306/luckyus_sales_order") \
    .option("dbtable", order_query) \
    .option("user", "${ssm:/luckyus/db/salesorder/user}") \
    .option("password", "${ssm:/luckyus/db/salesorder/password}") \
    .option("fetchsize", "10000") \
    .load()

# --- Extract t_order_pay ---
order_pay_query = f"""
(SELECT
    id,
    order_id,
    trade_no,
    pay_money,           -- CENTS (needs ÷100)
    pay_type,
    pay_status,
    create_time,
    update_time
FROM t_order_pay
WHERE DATE(create_time) = '{run_date}'
  AND is_del = 0
) AS t_order_pay_extract
"""

df_order_pay = spark.read.format("jdbc") \
    .option("url", "jdbc:mysql://aws-luckyus-salesorder-rw:3306/luckyus_sales_order") \
    .option("dbtable", order_pay_query) \
    .option("user", "${ssm:/luckyus/db/salesorder/user}") \
    .option("password", "${ssm:/luckyus/db/salesorder/password}") \
    .option("fetchsize", "10000") \
    .load()

# --- Extract t_finance_receipt ---
receipt_query = f"""
(SELECT
    id AS receipt_id,
    order_id,
    order_no,
    tp_serial_no,
    receipt_amount,       -- DOLLARS (no conversion needed)
    difference_amount,    -- Stripe fee offset (DOLLARS)
    receipt_type,
    receipt_status,
    shop_id,
    create_time,
    update_time
FROM t_finance_receipt
WHERE DATE(create_time) = '{run_date}'
  AND is_del = 0
) AS t_finance_receipt_extract
"""

df_receipt = spark.read.format("jdbc") \
    .option("url", "jdbc:mysql://aws-luckyus-salesorder-rw:3306/luckyus_sales_order") \
    .option("dbtable", receipt_query) \
    .option("user", "${ssm:/luckyus/db/salesorder/user}") \
    .option("password", "${ssm:/luckyus/db/salesorder/password}") \
    .option("fetchsize", "10000") \
    .load()

# --- Write to S3 Parquet ---
df_order.write.mode("overwrite") \
    .partitionBy("order_status") \
    .parquet(f"s3://luckyus-data-lake/staging/reconciliation/orders/dt={run_date}/")

df_order_pay.write.mode("overwrite") \
    .parquet(f"s3://luckyus-data-lake/staging/reconciliation/order_pay/dt={run_date}/")

df_receipt.write.mode("overwrite") \
    .parquet(f"s3://luckyus-data-lake/staging/reconciliation/receipts/dt={run_date}/")

job.commit()
```

#### Job: `recon-extract-salespayment`

```python
# Glue ETL Job: recon-extract-salespayment
# Source: aws-luckyus-salespayment-rw / luckyus_sales_payment
# Target: s3://luckyus-data-lake/staging/reconciliation/trades/

# ... (standard Glue boilerplate) ...

# --- Extract t_trade ---
trade_query = f"""
(SELECT
    id AS trade_id,
    trade_no,
    amount,              -- CENTS (needs ÷100)
    trade_status,
    channel_type,
    channel_trade_no,
    create_time,
    update_time,
    complete_time
FROM t_trade
WHERE DATE(create_time) = '{run_date}'
  AND is_del = 0
) AS t_trade_extract
"""

df_trade = spark.read.format("jdbc") \
    .option("url", "jdbc:mysql://aws-luckyus-salespayment-rw:3306/luckyus_sales_payment") \
    .option("dbtable", trade_query) \
    .option("user", "${ssm:/luckyus/db/salespayment/user}") \
    .option("password", "${ssm:/luckyus/db/salespayment/password}") \
    .option("fetchsize", "10000") \
    .load()

# --- Extract t_channel_fee ---
fee_query = f"""
(SELECT
    id AS fee_id,
    trade_no,
    fee_amount,          -- CENTS (needs ÷100)
    fee_rate,
    channel_type,
    create_time
FROM t_channel_fee
WHERE DATE(create_time) = '{run_date}'
  AND is_del = 0
) AS t_channel_fee_extract
"""

df_fee = spark.read.format("jdbc") \
    .option("url", "jdbc:mysql://aws-luckyus-salespayment-rw:3306/luckyus_sales_payment") \
    .option("dbtable", fee_query) \
    .option("user", "${ssm:/luckyus/db/salespayment/user}") \
    .option("password", "${ssm:/luckyus/db/salespayment/password}") \
    .option("fetchsize", "10000") \
    .load()

# --- Extract t_refund ---
refund_query = f"""
(SELECT
    id AS refund_id,
    trade_no,
    refund_amount,       -- CENTS (needs ÷100)
    refund_status,
    create_time,
    update_time,
    complete_time
FROM t_refund
WHERE DATE(create_time) = '{run_date}'
  AND is_del = 0
) AS t_refund_extract
"""

df_refund = spark.read.format("jdbc") \
    .option("url", "jdbc:mysql://aws-luckyus-salespayment-rw:3306/luckyus_sales_payment") \
    .option("dbtable", refund_query) \
    .option("user", "${ssm:/luckyus/db/salespayment/user}") \
    .option("password", "${ssm:/luckyus/db/salespayment/password}") \
    .option("fetchsize", "10000") \
    .load()

# --- Write to S3 ---
df_trade.write.mode("overwrite") \
    .parquet(f"s3://luckyus-data-lake/staging/reconciliation/trades/dt={run_date}/")

df_fee.write.mode("overwrite") \
    .parquet(f"s3://luckyus-data-lake/staging/reconciliation/channel_fees/dt={run_date}/")

df_refund.write.mode("overwrite") \
    .parquet(f"s3://luckyus-data-lake/staging/reconciliation/refunds/dt={run_date}/")

job.commit()
```

#### Job: `recon-extract-ifiaccounting`

```python
# Glue ETL Job: recon-extract-ifiaccounting
# Source: aws-luckyus-ifiaccounting-rw / luckyus_ifiaccounting
# Target: s3://luckyus-data-lake/staging/reconciliation/accounting/

# --- Extract t_acc_income_bill ---
income_bill_query = f"""
(SELECT
    id AS income_bill_id,
    biz_no,
    biz_type,
    income_type,
    amount,              -- DOLLARS (no conversion needed)
    shop_id,
    bill_status,
    biz_date,
    create_time,
    update_time
FROM t_acc_income_bill
WHERE DATE(create_time) = '{run_date}'
  AND is_del = 0
) AS t_acc_income_bill_extract
"""

df_income_bill = spark.read.format("jdbc") \
    .option("url", "jdbc:mysql://aws-luckyus-ifiaccounting-rw:3306/luckyus_ifiaccounting") \
    .option("dbtable", income_bill_query) \
    .option("user", "${ssm:/luckyus/db/ifiaccounting/user}") \
    .option("password", "${ssm:/luckyus/db/ifiaccounting/password}") \
    .option("fetchsize", "10000") \
    .load()

# --- Extract t_pre_voucher_entry ---
voucher_query = f"""
(SELECT
    id AS voucher_entry_id,
    voucher_id,
    account_code,
    debit_amount,        -- DOLLARS
    credit_amount,       -- DOLLARS
    biz_date,
    create_time
FROM t_pre_voucher_entry
WHERE DATE(create_time) = '{run_date}'
  AND is_del = 0
) AS t_pre_voucher_entry_extract
"""

df_voucher = spark.read.format("jdbc") \
    .option("url", "jdbc:mysql://aws-luckyus-ifiaccounting-rw:3306/luckyus_ifiaccounting") \
    .option("dbtable", voucher_query) \
    .option("user", "${ssm:/luckyus/db/ifiaccounting/user}") \
    .option("password", "${ssm:/luckyus/db/ifiaccounting/password}") \
    .option("fetchsize", "10000") \
    .load()

# --- Write to S3 ---
df_income_bill.write.mode("overwrite") \
    .parquet(f"s3://luckyus-data-lake/staging/reconciliation/income_bills/dt={run_date}/")

df_voucher.write.mode("overwrite") \
    .parquet(f"s3://luckyus-data-lake/staging/reconciliation/voucher_entries/dt={run_date}/")

job.commit()
```

### 2.2 Extraction Watermark Strategy

| Table | Watermark Column | Strategy |
|-------|-----------------|----------|
| t_order | `update_time` | Incremental (capture updates to order_status, pay_status) |
| t_order_pay | `update_time` | Incremental |
| t_finance_receipt | `update_time` | Incremental |
| t_trade | `update_time` | Incremental |
| t_channel_fee | `create_time` | Append-only (fees don't change) |
| t_refund | `update_time` | Incremental (status changes) |
| t_acc_income_bill | `update_time` | Incremental |
| t_pre_voucher_entry | `create_time` | Append-only |

**High-watermark tracking**: Store last-processed `update_time` per table in DynamoDB table `recon-etl-watermarks`.

---

## 3. Data Standardization Rules

### 3.1 CENTS → DOLLARS Conversion

**Critical Rule**: Some tables store amounts in CENTS (integer), others in DOLLARS (decimal). All standardized outputs use DOLLARS.

| Source Table | Column | Unit | Conversion |
|-------------|--------|------|------------|
| `t_order.pay_money` | pay_money | **DOLLARS** | None |
| `t_order.discount_money` | discount_money | **DOLLARS** | None |
| `t_order_pay.pay_money` | pay_money | **CENTS** | `÷ 100` |
| `t_trade.amount` | amount | **CENTS** | `÷ 100` |
| `t_channel_fee.fee_amount` | fee_amount | **CENTS** | `÷ 100` |
| `t_refund.refund_amount` | refund_amount | **CENTS** | `÷ 100` |
| `t_finance_receipt.receipt_amount` | receipt_amount | **DOLLARS** | None |
| `t_finance_receipt.difference_amount` | difference_amount | **DOLLARS** | None |
| `t_acc_income_bill.amount` | amount | **DOLLARS** | None |

**PySpark standardization transform**:

```python
# Standardize CENTS → DOLLARS for payment-side tables
df_order_pay_std = df_order_pay.withColumn(
    "pay_amount_usd",
    F.col("pay_money") / 100.0
)

df_trade_std = df_trade.withColumn(
    "trade_amount_usd",
    F.col("amount") / 100.0
)

df_fee_std = df_fee.withColumn(
    "fee_amount_usd",
    F.col("fee_amount") / 100.0
)

df_refund_std = df_refund.withColumn(
    "refund_amount_usd",
    F.col("refund_amount") / 100.0
)
```

### 3.2 Order ID Type Normalization

**Problem**: `t_order.id` is `bigint`, but `t_finance_receipt.order_no` and `t_finance_receipt.order_id` are `varchar(64)`.

```python
# Normalize order_id to VARCHAR for cross-table joins
df_order_std = df_order.withColumn(
    "order_id_str",
    F.col("order_id").cast("string")
)

df_order_pay_std = df_order_pay_std.withColumn(
    "order_id_str",
    F.col("order_id").cast("string")
)
```

### 3.3 NZD Test Data Filter

**Rule**: Exclude all NZD-currency records (5.7% contamination from test data).

```python
# Applied at extraction layer (WHERE currency_code = 'USD')
# Double-check at standardization layer:
df_order_std = df_order_std.filter(F.col("currency_code") == "USD")
```

### 3.4 Stripe Fee Normalization

**Context**: `t_finance_receipt.difference_amount` consistently shows ~$4.66 average, representing the Stripe processing fee offset between the charged amount and the received amount.

```python
# Extract Stripe fee as explicit column
df_receipt_std = df_receipt.withColumn(
    "stripe_fee_usd",
    F.col("difference_amount")
).withColumn(
    "net_receipt_usd",
    F.col("receipt_amount") - F.col("difference_amount")
)
```

### 3.5 Timezone Alignment

All timestamps normalized to UTC for consistent cross-source joins.

```python
# All MySQL sources are configured in UTC (AWS RDS default)
# Explicit cast for safety:
for ts_col in ["create_time", "update_time", "pay_time", "complete_time"]:
    if ts_col in df_order_std.columns:
        df_order_std = df_order_std.withColumn(
            ts_col,
            F.to_utc_timestamp(F.col(ts_col), "UTC")
        )
```

---

## 4. Staging Table Designs

### 4.1 Standardized Staging Tables (S3 Parquet)

#### `stg_recon_orders`

| Column | Type | Source | Notes |
|--------|------|--------|-------|
| order_id | BIGINT | t_order.id | Primary key |
| order_id_str | VARCHAR(64) | CAST(t_order.id AS CHAR) | For receipt joins |
| order_no | VARCHAR(64) | t_order.order_no | Alternate key |
| shop_id | BIGINT | t_order.shop_id | Store dimension |
| user_id | BIGINT | t_order.user_id | Customer dimension |
| pay_amount_usd | DECIMAL(12,2) | t_order.pay_money | Already in DOLLARS |
| discount_amount_usd | DECIMAL(12,2) | t_order.discount_money | Already in DOLLARS |
| order_status | INT | t_order.order_status | 0=created, 5=completed, etc. |
| pay_status | INT | t_order.pay_status | 0=unpaid, 1=paid |
| currency_code | VARCHAR(8) | t_order.currency_code | Always 'USD' after filter |
| order_type | INT | t_order.order_type | 1=pickup, 2=delivery |
| create_time | TIMESTAMP | t_order.create_time | UTC |
| pay_time | TIMESTAMP | t_order.pay_time | UTC |
| complete_time | TIMESTAMP | t_order.complete_time | UTC |
| dt | DATE | Partition key | Extract date |

#### `stg_recon_payments`

| Column | Type | Source | Notes |
|--------|------|--------|-------|
| order_pay_id | BIGINT | t_order_pay.id | Primary key |
| order_id | BIGINT | t_order_pay.order_id | FK to orders |
| order_id_str | VARCHAR(64) | CAST(order_id) | For receipt joins |
| trade_no | VARCHAR(64) | t_order_pay.trade_no | FK to trades |
| pay_amount_usd | DECIMAL(12,2) | t_order_pay.pay_money / 100 | **CENTS → DOLLARS** |
| pay_type | INT | t_order_pay.pay_type | Payment method |
| pay_status | INT | t_order_pay.pay_status | 0=pending, 1=success |
| create_time | TIMESTAMP | t_order_pay.create_time | UTC |
| dt | DATE | Partition key | Extract date |

#### `stg_recon_trades`

| Column | Type | Source | Notes |
|--------|------|--------|-------|
| trade_id | BIGINT | t_trade.id | Primary key |
| trade_no | VARCHAR(64) | t_trade.trade_no | Join key to order_pay |
| trade_amount_usd | DECIMAL(12,2) | t_trade.amount / 100 | **CENTS → DOLLARS** |
| trade_status | INT | t_trade.trade_status | 0=pending, 1=success |
| channel_type | INT | t_trade.channel_type | Payment channel |
| channel_trade_no | VARCHAR(128) | t_trade.channel_trade_no | Stripe transaction ID |
| create_time | TIMESTAMP | t_trade.create_time | UTC |
| complete_time | TIMESTAMP | t_trade.complete_time | UTC |
| dt | DATE | Partition key | Extract date |

#### `stg_recon_receipts`

| Column | Type | Source | Notes |
|--------|------|--------|-------|
| receipt_id | BIGINT | t_finance_receipt.id | Primary key |
| order_id_str | VARCHAR(64) | t_finance_receipt.order_id | FK to orders (varchar) |
| order_no | VARCHAR(64) | t_finance_receipt.order_no | Alternate FK |
| tp_serial_no | VARCHAR(128) | t_finance_receipt.tp_serial_no | FK to trade_no |
| receipt_amount_usd | DECIMAL(12,2) | t_finance_receipt.receipt_amount | Already DOLLARS |
| stripe_fee_usd | DECIMAL(12,2) | t_finance_receipt.difference_amount | Fee offset |
| net_receipt_usd | DECIMAL(12,2) | receipt_amount - difference_amount | Net after fee |
| receipt_type | INT | t_finance_receipt.receipt_type | Type of receipt |
| receipt_status | INT | t_finance_receipt.receipt_status | Status |
| shop_id | BIGINT | t_finance_receipt.shop_id | Store dimension |
| create_time | TIMESTAMP | t_finance_receipt.create_time | UTC |
| dt | DATE | Partition key | Extract date |

#### `stg_recon_income_bills`

| Column | Type | Source | Notes |
|--------|------|--------|-------|
| income_bill_id | BIGINT | t_acc_income_bill.id | Primary key |
| biz_no | VARCHAR(64) | t_acc_income_bill.biz_no | Business reference |
| biz_type | INT | t_acc_income_bill.biz_type | Business type |
| income_type | INT | t_acc_income_bill.income_type | Revenue category |
| amount_usd | DECIMAL(12,2) | t_acc_income_bill.amount | Already DOLLARS |
| shop_id | BIGINT | t_acc_income_bill.shop_id | Store dimension |
| bill_status | INT | t_acc_income_bill.bill_status | Status |
| biz_date | DATE | t_acc_income_bill.biz_date | Business date |
| create_time | TIMESTAMP | t_acc_income_bill.create_time | UTC |
| dt | DATE | Partition key | Extract date |

---

## 5. Reconciliation Match Logic — Level 1

### Level 1: Order ↔ Payment (Per-Transaction)

**Purpose**: Verify every order has a corresponding payment record, and amounts match after unit conversion.

**Join Path**:
```
t_order.id = t_order_pay.order_id
t_order_pay.trade_no = t_trade.trade_no
```

**Match Criteria**:
```
t_order.pay_money = t_order_pay.pay_money / 100 = t_trade.amount / 100
```

### SQL Implementation

```sql
-- =====================================================
-- LEVEL 1: Order ↔ Payment Reconciliation
-- =====================================================
-- Produces one row per order with match status

CREATE TABLE stg_recon_level1_results AS
WITH order_base AS (
    SELECT
        o.order_id,
        o.order_id_str,
        o.order_no,
        o.shop_id,
        o.pay_amount_usd      AS order_amount,
        o.order_status,
        o.pay_status           AS order_pay_status,
        o.pay_time,
        o.create_time          AS order_create_time,
        o.dt
    FROM stg_recon_orders o
    WHERE o.order_status IN (5, 6, 7)  -- completed/settled orders
),

payment_base AS (
    SELECT
        p.order_id,
        p.trade_no,
        p.pay_amount_usd      AS payment_amount,
        p.pay_status           AS payment_pay_status,
        p.create_time          AS payment_create_time
    FROM stg_recon_payments p
    WHERE p.pay_status = 1  -- successful payments only
),

trade_base AS (
    SELECT
        t.trade_no,
        t.trade_amount_usd    AS trade_amount,
        t.trade_status,
        t.channel_type,
        t.channel_trade_no,
        t.complete_time        AS trade_complete_time
    FROM stg_recon_trades t
    WHERE t.trade_status = 1  -- successful trades only
)

SELECT
    ob.order_id,
    ob.order_id_str,
    ob.order_no,
    ob.shop_id,
    ob.order_amount,
    pb.payment_amount,
    tb.trade_amount,
    ob.dt,

    -- Match flags
    CASE
        WHEN pb.order_id IS NULL THEN 'MISSING_PAYMENT'
        WHEN tb.trade_no IS NULL THEN 'MISSING_TRADE'
        WHEN ABS(ob.order_amount - pb.payment_amount) > 0.01 THEN 'AMOUNT_MISMATCH_ORDER_PAY'
        WHEN ABS(ob.order_amount - tb.trade_amount) > 0.01 THEN 'AMOUNT_MISMATCH_ORDER_TRADE'
        WHEN ABS(pb.payment_amount - tb.trade_amount) > 0.01 THEN 'AMOUNT_MISMATCH_PAY_TRADE'
        ELSE 'MATCHED'
    END AS match_status,

    -- Amount differences (for anomaly detection)
    COALESCE(ob.order_amount - pb.payment_amount, 0) AS diff_order_payment,
    COALESCE(ob.order_amount - tb.trade_amount, 0)   AS diff_order_trade,
    COALESCE(pb.payment_amount - tb.trade_amount, 0) AS diff_payment_trade,

    -- Timing
    ob.order_create_time,
    pb.payment_create_time,
    tb.trade_complete_time,
    TIMESTAMPDIFF(SECOND, ob.order_create_time, pb.payment_create_time) AS order_to_payment_sec,

    -- Metadata
    pb.trade_no,
    tb.channel_type,
    tb.channel_trade_no,
    CURRENT_TIMESTAMP AS reconciled_at

FROM order_base ob
LEFT JOIN payment_base pb ON ob.order_id = pb.order_id
LEFT JOIN trade_base tb ON pb.trade_no = tb.trade_no;
```

### Level 1 Expected Outcomes

| Match Status | Expected Volume | Action |
|-------------|----------------|--------|
| MATCHED | ~92% (~453K) | No action — healthy |
| MISSING_PAYMENT | ~1.5% (~7,600) | Flag for payment investigation |
| MISSING_TRADE | <0.5% | Flag for payment gateway investigation |
| AMOUNT_MISMATCH_* | Should be 0% | Critical anomaly — immediate investigation |

---

## 6. Reconciliation Match Logic — Level 2

### Level 2: Order ↔ Receipt (Per-Transaction)

**Purpose**: Verify payment receipts match orders, accounting for Stripe fees.

**Join Path**:
```
CAST(t_order.id AS CHAR) = t_finance_receipt.order_no
  -- OR --
t_order_pay.trade_no = t_finance_receipt.tp_serial_no
```

**Match Criteria**:
```
t_order.pay_money = t_finance_receipt.receipt_amount
(Stripe fee tracked in t_finance_receipt.difference_amount, expected ~$4.66 avg)
```

### SQL Implementation

```sql
-- =====================================================
-- LEVEL 2: Order ↔ Receipt Reconciliation
-- =====================================================
-- Matches orders to finance receipts with Stripe fee tracking

CREATE TABLE stg_recon_level2_results AS
WITH order_with_payment AS (
    SELECT
        o.order_id,
        o.order_id_str,
        o.order_no,
        o.shop_id,
        o.pay_amount_usd      AS order_amount,
        o.dt,
        p.trade_no
    FROM stg_recon_orders o
    LEFT JOIN stg_recon_payments p ON o.order_id = p.order_id AND p.pay_status = 1
    WHERE o.order_status IN (5, 6, 7)
),

receipt_base AS (
    SELECT
        r.receipt_id,
        r.order_id_str        AS receipt_order_id,
        r.order_no             AS receipt_order_no,
        r.tp_serial_no,
        r.receipt_amount_usd,
        r.stripe_fee_usd,
        r.net_receipt_usd,
        r.receipt_status,
        r.shop_id              AS receipt_shop_id,
        r.create_time          AS receipt_create_time
    FROM stg_recon_receipts r
    WHERE r.receipt_status = 1  -- active receipts
)

SELECT
    owp.order_id,
    owp.order_id_str,
    owp.order_no,
    owp.shop_id,
    owp.order_amount,
    owp.trade_no,
    rb.receipt_id,
    rb.receipt_amount_usd,
    rb.stripe_fee_usd,
    rb.net_receipt_usd,
    owp.dt,

    -- Match flags
    CASE
        WHEN rb.receipt_id IS NULL THEN 'MISSING_RECEIPT'
        WHEN ABS(owp.order_amount - rb.receipt_amount_usd) > 0.01 THEN 'AMOUNT_MISMATCH'
        ELSE 'MATCHED'
    END AS match_status,

    -- Amount differences
    COALESCE(owp.order_amount - rb.receipt_amount_usd, 0) AS diff_order_receipt,

    -- Stripe fee validation
    CASE
        WHEN rb.stripe_fee_usd IS NULL THEN 'NO_RECEIPT'
        WHEN rb.stripe_fee_usd < 0.01 THEN 'ZERO_FEE'
        WHEN rb.stripe_fee_usd < 2.00 THEN 'LOW_FEE'
        WHEN rb.stripe_fee_usd > 8.00 THEN 'HIGH_FEE'
        ELSE 'NORMAL_FEE'
    END AS fee_status,

    rb.stripe_fee_usd,
    rb.receipt_create_time,
    CURRENT_TIMESTAMP AS reconciled_at

FROM order_with_payment owp
LEFT JOIN receipt_base rb
    ON owp.order_id_str = rb.receipt_order_id
    OR owp.trade_no = rb.tp_serial_no;  -- fallback join via trade_no
```

### Level 2 Expected Outcomes

| Match Status | Expected Volume | Action |
|-------------|----------------|--------|
| MATCHED | ~98% | Normal — fee tracked |
| MISSING_RECEIPT | ~1.5% | Correlates with missing payment (Level 1) |
| AMOUNT_MISMATCH | Should be 0% | Critical — receipt ≠ order amount |

| Fee Status | Expected Volume | Action |
|-----------|----------------|--------|
| NORMAL_FEE ($2–$8) | ~95% | Expected Stripe fee range |
| LOW_FEE (<$2) | ~3% | Small transactions — normal |
| HIGH_FEE (>$8) | <1% | Review for delivery surcharges |
| ZERO_FEE | <0.5% | Investigate — possible comp/promo |

---

## 7. Reconciliation Match Logic — Level 3

### Level 3: Receipt ↔ Income Bill (Aggregated)

**Purpose**: Verify that daily shop-level receipt totals match accounting income bill summaries.

**Join Path**:
```
Aggregated by: shop_id + biz_date
Receipt sum per shop per day ↔ Income bill sum per shop per day
```

**Note**: This level operates on aggregated data because `t_acc_income_bill` uses `shop_income_summary` as its source, not individual transactions.

### SQL Implementation

```sql
-- =====================================================
-- LEVEL 3: Receipt ↔ Income Bill Reconciliation (Aggregated)
-- =====================================================
-- Compares daily shop-level totals between receipts and income bills

CREATE TABLE stg_recon_level3_results AS
WITH daily_receipt_totals AS (
    SELECT
        shop_id,
        DATE(create_time) AS biz_date,
        COUNT(*) AS receipt_count,
        SUM(receipt_amount_usd) AS total_receipt_amount,
        SUM(stripe_fee_usd) AS total_stripe_fees,
        SUM(net_receipt_usd) AS total_net_receipt
    FROM stg_recon_receipts
    WHERE receipt_status = 1
    GROUP BY shop_id, DATE(create_time)
),

daily_income_totals AS (
    SELECT
        shop_id,
        biz_date,
        COUNT(*) AS bill_count,
        SUM(amount_usd) AS total_income_amount
    FROM stg_recon_income_bills
    WHERE bill_status = 1
    GROUP BY shop_id, biz_date
),

daily_order_totals AS (
    -- Cross-reference with order totals for completeness
    SELECT
        shop_id,
        DATE(create_time) AS biz_date,
        COUNT(*) AS order_count,
        SUM(pay_amount_usd) AS total_order_amount
    FROM stg_recon_orders
    WHERE order_status IN (5, 6, 7)
    GROUP BY shop_id, DATE(create_time)
)

SELECT
    COALESCE(drt.shop_id, dit.shop_id, dot.shop_id) AS shop_id,
    COALESCE(drt.biz_date, dit.biz_date, dot.biz_date) AS biz_date,

    -- Receipt metrics
    COALESCE(drt.receipt_count, 0) AS receipt_count,
    COALESCE(drt.total_receipt_amount, 0) AS total_receipt_amount,
    COALESCE(drt.total_stripe_fees, 0) AS total_stripe_fees,
    COALESCE(drt.total_net_receipt, 0) AS total_net_receipt,

    -- Income bill metrics
    COALESCE(dit.bill_count, 0) AS bill_count,
    COALESCE(dit.total_income_amount, 0) AS total_income_amount,

    -- Order metrics (cross-reference)
    COALESCE(dot.order_count, 0) AS order_count,
    COALESCE(dot.total_order_amount, 0) AS total_order_amount,

    -- Match flags
    CASE
        WHEN dit.shop_id IS NULL THEN 'MISSING_INCOME_BILL'
        WHEN drt.shop_id IS NULL THEN 'MISSING_RECEIPTS'
        WHEN ABS(drt.total_receipt_amount - dit.total_income_amount) <= 1.00
            THEN 'MATCHED'
        WHEN ABS(drt.total_net_receipt - dit.total_income_amount) <= 1.00
            THEN 'MATCHED_NET'  -- matches after Stripe fee deduction
        ELSE 'AMOUNT_MISMATCH'
    END AS match_status,

    -- Differences
    COALESCE(drt.total_receipt_amount - dit.total_income_amount, 0) AS diff_gross,
    COALESCE(drt.total_net_receipt - dit.total_income_amount, 0) AS diff_net,
    COALESCE(drt.total_receipt_amount - dot.total_order_amount, 0) AS diff_receipt_order,
    COALESCE(dit.total_income_amount - dot.total_order_amount, 0) AS diff_income_order,

    -- Coverage metric
    CASE
        WHEN COALESCE(dot.order_count, 0) = 0 THEN 0
        ELSE ROUND(COALESCE(dit.bill_count, 0) * 100.0 / dot.order_count, 2)
    END AS income_bill_coverage_pct,

    CURRENT_TIMESTAMP AS reconciled_at

FROM daily_receipt_totals drt
FULL OUTER JOIN daily_income_totals dit
    ON drt.shop_id = dit.shop_id AND drt.biz_date = dit.biz_date
FULL OUTER JOIN daily_order_totals dot
    ON COALESCE(drt.shop_id, dit.shop_id) = dot.shop_id
    AND COALESCE(drt.biz_date, dit.biz_date) = dot.biz_date;
```

### Level 3 Expected Outcomes

| Match Status | Expected Volume | Explanation |
|-------------|----------------|-------------|
| MATCHED | ~5% | Gross amounts align directly |
| MATCHED_NET | ~5% | Amounts align after Stripe fee deduction |
| AMOUNT_MISMATCH | ~80% | Expected — income bills are aggregated differently |
| MISSING_INCOME_BILL | ~10% | Days/shops without accounting entries |
| MISSING_RECEIPTS | <1% | Shops with income bills but no receipts (rare) |

**Note**: Level 3 has high mismatch rates (~90%) because `t_acc_income_bill` aggregates via `shop_income_summary` which may use different grouping logic. This is a known gap documented in Phase 1 Section 5.5.

---

## 8. Data Quality Validation Rules

### 8.1 Pre-Reconciliation Checks

Run before each reconciliation cycle to ensure source data integrity.

```sql
-- =====================================================
-- DATA QUALITY VALIDATION SUITE
-- =====================================================

-- DQ-01: Record count validation (±5% tolerance vs previous day)
SELECT
    'DQ-01' AS check_id,
    'RECORD_COUNT' AS check_type,
    table_name,
    today_count,
    yesterday_count,
    ROUND((today_count - yesterday_count) * 100.0 / NULLIF(yesterday_count, 0), 2)
        AS pct_change,
    CASE
        WHEN ABS((today_count - yesterday_count) * 100.0 / NULLIF(yesterday_count, 0)) > 20
            THEN 'FAIL'
        WHEN ABS((today_count - yesterday_count) * 100.0 / NULLIF(yesterday_count, 0)) > 5
            THEN 'WARN'
        ELSE 'PASS'
    END AS status
FROM (
    SELECT 'stg_recon_orders' AS table_name,
        (SELECT COUNT(*) FROM stg_recon_orders WHERE dt = CURRENT_DATE) AS today_count,
        (SELECT COUNT(*) FROM stg_recon_orders WHERE dt = CURRENT_DATE - INTERVAL 1 DAY) AS yesterday_count
    UNION ALL
    SELECT 'stg_recon_payments',
        (SELECT COUNT(*) FROM stg_recon_payments WHERE dt = CURRENT_DATE),
        (SELECT COUNT(*) FROM stg_recon_payments WHERE dt = CURRENT_DATE - INTERVAL 1 DAY)
    UNION ALL
    SELECT 'stg_recon_trades',
        (SELECT COUNT(*) FROM stg_recon_trades WHERE dt = CURRENT_DATE),
        (SELECT COUNT(*) FROM stg_recon_trades WHERE dt = CURRENT_DATE - INTERVAL 1 DAY)
    UNION ALL
    SELECT 'stg_recon_receipts',
        (SELECT COUNT(*) FROM stg_recon_receipts WHERE dt = CURRENT_DATE),
        (SELECT COUNT(*) FROM stg_recon_receipts WHERE dt = CURRENT_DATE - INTERVAL 1 DAY)
) counts;

-- DQ-02: NULL check on critical join keys
SELECT
    'DQ-02' AS check_id,
    'NULL_KEY' AS check_type,
    source_table,
    key_column,
    null_count,
    CASE WHEN null_count > 0 THEN 'FAIL' ELSE 'PASS' END AS status
FROM (
    SELECT 'stg_recon_orders' AS source_table, 'order_id' AS key_column,
        SUM(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END) AS null_count
    FROM stg_recon_orders WHERE dt = CURRENT_DATE
    UNION ALL
    SELECT 'stg_recon_payments', 'trade_no',
        SUM(CASE WHEN trade_no IS NULL OR trade_no = '' THEN 1 ELSE 0 END)
    FROM stg_recon_payments WHERE dt = CURRENT_DATE
    UNION ALL
    SELECT 'stg_recon_receipts', 'order_id_str',
        SUM(CASE WHEN order_id_str IS NULL OR order_id_str = '' THEN 1 ELSE 0 END)
    FROM stg_recon_receipts WHERE dt = CURRENT_DATE
) null_checks;

-- DQ-03: Amount range validation (no negative amounts, reasonable maximums)
SELECT
    'DQ-03' AS check_id,
    'AMOUNT_RANGE' AS check_type,
    source_table,
    amount_column,
    min_amount,
    max_amount,
    avg_amount,
    CASE
        WHEN min_amount < 0 THEN 'FAIL_NEGATIVE'
        WHEN max_amount > 10000 THEN 'WARN_HIGH'
        ELSE 'PASS'
    END AS status
FROM (
    SELECT 'stg_recon_orders' AS source_table, 'pay_amount_usd' AS amount_column,
        MIN(pay_amount_usd), MAX(pay_amount_usd), AVG(pay_amount_usd)
    FROM stg_recon_orders WHERE dt = CURRENT_DATE
    UNION ALL
    SELECT 'stg_recon_payments', 'pay_amount_usd',
        MIN(pay_amount_usd), MAX(pay_amount_usd), AVG(pay_amount_usd)
    FROM stg_recon_payments WHERE dt = CURRENT_DATE
    UNION ALL
    SELECT 'stg_recon_trades', 'trade_amount_usd',
        MIN(trade_amount_usd), MAX(trade_amount_usd), AVG(trade_amount_usd)
    FROM stg_recon_trades WHERE dt = CURRENT_DATE
) amount_checks;

-- DQ-04: Currency filter verification (zero NZD records)
SELECT
    'DQ-04' AS check_id,
    'CURRENCY_FILTER' AS check_type,
    currency_code,
    COUNT(*) AS record_count,
    CASE WHEN currency_code != 'USD' THEN 'FAIL' ELSE 'PASS' END AS status
FROM stg_recon_orders
WHERE dt = CURRENT_DATE
GROUP BY currency_code;

-- DQ-05: Duplicate detection on primary keys
SELECT
    'DQ-05' AS check_id,
    'DUPLICATE' AS check_type,
    source_table,
    duplicate_count,
    CASE WHEN duplicate_count > 0 THEN 'FAIL' ELSE 'PASS' END AS status
FROM (
    SELECT 'stg_recon_orders' AS source_table,
        (SELECT COUNT(*) - COUNT(DISTINCT order_id)
         FROM stg_recon_orders WHERE dt = CURRENT_DATE) AS duplicate_count
    UNION ALL
    SELECT 'stg_recon_trades',
        (SELECT COUNT(*) - COUNT(DISTINCT trade_id)
         FROM stg_recon_trades WHERE dt = CURRENT_DATE)
) dup_checks;

-- DQ-06: Freshness check (latest record timestamp within expected window)
SELECT
    'DQ-06' AS check_id,
    'FRESHNESS' AS check_type,
    source_table,
    max_create_time,
    TIMESTAMPDIFF(HOUR, max_create_time, CURRENT_TIMESTAMP) AS hours_stale,
    CASE
        WHEN TIMESTAMPDIFF(HOUR, max_create_time, CURRENT_TIMESTAMP) > 24 THEN 'FAIL'
        WHEN TIMESTAMPDIFF(HOUR, max_create_time, CURRENT_TIMESTAMP) > 6 THEN 'WARN'
        ELSE 'PASS'
    END AS status
FROM (
    SELECT 'stg_recon_orders' AS source_table,
        MAX(create_time) AS max_create_time
    FROM stg_recon_orders WHERE dt = CURRENT_DATE
    UNION ALL
    SELECT 'stg_recon_trades',
        MAX(create_time) FROM stg_recon_trades WHERE dt = CURRENT_DATE
) freshness_checks;
```

### 8.2 Post-Reconciliation Validation

```sql
-- DQ-07: Match rate threshold check
SELECT
    'DQ-07' AS check_id,
    recon_level,
    total_records,
    matched_records,
    ROUND(matched_records * 100.0 / total_records, 2) AS match_rate_pct,
    CASE
        WHEN recon_level = 'L1' AND matched_records * 100.0 / total_records < 90 THEN 'FAIL'
        WHEN recon_level = 'L2' AND matched_records * 100.0 / total_records < 95 THEN 'FAIL'
        ELSE 'PASS'
    END AS status
FROM (
    SELECT 'L1' AS recon_level,
        COUNT(*) AS total_records,
        SUM(CASE WHEN match_status = 'MATCHED' THEN 1 ELSE 0 END) AS matched_records
    FROM stg_recon_level1_results WHERE dt = CURRENT_DATE
    UNION ALL
    SELECT 'L2',
        COUNT(*),
        SUM(CASE WHEN match_status IN ('MATCHED') THEN 1 ELSE 0 END)
    FROM stg_recon_level2_results WHERE dt = CURRENT_DATE
) match_rates;
```

---

## 9. ETL Scheduling & Dependencies

### 9.1 Glue Workflow Definition

```
Workflow: recon-daily-pipeline
Schedule: cron(0 6 * * ? *)  -- 06:00 UTC daily (01:00 ET)

Job Dependencies:
┌─────────────────────────────────────────────────────────┐
│ PHASE 1: EXTRACT (parallel)                             │
│                                                          │
│  recon-extract-salesorder ──────┐                        │
│  recon-extract-salespayment ────┤                        │
│  recon-extract-ifiaccounting ───┘                        │
│           │                                              │
│           ▼                                              │
│ PHASE 2: STANDARDIZE                                     │
│                                                          │
│  recon-standardize-all ─────────┐                        │
│           │                      │                       │
│           ▼                      ▼                       │
│ PHASE 3: DATA QUALITY      PHASE 3b: STAGING LOAD       │
│                                                          │
│  recon-dq-validation ──────────┐                        │
│           │                     │                        │
│           ▼ (if PASS)           │                        │
│ PHASE 4: RECONCILIATION        │                        │
│                                 │                        │
│  recon-match-level1 ────┐       │                        │
│  recon-match-level2 ────┤       │                        │
│  recon-match-level3 ────┘       │                        │
│           │                     │                        │
│           ▼                     │                        │
│ PHASE 5: LOAD TO DW             │                        │
│                                 │                        │
│  recon-load-redshift ───────────┘                        │
│           │                                              │
│           ▼                                              │
│ PHASE 6: ANOMALY DETECTION (Phase 3 scope)              │
│                                                          │
│  recon-anomaly-scan                                      │
└─────────────────────────────────────────────────────────┘
```

### 9.2 SLA Targets

| Phase | Max Duration | Alert Threshold |
|-------|-------------|----------------|
| Extract (all 3 parallel) | 15 min | >20 min |
| Standardize | 10 min | >15 min |
| Data Quality | 5 min | >10 min |
| Reconciliation (all 3 levels) | 20 min | >30 min |
| Load to DW | 10 min | >15 min |
| Anomaly Detection | 10 min | >15 min |
| **Total Pipeline** | **70 min** | **>90 min** |

### 9.3 Backfill Strategy

For historical reconciliation (initial load of 8.5 months data):

```python
# Backfill script — process one month at a time
import boto3
from datetime import date, timedelta

glue = boto3.client('glue')

start_date = date(2025, 6, 1)   # Luckin US launch
end_date = date(2026, 2, 16)    # Current date

current = start_date
while current <= end_date:
    glue.start_job_run(
        JobName='recon-extract-salesorder',
        Arguments={'--run_date': current.strftime('%Y-%m-%d')}
    )
    # ... trigger other extract jobs ...
    current += timedelta(days=1)
```

---

## 10. Error Handling & Recovery

### 10.1 Retry Policy

| Error Type | Max Retries | Backoff | Action |
|-----------|------------|---------|--------|
| JDBC Connection Timeout | 3 | Exponential (30s, 60s, 120s) | Retry with fresh connection |
| S3 Write Failure | 3 | Linear (10s) | Retry write |
| Glue Job OOM | 1 | None | Restart with 2x DPU allocation |
| Data Quality FAIL | 0 | None | Alert + halt pipeline |
| Reconciliation Exception | 2 | Linear (30s) | Retry match logic |

### 10.2 Dead Letter Queue

Failed records that cannot be reconciled are written to:
```
s3://luckyus-data-lake/staging/reconciliation/dead-letter/
  └── dt=YYYY-MM-DD/
      ├── level1_failures.parquet
      ├── level2_failures.parquet
      └── level3_failures.parquet
```

### 10.3 Alerting

| Condition | Channel | Severity |
|-----------|---------|----------|
| Pipeline fails to start | wecom-warning | Tier 2 |
| Data quality check FAIL | wecom-warning | Tier 2 |
| Match rate drops below threshold | wecom-critical | Tier 3 |
| Pipeline exceeds 90 min SLA | wecom-warning | Tier 2 |
| Amount mismatch detected (Level 1) | wecom-critical | Tier 3 |

---

## Appendix A: Column Mapping Summary

| Staging Column | Source Table | Source Column | Transform |
|---------------|-------------|---------------|-----------|
| `order_id` | t_order | id | Direct |
| `order_id_str` | t_order | id | CAST(id AS CHAR) |
| `pay_amount_usd` (orders) | t_order | pay_money | Direct (already DOLLARS) |
| `pay_amount_usd` (payments) | t_order_pay | pay_money | ÷ 100 (CENTS→DOLLARS) |
| `trade_amount_usd` | t_trade | amount | ÷ 100 (CENTS→DOLLARS) |
| `receipt_amount_usd` | t_finance_receipt | receipt_amount | Direct (already DOLLARS) |
| `stripe_fee_usd` | t_finance_receipt | difference_amount | Direct (already DOLLARS) |
| `net_receipt_usd` | t_finance_receipt | receipt_amount - difference_amount | Computed |
| `fee_amount_usd` | t_channel_fee | fee_amount | ÷ 100 (CENTS→DOLLARS) |
| `refund_amount_usd` | t_refund | refund_amount | ÷ 100 (CENTS→DOLLARS) |
| `amount_usd` (income) | t_acc_income_bill | amount | Direct (already DOLLARS) |

---

*End of Phase 2 — ETL Pipeline & Reconciliation Design*
*Next: Phase 3 — Anomaly Detection Rules*

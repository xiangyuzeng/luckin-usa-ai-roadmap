#!/usr/bin/env python3
"""
UC-SC-01: Forecast Accuracy Pipeline Orchestrator
==================================================
Bridges 3 MySQL servers to compute demand forecast accuracy metrics.

Architecture:
  Server 1 (ireplenishment)  --> Extract predictions
  Server 2 (scm-shopstock)   --> Extract actual consumption
  Server 3 (dbatest/test)    --> Stage, join, compute, aggregate, detect drift

Usage:
  # Daily run (yesterday's data)
  python run_pipeline.py

  # Specific date
  python run_pipeline.py --date 2026-02-14

  # Backfill a date range
  python run_pipeline.py --start-date 2026-01-01 --end-date 2026-02-14

  # Create tables (first-time setup)
  python run_pipeline.py --setup

  # Dry run (extract only, no load)
  python run_pipeline.py --date 2026-02-14 --dry-run

Author:  Data Engineering / BI Team
Created: 2026-02-15
"""

import argparse
import logging
import os
import sys
import uuid
from datetime import date, datetime, timedelta
from pathlib import Path

try:
    import pymysql
    import pymysql.cursors
except ImportError:
    print("ERROR: PyMySQL not installed. Run: pip install PyMySQL python-dotenv")
    print("       Or: pip install -r requirements.txt")
    sys.exit(1)

try:
    from dotenv import load_dotenv
except ImportError:
    # dotenv is optional; env vars can be set directly
    load_dotenv = None

# ============================================================================
# CONFIGURATION
# ============================================================================

ACTIVE_STORES = (1127, 1128, 1140, 1141, 20008, 20010, 20011, 20027, 20031, 20032)
STORE_NAMES = {
    1127:  "8th & Broadway",
    1128:  "28th & 6th",
    1140:  "100 Maiden Ln",
    1141:  "54th & 8th",
    20008: "33rd & 10th",
    20010: "102 Fulton",
    20011: "37th & Broadway",
    20027: "21st & 3rd",
    20031: "15th & 3rd",
    20032: "221 Grand",
}

BATCH_SIZE = 5000  # rows per INSERT batch

# ============================================================================
# LOGGING
# ============================================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("forecast_pipeline")


# ============================================================================
# DATABASE CONNECTIONS
# ============================================================================

def get_connection(prefix: str) -> pymysql.Connection:
    """Create a MySQL connection from environment variables with the given prefix."""
    host = os.environ.get(f"{prefix}_HOST")
    port = int(os.environ.get(f"{prefix}_PORT", "3306"))
    user = os.environ.get(f"{prefix}_USER")
    password = os.environ.get(f"{prefix}_PASSWORD")
    database = os.environ.get(f"{prefix}_DATABASE")

    if not all([host, user, password, database]):
        raise ValueError(
            f"Missing database config for {prefix}. "
            f"Set {prefix}_HOST, {prefix}_USER, {prefix}_PASSWORD, {prefix}_DATABASE"
        )

    log.info("Connecting to %s @ %s:%d/%s", prefix, host, port, database)
    return pymysql.connect(
        host=host,
        port=port,
        user=user,
        password=password,
        database=database,
        charset="utf8mb4",
        cursorclass=pymysql.cursors.Cursor,
        connect_timeout=30,
        read_timeout=300,
        write_timeout=300,
    )


# ============================================================================
# STEP 1: EXTRACT PREDICTIONS
# ============================================================================

EXTRACT_PREDICTIONS_SQL = """
SELECT
    p.dt                  AS dt,
    p.shop_dept_id        AS shop_dept_id,
    p.goods_code          AS goods_code,
    p.goods_name          AS goods_name,
    p.large_class_name    AS large_class_name,
    p.vlt_avg_demand      AS vlt_avg_demand,
    p.order_num           AS order_num,
    p.task_version_id     AS task_version_id
FROM luckyus_ireplenishment.t_order_predict_alg_v2 p
INNER JOIN (
    SELECT shop_dept_id, goods_code, dt, MAX(task_version_id) AS max_version_id
    FROM luckyus_ireplenishment.t_order_predict_alg_v2
    WHERE dt >= %s AND dt <= %s
      AND shop_dept_id IN ({stores})
    GROUP BY shop_dept_id, goods_code, dt
) latest
    ON  p.shop_dept_id    = latest.shop_dept_id
    AND p.goods_code      = latest.goods_code
    AND p.dt              = latest.dt
    AND p.task_version_id = latest.max_version_id
WHERE p.dt >= %s AND p.dt <= %s
  AND p.shop_dept_id IN ({stores})
ORDER BY p.dt, p.shop_dept_id, p.goods_code
""".format(stores=",".join(str(s) for s in ACTIVE_STORES))


def extract_predictions(conn, date_start: str, date_end: str) -> list:
    """Extract predictions from ireplenishment server."""
    log.info("STEP 1: Extracting predictions for %s to %s ...", date_start, date_end)
    with conn.cursor() as cur:
        cur.execute(EXTRACT_PREDICTIONS_SQL, (date_start, date_end, date_start, date_end))
        rows = cur.fetchall()
    log.info("  -> Extracted %d prediction rows", len(rows))
    return rows


# ============================================================================
# STEP 2: EXTRACT ACTUALS (CONSUMPTION)
# ============================================================================

EXTRACT_ACTUALS_SQL = """
SELECT
    DATE(scr.operated_time)           AS consumption_date,
    scr.shop_dept_id                  AS shop_dept_id,
    scr.goods_mid                     AS goods_mid,
    SUM(ABS(scr.total_adjust_num))    AS actual_consumption,
    COUNT(*)                          AS record_count
FROM luckyus_scm_shopstock.t_shop_goods_stock_change_record scr
WHERE scr.operated_time >= CONCAT(%s, ' 00:00:00')
  AND scr.operated_time <  DATE_ADD(%s, INTERVAL 1 DAY)
  AND scr.reason_code IN ('025', '1001', '1002')
  AND scr.total_adjust_num < 0
  AND scr.shop_dept_id IN ({stores})
GROUP BY DATE(scr.operated_time), scr.shop_dept_id, scr.goods_mid
ORDER BY consumption_date, scr.shop_dept_id, scr.goods_mid
""".format(stores=",".join(str(s) for s in ACTIVE_STORES))


def extract_actuals(conn, date_start: str, date_end: str) -> list:
    """Extract actual consumption from scm-shopstock server."""
    log.info("STEP 2: Extracting actuals for %s to %s ...", date_start, date_end)
    with conn.cursor() as cur:
        cur.execute(EXTRACT_ACTUALS_SQL, (date_start, date_end))
        rows = cur.fetchall()
    log.info("  -> Extracted %d actual consumption rows", len(rows))
    return rows


# ============================================================================
# STEP 3: LOAD STAGING TABLES
# ============================================================================

CREATE_TMP_PREDICTIONS = """
DROP TABLE IF EXISTS test.tmp_predictions;
CREATE TABLE test.tmp_predictions (
    dt               VARCHAR(32)  NOT NULL,
    shop_dept_id     BIGINT       NOT NULL,
    goods_code       VARCHAR(32)  NOT NULL,
    goods_name       VARCHAR(200),
    large_class_name VARCHAR(100),
    vlt_avg_demand   DECIMAL(12,2),
    order_num        DECIMAL(12,2),
    task_version_id  BIGINT,
    PRIMARY KEY (dt, shop_dept_id, goods_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
"""

CREATE_TMP_ACTUALS = """
DROP TABLE IF EXISTS test.tmp_actuals;
CREATE TABLE test.tmp_actuals (
    consumption_date DATE         NOT NULL,
    shop_dept_id     BIGINT       NOT NULL,
    goods_mid        VARCHAR(32)  NOT NULL,
    actual_consumption DECIMAL(12,2),
    record_count     INT,
    PRIMARY KEY (consumption_date, shop_dept_id, goods_mid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
"""

INSERT_PREDICTIONS = """
INSERT INTO test.tmp_predictions
    (dt, shop_dept_id, goods_code, goods_name, large_class_name,
     vlt_avg_demand, order_num, task_version_id)
VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
"""

INSERT_ACTUALS = """
INSERT INTO test.tmp_actuals
    (consumption_date, shop_dept_id, goods_mid, actual_consumption, record_count)
VALUES (%s, %s, %s, %s, %s)
"""


def load_staging(conn, predictions: list, actuals: list):
    """Create staging tables and bulk-load extracted data."""
    log.info("STEP 3: Loading staging tables ...")

    with conn.cursor() as cur:
        # Create staging tables (each statement separately)
        log.info("  Creating tmp_predictions ...")
        cur.execute("DROP TABLE IF EXISTS test.tmp_predictions")
        cur.execute("""CREATE TABLE test.tmp_predictions (
            dt               VARCHAR(32)  NOT NULL,
            shop_dept_id     BIGINT       NOT NULL,
            goods_code       VARCHAR(32)  NOT NULL,
            goods_name       VARCHAR(200),
            large_class_name VARCHAR(100),
            vlt_avg_demand   DECIMAL(12,2),
            order_num        DECIMAL(12,2),
            task_version_id  BIGINT,
            PRIMARY KEY (dt, shop_dept_id, goods_code)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""")

        log.info("  Creating tmp_actuals ...")
        cur.execute("DROP TABLE IF EXISTS test.tmp_actuals")
        cur.execute("""CREATE TABLE test.tmp_actuals (
            consumption_date DATE         NOT NULL,
            shop_dept_id     BIGINT       NOT NULL,
            goods_mid        VARCHAR(32)  NOT NULL,
            actual_consumption DECIMAL(12,2),
            record_count     INT,
            PRIMARY KEY (consumption_date, shop_dept_id, goods_mid)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""")

    conn.commit()

    # Bulk insert predictions
    if predictions:
        log.info("  Inserting %d prediction rows (batch size %d) ...", len(predictions), BATCH_SIZE)
        with conn.cursor() as cur:
            for i in range(0, len(predictions), BATCH_SIZE):
                batch = predictions[i : i + BATCH_SIZE]
                cur.executemany(INSERT_PREDICTIONS, batch)
                conn.commit()
                log.info("    Loaded predictions batch %d-%d", i, i + len(batch))

    # Bulk insert actuals
    if actuals:
        log.info("  Inserting %d actual rows (batch size %d) ...", len(actuals), BATCH_SIZE)
        with conn.cursor() as cur:
            for i in range(0, len(actuals), BATCH_SIZE):
                batch = actuals[i : i + BATCH_SIZE]
                cur.executemany(INSERT_ACTUALS, batch)
                conn.commit()
                log.info("    Loaded actuals batch %d-%d", i, i + len(batch))

    log.info("  -> Staging tables loaded: %d predictions, %d actuals",
             len(predictions), len(actuals))


# ============================================================================
# STEP 4: JOIN & COMPUTE ACCURACY METRICS
# ============================================================================

IDEMPOTENT_DELETE_DAILY = """
DELETE FROM test.forecast_accuracy_daily
WHERE accuracy_date >= %s AND accuracy_date <= %s
"""

COMPUTE_ACCURACY = """
INSERT INTO test.forecast_accuracy_daily (
    accuracy_date, shop_dept_id, shop_name,
    goods_code, goods_name, large_class_name,
    predicted_demand, predicted_order_qty, actual_consumption,
    absolute_error, absolute_pct_error, forecast_error, bias_pct, squared_error,
    prediction_dt, task_version_id, computed_at
)
SELECT
    a.consumption_date                                      AS accuracy_date,
    p.shop_dept_id                                          AS shop_dept_id,
    NULL                                                    AS shop_name,
    p.goods_code                                            AS goods_code,
    p.goods_name                                            AS goods_name,
    p.large_class_name                                      AS large_class_name,
    p.vlt_avg_demand                                        AS predicted_demand,
    p.order_num                                             AS predicted_order_qty,
    a.actual_consumption                                    AS actual_consumption,
    ABS(p.vlt_avg_demand - a.actual_consumption)            AS absolute_error,
    ABS(p.vlt_avg_demand - a.actual_consumption)
        / NULLIF(a.actual_consumption, 0)                   AS absolute_pct_error,
    (p.vlt_avg_demand - a.actual_consumption)               AS forecast_error,
    (p.vlt_avg_demand - a.actual_consumption)
        / NULLIF(a.actual_consumption, 0)                   AS bias_pct,
    POW(p.vlt_avg_demand - a.actual_consumption, 2)         AS squared_error,
    p.dt                                                    AS prediction_dt,
    p.task_version_id                                       AS task_version_id,
    NOW()                                                   AS computed_at
FROM test.tmp_predictions p
INNER JOIN test.tmp_actuals a
    ON  p.shop_dept_id = a.shop_dept_id
    AND p.goods_code   = a.goods_mid
    AND p.dt           = a.consumption_date
WHERE a.actual_consumption IS NOT NULL
  AND p.vlt_avg_demand     IS NOT NULL
"""


def compute_accuracy(conn, date_start: str, date_end: str) -> int:
    """Join predictions to actuals and compute accuracy metrics."""
    log.info("STEP 4: Computing accuracy metrics ...")

    with conn.cursor() as cur:
        # Idempotent delete
        cur.execute(IDEMPOTENT_DELETE_DAILY, (date_start, date_end))
        deleted = cur.rowcount
        log.info("  Deleted %d existing rows for idempotency", deleted)

        # Compute and insert
        cur.execute(COMPUTE_ACCURACY)
        inserted = cur.rowcount
        log.info("  Inserted %d accuracy rows", inserted)

        # Enrich shop names
        for shop_id, shop_name in STORE_NAMES.items():
            cur.execute(
                "UPDATE test.forecast_accuracy_daily "
                "SET shop_name = %s "
                "WHERE shop_dept_id = %s "
                "  AND accuracy_date >= %s AND accuracy_date <= %s "
                "  AND shop_name IS NULL",
                (shop_name, shop_id, date_start, date_end),
            )
        log.info("  Enriched shop names for %d stores", len(STORE_NAMES))

    conn.commit()
    return inserted


# ============================================================================
# STEP 5: AGGREGATE METRICS
# ============================================================================

def compute_aggregates(conn, date_start: str, date_end: str):
    """Compute aggregated accuracy metrics across periods and dimensions."""
    log.info("STEP 5: Computing aggregate metrics ...")

    agg_sql_blocks = _build_aggregate_sql()
    total_inserted = 0

    with conn.cursor() as cur:
        # Idempotent delete of overlapping summaries
        cur.execute(
            "DELETE FROM test.forecast_accuracy_summary "
            "WHERE period_end >= %s AND period_start <= %s",
            (date_start, date_end),
        )
        log.info("  Deleted overlapping summaries")

        for label, sql in agg_sql_blocks:
            cur.execute(sql, (date_start, date_end))
            count = cur.rowcount
            total_inserted += count
            log.info("  %s: %d rows", label, count)

    conn.commit()
    log.info("  -> Total aggregate rows inserted: %d", total_inserted)
    return total_inserted


def _build_aggregate_sql() -> list:
    """Return list of (label, sql) tuples for each aggregation section."""
    # Each query takes (%s, %s) for (date_start, date_end)
    metric_select = """
        ROUND(AVG(CASE WHEN d.actual_consumption > 0 THEN d.absolute_pct_error END), 4) AS mape,
        ROUND(SUM(d.absolute_error) / NULLIF(SUM(d.actual_consumption), 0), 4) AS wmape,
        ROUND(SQRT(AVG(d.squared_error)), 4) AS rmse,
        ROUND(AVG(d.forecast_error), 4) AS mfe,
        ROUND(SUM(CASE WHEN d.absolute_pct_error <= 0.20 THEN 1 ELSE 0 END)
            / NULLIF(COUNT(*), 0), 4) AS accuracy_rate_20,
        ROUND(SUM(d.forecast_error) / NULLIF(AVG(d.absolute_error), 0), 4) AS tracking_signal,
        COUNT(*) AS prediction_count,
        NULL AS coverage_pct,
        ROUND(AVG(d.actual_consumption), 2) AS avg_actual,
        NOW() AS computed_at
    """

    insert_prefix = """INSERT INTO test.forecast_accuracy_summary (
        period_type, period_start, period_end,
        dimension_type, dimension_value, dimension_name,
        mape, wmape, rmse, mfe,
        accuracy_rate_20, tracking_signal,
        prediction_count, coverage_pct, avg_actual, computed_at
    ) SELECT """

    where_clause = """
    FROM test.forecast_accuracy_daily d
    WHERE d.accuracy_date >= %s AND d.accuracy_date <= %s
    """

    blocks = []

    # DAILY x OVERALL
    blocks.append(("DAILY x OVERALL", insert_prefix + f"""
        'DAILY', d.accuracy_date, d.accuracy_date,
        'OVERALL', 'ALL', 'All Stores & Products',
        {metric_select}
        {where_clause}
        GROUP BY d.accuracy_date
    """))

    # DAILY x STORE
    blocks.append(("DAILY x STORE", insert_prefix + f"""
        'DAILY', d.accuracy_date, d.accuracy_date,
        'STORE', CAST(d.shop_dept_id AS CHAR), MAX(d.shop_name),
        {metric_select}
        {where_clause}
        GROUP BY d.accuracy_date, d.shop_dept_id
    """))

    # DAILY x CATEGORY
    blocks.append(("DAILY x CATEGORY", insert_prefix + f"""
        'DAILY', d.accuracy_date, d.accuracy_date,
        'CATEGORY', COALESCE(d.large_class_name, 'UNKNOWN'),
        COALESCE(d.large_class_name, 'Unknown Category'),
        {metric_select}
        {where_clause}
        GROUP BY d.accuracy_date, d.large_class_name
    """))

    # DAILY x DOW
    blocks.append(("DAILY x DOW", insert_prefix + f"""
        'DAILY', d.accuracy_date, d.accuracy_date,
        'DOW', CAST(DAYOFWEEK(d.accuracy_date) AS CHAR), DAYNAME(d.accuracy_date),
        {metric_select}
        {where_clause}
        GROUP BY d.accuracy_date, DAYOFWEEK(d.accuracy_date), DAYNAME(d.accuracy_date)
    """))

    # WEEKLY x OVERALL
    blocks.append(("WEEKLY x OVERALL", insert_prefix + f"""
        'WEEKLY',
        DATE_SUB(d.accuracy_date, INTERVAL (WEEKDAY(d.accuracy_date)) DAY),
        DATE_ADD(DATE_SUB(d.accuracy_date, INTERVAL (WEEKDAY(d.accuracy_date)) DAY), INTERVAL 6 DAY),
        'OVERALL', 'ALL', CONCAT('Week ', YEARWEEK(d.accuracy_date, 1)),
        {metric_select}
        {where_clause}
        GROUP BY YEARWEEK(d.accuracy_date, 1),
                 DATE_SUB(d.accuracy_date, INTERVAL (WEEKDAY(d.accuracy_date)) DAY)
    """))

    # WEEKLY x STORE
    blocks.append(("WEEKLY x STORE", insert_prefix + f"""
        'WEEKLY',
        DATE_SUB(d.accuracy_date, INTERVAL (WEEKDAY(d.accuracy_date)) DAY),
        DATE_ADD(DATE_SUB(d.accuracy_date, INTERVAL (WEEKDAY(d.accuracy_date)) DAY), INTERVAL 6 DAY),
        'STORE', CAST(d.shop_dept_id AS CHAR), MAX(d.shop_name),
        {metric_select}
        {where_clause}
        GROUP BY YEARWEEK(d.accuracy_date, 1),
                 DATE_SUB(d.accuracy_date, INTERVAL (WEEKDAY(d.accuracy_date)) DAY),
                 d.shop_dept_id
    """))

    # MONTHLY x OVERALL
    blocks.append(("MONTHLY x OVERALL", insert_prefix + f"""
        'MONTHLY',
        DATE_FORMAT(d.accuracy_date, '%%Y-%%m-01'),
        LAST_DAY(d.accuracy_date),
        'OVERALL', 'ALL', DATE_FORMAT(d.accuracy_date, '%%Y-%%m'),
        {metric_select}
        {where_clause}
        GROUP BY DATE_FORMAT(d.accuracy_date, '%%Y-%%m-01'), LAST_DAY(d.accuracy_date)
    """))

    # MONTHLY x CATEGORY
    blocks.append(("MONTHLY x CATEGORY", insert_prefix + f"""
        'MONTHLY',
        DATE_FORMAT(d.accuracy_date, '%%Y-%%m-01'),
        LAST_DAY(d.accuracy_date),
        'CATEGORY', COALESCE(d.large_class_name, 'UNKNOWN'),
        COALESCE(d.large_class_name, 'Unknown Category'),
        {metric_select}
        {where_clause}
        GROUP BY DATE_FORMAT(d.accuracy_date, '%%Y-%%m-01'),
                 LAST_DAY(d.accuracy_date), d.large_class_name
    """))

    # ROLLING_7D x OVERALL
    blocks.append(("ROLLING_7D x OVERALL", insert_prefix + f"""
        'ROLLING_7D',
        DATE_SUB(ref.ref_date, INTERVAL 6 DAY),
        ref.ref_date,
        'OVERALL', 'ALL', 'All Stores & Products (7D Rolling)',
        {metric_select.replace('d.', 'd2.')}
    FROM (
        SELECT DISTINCT accuracy_date AS ref_date
        FROM test.forecast_accuracy_daily
        WHERE accuracy_date >= %s AND accuracy_date <= %s
    ) ref
    INNER JOIN test.forecast_accuracy_daily d2
        ON d2.accuracy_date BETWEEN DATE_SUB(ref.ref_date, INTERVAL 6 DAY) AND ref.ref_date
    GROUP BY ref.ref_date
    """.replace(metric_select.replace('d.', 'd2.'), """
        ROUND(AVG(CASE WHEN d2.actual_consumption > 0 THEN d2.absolute_pct_error END), 4),
        ROUND(SUM(d2.absolute_error) / NULLIF(SUM(d2.actual_consumption), 0), 4),
        ROUND(SQRT(AVG(d2.squared_error)), 4),
        ROUND(AVG(d2.forecast_error), 4),
        ROUND(SUM(CASE WHEN d2.absolute_pct_error <= 0.20 THEN 1 ELSE 0 END)
            / NULLIF(COUNT(*), 0), 4),
        ROUND(SUM(d2.forecast_error) / NULLIF(AVG(d2.absolute_error), 0), 4),
        COUNT(*),
        NULL,
        ROUND(AVG(d2.actual_consumption), 2),
        NOW()
    """)))

    # ROLLING_7D x STORE
    blocks.append(("ROLLING_7D x STORE", insert_prefix + """
        'ROLLING_7D',
        DATE_SUB(ref.ref_date, INTERVAL 6 DAY),
        ref.ref_date,
        'STORE', CAST(d2.shop_dept_id AS CHAR), MAX(d2.shop_name),
        ROUND(AVG(CASE WHEN d2.actual_consumption > 0 THEN d2.absolute_pct_error END), 4),
        ROUND(SUM(d2.absolute_error) / NULLIF(SUM(d2.actual_consumption), 0), 4),
        ROUND(SQRT(AVG(d2.squared_error)), 4),
        ROUND(AVG(d2.forecast_error), 4),
        ROUND(SUM(CASE WHEN d2.absolute_pct_error <= 0.20 THEN 1 ELSE 0 END)
            / NULLIF(COUNT(*), 0), 4),
        ROUND(SUM(d2.forecast_error) / NULLIF(AVG(d2.absolute_error), 0), 4),
        COUNT(*), NULL,
        ROUND(AVG(d2.actual_consumption), 2), NOW()
    FROM (
        SELECT DISTINCT accuracy_date AS ref_date
        FROM test.forecast_accuracy_daily
        WHERE accuracy_date >= %s AND accuracy_date <= %s
    ) ref
    INNER JOIN test.forecast_accuracy_daily d2
        ON d2.accuracy_date BETWEEN DATE_SUB(ref.ref_date, INTERVAL 6 DAY) AND ref.ref_date
    GROUP BY ref.ref_date, d2.shop_dept_id
    """))

    # ROLLING_7D x CATEGORY
    blocks.append(("ROLLING_7D x CATEGORY", insert_prefix + """
        'ROLLING_7D',
        DATE_SUB(ref.ref_date, INTERVAL 6 DAY),
        ref.ref_date,
        'CATEGORY', COALESCE(d2.large_class_name, 'UNKNOWN'),
        COALESCE(d2.large_class_name, 'Unknown Category'),
        ROUND(AVG(CASE WHEN d2.actual_consumption > 0 THEN d2.absolute_pct_error END), 4),
        ROUND(SUM(d2.absolute_error) / NULLIF(SUM(d2.actual_consumption), 0), 4),
        ROUND(SQRT(AVG(d2.squared_error)), 4),
        ROUND(AVG(d2.forecast_error), 4),
        ROUND(SUM(CASE WHEN d2.absolute_pct_error <= 0.20 THEN 1 ELSE 0 END)
            / NULLIF(COUNT(*), 0), 4),
        ROUND(SUM(d2.forecast_error) / NULLIF(AVG(d2.absolute_error), 0), 4),
        COUNT(*), NULL,
        ROUND(AVG(d2.actual_consumption), 2), NOW()
    FROM (
        SELECT DISTINCT accuracy_date AS ref_date
        FROM test.forecast_accuracy_daily
        WHERE accuracy_date >= %s AND accuracy_date <= %s
    ) ref
    INNER JOIN test.forecast_accuracy_daily d2
        ON d2.accuracy_date BETWEEN DATE_SUB(ref.ref_date, INTERVAL 6 DAY) AND ref.ref_date
    GROUP BY ref.ref_date, d2.large_class_name
    """))

    # ROLLING_30D x OVERALL
    blocks.append(("ROLLING_30D x OVERALL", insert_prefix + """
        'ROLLING_30D',
        DATE_SUB(ref.ref_date, INTERVAL 29 DAY),
        ref.ref_date,
        'OVERALL', 'ALL', 'All Stores & Products (30D Rolling)',
        ROUND(AVG(CASE WHEN d2.actual_consumption > 0 THEN d2.absolute_pct_error END), 4),
        ROUND(SUM(d2.absolute_error) / NULLIF(SUM(d2.actual_consumption), 0), 4),
        ROUND(SQRT(AVG(d2.squared_error)), 4),
        ROUND(AVG(d2.forecast_error), 4),
        ROUND(SUM(CASE WHEN d2.absolute_pct_error <= 0.20 THEN 1 ELSE 0 END)
            / NULLIF(COUNT(*), 0), 4),
        ROUND(SUM(d2.forecast_error) / NULLIF(AVG(d2.absolute_error), 0), 4),
        COUNT(*), NULL,
        ROUND(AVG(d2.actual_consumption), 2), NOW()
    FROM (
        SELECT DISTINCT accuracy_date AS ref_date
        FROM test.forecast_accuracy_daily
        WHERE accuracy_date >= %s AND accuracy_date <= %s
    ) ref
    INNER JOIN test.forecast_accuracy_daily d2
        ON d2.accuracy_date BETWEEN DATE_SUB(ref.ref_date, INTERVAL 29 DAY) AND ref.ref_date
    GROUP BY ref.ref_date
    """))

    # ROLLING_30D x STORE
    blocks.append(("ROLLING_30D x STORE", insert_prefix + """
        'ROLLING_30D',
        DATE_SUB(ref.ref_date, INTERVAL 29 DAY),
        ref.ref_date,
        'STORE', CAST(d2.shop_dept_id AS CHAR), MAX(d2.shop_name),
        ROUND(AVG(CASE WHEN d2.actual_consumption > 0 THEN d2.absolute_pct_error END), 4),
        ROUND(SUM(d2.absolute_error) / NULLIF(SUM(d2.actual_consumption), 0), 4),
        ROUND(SQRT(AVG(d2.squared_error)), 4),
        ROUND(AVG(d2.forecast_error), 4),
        ROUND(SUM(CASE WHEN d2.absolute_pct_error <= 0.20 THEN 1 ELSE 0 END)
            / NULLIF(COUNT(*), 0), 4),
        ROUND(SUM(d2.forecast_error) / NULLIF(AVG(d2.absolute_error), 0), 4),
        COUNT(*), NULL,
        ROUND(AVG(d2.actual_consumption), 2), NOW()
    FROM (
        SELECT DISTINCT accuracy_date AS ref_date
        FROM test.forecast_accuracy_daily
        WHERE accuracy_date >= %s AND accuracy_date <= %s
    ) ref
    INNER JOIN test.forecast_accuracy_daily d2
        ON d2.accuracy_date BETWEEN DATE_SUB(ref.ref_date, INTERVAL 29 DAY) AND ref.ref_date
    GROUP BY ref.ref_date, d2.shop_dept_id
    """))

    return blocks


# ============================================================================
# STEP 6: DRIFT DETECTION & ALERTS
# ============================================================================

def run_drift_detection(conn, alert_date: str) -> int:
    """Execute the 5 alert rules and insert into forecast_alerts."""
    log.info("STEP 6: Running drift detection for alert_date=%s ...", alert_date)

    stores_list = ",".join(str(s) for s in ACTIVE_STORES)
    alerts_before = 0
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM test.forecast_alerts WHERE DATE(alert_timestamp) = CURDATE()")
        alerts_before = cur.fetchone()[0]

    with conn.cursor() as cur:
        # RULE 1: CRITICAL - 7-day MAPE > 40% per store
        cur.execute(f"""
            INSERT INTO test.forecast_alerts (
                alert_timestamp, alert_type, entity_type, entity_id, entity_name,
                metric_name, metric_value, threshold_value,
                description, recommended_action, is_acknowledged
            )
            SELECT NOW(), 'CRITICAL', 'STORE',
                CAST(shop_dept_id AS CHAR), MAX(shop_name),
                'mape_7d',
                ROUND(AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END), 4),
                0.4000,
                CONCAT('CRITICAL: Store ', MAX(shop_name), ' 7-day MAPE = ',
                       ROUND(AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END) * 100, 1), '%% > 40%%'),
                'Investigate SKU-level accuracy. Consider model retraining.',
                FALSE
            FROM test.forecast_accuracy_daily
            WHERE accuracy_date BETWEEN DATE_SUB(%s, INTERVAL 6 DAY) AND %s
              AND shop_dept_id IN ({stores_list})
            GROUP BY shop_dept_id
            HAVING AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END) > 0.40
               AND NOT EXISTS (
                   SELECT 1 FROM test.forecast_alerts fa
                   WHERE fa.alert_type = 'CRITICAL' AND fa.entity_id = CAST(shop_dept_id AS CHAR)
                     AND fa.metric_name = 'mape_7d' AND DATE(fa.alert_timestamp) = CURDATE()
               )
        """, (alert_date, alert_date))
        log.info("  Rule 1 (CRITICAL MAPE>40%%): %d alerts", cur.rowcount)

        # RULE 2: WARNING - 7-day MAPE > 30% per store (<=40%)
        cur.execute(f"""
            INSERT INTO test.forecast_alerts (
                alert_timestamp, alert_type, entity_type, entity_id, entity_name,
                metric_name, metric_value, threshold_value,
                description, recommended_action, is_acknowledged
            )
            SELECT NOW(), 'WARNING', 'STORE',
                CAST(shop_dept_id AS CHAR), MAX(shop_name),
                'mape_7d',
                ROUND(AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END), 4),
                0.3000,
                CONCAT('WARNING: Store ', MAX(shop_name), ' 7-day MAPE = ',
                       ROUND(AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END) * 100, 1), '%% > 30%%'),
                'Monitor closely for 2-3 days. Review top error SKUs.',
                FALSE
            FROM test.forecast_accuracy_daily
            WHERE accuracy_date BETWEEN DATE_SUB(%s, INTERVAL 6 DAY) AND %s
              AND shop_dept_id IN ({stores_list})
            GROUP BY shop_dept_id
            HAVING AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END) > 0.30
               AND AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END) <= 0.40
               AND NOT EXISTS (
                   SELECT 1 FROM test.forecast_alerts fa
                   WHERE fa.alert_type = 'WARNING' AND fa.entity_id = CAST(shop_dept_id AS CHAR)
                     AND fa.metric_name = 'mape_7d' AND DATE(fa.alert_timestamp) = CURDATE()
               )
        """, (alert_date, alert_date))
        log.info("  Rule 2 (WARNING MAPE>30%%): %d alerts", cur.rowcount)

        # RULE 3: BIAS - 14+ consecutive same-sign MFE days
        cur.execute(f"""
            INSERT INTO test.forecast_alerts (
                alert_timestamp, alert_type, entity_type, entity_id, entity_name,
                metric_name, metric_value, threshold_value, baseline_value,
                description, recommended_action, is_acknowledged
            )
            SELECT NOW(), 'BIAS', 'STORE',
                CAST(bc.shop_dept_id AS CHAR), bc.shop_name,
                'consecutive_bias_days', bc.consecutive_days, 14.0000, bc.avg_daily_mfe,
                CONCAT('BIAS: Store ', bc.shop_name, ' has ',
                       CASE WHEN bc.bias_direction = 'OVER' THEN 'over-predicted' ELSE 'under-predicted' END,
                       ' for ', bc.consecutive_days, ' consecutive days.'),
                'Systematic bias detected. Recommend model recalibration.',
                FALSE
            FROM (
                SELECT sub.shop_dept_id, sub.shop_name, sub.bias_direction,
                       COUNT(*) AS consecutive_days, AVG(sub.daily_mfe) AS avg_daily_mfe
                FROM (
                    SELECT d.shop_dept_id, MAX(d.shop_name) AS shop_name, d.accuracy_date,
                           AVG(d.forecast_error) AS daily_mfe,
                           CASE WHEN AVG(d.forecast_error) >= 0 THEN 'OVER' ELSE 'UNDER' END AS bias_direction,
                           ROW_NUMBER() OVER (PARTITION BY d.shop_dept_id ORDER BY d.accuracy_date DESC) AS rn
                    FROM test.forecast_accuracy_daily d
                    WHERE d.accuracy_date BETWEEN DATE_SUB(%s, INTERVAL 30 DAY) AND %s
                      AND d.shop_dept_id IN ({stores_list})
                    GROUP BY d.shop_dept_id, d.accuracy_date
                ) sub
                WHERE sub.rn <= 30
                GROUP BY sub.shop_dept_id, sub.shop_name, sub.bias_direction
                HAVING MIN(sub.rn) = 1 AND COUNT(*) >= 14
            ) bc
            WHERE NOT EXISTS (
                SELECT 1 FROM test.forecast_alerts fa
                WHERE fa.alert_type = 'BIAS' AND fa.entity_id = CAST(bc.shop_dept_id AS CHAR)
                  AND fa.metric_name = 'consecutive_bias_days' AND DATE(fa.alert_timestamp) = CURDATE()
            )
        """, (alert_date, alert_date))
        log.info("  Rule 3 (BIAS 14+ days): %d alerts", cur.rowcount)

        # RULE 5: DRIFT - WoW MAPE change > 50% by category
        cur.execute("""
            INSERT INTO test.forecast_alerts (
                alert_timestamp, alert_type, entity_type, entity_id, entity_name,
                metric_name, metric_value, threshold_value, baseline_value,
                description, recommended_action, is_acknowledged
            )
            SELECT NOW(), 'DRIFT', 'CATEGORY',
                curr.large_class_name, curr.large_class_name,
                'mape_wow_relative_change',
                ROUND((curr.curr_mape - prev.prev_mape) / NULLIF(prev.prev_mape, 0), 4),
                0.5000,
                ROUND(prev.prev_mape, 4),
                CONCAT('DRIFT: Category "', curr.large_class_name, '" MAPE WoW change = ',
                       ROUND((curr.curr_mape - prev.prev_mape) / NULLIF(prev.prev_mape, 0) * 100, 1), '%%'),
                'Investigate category for demand pattern changes.',
                FALSE
            FROM (
                SELECT COALESCE(large_class_name, 'UNKNOWN') AS large_class_name,
                       AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END) AS curr_mape
                FROM test.forecast_accuracy_daily
                WHERE accuracy_date BETWEEN DATE_SUB(%s, INTERVAL 6 DAY) AND %s
                GROUP BY large_class_name
            ) curr
            INNER JOIN (
                SELECT COALESCE(large_class_name, 'UNKNOWN') AS large_class_name,
                       AVG(CASE WHEN actual_consumption > 0 THEN absolute_pct_error END) AS prev_mape
                FROM test.forecast_accuracy_daily
                WHERE accuracy_date BETWEEN DATE_SUB(%s, INTERVAL 13 DAY) AND DATE_SUB(%s, INTERVAL 7 DAY)
                GROUP BY large_class_name
            ) prev ON curr.large_class_name = prev.large_class_name
            WHERE prev.prev_mape > 0
              AND ABS((curr.curr_mape - prev.prev_mape) / prev.prev_mape) > 0.50
              AND NOT EXISTS (
                  SELECT 1 FROM test.forecast_alerts fa
                  WHERE fa.alert_type = 'DRIFT' AND fa.entity_id = curr.large_class_name
                    AND fa.metric_name = 'mape_wow_relative_change' AND DATE(fa.alert_timestamp) = CURDATE()
              )
        """, (alert_date, alert_date, alert_date, alert_date))
        log.info("  Rule 5 (DRIFT WoW>50%%): %d alerts", cur.rowcount)

    conn.commit()

    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM test.forecast_alerts WHERE DATE(alert_timestamp) = CURDATE()")
        alerts_after = cur.fetchone()[0]

    new_alerts = alerts_after - alerts_before
    log.info("  -> Total new alerts generated: %d", new_alerts)
    return new_alerts


# ============================================================================
# STEP 7: CLEANUP
# ============================================================================

def cleanup_staging(conn):
    """Drop staging tables."""
    log.info("STEP 7: Cleaning up staging tables ...")
    with conn.cursor() as cur:
        cur.execute("DROP TABLE IF EXISTS test.tmp_predictions")
        cur.execute("DROP TABLE IF EXISTS test.tmp_actuals")
    conn.commit()
    log.info("  -> Staging tables dropped")


# ============================================================================
# PIPELINE LOGGING
# ============================================================================

def log_pipeline_run(conn, run_id: str, step: str, status: str,
                     date_start: str, date_end: str,
                     rows_extracted: int = 0, rows_loaded: int = 0,
                     error_msg: str = None, start_time: datetime = None):
    """Insert a row into the pipeline run log."""
    now = datetime.now()
    duration = int((now - start_time).total_seconds()) if start_time else 0
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO test.forecast_pipeline_run_log (
                    run_id, pipeline_name, step_name,
                    run_start, run_end, duration_seconds,
                    data_date_start, data_date_end,
                    status, rows_extracted, rows_loaded,
                    error_message, triggered_by, created_at
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                run_id, "forecast_accuracy_daily_etl", step,
                start_time or now, now, duration,
                date_start, date_end,
                status, rows_extracted, rows_loaded,
                error_msg, "python_orchestrator", now,
            ))
        conn.commit()
    except Exception as e:
        log.warning("Failed to log pipeline step '%s': %s", step, e)


# ============================================================================
# TABLE SETUP (--setup)
# ============================================================================

def setup_tables(conn):
    """Create the 4 analytics tables if they don't exist."""
    log.info("SETUP: Creating analytics tables ...")

    ddl_file = Path(__file__).parent.parent / "sql" / "02_create_analytics_schema.sql"
    if not ddl_file.exists():
        log.error("DDL file not found: %s", ddl_file)
        sys.exit(1)

    ddl_text = ddl_file.read_text()

    # Split on CREATE TABLE and execute each statement
    # Also handle the fact that the file has comments
    statements = []
    current = []
    for line in ddl_text.splitlines():
        stripped = line.strip()
        if stripped.startswith("--") or stripped.startswith("/*") or not stripped:
            continue
        current.append(line)
        if stripped.endswith(";"):
            stmt = "\n".join(current).strip()
            if stmt and not stmt.startswith("/*"):
                statements.append(stmt)
            current = []

    with conn.cursor() as cur:
        for stmt in statements:
            if stmt.upper().startswith(("CREATE TABLE", "SELECT")):
                try:
                    cur.execute(stmt)
                    log.info("  Executed: %s...", stmt[:60].replace("\n", " "))
                except pymysql.err.OperationalError as e:
                    if "already exists" in str(e):
                        log.info("  Table already exists, skipping")
                    else:
                        raise

    conn.commit()

    # Verify
    with conn.cursor() as cur:
        cur.execute("""
            SELECT TABLE_NAME FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = 'test'
              AND TABLE_NAME IN ('forecast_accuracy_daily','forecast_accuracy_summary',
                                 'forecast_alerts','forecast_pipeline_run_log')
            ORDER BY TABLE_NAME
        """)
        tables = [row[0] for row in cur.fetchall()]

    log.info("  -> Tables found: %s", ", ".join(tables) if tables else "NONE")
    if len(tables) < 4:
        log.warning("  Not all 4 tables were created. Missing: %s",
                     set(["forecast_accuracy_daily", "forecast_accuracy_summary",
                          "forecast_alerts", "forecast_pipeline_run_log"]) - set(tables))
    else:
        log.info("  -> All 4 tables ready!")


# ============================================================================
# MAIN PIPELINE
# ============================================================================

def run_pipeline(calc_date_start: str, calc_date_end: str, dry_run: bool = False):
    """Execute the full pipeline for the given date range."""
    run_id = str(uuid.uuid4())[:12]
    pipeline_start = datetime.now()

    log.info("=" * 70)
    log.info("UC-SC-01 FORECAST ACCURACY PIPELINE")
    log.info("Run ID:     %s", run_id)
    log.info("Date range: %s to %s", calc_date_start, calc_date_end)
    log.info("Dry run:    %s", dry_run)
    log.info("=" * 70)

    # Connect to all 3 servers
    pred_conn = None
    actual_conn = None
    analytics_conn = None

    try:
        pred_conn = get_connection("PRED")
        actual_conn = get_connection("ACTUAL")
        analytics_conn = get_connection("ANALYTICS")

        # Log start
        log_pipeline_run(analytics_conn, run_id, "PIPELINE_START", "RUNNING",
                         calc_date_start, calc_date_end, start_time=pipeline_start)

        # Step 1: Extract predictions
        step_start = datetime.now()
        predictions = extract_predictions(pred_conn, calc_date_start, calc_date_end)
        log_pipeline_run(analytics_conn, run_id, "EXTRACT_PREDICTIONS", "SUCCESS",
                         calc_date_start, calc_date_end,
                         rows_extracted=len(predictions), start_time=step_start)

        # Step 2: Extract actuals
        step_start = datetime.now()
        actuals = extract_actuals(actual_conn, calc_date_start, calc_date_end)
        log_pipeline_run(analytics_conn, run_id, "EXTRACT_ACTUALS", "SUCCESS",
                         calc_date_start, calc_date_end,
                         rows_extracted=len(actuals), start_time=step_start)

        if dry_run:
            log.info("DRY RUN: Skipping load and compute steps.")
            log.info("  Predictions: %d rows", len(predictions))
            log.info("  Actuals:     %d rows", len(actuals))
            if predictions:
                log.info("  Sample prediction: %s", predictions[0])
            if actuals:
                log.info("  Sample actual:     %s", actuals[0])
            return

        if not predictions:
            log.warning("No predictions found for date range. Aborting.")
            log_pipeline_run(analytics_conn, run_id, "PIPELINE_ABORT", "FAILED",
                             calc_date_start, calc_date_end,
                             error_msg="No predictions found", start_time=pipeline_start)
            return

        if not actuals:
            log.warning("No actuals found for date range. Aborting.")
            log_pipeline_run(analytics_conn, run_id, "PIPELINE_ABORT", "FAILED",
                             calc_date_start, calc_date_end,
                             error_msg="No actuals found", start_time=pipeline_start)
            return

        # Step 3: Load staging
        step_start = datetime.now()
        load_staging(analytics_conn, predictions, actuals)
        log_pipeline_run(analytics_conn, run_id, "LOAD_STAGING", "SUCCESS",
                         calc_date_start, calc_date_end,
                         rows_loaded=len(predictions) + len(actuals),
                         start_time=step_start)

        # Step 4: Compute accuracy
        step_start = datetime.now()
        daily_rows = compute_accuracy(analytics_conn, calc_date_start, calc_date_end)
        log_pipeline_run(analytics_conn, run_id, "COMPUTE_ACCURACY", "SUCCESS",
                         calc_date_start, calc_date_end,
                         rows_loaded=daily_rows, start_time=step_start)

        # Step 5: Aggregates
        step_start = datetime.now()
        summary_rows = compute_aggregates(analytics_conn, calc_date_start, calc_date_end)
        log_pipeline_run(analytics_conn, run_id, "COMPUTE_AGGREGATES", "SUCCESS",
                         calc_date_start, calc_date_end,
                         rows_loaded=summary_rows, start_time=step_start)

        # Step 6: Drift detection
        step_start = datetime.now()
        new_alerts = run_drift_detection(analytics_conn, calc_date_end)
        log_pipeline_run(analytics_conn, run_id, "DRIFT_DETECTION", "SUCCESS",
                         calc_date_start, calc_date_end,
                         rows_loaded=new_alerts, start_time=step_start)

        # Step 7: Cleanup
        cleanup_staging(analytics_conn)

        # Final log
        log_pipeline_run(analytics_conn, run_id, "PIPELINE_COMPLETE", "SUCCESS",
                         calc_date_start, calc_date_end,
                         rows_extracted=len(predictions) + len(actuals),
                         rows_loaded=daily_rows,
                         start_time=pipeline_start)

        duration = (datetime.now() - pipeline_start).total_seconds()
        log.info("=" * 70)
        log.info("PIPELINE COMPLETE")
        log.info("  Duration:     %.1f seconds", duration)
        log.info("  Predictions:  %d extracted", len(predictions))
        log.info("  Actuals:      %d extracted", len(actuals))
        log.info("  Daily rows:   %d computed", daily_rows)
        log.info("  Summary rows: %d aggregated", summary_rows)
        log.info("  Alerts:       %d generated", new_alerts)
        log.info("=" * 70)

    except Exception as e:
        log.error("PIPELINE FAILED: %s", e, exc_info=True)
        if analytics_conn:
            log_pipeline_run(analytics_conn, run_id, "PIPELINE_FAILED", "FAILED",
                             calc_date_start, calc_date_end,
                             error_msg=str(e)[:500], start_time=pipeline_start)
            try:
                cleanup_staging(analytics_conn)
            except Exception:
                pass
        raise

    finally:
        for conn in [pred_conn, actual_conn, analytics_conn]:
            if conn:
                try:
                    conn.close()
                except Exception:
                    pass


# ============================================================================
# CLI
# ============================================================================

def parse_args():
    parser = argparse.ArgumentParser(
        description="UC-SC-01: Forecast Accuracy Pipeline Orchestrator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python run_pipeline.py                         # Yesterday's data
  python run_pipeline.py --date 2026-02-14       # Specific date
  python run_pipeline.py --start-date 2026-01-01 --end-date 2026-02-14  # Backfill
  python run_pipeline.py --setup                 # Create tables
  python run_pipeline.py --date 2026-02-14 --dry-run  # Extract only
        """,
    )
    parser.add_argument("--date", type=str, help="Single date to process (YYYY-MM-DD)")
    parser.add_argument("--start-date", type=str, help="Start date for backfill (YYYY-MM-DD)")
    parser.add_argument("--end-date", type=str, help="End date for backfill (YYYY-MM-DD)")
    parser.add_argument("--setup", action="store_true", help="Create analytics tables")
    parser.add_argument("--dry-run", action="store_true", help="Extract only, no load")
    parser.add_argument("--env-file", type=str, default=".env", help="Path to .env file")
    parser.add_argument("--verbose", "-v", action="store_true", help="Debug logging")
    return parser.parse_args()


def main():
    args = parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Load environment variables
    env_path = Path(args.env_file)
    if env_path.exists() and load_dotenv:
        load_dotenv(env_path)
        log.info("Loaded env from %s", env_path)
    elif env_path.exists():
        # Manual .env loading if python-dotenv not installed
        for line in env_path.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, value = line.partition("=")
                os.environ.setdefault(key.strip(), value.strip())
        log.info("Loaded env from %s (manual parse)", env_path)

    # Setup mode
    if args.setup:
        conn = get_connection("ANALYTICS")
        try:
            setup_tables(conn)
        finally:
            conn.close()
        return

    # Determine date range
    if args.start_date and args.end_date:
        date_start = args.start_date
        date_end = args.end_date
    elif args.date:
        date_start = args.date
        date_end = args.date
    else:
        yesterday = (date.today() - timedelta(days=1)).isoformat()
        date_start = yesterday
        date_end = yesterday

    # Validate dates
    try:
        ds = date.fromisoformat(date_start)
        de = date.fromisoformat(date_end)
        if ds > de:
            log.error("start-date (%s) must be <= end-date (%s)", date_start, date_end)
            sys.exit(1)
        if de > date.today():
            log.warning("end-date (%s) is in the future; actuals may not be available", date_end)
    except ValueError as e:
        log.error("Invalid date format: %s", e)
        sys.exit(1)

    # For backfill of large ranges, process day by day
    days = (de - ds).days + 1
    if days > 30:
        log.info("Large backfill: %d days. Processing in 7-day chunks.", days)
        chunk_start = ds
        while chunk_start <= de:
            chunk_end = min(chunk_start + timedelta(days=6), de)
            run_pipeline(chunk_start.isoformat(), chunk_end.isoformat(), args.dry_run)
            chunk_start = chunk_end + timedelta(days=1)
    else:
        run_pipeline(date_start, date_end, args.dry_run)


if __name__ == "__main__":
    main()

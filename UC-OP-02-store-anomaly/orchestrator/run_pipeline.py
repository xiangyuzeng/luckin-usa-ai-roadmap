#!/usr/bin/env python3
"""
UC-OP-02: Store Performance Anomaly Detection -- ETL Pipeline Orchestrator
门店绩效异常检测 -- ETL管道编排器

12-step pipeline connecting 6 database servers:
  Step 1:  opshop           -> extract store master data
  Step 2:  salesorder       -> extract daily revenue/orders/AOV
  Step 3:  opproduction     -> extract production metrics
  Step 4:  opempefficiency  -> extract staffing metrics
  Step 5:  opqualitycontrol -> extract quality metrics
  Step 6:  Write all KPIs to test.store_kpi_daily
  Step 7:  Compute 28-day rolling stats + Z-scores
  Step 8:  Evaluate Western Electric rules
  Step 9:  Compute health scores
  Step 10: Generate alerts
  Step 11: Log pipeline execution
  Step 12: Verify row counts and data freshness

Schedule: Daily at 07:00 EST (after UC-SC-01's 06:00 EST run)
Dependencies: PyMySQL, python-dotenv

Usage:
  # Daily run (yesterday's data)
  python run_pipeline.py

  # Specific date
  python run_pipeline.py --date 2026-02-14

  # Backfill a date range
  python run_pipeline.py --backfill-from 2026-01-01 --backfill-to 2026-02-14

Author:  Data Engineering / BI Team
Created: 2026-02-15
"""

import os
import sys
import uuid
import argparse
import logging
import time
from datetime import datetime, date, timedelta
from decimal import Decimal

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
    load_dotenv = None

# Load .env from same directory as this script
_env_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.env')
if load_dotenv and os.path.exists(_env_path):
    load_dotenv(_env_path)

# ---------------------------------------------------------------------------
# LOGGING
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=getattr(logging, os.getenv('LOG_LEVEL', 'INFO')),
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
)
log = logging.getLogger('uc-op-02')

# ---------------------------------------------------------------------------
# CONSTANTS
# ---------------------------------------------------------------------------

# Active store IDs (dept_id from t_shop_info)
ACTIVE_STORES = {
    1131:  ('US00000', 'NJ Test Kitchen'),
    1127:  ('US00001', '8th & Broadway'),
    1128:  ('US00002', '28th & 6th'),
    1140:  ('US00003', '100 Maiden Ln'),
    20011: ('US00004', '37th & Broadway'),
    1141:  ('US00005', '54th & 8th'),
    20010: ('US00006', '102 Fulton'),
    20009: ('US00007', '108th & Broadway'),
    20008: ('US00008', '33rd & 10th'),
    20046: ('US99998', 'Shanghai Test Kitchen'),
}
STORE_IDS = tuple(ACTIVE_STORES.keys())

# SPC Constants
ROLLING_WINDOW = 28   # days for rolling statistics
DOW_WEEKS = 8         # weeks for day-of-week comparison
SIGMA_WARNING = 2     # sigma threshold for WARNING
SIGMA_CRITICAL = 3    # sigma threshold for CRITICAL
HEALTH_WEIGHTS = {
    'revenue':  0.40,
    'ops':      0.20,
    'quality':  0.15,
    'staffing': 0.15,
    'customer': 0.10,
}
LOOKBACK_DAYS = int(os.getenv('LOOKBACK_DAYS', '3'))


# ---------------------------------------------------------------------------
# DATABASE CONNECTION HELPER
# ---------------------------------------------------------------------------

_SERVER_ENV_MAP = {
    'opshop':      ('OPSHOP_HOST',      'OPSHOP_PORT',      'OPSHOP_USER',      'OPSHOP_PASS',      'OPSHOP_DB'),
    'salesorder':  ('SALESORDER_HOST',   'SALESORDER_PORT',  'SALESORDER_USER',  'SALESORDER_PASS',  'SALESORDER_DB'),
    'production':  ('PRODUCTION_HOST',   'PRODUCTION_PORT',  'PRODUCTION_USER',  'PRODUCTION_PASS',  'PRODUCTION_DB'),
    'quality':     ('QUALITY_HOST',      'QUALITY_PORT',     'QUALITY_USER',     'QUALITY_PASS',     'QUALITY_DB'),
    'empeff':      ('EMPEFF_HOST',       'EMPEFF_PORT',      'EMPEFF_USER',      'EMPEFF_PASS',      'EMPEFF_DB'),
    'dbatest':     ('DBATEST_HOST',      'DBATEST_PORT',     'DBATEST_USER',     'DBATEST_PASS',     'DBATEST_DB'),
}


def get_connection(server_name: str) -> pymysql.Connection:
    """Return a PyMySQL connection for the named server.

    server_name must be one of: opshop, salesorder, production,
    quality, empeff, dbatest.
    """
    if server_name not in _SERVER_ENV_MAP:
        raise ValueError(
            f"Unknown server '{server_name}'. "
            f"Must be one of: {', '.join(_SERVER_ENV_MAP.keys())}"
        )

    env_host, env_port, env_user, env_pass, env_db = _SERVER_ENV_MAP[server_name]
    host = os.environ.get(env_host)
    port = int(os.environ.get(env_port, '3306'))
    user = os.environ.get(env_user)
    password = os.environ.get(env_pass)
    database = os.environ.get(env_db)

    if not all([host, user, password, database]):
        raise ValueError(
            f"Missing database config for '{server_name}'. "
            f"Set {env_host}, {env_user}, {env_pass}, {env_db}"
        )

    log.debug("Connecting to %s @ %s:%d/%s", server_name, host, port, database)
    return pymysql.connect(
        host=host,
        port=port,
        user=user,
        password=password,
        database=database,
        charset='utf8mb4',
        cursorclass=pymysql.cursors.Cursor,
        connect_timeout=30,
        read_timeout=300,
        write_timeout=300,
    )


# ---------------------------------------------------------------------------
# PIPELINE STEP LOGGER
# ---------------------------------------------------------------------------

def log_step(conn, run_id: str, step_num: int, step_name: str,
             description: str, status: str, rows: int = 0,
             duration: float = 0, error: str = None):
    """Insert one row into test.store_anomaly_pipeline_log."""
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO test.store_anomaly_pipeline_log (
                    run_id, step_num, step_name, description,
                    status, rows_affected, duration_seconds,
                    error_message, created_at
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, NOW())
            """, (
                run_id, step_num, step_name, description,
                status, rows, round(duration, 2),
                (error or '')[:2000] if error else None,
            ))
        conn.commit()
    except Exception as exc:
        log.warning("Failed to write pipeline log for step %d (%s): %s",
                     step_num, step_name, exc)


# ---------------------------------------------------------------------------
# STEP 1: STORE MASTER DATA
# ---------------------------------------------------------------------------

def step_01_store_master(run_id: str, run_date: str) -> dict:
    """Extract store list from opshop.t_shop_info.

    Returns dict keyed by dept_id -> {store_code, store_name, ...}.
    """
    t0 = time.time()
    log.info("STEP 1: Extracting store master data ...")
    stores = {}
    conn = None
    try:
        conn = get_connection('opshop')
        placeholders = ','.join(['%s'] * len(STORE_IDS))
        sql = f"""
            SELECT dept_id, dept_code, dept_name, address, status
            FROM t_shop_info
            WHERE dept_id IN ({placeholders})
        """
        with conn.cursor() as cur:
            cur.execute(sql, STORE_IDS)
            rows = cur.fetchall()

        for row in rows:
            dept_id, dept_code, dept_name, address, status = row
            stores[dept_id] = {
                'dept_code': dept_code,
                'dept_name': dept_name,
                'address': address,
                'status': status,
            }
        log.info("  -> Extracted %d stores from opshop", len(stores))

    finally:
        if conn:
            conn.close()

    # Fallback: fill from ACTIVE_STORES dict for any missing
    for dept_id, (code, name) in ACTIVE_STORES.items():
        if dept_id not in stores:
            stores[dept_id] = {
                'dept_code': code,
                'dept_name': name,
                'address': None,
                'status': 1,
            }

    duration = time.time() - t0
    # Log step to dbatest
    db = None
    try:
        db = get_connection('dbatest')
        log_step(db, run_id, 1, 'store_master',
                 f'Extracted {len(stores)} stores from opshop',
                 'SUCCESS', rows=len(stores), duration=duration)
    finally:
        if db:
            db.close()

    log.info("  Step 1 complete (%.1fs)", duration)
    return stores


# ---------------------------------------------------------------------------
# STEP 2: REVENUE KPIs
# ---------------------------------------------------------------------------

def step_02_revenue_kpis(run_id: str, run_date: str) -> int:
    """Extract daily revenue, order_count, AOV from salesorder.t_order.

    Writes INTO test.store_kpi_daily (INSERT ... ON DUPLICATE KEY UPDATE).
    Returns number of rows upserted.
    """
    t0 = time.time()
    log.info("STEP 2: Extracting revenue KPIs from salesorder ...")
    placeholders = ','.join(['%s'] * len(STORE_IDS))
    start_date = (date.fromisoformat(run_date) - timedelta(days=LOOKBACK_DAYS - 1)).isoformat()

    # -- Extract from salesorder --
    extract_sql = f"""
        SELECT
            DATE(create_time)                         AS kpi_date,
            shop_dept_id                              AS store_id,
            ROUND(SUM(total_price), 2)                AS revenue,
            COUNT(DISTINCT order_id)                  AS order_count,
            ROUND(SUM(total_price) / NULLIF(COUNT(DISTINCT order_id), 0), 2)
                                                      AS aov
        FROM t_order
        WHERE DATE(create_time) >= %s
          AND DATE(create_time) <= %s
          AND shop_dept_id IN ({placeholders})
          AND order_status NOT IN (5, 6)
        GROUP BY DATE(create_time), shop_dept_id
        ORDER BY kpi_date, store_id
    """
    params = [start_date, run_date] + list(STORE_IDS)

    conn_src = None
    data = []
    try:
        conn_src = get_connection('salesorder')
        with conn_src.cursor() as cur:
            cur.execute(extract_sql, params)
            data = cur.fetchall()
        log.info("  -> Extracted %d revenue rows", len(data))
    finally:
        if conn_src:
            conn_src.close()

    if not data:
        log.warning("  No revenue data found for %s to %s", start_date, run_date)

    # -- Load into dbatest --
    upsert_sql = """
        INSERT INTO test.store_kpi_daily (
            kpi_date, store_id, store_code, store_name,
            revenue, order_count, aov
        ) VALUES (%s, %s, %s, %s, %s, %s, %s)
        ON DUPLICATE KEY UPDATE
            revenue     = VALUES(revenue),
            order_count = VALUES(order_count),
            aov         = VALUES(aov),
            updated_at  = NOW()
    """
    rows_upserted = 0
    conn_dst = None
    try:
        conn_dst = get_connection('dbatest')
        with conn_dst.cursor() as cur:
            for row in data:
                kpi_date, store_id, revenue, order_count, aov = row
                info = ACTIVE_STORES.get(store_id, ('UNKNOWN', 'Unknown Store'))
                cur.execute(upsert_sql, (
                    kpi_date, store_id, info[0], info[1],
                    revenue, order_count, aov,
                ))
                rows_upserted += 1
        conn_dst.commit()
        log.info("  -> Upserted %d rows into store_kpi_daily", rows_upserted)

        duration = time.time() - t0
        log_step(conn_dst, run_id, 2, 'revenue_kpis',
                 f'Extracted {len(data)} revenue rows, upserted {rows_upserted}',
                 'SUCCESS', rows=rows_upserted, duration=duration)
    finally:
        if conn_dst:
            conn_dst.close()

    log.info("  Step 2 complete (%.1fs)", time.time() - t0)
    return rows_upserted


# ---------------------------------------------------------------------------
# STEP 3: PRODUCTION KPIs
# ---------------------------------------------------------------------------

def step_03_production_kpis(run_id: str, run_date: str) -> int:
    """Extract production_count, avg_production_time_sec from
    opproduction.t_production. UPDATE test.store_kpi_daily.
    """
    t0 = time.time()
    log.info("STEP 3: Extracting production KPIs from opproduction ...")
    placeholders = ','.join(['%s'] * len(STORE_IDS))
    start_date = (date.fromisoformat(run_date) - timedelta(days=LOOKBACK_DAYS - 1)).isoformat()

    extract_sql = f"""
        SELECT
            DATE(create_time)               AS kpi_date,
            shop_dept_id                    AS store_id,
            COUNT(*)                        AS production_count,
            ROUND(AVG(
                TIMESTAMPDIFF(SECOND, create_time, complete_time)
            ), 1)                           AS avg_production_time_sec
        FROM t_production
        WHERE DATE(create_time) >= %s
          AND DATE(create_time) <= %s
          AND shop_dept_id IN ({placeholders})
          AND complete_time IS NOT NULL
        GROUP BY DATE(create_time), shop_dept_id
        ORDER BY kpi_date, store_id
    """
    params = [start_date, run_date] + list(STORE_IDS)

    conn_src = None
    data = []
    try:
        conn_src = get_connection('production')
        with conn_src.cursor() as cur:
            cur.execute(extract_sql, params)
            data = cur.fetchall()
        log.info("  -> Extracted %d production rows", len(data))
    finally:
        if conn_src:
            conn_src.close()

    update_sql = """
        UPDATE test.store_kpi_daily
        SET production_count         = %s,
            avg_production_time_sec  = %s,
            updated_at               = NOW()
        WHERE kpi_date = %s AND store_id = %s
    """
    rows_updated = 0
    conn_dst = None
    try:
        conn_dst = get_connection('dbatest')
        with conn_dst.cursor() as cur:
            for row in data:
                kpi_date, store_id, prod_count, avg_time = row
                cur.execute(update_sql, (prod_count, avg_time, kpi_date, store_id))
                rows_updated += cur.rowcount
        conn_dst.commit()
        log.info("  -> Updated %d rows in store_kpi_daily", rows_updated)

        duration = time.time() - t0
        log_step(conn_dst, run_id, 3, 'production_kpis',
                 f'Extracted {len(data)} production rows, updated {rows_updated}',
                 'SUCCESS', rows=rows_updated, duration=duration)
    finally:
        if conn_dst:
            conn_dst.close()

    log.info("  Step 3 complete (%.1fs)", time.time() - t0)
    return rows_updated


# ---------------------------------------------------------------------------
# STEP 4: STAFFING KPIs
# ---------------------------------------------------------------------------

def step_04_staffing_kpis(run_id: str, run_date: str) -> int:
    """Extract scheduled_hours, employee_count from
    opempefficiency.t_emp_scheduling. UPDATE test.store_kpi_daily.
    """
    t0 = time.time()
    log.info("STEP 4: Extracting staffing KPIs from opempefficiency ...")
    placeholders = ','.join(['%s'] * len(STORE_IDS))
    start_date = (date.fromisoformat(run_date) - timedelta(days=LOOKBACK_DAYS - 1)).isoformat()

    extract_sql = f"""
        SELECT
            schedule_date                           AS kpi_date,
            shop_dept_id                            AS store_id,
            ROUND(SUM(
                TIMESTAMPDIFF(MINUTE, start_time, end_time) / 60.0
            ), 2)                                   AS scheduled_hours,
            COUNT(DISTINCT employee_id)             AS employee_count
        FROM t_emp_scheduling
        WHERE schedule_date >= %s
          AND schedule_date <= %s
          AND shop_dept_id IN ({placeholders})
        GROUP BY schedule_date, shop_dept_id
        ORDER BY kpi_date, store_id
    """
    params = [start_date, run_date] + list(STORE_IDS)

    conn_src = None
    data = []
    try:
        conn_src = get_connection('empeff')
        with conn_src.cursor() as cur:
            cur.execute(extract_sql, params)
            data = cur.fetchall()
        log.info("  -> Extracted %d staffing rows", len(data))
    finally:
        if conn_src:
            conn_src.close()

    update_sql = """
        UPDATE test.store_kpi_daily
        SET scheduled_hours   = %s,
            employee_count    = %s,
            updated_at        = NOW()
        WHERE kpi_date = %s AND store_id = %s
    """
    rows_updated = 0
    conn_dst = None
    try:
        conn_dst = get_connection('dbatest')
        with conn_dst.cursor() as cur:
            for row in data:
                kpi_date, store_id, sched_hours, emp_count = row
                cur.execute(update_sql, (sched_hours, emp_count, kpi_date, store_id))
                rows_updated += cur.rowcount
        conn_dst.commit()
        log.info("  -> Updated %d rows in store_kpi_daily", rows_updated)

        duration = time.time() - t0
        log_step(conn_dst, run_id, 4, 'staffing_kpis',
                 f'Extracted {len(data)} staffing rows, updated {rows_updated}',
                 'SUCCESS', rows=rows_updated, duration=duration)
    finally:
        if conn_dst:
            conn_dst.close()

    log.info("  Step 4 complete (%.1fs)", time.time() - t0)
    return rows_updated


# ---------------------------------------------------------------------------
# STEP 5: QUALITY KPIs
# ---------------------------------------------------------------------------

def step_05_quality_kpis(run_id: str, run_date: str) -> int:
    """Extract inspection_count, avg_quality_score from
    opqualitycontrol.t_shopcheck_report. UPDATE test.store_kpi_daily.
    """
    t0 = time.time()
    log.info("STEP 5: Extracting quality KPIs from opqualitycontrol ...")
    placeholders = ','.join(['%s'] * len(STORE_IDS))
    start_date = (date.fromisoformat(run_date) - timedelta(days=LOOKBACK_DAYS - 1)).isoformat()

    extract_sql = f"""
        SELECT
            DATE(check_time)                        AS kpi_date,
            shop_dept_id                            AS store_id,
            COUNT(*)                                AS inspection_count,
            ROUND(AVG(total_score), 2)              AS avg_quality_score
        FROM t_shopcheck_report
        WHERE DATE(check_time) >= %s
          AND DATE(check_time) <= %s
          AND shop_dept_id IN ({placeholders})
        GROUP BY DATE(check_time), shop_dept_id
        ORDER BY kpi_date, store_id
    """
    params = [start_date, run_date] + list(STORE_IDS)

    conn_src = None
    data = []
    try:
        conn_src = get_connection('quality')
        with conn_src.cursor() as cur:
            cur.execute(extract_sql, params)
            data = cur.fetchall()
        log.info("  -> Extracted %d quality rows", len(data))
    finally:
        if conn_src:
            conn_src.close()

    update_sql = """
        UPDATE test.store_kpi_daily
        SET inspection_count    = %s,
            avg_quality_score   = %s,
            updated_at          = NOW()
        WHERE kpi_date = %s AND store_id = %s
    """
    rows_updated = 0
    conn_dst = None
    try:
        conn_dst = get_connection('dbatest')
        with conn_dst.cursor() as cur:
            for row in data:
                kpi_date, store_id, insp_count, avg_score = row
                cur.execute(update_sql, (insp_count, avg_score, kpi_date, store_id))
                rows_updated += cur.rowcount
        conn_dst.commit()
        log.info("  -> Updated %d rows in store_kpi_daily", rows_updated)

        duration = time.time() - t0
        log_step(conn_dst, run_id, 5, 'quality_kpis',
                 f'Extracted {len(data)} quality rows, updated {rows_updated}',
                 'SUCCESS', rows=rows_updated, duration=duration)
    finally:
        if conn_dst:
            conn_dst.close()

    log.info("  Step 5 complete (%.1fs)", time.time() - t0)
    return rows_updated


# ---------------------------------------------------------------------------
# STEP 6: DERIVED METRICS
# ---------------------------------------------------------------------------

def step_06_derived_metrics(run_id: str, run_date: str) -> int:
    """Compute revenue_per_labor_hour and orders_per_labor_hour
    on dbatest from existing store_kpi_daily data.
    """
    t0 = time.time()
    log.info("STEP 6: Computing derived metrics ...")
    start_date = (date.fromisoformat(run_date) - timedelta(days=LOOKBACK_DAYS - 1)).isoformat()

    update_sql = """
        UPDATE test.store_kpi_daily
        SET revenue_per_labor_hour = CASE
                WHEN scheduled_hours > 0
                THEN ROUND(revenue / scheduled_hours, 2)
                ELSE NULL
            END,
            orders_per_labor_hour = CASE
                WHEN scheduled_hours > 0
                THEN ROUND(order_count / scheduled_hours, 2)
                ELSE NULL
            END,
            updated_at = NOW()
        WHERE kpi_date >= %s AND kpi_date <= %s
    """

    rows_updated = 0
    conn = None
    try:
        conn = get_connection('dbatest')
        with conn.cursor() as cur:
            cur.execute(update_sql, (start_date, run_date))
            rows_updated = cur.rowcount
        conn.commit()
        log.info("  -> Updated %d rows with derived metrics", rows_updated)

        duration = time.time() - t0
        log_step(conn, run_id, 6, 'derived_metrics',
                 f'Computed revenue_per_labor_hour, orders_per_labor_hour for {rows_updated} rows',
                 'SUCCESS', rows=rows_updated, duration=duration)
    finally:
        if conn:
            conn.close()

    log.info("  Step 6 complete (%.1fs)", time.time() - t0)
    return rows_updated


# ---------------------------------------------------------------------------
# STEP 7: ANOMALY Z-SCORES (28-day rolling)
# ---------------------------------------------------------------------------

def step_07_anomaly_zscores(run_id: str, run_date: str) -> int:
    """Compute 28-day rolling Z-scores for all KPI metrics.

    INSERT INTO test.store_anomaly_scores.
    """
    t0 = time.time()
    log.info("STEP 7: Computing 28-day rolling Z-scores ...")

    metrics = [
        'revenue', 'order_count', 'aov',
        'production_count', 'avg_production_time_sec',
        'scheduled_hours', 'employee_count',
        'inspection_count', 'avg_quality_score',
        'revenue_per_labor_hour', 'orders_per_labor_hour',
    ]

    # Build a SELECT that computes mean/stddev over trailing 28 days
    # and produces Z-score = (today_value - mean) / stddev
    zscore_cases = []
    for m in metrics:
        zscore_cases.append(f"""
            ROUND(
                (k.{m} - rolling.avg_{m})
                / NULLIF(rolling.std_{m}, 0)
            , 4) AS z_{m}
        """)
        zscore_cases.append(f"rolling.avg_{m} AS mean_{m}")
        zscore_cases.append(f"rolling.std_{m} AS std_{m}")

    rolling_selects = []
    for m in metrics:
        rolling_selects.append(f"ROUND(AVG(hist.{m}), 4)    AS avg_{m}")
        rolling_selects.append(f"ROUND(STDDEV(hist.{m}), 4) AS std_{m}")

    sql = f"""
        INSERT INTO test.store_anomaly_scores (
            score_date, store_id, store_code, store_name,
            {', '.join(f'z_{m}, mean_{m}, std_{m}' for m in metrics)},
            created_at
        )
        SELECT
            k.kpi_date,
            k.store_id,
            k.store_code,
            k.store_name,
            {', '.join(zscore_cases)},
            NOW()
        FROM test.store_kpi_daily k
        INNER JOIN (
            SELECT
                ref.kpi_date  AS ref_date,
                ref.store_id  AS ref_store,
                {', '.join(rolling_selects)}
            FROM test.store_kpi_daily ref
            INNER JOIN test.store_kpi_daily hist
                ON  hist.store_id = ref.store_id
                AND hist.kpi_date >= DATE_SUB(ref.kpi_date, INTERVAL {ROLLING_WINDOW} DAY)
                AND hist.kpi_date <  ref.kpi_date
            WHERE ref.kpi_date = %s
            GROUP BY ref.kpi_date, ref.store_id
        ) rolling
            ON  rolling.ref_date  = k.kpi_date
            AND rolling.ref_store = k.store_id
        WHERE k.kpi_date = %s
        ON DUPLICATE KEY UPDATE
            {', '.join(f'z_{m} = VALUES(z_{m}), mean_{m} = VALUES(mean_{m}), std_{m} = VALUES(std_{m})' for m in metrics)},
            created_at = NOW()
    """

    rows_inserted = 0
    conn = None
    try:
        conn = get_connection('dbatest')
        with conn.cursor() as cur:
            cur.execute(sql, (run_date, run_date))
            rows_inserted = cur.rowcount
        conn.commit()
        log.info("  -> Upserted %d anomaly score rows", rows_inserted)

        duration = time.time() - t0
        log_step(conn, run_id, 7, 'anomaly_zscores',
                 f'Computed Z-scores for {len(metrics)} metrics, {rows_inserted} stores',
                 'SUCCESS', rows=rows_inserted, duration=duration)
    finally:
        if conn:
            conn.close()

    log.info("  Step 7 complete (%.1fs)", time.time() - t0)
    return rows_inserted


# ---------------------------------------------------------------------------
# STEP 8: WESTERN ELECTRIC RULES
# ---------------------------------------------------------------------------

def step_08_western_electric(run_id: str, run_date: str) -> int:
    """Evaluate Western Electric rules 1-5 against Z-scores.

    Updates we_rule1..we_rule5 and anomaly_severity in
    test.store_anomaly_scores.

    WE Rules (applied to z_revenue as primary):
      Rule 1: One point beyond 3 sigma                -> CRITICAL
      Rule 2: Two of three consecutive beyond 2 sigma -> WARNING
      Rule 3: Four of five consecutive beyond 1 sigma -> WARNING
      Rule 4: Eight consecutive on same side of mean   -> WARNING
      Rule 5: Six consecutive trending same direction  -> INFO
    """
    t0 = time.time()
    log.info("STEP 8: Evaluating Western Electric rules ...")

    conn = None
    rows_updated = 0
    try:
        conn = get_connection('dbatest')

        # ---- Rule 1: single point beyond 3 sigma ----
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE test.store_anomaly_scores
                SET we_rule1 = 1,
                    anomaly_severity = 'CRITICAL'
                WHERE score_date = %s
                  AND (ABS(z_revenue) >= %s OR ABS(z_order_count) >= %s)
            """, (run_date, SIGMA_CRITICAL, SIGMA_CRITICAL))
            r1 = cur.rowcount
            log.info("  Rule 1 (|Z| >= 3 sigma): %d stores", r1)

        # ---- Rule 2: 2 of 3 consecutive beyond 2 sigma ----
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE test.store_anomaly_scores sc
                INNER JOIN (
                    SELECT s.store_id
                    FROM test.store_anomaly_scores s
                    WHERE s.score_date BETWEEN DATE_SUB(%s, INTERVAL 2 DAY) AND %s
                    GROUP BY s.store_id
                    HAVING SUM(ABS(s.z_revenue) >= %s) >= 2
                ) hit ON hit.store_id = sc.store_id
                SET sc.we_rule2 = 1,
                    sc.anomaly_severity = CASE
                        WHEN sc.anomaly_severity = 'CRITICAL' THEN 'CRITICAL'
                        ELSE 'WARNING'
                    END
                WHERE sc.score_date = %s
            """, (run_date, run_date, SIGMA_WARNING, run_date))
            r2 = cur.rowcount
            log.info("  Rule 2 (2/3 beyond 2 sigma): %d stores", r2)

        # ---- Rule 3: 4 of 5 consecutive beyond 1 sigma ----
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE test.store_anomaly_scores sc
                INNER JOIN (
                    SELECT s.store_id
                    FROM test.store_anomaly_scores s
                    WHERE s.score_date BETWEEN DATE_SUB(%s, INTERVAL 4 DAY) AND %s
                    GROUP BY s.store_id
                    HAVING SUM(ABS(s.z_revenue) >= 1) >= 4
                ) hit ON hit.store_id = sc.store_id
                SET sc.we_rule3 = 1,
                    sc.anomaly_severity = CASE
                        WHEN sc.anomaly_severity IN ('CRITICAL', 'WARNING') THEN sc.anomaly_severity
                        ELSE 'WARNING'
                    END
                WHERE sc.score_date = %s
            """, (run_date, run_date, run_date))
            r3 = cur.rowcount
            log.info("  Rule 3 (4/5 beyond 1 sigma): %d stores", r3)

        # ---- Rule 4: 8 consecutive on same side of mean ----
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE test.store_anomaly_scores sc
                INNER JOIN (
                    SELECT s.store_id
                    FROM test.store_anomaly_scores s
                    WHERE s.score_date BETWEEN DATE_SUB(%s, INTERVAL 7 DAY) AND %s
                    GROUP BY s.store_id
                    HAVING COUNT(*) >= 8
                       AND (MIN(z_revenue) > 0 OR MAX(z_revenue) < 0)
                ) hit ON hit.store_id = sc.store_id
                SET sc.we_rule4 = 1,
                    sc.anomaly_severity = CASE
                        WHEN sc.anomaly_severity IN ('CRITICAL', 'WARNING') THEN sc.anomaly_severity
                        ELSE 'WARNING'
                    END
                WHERE sc.score_date = %s
            """, (run_date, run_date, run_date))
            r4 = cur.rowcount
            log.info("  Rule 4 (8 same side): %d stores", r4)

        # ---- Rule 5: 6 consecutive trending same direction ----
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE test.store_anomaly_scores sc
                INNER JOIN (
                    SELECT a.store_id
                    FROM (
                        SELECT store_id, score_date, z_revenue,
                            z_revenue - LAG(z_revenue) OVER (
                                PARTITION BY store_id ORDER BY score_date
                            ) AS delta
                        FROM test.store_anomaly_scores
                        WHERE score_date BETWEEN DATE_SUB(%s, INTERVAL 5 DAY) AND %s
                    ) a
                    WHERE a.delta IS NOT NULL
                    GROUP BY a.store_id
                    HAVING COUNT(*) >= 5
                       AND (MIN(a.delta) > 0 OR MAX(a.delta) < 0)
                ) hit ON hit.store_id = sc.store_id
                SET sc.we_rule5 = 1,
                    sc.anomaly_severity = CASE
                        WHEN sc.anomaly_severity IS NOT NULL THEN sc.anomaly_severity
                        ELSE 'INFO'
                    END
                WHERE sc.score_date = %s
            """, (run_date, run_date, run_date))
            r5 = cur.rowcount
            log.info("  Rule 5 (6 trending): %d stores", r5)

        conn.commit()
        rows_updated = r1 + r2 + r3 + r4 + r5

        duration = time.time() - t0
        log_step(conn, run_id, 8, 'western_electric',
                 f'WE rules evaluated: R1={r1} R2={r2} R3={r3} R4={r4} R5={r5}',
                 'SUCCESS', rows=rows_updated, duration=duration)
    finally:
        if conn:
            conn.close()

    log.info("  Step 8 complete (%.1fs)", time.time() - t0)
    return rows_updated


# ---------------------------------------------------------------------------
# STEP 9: HEALTH SCORES
# ---------------------------------------------------------------------------

def step_09_health_scores(run_id: str, run_date: str) -> int:
    """Compute composite health scores with weighted formula.

    INSERT INTO test.store_health_scores.

    Health score (0-100) = weighted combination of per-dimension scores.
    Each dimension score is derived from its Z-score:
      dimension_score = MAX(0, 100 - ABS(z) * 20)
    """
    t0 = time.time()
    log.info("STEP 9: Computing health scores ...")

    w = HEALTH_WEIGHTS

    sql = """
        INSERT INTO test.store_health_scores (
            score_date, store_id, store_code, store_name,
            revenue_score, ops_score, quality_score,
            staffing_score, customer_score,
            composite_score, health_grade, created_at
        )
        SELECT
            s.score_date,
            s.store_id,
            s.store_code,
            s.store_name,

            -- revenue dimension: based on z_revenue and z_aov
            ROUND(GREATEST(0, 100 - (ABS(COALESCE(s.z_revenue, 0))
                  + ABS(COALESCE(s.z_aov, 0))) / 2.0 * 20), 1)
                AS revenue_score,

            -- ops dimension: based on z_production_count, z_avg_production_time_sec
            ROUND(GREATEST(0, 100 - (ABS(COALESCE(s.z_production_count, 0))
                  + ABS(COALESCE(s.z_avg_production_time_sec, 0))) / 2.0 * 20), 1)
                AS ops_score,

            -- quality dimension: based on z_avg_quality_score
            ROUND(GREATEST(0, 100 - ABS(COALESCE(s.z_avg_quality_score, 0)) * 20), 1)
                AS quality_score,

            -- staffing dimension: based on z_scheduled_hours, z_employee_count
            ROUND(GREATEST(0, 100 - (ABS(COALESCE(s.z_scheduled_hours, 0))
                  + ABS(COALESCE(s.z_employee_count, 0))) / 2.0 * 20), 1)
                AS staffing_score,

            -- customer dimension: based on z_order_count, z_orders_per_labor_hour
            ROUND(GREATEST(0, 100 - (ABS(COALESCE(s.z_order_count, 0))
                  + ABS(COALESCE(s.z_orders_per_labor_hour, 0))) / 2.0 * 20), 1)
                AS customer_score,

            -- composite weighted score
            ROUND(
                {w_rev} * GREATEST(0, 100 - (ABS(COALESCE(s.z_revenue, 0))
                          + ABS(COALESCE(s.z_aov, 0))) / 2.0 * 20)
              + {w_ops} * GREATEST(0, 100 - (ABS(COALESCE(s.z_production_count, 0))
                          + ABS(COALESCE(s.z_avg_production_time_sec, 0))) / 2.0 * 20)
              + {w_qua} * GREATEST(0, 100 - ABS(COALESCE(s.z_avg_quality_score, 0)) * 20)
              + {w_sta} * GREATEST(0, 100 - (ABS(COALESCE(s.z_scheduled_hours, 0))
                          + ABS(COALESCE(s.z_employee_count, 0))) / 2.0 * 20)
              + {w_cus} * GREATEST(0, 100 - (ABS(COALESCE(s.z_order_count, 0))
                          + ABS(COALESCE(s.z_orders_per_labor_hour, 0))) / 2.0 * 20)
            , 1) AS composite_score,

            -- health grade
            CASE
                WHEN ROUND(
                    {w_rev} * GREATEST(0, 100 - (ABS(COALESCE(s.z_revenue, 0))
                              + ABS(COALESCE(s.z_aov, 0))) / 2.0 * 20)
                  + {w_ops} * GREATEST(0, 100 - (ABS(COALESCE(s.z_production_count, 0))
                              + ABS(COALESCE(s.z_avg_production_time_sec, 0))) / 2.0 * 20)
                  + {w_qua} * GREATEST(0, 100 - ABS(COALESCE(s.z_avg_quality_score, 0)) * 20)
                  + {w_sta} * GREATEST(0, 100 - (ABS(COALESCE(s.z_scheduled_hours, 0))
                              + ABS(COALESCE(s.z_employee_count, 0))) / 2.0 * 20)
                  + {w_cus} * GREATEST(0, 100 - (ABS(COALESCE(s.z_order_count, 0))
                              + ABS(COALESCE(s.z_orders_per_labor_hour, 0))) / 2.0 * 20)
                , 1) >= 90 THEN 'A'
                WHEN ROUND(
                    {w_rev} * GREATEST(0, 100 - (ABS(COALESCE(s.z_revenue, 0))
                              + ABS(COALESCE(s.z_aov, 0))) / 2.0 * 20)
                  + {w_ops} * GREATEST(0, 100 - (ABS(COALESCE(s.z_production_count, 0))
                              + ABS(COALESCE(s.z_avg_production_time_sec, 0))) / 2.0 * 20)
                  + {w_qua} * GREATEST(0, 100 - ABS(COALESCE(s.z_avg_quality_score, 0)) * 20)
                  + {w_sta} * GREATEST(0, 100 - (ABS(COALESCE(s.z_scheduled_hours, 0))
                              + ABS(COALESCE(s.z_employee_count, 0))) / 2.0 * 20)
                  + {w_cus} * GREATEST(0, 100 - (ABS(COALESCE(s.z_order_count, 0))
                              + ABS(COALESCE(s.z_orders_per_labor_hour, 0))) / 2.0 * 20)
                , 1) >= 75 THEN 'B'
                WHEN ROUND(
                    {w_rev} * GREATEST(0, 100 - (ABS(COALESCE(s.z_revenue, 0))
                              + ABS(COALESCE(s.z_aov, 0))) / 2.0 * 20)
                  + {w_ops} * GREATEST(0, 100 - (ABS(COALESCE(s.z_production_count, 0))
                              + ABS(COALESCE(s.z_avg_production_time_sec, 0))) / 2.0 * 20)
                  + {w_qua} * GREATEST(0, 100 - ABS(COALESCE(s.z_avg_quality_score, 0)) * 20)
                  + {w_sta} * GREATEST(0, 100 - (ABS(COALESCE(s.z_scheduled_hours, 0))
                              + ABS(COALESCE(s.z_employee_count, 0))) / 2.0 * 20)
                  + {w_cus} * GREATEST(0, 100 - (ABS(COALESCE(s.z_order_count, 0))
                              + ABS(COALESCE(s.z_orders_per_labor_hour, 0))) / 2.0 * 20)
                , 1) >= 60 THEN 'C'
                ELSE 'D'
            END AS health_grade,

            NOW()
        FROM test.store_anomaly_scores s
        WHERE s.score_date = %s
        ON DUPLICATE KEY UPDATE
            revenue_score   = VALUES(revenue_score),
            ops_score       = VALUES(ops_score),
            quality_score   = VALUES(quality_score),
            staffing_score  = VALUES(staffing_score),
            customer_score  = VALUES(customer_score),
            composite_score = VALUES(composite_score),
            health_grade    = VALUES(health_grade),
            created_at      = NOW()
    """.format(
        w_rev=w['revenue'], w_ops=w['ops'], w_qua=w['quality'],
        w_sta=w['staffing'], w_cus=w['customer'],
    )

    rows_upserted = 0
    conn = None
    try:
        conn = get_connection('dbatest')
        with conn.cursor() as cur:
            cur.execute(sql, (run_date,))
            rows_upserted = cur.rowcount
        conn.commit()
        log.info("  -> Upserted %d health score rows", rows_upserted)

        duration = time.time() - t0
        log_step(conn, run_id, 9, 'health_scores',
                 f'Computed health scores for {rows_upserted} stores',
                 'SUCCESS', rows=rows_upserted, duration=duration)
    finally:
        if conn:
            conn.close()

    log.info("  Step 9 complete (%.1fs)", time.time() - t0)
    return rows_upserted


# ---------------------------------------------------------------------------
# STEP 10: GENERATE ALERTS
# ---------------------------------------------------------------------------

def step_10_alerts(run_id: str, run_date: str) -> int:
    """Generate alerts based on anomaly severity and health grades.

    INSERT INTO test.store_anomaly_alerts with description_en and
    description_cn (bilingual).
    """
    t0 = time.time()
    log.info("STEP 10: Generating alerts ...")

    sql = """
        INSERT INTO test.store_anomaly_alerts (
            alert_date, store_id, store_code, store_name,
            alert_type, severity, metric_name, metric_value,
            z_score, threshold,
            description_en, description_cn,
            we_rules_triggered, health_grade, composite_score,
            is_acknowledged, created_at
        )
        SELECT
            sc.score_date,
            sc.store_id,
            sc.store_code,
            sc.store_name,
            CASE
                WHEN sc.anomaly_severity = 'CRITICAL' THEN 'SPC_VIOLATION'
                WHEN sc.anomaly_severity = 'WARNING'  THEN 'SPC_WARNING'
                ELSE 'HEALTH_DEGRADATION'
            END AS alert_type,
            COALESCE(sc.anomaly_severity,
                CASE WHEN h.health_grade = 'D' THEN 'WARNING' ELSE 'INFO' END
            ) AS severity,
            'revenue' AS metric_name,
            k.revenue AS metric_value,
            sc.z_revenue AS z_score,
            CASE
                WHEN ABS(sc.z_revenue) >= 3 THEN 3.0
                WHEN ABS(sc.z_revenue) >= 2 THEN 2.0
                ELSE 1.0
            END AS threshold,

            -- English description
            CONCAT(
                sc.store_name, ': ',
                CASE
                    WHEN sc.anomaly_severity = 'CRITICAL'
                        THEN CONCAT('CRITICAL anomaly detected. Revenue Z=',
                             ROUND(sc.z_revenue, 2), ' (beyond 3 sigma).')
                    WHEN sc.anomaly_severity = 'WARNING'
                        THEN CONCAT('WARNING: SPC rule triggered. Revenue Z=',
                             ROUND(sc.z_revenue, 2), '.')
                    WHEN h.health_grade = 'D'
                        THEN CONCAT('Health grade D (score=', ROUND(h.composite_score, 1),
                             '). Multiple dimensions degraded.')
                    ELSE CONCAT('Monitoring alert. Revenue Z=',
                             ROUND(sc.z_revenue, 2), ', Health=', h.health_grade, '.')
                END
            ) AS description_en,

            -- Chinese description
            CONCAT(
                sc.store_name, ': ',
                CASE
                    WHEN sc.anomaly_severity = 'CRITICAL'
                        THEN CONCAT('严重异常。营收Z=',
                             ROUND(sc.z_revenue, 2), '(超过3个标准差)')
                    WHEN sc.anomaly_severity = 'WARNING'
                        THEN CONCAT('警告: SPC规则触发。营收Z=',
                             ROUND(sc.z_revenue, 2))
                    WHEN h.health_grade = 'D'
                        THEN CONCAT('健康等级D(得分=', ROUND(h.composite_score, 1),
                             ')。多个维度下降。')
                    ELSE CONCAT('监控提醒。营收Z=',
                             ROUND(sc.z_revenue, 2), ', 健康=', h.health_grade)
                END
            ) AS description_cn,

            CONCAT_WS(',',
                IF(sc.we_rule1, 'R1', NULL),
                IF(sc.we_rule2, 'R2', NULL),
                IF(sc.we_rule3, 'R3', NULL),
                IF(sc.we_rule4, 'R4', NULL),
                IF(sc.we_rule5, 'R5', NULL)
            ) AS we_rules_triggered,

            h.health_grade,
            h.composite_score,
            0,
            NOW()
        FROM test.store_anomaly_scores sc
        LEFT JOIN test.store_health_scores h
            ON  h.score_date = sc.score_date
            AND h.store_id   = sc.store_id
        LEFT JOIN test.store_kpi_daily k
            ON  k.kpi_date  = sc.score_date
            AND k.store_id  = sc.store_id
        WHERE sc.score_date = %s
          AND (
              sc.anomaly_severity IS NOT NULL
              OR h.health_grade = 'D'
          )
        ON DUPLICATE KEY UPDATE
            alert_type         = VALUES(alert_type),
            severity           = VALUES(severity),
            metric_value       = VALUES(metric_value),
            z_score            = VALUES(z_score),
            description_en     = VALUES(description_en),
            description_cn     = VALUES(description_cn),
            we_rules_triggered = VALUES(we_rules_triggered),
            health_grade       = VALUES(health_grade),
            composite_score    = VALUES(composite_score),
            created_at         = NOW()
    """

    rows_inserted = 0
    conn = None
    try:
        conn = get_connection('dbatest')
        with conn.cursor() as cur:
            cur.execute(sql, (run_date,))
            rows_inserted = cur.rowcount
        conn.commit()
        log.info("  -> Generated %d alerts", rows_inserted)

        duration = time.time() - t0
        log_step(conn, run_id, 10, 'alerts',
                 f'Generated {rows_inserted} alerts',
                 'SUCCESS', rows=rows_inserted, duration=duration)
    finally:
        if conn:
            conn.close()

    log.info("  Step 10 complete (%.1fs)", time.time() - t0)
    return rows_inserted


# ---------------------------------------------------------------------------
# STEP 11: LOG PIPELINE COMPLETION
# ---------------------------------------------------------------------------

def step_11_log_completion(run_id: str, run_date: str,
                           pipeline_start: float, step_results: dict):
    """Write final pipeline summary log entry."""
    t0 = time.time()
    log.info("STEP 11: Logging pipeline completion ...")
    total_duration = time.time() - pipeline_start

    summary_parts = []
    for step_name, result in step_results.items():
        summary_parts.append(f"{step_name}={result}")
    summary = '; '.join(summary_parts)

    conn = None
    try:
        conn = get_connection('dbatest')
        log_step(conn, run_id, 11, 'pipeline_complete',
                 f'Pipeline finished in {total_duration:.1f}s. {summary}',
                 'SUCCESS', rows=0, duration=total_duration)
    finally:
        if conn:
            conn.close()

    log.info("  Step 11 complete -- pipeline duration %.1fs", total_duration)


# ---------------------------------------------------------------------------
# STEP 12: VERIFY
# ---------------------------------------------------------------------------

def step_12_verify(run_id: str, run_date: str) -> bool:
    """Check row counts and data freshness, print summary."""
    t0 = time.time()
    log.info("STEP 12: Verifying pipeline results ...")
    ok = True

    conn = None
    try:
        conn = get_connection('dbatest')
        checks = {
            'store_kpi_daily': (
                "SELECT COUNT(*) FROM test.store_kpi_daily WHERE kpi_date = %s",
                (run_date,),
            ),
            'store_anomaly_scores': (
                "SELECT COUNT(*) FROM test.store_anomaly_scores WHERE score_date = %s",
                (run_date,),
            ),
            'store_health_scores': (
                "SELECT COUNT(*) FROM test.store_health_scores WHERE score_date = %s",
                (run_date,),
            ),
            'store_anomaly_alerts': (
                "SELECT COUNT(*) FROM test.store_anomaly_alerts WHERE alert_date = %s",
                (run_date,),
            ),
            'pipeline_log': (
                "SELECT COUNT(*) FROM test.store_anomaly_pipeline_log WHERE run_id = %s",
                (run_id,),
            ),
        }

        log.info("  %-30s %s", "TABLE", "ROWS")
        log.info("  %-30s %s", "-" * 30, "----")
        for table_label, (sql, params) in checks.items():
            with conn.cursor() as cur:
                cur.execute(sql, params)
                count = cur.fetchone()[0]
            log.info("  %-30s %d", table_label, count)
            if table_label == 'store_kpi_daily' and count == 0:
                log.warning("  WARN: No KPI rows for %s", run_date)
                ok = False

        # Check data freshness
        with conn.cursor() as cur:
            cur.execute("""
                SELECT MAX(updated_at) FROM test.store_kpi_daily
                WHERE kpi_date = %s
            """, (run_date,))
            max_updated = cur.fetchone()[0]
            if max_updated:
                age_minutes = (datetime.now() - max_updated).total_seconds() / 60.0
                log.info("  Data freshness: last update %s (%.1f min ago)",
                         max_updated, age_minutes)
                if age_minutes > 120:
                    log.warning("  WARN: Data is >2 hours old")
                    ok = False
            else:
                log.warning("  WARN: No updated_at found for %s", run_date)
                ok = False

        duration = time.time() - t0
        status = 'SUCCESS' if ok else 'WARNING'
        log_step(conn, run_id, 12, 'verify',
                 f'Verification {"passed" if ok else "has warnings"}',
                 status, rows=0, duration=duration)

    finally:
        if conn:
            conn.close()

    log.info("  Step 12 complete (%.1fs) -- %s",
             time.time() - t0, "ALL OK" if ok else "WARNINGS DETECTED")
    return ok


# ---------------------------------------------------------------------------
# MAIN PIPELINE ORCHESTRATOR
# ---------------------------------------------------------------------------

def run_pipeline(run_date: str = None):
    """Main entry point. Execute all 12 steps with error handling.

    Each step is wrapped in try/except: on failure the error is logged
    and execution continues to the next step.
    """
    if run_date is None:
        run_date = (date.today() - timedelta(days=1)).isoformat()

    run_id = str(uuid.uuid4())[:12]
    pipeline_start = time.time()

    log.info("=" * 72)
    log.info("UC-OP-02  STORE PERFORMANCE ANOMALY DETECTION PIPELINE")
    log.info("Run ID:   %s", run_id)
    log.info("Run date: %s", run_date)
    log.info("Lookback: %d days", LOOKBACK_DAYS)
    log.info("Stores:   %d active", len(ACTIVE_STORES))
    log.info("=" * 72)

    step_results = {}
    failed_steps = []

    # -- Step 1: Store master data --
    try:
        stores = step_01_store_master(run_id, run_date)
        step_results['step01_stores'] = len(stores)
    except Exception as exc:
        log.error("STEP 1 FAILED: %s", exc, exc_info=True)
        failed_steps.append(1)
        step_results['step01_stores'] = 'FAILED'
        stores = dict(ACTIVE_STORES)  # fallback

    # -- Step 2: Revenue KPIs --
    try:
        rev_rows = step_02_revenue_kpis(run_id, run_date)
        step_results['step02_revenue'] = rev_rows
    except Exception as exc:
        log.error("STEP 2 FAILED: %s", exc, exc_info=True)
        failed_steps.append(2)
        step_results['step02_revenue'] = 'FAILED'

    # -- Step 3: Production KPIs --
    try:
        prod_rows = step_03_production_kpis(run_id, run_date)
        step_results['step03_production'] = prod_rows
    except Exception as exc:
        log.error("STEP 3 FAILED: %s", exc, exc_info=True)
        failed_steps.append(3)
        step_results['step03_production'] = 'FAILED'

    # -- Step 4: Staffing KPIs --
    try:
        staff_rows = step_04_staffing_kpis(run_id, run_date)
        step_results['step04_staffing'] = staff_rows
    except Exception as exc:
        log.error("STEP 4 FAILED: %s", exc, exc_info=True)
        failed_steps.append(4)
        step_results['step04_staffing'] = 'FAILED'

    # -- Step 5: Quality KPIs --
    try:
        qual_rows = step_05_quality_kpis(run_id, run_date)
        step_results['step05_quality'] = qual_rows
    except Exception as exc:
        log.error("STEP 5 FAILED: %s", exc, exc_info=True)
        failed_steps.append(5)
        step_results['step05_quality'] = 'FAILED'

    # -- Step 6: Derived metrics --
    try:
        derived_rows = step_06_derived_metrics(run_id, run_date)
        step_results['step06_derived'] = derived_rows
    except Exception as exc:
        log.error("STEP 6 FAILED: %s", exc, exc_info=True)
        failed_steps.append(6)
        step_results['step06_derived'] = 'FAILED'

    # -- Step 7: Z-scores --
    try:
        zscore_rows = step_07_anomaly_zscores(run_id, run_date)
        step_results['step07_zscores'] = zscore_rows
    except Exception as exc:
        log.error("STEP 7 FAILED: %s", exc, exc_info=True)
        failed_steps.append(7)
        step_results['step07_zscores'] = 'FAILED'

    # -- Step 8: Western Electric rules --
    try:
        we_rows = step_08_western_electric(run_id, run_date)
        step_results['step08_western_electric'] = we_rows
    except Exception as exc:
        log.error("STEP 8 FAILED: %s", exc, exc_info=True)
        failed_steps.append(8)
        step_results['step08_western_electric'] = 'FAILED'

    # -- Step 9: Health scores --
    try:
        health_rows = step_09_health_scores(run_id, run_date)
        step_results['step09_health'] = health_rows
    except Exception as exc:
        log.error("STEP 9 FAILED: %s", exc, exc_info=True)
        failed_steps.append(9)
        step_results['step09_health'] = 'FAILED'

    # -- Step 10: Alerts --
    try:
        alert_rows = step_10_alerts(run_id, run_date)
        step_results['step10_alerts'] = alert_rows
    except Exception as exc:
        log.error("STEP 10 FAILED: %s", exc, exc_info=True)
        failed_steps.append(10)
        step_results['step10_alerts'] = 'FAILED'

    # -- Step 11: Log completion --
    try:
        step_11_log_completion(run_id, run_date, pipeline_start, step_results)
    except Exception as exc:
        log.error("STEP 11 FAILED: %s", exc, exc_info=True)
        failed_steps.append(11)

    # -- Step 12: Verify --
    try:
        verify_ok = step_12_verify(run_id, run_date)
        step_results['step12_verify'] = 'OK' if verify_ok else 'WARNINGS'
    except Exception as exc:
        log.error("STEP 12 FAILED: %s", exc, exc_info=True)
        failed_steps.append(12)
        step_results['step12_verify'] = 'FAILED'

    # -- Final summary --
    total_duration = time.time() - pipeline_start
    log.info("=" * 72)
    if failed_steps:
        log.info("PIPELINE COMPLETE WITH ERRORS (steps %s failed)", failed_steps)
    else:
        log.info("PIPELINE COMPLETE SUCCESSFULLY")
    log.info("  Run ID:   %s", run_id)
    log.info("  Run date: %s", run_date)
    log.info("  Duration: %.1f seconds", total_duration)
    for k, v in step_results.items():
        log.info("  %-30s %s", k, v)
    log.info("=" * 72)

    if failed_steps:
        sys.exit(1)


# ---------------------------------------------------------------------------
# CLI ENTRY POINT
# ---------------------------------------------------------------------------

def main():
    """Parse args and invoke the pipeline."""
    parser = argparse.ArgumentParser(
        description="UC-OP-02: Store Performance Anomaly Detection -- ETL Pipeline",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python run_pipeline.py                          # Yesterday's data
  python run_pipeline.py --date 2026-02-14        # Specific date
  python run_pipeline.py --backfill-from 2026-01-01 --backfill-to 2026-02-14
        """,
    )
    parser.add_argument("--date", type=str,
                        help="Single date to process (YYYY-MM-DD). Default: yesterday.")
    parser.add_argument("--backfill-from", type=str,
                        help="Start date for backfill (YYYY-MM-DD)")
    parser.add_argument("--backfill-to", type=str,
                        help="End date for backfill (YYYY-MM-DD)")
    parser.add_argument("--env-file", type=str, default=None,
                        help="Path to .env file (default: ./orchestrator/.env)")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Enable DEBUG logging")
    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Optionally load a custom .env
    if args.env_file and load_dotenv:
        load_dotenv(args.env_file, override=True)
        log.info("Loaded env from %s", args.env_file)

    # Backfill mode
    if args.backfill_from and args.backfill_to:
        try:
            d_start = date.fromisoformat(args.backfill_from)
            d_end = date.fromisoformat(args.backfill_to)
        except ValueError as exc:
            log.error("Invalid date format: %s", exc)
            sys.exit(1)

        if d_start > d_end:
            log.error("--backfill-from (%s) must be <= --backfill-to (%s)",
                       args.backfill_from, args.backfill_to)
            sys.exit(1)

        total_days = (d_end - d_start).days + 1
        log.info("BACKFILL MODE: %d days from %s to %s",
                 total_days, d_start, d_end)

        current = d_start
        while current <= d_end:
            log.info("--- Backfill: %s ---", current.isoformat())
            run_pipeline(current.isoformat())
            current += timedelta(days=1)
        return

    # Single date mode
    if args.date:
        try:
            date.fromisoformat(args.date)
        except ValueError as exc:
            log.error("Invalid date format: %s", exc)
            sys.exit(1)
        run_pipeline(args.date)
    else:
        run_pipeline()  # defaults to yesterday


if __name__ == '__main__':
    main()

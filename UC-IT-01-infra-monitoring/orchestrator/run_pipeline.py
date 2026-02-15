#!/usr/bin/env python3
"""
UC-IT-01: Predictive Infrastructure Monitoring
Main Pipeline Orchestrator — Multi-Source ETL
预测性基础设施监控 — 主管道编排器

Coordinates the full 14-step daily pipeline:
    Step  1: Prometheus → Fleet inventory (up targets)
    Step  2: Prometheus → Redis memory, connections, ops/sec, CPU
    Step  3: Prometheus → Redis keyspace, evictions, hit rate
    Step  4: CloudWatch → RDS CPUUtilization, FreeableMemory, Connections
    Step  5: CloudWatch → RDS ReadLatency, WriteLatency, IOPS
    Step  6: CloudWatch Logs → Slow query counts from RDS log groups
    Step  7: MCP DB Gateway → MySQL-specific metrics (SHOW STATUS)
    Step  8: infra_metric_daily → infra_fleet_inventory (update registry)
    Step  9: infra_metric_daily → infra_anomaly_scores (14-day rolling SPC)
    Step 10: anomaly_scores → anomaly_scores (Western Electric rules)
    Step 11: anomaly_scores → anomaly_scores (rate-of-change features)
    Step 12: multi-table → infra_health_scores (composite health)
    Step 13: scores + health → infra_anomaly_alerts (tiered alerts)
    Step 14: all tables → pipeline_log (execution logging)

Usage:
    python run_pipeline.py                         # Full daily run
    python run_pipeline.py --date 2026-02-14       # Specific date
    python run_pipeline.py --backfill 14           # Last 14 days
    python run_pipeline.py --steps 1,2,3           # Specific steps only
    python run_pipeline.py --dry-run               # Validate without writes
    python run_pipeline.py --skip-cloudwatch       # Skip CW (saves API costs)

Author: Data Engineering / BI Team
Created: 2026-02-15
"""

import os
import sys
import uuid
import logging
import argparse
import json
import time
from datetime import datetime, date, timedelta
from typing import Dict, List, Optional, Set

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

# Import sibling collectors
_script_dir = os.path.dirname(os.path.abspath(__file__))
if _script_dir not in sys.path:
    sys.path.insert(0, _script_dir)

try:
    from prometheus_collector import (
        PrometheusClient,
        collect_instant_metrics,
        collect_rate_metrics,
        compute_derived_metrics,
        insert_metrics as prom_insert_metrics,
    )
    HAS_PROMETHEUS = True
except ImportError as exc:
    HAS_PROMETHEUS = False
    print(f"WARNING: prometheus_collector not available: {exc}")

try:
    from cloudwatch_collector import (
        CloudWatchCollector,
        collect_slow_query_counts,
        insert_metrics as cw_insert_metrics,
    )
    HAS_CLOUDWATCH = True
except ImportError as exc:
    HAS_CLOUDWATCH = False
    print(f"WARNING: cloudwatch_collector not available: {exc}")


# ---------------------------------------------------------------------------
# LOGGING
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=getattr(logging, os.getenv('LOG_LEVEL', 'INFO')),
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
)
log = logging.getLogger('uc-it-01')

# ---------------------------------------------------------------------------
# CONSTANTS
# ---------------------------------------------------------------------------

ROLLING_WINDOW = int(os.getenv('ROLLING_WINDOW', '14'))   # days for SPC baseline
SIGMA_WARNING  = int(os.getenv('SIGMA_WARNING', '2'))      # Z-score WARNING threshold
SIGMA_CRITICAL = int(os.getenv('SIGMA_CRITICAL', '3'))     # Z-score CRITICAL threshold
BATCH_SIZE     = int(os.getenv('BATCH_SIZE', '500'))

# Metric categories for health score computation
HEALTH_WEIGHTS = {
    'memory':      0.25,   # memory_utilization_pct, freeable_memory
    'cpu':         0.20,   # cpu_utilization, total_cpu_rate
    'connections': 0.15,   # connected_clients, database_connections
    'latency':     0.20,   # read_latency, write_latency
    'throughput':  0.10,   # commands_per_sec, read_iops, write_iops
    'cache':       0.10,   # cache_hit_rate_pct, evicted_keys_rate
}

# Map metric names to health categories
METRIC_CATEGORY_MAP = {
    'memory_utilization_pct': 'memory',
    'memory_used_bytes':      'memory',
    'memory_max_bytes':       'memory',
    'freeable_memory':        'memory',
    'free_storage_space':     'memory',
    'swap_usage':             'memory',
    'cpu_utilization':        'cpu',
    'total_cpu_rate':         'cpu',
    'cpu_sys_rate':           'cpu',
    'cpu_user_rate':          'cpu',
    'connected_clients':      'connections',
    'blocked_clients':        'connections',
    'database_connections':   'connections',
    'read_latency':           'latency',
    'write_latency':          'latency',
    'disk_queue_depth':       'latency',
    'commands_per_sec':       'throughput',
    'read_iops':              'throughput',
    'write_iops':             'throughput',
    'network_receive_throughput': 'throughput',
    'network_transmit_throughput': 'throughput',
    'cache_hit_rate_pct':     'cache',
    'keyspace_hits_rate':     'cache',
    'keyspace_misses_rate':   'cache',
    'evicted_keys_rate':      'cache',
}


# ---------------------------------------------------------------------------
# DATABASE CONNECTION HELPER
# ---------------------------------------------------------------------------

_SERVER_ENV_MAP = {
    'dbatest': ('DBATEST_HOST', 'DBATEST_PORT', 'DBATEST_USER', 'DBATEST_PASS', 'DBATEST_DB'),
}


def get_connection(server_name: str = 'dbatest') -> pymysql.Connection:
    """Return a PyMySQL connection for the named server.

    server_name must be one of: dbatest
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
    """Insert one row into test.infra_monitoring_pipeline_log."""
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO test.infra_monitoring_pipeline_log (
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
# STEP 1: FLEET INVENTORY FROM PROMETHEUS
# ---------------------------------------------------------------------------

def step_01_fleet_inventory(run_id: str, run_date: str, dry_run: bool = False) -> int:
    """Discover active infrastructure from Prometheus 'up' targets.

    Upserts into test.infra_fleet_inventory with resource metadata.
    """
    t0 = time.time()
    log.info("STEP 1: Discovering fleet inventory from Prometheus targets ...")

    if not HAS_PROMETHEUS:
        log.warning("  Prometheus collector not available. Skipping.")
        return 0

    prom = PrometheusClient()
    if not prom.health_check():
        log.error("  Prometheus unreachable. Skipping fleet discovery.")
        return 0

    targets = prom.get_targets()
    log.info("  Found %d active scrape targets", len(targets))

    if dry_run:
        log.info("  [DRY RUN] Would upsert %d inventory rows", len(targets))
        return len(targets)

    rows_affected = 0
    conn = None
    try:
        conn = get_connection('dbatest')
        upsert_sql = """
            INSERT INTO test.infra_fleet_inventory (
                resource_type, resource_name, instance, job,
                scrape_url, status, last_seen, created_at
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, NOW())
            ON DUPLICATE KEY UPDATE
                status    = VALUES(status),
                last_seen = VALUES(last_seen),
                updated_at = NOW()
        """

        with conn.cursor() as cur:
            for target in targets:
                labels = target.get('labels', {})
                job = labels.get('job', 'unknown')
                instance = labels.get('instance', labels.get('addr', 'unknown'))
                scrape_url = target.get('scrapeUrl', '')
                health = target.get('health', 'unknown')

                # Determine resource type from job label
                if 'redis' in job.lower():
                    resource_type = 'redis'
                elif 'node' in job.lower():
                    resource_type = 'ec2'
                elif 'mysql' in job.lower() or 'rds' in job.lower():
                    resource_type = 'rds'
                else:
                    resource_type = 'other'

                from prometheus_collector import parse_instance_name
                resource_name = parse_instance_name(instance)

                cur.execute(upsert_sql, (
                    resource_type, resource_name, instance[:255], job,
                    scrape_url[:512], health, run_date,
                ))
                rows_affected += cur.rowcount

        conn.commit()
        duration = time.time() - t0
        log_step(conn, run_id, 1, 'fleet_inventory',
                 f'Discovered {len(targets)} targets, upserted {rows_affected} inventory rows',
                 'SUCCESS', rows=rows_affected, duration=duration)

    except Exception as exc:
        duration = time.time() - t0
        log.error("  Step 1 failed: %s", exc)
        if conn:
            log_step(conn, run_id, 1, 'fleet_inventory',
                     'Fleet inventory discovery failed', 'FAILED',
                     duration=duration, error=str(exc))
        raise
    finally:
        if conn:
            conn.close()

    log.info("  Step 1 complete: %d rows (%.1fs)", rows_affected, time.time() - t0)
    return rows_affected


# ---------------------------------------------------------------------------
# STEP 2: PROMETHEUS REDIS MEMORY + CONNECTIONS + CPU
# ---------------------------------------------------------------------------

def step_02_redis_instant_metrics(run_id: str, run_date: str, dry_run: bool = False) -> int:
    """Collect Redis gauge metrics: memory, connections, CPU, fragmentation."""
    t0 = time.time()
    log.info("STEP 2: Collecting Redis instant (gauge) metrics ...")

    if not HAS_PROMETHEUS:
        log.warning("  Prometheus collector not available. Skipping.")
        return 0

    prom = PrometheusClient()
    target_date = date.fromisoformat(run_date)
    rows = collect_instant_metrics(prom, target_date)
    log.info("  Collected %d instant metric rows", len(rows))

    if dry_run:
        log.info("  [DRY RUN] Would insert %d rows", len(rows))
        return len(rows)

    rows_affected = 0
    conn = None
    try:
        conn = get_connection('dbatest')
        rows_affected = prom_insert_metrics(conn, rows)
        duration = time.time() - t0
        log_step(conn, run_id, 2, 'redis_instant_metrics',
                 f'Collected {len(rows)} gauge metrics, inserted {rows_affected}',
                 'SUCCESS', rows=rows_affected, duration=duration)
    except Exception as exc:
        duration = time.time() - t0
        log.error("  Step 2 failed: %s", exc)
        if conn:
            log_step(conn, run_id, 2, 'redis_instant_metrics',
                     'Redis gauge collection failed', 'FAILED',
                     duration=duration, error=str(exc))
        raise
    finally:
        if conn:
            conn.close()

    log.info("  Step 2 complete: %d rows (%.1fs)", rows_affected, time.time() - t0)
    return rows_affected


# ---------------------------------------------------------------------------
# STEP 3: PROMETHEUS REDIS KEYSPACE + EVICTIONS + DERIVED
# ---------------------------------------------------------------------------

def step_03_redis_rate_metrics(run_id: str, run_date: str, dry_run: bool = False) -> int:
    """Collect Redis counter metrics (rate) + compute derived metrics."""
    t0 = time.time()
    log.info("STEP 3: Collecting Redis rate (counter) metrics + derived ...")

    if not HAS_PROMETHEUS:
        log.warning("  Prometheus collector not available. Skipping.")
        return 0

    prom = PrometheusClient()
    target_date = date.fromisoformat(run_date)

    rate_rows = collect_rate_metrics(prom, target_date)
    log.info("  Collected %d rate metric rows", len(rate_rows))

    # Also re-read instant metrics for derived computation
    instant_rows = collect_instant_metrics(prom, target_date)
    all_raw = instant_rows + rate_rows
    derived_rows = compute_derived_metrics(all_raw)
    log.info("  Computed %d derived metrics", len(derived_rows))

    insert_rows = rate_rows + derived_rows

    if dry_run:
        log.info("  [DRY RUN] Would insert %d rows", len(insert_rows))
        return len(insert_rows)

    rows_affected = 0
    conn = None
    try:
        conn = get_connection('dbatest')
        rows_affected = prom_insert_metrics(conn, insert_rows)
        duration = time.time() - t0
        log_step(conn, run_id, 3, 'redis_rate_metrics',
                 f'Collected {len(rate_rows)} rate + {len(derived_rows)} derived, inserted {rows_affected}',
                 'SUCCESS', rows=rows_affected, duration=duration)
    except Exception as exc:
        duration = time.time() - t0
        log.error("  Step 3 failed: %s", exc)
        if conn:
            log_step(conn, run_id, 3, 'redis_rate_metrics',
                     'Redis rate collection failed', 'FAILED',
                     duration=duration, error=str(exc))
        raise
    finally:
        if conn:
            conn.close()

    log.info("  Step 3 complete: %d rows (%.1fs)", rows_affected, time.time() - t0)
    return rows_affected


# ---------------------------------------------------------------------------
# STEP 4: CLOUDWATCH RDS CORE METRICS
# ---------------------------------------------------------------------------

def step_04_rds_core_metrics(run_id: str, run_date: str, dry_run: bool = False) -> int:
    """Collect RDS CPUUtilization, FreeableMemory, DatabaseConnections."""
    t0 = time.time()
    log.info("STEP 4: Collecting RDS core metrics from CloudWatch ...")

    if not HAS_CLOUDWATCH:
        log.warning("  CloudWatch collector not available. Skipping.")
        return 0

    target_date = date.fromisoformat(run_date)
    collector = CloudWatchCollector()
    rows = collector.collect_rds_metrics(target_date)
    log.info("  Collected %d RDS metric rows", len(rows))

    if dry_run:
        log.info("  [DRY RUN] Would insert %d rows", len(rows))
        return len(rows)

    rows_affected = 0
    conn = None
    try:
        conn = get_connection('dbatest')
        rows_affected = cw_insert_metrics(conn, rows)
        duration = time.time() - t0
        log_step(conn, run_id, 4, 'rds_core_metrics',
                 f'Collected {len(rows)} RDS metrics, inserted {rows_affected}',
                 'SUCCESS', rows=rows_affected, duration=duration)
    except Exception as exc:
        duration = time.time() - t0
        log.error("  Step 4 failed: %s", exc)
        if conn:
            log_step(conn, run_id, 4, 'rds_core_metrics',
                     'RDS core metric collection failed', 'FAILED',
                     duration=duration, error=str(exc))
        raise
    finally:
        if conn:
            conn.close()

    log.info("  Step 4 complete: %d rows (%.1fs)", rows_affected, time.time() - t0)
    return rows_affected


# ---------------------------------------------------------------------------
# STEP 5: CLOUDWATCH RDS LATENCY + IOPS
# ---------------------------------------------------------------------------

def step_05_rds_latency_iops(run_id: str, run_date: str, dry_run: bool = False) -> int:
    """Collect RDS ReadLatency, WriteLatency, ReadIOPS, WriteIOPS.

    NOTE: These are collected together with step 4 in the current
    CloudWatchCollector implementation. This step logs the subset
    of latency/IOPS metrics for audit granularity.
    """
    t0 = time.time()
    log.info("STEP 5: Verifying RDS latency/IOPS metrics ...")

    # Latency and IOPS metrics are already collected in step 4.
    # This step verifies they exist in infra_metric_daily.
    rows_verified = 0
    conn = None
    try:
        conn = get_connection('dbatest')
        with conn.cursor() as cur:
            cur.execute("""
                SELECT COUNT(*) FROM test.infra_metric_daily
                WHERE metric_date = %s
                  AND resource_type = 'rds'
                  AND metric_name IN (
                      'read_latency', 'write_latency',
                      'read_iops', 'write_iops',
                      'disk_queue_depth'
                  )
            """, (run_date,))
            rows_verified = cur.fetchone()[0]

        duration = time.time() - t0
        log_step(conn, run_id, 5, 'rds_latency_iops',
                 f'Verified {rows_verified} RDS latency/IOPS rows for {run_date}',
                 'SUCCESS', rows=rows_verified, duration=duration)

    except Exception as exc:
        duration = time.time() - t0
        log.error("  Step 5 failed: %s", exc)
        if conn:
            log_step(conn, run_id, 5, 'rds_latency_iops',
                     'RDS latency/IOPS verification failed', 'FAILED',
                     duration=duration, error=str(exc))
    finally:
        if conn:
            conn.close()

    log.info("  Step 5 complete: %d rows verified (%.1fs)", rows_verified, time.time() - t0)
    return rows_verified


# ---------------------------------------------------------------------------
# STEP 6: SLOW QUERY COUNTS FROM CLOUDWATCH LOGS
# ---------------------------------------------------------------------------

def step_06_slow_query_counts(run_id: str, run_date: str, dry_run: bool = False) -> int:
    """Query CloudWatch Logs Insights for RDS slow query counts."""
    t0 = time.time()
    log.info("STEP 6: Collecting slow query counts from CloudWatch Logs ...")

    if not HAS_CLOUDWATCH:
        log.warning("  CloudWatch collector not available. Skipping.")
        return 0

    if os.getenv('ENABLE_SLOW_QUERY_ANALYSIS', 'true').lower() != 'true':
        log.info("  Slow query analysis disabled. Skipping.")
        return 0

    target_date = date.fromisoformat(run_date)
    rows = collect_slow_query_counts(target_date)
    log.info("  Collected %d slow query count rows", len(rows))

    if dry_run:
        log.info("  [DRY RUN] Would insert %d rows", len(rows))
        return len(rows)

    rows_affected = 0
    conn = None
    try:
        conn = get_connection('dbatest')
        rows_affected = cw_insert_metrics(conn, rows)
        duration = time.time() - t0
        log_step(conn, run_id, 6, 'slow_query_counts',
                 f'Collected {len(rows)} slow query counts, inserted {rows_affected}',
                 'SUCCESS', rows=rows_affected, duration=duration)
    except Exception as exc:
        duration = time.time() - t0
        log.error("  Step 6 failed: %s", exc)
        if conn:
            log_step(conn, run_id, 6, 'slow_query_counts',
                     'Slow query count collection failed', 'FAILED',
                     duration=duration, error=str(exc))
    finally:
        if conn:
            conn.close()

    log.info("  Step 6 complete: %d rows (%.1fs)", rows_affected, time.time() - t0)
    return rows_affected


# ---------------------------------------------------------------------------
# STEP 7: MCP DB GATEWAY MYSQL STATUS METRICS (placeholder)
# ---------------------------------------------------------------------------

def step_07_mysql_status_metrics(run_id: str, run_date: str, dry_run: bool = False) -> int:
    """Collect MySQL-specific metrics via MCP DB Gateway (SHOW STATUS).

    NOTE: This is a placeholder. In production, this would connect via the
    MCP DB Gateway to each MySQL/RDS instance and run SHOW GLOBAL STATUS
    to collect Threads_running, Slow_queries, Innodb_buffer_pool_read_requests, etc.
    """
    t0 = time.time()
    log.info("STEP 7: MySQL status metrics via MCP DB Gateway ...")
    log.info("  [PLACEHOLDER] MCP DB Gateway integration not yet implemented.")
    log.info("  Future: SHOW GLOBAL STATUS → Threads_running, Slow_queries, InnoDB pool stats")

    conn = None
    try:
        conn = get_connection('dbatest')
        duration = time.time() - t0
        log_step(conn, run_id, 7, 'mysql_status_metrics',
                 'Placeholder — MCP DB Gateway not yet integrated',
                 'SKIPPED', rows=0, duration=duration)
    finally:
        if conn:
            conn.close()

    log.info("  Step 7 complete (skipped, %.1fs)", time.time() - t0)
    return 0


# ---------------------------------------------------------------------------
# STEP 8: UPDATE FLEET INVENTORY FROM COLLECTED METRICS
# ---------------------------------------------------------------------------

def step_08_update_inventory(run_id: str, run_date: str, dry_run: bool = False) -> int:
    """Update infra_fleet_inventory with metadata from today's metric collection."""
    t0 = time.time()
    log.info("STEP 8: Updating fleet inventory from collected metrics ...")

    if dry_run:
        log.info("  [DRY RUN] Would update inventory")
        return 0

    rows_affected = 0
    conn = None
    try:
        conn = get_connection('dbatest')
        with conn.cursor() as cur:
            # Insert any newly-discovered resources from today's metrics
            cur.execute("""
                INSERT IGNORE INTO test.infra_fleet_inventory (
                    resource_type, resource_name, instance, job,
                    status, last_seen, created_at
                )
                SELECT DISTINCT
                    resource_type,
                    resource_name,
                    instance,
                    source AS job,
                    'up',
                    metric_date,
                    NOW()
                FROM test.infra_metric_daily
                WHERE metric_date = %s
            """, (run_date,))
            rows_affected = cur.rowcount

            # Update last_seen for all resources seen today
            cur.execute("""
                UPDATE test.infra_fleet_inventory fi
                INNER JOIN (
                    SELECT DISTINCT resource_type, resource_name
                    FROM test.infra_metric_daily
                    WHERE metric_date = %s
                ) m ON fi.resource_type = m.resource_type
                   AND fi.resource_name = m.resource_name
                SET fi.last_seen  = %s,
                    fi.status     = 'up',
                    fi.updated_at = NOW()
            """, (run_date, run_date))
            rows_affected += cur.rowcount

        conn.commit()
        duration = time.time() - t0
        log_step(conn, run_id, 8, 'update_inventory',
                 f'Updated {rows_affected} fleet inventory entries',
                 'SUCCESS', rows=rows_affected, duration=duration)

    except Exception as exc:
        duration = time.time() - t0
        log.error("  Step 8 failed: %s", exc)
        if conn:
            log_step(conn, run_id, 8, 'update_inventory',
                     'Fleet inventory update failed', 'FAILED',
                     duration=duration, error=str(exc))
    finally:
        if conn:
            conn.close()

    log.info("  Step 8 complete: %d rows (%.1fs)", rows_affected, time.time() - t0)
    return rows_affected


# ---------------------------------------------------------------------------
# STEP 9: SPC Z-SCORES (14-day rolling)
# ---------------------------------------------------------------------------

def step_09_anomaly_zscores(run_id: str, run_date: str, dry_run: bool = False) -> int:
    """Compute 14-day rolling Z-scores for all infrastructure metrics.

    For each (resource_type, resource_name, metric_name) triple:
        Z = (today_value - rolling_mean) / rolling_stddev

    INSERT INTO test.infra_anomaly_scores with ON DUPLICATE KEY UPDATE.
    """
    t0 = time.time()
    log.info("STEP 9: Computing %d-day rolling Z-scores ...", ROLLING_WINDOW)

    if dry_run:
        log.info("  [DRY RUN] Would compute Z-scores")
        return 0

    sql = f"""
        INSERT INTO test.infra_anomaly_scores (
            score_date, resource_type, resource_name, instance,
            metric_name, metric_value, rolling_mean, rolling_std,
            z_score, sigma_level,
            created_at
        )
        SELECT
            today.metric_date,
            today.resource_type,
            today.resource_name,
            today.instance,
            today.metric_name,
            today.metric_value,
            ROUND(baseline.avg_val, 6)  AS rolling_mean,
            ROUND(baseline.std_val, 6)  AS rolling_std,
            ROUND(
                (today.metric_value - baseline.avg_val)
                / NULLIF(baseline.std_val, 0)
            , 4)                         AS z_score,
            CASE
                WHEN ABS((today.metric_value - baseline.avg_val)
                     / NULLIF(baseline.std_val, 0)) >= {SIGMA_CRITICAL}
                THEN 'CRITICAL'
                WHEN ABS((today.metric_value - baseline.avg_val)
                     / NULLIF(baseline.std_val, 0)) >= {SIGMA_WARNING}
                THEN 'WARNING'
                ELSE 'NORMAL'
            END                          AS sigma_level,
            NOW()
        FROM test.infra_metric_daily today
        INNER JOIN (
            SELECT
                resource_type,
                resource_name,
                metric_name,
                AVG(metric_value)    AS avg_val,
                STDDEV(metric_value) AS std_val,
                COUNT(*)             AS sample_count
            FROM test.infra_metric_daily
            WHERE metric_date >= DATE_SUB(%s, INTERVAL {ROLLING_WINDOW} DAY)
              AND metric_date < %s
              AND metric_value IS NOT NULL
            GROUP BY resource_type, resource_name, metric_name
            HAVING COUNT(*) >= 3
        ) baseline
            ON  today.resource_type = baseline.resource_type
            AND today.resource_name = baseline.resource_name
            AND today.metric_name   = baseline.metric_name
        WHERE today.metric_date = %s
          AND today.metric_value IS NOT NULL
        ON DUPLICATE KEY UPDATE
            metric_value = VALUES(metric_value),
            rolling_mean = VALUES(rolling_mean),
            rolling_std  = VALUES(rolling_std),
            z_score      = VALUES(z_score),
            sigma_level  = VALUES(sigma_level),
            updated_at   = NOW()
    """

    rows_affected = 0
    conn = None
    try:
        conn = get_connection('dbatest')
        with conn.cursor() as cur:
            cur.execute(sql, (run_date, run_date, run_date))
            rows_affected = cur.rowcount
        conn.commit()
        log.info("  Upserted %d anomaly score rows", rows_affected)

        duration = time.time() - t0
        log_step(conn, run_id, 9, 'anomaly_zscores',
                 f'Computed Z-scores for {rows_affected} metric-resource pairs '
                 f'({ROLLING_WINDOW}-day rolling window)',
                 'SUCCESS', rows=rows_affected, duration=duration)

    except Exception as exc:
        duration = time.time() - t0
        log.error("  Step 9 failed: %s", exc)
        if conn:
            log_step(conn, run_id, 9, 'anomaly_zscores',
                     'Z-score computation failed', 'FAILED',
                     duration=duration, error=str(exc))
        raise
    finally:
        if conn:
            conn.close()

    log.info("  Step 9 complete: %d rows (%.1fs)", rows_affected, time.time() - t0)
    return rows_affected


# ---------------------------------------------------------------------------
# STEP 10: WESTERN ELECTRIC RULES
# ---------------------------------------------------------------------------

def step_10_western_electric(run_id: str, run_date: str, dry_run: bool = False) -> int:
    """Evaluate Western Electric rules using LAG() over recent anomaly scores.

    WE-1: 1 point beyond 3-sigma
    WE-2: 2 of 3 consecutive points beyond 2-sigma (same side)
    WE-3: 4 of 5 consecutive points beyond 1-sigma (same side)
    WE-4: 8 consecutive points on same side of centerline
    """
    t0 = time.time()
    log.info("STEP 10: Evaluating Western Electric rules ...")

    if dry_run:
        log.info("  [DRY RUN] Would evaluate WE rules")
        return 0

    # WE-1: already captured by sigma_level = 'CRITICAL' in step 9
    # WE-2 through WE-4 require looking back at prior days
    we_sql = f"""
        UPDATE test.infra_anomaly_scores curr
        INNER JOIN (
            SELECT
                a.score_date,
                a.resource_type,
                a.resource_name,
                a.metric_name,

                -- WE-1: current beyond 3-sigma (already in sigma_level)
                (ABS(a.z_score) >= {SIGMA_CRITICAL}) AS we1_flag,

                -- WE-2: 2 of last 3 beyond 2-sigma same side
                (
                    (SELECT COUNT(*)
                     FROM test.infra_anomaly_scores h
                     WHERE h.resource_type = a.resource_type
                       AND h.resource_name = a.resource_name
                       AND h.metric_name   = a.metric_name
                       AND h.score_date >= DATE_SUB(a.score_date, INTERVAL 2 DAY)
                       AND h.score_date <= a.score_date
                       AND h.z_score >= {SIGMA_WARNING}
                    ) >= 2
                    OR
                    (SELECT COUNT(*)
                     FROM test.infra_anomaly_scores h
                     WHERE h.resource_type = a.resource_type
                       AND h.resource_name = a.resource_name
                       AND h.metric_name   = a.metric_name
                       AND h.score_date >= DATE_SUB(a.score_date, INTERVAL 2 DAY)
                       AND h.score_date <= a.score_date
                       AND h.z_score <= -{SIGMA_WARNING}
                    ) >= 2
                ) AS we2_flag,

                -- WE-3: 4 of last 5 beyond 1-sigma same side
                (
                    (SELECT COUNT(*)
                     FROM test.infra_anomaly_scores h
                     WHERE h.resource_type = a.resource_type
                       AND h.resource_name = a.resource_name
                       AND h.metric_name   = a.metric_name
                       AND h.score_date >= DATE_SUB(a.score_date, INTERVAL 4 DAY)
                       AND h.score_date <= a.score_date
                       AND h.z_score >= 1
                    ) >= 4
                    OR
                    (SELECT COUNT(*)
                     FROM test.infra_anomaly_scores h
                     WHERE h.resource_type = a.resource_type
                       AND h.resource_name = a.resource_name
                       AND h.metric_name   = a.metric_name
                       AND h.score_date >= DATE_SUB(a.score_date, INTERVAL 4 DAY)
                       AND h.score_date <= a.score_date
                       AND h.z_score <= -1
                    ) >= 4
                ) AS we3_flag,

                -- WE-4: 8 consecutive on same side
                (
                    (SELECT COUNT(*)
                     FROM test.infra_anomaly_scores h
                     WHERE h.resource_type = a.resource_type
                       AND h.resource_name = a.resource_name
                       AND h.metric_name   = a.metric_name
                       AND h.score_date >= DATE_SUB(a.score_date, INTERVAL 7 DAY)
                       AND h.score_date <= a.score_date
                       AND h.z_score > 0
                    ) >= 8
                    OR
                    (SELECT COUNT(*)
                     FROM test.infra_anomaly_scores h
                     WHERE h.resource_type = a.resource_type
                       AND h.resource_name = a.resource_name
                       AND h.metric_name   = a.metric_name
                       AND h.score_date >= DATE_SUB(a.score_date, INTERVAL 7 DAY)
                       AND h.score_date <= a.score_date
                       AND h.z_score < 0
                    ) >= 8
                ) AS we4_flag

            FROM test.infra_anomaly_scores a
            WHERE a.score_date = %s
        ) flags
            ON  curr.score_date    = flags.score_date
            AND curr.resource_type = flags.resource_type
            AND curr.resource_name = flags.resource_name
            AND curr.metric_name   = flags.metric_name
        SET
            curr.we1_violation = flags.we1_flag,
            curr.we2_violation = flags.we2_flag,
            curr.we3_violation = flags.we3_flag,
            curr.we4_violation = flags.we4_flag,
            curr.updated_at    = NOW()
        WHERE curr.score_date = %s
    """

    rows_affected = 0
    conn = None
    try:
        conn = get_connection('dbatest')
        with conn.cursor() as cur:
            cur.execute(we_sql, (run_date, run_date))
            rows_affected = cur.rowcount
        conn.commit()
        log.info("  Evaluated WE rules for %d score rows", rows_affected)

        duration = time.time() - t0
        log_step(conn, run_id, 10, 'western_electric',
                 f'Evaluated WE-1 through WE-4 for {rows_affected} rows',
                 'SUCCESS', rows=rows_affected, duration=duration)

    except Exception as exc:
        duration = time.time() - t0
        log.error("  Step 10 failed: %s", exc)
        if conn:
            log_step(conn, run_id, 10, 'western_electric',
                     'Western Electric rule evaluation failed', 'FAILED',
                     duration=duration, error=str(exc))
    finally:
        if conn:
            conn.close()

    log.info("  Step 10 complete: %d rows (%.1fs)", rows_affected, time.time() - t0)
    return rows_affected


# ---------------------------------------------------------------------------
# STEP 11: RATE-OF-CHANGE FEATURES
# ---------------------------------------------------------------------------

def step_11_rate_of_change(run_id: str, run_date: str, dry_run: bool = False) -> int:
    """Compute day-over-day rate of change and update anomaly_scores.

    ROC = (today - yesterday) / yesterday * 100
    """
    t0 = time.time()
    log.info("STEP 11: Computing rate-of-change features ...")

    if dry_run:
        log.info("  [DRY RUN] Would compute ROC")
        return 0

    roc_sql = """
        UPDATE test.infra_anomaly_scores curr
        INNER JOIN test.infra_anomaly_scores prev
            ON  prev.resource_type = curr.resource_type
            AND prev.resource_name = curr.resource_name
            AND prev.metric_name   = curr.metric_name
            AND prev.score_date    = DATE_SUB(curr.score_date, INTERVAL 1 DAY)
        SET
            curr.prev_value     = prev.metric_value,
            curr.rate_of_change = CASE
                WHEN prev.metric_value IS NOT NULL AND prev.metric_value != 0
                THEN ROUND((curr.metric_value - prev.metric_value)
                           / ABS(prev.metric_value) * 100, 2)
                ELSE NULL
            END,
            curr.roc_alert = CASE
                WHEN prev.metric_value IS NOT NULL AND prev.metric_value != 0
                     AND ABS((curr.metric_value - prev.metric_value)
                             / ABS(prev.metric_value) * 100) >= 25
                THEN 1
                ELSE 0
            END,
            curr.updated_at = NOW()
        WHERE curr.score_date = %s
    """

    rows_affected = 0
    conn = None
    try:
        conn = get_connection('dbatest')
        with conn.cursor() as cur:
            cur.execute(roc_sql, (run_date,))
            rows_affected = cur.rowcount
        conn.commit()
        log.info("  Updated ROC for %d score rows", rows_affected)

        duration = time.time() - t0
        log_step(conn, run_id, 11, 'rate_of_change',
                 f'Computed rate-of-change for {rows_affected} rows',
                 'SUCCESS', rows=rows_affected, duration=duration)

    except Exception as exc:
        duration = time.time() - t0
        log.error("  Step 11 failed: %s", exc)
        if conn:
            log_step(conn, run_id, 11, 'rate_of_change',
                     'Rate-of-change computation failed', 'FAILED',
                     duration=duration, error=str(exc))
    finally:
        if conn:
            conn.close()

    log.info("  Step 11 complete: %d rows (%.1fs)", rows_affected, time.time() - t0)
    return rows_affected


# ---------------------------------------------------------------------------
# STEP 12: COMPOSITE HEALTH SCORES
# ---------------------------------------------------------------------------

def step_12_health_scores(run_id: str, run_date: str, dry_run: bool = False) -> int:
    """Compute composite health scores per resource.

    Health = 100 - SUM(category_weight * max(|Z| in category, 0))

    Scores clamped to [0, 100].  Lower = worse health.
    """
    t0 = time.time()
    log.info("STEP 12: Computing composite health scores ...")

    if dry_run:
        log.info("  [DRY RUN] Would compute health scores")
        return 0

    # Build the weighted penalty CASE expression
    category_cases = []
    for cat, weight in HEALTH_WEIGHTS.items():
        metrics_in_cat = [m for m, c in METRIC_CATEGORY_MAP.items() if c == cat]
        if not metrics_in_cat:
            continue
        placeholders = ','.join([f"'{m}'" for m in metrics_in_cat])
        category_cases.append(f"""
            {weight} * COALESCE(
                (SELECT MAX(ABS(s2.z_score))
                 FROM test.infra_anomaly_scores s2
                 WHERE s2.resource_type = s.resource_type
                   AND s2.resource_name = s.resource_name
                   AND s2.score_date    = s.score_date
                   AND s2.metric_name IN ({placeholders})
                ), 0)
        """)

    penalty_expr = ' + '.join(category_cases) if category_cases else '0'

    health_sql = f"""
        INSERT INTO test.infra_health_scores (
            score_date, resource_type, resource_name,
            health_score, penalty_total,
            anomaly_count_warning, anomaly_count_critical,
            we_violation_count,
            created_at
        )
        SELECT
            s.score_date,
            s.resource_type,
            s.resource_name,
            GREATEST(0, LEAST(100, ROUND(
                100 - ({penalty_expr}) * 10
            , 2)))                               AS health_score,
            ROUND({penalty_expr}, 4)             AS penalty_total,
            SUM(CASE WHEN s.sigma_level = 'WARNING'  THEN 1 ELSE 0 END) AS anomaly_count_warning,
            SUM(CASE WHEN s.sigma_level = 'CRITICAL' THEN 1 ELSE 0 END) AS anomaly_count_critical,
            SUM(COALESCE(s.we1_violation, 0) + COALESCE(s.we2_violation, 0)
              + COALESCE(s.we3_violation, 0) + COALESCE(s.we4_violation, 0)) AS we_violation_count,
            NOW()
        FROM test.infra_anomaly_scores s
        WHERE s.score_date = %s
        GROUP BY s.score_date, s.resource_type, s.resource_name
        ON DUPLICATE KEY UPDATE
            health_score          = VALUES(health_score),
            penalty_total         = VALUES(penalty_total),
            anomaly_count_warning = VALUES(anomaly_count_warning),
            anomaly_count_critical = VALUES(anomaly_count_critical),
            we_violation_count    = VALUES(we_violation_count),
            updated_at            = NOW()
    """

    rows_affected = 0
    conn = None
    try:
        conn = get_connection('dbatest')
        with conn.cursor() as cur:
            cur.execute(health_sql, (run_date,))
            rows_affected = cur.rowcount
        conn.commit()
        log.info("  Upserted %d health score rows", rows_affected)

        duration = time.time() - t0
        log_step(conn, run_id, 12, 'health_scores',
                 f'Computed health scores for {rows_affected} resources',
                 'SUCCESS', rows=rows_affected, duration=duration)

    except Exception as exc:
        duration = time.time() - t0
        log.error("  Step 12 failed: %s", exc)
        if conn:
            log_step(conn, run_id, 12, 'health_scores',
                     'Health score computation failed', 'FAILED',
                     duration=duration, error=str(exc))
    finally:
        if conn:
            conn.close()

    log.info("  Step 12 complete: %d rows (%.1fs)", rows_affected, time.time() - t0)
    return rows_affected


# ---------------------------------------------------------------------------
# STEP 13: TIERED ANOMALY ALERTS
# ---------------------------------------------------------------------------

def step_13_anomaly_alerts(run_id: str, run_date: str, dry_run: bool = False) -> int:
    """Generate tiered anomaly alerts with bilingual descriptions.

    Alert tiers:
        CRITICAL — |Z| >= 3 or WE-1 violation
        WARNING  — |Z| >= 2 or WE-2/WE-3 violation
        WATCH    — WE-4 violation or ROC > 25%
    """
    t0 = time.time()
    log.info("STEP 13: Generating tiered anomaly alerts ...")

    if dry_run:
        log.info("  [DRY RUN] Would generate alerts")
        return 0

    alert_sql = f"""
        INSERT INTO test.infra_anomaly_alerts (
            alert_date, resource_type, resource_name, instance,
            metric_name, metric_value, z_score,
            alert_tier, alert_rule,
            description_en, description_zh,
            created_at
        )
        SELECT
            s.score_date,
            s.resource_type,
            s.resource_name,
            s.instance,
            s.metric_name,
            s.metric_value,
            s.z_score,

            -- Alert tier
            CASE
                WHEN ABS(s.z_score) >= {SIGMA_CRITICAL} OR s.we1_violation = 1
                    THEN 'CRITICAL'
                WHEN ABS(s.z_score) >= {SIGMA_WARNING} OR s.we2_violation = 1 OR s.we3_violation = 1
                    THEN 'WARNING'
                WHEN s.we4_violation = 1 OR s.roc_alert = 1
                    THEN 'WATCH'
                ELSE NULL
            END AS alert_tier,

            -- Alert rule that triggered
            CASE
                WHEN ABS(s.z_score) >= {SIGMA_CRITICAL} THEN 'Z >= 3-sigma'
                WHEN s.we1_violation = 1                 THEN 'WE-1: beyond 3-sigma'
                WHEN s.we2_violation = 1                 THEN 'WE-2: 2/3 beyond 2-sigma'
                WHEN s.we3_violation = 1                 THEN 'WE-3: 4/5 beyond 1-sigma'
                WHEN ABS(s.z_score) >= {SIGMA_WARNING}   THEN 'Z >= 2-sigma'
                WHEN s.we4_violation = 1                 THEN 'WE-4: 8 same side'
                WHEN s.roc_alert = 1                     THEN 'ROC > 25% day-over-day'
                ELSE 'unknown'
            END AS alert_rule,

            -- English description
            CONCAT(
                UPPER(s.resource_type), ' ', s.resource_name,
                ' — ', s.metric_name,
                ': value=', ROUND(s.metric_value, 2),
                ', Z=', ROUND(s.z_score, 2),
                ' (mean=', ROUND(s.rolling_mean, 2),
                ', std=', ROUND(s.rolling_std, 2), ')'
            ) AS description_en,

            -- Chinese description
            CONCAT(
                CASE s.resource_type
                    WHEN 'redis' THEN 'Redis缓存'
                    WHEN 'rds'   THEN 'RDS数据库'
                    WHEN 'ec2'   THEN 'EC2服务器'
                    ELSE s.resource_type
                END,
                ' ', s.resource_name,
                ' — 指标 ', s.metric_name,
                ': 当前值=', ROUND(s.metric_value, 2),
                ', Z分数=', ROUND(s.z_score, 2),
                ' (均值=', ROUND(s.rolling_mean, 2),
                ', 标准差=', ROUND(s.rolling_std, 2), ')'
            ) AS description_zh,

            NOW()

        FROM test.infra_anomaly_scores s
        WHERE s.score_date = %s
          AND (
              ABS(s.z_score) >= {SIGMA_WARNING}
              OR s.we1_violation = 1
              OR s.we2_violation = 1
              OR s.we3_violation = 1
              OR s.we4_violation = 1
              OR s.roc_alert = 1
          )
        ON DUPLICATE KEY UPDATE
            metric_value    = VALUES(metric_value),
            z_score         = VALUES(z_score),
            alert_tier      = VALUES(alert_tier),
            alert_rule      = VALUES(alert_rule),
            description_en  = VALUES(description_en),
            description_zh  = VALUES(description_zh),
            updated_at      = NOW()
    """

    rows_affected = 0
    conn = None
    try:
        conn = get_connection('dbatest')
        with conn.cursor() as cur:
            cur.execute(alert_sql, (run_date,))
            rows_affected = cur.rowcount
        conn.commit()
        log.info("  Generated %d anomaly alerts", rows_affected)

        # Log alert tier breakdown
        with conn.cursor() as cur:
            cur.execute("""
                SELECT alert_tier, COUNT(*)
                FROM test.infra_anomaly_alerts
                WHERE alert_date = %s
                GROUP BY alert_tier
            """, (run_date,))
            tier_counts = dict(cur.fetchall())
        log.info("  Alert breakdown: %s", json.dumps(tier_counts, default=str))

        duration = time.time() - t0
        log_step(conn, run_id, 13, 'anomaly_alerts',
                 f'Generated {rows_affected} alerts: {json.dumps(tier_counts, default=str)}',
                 'SUCCESS', rows=rows_affected, duration=duration)

    except Exception as exc:
        duration = time.time() - t0
        log.error("  Step 13 failed: %s", exc)
        if conn:
            log_step(conn, run_id, 13, 'anomaly_alerts',
                     'Alert generation failed', 'FAILED',
                     duration=duration, error=str(exc))
    finally:
        if conn:
            conn.close()

    log.info("  Step 13 complete: %d alerts (%.1fs)", rows_affected, time.time() - t0)
    return rows_affected


# ---------------------------------------------------------------------------
# STEP 14: PIPELINE COMPLETION LOG
# ---------------------------------------------------------------------------

def step_14_log_completion(run_id: str, run_date: str, total_duration: float,
                           step_results: Dict[int, int]) -> int:
    """Log pipeline completion with summary statistics."""
    t0 = time.time()
    log.info("STEP 14: Logging pipeline completion ...")

    conn = None
    try:
        conn = get_connection('dbatest')

        # Summary counts
        total_rows = sum(step_results.values())
        steps_run = len(step_results)

        # Count today's data
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    (SELECT COUNT(*) FROM test.infra_metric_daily
                     WHERE metric_date = %s) AS metric_rows,
                    (SELECT COUNT(*) FROM test.infra_anomaly_scores
                     WHERE score_date = %s) AS score_rows,
                    (SELECT COUNT(*) FROM test.infra_health_scores
                     WHERE score_date = %s) AS health_rows,
                    (SELECT COUNT(*) FROM test.infra_anomaly_alerts
                     WHERE alert_date = %s) AS alert_rows
            """, (run_date, run_date, run_date, run_date))
            counts = cur.fetchone()

        summary = {
            'run_id':          run_id,
            'run_date':        run_date,
            'steps_executed':  steps_run,
            'total_rows':      total_rows,
            'duration_sec':    round(total_duration, 2),
            'metric_rows':     counts[0] if counts else 0,
            'score_rows':      counts[1] if counts else 0,
            'health_rows':     counts[2] if counts else 0,
            'alert_rows':      counts[3] if counts else 0,
        }

        duration = time.time() - t0
        log_step(conn, run_id, 14, 'pipeline_complete',
                 json.dumps(summary, default=str),
                 'SUCCESS', rows=total_rows, duration=total_duration)

        # Clean old pipeline logs
        retention_days = int(os.getenv('PIPELINE_LOG_RETENTION_DAYS', '90'))
        with conn.cursor() as cur:
            cur.execute("""
                DELETE FROM test.infra_monitoring_pipeline_log
                WHERE created_at < DATE_SUB(NOW(), INTERVAL %s DAY)
            """, (retention_days,))
            purged = cur.rowcount
        conn.commit()

        if purged:
            log.info("  Purged %d old pipeline log entries (>%d days)",
                     purged, retention_days)

        log.info("  Pipeline summary: %s", json.dumps(summary, indent=2, default=str))

    except Exception as exc:
        log.error("  Step 14 failed: %s", exc)
    finally:
        if conn:
            conn.close()

    log.info("  Step 14 complete (%.1fs)", time.time() - t0)
    return 0


# ---------------------------------------------------------------------------
# PIPELINE ORCHESTRATOR
# ---------------------------------------------------------------------------

def run_pipeline(target_date: date, steps: Optional[Set[int]] = None,
                 dry_run: bool = False, skip_cw: bool = False,
                 skip_prom: bool = False) -> Dict[str, any]:
    """Orchestrate the full 14-step pipeline.

    Args:
        target_date: The date to process.
        steps:       If set, only run these step numbers. None = run all.
        dry_run:     If True, validate but do not write to DB.
        skip_cw:     If True, skip CloudWatch steps (4, 5, 6).
        skip_prom:   If True, skip Prometheus steps (1, 2, 3).

    Returns:
        dict with run_id, step_results, duration, status.
    """
    run_id = str(uuid.uuid4())[:8]
    run_date = target_date.isoformat()
    pipeline_start = time.time()

    log.info("=" * 70)
    log.info("UC-IT-01 Pipeline — run_id=%s  date=%s", run_id, run_date)
    log.info("  dry_run=%s  skip_cw=%s  skip_prom=%s  steps=%s",
             dry_run, skip_cw, skip_prom, steps or 'ALL')
    log.info("=" * 70)

    # Define all steps
    step_funcs = {
        1:  ('fleet_inventory',       step_01_fleet_inventory),
        2:  ('redis_instant_metrics', step_02_redis_instant_metrics),
        3:  ('redis_rate_metrics',    step_03_redis_rate_metrics),
        4:  ('rds_core_metrics',      step_04_rds_core_metrics),
        5:  ('rds_latency_iops',      step_05_rds_latency_iops),
        6:  ('slow_query_counts',     step_06_slow_query_counts),
        7:  ('mysql_status_metrics',  step_07_mysql_status_metrics),
        8:  ('update_inventory',      step_08_update_inventory),
        9:  ('anomaly_zscores',       step_09_anomaly_zscores),
        10: ('western_electric',      step_10_western_electric),
        11: ('rate_of_change',        step_11_rate_of_change),
        12: ('health_scores',         step_12_health_scores),
        13: ('anomaly_alerts',        step_13_anomaly_alerts),
    }

    # Filter steps
    skip_steps: Set[int] = set()
    if skip_prom:
        skip_steps.update({1, 2, 3})
    if skip_cw:
        skip_steps.update({4, 5, 6})

    step_results: Dict[int, int] = {}
    pipeline_status = 'SUCCESS'

    for step_num in sorted(step_funcs.keys()):
        step_name, step_func = step_funcs[step_num]

        # Check if step should run
        if steps and step_num not in steps:
            log.info("  [SKIP] Step %d (%s) — not in --steps list", step_num, step_name)
            continue
        if step_num in skip_steps:
            log.info("  [SKIP] Step %d (%s) — skipped by flag", step_num, step_name)
            continue

        try:
            result = step_func(run_id, run_date, dry_run)
            step_results[step_num] = result
        except Exception as exc:
            log.error("STEP %d (%s) FAILED: %s", step_num, step_name, exc)
            step_results[step_num] = -1
            pipeline_status = 'PARTIAL_FAILURE'
            # Continue to next step — do not abort pipeline

    # Step 14 always runs
    total_duration = time.time() - pipeline_start
    step_14_log_completion(run_id, run_date, total_duration, step_results)

    log.info("=" * 70)
    log.info("Pipeline complete — %s (%.1fs)", pipeline_status, total_duration)
    log.info("  Results: %s", json.dumps(step_results, default=str))
    log.info("=" * 70)

    return {
        'run_id':       run_id,
        'run_date':     run_date,
        'status':       pipeline_status,
        'duration_sec': round(total_duration, 2),
        'step_results': step_results,
    }


# ---------------------------------------------------------------------------
# CLI ENTRYPOINT
# ---------------------------------------------------------------------------

def main():
    """Parse arguments and orchestrate the pipeline."""
    parser = argparse.ArgumentParser(
        description='UC-IT-01: Predictive Infrastructure Monitoring — Pipeline Orchestrator',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python run_pipeline.py                         # Full daily run (yesterday)
  python run_pipeline.py --date 2026-02-14       # Specific date
  python run_pipeline.py --backfill 14           # Last 14 days
  python run_pipeline.py --steps 1,2,3           # Specific steps only
  python run_pipeline.py --dry-run               # Validate without writes
  python run_pipeline.py --skip-cloudwatch       # Skip CW (saves API costs)
        """,
    )
    parser.add_argument(
        '--date', type=str, default=None,
        help='Target date YYYY-MM-DD (default: yesterday)',
    )
    parser.add_argument(
        '--backfill', type=int, default=None,
        help='Backfill N days ending yesterday',
    )
    parser.add_argument(
        '--steps', type=str, default=None,
        help='Comma-separated step numbers to run (e.g., "1,2,3,9,10")',
    )
    parser.add_argument(
        '--dry-run', action='store_true',
        help='Validate without writing to database',
    )
    parser.add_argument(
        '--skip-cloudwatch', action='store_true',
        help='Skip CloudWatch steps 4-6 (saves API costs)',
    )
    parser.add_argument(
        '--skip-prometheus', action='store_true',
        help='Skip Prometheus steps 1-3',
    )
    args = parser.parse_args()

    # Parse --steps
    step_set = None
    if args.steps:
        try:
            step_set = set(int(s.strip()) for s in args.steps.split(','))
            log.info("Running specific steps: %s", sorted(step_set))
        except ValueError:
            log.error("Invalid --steps format. Use comma-separated integers: --steps 1,2,3")
            return 1

    # Check skip flags from env + CLI
    skip_cw = args.skip_cloudwatch or os.getenv('SKIP_CLOUDWATCH', 'false').lower() == 'true'
    skip_prom = args.skip_prometheus or os.getenv('SKIP_PROMETHEUS', 'false').lower() == 'true'
    dry_run = args.dry_run or os.getenv('DRY_RUN', 'false').lower() == 'true'

    if args.backfill:
        end_date = date.today() - timedelta(days=1)
        start_date = end_date - timedelta(days=args.backfill - 1)
        log.info("Backfill mode: %s to %s (%d days)",
                 start_date, end_date, args.backfill)

        all_results = []
        current = start_date
        while current <= end_date:
            try:
                result = run_pipeline(
                    current,
                    steps=step_set,
                    dry_run=dry_run,
                    skip_cw=skip_cw,
                    skip_prom=skip_prom,
                )
                all_results.append(result)
            except Exception as exc:
                log.error("Pipeline failed for %s: %s", current, exc)
                all_results.append({'run_date': current.isoformat(), 'status': 'FAILED'})
            current += timedelta(days=1)

        # Summary
        success = sum(1 for r in all_results if r.get('status') == 'SUCCESS')
        log.info("Backfill complete: %d/%d days succeeded", success, len(all_results))

    else:
        target = date.fromisoformat(args.date) if args.date else date.today() - timedelta(days=1)
        result = run_pipeline(
            target,
            steps=step_set,
            dry_run=dry_run,
            skip_cw=skip_cw,
            skip_prom=skip_prom,
        )
        if result.get('status') == 'FAILED':
            return 1

    return 0


if __name__ == '__main__':
    sys.exit(main())

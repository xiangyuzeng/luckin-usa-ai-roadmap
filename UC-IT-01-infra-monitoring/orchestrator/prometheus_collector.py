#!/usr/bin/env python3
"""
UC-IT-01: Predictive Infrastructure Monitoring
Prometheus Collector — Redis Metrics Bridge
预测性基础设施监控 — Prometheus 采集器

Queries Prometheus HTTP API for Redis metrics and inserts daily aggregates
into the test.infra_metric_daily table on dbatest.

Architecture:
    Prometheus (http://localhost:9090) → PromQL API → Python → MySQL (dbatest)

Metrics Collected (10 per instance × 76 instances):
    1. redis_memory_used_bytes       — Memory utilization
    2. redis_memory_max_bytes        — Memory capacity
    3. redis_connected_clients       — Client connections
    4. redis_blocked_clients         — Blocked operations
    5. redis_commands_processed_total — Operations per second (rate)
    6. redis_cpu_sys_seconds_total   — System CPU (rate)
    7. redis_cpu_user_seconds_total  — User CPU (rate)
    8. redis_keyspace_hits_total     — Cache hit count
    9. redis_keyspace_misses_total   — Cache miss count
    10. redis_evicted_keys_total     — Eviction pressure

Usage:
    python prometheus_collector.py                    # Collect today
    python prometheus_collector.py --date 2026-02-14  # Specific date
    python prometheus_collector.py --backfill 14      # Last 14 days

Author: Data Engineering / BI Team
Created: 2026-02-15
"""

import os
import sys
import logging
import argparse
import json
import time
import re
from datetime import datetime, date, timedelta
from typing import Dict, List, Optional, Tuple, Any
from urllib.parse import urlparse

import requests
import pymysql
import pymysql.cursors
from dotenv import load_dotenv

# Load .env from same directory as this script
_env_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.env')
if os.path.exists(_env_path):
    load_dotenv(_env_path)

logging.basicConfig(
    level=getattr(logging, os.getenv('LOG_LEVEL', 'INFO')),
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
)
log = logging.getLogger('uc-it-01-prometheus')

# ---------------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------------

PROMETHEUS_URL = os.getenv('PROMETHEUS_URL', 'http://localhost:9090')
BATCH_SIZE = int(os.getenv('BATCH_SIZE', '500'))

# Gauge metrics — queried as instant values at end-of-day
INSTANT_METRICS = {
    'memory_used_bytes':       'redis_memory_used_bytes',
    'memory_max_bytes':        'redis_memory_max_bytes',
    'connected_clients':       'redis_connected_clients',
    'blocked_clients':         'redis_blocked_clients',
    'mem_fragmentation_ratio': 'redis_mem_fragmentation_ratio',
    'connected_slaves':        'redis_connected_slaves',
}

# Counter metrics — queried as rate() over the target day
RATE_METRICS = {
    'commands_per_sec':           'rate(redis_commands_processed_total[1d])',
    'cpu_sys_rate':               'rate(redis_cpu_sys_seconds_total[1d])',
    'cpu_user_rate':              'rate(redis_cpu_user_seconds_total[1d])',
    'keyspace_hits_rate':         'rate(redis_keyspace_hits_total[1d])',
    'keyspace_misses_rate':       'rate(redis_keyspace_misses_total[1d])',
    'evicted_keys_rate':          'rate(redis_evicted_keys_total[1d])',
    'rejected_connections_rate':  'rate(redis_rejected_connections_total[1d])',
    'net_input_bytes_rate':       'rate(redis_net_input_bytes_total[1d])',
    'net_output_bytes_rate':      'rate(redis_net_output_bytes_total[1d])',
}


# ---------------------------------------------------------------------------
# PROMETHEUS CLIENT
# ---------------------------------------------------------------------------

class PrometheusClient:
    """Thin wrapper around the Prometheus HTTP API (v1)."""

    def __init__(self, base_url: str = PROMETHEUS_URL, timeout: int = 60):
        self.base_url = base_url.rstrip('/')
        self.timeout = timeout
        self.session = requests.Session()
        self.session.headers.update({'Accept': 'application/json'})

    # -- Core API methods ---------------------------------------------------

    def query(self, promql: str, time_str: Optional[str] = None) -> List[Dict]:
        """Execute an instant query.  Returns list of {metric, value} dicts."""
        params: Dict[str, str] = {'query': promql}
        if time_str:
            params['time'] = time_str

        url = f'{self.base_url}/api/v1/query'
        resp = self.session.get(url, params=params, timeout=self.timeout)
        resp.raise_for_status()
        body = resp.json()

        if body.get('status') != 'success':
            raise RuntimeError(f"Prometheus query failed: {body.get('error', 'unknown')}")

        return body.get('data', {}).get('result', [])

    def query_range(self, promql: str, start: str, end: str,
                    step: str = '1h') -> List[Dict]:
        """Execute a range query.  Returns list of {metric, values} dicts."""
        params = {
            'query': promql,
            'start': start,
            'end':   end,
            'step':  step,
        }
        url = f'{self.base_url}/api/v1/query_range'
        resp = self.session.get(url, params=params, timeout=self.timeout)
        resp.raise_for_status()
        body = resp.json()

        if body.get('status') != 'success':
            raise RuntimeError(f"Prometheus range query failed: {body.get('error', 'unknown')}")

        return body.get('data', {}).get('result', [])

    def get_targets(self) -> List[Dict]:
        """List all scrape targets (active + dropped)."""
        url = f'{self.base_url}/api/v1/targets'
        resp = self.session.get(url, timeout=self.timeout)
        resp.raise_for_status()
        body = resp.json()

        if body.get('status') != 'success':
            raise RuntimeError(f"Failed to list targets: {body.get('error', 'unknown')}")

        active = body.get('data', {}).get('activeTargets', [])
        return active

    def health_check(self) -> bool:
        """Return True if Prometheus is reachable."""
        try:
            resp = self.session.get(
                f'{self.base_url}/-/healthy', timeout=10
            )
            return resp.status_code == 200
        except Exception:
            return False


# ---------------------------------------------------------------------------
# UTILITY FUNCTIONS
# ---------------------------------------------------------------------------

def parse_instance_name(instance_url: str) -> str:
    """Extract a short service name from a Redis connection URL.

    Examples:
        "rediss://master.luckyus-isales-market.vyllrs.use1.cache.amazonaws.com:6379"
            -> "isales-market"
        "rediss://master.luckyus-user-center.abc123.use1.cache.amazonaws.com:6379"
            -> "user-center"
        "10.0.1.5:6379" -> "10.0.1.5"
    """
    # Try to extract from ElastiCache-style DNS
    match = re.search(r'master\.luckyus-([a-z0-9-]+)\.', instance_url)
    if match:
        return match.group(1)

    # Try generic replication group name
    match = re.search(r'master\.([a-z0-9-]+)\.', instance_url)
    if match:
        return match.group(1)

    # Fallback: use the hostname part
    try:
        parsed = urlparse(instance_url)
        host = parsed.hostname or instance_url.split(':')[0]
        return host.split('.')[0]
    except Exception:
        return instance_url[:60]


def get_connection() -> pymysql.Connection:
    """Create a PyMySQL connection to dbatest using environment variables."""
    host = os.environ.get('DBATEST_HOST')
    port = int(os.environ.get('DBATEST_PORT', '3306'))
    user = os.environ.get('DBATEST_USER')
    password = os.environ.get('DBATEST_PASS')
    database = os.environ.get('DBATEST_DB', 'test')

    if not all([host, user, password]):
        raise ValueError(
            "Missing database config. "
            "Set DBATEST_HOST, DBATEST_USER, DBATEST_PASS"
        )

    log.debug("Connecting to dbatest @ %s:%d/%s", host, port, database)
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
# METRIC COLLECTION
# ---------------------------------------------------------------------------

def collect_instant_metrics(prom: PrometheusClient,
                            target_date: date) -> List[Dict]:
    """Collect gauge metrics via instant query at end-of-day.

    Returns a list of row dicts ready for INSERT:
        {metric_date, resource_type, resource_name, instance, metric_name, metric_value}
    """
    # Query at 23:59:59 of target_date
    query_time = datetime.combine(target_date, datetime.max.time())
    time_str = query_time.strftime('%Y-%m-%dT%H:%M:%SZ')

    rows: List[Dict] = []
    for metric_key, promql in INSTANT_METRICS.items():
        log.info("  Querying instant metric: %s", metric_key)
        try:
            results = prom.query(promql, time_str=time_str)
            for r in results:
                labels = r.get('metric', {})
                ts, value_str = r.get('value', [0, '0'])
                value = float(value_str) if value_str != 'NaN' else None

                instance = labels.get('addr', labels.get('instance', 'unknown'))
                resource_name = parse_instance_name(instance)

                rows.append({
                    'metric_date':   target_date.isoformat(),
                    'resource_type': 'redis',
                    'resource_name': resource_name,
                    'instance':      instance[:255],
                    'metric_name':   metric_key,
                    'metric_value':  value,
                    'metric_unit':   'gauge',
                    'source':        'prometheus',
                })
            log.info("    -> %d series returned", len(results))

        except Exception as exc:
            log.error("  Failed to query %s: %s", metric_key, exc)

    return rows


def collect_rate_metrics(prom: PrometheusClient,
                         target_date: date) -> List[Dict]:
    """Collect counter metrics via rate() at end-of-day.

    Returns row dicts in the same format as collect_instant_metrics.
    """
    query_time = datetime.combine(target_date, datetime.max.time())
    time_str = query_time.strftime('%Y-%m-%dT%H:%M:%SZ')

    rows: List[Dict] = []
    for metric_key, promql in RATE_METRICS.items():
        log.info("  Querying rate metric: %s", metric_key)
        try:
            results = prom.query(promql, time_str=time_str)
            for r in results:
                labels = r.get('metric', {})
                ts, value_str = r.get('value', [0, '0'])
                value = float(value_str) if value_str != 'NaN' else None

                instance = labels.get('addr', labels.get('instance', 'unknown'))
                resource_name = parse_instance_name(instance)

                rows.append({
                    'metric_date':   target_date.isoformat(),
                    'resource_type': 'redis',
                    'resource_name': resource_name,
                    'instance':      instance[:255],
                    'metric_name':   metric_key,
                    'metric_value':  value,
                    'metric_unit':   'rate_per_sec',
                    'source':        'prometheus',
                })
            log.info("    -> %d series returned", len(results))

        except Exception as exc:
            log.error("  Failed to query %s: %s", metric_key, exc)

    return rows


def compute_derived_metrics(rows: List[Dict]) -> List[Dict]:
    """Compute derived metrics from collected raw metrics.

    Derived metrics:
        - memory_utilization_pct = memory_used_bytes / memory_max_bytes * 100
        - cache_hit_rate_pct     = hits_rate / (hits_rate + misses_rate) * 100
        - total_cpu_rate         = cpu_sys_rate + cpu_user_rate

    Returns additional row dicts for the derived metrics.
    """
    # Index rows by (resource_name, metric_name) for quick lookup
    index: Dict[Tuple[str, str], Dict] = {}
    for row in rows:
        key = (row['resource_name'], row['metric_name'])
        index[key] = row

    derived: List[Dict] = []

    # Find all unique resource names
    resource_names = set(r['resource_name'] for r in rows)

    for rn in resource_names:
        # -- Memory utilization --
        used = index.get((rn, 'memory_used_bytes'))
        maxb = index.get((rn, 'memory_max_bytes'))
        if used and maxb and used['metric_value'] and maxb['metric_value']:
            max_val = maxb['metric_value']
            if max_val > 0:
                pct = round(used['metric_value'] / max_val * 100, 2)
                derived.append({
                    'metric_date':   used['metric_date'],
                    'resource_type': 'redis',
                    'resource_name': rn,
                    'instance':      used['instance'],
                    'metric_name':   'memory_utilization_pct',
                    'metric_value':  pct,
                    'metric_unit':   'percent',
                    'source':        'prometheus_derived',
                })

        # -- Cache hit rate --
        hits = index.get((rn, 'keyspace_hits_rate'))
        miss = index.get((rn, 'keyspace_misses_rate'))
        if hits and miss and hits['metric_value'] is not None and miss['metric_value'] is not None:
            total = hits['metric_value'] + miss['metric_value']
            if total > 0:
                hit_pct = round(hits['metric_value'] / total * 100, 2)
                derived.append({
                    'metric_date':   hits['metric_date'],
                    'resource_type': 'redis',
                    'resource_name': rn,
                    'instance':      hits['instance'],
                    'metric_name':   'cache_hit_rate_pct',
                    'metric_value':  hit_pct,
                    'metric_unit':   'percent',
                    'source':        'prometheus_derived',
                })

        # -- Total CPU rate --
        sys_cpu = index.get((rn, 'cpu_sys_rate'))
        usr_cpu = index.get((rn, 'cpu_user_rate'))
        if sys_cpu and usr_cpu and sys_cpu['metric_value'] is not None and usr_cpu['metric_value'] is not None:
            total_cpu = round(sys_cpu['metric_value'] + usr_cpu['metric_value'], 6)
            derived.append({
                'metric_date':   sys_cpu['metric_date'],
                'resource_type': 'redis',
                'resource_name': rn,
                'instance':      sys_cpu['instance'],
                'metric_name':   'total_cpu_rate',
                'metric_value':  total_cpu,
                'metric_unit':   'rate_per_sec',
                'source':        'prometheus_derived',
            })

    log.info("  Computed %d derived metrics for %d resources",
             len(derived), len(resource_names))
    return derived


# ---------------------------------------------------------------------------
# DATABASE INSERTION
# ---------------------------------------------------------------------------

def insert_metrics(conn: pymysql.Connection, rows: List[Dict]) -> int:
    """Batch INSERT rows into test.infra_metric_daily with ON DUPLICATE KEY UPDATE.

    Returns the number of rows affected.
    """
    if not rows:
        return 0

    sql = """
        INSERT INTO test.infra_metric_daily (
            metric_date, resource_type, resource_name, instance,
            metric_name, metric_value, metric_unit, source,
            created_at
        ) VALUES (
            %s, %s, %s, %s,
            %s, %s, %s, %s,
            NOW()
        )
        ON DUPLICATE KEY UPDATE
            metric_value = VALUES(metric_value),
            metric_unit  = VALUES(metric_unit),
            source       = VALUES(source),
            updated_at   = NOW()
    """

    total = 0
    with conn.cursor() as cur:
        batch = []
        for row in rows:
            batch.append((
                row['metric_date'],
                row['resource_type'],
                row['resource_name'],
                row['instance'],
                row['metric_name'],
                row['metric_value'],
                row['metric_unit'],
                row['source'],
            ))

            if len(batch) >= BATCH_SIZE:
                cur.executemany(sql, batch)
                total += cur.rowcount
                batch = []

        # Flush remaining
        if batch:
            cur.executemany(sql, batch)
            total += cur.rowcount

    conn.commit()
    return total


# ---------------------------------------------------------------------------
# MAIN COLLECTION FUNCTION
# ---------------------------------------------------------------------------

def collect_all(target_date: date) -> Dict[str, int]:
    """Run the full Prometheus collection pipeline for a single date.

    Returns a stats dict: {instant, rate, derived, total_inserted}
    """
    log.info("=" * 60)
    log.info("Prometheus collection for %s", target_date.isoformat())
    log.info("=" * 60)

    prom = PrometheusClient()

    # Health check
    if not prom.health_check():
        log.error("Prometheus at %s is unreachable. Aborting.", PROMETHEUS_URL)
        return {'instant': 0, 'rate': 0, 'derived': 0, 'total_inserted': 0}

    # Verify targets
    targets = prom.get_targets()
    redis_targets = [t for t in targets if 'redis' in t.get('labels', {}).get('job', '').lower()]
    log.info("Prometheus is healthy. %d active targets (%d Redis).",
             len(targets), len(redis_targets))

    # Step 1: Instant (gauge) metrics
    log.info("--- Collecting instant (gauge) metrics ---")
    instant_rows = collect_instant_metrics(prom, target_date)
    log.info("  Total instant rows: %d", len(instant_rows))

    # Step 2: Rate (counter) metrics
    log.info("--- Collecting rate (counter) metrics ---")
    rate_rows = collect_rate_metrics(prom, target_date)
    log.info("  Total rate rows: %d", len(rate_rows))

    # Step 3: Derived metrics
    log.info("--- Computing derived metrics ---")
    all_raw = instant_rows + rate_rows
    derived_rows = compute_derived_metrics(all_raw)

    # Step 4: Insert all into MySQL
    all_rows = all_raw + derived_rows
    log.info("--- Inserting %d rows into infra_metric_daily ---", len(all_rows))

    total_inserted = 0
    conn = None
    try:
        conn = get_connection()
        total_inserted = insert_metrics(conn, all_rows)
        log.info("  Rows affected: %d", total_inserted)
    except Exception as exc:
        log.error("Database insert failed: %s", exc)
        raise
    finally:
        if conn:
            conn.close()

    stats = {
        'instant':        len(instant_rows),
        'rate':           len(rate_rows),
        'derived':        len(derived_rows),
        'total_inserted': total_inserted,
    }
    log.info("Collection complete: %s", json.dumps(stats))
    return stats


# ---------------------------------------------------------------------------
# CLI ENTRYPOINT
# ---------------------------------------------------------------------------

def main():
    """Parse arguments and run collection."""
    parser = argparse.ArgumentParser(
        description='UC-IT-01: Prometheus Redis Metrics Collector',
    )
    parser.add_argument(
        '--date', type=str, default=None,
        help='Target date in YYYY-MM-DD format (default: yesterday)',
    )
    parser.add_argument(
        '--backfill', type=int, default=None,
        help='Backfill N days ending yesterday',
    )
    args = parser.parse_args()

    if args.backfill:
        end_date = date.today() - timedelta(days=1)
        start_date = end_date - timedelta(days=args.backfill - 1)
        log.info("Backfill mode: %s to %s (%d days)",
                 start_date, end_date, args.backfill)

        total_stats = {'instant': 0, 'rate': 0, 'derived': 0, 'total_inserted': 0}
        current = start_date
        while current <= end_date:
            try:
                stats = collect_all(current)
                for k in total_stats:
                    total_stats[k] += stats.get(k, 0)
            except Exception as exc:
                log.error("Failed for %s: %s", current, exc)
            current += timedelta(days=1)

        log.info("Backfill complete: %s", json.dumps(total_stats))

    else:
        target = date.fromisoformat(args.date) if args.date else date.today() - timedelta(days=1)
        stats = collect_all(target)
        log.info("Done: %s", json.dumps(stats))

    return 0


if __name__ == '__main__':
    sys.exit(main())

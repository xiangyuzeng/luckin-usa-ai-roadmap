#!/usr/bin/env python3
"""
UC-IT-01: Predictive Infrastructure Monitoring
CloudWatch Collector — RDS/EC2 Metrics Bridge
预测性基础设施监控 — CloudWatch 采集器

Queries AWS CloudWatch API for RDS and EC2 metrics and inserts daily aggregates
into the test.infra_metric_daily table on dbatest.

Architecture:
    CloudWatch API → boto3 → Python → MySQL (dbatest)

Metrics Collected:
    RDS (14 metrics × 62 instances):
        CPUUtilization, FreeableMemory, DatabaseConnections,
        ReadLatency, WriteLatency, ReadIOPS, WriteIOPS,
        NetworkReceiveThroughput, NetworkTransmitThroughput,
        ReplicaLag, DiskQueueDepth, FreeStorageSpace,
        SwapUsage, BinLogDiskUsage

    EC2 (future — placeholder for when node_exporter is deployed)

Usage:
    python cloudwatch_collector.py                    # Collect yesterday
    python cloudwatch_collector.py --date 2026-02-14  # Specific date
    python cloudwatch_collector.py --backfill 14      # Last 14 days

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
from typing import Dict, List, Optional, Any

import boto3
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
log = logging.getLogger('uc-it-01-cloudwatch')

# ---------------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------------

AWS_REGION = os.getenv('AWS_REGION', 'us-east-1')
BATCH_SIZE = int(os.getenv('BATCH_SIZE', '500'))

# RDS metrics to collect — each with name, unit label, and CloudWatch statistic
RDS_METRICS = [
    {'name': 'CPUUtilization',              'unit': 'percent',       'stat': 'Average'},
    {'name': 'FreeableMemory',              'unit': 'bytes',         'stat': 'Average'},
    {'name': 'DatabaseConnections',         'unit': 'count',         'stat': 'Average'},
    {'name': 'ReadLatency',                 'unit': 'seconds',       'stat': 'Average'},
    {'name': 'WriteLatency',                'unit': 'seconds',       'stat': 'Average'},
    {'name': 'ReadIOPS',                    'unit': 'count_per_sec', 'stat': 'Average'},
    {'name': 'WriteIOPS',                   'unit': 'count_per_sec', 'stat': 'Average'},
    {'name': 'NetworkReceiveThroughput',    'unit': 'bytes_per_sec', 'stat': 'Average'},
    {'name': 'NetworkTransmitThroughput',   'unit': 'bytes_per_sec', 'stat': 'Average'},
    {'name': 'ReplicaLag',                  'unit': 'seconds',       'stat': 'Average'},
    {'name': 'DiskQueueDepth',              'unit': 'count',         'stat': 'Average'},
    {'name': 'FreeStorageSpace',            'unit': 'bytes',         'stat': 'Average'},
    {'name': 'SwapUsage',                   'unit': 'bytes',         'stat': 'Average'},
    {'name': 'BinLogDiskUsage',             'unit': 'bytes',         'stat': 'Average'},
]

# EC2 metrics — placeholder for future implementation
EC2_METRICS = [
    {'name': 'CPUUtilization',              'unit': 'percent',       'stat': 'Average'},
    {'name': 'NetworkIn',                   'unit': 'bytes',         'stat': 'Sum'},
    {'name': 'NetworkOut',                  'unit': 'bytes',         'stat': 'Sum'},
    {'name': 'DiskReadOps',                 'unit': 'count',         'stat': 'Sum'},
    {'name': 'DiskWriteOps',               'unit': 'count',         'stat': 'Sum'},
    {'name': 'StatusCheckFailed',           'unit': 'count',         'stat': 'Maximum'},
]


# ---------------------------------------------------------------------------
# CLOUDWATCH COLLECTOR CLASS
# ---------------------------------------------------------------------------

class CloudWatchCollector:
    """Wraps boto3 CloudWatch client for RDS/EC2 metric collection."""

    def __init__(self, region: str = AWS_REGION):
        self.region = region
        self.cw_client = boto3.client('cloudwatch', region_name=region)
        self.rds_client = boto3.client('rds', region_name=region)
        self.logs_client = boto3.client('logs', region_name=region)
        log.info("CloudWatch collector initialized (region=%s)", region)

    # -- Discovery ----------------------------------------------------------

    def list_rds_instances(self) -> List[str]:
        """Get all RDS instance identifiers via CloudWatch dimension values.

        Uses list_metrics to discover all DBInstanceIdentifier dimensions
        that have published CPUUtilization data recently.
        """
        identifiers = set()
        paginator = self.cw_client.get_paginator('list_metrics')

        for page in paginator.paginate(
            Namespace='AWS/RDS',
            MetricName='CPUUtilization',
            Dimensions=[{'Name': 'DBInstanceIdentifier'}],
        ):
            for metric in page.get('Metrics', []):
                for dim in metric.get('Dimensions', []):
                    if dim['Name'] == 'DBInstanceIdentifier':
                        identifiers.add(dim['Value'])

        result = sorted(identifiers)
        log.info("Discovered %d RDS instances via CloudWatch", len(result))
        return result

    def list_ec2_instances(self) -> List[str]:
        """Get all EC2 instance IDs via CloudWatch dimension values.

        Placeholder for future implementation when node_exporter is deployed.
        """
        identifiers = set()
        paginator = self.cw_client.get_paginator('list_metrics')

        for page in paginator.paginate(
            Namespace='AWS/EC2',
            MetricName='CPUUtilization',
            Dimensions=[{'Name': 'InstanceId'}],
        ):
            for metric in page.get('Metrics', []):
                for dim in metric.get('Dimensions', []):
                    if dim['Name'] == 'InstanceId':
                        identifiers.add(dim['Value'])

        result = sorted(identifiers)
        log.info("Discovered %d EC2 instances via CloudWatch", len(result))
        return result

    # -- Metric Retrieval ---------------------------------------------------

    def get_metric_daily(self, namespace: str, metric_name: str,
                         dimensions: List[Dict], target_date: date,
                         stat: str = 'Average') -> Optional[float]:
        """Get the daily aggregate for a single metric + dimension set.

        Queries CloudWatch for the full 24-hour period of target_date
        with a single data point (period=86400 seconds).

        Returns the metric value or None if no data.
        """
        start_time = datetime.combine(target_date, datetime.min.time())
        end_time = start_time + timedelta(days=1)

        try:
            resp = self.cw_client.get_metric_statistics(
                Namespace=namespace,
                MetricName=metric_name,
                Dimensions=dimensions,
                StartTime=start_time,
                EndTime=end_time,
                Period=86400,  # 1 day
                Statistics=[stat],
            )

            datapoints = resp.get('Datapoints', [])
            if not datapoints:
                return None

            # Return the single daily aggregate
            return datapoints[0].get(stat)

        except Exception as exc:
            log.debug("  No data for %s/%s: %s", namespace, metric_name, exc)
            return None

    # -- RDS Collection -----------------------------------------------------

    def collect_rds_metrics(self, target_date: date) -> List[Dict]:
        """Collect all configured RDS metrics for all discovered instances.

        Returns a list of row dicts ready for INSERT into infra_metric_daily.
        """
        instances = self.list_rds_instances()
        if not instances:
            log.warning("No RDS instances found. Skipping RDS collection.")
            return []

        rows: List[Dict] = []
        total_api_calls = 0

        for idx, instance_id in enumerate(instances):
            short_name = parse_rds_instance_name(instance_id)
            log.info("  [%d/%d] Collecting metrics for RDS: %s",
                     idx + 1, len(instances), instance_id)

            dimensions = [
                {'Name': 'DBInstanceIdentifier', 'Value': instance_id},
            ]

            for metric_cfg in RDS_METRICS:
                value = self.get_metric_daily(
                    namespace='AWS/RDS',
                    metric_name=metric_cfg['name'],
                    dimensions=dimensions,
                    target_date=target_date,
                    stat=metric_cfg['stat'],
                )
                total_api_calls += 1

                if value is not None:
                    # Normalize metric name to snake_case
                    metric_key = _to_snake_case(metric_cfg['name'])
                    rows.append({
                        'metric_date':   target_date.isoformat(),
                        'resource_type': 'rds',
                        'resource_name': short_name,
                        'instance':      instance_id[:255],
                        'metric_name':   metric_key,
                        'metric_value':  round(value, 6),
                        'metric_unit':   metric_cfg['unit'],
                        'source':        'cloudwatch',
                    })

            # Throttle to avoid CloudWatch rate limits
            if (idx + 1) % 10 == 0:
                log.info("    Throttle pause after %d instances (%d API calls)...",
                         idx + 1, total_api_calls)
                time.sleep(1)

        log.info("  RDS collection complete: %d rows from %d instances (%d API calls)",
                 len(rows), len(instances), total_api_calls)
        return rows

    # -- EC2 Collection (placeholder) ----------------------------------------

    def collect_ec2_metrics(self, target_date: date) -> List[Dict]:
        """Collect EC2 metrics for all discovered instances.

        NOTE: This is a placeholder for future implementation.
        Currently EC2 instances lack node_exporter and detailed monitoring
        is not enabled on most instances. Returns empty list.
        """
        if os.getenv('ENABLE_EC2_COLLECTION', 'false').lower() != 'true':
            log.info("  EC2 collection is disabled (set ENABLE_EC2_COLLECTION=true to enable)")
            return []

        instances = self.list_ec2_instances()
        if not instances:
            log.warning("No EC2 instances found. Skipping EC2 collection.")
            return []

        rows: List[Dict] = []

        for idx, instance_id in enumerate(instances):
            log.info("  [%d/%d] Collecting metrics for EC2: %s",
                     idx + 1, len(instances), instance_id)

            dimensions = [
                {'Name': 'InstanceId', 'Value': instance_id},
            ]

            for metric_cfg in EC2_METRICS:
                value = self.get_metric_daily(
                    namespace='AWS/EC2',
                    metric_name=metric_cfg['name'],
                    dimensions=dimensions,
                    target_date=target_date,
                    stat=metric_cfg['stat'],
                )

                if value is not None:
                    metric_key = _to_snake_case(metric_cfg['name'])
                    rows.append({
                        'metric_date':   target_date.isoformat(),
                        'resource_type': 'ec2',
                        'resource_name': instance_id,
                        'instance':      instance_id,
                        'metric_name':   metric_key,
                        'metric_value':  round(value, 6),
                        'metric_unit':   metric_cfg['unit'],
                        'source':        'cloudwatch',
                    })

            if (idx + 1) % 20 == 0:
                time.sleep(0.5)

        log.info("  EC2 collection complete: %d rows from %d instances",
                 len(rows), len(instances))
        return rows

    # -- Slow Query Log Analysis --------------------------------------------

    def list_rds_log_groups(self) -> List[str]:
        """Discover RDS slow query log groups in CloudWatch Logs.

        Looks for log groups matching /aws/rds/instance/*/slowquery
        """
        log_groups = []
        paginator = self.logs_client.get_paginator('describe_log_groups')

        for page in paginator.paginate(
            logGroupNamePrefix='/aws/rds/instance/',
        ):
            for lg in page.get('logGroups', []):
                name = lg['logGroupName']
                if 'slowquery' in name:
                    log_groups.append(name)

        log.info("Discovered %d RDS slow query log groups", len(log_groups))
        return log_groups


def collect_slow_query_counts(target_date: date) -> List[Dict]:
    """Query CloudWatch Logs Insights for slow query counts per RDS instance.

    Runs a Logs Insights query against each slow query log group to count
    the number of slow queries for the target date.

    Returns row dicts for insertion into infra_metric_daily.
    """
    collector = CloudWatchCollector()
    log_groups = collector.list_rds_log_groups()

    if not log_groups:
        log.info("  No slow query log groups found. Skipping.")
        return []

    start_time = datetime.combine(target_date, datetime.min.time())
    end_time = start_time + timedelta(days=1)

    rows: List[Dict] = []

    # Process log groups in batches of 20 (Logs Insights limit)
    batch_size = 20
    for i in range(0, len(log_groups), batch_size):
        batch = log_groups[i:i + batch_size]
        log.info("  Querying slow query counts for %d log groups (%d-%d)",
                 len(batch), i + 1, min(i + batch_size, len(log_groups)))

        try:
            resp = collector.logs_client.start_query(
                logGroupNames=batch,
                startTime=int(start_time.timestamp()),
                endTime=int(end_time.timestamp()),
                queryString=(
                    'stats count(*) as slow_query_count by @logStream'
                    ' | sort slow_query_count desc'
                ),
            )
            query_id = resp['queryId']

            # Poll for results
            for _ in range(30):
                time.sleep(2)
                result = collector.logs_client.get_query_results(queryId=query_id)
                if result['status'] in ('Complete', 'Failed', 'Cancelled'):
                    break

            if result['status'] == 'Complete':
                for row_result in result.get('results', []):
                    fields = {f['field']: f['value'] for f in row_result}
                    log_stream = fields.get('@logStream', '')
                    count_val = float(fields.get('slow_query_count', 0))

                    # Extract instance name from log stream
                    instance_name = log_stream.split('/')[-1] if '/' in log_stream else log_stream
                    short_name = parse_rds_instance_name(instance_name)

                    rows.append({
                        'metric_date':   target_date.isoformat(),
                        'resource_type': 'rds',
                        'resource_name': short_name,
                        'instance':      instance_name[:255],
                        'metric_name':   'slow_query_count',
                        'metric_value':  count_val,
                        'metric_unit':   'count',
                        'source':        'cloudwatch_logs',
                    })
            else:
                log.warning("  Logs Insights query status: %s", result['status'])

        except Exception as exc:
            log.error("  Failed slow query analysis for batch %d: %s", i, exc)

    log.info("  Slow query analysis: %d rows from %d log groups",
             len(rows), len(log_groups))
    return rows


# ---------------------------------------------------------------------------
# UTILITY FUNCTIONS
# ---------------------------------------------------------------------------

def parse_rds_instance_name(identifier: str) -> str:
    """Extract a short descriptive name from an RDS instance identifier.

    Examples:
        "aws-luckyus-isales-prod-rw" -> "isales-prod-rw"
        "luckyus-user-center-ro"     -> "user-center-ro"
        "mydb-instance-1"            -> "mydb-instance-1"
    """
    # Strip common Luckin prefixes
    short = re.sub(r'^(aws-)?luckyus-', '', identifier, flags=re.IGNORECASE)
    return short or identifier


def _to_snake_case(name: str) -> str:
    """Convert CamelCase metric name to snake_case.

    Examples:
        "CPUUtilization"            -> "cpu_utilization"
        "FreeableMemory"            -> "freeable_memory"
        "NetworkReceiveThroughput"  -> "network_receive_throughput"
    """
    s1 = re.sub(r'([A-Z]+)([A-Z][a-z])', r'\1_\2', name)
    s2 = re.sub(r'([a-z0-9])([A-Z])', r'\1_\2', s1)
    return s2.lower()


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

        if batch:
            cur.executemany(sql, batch)
            total += cur.rowcount

    conn.commit()
    return total


# ---------------------------------------------------------------------------
# MAIN COLLECTION FUNCTION
# ---------------------------------------------------------------------------

def collect_all(target_date: date) -> Dict[str, int]:
    """Run the full CloudWatch collection pipeline for a single date.

    Returns a stats dict: {rds, ec2, slow_queries, total_inserted}
    """
    log.info("=" * 60)
    log.info("CloudWatch collection for %s", target_date.isoformat())
    log.info("=" * 60)

    collector = CloudWatchCollector()
    all_rows: List[Dict] = []

    # Step 1: RDS metrics
    log.info("--- Collecting RDS metrics ---")
    rds_rows = collector.collect_rds_metrics(target_date)
    all_rows.extend(rds_rows)

    # Step 2: EC2 metrics (placeholder)
    log.info("--- Collecting EC2 metrics ---")
    ec2_rows = collector.collect_ec2_metrics(target_date)
    all_rows.extend(ec2_rows)

    # Step 3: Slow query counts
    slow_rows = []
    if os.getenv('ENABLE_SLOW_QUERY_ANALYSIS', 'true').lower() == 'true':
        log.info("--- Collecting slow query counts ---")
        slow_rows = collect_slow_query_counts(target_date)
        all_rows.extend(slow_rows)
    else:
        log.info("--- Slow query analysis disabled ---")

    # Step 4: Insert all into MySQL
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
        'rds':            len(rds_rows),
        'ec2':            len(ec2_rows),
        'slow_queries':   len(slow_rows),
        'total_inserted': total_inserted,
    }
    log.info("CloudWatch collection complete: %s", json.dumps(stats))
    return stats


# ---------------------------------------------------------------------------
# CLI ENTRYPOINT
# ---------------------------------------------------------------------------

def main():
    """Parse arguments and run CloudWatch collection."""
    parser = argparse.ArgumentParser(
        description='UC-IT-01: CloudWatch RDS/EC2 Metrics Collector',
    )
    parser.add_argument(
        '--date', type=str, default=None,
        help='Target date in YYYY-MM-DD format (default: yesterday)',
    )
    parser.add_argument(
        '--backfill', type=int, default=None,
        help='Backfill N days ending yesterday',
    )
    parser.add_argument(
        '--skip-slow-queries', action='store_true',
        help='Skip slow query log analysis',
    )
    args = parser.parse_args()

    if args.skip_slow_queries:
        os.environ['ENABLE_SLOW_QUERY_ANALYSIS'] = 'false'

    if args.backfill:
        end_date = date.today() - timedelta(days=1)
        start_date = end_date - timedelta(days=args.backfill - 1)
        log.info("Backfill mode: %s to %s (%d days)",
                 start_date, end_date, args.backfill)

        total_stats = {'rds': 0, 'ec2': 0, 'slow_queries': 0, 'total_inserted': 0}
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

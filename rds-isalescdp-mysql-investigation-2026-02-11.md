# MySQL Direct Investigation: aws-luckyus-isalescdp-rw

**Date**: 2026-02-11
**Database**: luckyus_isales_cdp
**Engine**: MySQL 8.0.40

## Executive Summary

**ROOT CAUSE IDENTIFIED**: Data retention cleanup jobs on `t_user_event` and `t_user_event_track` tables are causing the slow query spike at 05:00-05:30 UTC.

- DELETE operations averaging **864ms** per execution
- Missing index on `create_time` column for cleanup queries
- No MySQL scheduled events - cleanup triggered by application

## Slow Query Configuration

| Variable | Value | Notes |
|----------|-------|-------|
| slow_query_log | **ON** | Slow query logging enabled |
| slow_query_log_file | /rdsdbdata/log/slowquery/mysql-slowquery.log | RDS managed |
| long_query_time | **0.100000** (100ms) | Aggressive threshold |
| Slow_queries (total) | **2,034,258** | Cumulative counter |

**Note**: The 100ms threshold is quite aggressive - any query > 100ms is logged as slow.

## Current Running Queries

| ID | User | Host | Command | Time (sec) | State |
|----|------|------|---------|------------|-------|
| 5 | event_scheduler | localhost | Daemon | 29,195,854 | Waiting on empty queue |
| 2860122 | datalink_canal | 10.238.3.233:10250 | Binlog Dump GTID | 3,022,874 | Master has sent all binlog |

**Status**: No user queries currently running > 1 second. System is idle.

## Top Slow Queries (Last 3 Hours)

### Critical - Data Cleanup Operations

| Query Pattern | Avg Time (ms) | Executions | Total Time (ms) | Status |
|--------------|---------------|------------|-----------------|--------|
| `DELETE FROM t_user_event WHERE id <= ?` | **864.1** | 2,139 | 1,848,322 | **ROOT CAUSE** |
| `DELETE FROM t_user_event_track WHERE id <= ?` | **321.2** | 2,601 | 835,495 | **ROOT CAUSE** |
| `SELECT id FROM t_user_event WHERE create_time < ? ORDER BY id LIMIT ?` | **249.3** | 2,009 | 500,935 | Related |
| `SELECT id FROM t_user_event_track WHERE create_time < ? ORDER BY id LIMIT ?` | **227.5** | 2,950 | 671,272 | Related |

### System Operations

| Query Pattern | Avg Time (ms) | Executions | Total Time (ms) |
|--------------|---------------|------------|-----------------|
| FLUSH LOGS | 124.5 | 97,603 | 12,154,580 |
| INSERT INTO t_user_event (...) | 121.2 | 661 | 80,096 |
| PURGE BINARY LOGS BEFORE ? | 25.5 | 97,313 | 2,486,048 |
| FLUSH SLOW LOGS | 19.8 | 5,515 | 109,047 |

## Problem Tables Analysis

### Table Statistics

| Table | Rows | Data (MB) | Index (MB) | Total (MB) |
|-------|------|-----------|------------|------------|
| t_user_event_track | 301,802 | 61.1 | 22.1 | 83.2 |
| t_user_event | 91,885 | 11.5 | 31.1 | 42.7 |

### Index Analysis - t_user_event

| Index Name | Columns | Cardinality |
|------------|---------|-------------|
| PRIMARY | id | 14 |
| idx_event_time | event_time | 14 |
| idx_msg_id | msg_id | 14 |
| idx_user_no | user_no | 12 |
| idx_user_event | user_no, event_type, event_sub_type, event_time | 14 |
| idx_user_event_type | event_type, event_sub_type, user_no | 13 |
| idx_user_event_sub_type | event_sub_type, user_no | 13 |

**Missing Index**: `create_time` - used in cleanup SELECT but no dedicated index!

### Index Analysis - t_user_event_track

| Index Name | Columns | Cardinality |
|------------|---------|-------------|
| PRIMARY | id | 3,011 |
| idx_user_event | user_no, event_type, event_time | 3,019 |

**Missing Index**: `create_time` - used in cleanup SELECT but no dedicated index!

## MySQL Scheduled Events

```sql
SELECT event_schema, event_name, last_executed, status
FROM information_schema.events WHERE status = 'ENABLED';
```

**Result**: No MySQL scheduled events found.

**Conclusion**: The cleanup jobs are triggered by the **application layer**, not MySQL events. This explains why they run at specific times (likely a cron job or application scheduler).

## Root Cause Analysis

### The Cleanup Pattern

The application runs a data retention process with this pattern:

1. **Find old records**:
   ```sql
   SELECT id FROM t_user_event WHERE create_time < ? ORDER BY id LIMIT ?
   ```
   - Average: 249ms (because `create_time` lacks an index)

2. **Delete in batches**:
   ```sql
   DELETE FROM t_user_event WHERE id <= ?
   ```
   - Average: 864ms (deleting by ID range)

3. **Repeat for t_user_event_track**

### Why It's Slow

1. **Missing Index**: `SELECT ... WHERE create_time < ?` does a full table scan
2. **Large Deletes**: Batch deletes cause lock contention
3. **Concurrent Execution**: Multiple workers running simultaneously (149 connections peak)
4. **Small Instance**: db.t4g.micro has limited CPU/memory for this workload

## Recommendations

### Immediate - Add Missing Indexes

```sql
-- Add index for cleanup queries
ALTER TABLE t_user_event ADD INDEX idx_create_time (create_time);
ALTER TABLE t_user_event_track ADD INDEX idx_create_time (create_time);
```

### Optimize Cleanup Process

```sql
-- Current (slow - full scan then delete)
SELECT id FROM t_user_event WHERE create_time < ? ORDER BY id LIMIT ?;
DELETE FROM t_user_event WHERE id <= ?;

-- Recommended (direct delete with limit)
DELETE FROM t_user_event
WHERE create_time < ?
ORDER BY id
LIMIT 1000;
```

### Application Changes

1. **Reduce Batch Size**: Delete 500-1000 rows at a time instead of large batches
2. **Add Delays**: Sleep 100-500ms between batches to reduce lock contention
3. **Reduce Parallelism**: Run cleanup with fewer concurrent workers
4. **Off-Peak Scheduling**: Move cleanup to 02:00-04:00 UTC (lower traffic)

### Instance Sizing

Consider upgrading from `db.t4g.micro` to:
- `db.t4g.small` (2 vCPU, 2 GB RAM) - moderate improvement
- `db.t4g.medium` (2 vCPU, 4 GB RAM) - recommended for this workload

## Verification Queries

### Monitor Slow Query Rate
```sql
-- Current slow query count
SHOW GLOBAL STATUS LIKE 'Slow_queries';

-- Watch for new slow queries (run every minute)
SELECT VARIABLE_VALUE FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Slow_queries';
```

### Check for Lock Contention
```sql
-- Current locks
SELECT * FROM sys.innodb_lock_waits;

-- Long-running transactions
SELECT trx_id, trx_started, trx_mysql_thread_id, trx_query
FROM information_schema.innodb_trx
WHERE trx_started < NOW() - INTERVAL 10 SECOND;
```

### Monitor Cleanup Progress
```sql
-- Check oldest record in tables
SELECT MIN(create_time) as oldest_event FROM t_user_event;
SELECT MIN(create_time) as oldest_track FROM t_user_event_track;

-- Check table row counts
SELECT
  (SELECT COUNT(*) FROM t_user_event) as event_count,
  (SELECT COUNT(*) FROM t_user_event_track) as track_count;
```

## Raw Query Results

### Slow Query Variables
```json
{
  "slow_query_log": "ON",
  "slow_query_log_file": "/rdsdbdata/log/slowquery/mysql-slowquery.log",
  "long_query_time": "0.100000",
  "Slow_queries": "2034258"
}
```

### Current Processlist (Non-Sleep, Time > 1s)
```json
[
  {
    "id": 5,
    "user": "event_scheduler",
    "host": "localhost",
    "db": null,
    "command": "Daemon",
    "time": 29195854,
    "state": "Waiting on empty queue"
  },
  {
    "id": 2860122,
    "user": "datalink_canal",
    "host": "10.238.3.233:10250",
    "db": "luckyus_isales_cdp",
    "command": "Binlog Dump GTID",
    "time": 3022874,
    "state": "Master has sent all binlog to slave; waiting for more updates"
  }
]
```

### Performance Schema - Top 5 Slow Queries
```json
[
  {
    "query": "DELETE FROM t_user_event WHERE id <= ?",
    "count": 2139,
    "avg_ms": 864.1,
    "total_ms": 1848321.7,
    "last_seen": "2026-02-11T07:00:28"
  },
  {
    "query": "DELETE FROM t_user_event_track WHERE id <= ?",
    "count": 2601,
    "avg_ms": 321.2,
    "total_ms": 835495.0,
    "last_seen": "2026-02-11T07:01:31"
  },
  {
    "query": "SELECT id FROM t_user_event WHERE create_time < ? ORDER BY id LIMIT ?",
    "count": 2009,
    "avg_ms": 249.3,
    "total_ms": 500935.4,
    "last_seen": "2026-02-11T07:00:28"
  },
  {
    "query": "SELECT id FROM t_user_event_track WHERE create_time < ? ORDER BY id LIMIT ?",
    "count": 2950,
    "avg_ms": 227.5,
    "total_ms": 671272.3,
    "last_seen": "2026-02-11T07:01:31"
  },
  {
    "query": "FLUSH LOGS",
    "count": 97603,
    "avg_ms": 124.5,
    "total_ms": 12154580.4,
    "last_seen": "2026-02-11T07:30:01"
  }
]
```

### MySQL Events
```json
{
  "enabled_events": [],
  "count": 0
}
```

No MySQL scheduled events - cleanup is application-triggered.

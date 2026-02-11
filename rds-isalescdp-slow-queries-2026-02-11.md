# MySQL Slow Query Analysis: aws-luckyus-isalescdp-rw

**Date**: 2026-02-11
**Time Range**: 04:00 - 07:00 UTC
**Data Source**: Grafana/Prometheus (UMBQuerier-Luckin)
**Instance**: aws-luckyus-isalescdp-rw

## Executive Summary

**CRITICAL**: Massive slow query spike detected between **05:01-05:30 UTC**:
- **6,303 new slow queries** generated in ~25 minutes
- Peak rate: **10.8 slow queries/second** (vs baseline 0.02/sec)
- Threads running spiked to **33** (vs baseline 3)
- Correlates exactly with CloudWatch CPU/IOPS spike

## Metrics Summary

### Slow Query Counter (Cumulative)

| Time (UTC) | Total Slow Queries | Delta from 04:00 |
|------------|-------------------|------------------|
| 04:00 | 2,027,573 | - |
| 05:00 | 2,027,671 | +98 (normal) |
| **05:01** | **2,028,085** | **+414 (spike starts)** |
| 05:05 | 2,028,341 | +768 |
| 05:10 | 2,029,104 | +1,531 |
| 05:15 | 2,030,639 | +3,066 |
| **05:17** | **2,032,239** | **+4,666 (peak rate)** |
| 05:20 | 2,033,226 | +5,653 |
| 05:25 | 2,033,788 | +6,215 |
| 05:30 | 2,033,870 | +6,297 |
| 07:00 | 2,033,974 | +6,401 |

**Total new slow queries during spike (05:01-05:30)**: ~6,200

### Slow Query Rate (queries/second)

| Period | Rate (queries/sec) | Status |
|--------|-------------------|--------|
| 04:00-05:00 (Baseline) | 0.01 - 0.10 | Normal |
| **05:01** | **1.38** | **Spike Start** |
| **05:02** | **2.02** | Escalating |
| **05:10** | **2.68** | High |
| **05:13** | **5.35** | Very High |
| **05:15** | **8.27** | Critical |
| **05:17** | **10.80** | **PEAK** |
| **05:18** | **9.21** | Declining |
| 05:25 | 1.87 | Recovery |
| 05:30 | 0.05 | Normal |
| 06:00-07:00 | 0.01 - 0.03 | Normal |

### Threads Running

| Period | Threads Running | Status |
|--------|----------------|--------|
| 04:00-05:00 (Baseline) | 3 | Normal |
| **05:01** | **33** | **PEAK** |
| 05:06 | 20 | High |
| 05:09-05:15 | 22-25 | Sustained High |
| **05:22** | **27** | Second Peak |
| 05:26 | 3 | Recovered |
| 05:30-07:00 | 3 | Normal |

## Timeline Analysis

```
Time (UTC)   Slow Queries/sec   Threads Running   Status
---------    ----------------   ---------------   ------
04:00        0.01               3                 Normal
04:30        0.02               3                 Normal
05:00        0.01               3                 Normal
05:01        1.38               33                ← SPIKE STARTS
05:02        2.02               3
05:06        0.72               20
05:08        0.81               22
05:10        2.68               24
05:11        3.47               24
05:13        5.35               22
05:14        7.03               22
05:15        8.27               25
05:16        10.45              22                ← PEAK RATE
05:17        10.80              20                ← MAX SLOW QUERIES
05:18        9.21               18
05:19        7.80               14
05:20        7.02               20
05:21        4.34               12
05:22        3.45               27                ← Second threads peak
05:23        3.03               8
05:24        2.63               9
05:25        1.87               11
05:26        1.01               3                 ← Recovery begins
05:27        0.65               3
05:30        0.05               3                 Normal
06:00        0.02               3                 Normal
07:00        0.003              3                 Normal
```

## Correlation with CloudWatch Metrics

| Metric | Peak Time | Peak Value | Baseline |
|--------|-----------|------------|----------|
| Slow Query Rate | 05:17 UTC | 10.8/sec | 0.02/sec |
| Threads Running | 05:01 UTC | 33 | 3 |
| CPU Utilization | 05:10 UTC | 69.6% | 6% |
| Write IOPS | 05:20 UTC | 1,052/sec | 10/sec |
| Connections | 05:10 UTC | 149 | 35 |

**Strong correlation**: All metrics spike between 05:00-05:30 UTC, confirming a single root cause event.

## Root Cause Analysis

### Evidence Points to Batch Processing Job

1. **Sudden Onset**: Activity jumped from baseline to peak within 1 minute (05:00 → 05:01)
2. **Write-Heavy**: 1,052 Write IOPS peak indicates bulk INSERT/UPDATE operations
3. **High Concurrency**: 149 connections & 33 threads running suggest parallel workers
4. **Slow Query Explosion**: 6,200+ slow queries in 25 minutes indicates:
   - Large table scans without proper indexes
   - Lock contention from concurrent writes
   - Possible missing query optimization

### Likely Scenarios

1. **ETL/Data Sync Job** - Bulk data import or synchronization
2. **Report Generation** - Complex aggregation queries
3. **Batch Processing** - Scheduled job processing accumulated data
4. **Data Migration** - Moving/transforming large datasets

## Recommendations

### Immediate Actions

1. **Identify the Job**
   ```sql
   -- Check slow query log for queries during 05:00-05:30 UTC
   SELECT * FROM mysql.slow_log
   WHERE start_time BETWEEN '2026-02-11 05:00:00' AND '2026-02-11 05:30:00'
   ORDER BY query_time DESC LIMIT 100;
   ```

2. **Review Application Logs**
   - Check for scheduled jobs starting at 05:00 UTC
   - Look for batch processing or ETL frameworks

3. **Optimize Slow Queries**
   - Add missing indexes for frequently queried columns
   - Review execution plans for the slowest queries
   - Consider query rewrites or batching

### Long-term Improvements

1. **Instance Sizing**
   - db.t4g.micro is undersized for this workload
   - Consider upgrade to db.t4g.small or db.t4g.medium

2. **Query Optimization**
   - Implement query caching
   - Add covering indexes for slow queries
   - Consider read replicas for reporting workloads

3. **Job Scheduling**
   - Move heavy batch jobs to off-peak hours
   - Implement rate limiting on batch operations
   - Consider splitting large batches into smaller chunks

4. **Monitoring**
   - Set up alerts for slow_query_rate > 1/sec
   - Monitor threads_running > 10
   - Track connection count approaching max_connections

## Raw Prometheus Data

### Slow Queries Counter (Selected Points)
```json
[
  {"timestamp": "2026-02-11T04:00:00Z", "value": 2027573},
  {"timestamp": "2026-02-11T05:00:00Z", "value": 2027671},
  {"timestamp": "2026-02-11T05:01:00Z", "value": 2028085},
  {"timestamp": "2026-02-11T05:05:00Z", "value": 2028341},
  {"timestamp": "2026-02-11T05:10:00Z", "value": 2029104},
  {"timestamp": "2026-02-11T05:15:00Z", "value": 2030639},
  {"timestamp": "2026-02-11T05:17:00Z", "value": 2032239},
  {"timestamp": "2026-02-11T05:20:00Z", "value": 2033226},
  {"timestamp": "2026-02-11T05:25:00Z", "value": 2033788},
  {"timestamp": "2026-02-11T05:30:00Z", "value": 2033870},
  {"timestamp": "2026-02-11T06:00:00Z", "value": 2033893},
  {"timestamp": "2026-02-11T07:00:00Z", "value": 2033974}
]
```

### Slow Query Rate (Peak Period)
```json
[
  {"timestamp": "2026-02-11T05:01:00Z", "rate_per_sec": 1.38},
  {"timestamp": "2026-02-11T05:02:00Z", "rate_per_sec": 2.02},
  {"timestamp": "2026-02-11T05:10:00Z", "rate_per_sec": 2.68},
  {"timestamp": "2026-02-11T05:13:00Z", "rate_per_sec": 5.35},
  {"timestamp": "2026-02-11T05:14:00Z", "rate_per_sec": 7.03},
  {"timestamp": "2026-02-11T05:15:00Z", "rate_per_sec": 8.27},
  {"timestamp": "2026-02-11T05:16:00Z", "rate_per_sec": 10.45},
  {"timestamp": "2026-02-11T05:17:00Z", "rate_per_sec": 10.80},
  {"timestamp": "2026-02-11T05:18:00Z", "rate_per_sec": 9.21},
  {"timestamp": "2026-02-11T05:19:00Z", "rate_per_sec": 7.80},
  {"timestamp": "2026-02-11T05:20:00Z", "rate_per_sec": 7.02}
]
```

### Threads Running (Peak Period)
```json
[
  {"timestamp": "2026-02-11T05:00:00Z", "threads": 3},
  {"timestamp": "2026-02-11T05:01:00Z", "threads": 33},
  {"timestamp": "2026-02-11T05:06:00Z", "threads": 20},
  {"timestamp": "2026-02-11T05:09:00Z", "threads": 22},
  {"timestamp": "2026-02-11T05:11:00Z", "threads": 24},
  {"timestamp": "2026-02-11T05:15:00Z", "threads": 25},
  {"timestamp": "2026-02-11T05:17:00Z", "threads": 20},
  {"timestamp": "2026-02-11T05:22:00Z", "threads": 27},
  {"timestamp": "2026-02-11T05:26:00Z", "threads": 3}
]
```

## Grafana Query Reference

```promql
# Slow query counter
mysql_global_status_slow_queries{dbinstance_identifier="aws-luckyus-isalescdp-rw"}

# Slow query rate (per second)
rate(mysql_global_status_slow_queries{dbinstance_identifier="aws-luckyus-isalescdp-rw"}[5m])

# Threads running
mysql_global_status_threads_running{dbinstance_identifier="aws-luckyus-isalescdp-rw"}
```

**Datasource**: UMBQuerier-Luckin (UID: df8o21agxtkw0d)

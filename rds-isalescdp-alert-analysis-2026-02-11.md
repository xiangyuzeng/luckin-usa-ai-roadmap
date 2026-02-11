# Alert Configuration Analysis: mysql_global_status_slow_queries

**Date**: 2026-02-11
**Instance**: aws-luckyus-isalescdp-rw
**Alert**: Slow Query Monitoring

## Executive Summary

**CRITICAL MISCONFIGURATION**: The current alert expression is fundamentally broken.

| Issue | Current | Correct |
|-------|---------|---------|
| Expression | `avg_over_time(mysql_global_status_slow_queries[3m]) > 300` | `rate(mysql_global_status_slow_queries[3m]) * 180 > 300` |
| What it measures | Cumulative counter (~2M) | New slow queries per 3 min |
| Result | **Always fires** | Fires only during actual spikes |

## Metric Type Verification

### 1. Is it a Counter or Gauge?

```sql
SHOW GLOBAL STATUS LIKE 'Slow_queries';
```

| Variable | Value | Type |
|----------|-------|------|
| Slow_queries | **2,034,727** | **COUNTER** (cumulative) |

**Confirmed**: This is a **monotonically increasing counter** that counts total slow queries since MySQL restart.

### 2. When Was Instance Last Restarted?

```sql
SELECT NOW() - INTERVAL Uptime SECOND AS last_restart;
```

| Uptime (seconds) | Uptime (days) | Last Restart |
|------------------|---------------|--------------|
| 29,196,081 | **338 days** | **2025-03-10 09:32:40 UTC** |

### 3. Current Metric Values

| Expression | Value | Meaning |
|------------|-------|---------|
| `mysql_global_status_slow_queries` | 2,034,727 | Total since restart |
| `avg_over_time(...[3m])` | **2,034,525** | Still the counter! |
| `rate(...[3m]) * 180` | **284** | New queries in 3 min |

## Alert Expression Analysis

### Current (BROKEN) Expression

```promql
avg_over_time(mysql_global_status_slow_queries{cluster="aws-luckyus-isalescdp-rw"}[3m]) > 300
```

**Problems**:
1. `avg_over_time()` on a counter returns the average counter VALUE, not the rate
2. Counter value is ~2,034,525, which is **always > 300**
3. This alert would fire **100% of the time** after ~5 minutes of uptime
4. Uses `cluster` label but correct label is `dbinstance_identifier`

### Correct Expression

```promql
rate(mysql_global_status_slow_queries{dbinstance_identifier="aws-luckyus-isalescdp-rw"}[3m]) * 180 > 300
```

**Explanation**:
- `rate(...[3m])` = new slow queries per second over 3 minutes
- `* 180` = convert to total new queries in 3 minutes (180 seconds)
- `> 300` = alert if more than 300 new slow queries in 3 minutes

## Spike Period Analysis

Using the **correct** expression during the 05:00-05:30 UTC spike:

| Time (UTC) | New Slow Queries (3 min) | Would Alert? |
|------------|--------------------------|--------------|
| 04:50 | 1 | No |
| 04:55 | 2 | No |
| 05:00 | 1 | No |
| **05:01** | **415** | **YES** |
| **05:02** | **605** | **YES** |
| **05:03** | **612** | **YES** |
| 05:04 | 201 | No |
| 05:06 | 18 | No |
| 05:08 | 170 | No |
| **05:10** | **300** | **YES (borderline)** |
| **05:11** | **648** | **YES** |
| **05:12** | **851** | **YES** |
| **05:13** | **1,421** | **YES** |
| **05:14** | **1,535** | **YES** |
| **05:15** | **1,740** | **YES** |
| **05:16** | **2,177** | **YES (PEAK)** |
| **05:17** | **1,983** | **YES** |
| **05:18** | **1,704** | **YES** |
| 05:19 | 739 | YES |
| **05:20** | **604** | **YES** |
| **05:21** | **715** | **YES** |
| **05:22** | **680** | **YES** |
| **05:23** | **507** | **YES** |
| 05:24 | 226 | No |
| 05:25 | 130 | No |
| 05:30 | 7 | No |

**Peak**: 2,177 new slow queries in 3 minutes at 05:16 UTC

## Recommended Alert Configurations

### Option 1: Simple Threshold (Recommended)

```yaml
alert: MySQLHighSlowQueryRate
expr: rate(mysql_global_status_slow_queries{dbinstance_identifier="aws-luckyus-isalescdp-rw"}[3m]) * 180 > 300
for: 2m
labels:
  severity: warning
annotations:
  summary: "High slow query rate on {{ $labels.dbinstance_identifier }}"
  description: "{{ $value }} slow queries in the last 3 minutes (threshold: 300)"
```

### Option 2: Per-Second Rate

```yaml
alert: MySQLHighSlowQueryRate
expr: rate(mysql_global_status_slow_queries{dbinstance_identifier="aws-luckyus-isalescdp-rw"}[5m]) > 1
for: 3m
labels:
  severity: warning
annotations:
  summary: "Elevated slow query rate on {{ $labels.dbinstance_identifier }}"
  description: "{{ $value | printf \"%.2f\" }} slow queries/second (threshold: 1/sec)"
```

### Option 3: Percentage Increase (Advanced)

```yaml
alert: MySQLSlowQuerySpike
expr: |
  rate(mysql_global_status_slow_queries{dbinstance_identifier="aws-luckyus-isalescdp-rw"}[5m])
  /
  rate(mysql_global_status_slow_queries{dbinstance_identifier="aws-luckyus-isalescdp-rw"}[1h] offset 5m)
  > 10
for: 3m
labels:
  severity: critical
annotations:
  summary: "Slow query spike detected on {{ $labels.dbinstance_identifier }}"
  description: "Slow query rate is {{ $value }}x higher than the last hour average"
```

## Label Correction

The alert uses `cluster` but the metric has `dbinstance_identifier`:

```promql
# Wrong
mysql_global_status_slow_queries{cluster="aws-luckyus-isalescdp-rw"}

# Correct
mysql_global_status_slow_queries{dbinstance_identifier="aws-luckyus-isalescdp-rw"}
```

## Summary of Issues

| # | Issue | Impact | Fix |
|---|-------|--------|-----|
| 1 | Using `avg_over_time()` on counter | Alert always fires | Use `rate()` |
| 2 | Wrong label name (`cluster`) | Query returns no data | Use `dbinstance_identifier` |
| 3 | No `for` clause | Alert fires immediately | Add `for: 2m` |
| 4 | Threshold may be too low | Noisy alerts | Tune based on baseline |

## Verification Queries

### Check Current Slow Query Rate
```promql
# New slow queries per second (current)
rate(mysql_global_status_slow_queries{dbinstance_identifier="aws-luckyus-isalescdp-rw"}[5m])

# New slow queries in last 5 minutes
rate(mysql_global_status_slow_queries{dbinstance_identifier="aws-luckyus-isalescdp-rw"}[5m]) * 300
```

### Check Baseline Rate
```promql
# Average slow queries per second over 24 hours
avg_over_time(
  rate(mysql_global_status_slow_queries{dbinstance_identifier="aws-luckyus-isalescdp-rw"}[5m])[24h:5m]
)
```

## Raw Data

### MySQL Status
```json
{
  "Slow_queries": "2034727",
  "Uptime": "29196081",
  "last_restart": "2025-03-10T09:32:40"
}
```

### Prometheus Comparison
```json
{
  "current_alert_expression": {
    "query": "avg_over_time(mysql_global_status_slow_queries[3m])",
    "value": 2034525,
    "interpretation": "WRONG - returns cumulative counter value"
  },
  "correct_expression": {
    "query": "rate(mysql_global_status_slow_queries[3m]) * 180",
    "value": 284,
    "interpretation": "CORRECT - new slow queries in 3 minutes"
  }
}
```

### Spike Period Rate Data (05:00-05:40 UTC)
```json
[
  {"time": "05:00", "new_queries_3min": 1},
  {"time": "05:01", "new_queries_3min": 415},
  {"time": "05:02", "new_queries_3min": 605},
  {"time": "05:03", "new_queries_3min": 612},
  {"time": "05:10", "new_queries_3min": 300},
  {"time": "05:11", "new_queries_3min": 648},
  {"time": "05:13", "new_queries_3min": 1421},
  {"time": "05:16", "new_queries_3min": 2177},
  {"time": "05:17", "new_queries_3min": 1983},
  {"time": "05:20", "new_queries_3min": 604},
  {"time": "05:25", "new_queries_3min": 130},
  {"time": "05:30", "new_queries_3min": 7}
]
```

# RDS Active Threads Alert - Incident Report
**Cluster:** aws-luckyus-iluckyhealth-rw (MySQL RDS)
**Alert Time:** 2026-02-11 (Duration: Self-resolved before investigation)
**Severity:** High
**Status:** Resolved (Alert cleared at time of investigation)

---

## Executive Summary

The RDS cluster `aws-luckyus-iluckyhealth-rw` triggered an alert for sustained high active threads (>24 for 2 minutes). Investigation revealed **extremely slow analytical queries** on large collection tables causing thread buildup. The alert self-resolved before DBA intervention, but root cause analysis identified critical performance issues requiring immediate optimization.

---

## Root Cause Analysis

### PRIMARY CAUSE: Slow Query Pileup on Unoptimized Analytics Queries

**Critical Findings:**

1. **Extreme Query Duration - Up to 96 Minutes**
   - `t_collect_shop_make_inter` GROUP BY query: **5,787 seconds (96 minutes)**
   - Examined: **20,722,827 rows** per execution
   - No supporting indexes for aggregation queries

2. **High-Frequency Slow Queries**
   - Time-bucketing query on `t_collect_shop_make_inter`: **7,625 executions**
   - Average duration: **118 seconds per query**
   - Total rows examined: **381,753,314 rows**
   - These queries were likely overlapping, causing thread accumulation

3. **Large Table Sizes Without Optimization**
   - `t_collect_order_tenant_inter`: 36.7M rows (8.8 GB)
   - `t_collect_shop_make_inter`: 27.5M rows (6.7 GB)
   - `t_collect_order_inter`: 12.3M rows (2.6 GB)
   - Total query load: **38.6 billion rows examined** across 20.4M executions

### SECONDARY FACTORS:
- ✅ No lock contention detected
- ✅ No metadata locks blocking DML
- ✅ No deadlocks in InnoDB status
- ✅ Connection distribution normal (9 total connections at investigation time)

---

## Affected Components

### Tables
- `t_collect_shop_make_inter` (27.5M rows) - **PRIMARY**
- `t_collect_order_inter` (12.3M rows)
- `t_collect_order_tenant_inter` (36.7M rows)
- `t_collect_payment_inter` (6.6M rows)
- `t_collect_shop_inter` (6.8M rows)

### Query Patterns
1. **Analytical GROUP BY aggregations** without indexes
2. **Time-range queries with date bucketing** (UNIX_TIMESTAMP calculations)
3. **DISTINCTROW queries** with sorting on metric_name columns
4. **Current-day aggregations** using `DATE(insert_time) = CURDATE()`

### Users/Applications
- **User:** `iluckyhealth_o` (application queries)
- **Database:** `luckyus_iluckyhealth`

---

## Actions Taken

### Immediate (During Investigation)
1. ✅ Confirmed alert self-resolved (Threads_running: 2, Threads_connected: 9)
2. ✅ No active long-running queries requiring termination
3. ✅ Collected performance schema diagnostics
4. ✅ Analyzed query patterns and table statistics

### Not Required
- No KILL commands needed (no queries >60 seconds active)
- No emergency parameter tuning required

---

## Follow-Up Items (CRITICAL - Action Required)

### 1. **URGENT: Index Optimization (P0)**

**Target: `t_collect_shop_make_inter` (27.5M rows)**
```sql
-- For GROUP BY metric_name queries
CREATE INDEX idx_metric_name_inserttime ON t_collect_shop_make_inter(metric_name, metric_name_comment, insert_time);

-- For time-range + metric filtering
CREATE INDEX idx_inserttime_metricname_value ON t_collect_shop_make_inter(insert_time, metric_name, metric_value);
```

**Target: `t_collect_order_inter` (12.3M rows)**
```sql
-- For daily aggregations with CURDATE()
CREATE INDEX idx_inserttime_metricname ON t_collect_order_inter(insert_time, metric_name, metric_value);

-- For channel/type analysis queries
CREATE INDEX idx_metric_inserttime ON t_collect_order_inter(metric_name, insert_time);
```

**Target: `t_collect_payment_inter` (6.6M rows)**
```sql
CREATE INDEX idx_metric_inserttime ON t_collect_payment_inter(metric_name, insert_time);
```

### 2. **Query Rewrite Recommendations (P0)**

**Replace:**
```sql
-- BAD: Full table scan with DATE() function
WHERE DATE(insert_time) = CURDATE()
```

**With:**
```sql
-- GOOD: Index-friendly range scan
WHERE insert_time >= CURDATE() AND insert_time < CURDATE() + INTERVAL 1 DAY
```

**For time bucketing, consider pre-computed materialized aggregations:**
```sql
-- Instead of real-time UNIX_TIMESTAMP() calculations on 27M rows
-- Create hourly/daily summary tables via scheduled jobs
```

### 3. **Application-Side Optimizations (P1)**

- **Implement query result caching** for repeated metric queries
- **Add pagination/limits** to analytical queries (avoid unbounded GROUP BY)
- **Schedule heavy analytics** during off-peak hours
- **Consider read replicas** for reporting queries

### 4. **Table Partitioning Strategy (P1)**

For tables with time-series data:
```sql
-- Partition by month/week to improve query pruning
ALTER TABLE t_collect_shop_make_inter
PARTITION BY RANGE (TO_DAYS(insert_time)) (
    PARTITION p202601 VALUES LESS THAN (TO_DAYS('2026-02-01')),
    PARTITION p202602 VALUES LESS THAN (TO_DAYS('2026-03-01')),
    ...
);
```

### 5. **Monitoring Enhancements (P2)**

- Add slow query log analysis (queries >5s)
- Set up alerts for:
  - Queries examining >1M rows
  - Individual query duration >60s
  - `Threads_running` spikes with query details

### 6. **Data Lifecycle Management (P2)**

- Implement data archival for `t_collect_*` tables older than 90 days
- Current growth rate: ~27M rows = 6.7GB per table
- Project: 300M+ rows per year without archival

---

## Performance Impact Assessment

| Metric | Before (During Alert) | After (Current) |
|--------|----------------------|-----------------|
| Threads Running | >24 (alert threshold) | 2 |
| Threads Connected | Unknown (likely >50) | 9 |
| Longest Query | 5,787 seconds | 0 seconds |
| Rows Examined (Total) | 38.6 billion | Minimal |

---

## Lessons Learned

1. **Analytical queries on OLTP databases without indexes cause severe performance degradation**
2. **Date function usage in WHERE clauses prevents index usage** (DATE(insert_time) vs. insert_time range)
3. **Large table aggregations require covering indexes** (metric_name + insert_time)
4. **Monitoring should include query-level metrics**, not just connection/thread counts

---

## Next Steps & Owners

| Action | Owner | Deadline | Status |
|--------|-------|----------|--------|
| Create indexes on t_collect_shop_make_inter | DBA Team | 2026-02-12 | 🔴 Pending |
| Rewrite CURDATE() queries | App Team (iLuckyHealth) | 2026-02-13 | 🔴 Pending |
| Implement query caching | App Team | 2026-02-15 | 🔴 Pending |
| Evaluate partitioning strategy | DBA Team | 2026-02-18 | 🔴 Pending |
| Set up enhanced monitoring | DevOps Team | 2026-02-20 | 🔴 Pending |

---

## Appendix: Query Examples

### Top 3 Slowest Queries

**1. Metric Aggregation on Shop Make (5787 seconds)**
```sql
SELECT DISTINCTROW metric_name, metric_name_comment,
       COUNT(*) AS record_count,
       MIN(insert_time) AS earliest,
       MAX(insert_time) AS latest
FROM luckyus_iluckyhealth.t_collect_shop_make_inter
GROUP BY metric_name, metric_name_comment
ORDER BY metric_name;
-- Rows examined: 20,722,827
-- Rows sent: 184
```

**2. Time Bucketing Query (118s average, 7625 executions)**
```sql
SELECT (UNIX_TIMESTAMP(insert_time) DIV ? * ?) DIV (? * ?) * (? * ?) AS ?,
       SUM(metric_count) AS ?
FROM t_collect_shop_make_inter
WHERE insert_time BETWEEN FROM_UNIXTIME(?) AND FROM_UNIXTIME(?)
  AND metric_name = ? AND metric_value = ?
GROUP BY ?
ORDER BY UNIX_TIMESTAMP(insert_time) DIV ? * ?;
-- Total rows examined: 381,753,314 (across all executions)
```

**3. Current Day Aggregation (78s average, 130 executions)**
```sql
SELECT SUM(metric_count) AS ?
FROM luckyus_iluckyhealth.t_collect_order_inter
WHERE metric_name = ? AND metric_value = ?
  AND DATE(insert_time) = CURDATE();
-- Total rows examined: 26,770,369 (across all executions)
```

---

**Report Generated:** 2026-02-11
**Investigated By:** DBA Team (Automated MCP Diagnostic)
**Severity Classification:** High (Self-resolved, but root cause remains)

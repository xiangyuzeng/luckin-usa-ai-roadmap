# RDS Metrics Report: aws-luckyus-isalescdp-rw

**Date**: 2026-02-11
**Time Range**: 04:00 - 07:00 UTC
**Instance**: aws-luckyus-isalescdp-rw (MySQL 8.0.40, db.t4g.micro)

## Executive Summary

**ALERT**: Significant activity spike detected between **05:00-05:25 UTC** with:
- CPU spike to **69.6%** (from baseline ~6%)
- Connections spike to **149** (from baseline ~35)
- Write IOPS spike to **1,052/sec** (from baseline ~10/sec)
- No deadlocks detected

## Metrics Summary

### CPU Utilization (%)

| Period | Average | Maximum | Status |
|--------|---------|---------|--------|
| 04:00-04:55 (Baseline) | 6.4% | 9.3% | Normal |
| **05:00-05:25 (Spike)** | **52.3%** | **69.6%** | **HIGH** |
| 05:30-07:00 (Recovery) | 6.4% | 9.2% | Normal |

**Peak**: 69.64% at 05:10 UTC

### Database Connections

| Period | Average | Maximum | Status |
|--------|---------|---------|--------|
| 04:00-04:55 (Baseline) | 34 | 54 | Normal |
| **05:00-05:25 (Spike)** | **103** | **149** | **HIGH** |
| 05:30-07:00 (Recovery) | 46 | 61 | Normal |

**Peak**: 149 connections at 05:10 UTC

### Read IOPS

| Period | Average | Maximum | Status |
|--------|---------|---------|--------|
| 04:00-04:55 (Baseline) | 38 | 123 | Normal |
| **05:00-05:25 (Spike)** | **207** | **350** | **HIGH** |
| 05:30-07:00 (Recovery) | 37 | 82 | Normal |

**Peak**: 349.9 IOPS at 05:00 UTC

### Write IOPS

| Period | Average | Maximum | Status |
|--------|---------|---------|--------|
| 04:00-04:55 (Baseline) | 8 | 19 | Normal |
| **05:00-05:25 (Spike)** | **769** | **1,053** | **CRITICAL** |
| 05:30-07:00 (Recovery) | 7 | 21 | Normal |

**Peak**: 1,052.9 IOPS at 05:20 UTC

### Deadlocks

**Status**: None detected during the period

## Detailed Timeline

```
Time (UTC)   CPU%     Connections   ReadIOPS   WriteIOPS
---------    -----    -----------   --------   ---------
04:00        7.1%     36            54         9
04:30        6.3%     30            32         5
05:00        22.8%    71            154        278       ← Start of spike
05:05        52.8%    97            177        880       ← Escalation
05:10        67.6%    132           283        911       ← Peak CPU/Connections
05:15        62.3%    119           286        921       ← Peak Read IOPS
05:20        52.1%    96            220        1020      ← Peak Write IOPS
05:25        16.0%    59            121        255       ← Recovery begins
05:30        7.1%     44            63         6         ← Back to normal
06:00        6.9%     48            38         10
06:30        6.5%     45            38         4
07:00        6.0%     47            36         8
```

## Analysis

### Root Cause Indicators

1. **Write-Heavy Workload**: Write IOPS spiked to 1,052/sec (100x baseline), indicating:
   - Bulk data import/ETL job
   - Batch processing operation
   - Large transaction commit

2. **Connection Surge**: 4x increase in connections suggests:
   - Application scale-out event
   - Batch job spawning multiple workers
   - Connection pool exhaustion recovery

3. **CPU Correlation**: CPU directly correlated with IOPS, indicating I/O-bound processing

### Instance Capacity Assessment

| Resource | Capacity | Peak Usage | Headroom |
|----------|----------|------------|----------|
| CPU | 100% | 69.6% | 30.4% |
| IOPS (provisioned) | 3,000 | 1,403 | 53% |
| Connections (t4g.micro) | ~85* | 149 | **EXCEEDED** |

*db.t4g.micro has limited max_connections (~85 default for 1GB RAM)

### Recommendations

1. **Investigate 05:00-05:25 UTC Activity**
   - Check application logs for scheduled jobs
   - Review slow query logs during this period
   - Identify the source of bulk writes

2. **Connection Pool Review**
   - 149 connections exceeds typical t4g.micro limits
   - Consider connection pooling (RDS Proxy or PgBouncer equivalent)
   - Or upgrade instance class if connections are legitimate

3. **Instance Sizing**
   - db.t4g.micro may be undersized for this workload
   - Consider db.t4g.small or db.t4g.medium for more headroom

## Raw Data

### CPU Utilization (Full Dataset)
```json
[
  {"Timestamp": "2026-02-11T04:00:00Z", "Average": 7.14, "Maximum": 9.17},
  {"Timestamp": "2026-02-11T04:05:00Z", "Average": 6.45, "Maximum": 7.83},
  {"Timestamp": "2026-02-11T04:10:00Z", "Average": 7.15, "Maximum": 9.29},
  {"Timestamp": "2026-02-11T04:15:00Z", "Average": 6.37, "Maximum": 7.43},
  {"Timestamp": "2026-02-11T04:20:00Z", "Average": 6.36, "Maximum": 7.08},
  {"Timestamp": "2026-02-11T04:25:00Z", "Average": 6.32, "Maximum": 6.85},
  {"Timestamp": "2026-02-11T04:30:00Z", "Average": 6.28, "Maximum": 7.61},
  {"Timestamp": "2026-02-11T04:35:00Z", "Average": 5.98, "Maximum": 6.70},
  {"Timestamp": "2026-02-11T04:40:00Z", "Average": 6.14, "Maximum": 6.72},
  {"Timestamp": "2026-02-11T04:45:00Z", "Average": 6.44, "Maximum": 6.96},
  {"Timestamp": "2026-02-11T04:50:00Z", "Average": 6.04, "Maximum": 6.45},
  {"Timestamp": "2026-02-11T04:55:00Z", "Average": 6.74, "Maximum": 7.94},
  {"Timestamp": "2026-02-11T05:00:00Z", "Average": 22.85, "Maximum": 61.74},
  {"Timestamp": "2026-02-11T05:05:00Z", "Average": 52.84, "Maximum": 60.80},
  {"Timestamp": "2026-02-11T05:10:00Z", "Average": 67.60, "Maximum": 69.64},
  {"Timestamp": "2026-02-11T05:15:00Z", "Average": 62.29, "Maximum": 65.31},
  {"Timestamp": "2026-02-11T05:20:00Z", "Average": 52.12, "Maximum": 63.97},
  {"Timestamp": "2026-02-11T05:25:00Z", "Average": 16.02, "Maximum": 39.58},
  {"Timestamp": "2026-02-11T05:30:00Z", "Average": 7.12, "Maximum": 8.06},
  {"Timestamp": "2026-02-11T05:35:00Z", "Average": 6.89, "Maximum": 8.22},
  {"Timestamp": "2026-02-11T05:40:00Z", "Average": 6.37, "Maximum": 7.27},
  {"Timestamp": "2026-02-11T05:45:00Z", "Average": 6.40, "Maximum": 7.38},
  {"Timestamp": "2026-02-11T05:50:00Z", "Average": 6.46, "Maximum": 7.17},
  {"Timestamp": "2026-02-11T05:55:00Z", "Average": 6.53, "Maximum": 7.10},
  {"Timestamp": "2026-02-11T06:00:00Z", "Average": 6.92, "Maximum": 9.23},
  {"Timestamp": "2026-02-11T06:05:00Z", "Average": 6.31, "Maximum": 6.90},
  {"Timestamp": "2026-02-11T06:10:00Z", "Average": 6.12, "Maximum": 6.79},
  {"Timestamp": "2026-02-11T06:15:00Z", "Average": 6.53, "Maximum": 8.06},
  {"Timestamp": "2026-02-11T06:20:00Z", "Average": 6.33, "Maximum": 7.00},
  {"Timestamp": "2026-02-11T06:25:00Z", "Average": 6.29, "Maximum": 7.25},
  {"Timestamp": "2026-02-11T06:30:00Z", "Average": 6.45, "Maximum": 7.77},
  {"Timestamp": "2026-02-11T06:35:00Z", "Average": 6.10, "Maximum": 6.50},
  {"Timestamp": "2026-02-11T06:40:00Z", "Average": 5.66, "Maximum": 6.31},
  {"Timestamp": "2026-02-11T06:45:00Z", "Average": 6.06, "Maximum": 7.25},
  {"Timestamp": "2026-02-11T06:50:00Z", "Average": 6.23, "Maximum": 6.41},
  {"Timestamp": "2026-02-11T06:55:00Z", "Average": 6.02, "Maximum": 6.39}
]
```

### Database Connections (Full Dataset)
```json
[
  {"Timestamp": "2026-02-11T04:00:00Z", "Average": 36, "Maximum": 44},
  {"Timestamp": "2026-02-11T04:05:00Z", "Average": 35, "Maximum": 39},
  {"Timestamp": "2026-02-11T04:10:00Z", "Average": 38, "Maximum": 45},
  {"Timestamp": "2026-02-11T04:15:00Z", "Average": 36, "Maximum": 39},
  {"Timestamp": "2026-02-11T04:20:00Z", "Average": 39, "Maximum": 54},
  {"Timestamp": "2026-02-11T04:25:00Z", "Average": 30, "Maximum": 34},
  {"Timestamp": "2026-02-11T04:30:00Z", "Average": 30, "Maximum": 37},
  {"Timestamp": "2026-02-11T04:35:00Z", "Average": 30, "Maximum": 35},
  {"Timestamp": "2026-02-11T04:40:00Z", "Average": 34, "Maximum": 41},
  {"Timestamp": "2026-02-11T04:45:00Z", "Average": 38, "Maximum": 40},
  {"Timestamp": "2026-02-11T04:50:00Z", "Average": 34, "Maximum": 40},
  {"Timestamp": "2026-02-11T04:55:00Z", "Average": 28, "Maximum": 34},
  {"Timestamp": "2026-02-11T05:00:00Z", "Average": 71, "Maximum": 98},
  {"Timestamp": "2026-02-11T05:05:00Z", "Average": 97, "Maximum": 117},
  {"Timestamp": "2026-02-11T05:10:00Z", "Average": 132, "Maximum": 149},
  {"Timestamp": "2026-02-11T05:15:00Z", "Average": 119, "Maximum": 144},
  {"Timestamp": "2026-02-11T05:20:00Z", "Average": 96, "Maximum": 109},
  {"Timestamp": "2026-02-11T05:25:00Z", "Average": 59, "Maximum": 68},
  {"Timestamp": "2026-02-11T05:30:00Z", "Average": 44, "Maximum": 58},
  {"Timestamp": "2026-02-11T05:35:00Z", "Average": 51, "Maximum": 61},
  {"Timestamp": "2026-02-11T05:40:00Z", "Average": 47, "Maximum": 50},
  {"Timestamp": "2026-02-11T05:45:00Z", "Average": 45, "Maximum": 49},
  {"Timestamp": "2026-02-11T05:50:00Z", "Average": 48, "Maximum": 50},
  {"Timestamp": "2026-02-11T05:55:00Z", "Average": 45, "Maximum": 51},
  {"Timestamp": "2026-02-11T06:00:00Z", "Average": 48, "Maximum": 51},
  {"Timestamp": "2026-02-11T06:05:00Z", "Average": 47, "Maximum": 53},
  {"Timestamp": "2026-02-11T06:10:00Z", "Average": 45, "Maximum": 53},
  {"Timestamp": "2026-02-11T06:15:00Z", "Average": 53, "Maximum": 56},
  {"Timestamp": "2026-02-11T06:20:00Z", "Average": 50, "Maximum": 60},
  {"Timestamp": "2026-02-11T06:25:00Z", "Average": 47, "Maximum": 60},
  {"Timestamp": "2026-02-11T06:30:00Z", "Average": 45, "Maximum": 50},
  {"Timestamp": "2026-02-11T06:35:00Z", "Average": 44, "Maximum": 53},
  {"Timestamp": "2026-02-11T06:40:00Z", "Average": 41, "Maximum": 46},
  {"Timestamp": "2026-02-11T06:45:00Z", "Average": 40, "Maximum": 47},
  {"Timestamp": "2026-02-11T06:50:00Z", "Average": 50, "Maximum": 56},
  {"Timestamp": "2026-02-11T06:55:00Z", "Average": 47, "Maximum": 51}
]
```

### Deadlocks
```json
{
  "Label": "Deadlocks",
  "Datapoints": []
}
```
No deadlocks detected during the monitoring period.

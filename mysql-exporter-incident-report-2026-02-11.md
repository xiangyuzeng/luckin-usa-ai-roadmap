# Incident Report: MySQL Exporter Alert - db-aws-luckyus-isalescdp

**Incident ID:** INC-2026-0211-MYSQL-EXPORTER
**Date:** 2026-02-11
**Status:** RESOLVED
**Severity:** Medium

---

## Executive Summary

The Prometheus alert `up{job=~".*exporter.*"} == 0` triggered for MySQL exporter job `db-aws-luckyus-isalescdp` due to an RDS MySQL instance restart/failover event. The exporter experienced scrape timeouts for approximately 16 minutes before automatically recovering once MySQL became available again.

---

## Root Cause Analysis

**Primary Cause:** AWS RDS MySQL instance restart/failover

**Evidence:**

| Metric | Before Incident | During Incident | After Recovery |
|--------|----------------|-----------------|----------------|
| `mysql_global_status_uptime` | 29,222,715 sec (338 days) | Reset to 66 sec | Currently ~4,127 sec |
| `scrape_duration_seconds` | ~0.1 sec | 10 sec (timeout) | ~0.1 sec |
| `up` | 1 | 0 | 1 |
| `mysql_up` | 1 | 0 | 1 |

**Technical Details:**
- Job: `db-aws-luckyus-isalescdp`
- Instance: `10.238.3.136:9154`
- Prometheus Datasource: UMBQuerier-Luckin
- MySQL Version: 8.0.40
- Database Type: AWS RDS MySQL

The uptime reset from 338 days to ~66 seconds confirms the MySQL server underwent a restart at approximately **15:14:54 UTC**.

---

## Impact Scope

### Monitoring Gaps During Outage
- MySQL performance metrics unavailable for ~16 minutes
- Query statistics, connection counts, and throughput metrics missing
- No visibility into MySQL health during restart window

### Affected Grafana Dashboards
- MySQL Enterprise Monitoring Dashboard (UID: Qf9gQHZVz)
- Any custom dashboards querying `db-aws-luckyus-isalescdp` job

### Alert Blind Spots
- During the 16-minute window, no MySQL-specific alerts could fire
- Connection issues, slow queries, or performance degradation would have gone undetected
- Only the `up == 0` alert provided visibility into the outage

### Fleet Impact
- Analysis revealed this was a **fleet-wide event** - multiple MySQL instances across the `custom-scrape-iprod-us` namespace showed uptime changes during the same timeframe
- This suggests a coordinated maintenance window or AWS infrastructure event

---

## Timeline

| Time (UTC) | Event |
|------------|-------|
| ~14:59:00 | Scrape duration begins increasing, exporter starts experiencing timeouts |
| ~14:59:00 | `up{job="db-aws-luckyus-isalescdp"}` transitions to 0 |
| ~14:59-15:14 | MySQL unavailable, exporter scrapes timing out at 10s |
| 15:14:54 | RDS MySQL restart completes, server becomes available |
| ~15:15:00 | Exporter successfully reconnects, `up` returns to 1 |
| ~15:15:00 | Alert auto-resolves |

**Total Duration:** ~16 minutes

---

## Resolution Steps

1. **No manual intervention required** - The exporter automatically recovered once MySQL became available
2. **Verification performed:**
   - Confirmed `up=1` and `mysql_up=1` via Prometheus queries
   - Verified MySQL connectivity via gateway (responding normally)
   - Checked MySQL status: 62 threads connected, 3 running, 0 aborted connections
   - Confirmed scrape duration returned to normal (~0.1s)

---

## Prevention Measures

### Immediate Actions
1. **Configure RDS Event Notifications** - Set up SNS notifications for RDS maintenance events to provide advance warning
2. **Add Maintenance Window Awareness** - Suppress alerts during planned AWS maintenance windows
3. **Implement Exporter Resilience** - Consider configuring exporter retry logic with shorter timeout intervals

### Recommended Follow-up Actions

#### 1. Fleet Audit
- Audit all mysqld_exporter instances across the fleet for consistent configuration
- Verify all exporters have appropriate timeout and retry settings
- Ensure `monitor_exporter` user has minimal required privileges across all instances

#### 2. Alert Enhancement
- Add `for: 5m` duration to `up == 0` alerts to reduce noise from brief connectivity blips
- Create separate alert for extended outages (>15m) with higher severity
- Implement predictive alerting on `scrape_duration_seconds` trending upward

#### 3. Dashboard Improvements
- Add RDS event correlation to MySQL dashboards
- Display `mysql_global_status_uptime` to quickly identify recent restarts
- Add fleet-wide uptime comparison panel

#### 4. Documentation
- Document expected behavior during RDS maintenance/failover
- Create runbook for MySQL exporter troubleshooting
- Update on-call escalation procedures for database-related alerts

---

## Current Status

| Check | Status |
|-------|--------|
| Exporter Up | **HEALTHY** |
| MySQL Connectivity | **HEALTHY** |
| Scrape Duration | **NORMAL** (~0.1s) |
| Active Connections | 62 threads |
| Aborted Connections | 0 |

---

## Lessons Learned

1. The alert correctly detected the MySQL unavailability - monitoring worked as designed
2. RDS restarts/failovers are expected to cause brief exporter outages
3. Fleet-wide maintenance events should be communicated in advance to reduce alert fatigue
4. The 16-minute outage window represents acceptable recovery time for RDS failover

---

## Investigation Queries Used

```promql
# Check exporter status
up{job="db-aws-luckyus-isalescdp"}

# Check MySQL connectivity from exporter perspective
mysql_up{job="db-aws-luckyus-isalescdp"}

# Check scrape duration for timeout detection
scrape_duration_seconds{job="db-aws-luckyus-isalescdp"}

# Check MySQL uptime for restart detection
mysql_global_status_uptime{job="db-aws-luckyus-isalescdp"}

# Fleet-wide restart detection
changes(mysql_global_status_uptime{namespace="custom-scrape-iprod-us"}[3h]) > 0
```

---

**Report Generated:** 2026-02-11
**Investigator:** Claude Code DBA Assistant

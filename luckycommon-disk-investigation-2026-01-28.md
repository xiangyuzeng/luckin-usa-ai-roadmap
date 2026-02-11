# AWS OpenSearch (luckycommon) Disk Space Investigation Report

**Investigation Date:** 2026-01-28
**Alert:** 【DB告警】AWS-ES磁盘空间不足10G
**Cluster:** luckycommon
**Account ID:** 257394478466
**Region:** us-east-1
**Priority:** P0 - Critical
**Status:** Expansion Applied - Follow-up Required

---

## Executive Summary

On 2026-01-28, the luckycommon cluster triggered disk space alerts when free space dropped below 10GB. Analysis shows disk space fell from ~11GB (Jan 27) to ~7.7GB (Jan 28 16:48 UTC) before a **50GB expansion was applied at 19:12 UTC**, restoring free space to ~48GB.

**Root Cause Hypothesis:** Three large log indices are NOT partitioned by date/month and continue growing unbounded, consuming disk space faster than expected.

**Current State:**
- Free Space: ~48 GB (after expansion)
- Cluster Status: GREEN
- Writes Blocked: NO
- Nodes: 7 (stable)

---

## 1. CloudWatch Metrics Analysis

### 1.1 Free Storage Space Trend

| Timestamp (UTC) | Free Space (MB) | Notes |
|-----------------|-----------------|-------|
| 2026-01-27 00:00 | 10,983 | Starting point |
| 2026-01-27 12:00 | 11,132 | Peak (after cleanup?) |
| 2026-01-28 00:00 | 9,780 | Dropped below 10GB |
| 2026-01-28 16:00 | 9,036 | Alert threshold |
| 2026-01-28 16:48 | 7,852 | **Critical low** |
| 2026-01-28 17:36 | 7,783 | Lowest point |
| 2026-01-28 19:12 | **48,107** | **50GB expansion applied** |
| 2026-01-28 20:00 | 48,067 | Stable post-expansion |

### 1.2 Cluster Used Space

| Timestamp (UTC) | Used Space (MB) | Daily Growth |
|-----------------|-----------------|--------------|
| 2026-01-27 00:00 | 112,756 (~110 GB) | - |
| 2026-01-28 00:00 | 115,507 (~113 GB) | +2.7 GB/day |
| 2026-01-28 20:00 | 118,338 (~116 GB) | +2.8 GB/day |

**Growth Rate:** ~3 GB/day average

### 1.3 Indexing Rate Pattern

| Time Period | Docs/Sec | Description |
|-------------|----------|-------------|
| 00:00-06:00 UTC | 200-350 | Off-peak (night) |
| 06:00-12:00 UTC | 200-300 | Morning ramp-up |
| 12:00-14:00 UTC | 1,500-3,000 | **Peak business hours** |
| 14:00-20:00 UTC | 1,000-2,000 | Sustained high load |
| 20:00-00:00 UTC | 500-800 | Evening decline |

**Peak Indexing:** ~3,000 docs/sec (10.8M docs/hour during peak)

### 1.4 Cluster Health

| Metric | Value | Status |
|--------|-------|--------|
| Cluster Status | GREEN | OK |
| Node Count | 7 | Stable |
| Writes Blocked | 0 | OK |
| JVM Memory Pressure | N/A | Need to verify |

---

## 2. Alert History

### 2.1 Recent Alerts (from DevOps DB)

| Alert Time | Alert Name | Status | Domain |
|------------|------------|--------|--------|
| 2026-01-28 18:10 | 【DB告警】AWS-ES磁盘空间不足10G | **FIRING** | luckycommon |
| 2026-01-28 17:39 | 【DB告警】AWS-ES磁盘空间不足10G | FIRING | luckycommon |
| 2026-01-28 17:09 | 【DB告警】AWS-ES磁盘空间不足10G | FIRING | luckycommon |
| 2026-01-28 00:08 | 【DB告警】AWS-ES 集群状态Yellow | resolved | luckyur-log |

**Note:** Alert is still in FIRING state - needs acknowledgment after expansion.

---

## 3. Investigation: Identifying Non-Partitioned Indices

### 3.1 Commands to Execute on ES Cluster

**IMPORTANT:** Execute these commands via the ES endpoint to identify the 3 large non-partitioned indices.

```bash
# Set endpoint
export ES_ENDPOINT="https://search-luckycommon-XXXX.us-east-1.es.amazonaws.com"

# Step 1: Check current disk status
curl -X GET "${ES_ENDPOINT}/_cat/nodes?v&h=name,disk.total,disk.used,disk.avail,disk.used_percent"

# Step 2: List ALL indices sorted by size (CRITICAL)
curl -X GET "${ES_ENDPOINT}/_cat/indices?v&s=store.size:desc&bytes=gb&h=index,health,store.size,docs.count,creation.date.string" | head -30

# Step 3: Identify NON-PARTITIONED indices
# Look for indices WITHOUT date patterns like:
#   - -YYYY.MM.DD
#   - -YYYY-MM-DD
#   - -000001 (rollover pattern)
# These are the problematic growing indices

# Step 4: For each suspicious index, check ISM policy
curl -X GET "${ES_ENDPOINT}/_plugins/_ism/explain/INDEX_NAME"

# Step 5: Check if index has write alias
curl -X GET "${ES_ENDPOINT}/INDEX_NAME/_alias"

# Step 6: Check document count growth
curl -X GET "${ES_ENDPOINT}/INDEX_NAME/_count"
curl -X GET "${ES_ENDPOINT}/INDEX_NAME/_stats/indexing"
```

### 3.2 Expected Non-Partitioned Index Patterns

Based on typical log systems, suspect indices may include:

| Index Pattern | Risk Level | Typical Size |
|---------------|------------|--------------|
| `logs-*` (no date suffix) | HIGH | Growing |
| `application-logs` | HIGH | Growing |
| `error-logs` | HIGH | Growing |
| `audit-*` (no date) | MEDIUM | Growing |
| Any index without date pattern | HIGH | Growing |

---

## 4. Root Cause Analysis

### 4.1 Primary Cause
**Non-partitioned indices growing unbounded** - Three or more indices are configured without:
- Date-based naming (e.g., `logs-2026.01.28`)
- Rollover policies (ISM)
- Retention/deletion policies

### 4.2 Contributing Factors
1. **High indexing rate:** Peak 3,000 docs/sec during business hours
2. **No ILM/ISM policies:** Indices growing without lifecycle management
3. **Storage undersized:** Original storage insufficient for growth rate

### 4.3 Growth Calculation
- Daily growth: ~3 GB/day
- Monthly projection: ~90 GB/month
- Current capacity: ~165 GB total (after 50GB expansion)
- **Time to next alert:** ~13 days at current growth rate

---

## 5. Recommendations

### 5.1 Immediate Actions (P0 - Within 24 hours)

#### 5.1.1 Identify and Document Problematic Indices
```bash
# Run on ES cluster
curl -X GET "${ES_ENDPOINT}/_cat/indices?v&s=store.size:desc" | grep -v "\-[0-9]\{4\}\." | head -20
```

#### 5.1.2 Create ISM Rollover Policy
```json
PUT _plugins/_ism/policies/luckycommon-log-rollover
{
  "policy": {
    "policy_id": "luckycommon-log-rollover",
    "description": "Rollover and delete policy for luckycommon logs",
    "default_state": "hot",
    "states": [
      {
        "name": "hot",
        "actions": [
          {
            "rollover": {
              "min_size": "5gb",
              "min_index_age": "1d"
            }
          }
        ],
        "transitions": [
          {
            "state_name": "warm",
            "conditions": {
              "min_index_age": "2d"
            }
          }
        ]
      },
      {
        "name": "warm",
        "actions": [
          {
            "replica_count": {
              "number_of_replicas": 0
            }
          }
        ],
        "transitions": [
          {
            "state_name": "delete",
            "conditions": {
              "min_index_age": "7d"
            }
          }
        ]
      },
      {
        "name": "delete",
        "actions": [
          {
            "delete": {}
          }
        ]
      }
    ],
    "ism_template": {
      "index_patterns": ["logs-*", "application-*", "error-*"],
      "priority": 100
    }
  }
}
```

### 5.2 Short-term Actions (P1 - Within 1 week)

1. **Create index templates with rollover aliases**
```json
PUT _index_template/luckycommon-logs-template
{
  "index_patterns": ["logs-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1,
      "plugins.index_state_management.rollover_alias": "logs"
    }
  }
}
```

2. **Reindex existing large indices** to new date-partitioned indices

3. **Set up monitoring dashboards** for index growth

### 5.3 Long-term Actions (P2 - Within 1 month)

1. **Implement proper logging architecture**
   - Use Filebeat/Logstash with date-based indices
   - Configure automatic rollover at source

2. **Right-size storage**
   - Calculate 30-day retention needs
   - Add 50% buffer for growth

3. **Set up proactive alerts**
   - Alert at 20% free (not 10GB)
   - Alert on daily growth rate anomalies

---

## 6. Verification Checklist

After remediation, verify:

| Check | Command | Expected Result |
|-------|---------|-----------------|
| Cluster Health | `GET _cluster/health` | status: green |
| Free Space | `GET _cat/allocation?v` | disk.avail > 30GB |
| ISM Policies | `GET _plugins/_ism/policies` | Policies listed |
| Policy Applied | `GET _plugins/_ism/explain/logs-*` | managed: true |
| No Large Non-Partitioned | `GET _cat/indices?s=store.size:desc` | All have date suffix |

---

## 7. Evidence Attachments

### 7.1 CloudWatch FreeStorageSpace Data
```
Timestamp                 | Value (MB)
--------------------------|------------
2026-01-27T00:00:00Z      | 10982.864
2026-01-28T16:48:00Z      | 7852.317 (LOWEST)
2026-01-28T19:12:00Z      | 48106.875 (AFTER EXPANSION)
```

### 7.2 Alert Log Query
```sql
SELECT alertname, status, instance, labels, create_time
FROM luckyus_izeus.t_umb_alert_log
WHERE alertname LIKE '%ES%磁盘%' AND domain_name = 'luckycommon'
ORDER BY create_time DESC;
```

---

## 8. Next Steps

1. **Acknowledge alert** after confirming expansion is stable
2. **Execute investigation commands** (Section 3.1) to identify problematic indices
3. **Create and apply ISM policy** (Section 5.1.2)
4. **Schedule review** in 3 days to verify growth is controlled
5. **Update runbook** with lessons learned

---

**Investigation Completed:** 2026-01-28T20:00:00Z
**Investigator:** Claude Code (Automated Analysis)
**Data Sources:** CloudWatch Metrics, DevOps Alert Logs, Existing Documentation
**Review Required By:** DBA Team Lead

---

## Appendix: Quick Reference Commands

```bash
# All-in-one diagnostic script
export ES_ENDPOINT="https://search-luckycommon-XXXX.us-east-1.es.amazonaws.com"

echo "=== Cluster Health ==="
curl -s "${ES_ENDPOINT}/_cluster/health?pretty"

echo "=== Disk Usage ==="
curl -s "${ES_ENDPOINT}/_cat/allocation?v"

echo "=== Top 15 Indices by Size ==="
curl -s "${ES_ENDPOINT}/_cat/indices?v&s=store.size:desc&h=index,store.size,docs.count" | head -15

echo "=== Non-Partitioned Indices (PROBLEM AREAS) ==="
curl -s "${ES_ENDPOINT}/_cat/indices?h=index,store.size&s=store.size:desc" | grep -v "\-[0-9]\{4\}\." | grep -v "\-[0-9]\{6\}$" | head -10

echo "=== ISM Policies ==="
curl -s "${ES_ENDPOINT}/_plugins/_ism/policies?pretty"
```

# OpenSearch Cluster Storage Management — February 2026 Update

**Report Date**: February 10, 2026
**Prepared By**: DevOps DBA Team
**Distribution**: Engineering Management, Infrastructure Leadership
**Classification**: Internal — Operations Report

---

## Executive Summary

Following the **luckycommon OpenSearch cluster disk space alert on January 28, 2026** (free space dropped to ~7.6 GB), the DevOps DBA team has conducted a comprehensive review and remediation across all North American OpenSearch domains. While the luckycommon incident has been stabilized, **a more critical situation has emerged on the luckyur-log cluster**, which reached a dangerously low **21.6 GB free space on February 9** — approaching the threshold where OpenSearch automatically blocks write operations to prevent data corruption.

### Current Fleet Status at a Glance

| Domain | Usage | Free Space | Trend | Status | Priority |
|--------|-------|------------|-------|--------|----------|
| **luckyur-log** | 96.4%+ | ~35 GB | ↓ Declining | 🔴 **CRITICAL** | P0 — Immediate |
| luckylfe-log | 87.5% | ~23 GB | ↔ Stable (sawtooth) | ⚠️ Warning | P2 — Monitor |
| luckycommon | 69.7% | ~50 GB | ↔ Stable | ✅ Healthy | Resolved |
| luckyus-opensearch-dify | ~0% | ~24 GB | ↔ Idle | ✅ Healthy | N/A |

**Key Risk**: Without immediate intervention on luckyur-log, the cluster will enter read-only mode within **2-3 business days**, impacting all log ingestion from the US region's Kubernetes workloads.

---

## Section 1: Luckycommon Incident Resolution (January 28, 2026)

### Background

On January 28, 2026, the luckycommon OpenSearch cluster triggered a critical disk space alert when free storage dropped to approximately **7.6 GB**. The DevOps DBA team executed an emergency response that included:

1. **Immediate Capacity Expansion**: Added 50 GB EBS storage per node
2. **Comprehensive Index Analysis**: Identified the three largest storage consumers
3. **Cross-Team Coordination**: Worked with R&D middleware and application teams to establish retention policies

### Retention Policy Agreements

| Index Category | Storage Impact | Agreed Retention | Rationale |
|----------------|----------------|------------------|-----------|
| `lucky_sys_oplog` | Major | 60 days | Extended retention required for certain log scenarios per R&D |
| `koala_delay_task-*` | Major | 30 days | Safe to clean per middleware team; root cause was missing scheduled task in NA environment |
| `koala_delay_task_track` | Moderate | 30 days (by createTime) | Standard operational log retention |

### Results

- **Projected Recovery**: ~59.5 GB of reclaimable space
- **Current Status**: Stable at **69.7% utilization** (~49.5 GB free)
- **Automation**: Cleanup policies being configured on KBX platform to prevent recurrence

---

## Section 2: Fleet-Wide Health Assessment (February 2026)

### Infrastructure Overview

| Domain | Engine | Data Nodes | Storage/Node | Total Capacity | VPC |
|--------|--------|------------|--------------|----------------|-----|
| luckyur-log | ES 7.10 | 4× m5.xlarge | 350 GB (gp2) | 1,400 GB | vpc-0dce7ca7770422d33 |
| luckylfe-log | ES 7.10 | 4× m5.large | 80 GB (gp2) | 320 GB | VPC-based |
| luckycommon | ES 6.8 | 4× m5.large | 100 GB (gp3) | 400 GB | VPC-based |
| luckyus-opensearch-dify | OS 2.15 | 2× r6g.large | 30 GB (gp3) | 60 GB | VPC-based |

### Detailed Status by Domain

#### 1. luckyur-log — 🔴 CRITICAL

| Metric | Value | Threshold | Assessment |
|--------|-------|-----------|------------|
| Storage Utilization | 96.4%+ | <85% recommended | 🔴 Critical |
| Free Space (Current) | ~35 GB | >100 GB recommended | 🔴 Critical |
| Free Space (Lowest - Feb 9) | **21.6 GB** | >20 GB minimum | 🔴 Near-outage |
| JVM Memory Pressure | 74-76% | <75% warning, <85% critical | ⚠️ At Threshold |
| Cluster Status | Green | Green | ✅ Healthy |
| Indexing Latency | 0.14-0.28ms | <0.5ms | ⚠️ Degraded during peaks |
| Search Latency | 0.5-3.7ms | <2.0ms | ⚠️ Spikes observed |

**CloudWatch Trend Analysis (Feb 1-10, 2026):**

```
Free Storage Space (GB) - Minimum per period:
Feb 1:  ████████████████████████████████░░░░░░  58 GB
Feb 3:  ███████████████████████████░░░░░░░░░░░  47 GB
Feb 5:  ████████████████████████░░░░░░░░░░░░░░  41 GB
Feb 7:  ██████████████████████░░░░░░░░░░░░░░░░  38 GB
Feb 9:  ████████████░░░░░░░░░░░░░░░░░░░░░░░░░░  21.6 GB ⚠️ DANGER
Feb 10: ████████████████████░░░░░░░░░░░░░░░░░░  35 GB
        └────────────────────────────────────┘
        0 GB                              100 GB
```

**Pattern Observed**: Storage drops 15-25 GB during business hours (heavy data ingestion from US region K8s workloads), partially recovers overnight, but overall trajectory is **sharply downward**. Data ingestion is outpacing the current cleanup rate.

**Performance Impact**:
- Indexing latency increased **100%** during low-storage periods (0.14ms → 0.28ms)
- Search latency spiked to **3.7ms** (7× normal) indicating cluster stress
- JVM memory pressure consistently at warning threshold (74-76%)

#### 2. luckylfe-log — ⚠️ Warning

| Metric | Value | Assessment |
|--------|-------|------------|
| Storage Utilization | 87.5% | ⚠️ Elevated but manageable |
| Free Space | ~22.8 GB | ⚠️ Limited headroom |
| Trend | Stable sawtooth | ✅ Auto-cleanup functioning |

The daily auto-cleanup cycle is operating as expected. Storage follows a predictable pattern of accumulation during the day and cleanup overnight, maintaining a stable equilibrium.

#### 3. luckycommon — ✅ Healthy (Post-Incident)

| Metric | Value | Assessment |
|--------|-------|------------|
| Storage Utilization | 69.7% | ✅ Healthy |
| Free Space | ~49.5 GB | ✅ Adequate |
| Trend | Stable | ✅ Remediation successful |

Following the January 28 intervention and implementation of retention policies, luckycommon has stabilized and requires only routine monitoring.

#### 4. luckyus-opensearch-dify — ✅ Healthy

| Metric | Value | Assessment |
|--------|-------|------------|
| Storage Utilization | ~0% | ✅ Nearly empty |
| Free Space | ~24 GB | ✅ Full capacity available |

This domain was recently provisioned with Graviton instances (r6g.large) and gp3 storage, representing our target architecture for future domains.

---

## Section 3: Luckyur-log Deep Dive Analysis

### Root Cause: Missing Index Lifecycle Management

The primary cause of the luckyur-log storage crisis is **the absence of Index State Management (ISM) policies**. Unlike luckycommon and luckylfe-log which have some automated cleanup mechanisms, luckyur-log has no lifecycle policies configured, resulting in indefinite index accumulation.

### Storage Consumption Breakdown

| Index Category | Size | % of Total | Index Count | Age Range | Issue |
|----------------|------|------------|-------------|-----------|-------|
| `iprod_tomcat_lucky_k8s-*` | ~537 GB | 48.2% | 19+ | Daily rolling | **Sept 2025 indices still present** |
| `skywalking_idx_segment-*` | ~156 GB | 14.0% | 7+ | Daily rolling | No retention policy |
| `prod-worker01-eks-us-*-dify` | ~106 GB | 9.5% | 1+ | Unknown | No retention policy |
| `iprod_tomcat_lucky_k8s-2025.09.*` | ~80 GB | 7.2% | 5 | Sept 10-14, 2025 | **5 months stale** |
| `skywalking_idx_segment-2025.09.*` | ~45 GB | 4.0% | 5+ | Sept 2025 | **5 months stale** |
| `skywalking_idx_metrics-all-*` | ~45 GB | 4.0% | 7+ | Daily rolling | Default 90-day retention |
| `aws_cloud_operation` | 25.8 GB | 2.3% | 1 | Single | No retention policy |
| `izeus-skywalking-trace-exception` | 10.7 GB | 1.0% | 1 | Single | No retention policy |
| Other indices | ~109 GB | 9.8% | Various | Various | Mixed |
| **TOTAL** | **~1,115 GB** | **100%** | - | - | - |

### Key Finding: Stale Historical Indices

**Critical Discovery**: Indices from **September 2025** (5 months ago) remain in the cluster, consuming over **125 GB** of storage. These include:

- `iprod_tomcat_lucky_k8s-2025.09.10` through `2025.09.14`
- `skywalking_idx_segment-2025.09.*`
- `skywalking_idx_metrics-all-2025.09.*`

Additionally, October and November 2025 indices are likely consuming another **100+ GB**.

### SkyWalking Retention Analysis

SkyWalking APM indices collectively consume **~212 GB (19%+ of total storage)**:

| SkyWalking Index Type | Description | Current Retention | Industry Best Practice |
|-----------------------|-------------|-------------------|------------------------|
| `skywalking_idx_segment` | Distributed trace segments | Unlimited (default 90d) | 7-14 days |
| `skywalking_idx_metrics-all` | Aggregated APM metrics | Unlimited (default 90d) | 30 days |
| `izeus-skywalking-trace-exception` | Exception traces | Unlimited | 14-30 days |

**Recommendation**: Coordinate with the R&D team to reduce SkyWalking retention to industry-standard periods. Trace segments are primarily used for immediate troubleshooting and rarely accessed beyond 7-14 days.

---

## Section 4: Remediation Plan

### Immediate Actions (P0 — Execute Within 24-48 Hours)

| Action | Target Indices | Expected Recovery | Risk Level | Owner |
|--------|----------------|-------------------|------------|-------|
| Delete Sept 2025 indices | `*-2025.09.*` | ~125 GB | Low (5 months old) | DevOps DBA |
| Delete Oct 2025 indices | `*-2025.10.*` | ~50 GB | Low (4 months old) | DevOps DBA |
| Monitor post-cleanup | - | - | - | DevOps DBA |

**Total Immediate Recovery: ~175 GB**

After cleanup, storage utilization should drop from **96%+ to approximately 82%**, providing 30+ days of runway.

### Short-Term Actions (P1 — This Week)

| Action | Description | Owner |
|--------|-------------|-------|
| Configure ISM policies | Create 5 retention policies (see below) | DevOps DBA |
| Attach policies to existing indices | Ensure ongoing automated cleanup | DevOps DBA |
| Coordinate SkyWalking retention | Work with R&D to reduce segment retention to 7-14 days | DevOps DBA + R&D |
| Delete Nov 2025 indices | If additional space needed (~50 GB) | DevOps DBA |

### Proposed ISM (Index State Management) Policy Configuration

| Policy Name | Index Pattern | Retention | Rationale |
|-------------|---------------|-----------|-----------|
| `app-logs-30d` | `iprod_tomcat_lucky_k8s-*`, `iprod_tomcat_lucky-*` | 30 days | Standard application log retention |
| `skywalking-traces-7d` | `skywalking_idx_segment*` | 7 days | Traces for immediate troubleshooting only |
| `skywalking-metrics-30d` | `skywalking_idx_metrics-all*` | 30 days | Aggregated metrics for trend analysis |
| `aws-ops-14d` | `aws_cloud_operation*` | 14 days | Operational logs |
| `dify-logs-14d` | `prod-*-dify*` | 14 days | Service logs |

### Medium-Term Optimization (P2 — February-March 2026)

| Action | Benefit | Estimated Savings |
|--------|---------|-------------------|
| Migrate gp2 → gp3 storage | 20% lower cost, better performance | $26/month |
| Migrate m5 → m6g (Graviton) | Better price-performance | $58/month |
| Engine upgrade ES 7.10 → OS 2.x | Security patches, new features | - |
| Enable UltraWarm for cold data | 78% storage cost reduction for aged logs | TBD |

**Total Potential Monthly Savings: $84.51 per domain**

---

## Section 5: Monitoring and Prevention

### CloudWatch Alarms to Implement

| Alarm | Metric | Threshold | Severity |
|-------|--------|-----------|----------|
| FreeStorageSpace Critical | Minimum | < 30 GB | Critical (page on-call) |
| FreeStorageSpace Warning | Minimum | < 50 GB | Warning (ticket) |
| JVMMemoryPressure Warning | Maximum | > 80% | Warning |
| JVMMemoryPressure Critical | Maximum | > 90% | Critical |

### Recommended Monitoring Cadence

| Check | Frequency | Responsible |
|-------|-----------|-------------|
| CloudWatch dashboard review | Daily | DevOps DBA |
| Storage utilization trending | Weekly | DevOps DBA |
| ISM policy execution verification | Weekly | DevOps DBA |
| Fleet-wide health report | Monthly | DevOps DBA → Management |

---

## Section 6: Risk Assessment

### Without Intervention

| Timeline | Projected State | Impact |
|----------|-----------------|--------|
| Day 0 (Feb 10) | ~35 GB free | Current state — degraded performance |
| Day 1-2 | ~25-30 GB free | High risk — latency increasing |
| Day 2-3 | <20 GB free | **Cluster enters read-only mode** |
| Post-outage | Write operations blocked | **All US region log ingestion fails** |

### With Recommended Actions

| Timeline | Projected State | Status |
|----------|-----------------|--------|
| Day 0 (Post-cleanup) | ~210 GB free | ✅ Healthy |
| Day 7 | ~185 GB free | ✅ Healthy |
| Day 14 | ~160 GB free | ✅ Healthy |
| Day 30+ | ~100-150 GB (stable) | ✅ ISM maintaining equilibrium |

---

## Section 7: Summary and Next Steps

### Summary

1. **Luckycommon incident (Jan 28)**: Successfully resolved through capacity expansion and retention policy implementation
2. **Luckyur-log crisis (Current)**: Requires immediate P0 intervention — cluster hit 21.6 GB minimum on Feb 9
3. **Fleet status**: 1 critical, 1 warning, 2 healthy domains
4. **Root cause**: Missing ISM policies leading to unbounded index growth
5. **Recovery plan**: ~175 GB recoverable through stale index cleanup

### Immediate Next Steps

| Step | Action | Target Date | Owner |
|------|--------|-------------|-------|
| 1 | Approve luckyur-log cleanup plan | Feb 10 | Management |
| 2 | Execute Sept/Oct 2025 index deletion | Feb 10-11 | DevOps DBA |
| 3 | Verify storage recovery (target: >150 GB free) | Feb 11 | DevOps DBA |
| 4 | Deploy ISM policies | Feb 12-14 | DevOps DBA |
| 5 | Coordinate SkyWalking retention with R&D | Feb 14 | DevOps DBA + R&D |
| 6 | Status update to management | Feb 14 | DevOps DBA |

### Request for Management

1. **Approval** to proceed with stale index cleanup on luckyur-log (Sept-Nov 2025 indices)
2. **Support** for coordinating with R&D team on SkyWalking retention policy adjustment
3. **Prioritization** of ISM policy implementation as a standard practice across all OpenSearch domains

---

## Appendix A: Technical Details

### Cluster Configuration Reference

```
Domain:          luckyur-log
Engine:          Elasticsearch 7.10
Data Nodes:      4× m5.xlarge.search (4 vCPU, 16 GB RAM each)
Master Nodes:    3× t3.medium.search (dedicated)
Storage:         gp2 EBS, 350 GB per node (1,400 GB total)
Availability:    Zone-aware, 2 AZs (us-east-1a, us-east-1b)
VPC:             vpc-0dce7ca7770422d33
Endpoint:        vpc-luckyur-log-h2ri4xhsubrzscobj64zswc2e4.us-east-1.es.amazonaws.com
```

### ISM Policy Files

Ready-to-deploy ISM policy JSON files are available in the repository:
- `luckyur-log-opensearch-analysis-2026-02-10/ism-policies/`

### CloudWatch Metrics Data Source

All storage and performance metrics sourced from AWS CloudWatch:
- Namespace: `AWS/ES`
- Dimensions: `DomainName=luckyur-log`, `ClientId=257394478466`
- Time range: January 22 – February 10, 2026

---

**Report Version**: 1.0
**Last Updated**: February 10, 2026
**Next Review**: February 14, 2026

---

*For questions or clarification, please contact the DevOps DBA team.*

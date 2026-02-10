# OpenSearch m7g.medium.search Master Node Evaluation

**Date:** February 10, 2026
**Region:** us-east-1 (Luckin Coffee US)
**EDP Discount:** 31% (multiplier: 0.69)

---

## Executive Summary

**m7g.medium.search is a viable and cost-effective alternative to t3.medium.search for master nodes.**

| Finding | Details |
|---------|---------|
| ✅ **Available** | m7g.medium.search is available for Elasticsearch 7.10 |
| ✅ **Master Eligible** | Can be used as dedicated master node (confirmed in InstanceRole) |
| ✅ **Cheaper** | $0.068/hr vs $0.073/hr On-Demand (7% savings) |
| ✅ **Same RAM** | 4 GB (same as t3.medium) |
| ⚠️ **Fewer vCPUs** | 1 vCPU vs 2 vCPU (but master nodes are CPU-idle) |
| ⚠️ **Non-burstable** | Consistent performance vs burstable (better for stability) |
| ❌ **Not for ES 6.8** | Not available for Elasticsearch 6.8 (luckycommon) |

### Quick Savings Summary

| Scenario | Annual Savings | Notes |
|----------|----------------|-------|
| Switch luckylfe-log to m7g.medium | **$90.60** | Low risk, same specs |
| Switch luckyur-log to m7g.medium | **$90.60** | ⚠️ Moderate risk (1 vCPU for 6000 shards) |
| Switch luckyur-log to m7g.large | **-$270.36** | Costs MORE but adds stability for 6000 shards |
| **Total (both domains → m7g.medium)** | **$181.20** | |
| **With 1yr RI (if EDP stacks)** | **$591.12** | Best case scenario |

---

## Instance Specifications Comparison

| Instance Type | vCPU | RAM | Network | Burstable | Hourly Rate | Available for ES 7.10 | Master Eligible |
|--------------|------|-----|---------|-----------|-------------|----------------------|-----------------|
| t3.small.search | 2 | 2 GB | Low-Moderate | Yes | $0.036 | ✅ | ✅ |
| t3.medium.search | 2 | 4 GB | Low-Moderate | Yes | $0.073 | ✅ | ✅ |
| **m7g.medium.search** | **1** | **4 GB** | Up to 12.5 Gbps | **No** | **$0.068** | ✅ | ✅ |
| m7g.large.search | 2 | 8 GB | Up to 12.5 Gbps | No | $0.135 | ✅ | ✅ |

### Key Differences: t3.medium vs m7g.medium

| Attribute | t3.medium.search | m7g.medium.search | Impact on Master Nodes |
|-----------|------------------|-------------------|------------------------|
| vCPU | 2 | 1 | Low — masters use <15% CPU typically |
| RAM | 4 GB | 4 GB | None — same JVM heap available |
| Burstable | Yes | No | Better — consistent performance |
| Network | Low-Moderate | Up to 12.5 Gbps | Better — faster cluster state sync |
| Price | $0.073/hr | $0.068/hr | **7% cheaper** |
| Architecture | Intel x86 | AWS Graviton3 (ARM) | More efficient |

---

## Pricing Reference

### On-Demand Pricing (us-east-1)

| Instance Type | Hourly | Monthly/Node | Monthly ×3 (pre-EDP) | Monthly ×3 (w/EDP) |
|--------------|--------|--------------|----------------------|---------------------|
| t3.small.search | $0.036 | $26.28 | $78.84 | $54.40 |
| t3.medium.search | $0.073 | $53.29 | $159.87 | $110.31 |
| **m7g.medium.search** | **$0.068** | **$49.64** | **$148.92** | **$102.76** |
| m7g.large.search | $0.135 | $98.55 | $295.65 | $204.00 |

### Reserved Instance Pricing (1yr and 3yr)

| Instance Type | 1yr No Upfront | 1yr All Upfront | 3yr No Upfront | 3yr All Upfront |
|--------------|----------------|-----------------|----------------|-----------------|
| t3.medium.search | $0.060/hr | $499/yr ($0.057/hr) | $0.052/hr | $1,305/3yr ($0.050/hr) |
| m7g.medium.search | $0.047/hr | $387/yr ($0.044/hr) | $0.035/hr | $858/3yr ($0.033/hr) |
| m7g.large.search | $0.093/hr | $769/yr ($0.088/hr) | $0.070/hr | $1,703/3yr ($0.065/hr) |

### Monthly Cost Comparison (3 Master Nodes)

| Instance Type | On-Demand (pre-EDP) | On-Demand (w/EDP) | 1yr RI All Upfront | 3yr RI All Upfront |
|--------------|---------------------|-------------------|---------------------|---------------------|
| t3.medium.search | $159.87 | $110.31 | $124.75 | $108.75 |
| m7g.medium.search | $148.92 | $102.76 | $96.75 | $71.50 |
| m7g.large.search | $295.65 | $204.00 | $192.25 | $141.92 |

---

## Per-Domain Analysis

### 1. luckylfe-log

**Current Configuration:**
- Master nodes: t3.medium.search × 3
- Engine: Elasticsearch 7.10
- Active Shards: ~616
- CPU Utilization: Avg 7.5%, Max 42%
- JVM Memory Pressure: Avg 44%, Max 76%

**Assessment for m7g.medium.search:**

| Factor | Current (t3.medium) | Proposed (m7g.medium) | Risk |
|--------|--------------------|-----------------------|------|
| vCPU | 2 | 1 | ✅ Low — CPU usage is only 7.5% avg |
| RAM | 4 GB | 4 GB | ✅ None — same |
| Shards | 616 | 616 | ✅ Within limits for both |
| JVM Pressure | 44% avg | Expected same | ✅ RAM unchanged |

**Recommendation:** ✅ **MIGRATE TO m7g.medium.search**

The 7.5% average CPU means the second vCPU is completely unused. Non-burstable Graviton3 will provide more consistent performance for cluster state management.

| Metric | Current | New | Change |
|--------|---------|-----|--------|
| Monthly Cost (w/EDP) | $110.31 | $102.76 | **-$7.55** |
| Annual Savings | — | — | **$90.60** |

---

### 2. luckyur-log

**Current Configuration:**
- Master nodes: t3.medium.search × 3
- Engine: Elasticsearch 7.10
- Active Shards: **~6,000** ⚠️
- CPU Utilization: Avg 10.8%, Max 53%
- JVM Memory Pressure: Avg 47%, Max 77.6%

**⚠️ Critical Context:** This domain has 6× more shards than AWS recommends for t3.medium (<1,000 shards). It's already running at the edge of capacity.

**Option A: Switch to m7g.medium.search (Cost Savings)**

| Factor | Current (t3.medium) | m7g.medium | Risk Assessment |
|--------|--------------------|-----------------------|-----------------|
| vCPU | 2 | 1 | ⚠️ Moderate — 10.8% avg but 53% max spikes |
| RAM | 4 GB | 4 GB | ✅ None — same |
| Shards | 6,000 | 6,000 | ⚠️ Both undersized per guidelines |

**Concern:** The 53% CPU max spikes indicate occasional intensive cluster operations. With 1 vCPU on m7g.medium, these operations might take longer, though they should still complete.

**Option B: Switch to m7g.large.search (More Headroom)**

| Factor | Current (t3.medium) | m7g.large | Risk Assessment |
|--------|--------------------|-----------------------|-----------------|
| vCPU | 2 | 2 | ✅ Same |
| RAM | 4 GB | 8 GB | ✅ Better — more JVM headroom |
| Shards | 6,000 | 6,000 | ✅ Better support with more RAM |
| JVM Pressure | 47% avg | Expected ~24% | ✅ Significant improvement |

**Cost Comparison:**

| Option | Monthly (w/EDP) | vs Current | Annual Impact |
|--------|-----------------|------------|---------------|
| Keep t3.medium | $110.31 | Baseline | — |
| A: m7g.medium | $102.76 | -$7.55 | **+$90.60 savings** |
| B: m7g.large | $204.00 | +$93.69 | **-$1,124.28 increase** |

**Recommendation:**

**For cost optimization → Option A (m7g.medium)** with close monitoring. The 10.8% average CPU is well within single vCPU capacity. Set up CloudWatch alarms for:
- MasterCPUUtilization > 70% (warning) / > 85% (critical)
- MasterJVMMemoryPressure > 80%

**For stability optimization → Option B (m7g.large)** if budget allows. The 8 GB RAM would bring JVM pressure from 47% to ~24%, providing much better headroom for the 6,000 shards.

---

### 3. luckycommon

**Current Configuration:**
- Master nodes: t3.small.search × 3
- Engine: **Elasticsearch 6.8** ⚠️
- Active Shards: ~104
- JVM Memory Pressure: Avg 52%, Max 77.5%

**m7g Availability Check:**

```
ES 6.8 m7g instance types: NONE AVAILABLE
```

**Recommendation:** ❌ **NO CHANGE POSSIBLE**

Elasticsearch 6.8 does not support any Graviton (m7g/m6g) instance types. Options:
1. **Stay on t3.small.search** — current approach
2. **Upgrade to ES 7.10+** — enables m7g options (migration project required)
3. **Monitor JVM pressure** — 52% avg / 77.5% max on 2GB RAM is concerning

---

## Reserved Instance Comparison: m7g vs t3

### Scenario A: EDP Does NOT Stack with RI (RI pricing standalone)

| Instance | Term | Payment | Monthly ×3 | vs t3.medium OD+EDP ($110.31) |
|----------|------|---------|------------|-------------------------------|
| t3.medium | 1yr | All Upfront | $124.75 | **+$14.44** (more expensive) |
| t3.medium | 3yr | All Upfront | $108.75 | **-$1.56** |
| **m7g.medium** | **1yr** | **All Upfront** | **$96.75** | **-$13.56** |
| **m7g.medium** | **3yr** | **All Upfront** | **$71.50** | **-$38.81** |

**Key Insight:** m7g.medium 1yr RI is cheaper than current t3.medium with EDP!

### Scenario B: EDP DOES Stack with RI (RI × 0.69)

| Instance | Term | Payment | Monthly ×3 (w/EDP) | vs Current | Annual Savings |
|----------|------|---------|---------------------|------------|----------------|
| m7g.medium | 1yr | All Upfront | $66.76 | -$43.55 | **$522.60** |
| m7g.medium | 3yr | All Upfront | $49.34 | -$60.97 | **$731.64** |

---

## Final Comparison Table

| Domain | Current Config | Recommended Config | Current Monthly (w/EDP) | New Monthly (w/EDP) | Monthly Savings | Annual Savings | Risk Level | Notes |
|--------|---------------|-------------------|------------------------|---------------------|-----------------|----------------|------------|-------|
| luckylfe-log | t3.medium × 3 | **m7g.medium × 3** | $110.31 | $102.76 | $7.55 | **$90.60** | LOW | Same RAM, CPU well under 1 vCPU |
| luckyur-log | t3.medium × 3 | **m7g.medium × 3** | $110.31 | $102.76 | $7.55 | **$90.60** | MODERATE | 6000 shards with 1 vCPU needs monitoring |
| luckycommon | t3.small × 3 | t3.small × 3 (no change) | $54.40 | $54.40 | $0.00 | $0.00 | N/A | ES 6.8 doesn't support m7g |
| **TOTAL** | | | **$275.02** | **$259.92** | **$15.10** | **$181.20** | | |

### Alternative: luckyur-log → m7g.large (Stability Focus)

| Domain | Current Config | Recommended Config | Current Monthly (w/EDP) | New Monthly (w/EDP) | Monthly Savings | Annual Savings | Risk Level | Notes |
|--------|---------------|-------------------|------------------------|---------------------|-----------------|----------------|------------|-------|
| luckylfe-log | t3.medium × 3 | m7g.medium × 3 | $110.31 | $102.76 | $7.55 | $90.60 | LOW | |
| luckyur-log | t3.medium × 3 | **m7g.large × 3** | $110.31 | $204.00 | **-$93.69** | **-$1,124.28** | LOW | Better stability for 6000 shards |
| luckycommon | t3.small × 3 | t3.small × 3 | $54.40 | $54.40 | $0.00 | $0.00 | N/A | |
| **TOTAL** | | | **$275.02** | **$361.16** | **-$86.14** | **-$1,033.68** | | Trades cost for stability |

---

## Reserved Instance Strategy with m7g

### Best Value: m7g.medium 1yr All Upfront (per node)

| Metric | Value |
|--------|-------|
| Upfront Cost | $387/node/year |
| Total for 6 nodes (2 domains) | $2,322 |
| Effective hourly | $0.044/hr |
| Monthly cost (6 nodes) | $193.50 |

### Comparison to Current State

| Scenario | Monthly Cost (6 nodes) | Annual Cost | Annual Savings vs Current |
|----------|------------------------|-------------|---------------------------|
| Current (t3.medium OD + EDP) | $220.62 | $2,647.44 | Baseline |
| m7g.medium OD + EDP | $205.52 | $2,466.24 | **$181.20** |
| m7g.medium 1yr RI (no EDP stack) | $193.50 | $2,322.00 | **$325.44** |
| m7g.medium 1yr RI (EDP stacks) | $133.52 | $1,602.24 | **$1,045.20** |

---

## Final Recommendations

### Recommended Actions (Priority Order)

#### 1. ✅ Migrate luckylfe-log to m7g.medium.search (LOW RISK)

**Rationale:**
- CPU usage is only 7.5% average — 1 vCPU is more than enough
- Same 4 GB RAM maintains current JVM headroom
- 616 shards is well within capacity
- Saves $90.60/year with minimal risk

**Implementation:**
1. Schedule maintenance window (non-peak hours)
2. Use rolling blue-green deployment via AWS Console or CLI
3. Monitor for 48 hours post-migration
4. Verify cluster health and master node metrics

#### 2. ⚠️ Migrate luckyur-log to m7g.medium.search (MODERATE RISK)

**Rationale:**
- 10.8% average CPU fits within 1 vCPU capacity
- 53% max CPU spikes are concerning but manageable
- Same RAM — JVM pressure unchanged
- Saves $90.60/year

**Risk Mitigation:**
- Set up CloudWatch alarms BEFORE migration:
  - MasterCPUUtilization > 70% → Warning
  - MasterCPUUtilization > 85% → Critical
  - MasterJVMMemoryPressure > 80% → Critical
- Have rollback plan ready (can switch back to t3.medium)
- Consider migrating AFTER luckylfe-log proves stable on m7g.medium

**Alternative (Higher Cost, Lower Risk):**
If 6,000 shards causes concern, use m7g.large instead:
- 2 vCPU (same as current)
- 8 GB RAM (2× current — better JVM headroom)
- Costs $93.69/month MORE but provides stability margin

#### 3. ❌ No Change for luckycommon (ES 6.8 Limitation)

**Current Constraint:** Elasticsearch 6.8 does not support Graviton instances.

**Future Consideration:** Plan ES 6.8 → ES 7.10 upgrade project, which would enable:
- m7g.medium.search as master nodes
- Access to newer features and security patches
- Long-term cost optimization opportunities

---

## Summary

| Metric | Value |
|--------|-------|
| Domains eligible for m7g migration | 2 (luckylfe-log, luckyur-log) |
| Total annual savings (OD + EDP) | **$181.20** |
| Total annual savings (1yr RI, no EDP) | **$325.44** |
| Total annual savings (1yr RI + EDP) | **$1,045.20** (best case) |
| Implementation risk | Low to Moderate |
| Recommended first migration | luckylfe-log (lowest risk) |

### Action Items

1. **Immediate:** Verify with AWS account team if EDP applies to Reserved Instances
2. **Week 1:** Migrate luckylfe-log to m7g.medium.search, set up monitoring
3. **Week 2-3:** Monitor luckylfe-log performance and stability
4. **Week 4:** If stable, migrate luckyur-log to m7g.medium.search
5. **Post-migration:** Evaluate 1yr RI purchase for m7g.medium nodes
6. **Long-term:** Plan luckycommon ES 6.8 → 7.10 upgrade

---

*Generated by Claude Code for Luckin Coffee US AWS Cost Optimization Initiative*

# OpenSearch/Elasticsearch Graviton Migration Opportunity Analysis

**Date:** February 10, 2026
**Region:** us-east-1
**Total Domains:** 4
**EDP Discount Applied:** 31% (0.69 multiplier)

---

## Executive Summary

| Metric | Value |
|--------|-------|
| **Total Domains Analyzed** | 4 |
| **Already on Graviton (fully)** | 1 (25%) |
| **Partially Eligible for Graviton** | 2 (50%) |
| **Cannot Migrate (engine limitation)** | 1 (25%) |
| **Total Monthly Graviton Savings** | **$82.39** |
| **Total Monthly Storage Savings (gp2→gp3)** | **$41.54** |
| **Grand Total Monthly Savings** | **$123.93** |
| **Annual Savings Potential** | **$1,487.16** |

---

## Question 1: Which Instances CAN/CANNOT Be Converted to Graviton?

### Domain Inventory Summary

| Domain | Engine Version | Data Nodes | Master Nodes | Status |
|--------|---------------|------------|--------------|--------|
| luckylfe-log | Elasticsearch 7.10 | m5.large.search × 4 | t3.medium.search × 3 | **Partial** - Data only |
| luckycommon | Elasticsearch 6.8 | m5.large.search × 4 | t3.small.search × 3 | **Cannot** - ES 6.8 no Graviton |
| luckyur-log | Elasticsearch 7.10 | m5.xlarge.search × 4 | t3.medium.search × 3 | **Partial** - Data only |
| luckyus-opensearch-dify | OpenSearch 2.15 | r6g.large.search × 2 | m7g.large.search × 3 | **Already Graviton** |

---

### Detailed Eligibility Analysis

#### Domain: luckylfe-log

| Component | Current | Target | Eligible? | Reason |
|-----------|---------|--------|-----------|--------|
| **Data Nodes** | m5.large.search × 4 | m6g.large.search × 4 | **YES** | ES 7.10 supports Graviton |
| **Master Nodes** | t3.medium.search × 3 | N/A | **NO** | t3.* has no Graviton equivalent |
| **Storage** | gp2 80GB × 4 | gp3 | **YES** | Free optimization |

**Health Status:** Avg CPU 8.1%, Max CPU 50% - HEALTHY

---

#### Domain: luckycommon

| Component | Current | Target | Eligible? | Reason |
|-----------|---------|--------|-----------|--------|
| **Data Nodes** | m5.large.search × 4 | N/A | **NO** | **ES 6.8 does not support Graviton instances** |
| **Master Nodes** | t3.small.search × 3 | N/A | **NO** | t3.* has no Graviton equivalent |
| **Storage** | gp3 100GB × 4 | N/A | Already gp3 | No action needed |

**Health Status:** Avg CPU 12.9%, Max CPU 54% - HEALTHY

**CRITICAL NOTE:** This domain is on Elasticsearch 6.8, which is EOL and does not support Graviton2 instances. To enable Graviton migration, you must first upgrade to Elasticsearch 7.x or OpenSearch 1.x+.

---

#### Domain: luckyur-log

| Component | Current | Target | Eligible? | Reason |
|-----------|---------|--------|-----------|--------|
| **Data Nodes** | m5.xlarge.search × 4 | m6g.xlarge.search × 4 | **YES** | ES 7.10 supports Graviton |
| **Master Nodes** | t3.medium.search × 3 | N/A | **NO** | t3.* has no Graviton equivalent |
| **Storage** | gp2 350GB × 4 | gp3 | **YES** | Free optimization |

**Health Status:** Avg CPU 16.9%, Max CPU 84% - **CAUTION** (Max CPU > 80%)

**WARNING:** This domain shows peak CPU utilization of 84%. Consider monitoring closely after migration and ensure maintenance window during low-traffic period.

---

#### Domain: luckyus-opensearch-dify

| Component | Current | Target | Eligible? | Reason |
|-----------|---------|--------|-----------|--------|
| **Data Nodes** | r6g.large.search × 2 | N/A | **Already Graviton** | No action needed |
| **Master Nodes** | m7g.large.search × 3 | N/A | **Already Graviton** | No action needed |
| **Storage** | gp3 30GB × 2 | N/A | Already gp3 | No action needed |

**Health Status:** Avg CPU 8.2%, Max CPU 36% - HEALTHY

---

## Question 2: Monthly Cost Savings Per Convertible Domain

### Pricing Reference (US East - N. Virginia)

| Instance Type | On-Demand $/hr | After EDP (×0.69) $/hr |
|---------------|----------------|------------------------|
| m5.large.search | $0.142 | $0.09798 |
| m6g.large.search | $0.128 | $0.08832 |
| m5.xlarge.search | $0.283 | $0.19527 |
| m6g.xlarge.search | $0.256 | $0.17664 |
| t3.small.search | $0.036 | $0.02484 |
| t3.medium.search | $0.073 | $0.05037 |
| r6g.large.search | $0.167 | $0.11523 |
| m7g.large.search | $0.135 | $0.09315 |

---

### Detailed Cost Savings Table

| Domain | Component | Type × Count | Current $/mo | Target $/mo | Graviton Savings $/mo | Storage Savings $/mo |
|--------|-----------|--------------|--------------|-------------|----------------------|---------------------|
| **luckylfe-log** | Data Nodes | m5.large × 4 → m6g.large × 4 | $286.17 | $258.13 | **$28.04** | - |
| | Master Nodes | t3.medium × 3 | $110.33 | $110.33 | $0 (no Graviton) | - |
| | Storage | gp2 320GB → gp3 | $25.42 | $17.69 | - | **$7.73** |
| | **Subtotal** | | **$421.92** | **$386.15** | **$28.04** | **$7.73** |
| **luckycommon** | Data Nodes | m5.large × 4 | $286.17 | $286.17 | $0 (ES 6.8) | - |
| | Master Nodes | t3.small × 3 | $54.44 | $54.44 | $0 (no Graviton) | - |
| | Storage | gp3 400GB | $22.08 | $22.08 | - | $0 (already gp3) |
| | **Subtotal** | | **$362.69** | **$362.69** | **$0** | **$0** |
| **luckyur-log** | Data Nodes | m5.xlarge × 4 → m6g.xlarge × 4 | $570.13 | $515.78 | **$54.35** | - |
| | Master Nodes | t3.medium × 3 | $110.33 | $110.33 | $0 (no Graviton) | - |
| | Storage | gp2 1400GB → gp3 | $111.09 | $77.28 | - | **$33.81** |
| | **Subtotal** | | **$791.55** | **$703.39** | **$54.35** | **$33.81** |
| **luckyus-opensearch-dify** | Data Nodes | r6g.large × 2 | $168.25 | $168.25 | $0 (already Graviton) | - |
| | Master Nodes | m7g.large × 3 | $203.93 | $203.93 | $0 (already Graviton) | - |
| | Storage | gp3 60GB | $3.31 | $3.31 | - | $0 (already gp3) |
| | **Subtotal** | | **$375.49** | **$375.49** | **$0** | **$0** |
| **GRAND TOTAL** | | | **$1,951.65** | **$1,827.72** | **$82.39** | **$41.54** |

---

### Cost Calculation Breakdown

#### luckylfe-log: Data Nodes (m5.large.search → m6g.large.search)
```
Current: $0.142/hr × 730 hrs × 4 nodes × 0.69 EDP = $286.17/month
Target:  $0.128/hr × 730 hrs × 4 nodes × 0.69 EDP = $258.13/month
Savings: $28.04/month (9.8% reduction)
```

#### luckylfe-log: Storage (gp2 → gp3)
```
Volume: 80 GB × 4 nodes = 320 GB total
gp2 cost: 320 GB × $0.115/GB × 0.69 = $25.42/month
gp3 cost: 320 GB × $0.08/GB × 0.69 = $17.69/month
Savings: $7.73/month (30.4% reduction)
```

#### luckyur-log: Data Nodes (m5.xlarge.search → m6g.xlarge.search)
```
Current: $0.283/hr × 730 hrs × 4 nodes × 0.69 EDP = $570.13/month
Target:  $0.256/hr × 730 hrs × 4 nodes × 0.69 EDP = $515.78/month
Savings: $54.35/month (9.5% reduction)
```

#### luckyur-log: Storage (gp2 → gp3)
```
Volume: 350 GB × 4 nodes = 1,400 GB total
gp2 cost: 1,400 GB × $0.115/GB × 0.69 = $111.09/month
gp3 cost: 1,400 GB × $0.08/GB × 0.69 = $77.28/month
Savings: $33.81/month (30.4% reduction)
```

---

## Summary by Savings Category

| Category | Domain Count | Monthly Savings |
|----------|--------------|-----------------|
| Graviton Migration (Data Nodes) | 2 | $82.39 |
| Graviton Migration (Master Nodes) | 0 | $0 (t3.* not supported) |
| gp2→gp3 Storage | 2 | $41.54 |
| **TOTAL** | | **$123.93** |

---

## Final Summary Table

| Domain Name | Engine | Data Nodes | Master Nodes | Data Eligible? | Master Eligible? | Reason (if not) | Current $/mo | Target $/mo | Graviton $/mo | Storage $/mo | Total $/mo |
|-------------|--------|------------|--------------|----------------|------------------|-----------------|--------------|-------------|---------------|--------------|------------|
| luckylfe-log | ES 7.10 | m5.large×4 | t3.medium×3 | **YES** | NO | t3 no Graviton | $421.92 | $386.15 | $28.04 | $7.73 | **$35.77** |
| luckycommon | ES 6.8 | m5.large×4 | t3.small×3 | **NO** | NO | ES 6.8 no Graviton; t3 no Graviton | $362.69 | $362.69 | $0 | $0 | **$0** |
| luckyur-log | ES 7.10 | m5.xlarge×4 | t3.medium×3 | **YES** | NO | t3 no Graviton | $791.55 | $703.39 | $54.35 | $33.81 | **$88.16** |
| luckyus-opensearch-dify | OS 2.15 | r6g.large×2 | m7g.large×3 | Already | Already | - | $375.49 | $375.49 | $0 | $0 | **$0** |
| **TOTAL** | | | | | | | **$1,951.65** | **$1,827.72** | **$82.39** | **$41.54** | **$123.93** |

---

## Recommended Migration Priority

### Priority 1: Highest Impact
| Rank | Domain | Savings/mo | Effort | Risk | Notes |
|------|--------|------------|--------|------|-------|
| 1 | luckyur-log | $88.16 | Medium | Medium | **CAUTION:** Max CPU 84% - monitor closely |
| 2 | luckylfe-log | $35.77 | Medium | Low | Healthy cluster, straightforward migration |

### Priority 2: Requires Version Upgrade First
| Rank | Domain | Potential Savings | Effort | Blocker |
|------|--------|-------------------|--------|---------|
| 3 | luckycommon | $28.04 (estimate) | High | **Must upgrade from ES 6.8 to 7.x or OpenSearch first** |

### No Action Needed
| Domain | Reason |
|--------|--------|
| luckyus-opensearch-dify | Already fully optimized (Graviton + gp3) |

---

## Migration Notes

### Pre-Migration Checklist
- [ ] Verify cluster is in GREEN health status
- [ ] Ensure recent snapshot exists
- [ ] Schedule during low-traffic maintenance window
- [ ] For luckyur-log: consider during off-peak hours due to high CPU utilization

### Migration Process (Blue/Green Deployment)

OpenSearch/Elasticsearch instance type changes use a **blue/green deployment** process:

1. **Initiate Change** via AWS Console or CLI:
   ```bash
   aws opensearch update-domain-config \
     --domain-name <domain-name> \
     --cluster-config InstanceType=m6g.large.search
   ```

2. **AWS Creates New Nodes** - New Graviton nodes are provisioned alongside existing nodes

3. **Data Migration** - Data is automatically migrated to new nodes (can take hours for large clusters)

4. **Cutover** - Traffic is switched to new nodes

5. **Cleanup** - Old nodes are terminated

**Estimated Downtime:** Minimal (blue/green), but recommend scheduling during maintenance window.

### gp2→gp3 Storage Migration

Storage type changes are **online operations** with no downtime:

```bash
aws opensearch update-domain-config \
  --domain-name <domain-name> \
  --ebs-options VolumeType=gp3,VolumeSize=<size>,Iops=3000,Throughput=125
```

---

## Key Findings & Recommendations

### 1. **luckycommon (ES 6.8) - Version Upgrade Required**
This domain runs Elasticsearch 6.8, which reached end-of-life and **does not support Graviton instances**. Before any Graviton migration:
- Upgrade to Elasticsearch 7.x (minimum 7.1) or preferably OpenSearch 1.x/2.x
- This will unlock ~$28/month in Graviton savings
- Also provides security patches and new features

### 2. **t3.* Master Nodes - No Graviton Path**
All three legacy domains use t3.medium or t3.small for dedicated master nodes. There is **no Graviton equivalent** for t3.* instance types in OpenSearch. Options:
- Accept current costs ($165/month combined for all t3 masters)
- Upgrade to m6g.* for masters (would increase costs, not recommended unless needed for performance)

### 3. **luckyus-opensearch-dify - Best Practice Example**
This domain is already fully optimized:
- Graviton data nodes (r6g.large)
- Graviton master nodes (m7g.large)
- gp3 storage
Use this as a template for new deployments.

### 4. **luckyur-log - Monitor After Migration**
This domain shows peak CPU utilization of 84%. After Graviton migration:
- Monitor CPU closely for the first week
- Graviton typically provides equal or better performance, but validate workload

---

## Annual Savings Summary

| Category | Monthly | Annual |
|----------|---------|--------|
| Graviton Data Nodes | $82.39 | $988.68 |
| gp2→gp3 Storage | $41.54 | $498.48 |
| **TOTAL** | **$123.93** | **$1,487.16** |

**Note:** If luckycommon is upgraded to ES 7.x+, an additional ~$28/month ($336/year) in Graviton savings becomes available.

---

*Report generated: February 10, 2026*
*AWS Region: us-east-1*
*Pricing source: AWS Price List API (AmazonES) with 31% EDP discount*

# EC2 Cost Optimization Report
## Luckin Coffee North America - AWS Account 257394478466

**Report Date:** 2026-02-05
**Analysis Period:** 2026-01-06 to 2026-02-05 (30 days)
**Region:** us-east-1
**Pricing Model:** On-Demand with 31% Enterprise Discount Program (EDP)

---

## Executive Summary

| Metric | Value |
|--------|-------|
| Total Running Instances | 233 |
| Total Monthly EC2 Cost (with EDP) | $26,118.71 |
| Idle Instances (China Standard) | 181 (78%) |
| Underutilized Instances (AWS Standard) | 222 (95%) |
| **Potential Monthly Savings** | **$14,675.60** |
| **Potential Annual Savings** | **$176,107.20** |
| Savings as % of Total | 56.2% |

### Key Findings

1. **Critical Underutilization**: 78% of EC2 instances are classified as IDLE (<2% average CPU) by China HQ standards
2. **EKS Node Group Optimization Opportunity**: 20 large instances (m6i.8xlarge/4xlarge) running as EKS workers with <2% CPU utilization - requires Kubernetes workload analysis
3. **Compute-Optimized Fleet Dominance**: 195 instances (84%) are c6i family, majority showing <1% CPU utilization
4. **EBS Optimization**: 94% of volumes already use gp3 - minimal additional savings ($18.20/month)

---

## Fleet Inventory Summary

### Instance Type Distribution

| Instance Type | Count | Monthly Cost (EDP) | % of Fleet | % of Cost |
|--------------|-------|-------------------|-----------|----------|
| c6i.large | 144 | $4,285.86 | 61.8% | 16.4% |
| c6i.xlarge | 45 | $2,680.55 | 19.3% | 10.3% |
| m6i.8xlarge | 13 | $10,055.38 | 5.6% | 38.5% |
| m6i.4xlarge | 7 | $2,706.08 | 3.0% | 10.4% |
| m5.xlarge | 6 | $578.59 | 2.6% | 2.2% |
| c6i.2xlarge | 5 | $855.36 | 2.1% | 3.3% |
| m6a.large | 3 | $130.38 | 1.3% | 0.5% |
| r6i.2xlarge | 2 | $507.07 | 0.9% | 1.9% |
| m6a.xlarge | 2 | $173.85 | 0.9% | 0.7% |
| r6i.4xlarge | 1 | $507.07 | 0.4% | 1.9% |
| c6i.4xlarge | 1 | $342.59 | 0.4% | 1.3% |
| t3.large | 1 | $41.94 | 0.4% | 0.2% |
| m4.xlarge | 1 | $100.74 | 0.4% | 0.4% |
| m4.large | 1 | $50.37 | 0.4% | 0.2% |
| c5.large | 1 | $42.83 | 0.4% | 0.2% |

### Platform Distribution
- Linux: 230 instances (98.7%)
- Windows: 3 instances (1.3%)

### Availability Zone Distribution
- us-east-1a: 212 instances (91.0%)
- us-east-1b: 17 instances (7.3%)
- us-east-1c: 4 instances (1.7%)

**WARNING**: Heavy concentration in us-east-1a creates availability risk.

---

## Utilization Classification

### Dual-Standard Classification Results

#### China HQ Standard (Conservative)

| Classification | CPU Criteria | Count | % of Fleet |
|---------------|-------------|-------|-----------|
| IDLE | < 2% avg | 181 | 77.7% |
| LOW_LOAD | 2-20% avg | 47 | 20.2% |
| NORMAL | >= 20% avg | 5 | 2.1% |

#### AWS Industry Standard

| Classification | Criteria | Count | % of Fleet |
|---------------|----------|-------|-----------|
| SEVERE_UNDERUTIL | < 5% avg, < 20% max | 173 | 74.2% |
| UNDERUTIL | < 10% avg | 222 | 95.3% |
| RIGHT_SIZED | 10-70% avg | 11 | 4.7% |
| OVER_UTIL | > 70% avg | 0 | 0.0% |

---

## Top 20 Savings Opportunities

| Rank | Instance ID | Type | Name | Avg CPU | Monthly Cost | Potential Savings |
|------|------------|------|------|---------|--------------|-------------------|
| 1 | i-0e96768c9f352766c | m6i.8xlarge | EKS-worker | 1.69% | $773.68 | $657.63 |
| 2 | i-05cea5a6a4ae2801d | m6i.8xlarge | EKS-worker | 1.70% | $773.68 | $657.63 |
| 3 | i-0b94e2139334f6c97 | m6i.8xlarge | EKS-worker | 1.76% | $773.68 | $657.63 |
| 4 | i-00a8aa0a09849ca17 | m6i.8xlarge | EKS-worker | 1.87% | $773.68 | $386.84 |
| 5 | i-0e72d539f775da4bb | m6i.8xlarge | EKS-worker | 1.83% | $773.68 | $386.84 |
| 6 | i-02ca602ec667ca5c1 | m6i.8xlarge | EKS-worker | 1.94% | $773.68 | $386.84 |
| 7 | i-0b992e7a6fa1b66b4 | m6i.8xlarge | EKS-worker | 1.61% | $773.68 | $386.84 |
| 8 | i-09a76a8b0f16c4c39 | m6i.4xlarge | EKS-native | 1.43% | $386.84 | $328.82 |
| 9 | i-087d9aa6a44983b43 | m6i.4xlarge | EKS-worker | 1.70% | $386.84 | $328.82 |
| 10 | i-0f8d8fa6277335edf | c6i.4xlarge | ifeilianvpn01-prod-usa-aws | 0.31% | $342.59 | $291.14 |
| 11 | i-04b4ad1b0469397da | r6i.4xlarge | iluckydpbi03-prod-usa-aws | 1.88% | $507.07 | $253.86 |
| 12 | i-0fc62b28f38f4275e | m6i.8xlarge | EKS-worker | 2.30% | $773.68 | $232.10 |
| 13 | i-0a7889d373836f786 | m6i.8xlarge | EKS-worker | 2.42% | $773.68 | $232.10 |
| 14 | i-07f28f6e4d0193485 | m6i.8xlarge | EKS-worker | 2.67% | $773.68 | $232.10 |
| 15 | i-0b9a758f7e72da236 | m6i.8xlarge | EKS-worker | 2.47% | $773.68 | $232.10 |
| 16 | i-08c37e4b962909d8b | m6i.8xlarge | EKS-worker | 2.95% | $773.68 | $232.10 |
| 17 | i-0f09e3529105df1e9 | m6i.8xlarge | EKS-worker | 3.87% | $773.68 | $232.10 |
| 18 | i-04f5d14a1fafdea36 | m6i.4xlarge | EKS-native | 1.01% | $386.84 | $193.42 |
| 19 | i-05ebee32958e4dc1c | m6i.4xlarge | EKS-native | 1.50% | $386.84 | $193.42 |
| 20 | i-0eb265d2fe5b513d1 | m6i.4xlarge | EKS-worker | 1.87% | $386.84 | $193.42 |

**Note**: EKS-worker and EKS-native instances are managed by Auto Scaling Groups. Optimization requires Kubernetes-level analysis.

---

## EKS Node Group Analysis

### Cluster: prod-worker01-eks-us
| Instance Type | Count | Monthly Cost | Avg CPU | Recommendation |
|--------------|-------|--------------|---------|----------------|
| m6i.8xlarge | 13 | $10,055.38 | 1.7-3.9% | Review node group sizing |
| m6i.4xlarge | 4 | $1,547.36 | 1.4-1.9% | Consider smaller instance types |

### Cluster: prod-native-eks-us
| Instance Type | Count | Monthly Cost | Avg CPU | Recommendation |
|--------------|-------|--------------|---------|----------------|
| m6i.4xlarge | 3 | $1,160.52 | 1.0-1.5% | Consider smaller instance types |

**Total EKS Worker Nodes**: 20 instances
**Total EKS Monthly Cost**: $12,763.26 (48.9% of total EC2 spend)
**Potential EKS Optimization**: $6,000-8,000/month (requires K8s workload analysis)

### EKS Optimization Recommendations

1. **Analyze Kubernetes resource requests/limits** - CPU metrics alone don't capture memory or pod density requirements
2. **Review Cluster Autoscaler configuration** - May be over-provisioned for burst capacity
3. **Consider mixed instance types** - Use Spot instances or smaller general-purpose instances
4. **Implement Karpenter** - For more efficient node provisioning

---

## Standalone Instance Analysis

### High-Priority Rightsizing Candidates (Non-ASG)

| Instance ID | Type | Name | Avg CPU | Max CPU | Action |
|------------|------|------|---------|---------|--------|
| i-0f8d8fa6277335edf | c6i.4xlarge | ifeilianvpn01-prod-usa-aws | 0.31% | 1.52% | Downsize to c6i.large |
| i-04b4ad1b0469397da | r6i.4xlarge | iluckydpbi03-prod-usa-aws | 1.88% | 12.16% | Downsize to r6i.xlarge |
| i-0125dfcf211bb3b6d | m5.xlarge | luckin-prod-us-sec-honeypot-hive | 0.10% | 20.43% | Downsize to t3.small |
| i-06fc986a73d97b055 | t3.large | luckin-prod-us-sec-honeypot-sensor | 0.15% | 44.62% | Right-sized (burst workload) |

### c6i.large Fleet (144 instances)

| CPU Range | Count | Monthly Cost | Recommendation |
|-----------|-------|--------------|----------------|
| < 1% avg | 98 | $2,914.82 | Evaluate for consolidation or t3.small |
| 1-2% avg | 24 | $713.74 | Consider t3.medium |
| 2-5% avg | 18 | $535.31 | Likely right-sized for workload |
| > 5% avg | 4 | $118.96 | Right-sized |

---

## EBS Storage Analysis

### Volume Type Distribution
- gp3: 313 volumes (94.3%)
- gp2: 19 volumes (5.7%)

### gp2 to gp3 Migration Opportunity

| Metric | Value |
|--------|-------|
| gp2 Volumes | 19 |
| Total gp2 Storage | 910 GB |
| Current Monthly Cost | $91.00 |
| Post-Migration Cost | $72.80 |
| **Monthly Savings** | **$18.20** |
| **Annual Savings** | **$218.40** |

**Note**: Most volumes already use gp3. Recommend completing migration for remaining 19 volumes for consistency.

---

## Cost Trend Analysis

### EC2 Compute Costs (Last 4 Months)

| Month | EC2 Compute | EC2-Other | Total |
|-------|-------------|-----------|-------|
| Nov 2025 | $25,318.17 | $2,910.83 | $28,229.00 |
| Dec 2025 | $26,577.29 | $3,032.17 | $29,609.46 |
| Jan 2026 | $26,693.06 | $3,097.14 | $29,790.20 |
| Feb 2026 (partial) | $22,132.99 | $409.17 | $22,542.16 |

**Trend**: Relatively stable with slight increase month-over-month (~2% growth Nov-Jan)

---

## Recommendations Summary

### Immediate Actions (0-30 days)

| Priority | Action | Estimated Monthly Savings | Risk |
|----------|--------|--------------------------|------|
| P1 | Rightsize i-0f8d8fa6277335edf (c6i.4xlarge -> c6i.large) | $256.94 | Low |
| P1 | Rightsize i-04b4ad1b0469397da (r6i.4xlarge -> r6i.xlarge) | $379.30 | Medium |
| P1 | Rightsize i-0125dfcf211bb3b6d (m5.xlarge -> t3.small) | $85.71 | Low |
| P2 | Complete gp2 -> gp3 migration (19 volumes) | $18.20 | Low |
| P2 | Review/terminate idle c6i.large instances (98 candidates) | $2,914.82 | Medium |

### Medium-Term Actions (30-90 days)

| Priority | Action | Estimated Monthly Savings | Risk |
|----------|--------|--------------------------|------|
| P2 | EKS node group optimization - reduce m6i.8xlarge count | $3,000-5,000 | Medium |
| P2 | Implement Cluster Autoscaler tuning | $1,000-2,000 | Low |
| P3 | Consider Reserved Instances for stable workloads | 20-30% additional | Low |
| P3 | Multi-AZ rebalancing (91% in us-east-1a) | $0 (risk reduction) | Low |

### Long-Term Actions (90+ days)

| Priority | Action | Estimated Impact | Risk |
|----------|--------|-----------------|------|
| P3 | Implement Karpenter for EKS | 30-40% EKS savings | Medium |
| P3 | Evaluate Graviton instances for Linux workloads | 10-20% savings | Medium |
| P3 | Implement automated rightsizing pipeline | Continuous optimization | Low |

---

## Data Gaps and Limitations

1. **Memory Utilization Data**: Prometheus node_exporter metrics not available - memory-based rightsizing recommendations require additional data collection
2. **Network I/O Metrics**: Not collected in this analysis - may affect recommendations for network-intensive workloads
3. **Disk I/O Metrics**: Not collected - EBS optimization recommendations based on volume type only
4. **Application-Level Metrics**: Kubernetes pod resource utilization not analyzed - EKS recommendations require deeper analysis
5. **Reserved Instance Coverage**: Current RI/SP coverage not verified - savings calculations assume full On-Demand pricing

---

## Appendix: Methodology

### Pricing Calculations
- All costs calculated using us-east-1 On-Demand pricing with 31% EDP discount
- Monthly hours: 730
- Cost formula: `hourly_rate * 730 * (1 - 0.31)`

### Classification Standards

**China HQ Standard (Conservative)**:
- IDLE: < 2% average CPU
- LOW_LOAD: 2-20% average CPU
- NORMAL: >= 20% average CPU

**AWS Industry Standard**:
- SEVERE_UNDERUTIL: < 5% average CPU AND < 20% max CPU
- UNDERUTIL: < 10% average CPU
- RIGHT_SIZED: 10-70% average CPU
- OVER_UTIL: > 70% average CPU

### Rightsizing Logic
- Terminate/consolidate: Max CPU < 10%
- Downsize 2 sizes: Max CPU < 20%
- Downsize 1 size: Max CPU < 40%
- Right-sized: 40-70% max CPU with reasonable average

---

*Report generated by Claude Code | Analysis Date: 2026-02-05*

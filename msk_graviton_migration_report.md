# MSK Graviton Migration Opportunity Analysis

**Generated:** 2026-02-05
**Region:** us-east-1
**EDP Discount Applied:** 31%

---

## Executive Summary

Your MSK fleet has **0 of 3 clusters already optimized**. The remaining **3 clusters** are candidates for Graviton migration and gp2→gp3 storage upgrades.

### Key Findings

| Metric | Value |
|--------|-------|
| Total Clusters | 3 |
| Already Optimized | 0 (0%) |
| Migration Candidates | 3 (100%) |
| **Monthly Savings Potential** | **$219.40** |
| **Annual Savings Potential** | **$2632.79** |

### Savings Breakdown

| Category | Monthly Savings |
|----------|-----------------|
| Graviton Brokers (m5 → m7g) | $114.09 |
| gp2 → gp3 Storage | $105.31 |

---

## Cluster Inventory

| Cluster | Kafka Version | Brokers | Broker Type | Storage | Graviton Compatible |
|---------|---------------|---------|-------------|---------|---------------------|
| iprod-kafka-base-cluster | 2.8.1 | 3 | kafka.m5.large | gp2 1000GB/broker | ✅ Yes |
| iprod-kafka-architecture-cluster | 2.8.1 | 3 | kafka.m5.large | gp2 1000GB/broker | ✅ Yes |
| iprod-kafka-business-cluster | 2.8.1 | 3 | kafka.m5.large | gp2 1000GB/broker | ✅ Yes |

---

## CloudWatch Metrics Summary (7-day)

| Cluster | Avg CPU | Max CPU | Memory Used | Bytes In/s | Bytes Out/s | Under-Replicated | Status |
|---------|---------|---------|-------------|------------|-------------|------------------|--------|
| iprod-kafka-base-cluster | 28.2% | 65.0% | 4.0 GB | 300.0 KB/s | 450.0 KB/s | 0 | ✅ Healthy |
| iprod-kafka-architecture-cluster | 16.4% | 45.0% | 3.8 GB | 150.0 KB/s | 200.0 KB/s | 0 | ✅ Healthy |
| iprod-kafka-business-cluster | 12.1% | 38.0% | 3.7 GB | 100.0 KB/s | 150.0 KB/s | 0 | ✅ Healthy |

**Health Thresholds:**
- CPU: <70% healthy, 70-85% warning, >85% critical
- Under-replicated partitions: 0 is healthy, >0 requires investigation
- Offline partitions: Must always be 0

---

## Optimization Opportunities

### Priority 1: iprod-kafka-base-cluster

**Monthly Savings: $73.13 | Annual Savings: $877.60**

| Component | Current | Recommended | Savings/mo |
|-----------|---------|-------------|------------|
| Broker Type | 3x kafka.m5.large | 3x kafka.m7g.large | $38.03 |
| Storage | gp2 1000GB/broker | gp3 1000GB/broker | $35.10 |

**Current Metrics:**
- CPU: 28.2% avg, 65.0% max
- Memory Used: 4.0 GB (of 8 GB)
- Throughput: 300.0 KB/s in, 450.0 KB/s out
- Under-replicated partitions: 0

**Risk Assessment:** LOW
- Multi-AZ with rolling upgrade support

### Priority 2: iprod-kafka-architecture-cluster

**Monthly Savings: $73.13 | Annual Savings: $877.60**

| Component | Current | Recommended | Savings/mo |
|-----------|---------|-------------|------------|
| Broker Type | 3x kafka.m5.large | 3x kafka.m7g.large | $38.03 |
| Storage | gp2 1000GB/broker | gp3 1000GB/broker | $35.10 |

**Current Metrics:**
- CPU: 16.4% avg, 45.0% max
- Memory Used: 3.8 GB (of 8 GB)
- Throughput: 150.0 KB/s in, 200.0 KB/s out
- Under-replicated partitions: 0

**Risk Assessment:** LOW
- Multi-AZ with rolling upgrade support

### Priority 3: iprod-kafka-business-cluster

**Monthly Savings: $73.13 | Annual Savings: $877.60**

| Component | Current | Recommended | Savings/mo |
|-----------|---------|-------------|------------|
| Broker Type | 3x kafka.m5.large | 3x kafka.m7g.large | $38.03 |
| Storage | gp2 1000GB/broker | gp3 1000GB/broker | $35.10 |

**Current Metrics:**
- CPU: 12.1% avg, 38.0% max
- Memory Used: 3.7 GB (of 8 GB)
- Throughput: 100.0 KB/s in, 150.0 KB/s out
- Under-replicated partitions: 0

**Risk Assessment:** LOW
- Multi-AZ with rolling upgrade support

---

## Graviton Compatibility

### Kafka Version Requirements

| Kafka Version | Graviton Support | Notes |
|---------------|------------------|-------|
| < 2.8 | ❌ Not Supported | Must upgrade Kafka first |
| 2.8.x | ✅ Supported | m7g instances available |
| 3.x | ✅ Supported | Full Graviton support |

All your clusters are running Kafka 2.8.1, which **fully supports Graviton (m7g) instances**.

---

## Migration Guide

### Option 1: Rolling Upgrade (Recommended - Zero Downtime)

MSK supports rolling configuration updates for Graviton migration:

```bash
# Example: Migrate iprod-kafka-base-cluster to Graviton
aws kafka update-broker-type \
    --cluster-arn <cluster-arn> \
    --target-instance-type kafka.m7g.large

# Monitor the rolling update
aws kafka describe-cluster \
    --cluster-arn <cluster-arn> \
    --query 'ClusterInfo.State'
```

**Process:**
1. MSK updates brokers one at a time
2. Each broker is stopped, replaced, and restarted
3. Partitions automatically rebalance
4. Zero client-side changes required

**Expected Duration:** 15-30 minutes per broker (45-90 minutes per cluster)

### Option 2: Storage Upgrade (gp2 → gp3)

```bash
aws kafka update-storage \
    --cluster-arn <cluster-arn> \
    --volume-type gp3

# Or combine with broker upgrade
aws kafka update-broker-storage \
    --cluster-arn <cluster-arn> \
    --target-broker-ebs-volume-info '[{
        "VolumeSize": 1000,
        "VolumeType": "gp3",
        "Throughput": 125,
        "Iops": 3000
    }]'
```

### Pre-Migration Checklist

- [ ] Verify Kafka version is 2.8+ (all clusters ✅)
- [ ] Check for under-replicated partitions (should be 0)
- [ ] Ensure no offline partitions
- [ ] Review producer/consumer lag
- [ ] Schedule during low-traffic period
- [ ] Notify application teams
- [ ] Have rollback plan ready

---

## Recommended Migration Order

| Order | Cluster | Optimizations | Savings/mo | Rationale |
|-------|---------|---------------|------------|-----------|
| 1 | iprod-kafka-base-cluster | Graviton (kafka.m5.large → kafka.m7g.large), gp2 → gp3 storage | $73.13 | Highest savings |
| 2 | iprod-kafka-architecture-cluster | Graviton (kafka.m5.large → kafka.m7g.large), gp2 → gp3 storage | $73.13 | Lower traffic, safer |
| 3 | iprod-kafka-business-cluster | Graviton (kafka.m5.large → kafka.m7g.large), gp2 → gp3 storage | $73.13 | Lower traffic, safer |

---

## Cost Summary

### Current Monthly Costs (with 31% EDP)

| Cluster | Broker Cost | Storage Cost | Total |
|---------|-------------|--------------|-------|
| iprod-kafka-base-cluster | $314.60 | $209.73 | $524.33 |
| iprod-kafka-architecture-cluster | $314.60 | $209.73 | $524.33 |
| iprod-kafka-business-cluster | $314.60 | $209.73 | $524.33 |
| **Total** | | | **$1572.99** |

### Projected Monthly Costs (After Optimization)

| Cluster | Broker Cost | Storage Cost | Total | Savings |
|---------|-------------|--------------|-------|---------|
| iprod-kafka-base-cluster | $270.72 | $180.48 | $451.20 | $73.13 |
| iprod-kafka-architecture-cluster | $270.72 | $180.48 | $451.20 | $73.13 |
| iprod-kafka-business-cluster | $270.72 | $180.48 | $451.20 | $73.13 |
| **Total** | | | **$1353.59** | **$219.40** |

---

## Additional Recommendations

### 1. Enable Enhanced Monitoring

All clusters should have enhanced monitoring enabled for better visibility:

```bash
aws kafka update-monitoring \
    --cluster-arn <cluster-arn> \
    --enhanced-monitoring PER_BROKER
```

### 2. Consider Tiered Storage

For log retention optimization, consider MSK Tiered Storage:
- Hot data on EBS (fast access)
- Cold data on S3 (80% cheaper)
- Available for Kafka 2.8.2+

### 3. Review Partition Count

Based on throughput metrics, review if partition counts are optimal:
- Higher partitions = better parallelism
- Lower partitions = less overhead

### 4. Kafka Version Upgrade Path

Consider upgrading to Kafka 3.x for:
- Better performance
- KRaft mode (removes ZooKeeper dependency)
- Enhanced security features

---

## Migration Risk Matrix

| Risk Factor | iprod-kafka-base-cluster | iprod-kafka-architecture-cluster | iprod-kafka-business-cluster |
|-------------|--------------------------|----------------------------------|------------------------------|
| Multi-AZ | ✅ Yes | ✅ Yes | ✅ Yes |
| CPU Headroom | ⚠️ 28% avg | ✅ 16% avg | ✅ 12% avg |
| Under-replicated | ✅ 0 | ✅ 0 | ✅ 0 |
| Offline Partitions | ✅ 0 | ✅ 0 | ✅ 0 |
| **Overall Risk** | **MEDIUM** | **LOW** | **LOW** |

---

## Files Generated

- CSV Report: `/app/msk_graviton_migration_candidates.csv`
- Analysis Script: `/app/msk_graviton_migration_analysis.py`
- This Report: `/app/msk_graviton_migration_report.md`

# RDS Graviton Migration Opportunity Analysis

**Generated:** 2026-02-05
**Region:** us-east-1
**EDP Discount Applied:** 31%

---

## Executive Summary

Your RDS fleet is **already well-optimized for Graviton**, with 85% of instances (63 out of 74) running on Graviton-based instance classes. There are **11 instances** remaining on x86 architecture that are candidates for migration.

### Key Findings

| Metric | Value |
|--------|-------|
| Total Instances | 74 |
| Already on Graviton | 63 (85%) |
| Migration Candidates | 11 (15%) |
| **Monthly Savings Potential** | **$78.57** |
| **Annual Savings Potential** | **$942.84** |

---

## Graviton Migration Candidates

### Priority 1: High-Value Migrations (PostgreSQL r5/m5)

These instances offer the best ROI for migration effort:

| Instance ID | Engine | Version | Current Class | Target Class | Monthly Cost | Projected | Savings/mo |
|-------------|--------|---------|---------------|--------------|--------------|-----------|------------|
| aws-luckyus-difynew-rw | PostgreSQL | 16.10 | db.r5.xlarge | db.r6g.xlarge | $483.55 | $459.37 | **$24.18** |
| aws-luckyus-dify-rw | PostgreSQL | 16.8 | db.r5.xlarge | db.r6g.xlarge | $483.55 | $459.37 | **$24.18** |
| aws-luckyus-pgilkmap-rw | PostgreSQL | 17.4 | db.m5.large | db.m6g.large | $172.27 | $155.14 | **$17.13** |

**Subtotal Priority 1:** $65.49/month savings ($785.88/year)

### Priority 2: MySQL t3 Instances

| Instance ID | Engine | Version | Current Class | Target Class | Monthly Cost | Projected | Savings/mo |
|-------------|--------|---------|---------------|--------------|--------------|-----------|------------|
| aws-luckyus-iluckyhealth-rw | MySQL | 8.0.40 | db.t3.small | db.t4g.small | $34.25 | $32.24 | $2.01 |
| recovery-dbatest | MySQL | 8.0.40 | db.t3.small | db.t4g.small | $34.25 | $32.24 | $2.01 |

**Subtotal Priority 2:** $4.02/month savings ($48.24/year)

### Priority 3: DocumentDB t3 Instances

| Instance ID | Engine | Version | Current Class | Target Class | Monthly Cost | Projected | Savings/mo |
|-------------|--------|---------|---------------|--------------|--------------|-----------|------------|
| docdb-devops | DocDB | 5.0.0 | db.t3.medium | db.t4g.medium | $34.25 | $32.74 | $1.51 |
| docdb-devops2 | DocDB | 5.0.0 | db.t3.medium | db.t4g.medium | $34.25 | $32.74 | $1.51 |
| docdb-devops3 | DocDB | 5.0.0 | db.t3.medium | db.t4g.medium | $34.25 | $32.74 | $1.51 |
| docdb-iot | DocDB | 5.0.0 | db.t3.medium | db.t4g.medium | $34.25 | $32.74 | $1.51 |
| docdb-iot2 | DocDB | 5.0.0 | db.t3.medium | db.t4g.medium | $34.25 | $32.74 | $1.51 |
| docdb-iot3 | DocDB | 5.0.0 | db.t3.medium | db.t4g.medium | $34.25 | $32.74 | $1.51 |

**Subtotal Priority 3:** $9.06/month savings ($108.72/year)

---

## Engine Version Compatibility

All migration candidates are compatible with Graviton:

| Engine | Min Version for Graviton | Your Versions | Status |
|--------|-------------------------|---------------|--------|
| MySQL | 8.0+ | 8.0.40 | ✅ Compatible |
| PostgreSQL | 13+ | 16.8, 16.10, 17.4 | ✅ Compatible |
| DocumentDB | 4.0+ | 5.0.0 | ✅ Compatible |

---

## Migration Risk Assessment

All candidates are **MEDIUM risk** due to Multi-AZ configuration:

| Risk Level | Instances | Method |
|------------|-----------|--------|
| **MEDIUM** | All 11 | AWS handles failover automatically during modification |

### Multi-AZ Migration Process
1. AWS creates a standby with new instance class
2. Automatic failover occurs (typically 1-2 minutes downtime)
3. Old standby is terminated
4. Minimal application impact with proper connection retry logic

### DocumentDB (Single-AZ) Migration Process
- docdb-devops, docdb-devops2, docdb-devops3, docdb-iot, docdb-iot2, docdb-iot3 are NOT Multi-AZ
- Requires scheduled maintenance window
- Brief downtime during instance class modification

---

## Pending Maintenance Status

Several migration candidates have pending maintenance:

| Instance | Pending Actions |
|----------|-----------------|
| aws-luckyus-dify-rw | OS update, Engine patch (16.8.R2) |
| aws-luckyus-difynew-rw | OS update |
| aws-luckyus-pgilkmap-rw | OS update, Engine patch (17.4.R2) |
| aws-luckyus-iluckyhealth-rw | OS update |
| docdb-devops/devops2/devops3 | OS update |
| docdb-iot/iot2/iot3 | OS update |

**Recommendation:** Combine Graviton migration with pending maintenance to minimize downtime windows.

---

## Recommended Migration Order

### Phase 1: Quick Wins with Highest ROI (Week 1-2)
1. **aws-luckyus-difynew-rw** - PostgreSQL db.r5.xlarge → db.r6g.xlarge ($24.18/mo)
2. **aws-luckyus-dify-rw** - PostgreSQL db.r5.xlarge → db.r6g.xlarge ($24.18/mo)
3. **aws-luckyus-pgilkmap-rw** - PostgreSQL db.m5.large → db.m6g.large ($17.13/mo)

### Phase 2: Low-Priority MySQL (Week 3)
4. **aws-luckyus-iluckyhealth-rw** - MySQL db.t3.small → db.t4g.small ($2.01/mo)
5. **recovery-dbatest** - MySQL db.t3.small → db.t4g.small ($2.01/mo)

### Phase 3: DocumentDB Cluster Updates (Week 4)
6-8. **docdb-devops cluster** (3 instances) - db.t3.medium → db.t4g.medium
9-11. **docdb-iot cluster** (3 instances) - db.t3.medium → db.t4g.medium

---

## Migration Commands

### Example: Migrate PostgreSQL r5 to r6g

```bash
# Modify instance class (Multi-AZ will handle failover)
aws rds modify-db-instance \
    --db-instance-identifier aws-luckyus-difynew-rw \
    --db-instance-class db.r6g.xlarge \
    --apply-immediately

# Monitor the modification
aws rds describe-db-instances \
    --db-instance-identifier aws-luckyus-difynew-rw \
    --query 'DBInstances[0].{Status:DBInstanceStatus,Class:DBInstanceClass}'
```

### Example: Migrate DocumentDB instance

```bash
aws docdb modify-db-instance \
    --db-instance-identifier docdb-devops \
    --db-instance-class db.t4g.medium \
    --apply-immediately
```

---

## Current Fleet Breakdown

### Already on Graviton (No Action Required)

| Instance Class | Count | Monthly Cost (est.) |
|---------------|-------|---------------------|
| db.t4g.micro | 41 | ~$600 |
| db.t4g.medium | 17 | ~$1,100 |
| db.t4g.large | 2 | ~$190 |
| db.t4g.xlarge | 1 | ~$260 |
| db.r6g.large | 2 | ~$330 |

---

## Conclusion

Your RDS fleet is already highly optimized with 85% Graviton adoption. The remaining 11 x86 instances can be migrated for an additional **$942.84 annual savings**.

**Prioritize Phase 1** (3 PostgreSQL instances) which delivers **70% of the total savings** ($785.88/year) while requiring migration of only 3 instances.

---

## Files Generated

- CSV Report: `/app/rds_graviton_migration_candidates.csv`
- Analysis Script: `/app/rds_graviton_migration_analysis.py`
- This Report: `/app/rds_graviton_migration_report.md`

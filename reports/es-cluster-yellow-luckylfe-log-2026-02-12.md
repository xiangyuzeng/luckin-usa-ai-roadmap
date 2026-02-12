# ES Cluster Yellow Status Investigation Report

**Cluster**: `luckylfe-log`
**Alert**: AWS-ES 集群状态 Yellow (`aws_es_cluster_status_yellow == 1`)
**Investigation Time**: 2026-02-12 19:30 UTC
**Severity**: WARNING - Production log ingestion severely degraded

---

## 1. Affected Cluster Summary

| Property | Value |
|---|---|
| **Domain Name** | luckylfe-log |
| **Engine** | Elasticsearch 7.10 |
| **VPC Endpoint** | vpc-luckylfe-log-eh3n6nwo4c43eofoz36j35kni4.us-east-1.es.amazonaws.com |
| **Data Nodes** | 4x m5.large.elasticsearch (2 vCPU, 8 GiB RAM each) |
| **Dedicated Masters** | 3x t3.medium.elasticsearch |
| **EBS Volume** | 80 GB gp2 per node (320 GB total) |
| **Zone Awareness** | 2 AZs (us-east-1a, us-east-1b) |
| **Account** | 257394478466 |

## 2. Current Status (as of 19:30 UTC)

| Metric | Value | Status |
|---|---|---|
| **Cluster Status** | YELLOW | Replica shards unassigned |
| **Unassigned Shards** | **7** | Growing (was 0 before 19:00) |
| **Active Primary Shards** | 558 (stable) | OK - no data loss |
| **Active Total Shards** | 597 (was 604) | 7 replicas lost |
| **Node Count** | 7 (4 data + 3 master) | All nodes present |
| **JVM Memory Pressure** | **99.9%** | CRITICAL |
| **CPU Utilization** | 66% (peak 97%) | HIGH |
| **Free Storage (min node)** | 14.3 GB / 80 GB (82% used) | WARNING - approaching 85% watermark |

## 3. Incident Timeline

```
Time (UTC)     JVM Max%  Unassigned  Indexing(docs/5m)  Search(req/5m)  UsedSpace(GB)
────────────── ──────── ─────────── ────────────────── ─────────────── ─────────────
18:32          78.3%    0           47,814             1,178           161.2
18:37          69.2%    0           49,946             1,018           161.2
18:42          72.1%    0           47,851             1,358           161.2
18:47          97.6%    0           35,091             2,395 <-spike   161.3
18:52          99.9%    0           2,898  <-collapse  27    <-crash   48.1  <-drop!
18:57          99.7%    0           2,679              82              48.2
19:02          99.8%    4           2,654              148             48.1
19:07          99.7%    4           2,780              68              48.2
19:12          99.9%    4           1,814              22              48.2
19:17          100.0%   7           2,647              40              48.2
19:22          100.0%   7           3,327              47              48.2
19:27          99.9%    7           1,902              26              48.2
```

## 4. Root Cause Analysis

### Primary Root Cause: JVM Memory Pressure at Critical Level (99-100%)

The incident follows a clear chain of events:

**Phase 1 - JVM Pressure Build-up (13:00-18:42 UTC)**
- JVM avg pressure climbed steadily from 40% to 48% over 6 hours
- JVM max stayed in the 68-78% range (elevated but manageable)
- The m5.large instances have only **~4 GB JVM heap** (half of 8 GB RAM)
- With **~151 shards per data node** (604 total / 4 nodes), this exceeds the recommended 20-25 shards per GB of heap

**Phase 2 - Search Spike Triggers GC Storm (18:47 UTC)**
- Search rate spiked to **2,395 req/5min** (2x the normal ~1,000)
- This pushed JVM pressure from 78% to **97.6%** in one interval
- CPU spiked to **97%** simultaneously (heavy GC activity)
- Indexing rate began dropping (35K from ~47K)

**Phase 3 - Index Lifecycle Deletion + GC Death Spiral (18:52 UTC)**
- Cluster used space dropped from **161 GB to 48 GB** (index lifecycle/ISM policy deleted old indices)
- Despite freeing 113 GB of disk, JVM remained at 99.9% (segment metadata still in heap)
- Indexing rate collapsed from 47K to **2.9K docs/5min** (94% drop)
- Search rate collapsed from 2,395 to **27 req/5min** (99% drop)
- Bulk indexing requests being rejected/timing out

**Phase 4 - Yellow Status (19:02+ UTC)**
- JVM unable to recover; stuck in full GC loop
- Cluster cannot allocate 7 replica shards due to resource pressure
- Unassigned shards growing: 0 -> 4 -> 7

### Contributing Factors

| Factor | Details | Severity |
|---|---|---|
| **Undersized JVM heap** | m5.large = ~4 GB heap for 151 shards/node | **ROOT CAUSE** |
| **Too many shards per node** | 151 shards/node vs recommended ~100 max | HIGH |
| **Disk usage at 82%** | Approaching 85% high watermark | MEDIUM |
| **No warm/UltraWarm tier** | All data on hot nodes | MEDIUM |
| **Search spike** | 2x normal search load triggered the crash | TRIGGER |

## 5. Production Impact Assessment

### IMPACT: MODERATE-HIGH

| Impact Area | Status | Details |
|---|---|---|
| **Data Loss** | None | All 558 primary shards intact and stable |
| **Log Ingestion** | **SEVERELY DEGRADED** | Dropped from ~47K to ~2K docs/5min (96% reduction) |
| **Search/Query** | **SEVERELY DEGRADED** | Dropped from ~1000 to ~30 req/5min (97% reduction) |
| **Data Durability** | **REDUCED** | 7 replica shards unassigned = reduced redundancy |
| **Kibana/Dashboards** | **SLOW/TIMEOUT** | Queries timing out due to JVM pressure |

**Risk**: If JVM doesn't recover, the cluster could escalate to RED status. Log data from applications may be lost if upstream buffers overflow.

## 6. Recommended Remediation

### Immediate Actions (Do Now)

**Action 1: Force a JVM circuit breaker reset by clearing field data cache**
```bash
# Clear field data cache to free JVM heap immediately
curl -XPOST "https://vpc-luckylfe-log-eh3n6nwo4c43eofoz36j35kni4.us-east-1.es.amazonaws.com/_cache/clear"
```

**Action 2: Reduce replica count on non-critical log indices to free resources**
```bash
# Set replicas to 0 for today's log indices to reduce shard count
curl -XPUT "https://vpc-luckylfe-log-eh3n6nwo4c43eofoz36j35kni4.us-east-1.es.amazonaws.com/*-2026.02.12*/_settings" \
  -H 'Content-Type: application/json' \
  -d '{"index": {"number_of_replicas": 0}}'
```

**Action 3: Force retry shard allocation once JVM recovers**
```bash
curl -XPOST "https://vpc-luckylfe-log-eh3n6nwo4c43eofoz36j35kni4.us-east-1.es.amazonaws.com/_cluster/reroute?retry_failed=true"
```

### Short-Term Fix (Within 24 hours)

**Upgrade instance type from m5.large to m5.xlarge**
- m5.xlarge = 4 vCPU, 16 GiB RAM -> ~8 GB JVM heap (2x current)
- This can be done via AWS Console -> OpenSearch -> luckylfe-log -> Edit domain -> Instance type
- Will trigger a blue/green deployment with zero downtime

### Long-Term Recommendations

1. **Reduce shard count**: Merge small indices, use ILM to rollover indices at larger sizes instead of daily
2. **Add UltraWarm tier**: Move older log indices (>7 days) to UltraWarm for cost-effective storage
3. **Upgrade to OpenSearch**: ES 7.10 is end-of-life; migrate to OpenSearch 2.x for better memory management
4. **Increase EBS volume**: 80 GB gp2 at 82% utilization is tight; increase to 150+ GB gp3
5. **Monitor JVM threshold**: Set alarm at JVM > 80% for early warning

## 7. 中文摘要 (Slack 通知)

```
🟡 [ES告警] luckylfe-log 集群状态 Yellow - 调查报告

📊 当前状态:
• 集群状态: YELLOW (7个副本分片未分配)
• JVM内存压力: 99.9% ⚠️ 严重
• 主分片: 558个, 全部正常 (无数据丢失)
• 日志写入速率: 从 47K/5min 降至 2K/5min (下降96%)
• 搜索速率: 从 1000/5min 降至 30/5min (下降97%)
• 磁盘使用: 82% (接近85%水位线)

🔍 根本原因:
JVM堆内存严重不足导致GC死循环。
m5.large 实例仅有 ~4GB JVM堆, 但每节点承载 151个分片,
远超推荐值(每GB堆内存20-25个分片)。
18:47 UTC 搜索请求突增(2倍正常流量)触发JVM压力飙升至99%+,
导致写入和搜索性能断崖式下降,副本分片无法分配。

⚡ 影响:
• 数据丢失: 无 (主分片完整)
• 日志写入: 严重降级 (96%下降)
• 查询搜索: 严重降级 (97%下降)
• Kibana: 查询超时

🔧 建议修复:
1. [立即] 清理缓存释放JVM: POST /_cache/clear
2. [立即] 降低今日日志索引副本数为0
3. [24h内] 升级实例类型 m5.large → m5.xlarge (JVM翻倍至8GB)
4. [长期] 减少分片数量, 添加UltraWarm层, 升级至OpenSearch 2.x

👤 如需执行修复操作请联系 SRE 值班人员确认。
```

---

*Report generated: 2026-02-12T19:30:00Z*
*Investigator: Claude Code (automated)*

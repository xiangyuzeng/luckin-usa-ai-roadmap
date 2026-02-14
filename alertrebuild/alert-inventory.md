# Luckin Coffee NA — Alert Inventory & Migration Map

> **Version:** 1.0 | **Date:** 2026-02-14 | **Status:** Planned
>
> Complete mapping from the legacy 135-alert system to the rebuilt 72-alert three-tier architecture.
> Source of truth: `/app/alertrebuild/报警面板.html` (alertsData, line 986)

---

## Summary

| Metric | Old System | New System | Change |
|--------|-----------|------------|--------|
| Total Alerts | 135 | 72 | -63 (-47%) |
| Categories | 16 | 10 | -6 (-38%) |
| Priority System | P0/P1/P2/P3 | Info/Warning/Critical | 3-tier escalation |
| P0 Alerts (highest) | 41 (30%) | — | Replaced by severity labels |
| Duplicate Rules | 8 pairs | 0 | Merged |
| _语音 Duplicates | 7 | 0 | Phone via Alertmanager routing |
| Language | Chinese names | English names | Bilingual descriptions |

---

## Category Consolidation (16 → 10)

| New Category | Old Categories Absorbed | Old Count | New Count |
|-------------|------------------------|-----------|-----------|
| **BIZ** | Business (5) | 5 | 10 |
| **DB-RDS** | Database-RDS (11) + Grafana Native (3) | 14 | 12 |
| **DB-REDIS** | Database-Redis (10) | 10 | 10 |
| **DB-ES** | Database-ES (7) | 7 | 6 |
| **DB-MONGO** | Database-Mongo (3) | 3 | 5 |
| **INFRA-K8S** | Pod/Container (11) | 11 | 7 |
| **INFRA-VM** | VM/Host (17) | 17 | 8 |
| **APM** | APM-iZeus (25) + APM-Default (4) | 29 | 6 |
| **PIPELINE** | DataLink (14) | 14 | 4 |
| **PLATFORM** | SMS-UPUSH (9) + Risk Control (9) + Gateway/Network (2) + Database-Exporter (1) | 21 | 4 |
| ~~Priority Levels~~ | Priority Levels (4) | 4 | 0 (eliminated) |
| **TOTAL** | | **135** | **72** |

---

## Eliminated Alerts (63 Total)

### Meta-Alerts (4) — Replaced by severity label system
| Old ID | Old Name | Reason |
|--------|----------|--------|
| ALR-001 | [LCP-Prod-P0] 生产环境紧急告警 | Priority aggregation replaced by `severity: critical` label |
| ALR-002 | [LCP-Prod-P1] 生产环境高优先级告警 | Priority aggregation replaced by `severity: warning` label |
| ALR-003 | [LCP-Prod-P2] 生产环境中优先级告警 | Priority aggregation replaced by `severity: info` label |
| ALR-004 | [LCP-Prod-P3] 生产环境低优先级告警 | Priority aggregation replaced by dashboard filtering |

### _语音 Duplicates (7) — Phone calls handled by Alertmanager routing
| Old ID | Old Name | Base Alert | Reason |
|--------|----------|-----------|--------|
| ALR-022 | AWS RDS Vip 持续一分钟不通_语音 | ALR-021 | Duplicate — Twilio routing via Alertmanager |
| ALR-024 | AWS RDS 发生重启或者主从切换_语音 | ALR-023 | Duplicate — Twilio routing via Alertmanager |
| ALR-031 | AWS Mongo CPU大于90%_语音 | ALR-030 | Duplicate — Twilio routing via Alertmanager |
| ALR-034 | AWS-ES CPU大于90%_语音 | ALR-033 | Duplicate — Twilio routing via Alertmanager |
| ALR-036 | AWS-ES 集群状态Red_语音 | ALR-035 | Duplicate — Twilio routing via Alertmanager |
| ALR-039 | AWS-ES磁盘空间不足10G_语音 | ALR-038 | Duplicate — Twilio routing via Alertmanager |
| ALR-050 | exporter 进程异常 | — | Absorbed into platform exporter-health alert |

### Duplicate PromQL (8) — Merged into single alerts
| Old ID | Duplicate Of | Old Name | Reason |
|--------|-------------|----------|--------|
| ALR-020 | ALR-019 | AWS RDS CPU大于90% (duplicate) | Identical expression, different name format |
| ALR-026 | ALR-025 | AWS-RDS 慢查询大于300 (duplicate) | Identical expression, hyphen vs space in name |
| ALR-028 | ALR-027 | AWS-RDS 活跃线程大于24 (duplicate) | Identical expression, hyphen vs space in name |
| ALR-133 | ALR-025 | Grafana Slow Query Spike | Overlaps with RDS slow query alerts |
| ALR-087 | ALR-088 | 服务器每分钟异常数大于20 | Overlaps with ALR-088 (>5), covered by three-tier |
| ALR-134 | ALR-025 | Grafana Slow Query Critical | Overlaps with RDS slow query three-tier |
| ALR-135 | ALR-025 | Grafana Slow Query Weekly | Overlaps with RDS slow query three-tier |
| ALR-088 | ALR-087 | 服务器每分钟异常数大于5 | Merged into APM exception three-tier |

### iZeus Strategy Duplicates (8) — Consolidated into 1 parameterized rule
| Old ID | Old Name | Reason |
|--------|----------|--------|
| ALR-061 | iZeus-策略2 服务每分钟异常数大于2 | Identical to ALR-060 (策略1) with different strategy name |
| ALR-062 | iZeus-策略3 服务每分钟异常数大于2 | Identical to ALR-060 |
| ALR-063 | iZeus-策略4 服务每分钟异常数大于2 | Identical to ALR-060 |
| ALR-064 | iZeus-策略5 服务每分钟异常数大于3 | Near-identical (threshold 3 vs 2) |
| ALR-065 | iZeus-策略6 服务每分钟异常数大于2 | Identical to ALR-060 |
| ALR-066 | iZeus-策略7 服务每分钟异常数大于2 | Identical to ALR-060 |
| ALR-067 | iZeus-策略8 服务每分钟异常数大于2 | Identical to ALR-060 |
| ALR-068 | iZeus-策略9 服务每分钟异常数大于2 | Identical to ALR-060 |

### DataLink Day/Night Pairs (10) — Merged into 4 alerts + time-based muting
| Old IDs | Old Names | New Alert |
|---------|----------|-----------|
| ALR-005, ALR-006 | 黄金流程延迟/异常（白天） | LCK-PL-001 GoldenFlowPipelineDelay |
| ALR-007, ALR-008 | 离线核心延迟/异常（白天） | LCK-PL-002 CorePipelineDelay |
| ALR-009, ALR-010, ALR-013, ALR-014 | 重要任务延迟/异常（白天+夜晚） | LCK-PL-003 ImportantPipelineDelay |
| ALR-011, ALR-012, ALR-015, ALR-016, ALR-017, ALR-018 | 离线重要/普通延迟/异常 | LCK-PL-004 StandardPipelineDelay |

### VM/K8S Consolidation (9)
| Old IDs | Merged Into | Reason |
|---------|------------|--------|
| ALR-112, ALR-113, ALR-114, ALR-115 | LCK-VM-008 NetworkErrors | 4 NIC alerts → 1 three-tier network alert |
| ALR-089, ALR-090, ALR-091 | LCK-K8-001/002/003 PodCPU | 3 CPU alerts → 3-tier (info/warning/critical) |
| ALR-096, ALR-097 | LCK-K8-005 PodDiskIO | Write/read IO merged into single IO alert |

### SMS/Risk/Platform Misc (17)
| Old IDs | Absorbed Into | Reason |
|---------|--------------|--------|
| ALR-051–059 | LCK-PT-001 SMSDeliveryFailure | 9 SMS alerts → 1 parameterized alert |
| ALR-122–130 | LCK-PT-002/003 RiskControlCircuitBreaker | 9 risk control alerts → 2 alerts (pre-warning + breaker) |
| ALR-050 | LCK-PT-004 ExporterHealth | Exporter down folded into platform health |

---

## New Alert Inventory (72 Alerts)

### BIZ — Business Metrics (10 alerts)

| New ID | New Name | Severity | Tier | Team | Old IDs Replaced | Action | Runbook Summary | First Responder |
|--------|----------|----------|------|------|-----------------|--------|----------------|-----------------|
| LCK-BZ-001 | OrdersCompletedLow_Info | info | 1 | biz-ops | ALR-118 (partial) | SPLIT | Orders < 5 in 10min during business hours. Monitor trend, check for regional outage. | US Biz-Ops |
| LCK-BZ-002 | OrdersCompletedLow_Warning | warning | 2 | biz-ops | ALR-118 (partial) | SPLIT | Orders < 3 in 10min. Check payment service, order service health. Notify team lead. | US Biz-Ops |
| LCK-BZ-003 | OrdersCompletedLow_Critical | critical | 3 | biz-ops | ALR-118, ALR-119 | MERGE | Orders < 1 in 10min. Golden path broken. Immediate escalation to China HQ. | US Biz-Ops + China HQ |
| LCK-BZ-004 | OrdersCancelledHigh_Warning | warning | 2 | biz-ops | ALR-117 | KEEP | Cancellations > 1/5min sustained. Investigate payment failures or UX issues. | US Biz-Ops |
| LCK-BZ-005 | PaymentVolumeLow_Warning | warning | 2 | biz-ops | ALR-121 | KEEP | Payment amount < 500 cents in 5min. Check Stripe integration and payment service. | US Biz-Ops |
| LCK-BZ-006 | PaymentVolumeLow_Critical | critical | 3 | biz-ops | ALR-121 | SPLIT | Payment amount = 0 for 10min. Payment pipeline completely stopped. | US Biz-Ops + China HQ |
| LCK-BZ-007 | RegistrationZero_Warning | warning | 2 | biz-ops | ALR-120 | KEEP | Zero registrations for 10min. Check auth service and registration flow. | US Biz-Ops |
| LCK-BZ-008 | RegistrationZero_Critical | critical | 3 | biz-ops | ALR-120 | SPLIT | Zero registrations for 30min. Registration pipeline broken. | US Biz-Ops + China HQ |
| LCK-BZ-009 | TrafficAnomalySpike_Warning | warning | 2 | biz-ops | — | NEW | Traffic > 3x normal baseline. Possible bot activity or viral event. | US Biz-Ops |
| LCK-BZ-010 | GoldenPathLatencyP99_Warning | warning | 2 | app-ops | — | NEW | End-to-end order p99 latency > 3s. User experience degraded. | US App-Ops |

### DB-RDS — RDS MySQL (12 alerts)

| New ID | New Name | Severity | Tier | Team | Old IDs Replaced | Action | Runbook Summary | First Responder |
|--------|----------|----------|------|------|-----------------|--------|----------------|-----------------|
| LCK-RD-001 | RDSCpuHigh_Info | info | 1 | dba | ALR-019, ALR-020 | MERGE | CPU avg > 50% for 10min. Monitor trend, check for long-running queries. | US DBA |
| LCK-RD-002 | RDSCpuHigh_Warning | warning | 2 | dba | ALR-019, ALR-020 | MERGE | CPU avg > 70% for 5min. Identify top queries, check connection count. | US DBA |
| LCK-RD-003 | RDSCpuHigh_Critical | critical | 3 | dba | ALR-019, ALR-020 | MERGE | CPU avg > 90% for 3min. Kill long queries, consider read replica failover. | US DBA + China HQ |
| LCK-RD-004 | RDSSlowQueries_Info | info | 1 | dba | ALR-025, ALR-026, ALR-133 | MERGE | Slow queries > 10/min for 5min. Review query plans, check index usage. | US DBA |
| LCK-RD-005 | RDSSlowQueries_Warning | warning | 2 | dba | ALR-025, ALR-026 | MERGE | Slow queries > 50/min for 5min. Identify problematic queries, optimize. | US DBA |
| LCK-RD-006 | RDSSlowQueries_Critical | critical | 3 | dba | ALR-025, ALR-026, ALR-134 | MERGE | Slow queries > 200/min for 3min. Emergency query kill, possible index rebuild. | US DBA + China HQ |
| LCK-RD-007 | RDSActiveThreads_Info | info | 1 | dba | ALR-027, ALR-028 | MERGE | Active threads > 12 for 5min. Monitor connection pool, check app behavior. | US DBA |
| LCK-RD-008 | RDSActiveThreads_Warning | warning | 2 | dba | ALR-027, ALR-028 | MERGE | Active threads > 24 for 3min. Connection pool exhaustion risk. | US DBA |
| LCK-RD-009 | RDSActiveThreads_Critical | critical | 3 | dba | ALR-027, ALR-028 | MERGE | Active threads > 48 for 2min. Database near lock-up. Emergency thread kill. | US DBA + China HQ |
| LCK-RD-010 | RDSDiskLow_Warning | warning | 2 | dba | ALR-029 | KEEP | Disk free < 15% for 5min. Purge old logs, check binary log growth. | US DBA |
| LCK-RD-011 | RDSVipUnreachable_Critical | critical | 3 | dba | ALR-021, ALR-022 | MERGE | VIP unreachable for 1min. Check RDS instance status, network connectivity. | US DBA + China HQ |
| LCK-RD-012 | RDSFailover_Critical | critical | 3 | dba | ALR-023, ALR-024 | MERGE | Failover/restart detected. Verify application reconnection, check data consistency. | US DBA + China HQ |

### DB-REDIS — ElastiCache Redis (10 alerts)

| New ID | New Name | Severity | Tier | Team | Old IDs Replaced | Action | Runbook Summary | First Responder |
|--------|----------|----------|------|------|-----------------|--------|----------------|-----------------|
| LCK-RE-001 | RedisCpuHigh_Info | info | 1 | dba | ALR-041 | KEEP | Engine CPU > 50% for 5min. Monitor trend, check command rate. | US DBA |
| LCK-RE-002 | RedisCpuHigh_Warning | warning | 2 | dba | ALR-041 | SPLIT | Engine CPU > 65% for 5min. Check hot keys, evaluate connection count. | US DBA |
| LCK-RE-003 | RedisCpuHigh_Critical | critical | 3 | dba | ALR-040 | KEEP | Engine CPU > 90% for 3min. Identify hot keys, consider scaling. | US DBA + China HQ |
| LCK-RE-004 | RedisMemoryHigh_Warning | warning | 2 | dba | ALR-042 | KEEP | Memory > 80% for 5min. Check TTL compliance, review key growth. | US DBA |
| LCK-RE-005 | RedisMemoryHigh_Critical | critical | 3 | dba | ALR-042 | SPLIT | Memory > 95% for 1min. Eviction risk. Emergency TTL fix or scaling. | US DBA + China HQ |
| LCK-RE-006 | RedisLatencyHigh_Warning | warning | 2 | dba | ALR-044 | KEEP | Command p99 latency > 5ms. Check slow log, evaluate network. | US DBA |
| LCK-RE-007 | RedisEvictions_Warning | warning | 2 | dba | ALR-047 | KEEP | Evictions > 1K/min. Cache miss rate increasing. Review memory policy. | US DBA |
| LCK-RE-008 | RedisConnectionHigh_Warning | warning | 2 | dba | ALR-048, ALR-043 | MERGE | Connection usage > 60% or client blocked. Check connection pool config. | US DBA |
| LCK-RE-009 | RedisNetworkHigh_Warning | warning | 2 | dba | ALR-045, ALR-046 | MERGE | Bandwidth > 32Mbps or buffer > 32MB. Check large key operations. | US DBA |
| LCK-RE-010 | RedisInstanceDown_Critical | critical | 3 | dba | ALR-049 | KEEP | Redis instance unreachable. Check ElastiCache console, verify failover. | US DBA + China HQ |

### DB-ES — Elasticsearch (6 alerts)

| New ID | New Name | Severity | Tier | Team | Old IDs Replaced | Action | Runbook Summary | First Responder |
|--------|----------|----------|------|------|-----------------|--------|----------------|-----------------|
| LCK-ES-001 | ESClusterYellow_Warning | warning | 2 | dba | ALR-037 | KEEP | Cluster yellow for 5min. Unassigned replicas. Check node health. | US DBA |
| LCK-ES-002 | ESClusterRed_Critical | critical | 3 | dba | ALR-035, ALR-036 | MERGE | Cluster red. Data loss risk. Check unassigned primary shards immediately. | US DBA + China HQ |
| LCK-ES-003 | ESCpuHigh_Warning | warning | 2 | dba | ALR-033 | KEEP | Node CPU > 75% for 5min. Check indexing rate, search queries. | US DBA |
| LCK-ES-004 | ESCpuHigh_Critical | critical | 3 | dba | ALR-033, ALR-034 | MERGE | Node CPU > 85% for 3min. Throttle indexing, add nodes. | US DBA + China HQ |
| LCK-ES-005 | ESDiskLow_Warning | warning | 2 | dba | ALR-038 | KEEP | Disk usage > 85%. Rotate indices, delete old data. | US DBA |
| LCK-ES-006 | ESDiskLow_Critical | critical | 3 | dba | ALR-038, ALR-039 | MERGE | Disk usage > 90%. Read-only watermark imminent. Emergency cleanup. | US DBA + China HQ |

### DB-MONGO — MongoDB (5 alerts)

| New ID | New Name | Severity | Tier | Team | Old IDs Replaced | Action | Runbook Summary | First Responder |
|--------|----------|----------|------|------|-----------------|--------|----------------|-----------------|
| LCK-MG-001 | MongoCpuHigh_Warning | warning | 2 | dba | ALR-030 | KEEP | CPU > 70% for 5min. Check slow operations, index coverage. | US DBA |
| LCK-MG-002 | MongoCpuHigh_Critical | critical | 3 | dba | ALR-030, ALR-031 | MERGE | CPU > 90% for 3min. Kill long operations, consider scaling. | US DBA + China HQ |
| LCK-MG-003 | MongoMemoryLow_Warning | warning | 2 | dba | ALR-032 | KEEP | Available memory < 500MB for 3min. Check WiredTiger cache. | US DBA |
| LCK-MG-004 | MongoMemoryLow_Critical | critical | 3 | dba | ALR-032 | SPLIT | Available memory < 200MB for 1min. OOM risk. Emergency action. | US DBA + China HQ |
| LCK-MG-005 | MongoConnectionHigh_Warning | warning | 2 | dba | — | NEW | Connection count > 80% of max. Check connection pool settings. | US DBA |

### INFRA-K8S — Kubernetes/EKS (7 alerts)

| New ID | New Name | Severity | Tier | Team | Old IDs Replaced | Action | Runbook Summary | First Responder |
|--------|----------|----------|------|------|-----------------|--------|----------------|-----------------|
| LCK-K8-001 | PodCpuHigh_Info | info | 1 | k8s-ops | ALR-090 | KEEP | Pod CPU > 50% for 10min. Monitor trend, check HPA config. | US K8s-Ops |
| LCK-K8-002 | PodCpuHigh_Warning | warning | 2 | k8s-ops | ALR-091 | KEEP | Pod CPU > 70% for 5min. Check for CPU throttling, memory leaks. | US K8s-Ops |
| LCK-K8-003 | PodCpuHigh_Critical | critical | 3 | k8s-ops | ALR-089 | KEEP | Pod CPU > 85% for 3min. Scale pods, investigate resource limits. | US K8s-Ops + China HQ |
| LCK-K8-004 | PodRestart_Warning | warning | 2 | k8s-ops | ALR-093 | KEEP | Pod restart > 1 in 2min. Check logs for crash reason. | US K8s-Ops |
| LCK-K8-005 | PodDiskIO_Warning | warning | 2 | k8s-ops | ALR-096, ALR-097 | MERGE | Disk IO > 50MB/s sustained. Check logging volume, data writes. | US K8s-Ops |
| LCK-K8-006 | PodOOM_Critical | critical | 3 | k8s-ops | ALR-094 | KEEP | WSS memory = 100% (OOM). Increase memory limits, check memory leaks. | US K8s-Ops + China HQ |
| LCK-K8-007 | NodeHeartbeatLost_Critical | critical | 3 | k8s-ops | ALR-092 | KEEP | Node heartbeat lost for 5min. Check EC2 instance status, kubelet. | US K8s-Ops + China HQ |

### INFRA-VM — VM/Host (8 alerts)

| New ID | New Name | Severity | Tier | Team | Old IDs Replaced | Action | Runbook Summary | First Responder |
|--------|----------|----------|------|------|-----------------|--------|----------------|-----------------|
| LCK-VM-001 | VMCpuHigh_Warning | warning | 2 | sys-ops | ALR-100, ALR-101 | MERGE | CPU > 80% for 5min or load > 1x cores. Check top processes. | US Sys-Ops |
| LCK-VM-002 | VMCpuHigh_Critical | critical | 3 | sys-ops | ALR-102, ALR-103 | MERGE | CPU > 95% or IOWait > 80% or steal > 10%. Emergency triage. | US Sys-Ops + China HQ |
| LCK-VM-003 | VMMemoryHigh_Warning | warning | 2 | sys-ops | ALR-109 | KEEP | Memory > 85% for 10min. Identify memory consumers, check for leaks. | US Sys-Ops |
| LCK-VM-004 | VMMemoryHigh_Critical | critical | 3 | sys-ops | ALR-109 | SPLIT | Memory > 95% for 5min. OOM imminent. Kill processes or scale. | US Sys-Ops + China HQ |
| LCK-VM-005 | VMDiskHigh_Warning | warning | 2 | sys-ops | ALR-111 | KEEP | Partition > 85% used. Clean logs, extend volume. | US Sys-Ops |
| LCK-VM-006 | VMDiskCritical_Critical | critical | 3 | sys-ops | ALR-104, ALR-105, ALR-111 | MERGE | Partition > 95% or inodes > 95% or read-only. Emergency cleanup. | US Sys-Ops + China HQ |
| LCK-VM-007 | VMInstanceDown_Critical | critical | 3 | sys-ops | ALR-110, ALR-116 | MERGE | Instance heartbeat lost 10min or NIC down. Check EC2 console. | US Sys-Ops + China HQ |
| LCK-VM-008 | VMNetworkErrors_Warning | warning | 2 | sys-ops | ALR-108, ALR-112–115 | MERGE | TCP retransmit > 200/s or packet drops > 20/s. Check NIC, MTU, routes. | US Sys-Ops |

### APM — Application Performance (6 alerts)

| New ID | New Name | Severity | Tier | Team | Old IDs Replaced | Action | Runbook Summary | First Responder |
|--------|----------|----------|------|------|-----------------|--------|----------------|-----------------|
| LCK-AP-001 | ServiceExceptionRate_Warning | warning | 2 | app-ops | ALR-060–068, ALR-073, ALR-087, ALR-088 | MERGE | Service exceptions > 5/min for 3min. Check iZeus traces for root cause. | US App-Ops |
| LCK-AP-002 | ServiceExceptionRate_Critical | critical | 3 | app-ops | ALR-060–068 | MERGE | Service exceptions > 20/min for 2min. Critical service degradation. | US App-Ops + China HQ |
| LCK-AP-003 | ServiceLatencyHigh_Warning | warning | 2 | app-ops | ALR-070 | KEEP | Response time p99 > 1500ms. Check downstream dependencies. | US App-Ops |
| LCK-AP-004 | EndpointFailure_Warning | warning | 2 | app-ops | ALR-071, ALR-072, ALR-074, ALR-075 | MERGE | Endpoint failures > 2/min. Check specific endpoint in iZeus. | US App-Ops |
| LCK-AP-005 | JVMFullGC_Warning | warning | 2 | app-ops | ALR-079, ALR-085 | MERGE | Full GC > 5 or YGC > 500ms. Check heap configuration, memory leaks. | US App-Ops |
| LCK-AP-006 | APMInfraHealth_Warning | warning | 2 | app-ops | ALR-076–078, ALR-080–084 | MERGE | iZeus/OAP node health issue. Check APM pipeline connectivity. | US App-Ops |

### PIPELINE — Data Pipeline (4 alerts)

| New ID | New Name | Severity | Tier | Team | Old IDs Replaced | Action | Runbook Summary | First Responder |
|--------|----------|----------|------|------|-----------------|--------|----------------|-----------------|
| LCK-PL-001 | GoldenFlowPipelineDelay_Critical | critical | 3 | data-arch | ALR-005, ALR-006 | MERGE | Golden flow pipeline delay > 5min or exception. Order sync at risk. | US Data-Arch + China HQ |
| LCK-PL-002 | CorePipelineDelay_Warning | warning | 2 | data-arch | ALR-007, ALR-008 | MERGE | Core offline pipeline delayed or failing. Check DataLink scheduler. | US Data-Arch |
| LCK-PL-003 | ImportantPipelineDelay_Info | info | 1 | data-arch | ALR-009–014 | MERGE | Important pipeline delayed (day or night). Monitor, no immediate action. | US Data-Arch |
| LCK-PL-004 | StandardPipelineDelay_Info | info | 1 | data-arch | ALR-011, ALR-012, ALR-015–018 | MERGE | Standard/routine pipeline delayed. Review during business hours. | US Data-Arch |

### PLATFORM — Platform Services (4 alerts)

| New ID | New Name | Severity | Tier | Team | Old IDs Replaced | Action | Runbook Summary | First Responder |
|--------|----------|----------|------|------|-----------------|--------|----------------|-----------------|
| LCK-PT-001 | SMSDeliveryFailure_Warning | warning | 2 | platform | ALR-051–059 | MERGE | SMS delivery failure rate elevated. Check provider status, fallback config. | US Platform |
| LCK-PT-002 | RiskControlPreWarning_Warning | warning | 2 | risk | ALR-122, ALR-124, ALR-126–130 | MERGE | Risk control approaching circuit breaker. Review rule thresholds. | US Risk |
| LCK-PT-003 | RiskControlCircuitBreaker_Critical | critical | 3 | risk | ALR-123, ALR-125 | MERGE | Risk control circuit breaker triggered. Orders may be blocked. | US Risk + China HQ |
| LCK-PT-004 | GatewayErrorRate_Critical | critical | 3 | platform | ALR-131, ALR-132, ALR-050 | MERGE | Gateway error rate > 15% or network probe failure. Check API gateway, exporter. | US Platform + China HQ |

---

## Old-to-New Mapping (All 135 Alerts)

| Old ID | Old Name (abbreviated) | Old Priority | Disposition | New ID | New Name |
|--------|----------------------|-------------|-------------|--------|----------|
| ALR-001 | [LCP-Prod-P0] | P0 | ELIMINATE | — | Replaced by severity labels |
| ALR-002 | [LCP-Prod-P1] | P1 | ELIMINATE | — | Replaced by severity labels |
| ALR-003 | [LCP-Prod-P2] | P2 | ELIMINATE | — | Replaced by severity labels |
| ALR-004 | [LCP-Prod-P3] | P3 | ELIMINATE | — | Replaced by severity labels |
| ALR-005 | Datalink 黄金流程延迟(白天) | P0 | MERGE | LCK-PL-001 | GoldenFlowPipelineDelay_Critical |
| ALR-006 | Datalink 黄金流程异常(白天) | P0 | MERGE | LCK-PL-001 | GoldenFlowPipelineDelay_Critical |
| ALR-007 | Datalink 离线核心延迟(白天) | P1 | MERGE | LCK-PL-002 | CorePipelineDelay_Warning |
| ALR-008 | Datalink 离线核心异常(白天) | P1 | MERGE | LCK-PL-002 | CorePipelineDelay_Warning |
| ALR-009 | Datalink 重要任务延迟(白天) | P2 | MERGE | LCK-PL-003 | ImportantPipelineDelay_Info |
| ALR-010 | Datalink 重要任务异常(白天) | P2 | MERGE | LCK-PL-003 | ImportantPipelineDelay_Info |
| ALR-011 | Datalink 离线重要延迟(白天) | P2 | MERGE | LCK-PL-004 | StandardPipelineDelay_Info |
| ALR-012 | Datalink 离线重要异常(白天) | P2 | MERGE | LCK-PL-004 | StandardPipelineDelay_Info |
| ALR-013 | Datalink 任务延迟(夜晚) | P2 | MERGE | LCK-PL-003 | ImportantPipelineDelay_Info |
| ALR-014 | Datalink 任务异常(夜晚) | P2 | MERGE | LCK-PL-003 | ImportantPipelineDelay_Info |
| ALR-015 | Datalink 普通任务延迟(白天) | P3 | MERGE | LCK-PL-004 | StandardPipelineDelay_Info |
| ALR-016 | Datalink 普通任务异常(白天) | P3 | MERGE | LCK-PL-004 | StandardPipelineDelay_Info |
| ALR-017 | Datalink 离线普通延迟(白天) | P3 | MERGE | LCK-PL-004 | StandardPipelineDelay_Info |
| ALR-018 | Datalink 离线普通异常(白天) | P3 | MERGE | LCK-PL-004 | StandardPipelineDelay_Info |
| ALR-019 | RDS CPU>90% | P1 | MERGE | LCK-RD-001/002/003 | RDSCpuHigh (three-tier) |
| ALR-020 | RDS CPU>90% (dup) | P1 | ELIMINATE | — | Duplicate of ALR-019 |
| ALR-021 | RDS VIP不通 | P0 | MERGE | LCK-RD-011 | RDSVipUnreachable_Critical |
| ALR-022 | RDS VIP不通_语音 | P0 | ELIMINATE | — | _语音 duplicate |
| ALR-023 | RDS 主从切换 | P0 | MERGE | LCK-RD-012 | RDSFailover_Critical |
| ALR-024 | RDS 主从切换_语音 | P0 | ELIMINATE | — | _语音 duplicate |
| ALR-025 | RDS 慢查询>300 | P2 | MERGE | LCK-RD-004/005/006 | RDSSlowQueries (three-tier) |
| ALR-026 | RDS 慢查询>300 (dup) | P2 | ELIMINATE | — | Duplicate of ALR-025 |
| ALR-027 | RDS 活跃线程>24 | P2 | MERGE | LCK-RD-007/008/009 | RDSActiveThreads (three-tier) |
| ALR-028 | RDS 活跃线程>24 (dup) | P2 | ELIMINATE | — | Duplicate of ALR-027 |
| ALR-029 | RDS 磁盘<10G | P1 | MERGE | LCK-RD-010 | RDSDiskLow_Warning |
| ALR-030 | Mongo CPU>90% | P1 | MERGE | LCK-MG-001/002 | MongoCpuHigh (two-tier) |
| ALR-031 | Mongo CPU>90%_语音 | P0 | ELIMINATE | — | _语音 duplicate |
| ALR-032 | Mongo 内存<500M | P1 | MERGE | LCK-MG-003/004 | MongoMemoryLow (two-tier) |
| ALR-033 | ES CPU>90% | P1 | MERGE | LCK-ES-003/004 | ESCpuHigh (two-tier) |
| ALR-034 | ES CPU>90%_语音 | P0 | ELIMINATE | — | _语音 duplicate |
| ALR-035 | ES 集群Red | P0 | MERGE | LCK-ES-002 | ESClusterRed_Critical |
| ALR-036 | ES 集群Red_语音 | P0 | ELIMINATE | — | _语音 duplicate |
| ALR-037 | ES 集群Yellow | P2 | KEEP | LCK-ES-001 | ESClusterYellow_Warning |
| ALR-038 | ES 磁盘<10G | P1 | MERGE | LCK-ES-005/006 | ESDiskLow (two-tier) |
| ALR-039 | ES 磁盘<10G_语音 | P0 | ELIMINATE | — | _语音 duplicate |
| ALR-040 | Redis CPU>90% | P1 | KEEP | LCK-RE-003 | RedisCpuHigh_Critical |
| ALR-041 | Redis CPU>70% | P2 | MERGE | LCK-RE-001/002 | RedisCpuHigh (info/warning) |
| ALR-042 | Redis 内存>70% | P2 | MERGE | LCK-RE-004/005 | RedisMemoryHigh (two-tier) |
| ALR-043 | Redis 客户端堵塞 | P1 | MERGE | LCK-RE-008 | RedisConnectionHigh_Warning |
| ALR-044 | Redis 时延>2ms | P2 | KEEP | LCK-RE-006 | RedisLatencyHigh_Warning |
| ALR-045 | Redis 缓冲>32m | P2 | MERGE | LCK-RE-009 | RedisNetworkHigh_Warning |
| ALR-046 | Redis 流量>32Mbps | P2 | MERGE | LCK-RE-009 | RedisNetworkHigh_Warning |
| ALR-047 | Redis key淘汰 | P2 | KEEP | LCK-RE-007 | RedisEvictions_Warning |
| ALR-048 | Redis 连接>30% | P2 | MERGE | LCK-RE-008 | RedisConnectionHigh_Warning |
| ALR-049 | Redis 采集失败 | P0 | KEEP | LCK-RE-010 | RedisInstanceDown_Critical |
| ALR-050 | exporter异常 | P0 | MERGE | LCK-PT-004 | GatewayErrorRate_Critical |
| ALR-051 | UPUSH 供应商调用失败>50 | P1 | MERGE | LCK-PT-001 | SMSDeliveryFailure_Warning |
| ALR-052 | UPUSH 供应商返回失败>200 | P1 | MERGE | LCK-PT-001 | SMSDeliveryFailure_Warning |
| ALR-053 | UPUSH 营销短信回执<60% | P2 | MERGE | LCK-PT-001 | SMSDeliveryFailure_Warning |
| ALR-054 | UPUSH 营销短信过滤>100 | P2 | MERGE | LCK-PT-001 | SMSDeliveryFailure_Warning |
| ALR-055 | UPUSH 行业短信回执<70% | P1 | MERGE | LCK-PT-001 | SMSDeliveryFailure_Warning |
| ALR-056 | UPUSH 行业短信过滤>50 | P2 | MERGE | LCK-PT-001 | SMSDeliveryFailure_Warning |
| ALR-057 | UPUSH 验证码同比+30% | P2 | MERGE | LCK-PT-001 | SMSDeliveryFailure_Warning |
| ALR-058 | UPUSH 验证码回执<70% | P1 | MERGE | LCK-PT-001 | SMSDeliveryFailure_Warning |
| ALR-059 | UPUSH 验证码过滤>50 | P2 | MERGE | LCK-PT-001 | SMSDeliveryFailure_Warning |
| ALR-060 | iZeus-策略1 异常>2 | P1 | MERGE | LCK-AP-001/002 | ServiceExceptionRate (two-tier) |
| ALR-061 | iZeus-策略2 异常>2 | P1 | ELIMINATE | — | Duplicate of ALR-060 |
| ALR-062 | iZeus-策略3 异常>2 | P1 | ELIMINATE | — | Duplicate of ALR-060 |
| ALR-063 | iZeus-策略4 异常>2 | P1 | ELIMINATE | — | Duplicate of ALR-060 |
| ALR-064 | iZeus-策略5 异常>3 | P1 | ELIMINATE | — | Duplicate of ALR-060 |
| ALR-065 | iZeus-策略6 异常>2 | P1 | ELIMINATE | — | Duplicate of ALR-060 |
| ALR-066 | iZeus-策略7 异常>2 | P1 | ELIMINATE | — | Duplicate of ALR-060 |
| ALR-067 | iZeus-策略8 异常>2 | P1 | ELIMINATE | — | Duplicate of ALR-060 |
| ALR-068 | iZeus-策略9 异常>2 | P1 | ELIMINATE | — | Duplicate of ALR-060 |
| ALR-069 | iZeus JVM CPU>20 | P2 | MERGE | LCK-AP-005 | JVMFullGC_Warning |
| ALR-070 | iZeus 响应>1500ms | P1 | KEEP | LCK-AP-003 | ServiceLatencyHigh_Warning |
| ALR-071 | iZeus-策略11 端点失败>=1 | P1 | MERGE | LCK-AP-004 | EndpointFailure_Warning |
| ALR-072 | iZeus-策略12 端点失败>=1 | P1 | MERGE | LCK-AP-004 | EndpointFailure_Warning |
| ALR-073 | iZeus-策略15 异常>3 | P1 | MERGE | LCK-AP-001 | ServiceExceptionRate_Warning |
| ALR-074 | iZeus-策略16 端点失败>2 | P1 | MERGE | LCK-AP-004 | EndpointFailure_Warning |
| ALR-075 | iZeus-策略17 端点失败>3 | P1 | MERGE | LCK-AP-004 | EndpointFailure_Warning |
| ALR-076 | iZeus Node-CPU-85 | P1 | MERGE | LCK-AP-006 | APMInfraHealth_Warning |
| ALR-077 | iZeus Node-Disk-85 | P2 | MERGE | LCK-AP-006 | APMInfraHealth_Warning |
| ALR-078 | iZeus Node-Memory-95 | P1 | MERGE | LCK-AP-006 | APMInfraHealth_Warning |
| ALR-079 | iZeus OAP-FGC-5 | P2 | MERGE | LCK-AP-005 | JVMFullGC_Warning |
| ALR-080 | iZeus Storage-Receiver2Thanos | P1 | MERGE | LCK-AP-006 | APMInfraHealth_Warning |
| ALR-081 | iZeus Storage-Receiver2VM | P1 | MERGE | LCK-AP-006 | APMInfraHealth_Warning |
| ALR-082 | iZeus Transfer-Agent2OAP | P1 | MERGE | LCK-AP-006 | APMInfraHealth_Warning |
| ALR-083 | iZeus Transfer-OAP2OAP | P1 | MERGE | LCK-AP-006 | APMInfraHealth_Warning |
| ALR-084 | iZeus Transfer-OAPTrace2Receiver | P1 | MERGE | LCK-AP-006 | APMInfraHealth_Warning |
| ALR-085 | 默认策略 FGC>0 / YGC>500ms | P2 | MERGE | LCK-AP-005 | JVMFullGC_Warning |
| ALR-086 | 默认策略 okhttp异常>50 | P2 | MERGE | LCK-AP-001 | ServiceExceptionRate_Warning |
| ALR-087 | 默认策略 服务异常>20 | P1 | MERGE | LCK-AP-002 | ServiceExceptionRate_Critical |
| ALR-088 | 默认策略 服务异常>5 | P2 | MERGE | LCK-AP-001 | ServiceExceptionRate_Warning |
| ALR-089 | pod-cpu兜底 CPU>85% | P0 | KEEP | LCK-K8-003 | PodCpuHigh_Critical |
| ALR-090 | pod-cpu CPU>50% 10min | P0 | KEEP | LCK-K8-001 | PodCpuHigh_Info |
| ALR-091 | pod-cpu CPU>70% 3min | P0 | KEEP | LCK-K8-002 | PodCpuHigh_Warning |
| ALR-092 | pod-全局 node心跳丢失 | P0 | KEEP | LCK-K8-007 | NodeHeartbeatLost_Critical |
| ALR-093 | pod-全局 Pod 2m内重启 | P0 | KEEP | LCK-K8-004 | PodRestart_Warning |
| ALR-094 | pod-宕机 WSS内存=100% | P1 | KEEP | LCK-K8-006 | PodOOM_Critical |
| ALR-095 | pod-线程 线程>3600 | P0 | MERGE | LCK-K8-003 | PodCpuHigh_Critical |
| ALR-096 | pod-网卡 写入>50MBs | P0 | MERGE | LCK-K8-005 | PodDiskIO_Warning |
| ALR-097 | pod-网卡 读取>50MBs | P0 | MERGE | LCK-K8-005 | PodDiskIO_Warning |
| ALR-098 | pod-网卡 流入>30MBs | P0 | MERGE | LCK-K8-005 | PodDiskIO_Warning |
| ALR-099 | pod-网卡 流出>30MBs | P0 | MERGE | LCK-K8-005 | PodDiskIO_Warning |
| ALR-100 | vm-CPU 负载>1x cores | P1 | MERGE | LCK-VM-001 | VMCpuHigh_Warning |
| ALR-101 | vm-CPU CPU>80% | P1 | MERGE | LCK-VM-001 | VMCpuHigh_Warning |
| ALR-102 | vm-cpu IOWait>80% | P0 | MERGE | LCK-VM-002 | VMCpuHigh_Critical |
| ALR-103 | vm-cpu CPU steal>10% | P0 | MERGE | LCK-VM-002 | VMCpuHigh_Critical |
| ALR-104 | vm-fileSystem inodes>95% | P0 | MERGE | LCK-VM-006 | VMDiskCritical_Critical |
| ALR-105 | vm-fileSystem 只读 | P0 | MERGE | LCK-VM-006 | VMDiskCritical_Critical |
| ALR-106 | vm-io IO>90ms | P0 | MERGE | LCK-VM-002 | VMCpuHigh_Critical |
| ALR-107 | vm-io IO使用率>70% | P1 | MERGE | LCK-VM-001 | VMCpuHigh_Warning |
| ALR-108 | vm-tcp 重传>200 | P0 | MERGE | LCK-VM-008 | VMNetworkErrors_Warning |
| ALR-109 | vm-内存 >90% 10min | P1 | MERGE | LCK-VM-003/004 | VMMemoryHigh (two-tier) |
| ALR-110 | vm-宕机 心跳丢失10min | P0 | MERGE | LCK-VM-007 | VMInstanceDown_Critical |
| ALR-111 | vm-磁盘 >90% | P1 | MERGE | LCK-VM-005/006 | VMDiskHigh (two-tier) |
| ALR-112 | vm-网卡 入丢弃>20 | P0 | MERGE | LCK-VM-008 | VMNetworkErrors_Warning |
| ALR-113 | vm-网卡 入错误>20 | P0 | MERGE | LCK-VM-008 | VMNetworkErrors_Warning |
| ALR-114 | vm-网卡 出丢弃>20 | P0 | MERGE | LCK-VM-008 | VMNetworkErrors_Warning |
| ALR-115 | vm-网卡 出错误>20 | P0 | MERGE | LCK-VM-008 | VMNetworkErrors_Warning |
| ALR-116 | vm-网卡 NIC down | P0 | MERGE | LCK-VM-007 | VMInstanceDown_Critical |
| ALR-117 | 业务 取消订单>1/5min | P1 | KEEP | LCK-BZ-004 | OrdersCancelledHigh_Warning |
| ALR-118 | 业务 完成订单<1/10min | P0 | SPLIT | LCK-BZ-001/002/003 | OrdersCompleted (three-tier) |
| ALR-119 | 业务 支付<1/10min | P0 | MERGE | LCK-BZ-003 | OrdersCompletedLow_Critical |
| ALR-120 | 业务 注册=0/10min | P1 | SPLIT | LCK-BZ-007/008 | RegistrationZero (two-tier) |
| ALR-121 | 业务 支付金额<500分 | P1 | SPLIT | LCK-BZ-005/006 | PaymentVolumeLow (two-tier) |
| ALR-122 | 风控 全局预告警 | P1 | MERGE | LCK-PT-002 | RiskControlPreWarning_Warning |
| ALR-123 | 风控 全局熔断 | P0 | MERGE | LCK-PT-003 | RiskControlCircuitBreaker_Critical |
| ALR-124 | 风控 场景预告警 | P1 | MERGE | LCK-PT-002 | RiskControlPreWarning_Warning |
| ALR-125 | 风控 场景熔断 | P0 | MERGE | LCK-PT-003 | RiskControlCircuitBreaker_Critical |
| ALR-126 | 风控 下单RPC>200+60% | P2 | MERGE | LCK-PT-002 | RiskControlPreWarning_Warning |
| ALR-127 | 风控 支付RPC>200+60% | P2 | MERGE | LCK-PT-002 | RiskControlPreWarning_Warning |
| ALR-128 | 风控 注册RPC>100+60% | P2 | MERGE | LCK-PT-002 | RiskControlPreWarning_Warning |
| ALR-129 | 风控 登录RPC>100+60% | P2 | MERGE | LCK-PT-002 | RiskControlPreWarning_Warning |
| ALR-130 | 风控 短信RPC>100+60% | P2 | MERGE | LCK-PT-002 | RiskControlPreWarning_Warning |
| ALR-131 | 网关错误率>15% | P0 | MERGE | LCK-PT-004 | GatewayErrorRate_Critical |
| ALR-132 | 网络质量探测失败 | P1 | MERGE | LCK-PT-004 | GatewayErrorRate_Critical |
| ALR-133 | Grafana Slow Query Spike | P2 | ELIMINATE | — | Absorbed into RDS slow query three-tier |
| ALR-134 | Grafana Slow Query Critical | P1 | ELIMINATE | — | Absorbed into RDS slow query three-tier |
| ALR-135 | Grafana Slow Query Weekly | P2 | ELIMINATE | — | Absorbed into RDS slow query three-tier |

---

## Severity Distribution (New System)

| Severity | Count | % | Notification Channel |
|----------|-------|---|---------------------|
| Info | 6 | 8% | WeCom text only |
| Warning | 42 | 58% | WeCom + Twilio (team lead) |
| Critical | 24 | 33% | WeCom + Twilio (all DevOps) |
| **Total** | **72** | **100%** | |

## Team Distribution (New System)

| Team | Alert Count | Categories |
|------|------------|------------|
| dba | 33 | DB-RDS, DB-REDIS, DB-ES, DB-MONGO |
| k8s-ops | 7 | INFRA-K8S |
| sys-ops | 8 | INFRA-VM |
| app-ops | 7 | APM, BIZ (partial) |
| biz-ops | 9 | BIZ |
| data-arch | 4 | PIPELINE |
| risk | 2 | PLATFORM (partial) |
| platform | 2 | PLATFORM (partial) |
| **Total** | **72** | |

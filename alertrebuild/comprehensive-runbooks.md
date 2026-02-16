# Luckin Coffee NA — Comprehensive Bilingual Runbooks

> **Prompt:** 1.2 | **Version:** 1.0 | **Date:** 2026-02-16 | **Status:** Complete
>
> Comprehensive bilingual (English + Chinese) runbooks for all 72 production alerts.
> Structure: Merged 5A Response Pattern + 12-Section Old SOP format.

---

## Document Structure

This document contains full bilingual runbooks for all 72 alerts across 10 categories.
Each runbook follows the **Merged 5A + 12-Section** structure:

| 5A Phase | Old SOP Sections Merged | Key Content |
|----------|------------------------|-------------|
| **1. ASSESS** (评估) | 告警概览, 告警描述, 告警解析 | Metadata, meaning, golden path check |
| **2. ACKNOWLEDGE** (确认) | 立即响应 (partial) | Silence alert, WeCom post, SLA timers |
| **3. ANALYZE** (分析) | 系统访问, 诊断命令, 根因分析 | Diagnostic commands, root causes |
| **4. ACT** (行动) | 处理步骤, 升级标准 | Tier-based remediation, escalation |
| **5. AFTERMATH** (善后) | 预防措施, 相关告警 | Prevention, related alerts, KB update |

---

## Common Reference / 通用参考

### Datasource UIDs / 数据源UID

| Datasource | UID | Purpose |
|------------|-----|---------|
| UMBQuerier-Luckin | `df8o21agxtkw0d` | Primary Prometheus (node, RDS, business metrics) |
| prometheus | `ff7hkeec6c9a8e` | General metrics |
| prometheus_redis | `ff6p0gjt24phce` | Redis/ElastiCache metrics |

### VMAlert Endpoints / VMAlert节点

| Instance | IP:Port | Role |
|----------|---------|------|
| APM-1 | 10.238.3.137:8880 | APM alert evaluation |
| APM-2 | 10.238.3.143:8880 | APM alert evaluation |
| APM-3 | 10.238.3.52:8880 | APM alert evaluation |
| Basic | 10.238.3.153:8880 | Infrastructure alert evaluation |

### AWS Environment / AWS环境

| Resource | Value |
|----------|-------|
| Account ID | 257394478466 |
| Region | us-east-1 |
| EKS Cluster | luckyus-prod |
| DevOps DB | aws-luckyus-devops-rw |

### SLA Timers / SLA时间要求

| Tier | Acknowledge / 确认 | First Update / 首次更新 | Resolution / 解决 |
|------|-------------------|----------------------|-------------------|
| Tier 1 (Info) | 30 min | 2 hours | 8 hours |
| Tier 2 (Warning) | 15 min | 1 hour | 4 hours |
| Tier 3 (Critical) | 5 min | 15 min | 1 hour |

### Notification Channels / 通知渠道

| Channel | Tier | Recipients |
|---------|------|-----------|
| wecom-info | Tier 1 | US DevOps (text only) |
| wecom-warning | Tier 2 | US DevOps + Team Lead (text + phone lead) |
| wecom-critical | Tier 3 | All DevOps US + China HQ (text + phone all) |

### Escalation Path / 升级路径

```
Tier 1 → (15 min no resolution) → Tier 2 → (30 min no resolution) → Tier 3
                                                                        ↓
                                                             China HQ Engineering
                                                             中国总部工程团队
```

### Golden Path Check / 黄金流程检查

```
Golden Path = User Order Flow (用户下单流程):
1. Open App (打开App) → 2. Browse Menu (浏览菜单) → 3. Place Order (下单)
4. Payment (支付) → 5. Order Complete (完成订单)

PromQL check:
  sum_over_time(business_completed_orders_total[10m])
  → If == 0 for 10 min → Golden path is DOWN → Tier 3 Critical
```

### Skill File References / 技能文件参考

| Category | Skill File | Invocation |
|----------|-----------|------------|
| EC2/VM | `/app/skills/ec2-alert-investigation.md` | `/investigate-ec2` |
| RDS | `/app/skills/rds-alert-investigation.md` | `/investigate-rds` |
| Kubernetes | `/app/skills/k8s-alert-investigation.md` | `/investigate-k8s` |
| Redis | `/app/skills/redis-alert-investigation.md` | `/investigate-redis` |
| Elasticsearch | `/app/skills/elasticsearch-alert-investigation.md` | `/investigate-elasticsearch` |
| APM | `/app/skills/apm-alert-investigation.md` | `/investigate-apm` |

---

## Category Index / 分类索引

| # | Category | Alerts | File Section |
|---|----------|--------|-------------|
| 1 | BIZ — Business Metrics / 业务指标 | BIZ-01 to BIZ-10 | [Part 1](#part-1-biz--business-metrics) |
| 2 | DB-RDS — RDS MySQL / 数据库RDS | RDS-01 to RDS-12 | [Part 2](#part-2-db-rds--rds-mysql) |
| 3 | DB-REDIS — ElastiCache Redis | REDIS-01 to REDIS-10 | [Part 3](#part-3-db-redis--elasticache-redis) |
| 4 | DB-ES — Elasticsearch | ES-01 to ES-06 | [Part 4](#part-4-db-es--elasticsearch) |
| 5 | DB-MONGO — MongoDB/DocumentDB | MONGO-01 to MONGO-05 | [Part 5](#part-5-db-mongo--mongodbdocumentdb) |
| 6 | INFRA-K8S — Kubernetes/EKS | K8S-01 to K8S-07 | [Part 6](#part-6-infra-k8s--kuberneteseks) |
| 7 | INFRA-VM — VM/Host | VM-01 to VM-08 | [Part 7](#part-7-infra-vm--vmhost) |
| 8 | APM — Application Performance | APM-01 to APM-06 | [Part 8](#part-8-apm--application-performance) |
| 9 | PIPELINE — Data Pipeline | PIPE-01 to PIPE-04 | [Part 9](#part-9-pipeline--data-pipeline) |
| 10 | PLATFORM — Platform Services | PLAT-01 to PLAT-04 | [Part 10](#part-10-platform--platform-services) |

---

*Individual category runbooks follow in Parts 1-10.*
*Each part is generated separately and appended below.*


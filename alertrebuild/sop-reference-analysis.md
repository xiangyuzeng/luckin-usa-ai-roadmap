# Old Dashboard SOP Reference Analysis

> **Prompt 1.1 Output** — Extracted from `/app/alertrebuild/报警面板.html` (41,498 lines, 135 alerts)
>
> Purpose: Establish the SOP structure, detail level, and Luckin-specific context as a reference baseline for writing new runbooks.

---

## 1. Source Dashboard Summary

| Property | Value |
|----------|-------|
| File | `报警面板.html` |
| Total alerts | 135 (ALR-001 through ALR-135) |
| Data structure | JavaScript `const alertsData = [...]` starting at line 986 |
| SOP field | `handbook` property (markdown string, 250-350 lines each) |
| Language | Chinese (Simplified) |

### Old Category → New Category Mapping

| Old Category | ALR Range | Count | New Category |
|-------------|-----------|-------|--------------|
| Business | ALR-117 to ALR-121 | 5 | **BIZ** |
| Database-RDS | ALR-019 to ALR-029 | 11 | **DB-RDS** |
| Database-Redis | ALR-040 to ALR-049 | 10 | **DB-REDIS** |
| Database-ES | ALR-033 to ALR-039 | 7 | **DB-ES** |
| Database-Mongo | ALR-030 to ALR-032 | 3 | **DB-MONGO** |
| Pod/Container | ALR-089 to ALR-099 | 11 | **INFRA-K8S** |
| VM/Host | ALR-100 to ALR-116 | 17 | **INFRA-VM** |
| APM-iZeus + APM-Default | ALR-060 to ALR-088 | 29 | **APM** |
| DataLink | ALR-005 to ALR-018 | 14 | **PIPELINE** |
| Database-Exporter + SMS-UPUSH + Risk Control + Priority Levels | ALR-001 to ALR-004, ALR-050 to ALR-059, ALR-122 to ALR-135 | 28 | **PLATFORM** |

---

## 2. Standard SOP Structure (12 Sections)

Every old SOP follows this exact section layout. The section headings are in Chinese with consistent formatting:

```
1.  # ALR-NNN【Category】Alert Name              ← Title line
2.  > 瑞幸咖啡美国运维告警响应参考手册              ← Standard header block
3.  ## 告警概览 (Alert Overview)                   ← Metadata table
4.  ## 告警描述 (Alert Description)                ← Priority/service level statement
5.  ## 告警解析 (Alert Analysis)                   ← Root cause context
      - 告警含义 (Alert Meaning)
      - 业务影响 (Business Impact)
      - 受影响服务 (Affected Services)
      - PromQL表达式 (PromQL Expression)
      - 常见根因 (Common Root Causes)
6.  ## 立即响应 (Immediate Response)               ← 3-step response pattern
      - 第一步: 评估黄金流程影响 (Assess golden flow impact)
      - 第二步: 初步诊断 (Initial diagnosis)
      - 第三步: 深入排查 (Deep investigation)
7.  ## 系统访问方式 (System Access Methods)         ← Shared boilerplate
8.  ## 诊断命令 (Diagnostic Commands)              ← Category-specific commands
9.  ## 根因分析 (Root Cause Analysis)              ← Causes + Luckin-specific causes + checklist
10. ## 处理步骤 (Handling Steps)                   ← Multi-scenario remediation
11. ## 升级标准 (Escalation Standards)             ← Escalation condition table
12. ## 预防措施 (Prevention Measures)              ← Prevention bullet list
13. ## 相关告警 (Related Alerts)                   ← Co-firing alerts
```

### Section Detail — Metadata Table (告警概览)

Always a 6-row table:

| 属性 | 值 |
|------|-----|
| **告警ID** | ALR-NNN |
| **告警名称** | Full Chinese alert name |
| **优先级** | P0 / P1 / P2 |
| **服务等级** | L0 / L1 / L2 |
| **类别** | Category label |
| **响应时间** | 立即响应（< 5分钟） / 快速响应（< 15分钟） / 标准响应（< 30分钟） |

### Response Time by Priority

| Priority | Response Time | Chinese Label |
|----------|--------------|---------------|
| P0 | < 5 minutes | 立即响应 |
| P1 | < 15 minutes | 快速响应 |
| P2 | < 30 minutes | 标准响应 |

---

## 3. Two Quality Tiers — Critical Finding

**The old SOPs have two distinct quality levels:**

### Tier A: Fully Customized (Exemplary SOPs)

These have alert-specific diagnostic commands, scenario-based handling steps, and accurate PromQL/descriptions.

**Representative examples:**
- **ALR-019** (DB-RDS CPU > 90%) — the gold standard
- **ALR-040** (DB-Redis CPU > 90%)
- **ALR-117** (Business cancel orders)
- **ALR-092** (K8S node heartbeat lost)

**Characteristics:**
- `告警含义` matches the actual alert condition
- `诊断命令` has technology-specific commands (MySQL SHOW PROCESSLIST, redis-cli INFO, kubectl describe)
- `处理步骤` has multiple named scenarios (e.g., "慢查询导致CPU过高", "连接数过多导致CPU过高")
- `常见根因` lists 4-6 specific causes relevant to the alert type
- `相关告警` lists actual co-firing alerts by name

### Tier B: Template-Generated (Generic SOPs)

These were generated from a template and contain content that does NOT match the alert type.

**Representative examples:**
- **ALR-035** (ES Cluster Red) — `告警含义` says "RDS VIP连续1分钟无法访问" (wrong — should describe ES Red)
- **ALR-060** (iZeus exceptions) — `告警含义` says "Pod CPU使用率连续3分钟超过85%" (wrong — should describe APM exceptions)
- **ALR-030** (Mongo CPU > 90%) — `告警含义` says "RDS MySQL实例的CPU使用率" (wrong — should say DocumentDB)
- **ALR-100** (VM CPU load) — `告警含义` says "CPU平均使用率超过80%" (close but imprecise for load average)
- **ALR-050** (Exporter process) — `告警含义` says "Redis有客户端处于阻塞状态" (wrong — should describe exporter down)

**Characteristics:**
- `告警含义` is copied from a different alert's SOP
- `诊断命令` are generic or from wrong technology
- `处理步骤` are generic 5-step placeholders ("检查服务状态和日志", "分析告警触发原因", etc.)
- `根因分析 > Luckin系统特定原因` is identical boilerplate across all alerts
- `相关告警` uses placeholder text ("相关类别的其他告警", "依赖服务的告警")
- `预防措施` uses generic operational advice

**Implication for new runbooks:** The Tier B alerts need to be rewritten from scratch, not translated. Only Tier A SOPs should be used as content references.

---

## 4. Shared Boilerplate — System Access Methods

The `系统访问方式` section is **100% identical** across all 135 alerts. It contains:

### AWS Console
```
Account ID: 257394478466
Region: us-east-1 (美东)
Console URL: https://257394478466.signin.aws.amazon.com/console
```

### AWS CLI
```bash
aws sts get-caller-identity
aws configure get region  # should return us-east-1
```

### Database Access (RDS MySQL)
```
JumpServer跳板机 (recommended)
MySQL client via VPN:
  - 订单库: aws-luckyus-salesorder-rw.cxwu08m2qypw.us-east-1.rds.amazonaws.com
  - 支付库: aws-luckyus-salespayment-rw.cxwu08m2qypw.us-east-1.rds.amazonaws.com
  - 风控库: aws-luckyus-iriskcontrolservice-rw.cxwu08m2qypw.us-east-1.rds.amazonaws.com
```

### Redis Access (ElastiCache)
```
  - 订单缓存: luckyus-isales-order.xxxxx.use1.cache.amazonaws.com
  - 会话缓存: luckyus-session.xxxxx.use1.cache.amazonaws.com
  - 认证缓存: luckyus-unionauth.xxxxx.use1.cache.amazonaws.com
```

### Kubernetes Access (EKS)
```bash
aws eks update-kubeconfig --name <CLUSTER_NAME> --region us-east-1
kubectl get pods -n <NAMESPACE>
kubectl logs -f <POD_NAME> -n <NAMESPACE>
```

### Monitoring System
```
Grafana Datasource UIDs:
  - MySQL指标: ff7hkeec6c9a8e
  - Redis指标: ff6p0gjt24phce
  - 主Prometheus: df8o21agxtkw0d

VMAlert:
  - APM instances: 10.238.3.137:8880, 10.238.3.143:8880, 10.238.3.52:8880
  - Basic instance: 10.238.3.153:8880
  - Config: /etc/rules/alert_rules.json
```

### Key RDS Instance List (in 诊断命令 boilerplate)
```
aws-luckyus-salesorder-rw       — 订单主库 (L0核心)
aws-luckyus-salespayment-rw     — 支付主库 (L0核心)
aws-luckyus-iriskcontrolservice-rw — 风控主库
aws-luckyus-framework01-rw      — 框架库01
aws-luckyus-framework02-rw      — 框架库02
```

**Recommendation for new system:** Extract this shared context into a single "System Access Reference" page linked from all runbooks, rather than duplicating it 72 times.

---

## 5. Category-Specific Analysis — Representative SOPs

### 5.1 BIZ — ALR-117 (Business: Cancel Orders)

**Source:** Lines 35665–35964, ~300 lines

| Field | Value |
|-------|-------|
| Priority | P1 |
| Service Level | L0 |
| Response Time | < 15 minutes |
| PromQL | `sum_over_time(business_completed_orders_total[10m]) < 1` |
| Quality Tier | **A** (Customized) |

**Key content:**
- `告警含义`: Describes the golden flow (新建-付款-完成 order chain) being disrupted for 10 minutes
- `常见根因`: Lists 6 specific causes — isales-order service, salespayment service, salesorder-rw DB, session Redis, upstream auth, external payment (Stripe)
- `诊断命令`: Checks isalesorderservice pods, business metrics Grafana dashboard
- `相关告警`: Lists actual alert names

**Luckin-specific context extracted:**
- Golden flow = 新建(Create) → 付款(Pay) → 完成(Complete) order chain
- isalesorderservice is the core order microservice
- Stripe is the payment processor
- Business impact is measured in revenue loss per minute

---

### 5.2 DB-RDS — ALR-019 (RDS CPU > 90%)

**Source:** Lines 5979–6328, ~350 lines

| Field | Value |
|-------|-------|
| Priority | P1 |
| Service Level | L0 |
| Response Time | < 15 minutes |
| PromQL | `avg_over_time(aws_rds_cpuutilization_average[3m]) >= 90` |
| Quality Tier | **A** (Gold standard — most detailed SOP) |

**Key content — Diagnostic Commands:**
```sql
-- MySQL diagnostics
SHOW PROCESSLIST;
SHOW ENGINE INNODB STATUS;
SELECT * FROM information_schema.INNODB_TRX;
SHOW VARIABLES LIKE 'max_connections';
SHOW STATUS LIKE 'Threads_connected';
```
```bash
# AWS CloudWatch
aws cloudwatch get-metric-statistics --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=aws-luckyus-salesorder-rw \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 --statistics Average Maximum
```

**Key content — Multi-scenario Handling:**
- Scenario 1: 慢查询导致CPU过高 (Slow queries causing high CPU)
  - SHOW PROCESSLIST → identify long queries → EXPLAIN → add indexes or KILL
- Scenario 2: 连接数过多导致CPU过高 (Too many connections)
  - Check connection pool settings → identify source → adjust max_connections

---

### 5.3 DB-REDIS — ALR-040 (Redis CPU > 90%)

**Source:** Lines 13228–13566, ~340 lines

| Field | Value |
|-------|-------|
| Priority | P1 |
| Service Level | L0 |
| Response Time | < 15 minutes |
| PromQL | `aws_elasticache_cpuutilization_average >= 90` |
| Quality Tier | **A** (Customized) |

**Key content — Diagnostic Commands:**
```bash
# ElastiCache diagnostics
aws elasticache describe-cache-clusters --show-cache-node-info
redis-cli -h [REDIS_ENDPOINT] INFO memory
redis-cli -h [REDIS_ENDPOINT] CLIENT LIST
redis-cli -h [REDIS_ENDPOINT] SLOWLOG GET 10
```

**Key content — Multi-scenario Handling:**
- Scenario: 内存使用过高 (High memory)
  - INFO memory → --bigkeys → check TTL policies → cleanup → scale up
- Scenario: 客户端连接问题 (Client connection issues)
  - CLIENT LIST → identify abnormal sources → check pool config → CLIENT KILL

---

### 5.4 DB-ES — ALR-035 (OpenSearch Cluster Status Red)

**Source:** Lines 11545–11868, ~320 lines

| Field | Value |
|-------|-------|
| Priority | P0 |
| Service Level | L0 |
| Response Time | < 5 minutes |
| PromQL | `aws_es_cluster_status_red == 1` |
| Quality Tier | **B** (Template-generated — `告警含义` incorrectly says "RDS VIP连续1分钟无法访问") |

**Diagnostic commands (ES-specific, correctly placed):**
```bash
aws opensearch describe-domain --domain-name [DOMAIN_NAME]
curl -X GET "https://[OPENSEARCH_ENDPOINT]/_cluster/health?pretty"
curl -X GET "https://[OPENSEARCH_ENDPOINT]/_cat/nodes?v"
curl -X GET "https://[OPENSEARCH_ENDPOINT]/_cat/indices?v"
```

**Issue:** Despite having correct ES diagnostic commands in the `诊断命令` section, the `告警含义`, `业务影响`, `处理步骤` sections all contain content from the RDS VIP template. The new runbook must be written from scratch using the ES diagnostic commands as a starting point.

---

### 5.5 DB-MONGO — ALR-030 (DocumentDB CPU > 90%)

**Source:** Lines 9912–10236, ~325 lines

| Field | Value |
|-------|-------|
| Priority | P1 |
| Service Level | L0 |
| Response Time | < 15 minutes |
| PromQL | `avg_over_time(aws_docdb_cpuutilization_average[3m]) >= 90` |
| Quality Tier | **B** (Template-generated — `告警含义` says "AWS RDS MySQL实例" instead of DocumentDB) |

**Diagnostic commands (Mongo-specific, correctly placed):**
```bash
aws docdb describe-db-clusters
aws docdb describe-db-instances
mongo --host [DOCDB_ENDPOINT] --eval "db.currentOp()"
mongo --host [DOCDB_ENDPOINT] --eval "db.serverStatus()"
```

**Luckin-specific context:**
- Affected services listed: 风控服务 (Risk Control Service)
- This confirms DocumentDB is primarily used by the iriskcontrolservice

---

### 5.6 INFRA-K8S — ALR-092 (K8S Node Heartbeat Lost)

**Source:** Lines 28278–28577, ~300 lines (read in previous session)

| Field | Value |
|-------|-------|
| Priority | P0 |
| Service Level | L0 |
| Response Time | < 5 minutes |
| PromQL | `kube_node_status_condition{condition="Ready",status="true"} == 0` |
| Quality Tier | **A** (Customized) |

**Key content — Diagnostic Commands:**
```bash
kubectl get nodes
kubectl describe node [NODE_NAME]
kubectl get pods -A --field-selector spec.nodeName=[NODE_NAME]
kubectl top nodes
kubectl top pods -A --sort-by=cpu
kubectl logs -n kube-system [POD] --previous
```

**Key content — Root Causes:**
- OOM Kill by kubelet
- Liveness/Readiness probe failures
- Pod eviction due to resource pressure
- Node NotReady due to kubelet crash
- EBS volume issues on AWS

---

### 5.7 INFRA-VM — ALR-100 (VM CPU Load > Cores)

**Source:** Lines 30740–31025, ~285 lines

| Field | Value |
|-------|-------|
| Priority | P2 |
| Service Level | L1 |
| Response Time | < 30 minutes |
| PromQL | `avg_over_time(node_load1[5m]) > count(node_cpu_seconds_total{mode="idle"})` |
| Quality Tier | **B** (Template-generated — generic content, but diagnostic commands are correctly VM-specific) |

**Diagnostic commands (VM-specific):**
```bash
top -bn1 | head -20
free -h
df -h
iostat -x 1 5
netstat -tunlp | head -20
ss -tunlp | head -20
```

**Handling steps correctly cover two scenarios:**
- CPU使用率过高: top → analyze high-CPU processes → check for anomalies → optimize/scale
- 磁盘空间不足: df -h → du -sh /* → clean logs/tmp → expand disk

**Related alerts listed (specific, not placeholder):**
- CPU平均使用率超过80%
- 内存使用率持续10分钟超过90%
- 磁盘使用率超过90%
- 心跳丢失超过10分钟
- 文件系统只读

---

### 5.8 APM — ALR-060 (iZeus Service Exceptions > 2/min)

**Source:** Lines 19380–19657, ~278 lines

| Field | Value |
|-------|-------|
| Priority | P1 |
| Service Level | L0 |
| Response Time | < 15 minutes |
| PromQL | `izeus_service_exception_count_per_minute > 2` |
| Quality Tier | **B** (Template-generated — `告警含义` incorrectly says "Pod CPU使用率连续3分钟超过85%") |

**Diagnostic commands (APM-specific):**
```bash
kubectl get pods -A | grep -i [SERVICE_NAME]
kubectl logs -n [NAMESPACE] [POD_NAME] --tail=100
# Check Grafana dashboards for detailed metrics
```

**Issue:** The iZeus APM alerts (ALR-060 to ALR-084 = 25 alerts!) all use the same template. The new APM runbooks need iZeus-specific diagnostic content: exception trace analysis, service dependency mapping, iZeus dashboard navigation.

---

### 5.9 PIPELINE — ALR-005 (DataLink Golden Flow Delay)

**Source:** Lines 2095–2376, ~280 lines

| Field | Value |
|-------|-------|
| Priority | P0 |
| Service Level | L0 |
| Response Time | < 5 minutes |
| PromQL | `datalink_golden_flow_delay_seconds > 300` |
| Quality Tier | **A** (Partially customized — good root causes, but template handling steps) |

**Diagnostic commands (Pipeline-specific):**
```bash
# DataLink task status — via DataLink admin console
kafka-consumer-groups.sh --bootstrap-server [KAFKA_BROKER] --describe --group [GROUP_NAME]
# Flink job status — via Flink Dashboard
```

**Luckin-specific context:**
- Golden flow pipeline monitors: 新建-付款-完成 order chain data sync
- Services: DataLink, 订单同步, 库存同步
- Root causes: isales-order service, salespayment service, salesorder-rw DB, session Redis, Stripe payment channel

---

### 5.10 PLATFORM — ALR-050 (DB Exporter Process Abnormal)

**Source:** Lines 16616–16759, ~145 lines (shortest SOP)

| Field | Value |
|-------|-------|
| Priority | P2 |
| Service Level | L1 |
| Response Time | < 30 minutes |
| PromQL | `up{job=~".*exporter.*"} == 0` |
| Quality Tier | **B** (Template-generated — `告警含义` says "Redis有客户端处于阻塞状态") |

**Note:** Platform-type alerts in the old system are scattered across several categories (Database-Exporter, SMS-UPUSH, Risk Control, Priority Levels). The new PLATFORM category consolidates monitoring infrastructure, notification services, and cross-cutting concerns.

---

## 6. Luckin-Specific Operational Context (Extracted)

### Golden Flow (黄金流程)
The most critical concept in Luckin NA operations:
```
用户打开App → 浏览菜单 → 选择商品 → 下单 → 支付 → 完成
(Open App)  → (Browse)  → (Select)  → (Order) → (Pay) → (Complete)
```

### Service Tiers
| Level | Label | Description | Examples |
|-------|-------|-------------|----------|
| L0 | 核心 | Golden flow services | salesorder-rw, salespayment-rw |
| L1 | 重要 | Important supporting | framework01-rw, framework02-rw |
| L2 | 一般 | Non-critical | analytics, reporting |

### Priority Response Escalation
| Condition | Chinese | Escalation Target |
|-----------|---------|-------------------|
| Initial response cannot resolve | 初次响应无法解决 | DevOps值班成员 (on-call) |
| Problem worsening | 问题持续恶化 | Team Lead |
| External support needed | 需要外部支持 | AWS/供应商支持 |
| Golden flow impacted (P0) | 黄金流程受影响 | 通知中国团队所有相关成员（包括半夜唤醒）|

### Key Infrastructure Identifiers
```
AWS Account: 257394478466
AWS Region: us-east-1
RDS Endpoint Suffix: .cxwu08m2qypw.us-east-1.rds.amazonaws.com
Redis Endpoint Pattern: luckyus-{name}.xxxxx.use1.cache.amazonaws.com
RDS Instance Pattern: aws-luckyus-{service}-rw
```

### Escalation to China Team
For P0 golden flow incidents, the SOP explicitly says:
> "通知中国团队所有相关成员（包括半夜唤醒）" — Notify all relevant China team members (including waking them at night)

This cross-timezone escalation pattern is unique to Luckin NA operations.

---

## 7. Key Recommendations for New Runbooks

### Structure
1. **Keep the 12-section structure** — it's well-designed and comprehensive
2. **Extract shared boilerplate** (System Access Methods) into a linked reference page
3. **Add the 5A pattern** from the new runbook template (Assess → Acknowledge → Analyze → Act → Aftermath) as a wrapper around the existing 3-step response
4. **Use bilingual headers** (Chinese + English) for the NA team

### Content Quality
5. **Write ALL 72 runbooks at Tier A quality** — the Tier B template approach produced incorrect content
6. **Validate `告警含义` matches the actual PromQL** — the #1 quality issue in old SOPs
7. **Include category-specific diagnostic commands** — not generic placeholders
8. **Write scenario-based handling steps** — at least 2 scenarios per alert

### Luckin Context
9. **Preserve golden flow assessment** as the first step for all P0/P1 alerts
10. **Keep the China team escalation path** for P0 incidents
11. **Include actual service/instance names** (salesorder-rw, salespayment-rw, etc.) not placeholders
12. **Map each alert to affected microservices** with service dependency context

### What to NOT Carry Forward
13. **Remove the identical `实时数据库诊断` block** from non-RDS alerts — it appears in ES, Mongo, APM alerts where it's irrelevant
14. **Remove the identical Luckin特定原因 block** that lists the same 4 RDS/Redis causes in every alert regardless of category
15. **Remove placeholder `相关告警`** — use actual alert IDs from the new system or leave blank

---

## 8. SOP Section Template (For New Runbook Writers)

Based on the best Tier A examples, here is the expected content depth per section:

| Section | Expected Content | Lines |
|---------|-----------------|-------|
| 告警概览 | 6-row metadata table | 10 |
| 告警描述 | 1-2 sentence priority statement | 3 |
| 告警解析 | 5 subsections: meaning, impact, services, PromQL, root causes | 30-40 |
| 立即响应 | 3-step pattern with golden flow assessment checklist | 40-50 |
| 系统访问方式 | Shared reference (link to common page) | 5 (linked) |
| 诊断命令 | 4-8 technology-specific commands with comments | 20-30 |
| 根因分析 | General causes + Luckin-specific causes + checklist | 25-35 |
| 处理步骤 | 2-3 named scenarios, each with 4-5 steps | 30-50 |
| 升级标准 | 3-row condition/target table | 10 |
| 预防措施 | 4-6 specific prevention items | 10 |
| 相关告警 | 3-5 specific co-firing alert IDs | 8 |
| **Total** | | **200-260** |

---

## Appendix: Files Cross-Referenced

| File | Purpose |
|------|---------|
| `/app/alertrebuild/报警面板.html` | Source: 135 old SOPs (this analysis) |
| `/app/alertrebuild/alert-dashboard.html` | Target: 72 new alerts with minimal runbooks |
| `/app/alertrebuild/alert-rules-complete.yml` | PromQL expressions for all 72 new alerts |
| `/app/alertrebuild/runbook-template.md` | 5A response pattern template |
| `/app/alertrebuild/alert-inventory.md` | Alert inventory with category mapping |
| `/app/alertrebuild/migration-plan.md` | 12-week migration plan |
| `/app/skills/rds-alert-investigation.md` | Existing English SOP for RDS alerts |
| `/app/skills/redis-alert-investigation.md` | Existing English SOP for Redis alerts |
| `/app/skills/k8s-alert-investigation.md` | Existing English SOP for K8s alerts |
| `/app/skills/ec2-alert-investigation.md` | Existing English SOP for EC2 alerts |
| `/app/skills/elasticsearch-alert-investigation.md` | Existing English SOP for ES alerts |
| `/app/skills/apm-alert-investigation.md` | Existing English SOP for APM alerts |

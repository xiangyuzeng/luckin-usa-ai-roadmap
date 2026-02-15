# Luckin Coffee USA — Claude Code Project Context

## Company Overview
Luckin Coffee USA (First Ray Holdings USA Inc.) — app-only coffee chain, 10 Manhattan stores + JFK kiosk.
- ~500-600 daily orders/store (target: 1,200 for break-even)
- 277K registered users, 466K+ completed orders, $2.19M cumulative revenue
- 143 database instances, 233 EC2 instances, $49,645/month AWS spend
- AI transformation: 41 use cases across 7 departments over 18 months

## Team Role
DBA/Infrastructure team managing production databases and AWS infrastructure.
Daily work: alert investigation, database health checks, slow query analysis, Redis monitoring, cost optimization, infrastructure reporting, and AI use case implementation.

---

## Infrastructure Inventory

### MySQL Databases (62 via mcp-db-gateway)
| Domain | Databases | Key Servers |
|--------|-----------|-------------|
| DevOps (12) | devops, ijumpserver, iluckydorisops, dbatest, recovery-dbatest, framework01, framework02, iadmin, ipermission, iluckyauthapi, iworkflowmidlayer, oplog |
| Sales/CRM (9) | salescrm, salesmarketing, salesorder, salespayment, isalescdp, isalesdatamarketing, isalesmembermarketing, isalesprivatedomain, cdpactivity |
| SCM (11) | scm-asset, scm-openapi, scm-ordering, scm-plan, scm-purchase, scm-shopstock, scm-wds, scm-wmssimulate, scmcommodity, scmsrm, ireplenishment |
| Finance (5) | fichargecontrol, fitax, ifiaccounting, ibillingcentersrv, iunifiedreconcile |
| Operations (8) | opempefficiency, opproduction, opqualitycontrol, opshop, opshopsale, iopshopexpand, iopocp, mfranchise |
| Platform (9) | iopenadmin, iopenlinker, iopenservice, ibizconfigcenter, iluckyams, iluckyhealth, iluckymedia, upush, iotplatform |
| Data/Analytics (4) | ldas, ldas01, pubdm, icyberdata |
| HR/Other (3) | iehr, igers, iriskcontrolservice |

Server name pattern: `aws-luckyus-{name}-rw`

### PostgreSQL Databases (3)
- `aws-luckyus-dify-rw` — Dify AI platform (primary)
- `aws-luckyus-difynew-rw` — Dify AI platform (new)
- `aws-luckyus-pgilkmap-rw` — PostGIS map services

### Redis Clusters (78 via Prometheus)
Auth (8), API/Network (3), Sales/CRM (10), SCM (11), DevOps (6), Analytics (5), Finance (6), Operations (9), Platform (18), Dify (1), Map (1).
Name pattern: `luckyus-{name}`

### Other Infrastructure
- **Kafka**: 2 MSK clusters, 308 topics
- **EKS**: 3+ clusters
- **DocumentDB**: 4 instances
- **OpenSearch**: 2 clusters
- **CloudWatch**: 100+ log groups, 52 RDS slow query logs

---

## MCP Servers (10 Active)

| Server | Transport | Purpose |
|--------|-----------|---------|
| **mcp-db-gateway** | SSE | 62 MySQL + 3 PostgreSQL + 78 Redis — primary data access |
| **grafana** | SSE | Dashboards, Prometheus queries, Loki logs, alerts, incidents |
| **grafana-lucky** | SSE | Secondary Grafana instance (same capabilities) |
| **cloudwatch-server** | SSE | Log Insights queries, metrics, alarms |
| **prometheus** | SSE | Direct PromQL — 76 Redis targets, 155 metrics |
| **eks-server** | SSE | Kubernetes/EKS cluster management |
| **cost-explorer** | SSE | AWS Cost Explorer analysis |
| **redshift** | stdio | Redshift Serverless data warehouse queries |
| **aws-dataprocessing** | stdio | Glue/EMR ETL job management |
| **billing** | stdio | AWS billing and cost management |

Additional SSE servers: aws-pricing-server, ccapi-server, aws-documentation-server.

---

## Skills & Runbooks

### Alert Investigation Skills (`/app/skills/`)
| Skill | Invocation |
|-------|------------|
| EC2 Alert Investigation | `/investigate-ec2` |
| RDS Alert Investigation | `/investigate-rds` |
| K8s Alert Investigation | `/investigate-k8s` |
| Redis Alert Investigation | `/investigate-redis` |
| Elasticsearch Alert Investigation | `/investigate-elasticsearch` |
| APM Alert Investigation | `/investigate-apm` |

### SOPs (`/app/sopprompt/`)
- EC2 alert investigation SOP v4 + quick prompt
- K8s alert investigation SOP v1 + quick prompt
- RDS alert investigation SOP v1 + quick prompt

### Active Runbook
- `/app/runbooks/redis-isales-market-remediation/` — Redis TTL fix scripts, monitoring configs

---

## AI Use Case IDs (41 total)

| Dept | IDs | Count |
|------|-----|-------|
| Infrastructure (IT) | UC-IT-01 through UC-IT-06 | 6 |
| Marketing (MK) | UC-MK-01 through UC-MK-10 | 10 |
| Finance (FN) | UC-FN-01 through UC-FN-05 | 5 |
| Product (PR) | UC-PR-01 through UC-PR-05 | 5 |
| Operations (OP) | UC-OP-01 through UC-OP-06 | 6 |
| Supply Chain (SC) | UC-SC-01 through UC-SC-05 | 5 |
| Executive (EX) | UC-EX-01 through UC-EX-04 | 4 |

Active implementations: UC-IT-01 (infra monitoring), UC-OP-02 (store anomaly), UC-SC-01 (forecast accuracy).
Full catalog: `/app/ai-transformation-roadmap/02-ai-use-case-catalog.md`

---

## Safety Rules

1. **Read-only by default** on all production databases. Never run writes unless explicitly requested.
2. **No DROP/DELETE/TRUNCATE** without explicit user confirmation — ask twice for production.
3. **Always use LIMIT** on production queries (default LIMIT 100).
4. **PII masking**: mask customer email, phone, payment info in outputs. Show only last 4 digits or domain.
5. **No credential exposure**: never output passwords, tokens, connection strings, or AWS keys.
6. **Cost awareness**: each Cost Explorer API call costs $0.01. Minimize redundant calls.
7. **Git commits**: descriptive messages with context, never force-push to main.

---

## Conventions

### Output Locations
- General outputs: `/app/claude-code-output/`
- Project-specific: `/app/UC-{dept}-{nn}-{name}/` for AI use case work
- Reports: `/app/reports/`

### Architecture Standards
- Target: 4-layer architecture (Source → Data Platform → AI/ML → Applications)
- Data flow: MySQL → Glue ETL → S3 → Redshift Serverless
- MLflow model naming: `{department}-{use_case_id}-{model_type}`
- Feature Store for shared ML features

### Database Query Patterns
- MySQL server names: `aws-luckyus-{service}-rw` (via mcp-db-gateway)
- Redis cluster names: `luckyus-{service}` (via mcp-db-gateway or Prometheus)
- Always check `SHOW PROCESSLIST` before running heavy queries on production
- Use `information_schema` for schema exploration, not `SHOW TABLES` on large databases

---

## Key File Paths

| Path | Contents |
|------|----------|
| `/app/ai-transformation-roadmap/` | 5 strategic deliverables (architecture, use cases, blueprint, roadmap, exec summary) |
| `/app/skills/` | 6 alert investigation skills + MCP documentation |
| `/app/sopprompt/` | 6 SOP documents (EC2, K8s, RDS) |
| `/app/runbooks/` | Operational runbooks (Redis remediation) |
| `/app/reports/` | Infrastructure and analysis reports |
| `/app/claude-code-output/` | Generated dashboards, scripts, investigations |
| `/app/mcp-datasources-inventory.md` | Complete datasource inventory (148 sources) |
| `/app/LUCKIN_USA_DATABASE_INFRASTRUCTURE_REPORT.md` | Full infrastructure report |
| `/app/ec2_cost_optimization_report.md` | EC2 cost analysis ($176K annual savings potential) |

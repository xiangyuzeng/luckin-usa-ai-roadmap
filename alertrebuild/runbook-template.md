# Luckin Coffee NA — Alert Runbook Template

> **Version:** 1.0 | **Format:** 5 A's Pattern | **Platform:** AWS (us-east-1)
>
> This template defines the standard runbook structure for all 72 production alerts.
> Every runbook follows the **5 A's Pattern**: Assess → Acknowledge → Analyze → Act → Aftermath.

---

## Runbook Metadata Block

```yaml
# Copy this block to the top of every runbook
alert_id: "LCK-{CAT}-{NNN}"
alert_name: "{AlertName}"
severity: "info|warning|critical"
tier: "1|2|3"
category: "{category}"
team: "{team}"
first_responder: "{team} on-call"
sla_response: "Tier 1: 30min | Tier 2: 15min | Tier 3: 5min"
skill_reference: "/app/skills/{skill-name}.md"
last_updated: "YYYY-MM-DD"
```

---

## 1. ASSESS (First 2 Minutes)

**Goal:** Determine if this alert impacts the golden path (user ordering flow) and triage severity.

### 1.1 Golden Path Impact Check

```bash
# Check if completed orders are flowing (golden path health)
# Prometheus datasource: df8o21agxtkw0d (UMBQuerier-Luckin)
# PromQL — run via Grafana or curl to Prometheus API:
curl -s "http://prometheus:9090/api/v1/query?query=sum_over_time(business_completed_orders_total[10m])"

# Quick service health check (replace SERVICE_NAME)
kubectl get pods -n production -l app=SERVICE_NAME --no-headers | \
  awk '{print $1, $2, $3, $5}'
```

### 1.2 Quick Triage Commands

```bash
# Check if this is an isolated alert or part of a storm
# (Are other alerts firing for the same service/instance?)
curl -s "http://alertmanager:9093/api/v2/alerts?filter=service%3D%22SERVICE_NAME%22" | \
  jq '.[].labels | {alertname, severity, instance}'

# Check recent deployments (last 2 hours)
kubectl get events -n production --sort-by='.lastTimestamp' --field-selector reason=Pulling | \
  tail -10
```

### 1.3 Severity Classification

| Condition | Severity | Action |
|-----------|----------|--------|
| Golden path impacted (orders stopped) | **Critical → Tier 3** | Wake China HQ immediately |
| Service degraded, golden path OK | **Warning → Tier 2** | US DevOps handles, notify team lead |
| Metric elevated, no user impact | **Info → Tier 1** | US DevOps monitors, no phone calls |

---

## 2. ACKNOWLEDGE (Within SLA)

**Goal:** Confirm ownership and notify stakeholders via the correct channel.

### 2.1 Acknowledge the Alert

```bash
# Silence the alert in Alertmanager (prevent repeat notifications during investigation)
# Duration: 1h for info, 30m for warning, 15m for critical
amtool silence add \
  alertname="ALERT_NAME" \
  service="SERVICE_NAME" \
  --duration="30m" \
  --comment="Investigating - YOUR_NAME" \
  --author="YOUR_NAME"
```

### 2.2 Post to WeCom Incident Channel

```
Template (paste into WeCom):
---
🔔 Alert Acknowledged
Alert: {alert_name} ({alert_id})
Severity: {severity} | Tier: {tier}
Owner: {your_name}
Status: Investigating
ETA for update: {time + 15min}
---
```

### 2.3 SLA Timers

| Tier | Acknowledge By | First Update By | Resolution Target |
|------|---------------|-----------------|-------------------|
| Tier 1 (Info) | 30 min | 2 hours | 8 hours |
| Tier 2 (Warning) | 15 min | 1 hour | 4 hours |
| Tier 3 (Critical) | 5 min | 15 min | 1 hour |

---

## 3. ANALYZE (Root Cause Investigation)

**Goal:** Identify the root cause using structured diagnostic commands.

### 3.1 Common Causes Checklist

```
[ ] Recent deployment or config change (check last 2h)
[ ] Upstream dependency failure (DB, Redis, external API)
[ ] Resource exhaustion (CPU, memory, disk, connections)
[ ] Traffic anomaly (spike or sudden drop)
[ ] Infrastructure event (AWS maintenance, AZ issue)
[ ] Certificate/credential expiry
```

### 3.2 Diagnostic Commands by Category

#### Database (RDS)
```bash
# CPU and active threads — use Prometheus UID: df8o21agxtkw0d
# PromQL: aws_rds_cpuutilization_average{dbinstance_identifier="INSTANCE_NAME"}
# PromQL: aws_rds_database_connections_average{dbinstance_identifier="INSTANCE_NAME"}

# Slow queries (via DevOps DB)
# Server: aws-luckyus-devops-rw
# SQL: SELECT * FROM slow_query_log WHERE start_time > NOW() - INTERVAL 30 MINUTE ORDER BY query_time DESC LIMIT 20;

# Disk space
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name FreeStorageSpace \
  --dimensions Name=DBInstanceIdentifier,Value=INSTANCE_NAME \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 --statistics Minimum --region us-east-1
```

#### Redis (ElastiCache)
```bash
# Memory and CPU — use Prometheus UID: ff6p0gjt24phce
# PromQL: redis_memory_usage_ratio{cluster="CLUSTER_NAME"}
# PromQL: redis_cpu_usage{cluster="CLUSTER_NAME"}

# Connection count
redis-cli -h master.CLUSTER_NAME.vyllrs.use1.cache.amazonaws.com \
  -p 6379 --tls --no-auth-warning INFO clients | grep connected_clients

# Memory breakdown
redis-cli -h master.CLUSTER_NAME.vyllrs.use1.cache.amazonaws.com \
  -p 6379 --tls --no-auth-warning INFO memory | grep -E 'used_memory_human|maxmemory_human|mem_fragmentation_ratio'
```

#### Kubernetes (EKS)
```bash
# Pod status and recent events
kubectl get pods -n production -l app=SERVICE_NAME -o wide
kubectl describe pod POD_NAME -n production | tail -30

# OOM kills in last hour
kubectl get events -n production --field-selector reason=OOMKilling --sort-by='.lastTimestamp'

# Resource usage
kubectl top pods -n production -l app=SERVICE_NAME --sort-by=cpu
```

#### VM / EC2
```bash
# CPU, Memory, Disk via node_exporter
# PromQL: 100 - (avg by(instance)(irate(node_cpu_seconds_total{mode="idle",instance="INSTANCE_IP:9100"}[5m])) * 100)
# PromQL: (1 - node_memory_MemAvailable_bytes{instance="INSTANCE_IP:9100"} / node_memory_MemTotal_bytes{instance="INSTANCE_IP:9100"}) * 100

# Disk usage
ssh INSTANCE_IP "df -h | grep -vE 'tmpfs|devtmpfs|overlay'"

# IO wait
ssh INSTANCE_IP "iostat -xz 1 5"
```

#### Elasticsearch
```bash
# Cluster health
curl -s "http://ES_ENDPOINT:9200/_cluster/health" | jq '{status, number_of_nodes, active_shards, relocating_shards, unassigned_shards}'

# Node stats (CPU, JVM heap)
curl -s "http://ES_ENDPOINT:9200/_nodes/stats/jvm,os" | jq '.nodes | to_entries[] | {name: .value.name, cpu: .value.os.cpu.percent, heap_percent: .value.jvm.mem.heap_used_percent}'

# Hot threads (if CPU high)
curl -s "http://ES_ENDPOINT:9200/_nodes/hot_threads?threads=3"
```

### 3.3 MCP Skill References

| Category | Skill File | Version |
|----------|-----------|---------|
| EC2/VM | `/app/skills/ec2-alert-investigation.md` | v5.0 |
| RDS | `/app/skills/rds-alert-investigation.md` | v2.0 |
| Kubernetes | `/app/skills/k8s-alert-investigation.md` | v2.0 |
| Redis | `/app/skills/redis-alert-investigation.md` | v1.0 |
| Elasticsearch | `/app/skills/es-alert-investigation.md` | v1.0 |
| APM/iZeus | `/app/skills/apm-alert-investigation.md` | v1.0 |

### 3.4 Grafana Dashboard Links

```
# Main Prometheus datasource: df8o21agxtkw0d (UMBQuerier-Luckin)
# Redis datasource: ff6p0gjt24phce (prometheus_redis)
# General datasource: ff7hkeec6c9a8e (prometheus)

# Construct dashboard URL:
https://grafana.luckinus.com/d/{DASHBOARD_UID}?var-instance={instance}&from=now-1h&to=now

# iZeus trace URL:
https://izeus.luckincoffee.us/trace?service={service_name}&start={timestamp}
```

---

## 4. ACT (Remediation)

**Goal:** Execute the appropriate remediation based on tier level.

### 4.1 Tier-Based Remediation Authority

| Tier | Who Acts | Authority Level |
|------|----------|----------------|
| Tier 1 (Info) | US DevOps on-call | Monitor, tune thresholds, non-disruptive actions |
| Tier 2 (Warning) | US DevOps + Team Lead | Restart services, scale resources, apply hotfixes |
| Tier 3 (Critical) | US + China HQ Engineering | Failover, emergency scaling, rollback deployments |

### 4.2 Common Remediation Actions

#### Service Restart (Tier 2+)
```bash
# Rolling restart of a deployment (zero-downtime)
kubectl rollout restart deployment/SERVICE_NAME -n production

# Monitor rollout progress
kubectl rollout status deployment/SERVICE_NAME -n production --timeout=300s

# Rollback if new pods are failing
kubectl rollout undo deployment/SERVICE_NAME -n production
```

#### Scale Up (Tier 2+)
```bash
# Horizontal pod autoscaling check
kubectl get hpa -n production | grep SERVICE_NAME

# Manual scale (if needed)
kubectl scale deployment/SERVICE_NAME -n production --replicas=NEW_COUNT

# RDS scale (Tier 3 — requires China approval)
aws rds modify-db-instance \
  --db-instance-identifier INSTANCE_NAME \
  --db-instance-class db.r6g.xlarge \
  --apply-immediately --region us-east-1
```

#### Emergency Failover (Tier 3 Only)
```bash
# RDS failover
aws rds reboot-db-instance \
  --db-instance-identifier INSTANCE_NAME \
  --force-failover --region us-east-1

# Redis failover
aws elasticache modify-replication-group \
  --replication-group-id CLUSTER_NAME \
  --automatic-failover-enabled \
  --apply-immediately --region us-east-1
```

### 4.3 Escalation Path

```
Tier 1 → (15 min no resolution) → Tier 2 → (30 min no resolution) → Tier 3
                                                                         ↓
                                                              China HQ Engineering
                                                              WeCom: @all in critical channel
                                                              Twilio: All DevOps numbers
```

---

## 5. AFTERMATH (Post-Incident)

**Goal:** Document the incident, extract learnings, and prevent recurrence.

### 5.1 Incident Timeline Template

```markdown
## Incident Report: {alert_name}

**Date:** YYYY-MM-DD
**Duration:** HH:MM (start to resolution)
**Severity:** {severity} | **Tier:** {tier}
**First Responder:** {name}
**Resolution Owner:** {name}

### Timeline
| Time (UTC) | Event |
|------------|-------|
| HH:MM | Alert fired: {alert_name} |
| HH:MM | Acknowledged by {name} |
| HH:MM | Root cause identified: {description} |
| HH:MM | Remediation applied: {action} |
| HH:MM | Alert resolved |

### Root Cause
{One paragraph description}

### Impact
- Users affected: {count or "none"}
- Revenue impact: {estimate or "none"}
- Duration of impact: {minutes}

### Action Items
| Action | Owner | Due Date | Status |
|--------|-------|----------|--------|
| {prevention measure} | {name} | YYYY-MM-DD | TODO |
| {threshold adjustment} | {name} | YYYY-MM-DD | TODO |
| {runbook update} | {name} | YYYY-MM-DD | TODO |
```

### 5.2 Threshold Review

```bash
# After every critical/warning incident, review:
# 1. Was the threshold appropriate? (too sensitive = alert fatigue, too loose = missed incidents)
# 2. Was the `for` duration appropriate? (too short = flapping, too long = delayed response)
# 3. Should this alert be promoted/demoted in severity?

# Check alert firing history (last 7 days)
curl -s "http://prometheus:9090/api/v1/query?query=ALERTS{alertname='ALERT_NAME'}" | \
  jq '.data.result[] | {alertname: .metric.alertname, state: .metric.alertstate}'
```

### 5.3 Knowledge Base Update

After resolution, update the following:
1. **This runbook** — Add the root cause to Section 3.1 common causes if it's new
2. **Skills file** — Update `/app/skills/{category}-alert-investigation.md` with new diagnostic commands
3. **Alert thresholds** — Submit PR to `alert-rules-complete.yml` if threshold change needed
4. **Dashboard** — Add new panel to Grafana if visibility gap identified

---

## Appendix: Environment Reference

### Verified Datasource UIDs

| Datasource | UID | Purpose |
|------------|-----|---------|
| UMBQuerier-Luckin | `df8o21agxtkw0d` | Primary Prometheus (node, RDS, business metrics) |
| prometheus | `ff7hkeec6c9a8e` | General metrics |
| prometheus_redis | `ff6p0gjt24phce` | Redis/ElastiCache metrics |

### VMAlert Endpoints

| Instance | IP:Port | Role |
|----------|---------|------|
| APM-1 | 10.238.3.137:8880 | APM alert evaluation |
| APM-2 | 10.238.3.143:8880 | APM alert evaluation |
| APM-3 | 10.238.3.52:8880 | APM alert evaluation |
| Basic | 10.238.3.153:8880 | Infrastructure alert evaluation |

### Key AWS Resources

| Resource | Identifier | Notes |
|----------|-----------|-------|
| AWS Account | 257394478466 | Production |
| Region | us-east-1 | Primary |
| EKS Cluster | luckyus-prod | Main K8s cluster |
| DevOps DB | aws-luckyus-devops-rw | Service registry, alert logs |

### WeCom Notification Channels

| Channel | Tier | Recipients |
|---------|------|-----------|
| wecom-info | Tier 1 | US DevOps (text only) |
| wecom-warning | Tier 2 | US DevOps + Team Lead (text + phone lead) |
| wecom-critical | Tier 3 | All DevOps US + China HQ (text + phone all) |

### Contact Escalation

| Role | Contact Method | When |
|------|---------------|------|
| US DevOps On-Call | WeCom group | All alerts |
| US Team Lead | WeCom + Twilio (US number) | Tier 2+ |
| China HQ DBA | WeCom + Twilio (CN number) | Tier 3 only |
| China HQ Engineering | WeCom + Twilio (CN number) | Tier 3 only |
| AWS Support | Support console | Infrastructure issues unresolvable internally |

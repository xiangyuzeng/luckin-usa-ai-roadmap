# Luckin Coffee NA — Alert System Migration Plan

> **Version:** 1.0 | **Date:** 2026-02-14 | **Duration:** 12 Weeks (4 Phases)
>
> Migrate from 135-alert P0-P3 system to 72-alert three-tier (Info/Warning/Critical) architecture.

---

## Migration Overview

| Aspect | Current State | Target State |
|--------|--------------|--------------|
| Alert Count | 135 | 72 |
| Priority System | P0/P1/P2/P3 | Info/Warning/Critical |
| Categories | 16 | 10 |
| Notification | Direct WeCom + _语音 duplicates | Alertmanager routing → WeCom + Twilio |
| Runbooks | Chinese AI-generated handbooks | English 5 A's pattern with diagnostic commands |
| Dashboard | 报警面板.html (Chinese) | alert-dashboard.html (English) |

---

## Phase 0: Foundation (Weeks 0–2)

### Objectives
- Set up infrastructure for new alerting system
- Validate all PromQL expressions against live Prometheus
- Create notification channels

### Week 0: Setup & Validation

#### Day 1-2: Repository & Infrastructure
```bash
# 1. Create alerting branch
cd /app/alertrebuild
git checkout -b alert-rebuild-v2

# 2. Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('alert-rules-complete.yml')); print('YAML valid')"
python3 -c "import yaml; yaml.safe_load(open('alertmanager-config.yml')); print('YAML valid')"

# 3. Count rules for verification
grep -c "alert:" alert-rules-complete.yml   # Should be 72
grep -c "record:" alert-rules-complete.yml  # Should be 14
```

#### Day 3-5: PromQL Validation Against Live Prometheus
```bash
# Prometheus endpoint: UMBQuerier-Luckin (UID: df8o21agxtkw0d)
# Test each recording rule expression against live data

# Example: Validate RDS CPU recording rule
curl -s "http://prometheus:9090/api/v1/query?query=avg_over_time(aws_rds_cpuutilization_average[3m])" | \
  jq '.data.result | length'

# Example: Validate Redis memory recording rule
curl -s "http://prometheus:9090/api/v1/query?query=avg_over_time(redis_memory_usage_ratio[3m])" | \
  jq '.data.result | length'

# Validate node_exporter metrics exist
curl -s "http://prometheus:9090/api/v1/query?query=node_cpu_seconds_total{mode='idle'}" | \
  jq '.data.result | length'

# Document any metrics that return 0 results → mark with # TODO: validate
```

### Week 1: Notification Channel Setup

#### WeCom Channels
```
Create 3 new WeCom group chats:
1. [LCK-NA] Alert Info (Tier 1)        → Generate webhook → ${WECOM_WEBHOOK_INFO}
2. [LCK-NA] Alert Warning (Tier 2)     → Generate webhook → ${WECOM_WEBHOOK_WARNING}
3. [LCK-NA] Alert Critical (Tier 3)    → Generate webhook → ${WECOM_WEBHOOK_CRITICAL}

Members:
- Info: US DevOps team
- Warning: US DevOps team + Team Lead
- Critical: US DevOps team + Team Lead + China HQ Engineering
```

#### Twilio Setup
```bash
# 1. Configure Twilio webhook proxy (localhost:9097)
# 2. Test phone call to team lead number
curl -X POST http://localhost:9097/twilio/test \
  -d '{"to": "${TWILIO_TEAM_LEAD_US}", "message": "LCK-NA Alert System Test"}'

# 3. Verify all phone numbers
# US Team Lead: ${TWILIO_TEAM_LEAD_US}
# US DevOps 1: ${TWILIO_DEVOPS_US_1}
# US DevOps 2: ${TWILIO_DEVOPS_US_2}
# China HQ 1: ${TWILIO_DEVOPS_CN_1}
# China HQ 2: ${TWILIO_DEVOPS_CN_2}
```

### Week 2: Deploy Recording Rules

#### Deploy to VMAlert Nodes
```bash
# VMAlert instances:
# APM: 10.238.3.137:8880, 10.238.3.143:8880, 10.238.3.52:8880
# Basic: 10.238.3.153:8880

# 1. Extract recording rules only
python3 -c "
import yaml
with open('alert-rules-complete.yml') as f:
    data = yaml.safe_load(f)
recording = {'groups': [g for g in data['groups'] if 'recording' in g['name']]}
with open('recording-rules-only.yml', 'w') as f:
    yaml.dump(recording, f, default_flow_style=False)
print(f'Extracted {sum(len(g[\"rules\"]) for g in recording[\"groups\"])} recording rules')
"

# 2. Deploy recording rules to Basic VMAlert node
scp recording-rules-only.yml 10.238.3.153:/etc/rules/lck-na-recording.yml

# 3. Reload VMAlert configuration
curl -X POST http://10.238.3.153:8880/-/reload

# 4. Verify recording rules are evaluating
curl -s "http://10.238.3.153:8880/api/v1/rules" | \
  jq '.data.groups[] | select(.name | startswith("lck-na.recording")) | .name'
```

#### Baseline VMAlert Resource Usage
```bash
# Record CPU/memory usage before adding alert rules
for node in 10.238.3.137 10.238.3.143 10.238.3.52 10.238.3.153; do
  echo "=== $node ==="
  curl -s "http://$node:8880/metrics" | grep -E 'process_(cpu|resident_memory)'
done > /tmp/vmalert-baseline-$(date +%Y%m%d).txt
```

---

## Phase 1: Parallel Run (Weeks 3–6)

### Objectives
- Deploy new alert rules alongside existing rules
- Compare firing patterns between old and new systems
- Validate three-tier routing before cutover

### Batch Deployment Schedule

| Batch | Weeks | Categories | Alert Count | Risk |
|-------|-------|-----------|-------------|------|
| Batch 1 | 3-4 | BIZ + DB-RDS + DB-REDIS | 32 | HIGH (business-critical) |
| Batch 2 | 4-5 | DB-ES + DB-MONGO + INFRA-VM | 19 | MEDIUM |
| Batch 3 | 5-6 | INFRA-K8S + APM + PIPELINE + PLATFORM | 21 | LOW-MEDIUM |

### Batch 1 Deployment (Weeks 3-4)

```bash
# 1. Extract Batch 1 alert rules
python3 -c "
import yaml
with open('alert-rules-complete.yml') as f:
    data = yaml.safe_load(f)
batch1_names = ['lck-na.alerts.biz', 'lck-na.alerts.db-rds', 'lck-na.alerts.db-redis']
batch1 = {'groups': [g for g in data['groups'] if g['name'] in batch1_names]}
with open('batch1-alerts.yml', 'w') as f:
    yaml.dump(batch1, f, default_flow_style=False)
print(f'Batch 1: {sum(len(g[\"rules\"]) for g in batch1[\"groups\"])} alerts')
"

# 2. Deploy to VMAlert (rules are additive — old rules continue running)
scp batch1-alerts.yml 10.238.3.153:/etc/rules/lck-na-batch1.yml
curl -X POST http://10.238.3.153:8880/-/reload

# 3. Verify new rules are evaluating (should show pending/inactive)
curl -s "http://10.238.3.153:8880/api/v1/rules" | \
  jq '.data.groups[] | select(.name | startswith("lck-na.alerts")) | {name: .name, rules: [.rules[] | .name]}'
```

### Comparison Framework

```bash
# Daily comparison script — run at 9 AM ET
#!/bin/bash
DATE=$(date -d yesterday +%Y-%m-%d)

echo "=== Alert Firing Comparison: $DATE ==="

# Count old system firings (from VMAlert metrics)
echo "Old system alerts fired:"
curl -s "http://10.238.3.153:8880/api/v1/query?query=count(ALERTS{alertname=~'ALR-.*'})" | \
  jq '.data.result[0].value[1]'

# Count new system firings
echo "New system alerts fired:"
curl -s "http://10.238.3.153:8880/api/v1/query?query=count(ALERTS{alertname=~'LCK-.*'})" | \
  jq '.data.result[0].value[1]'

# Check for alerts that fired in old but not new (potential gaps)
echo "Old alerts without new equivalent:"
# (Manual review required — compare alert logs)
```

### Batch 2 Deployment (Weeks 4-5)
```bash
# Same process as Batch 1, categories: DB-ES, DB-MONGO, INFRA-VM
# Extract, deploy, verify, compare
```

### Batch 3 Deployment (Weeks 5-6)
```bash
# Same process, categories: INFRA-K8S, APM, PIPELINE, PLATFORM
# After Batch 3: all 72 new rules running alongside old 135 rules
```

---

## Phase 2: Cutover (Weeks 7–9)

### Objectives
- Switch notification routing to new system
- Enable Twilio integration
- Disable old rules
- Maintain 2-week rollback window

### Week 7: Switch WeCom Routing

```bash
# 1. Deploy Alertmanager configuration
cp alertmanager-config.yml /etc/alertmanager/alertmanager.yml

# 2. Set environment variables
export WECOM_WEBHOOK_INFO="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=INFO_KEY"
export WECOM_WEBHOOK_WARNING="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=WARNING_KEY"
export WECOM_WEBHOOK_CRITICAL="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=CRITICAL_KEY"
export IZEUS_WEBHOOK_URL="https://izeus.luckincoffee.us/api/v1/alertmanager/webhook"

# 3. Reload Alertmanager
curl -X POST http://alertmanager:9093/-/reload

# 4. Verify routing is active
curl -s http://alertmanager:9093/api/v2/status | jq '.config'

# 5. Send test alert to verify each tier
# Test info tier
curl -X POST http://alertmanager:9093/api/v2/alerts \
  -H 'Content-Type: application/json' \
  -d '[{"labels":{"alertname":"test_info","severity":"info","category":"test","team":"devops"},"annotations":{"summary":"Test info alert"}}]'

# Test warning tier (verify WeCom + Twilio team lead)
# Test critical tier (verify WeCom + Twilio all)
```

### Week 8: Enable Twilio & Disable Old Rules

```bash
# 1. Enable Twilio integration
export TWILIO_ACCOUNT_SID="AC..."
export TWILIO_AUTH_TOKEN="..."
export TWILIO_FROM_NUMBER="+1..."

# 2. Test Twilio with a single warning alert
# (Coordinate with team lead to expect test call)

# 3. Disable old rules (DO NOT DELETE — keep for rollback)
# Rename old rule files to .disabled extension
for node in 10.238.3.137 10.238.3.143 10.238.3.52 10.238.3.153; do
  ssh $node "cd /etc/rules && for f in *.json; do mv \$f \$f.disabled; done"
  curl -X POST http://$node:8880/-/reload
done

# 4. Verify old rules are no longer evaluating
curl -s "http://10.238.3.153:8880/api/v1/rules" | \
  jq '[.data.groups[] | select(.name | startswith("lck-na")) | .name]'
```

### Week 9: Disable _语音 Alerts & Validation

```bash
# 1. Confirm all _语音 alerts are silenced
# (These should already be disabled from Week 8)

# 2. Full validation checklist
echo "=== Cutover Validation ==="
echo "[ ] WeCom info channel receiving info alerts"
echo "[ ] WeCom warning channel receiving warning alerts"
echo "[ ] WeCom critical channel receiving critical alerts"
echo "[ ] Twilio calling team lead on warning alerts"
echo "[ ] Twilio calling all DevOps on critical alerts"
echo "[ ] iZeus webhook receiving all alerts"
echo "[ ] Inhibition rules working (critical suppresses warning)"
echo "[ ] Time-based muting working (info suppressed 2-7 AM ET)"
echo "[ ] No old ALR-* alerts firing"
echo "[ ] All 72 LCK-* rules active"
```

### Rollback Procedure

```bash
# ============================================================
# ROLLBACK: Re-enable old rules in < 5 minutes
# ============================================================

# Step 1: Re-enable old rule files on all VMAlert nodes
for node in 10.238.3.137 10.238.3.143 10.238.3.52 10.238.3.153; do
  ssh $node "cd /etc/rules && for f in *.json.disabled; do mv \$f \${f%.disabled}; done"
  curl -X POST http://$node:8880/-/reload
done

# Step 2: Revert Alertmanager to old config
cp /etc/alertmanager/alertmanager.yml.backup /etc/alertmanager/alertmanager.yml
curl -X POST http://alertmanager:9093/-/reload

# Step 3: Notify team
echo "ROLLBACK COMPLETE: Old alerting system re-enabled. New rules still running in parallel."

# Step 4: Disable new rules if needed
for node in 10.238.3.137 10.238.3.143 10.238.3.52 10.238.3.153; do
  ssh $node "rm -f /etc/rules/lck-na-*.yml"
  curl -X POST http://$node:8880/-/reload
done
```

---

## Phase 3: Optimization (Weeks 10–12)

### Objectives
- Tune thresholds based on 4-week baseline data
- Complete all 72 runbooks
- Deploy new dashboard
- Decommission old rules

### Week 10: Threshold Tuning

```bash
# 1. Analyze alert firing frequency over last 4 weeks
curl -s "http://prometheus:9090/api/v1/query?query=\
  topk(20, sum by(alertname) (count_over_time(ALERTS{alertname=~'LCK-.*'}[4w])))" | \
  jq '.data.result[] | {alert: .metric.alertname, firings: .value[1]}'

# 2. Identify noisy alerts (>100 firings in 4 weeks)
# → These need threshold adjustment

# 3. Identify silent alerts (0 firings in 4 weeks)
# → Verify expressions are correct, not just quiet

# 4. Adjust thresholds in alert-rules-complete.yml
# → Re-deploy via same batch process
```

### Week 11: Runbook Completion

```
Runbook completion targets:
- [ ] BIZ: 10 runbooks (template: runbook-template.md)
- [ ] DB-RDS: 12 runbooks
- [ ] DB-REDIS: 10 runbooks (partially done — redis-isales-market RUNBOOK.md exists)
- [ ] DB-ES: 6 runbooks
- [ ] DB-MONGO: 5 runbooks
- [ ] INFRA-K8S: 7 runbooks
- [ ] INFRA-VM: 8 runbooks
- [ ] APM: 6 runbooks
- [ ] PIPELINE: 4 runbooks
- [ ] PLATFORM: 4 runbooks

Each runbook must have:
✓ Copy-paste diagnostic commands (not generic advice)
✓ Tier-appropriate remediation steps
✓ Correct Prometheus datasource UIDs
✓ Links to relevant Grafana dashboards
✓ MCP skill references
```

### Week 12: Dashboard & Decommission

```bash
# 1. Deploy new dashboard
cp alert-dashboard.html /var/www/monitoring/alert-dashboard.html

# 2. Verify dashboard renders correctly
# → Open in browser, check all 72 alerts load
# → Test all 4 views (Cards, Hierarchy, Relationship, Routing Pipeline)
# → Verify search/filter functionality
# → Verify sidebar shows 10 categories

# 3. Delete old rule files (FINAL — no rollback after this)
# Only proceed if Phase 2+3 have been stable for 4+ weeks
for node in 10.238.3.137 10.238.3.143 10.238.3.52 10.238.3.153; do
  ssh $node "rm -f /etc/rules/*.json.disabled"
done

# 4. Archive old dashboard
mv /var/www/monitoring/报警面板.html /var/www/monitoring/archive/报警面板-legacy-$(date +%Y%m%d).html

# 5. Update documentation
# → Update README with new alerting architecture
# → Update on-call handbook with new escalation procedures
# → Archive old alert inventory
```

---

## Risk Register

| Risk | Probability | Impact | Mitigation | Owner |
|------|------------|--------|------------|-------|
| PromQL references non-existent metrics | Medium | High | Phase 0 live validation. Mark unvalidated with `# TODO` | DBA |
| iZeus webhook payload incompatibility | Medium | Medium | Test with single info alert. Custom Alertmanager template | App-Ops |
| Parallel run doubles VMAlert load | Low | Medium | Recording rules reduce per-eval cost. Baseline before Phase 1 | Sys-Ops |
| WeCom rate limiting during storms | Low | Low | `group_wait: 30s` + `group_interval: 5m` + inhibition rules | Platform |
| Team confusion during cutover | Medium | Medium | Clear communication plan. Old system preserved for 4 weeks | Team Lead |
| False negatives (missed alerts) | Low | High | Parallel run comparison framework. Daily diff reports | DBA |

---

## Success Criteria

| Metric | Target | Measurement |
|--------|--------|-------------|
| Alert count reduction | 135 → 72 (-47%) | Count active rules in VMAlert |
| P0 alert ratio | 30% → 0% (replaced) | No P0/P1/P2/P3 labels in new system |
| Duplicate alerts | 15+ pairs → 0 | No identical PromQL expressions |
| MTTR for Tier 3 incidents | Baseline → -20% | Incident timeline analysis |
| Alert fatigue (surveys) | High → Medium | Monthly DevOps team survey |
| Runbook actionability | Generic → Copy-paste commands | Runbook review audit |
| Notification accuracy | _语音 misfires → 0 | Twilio call logs vs incident correlation |

---

## Communication Plan

| Milestone | Audience | Channel | Timing |
|-----------|----------|---------|--------|
| Migration kickoff | All DevOps | WeCom all-hands | Week 0 Day 1 |
| Phase 1 batch deployments | Affected teams | WeCom category channels | Each batch start |
| Cutover date | All DevOps + China HQ | WeCom + Email | Week 7 -3 days |
| Cutover complete | All DevOps + China HQ | WeCom + Email | Week 8 Day 1 |
| Old system decommission | All DevOps | WeCom all-hands | Week 12 |
| Final report | Management | Email + document | Week 12 +1 |

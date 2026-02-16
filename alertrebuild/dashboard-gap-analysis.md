# Dashboard Gap Analysis: Old → New Alert Dashboard

> **Prompt 4.1 Output** — Systematic comparison of `报警面板.html` (OLD, 41,498 lines, 135 alerts) vs `alert-dashboard.html` (NEW, 1,165 lines, 72 alerts)
>
> Purpose: Identify all feature gaps, regressions, improvements, and migration considerations between the two dashboard implementations.

---

## Executive Summary

The new dashboard is a structural improvement over the old — it adds routing pipeline visualization, notification channel tracking, migration traceability (`oldIds`), and a cleaner English-first architecture. However, it has a **critical content gap**: the old dashboard's 250–350 line comprehensive Chinese SOPs have been reduced to 5–15 line English stubs. The new dashboard also consolidates 135 alerts down to 72 through multi-tier severity (info/warning/critical replacing P0-P3), which is architecturally sound but means some old alert-level granularity has been merged.

### Gap Severity Classification

| Severity | Count | Description |
|----------|-------|-------------|
| **CRITICAL** | 1 | Runbook/SOP content depth — blocks go-live |
| **HIGH** | 3 | Bilingual support, sidebar UX, SOP content structure |
| **MEDIUM** | 5 | Branding, CSS styling, search enhancement, category naming, data completeness |
| **LOW** | 4 | Minor UX refinements, emoji usage, responsive tuning |
| **IMPROVEMENT** (New > Old) | 6 | Routing pipeline, notification tracking, tier system, oldIds, cleaner code, search scope |

---

## 1. Alert Count & Consolidation

### 1.1 Quantitative Summary

| Dimension | Old Dashboard | New Dashboard | Delta |
|-----------|---------------|---------------|-------|
| Total alerts | 135 | 72 | −63 (−47%) |
| Categories | 12+ | 10 | −2 |
| File size | 41,498 lines | 1,165 lines | −97% |
| SOP content per alert | 250–350 lines | 5–15 lines | −97% |

### 1.2 Category Mapping & Consolidation

| Old Category | Old Count | New Category | New Count | Consolidation Notes |
|-------------|-----------|--------------|-----------|---------------------|
| Priority Levels | 4 | *(eliminated)* | 0 | Meta-alerts removed; severity now per-alert |
| DataLink | 14 | pipeline | 4 | Day/night split removed; golden/core/important/standard tiers |
| Database-RDS | 11 | db-rds | 12 | Expanded with multi-tier (info/warning/critical per metric) |
| Database-Redis | 10 | db-redis | 10 | Maintained; multi-tier severity added |
| Database-ES | 7 | db-es | 6 | Slight consolidation |
| Database-Mongo | 3 | db-mongo | 5 | Expanded (memory, connections added) |
| VM/Host | 17 | infra-vm | 8 | Heavy consolidation; multi-tier replaces duplicate rules |
| Pod/Container | 11 | infra-k8s | 7 | Consolidated; multi-tier severity |
| APM-iZeus + APM-Default | 29 | apm | 6 | Major consolidation |
| Database-Exporter | 6 | *(merged into platform)* | — | Exporter-down alerts → PLAT-04 type |
| SMS-UPUSH | 4 | platform | 4 | SMS + risk control → platform category |
| Risk Control | 4 | *(merged into platform)* | — | Combined into platform |
| Grafana Native | 7 | *(eliminated)* | 0 | Grafana-native alerts moved to Grafana itself |
| Business | 5 | biz | 10 | Expanded significantly |

### 1.3 Consolidation Approach

The old dashboard had separate alerts for the same metric at different severities (e.g., ALR-100 through ALR-103 for VM CPU at different thresholds). The new dashboard uses a consistent **3-tier pattern** per metric:
- `info` (tier 1): Early warning, WeCom only
- `warning` (tier 2): Needs attention, WeCom + Twilio lead
- `critical` (tier 3): Immediate action, WeCom + Twilio all

This is structurally superior but requires verification that no old alert scenario has been lost in the consolidation (see Prompt 4.3).

---

## 2. Data Schema Comparison

### 2.1 Alert Object Fields

| Field | Old | New | Gap Type |
|-------|-----|-----|----------|
| `id` | `ALR-NNN` | `{CAT}-NN` (e.g., `BIZ-01`) | IMPROVEMENT — semantic IDs |
| `name` | Chinese with brackets `【】` | English CamelCase (e.g., `BizOrderVolumeInfo`) | CHANGE — needs bilingual |
| `priority` | `P0/P1/P2/P3` | *(removed)* | REPLACED by `severity` |
| `severity` | *(absent)* | `info/warning/critical` | NEW field |
| `tier` | *(absent)* | `1/2/3` (notification tier) | NEW field |
| `category` | Mixed English | Lowercase kebab (e.g., `db-rds`) | IMPROVEMENT — consistent |
| `team` | Chinese (e.g., `全局`, `DBA`, `系统运维`) | English (e.g., `biz-ops`, `dba`, `k8s-ops`) | CHANGE — needs bilingual |
| `metric` | Descriptive English | Prometheus metric name | IMPROVEMENT — machine-readable |
| `threshold` | English description | English description | SAME |
| `duration` | String or `N/A` | String | SAME |
| `expression` | Raw PromQL | PromQL with `lckna:` recording rules | IMPROVEMENT — uses recording rules |
| `services` | Chinese service names | English service names | CHANGE — needs bilingual |
| `handbook` | 250–350 line markdown (Chinese) | *(removed)* | REPLACED by `runbook` |
| `runbook` | *(absent)* | 5–15 line markdown (English) | **CRITICAL GAP** — minimal content |
| `notification` | *(absent)* | `wecom-only/wecom+twilio-lead/wecom+twilio-all` | NEW field |
| `oldIds` | *(absent)* | Array of `ALR-NNN` references | NEW field — migration tracing |

### 2.2 Priority → Severity Mapping

| Old Priority | Old Response Time | New Severity | New Tier | New Notification |
|-------------|-------------------|-------------|----------|-----------------|
| P0 | < 5 min | critical | 3 | wecom+twilio-all |
| P1 | < 15 min | warning | 2 | wecom+twilio-lead |
| P2 | < 30 min | info | 1 | wecom-only |
| P3 | < 2 hours | info | 1 | wecom-only |

Note: P2 and P3 are both mapped to `info`. This loses the distinction between "standard response" and "low priority" from the old system.

---

## 3. Feature Comparison

### 3.1 Views

| View | Old Dashboard | New Dashboard | Status |
|------|---------------|---------------|--------|
| Card Grid (告警卡片) | Present | Present | MAINTAINED |
| Category Hierarchy (分类层级) | Present — collapsible sections | Present — collapsible sections | MAINTAINED |
| Relationship Tree (关系图) | Present — 3-level tree (System → Team → Category → Alert) | Present — 3-level tree | MAINTAINED |
| **Routing Pipeline** | **ABSENT** | **Present** — VMAlert → Alertmanager → Inhibition → Notification → iZeus | **NEW FEATURE** |

### 3.2 Detail View

| Feature | Old Dashboard | New Dashboard | Status |
|---------|---------------|---------------|--------|
| Info tab (告警概览) | Present — 8 fields + expression + services | Present — 8 fields + expression + services | MAINTAINED |
| Handbook/Runbook tab | Present — rich markdown (250–350 lines) | Present — minimal markdown (5–15 lines) | **CRITICAL REGRESSION** |
| **Routing tab** | **ABSENT** | **Present** — per-alert routing path diagram | **NEW FEATURE** |
| Detail header | Luckin blue gradient with priority badge | Simple dark header with severity dot | REGRESSION in branding |
| Service level display | `L0/L1/L2` derived from priority | Not shown | REGRESSION |

### 3.3 Sidebar Navigation

| Feature | Old Dashboard | New Dashboard | Status |
|---------|---------------|---------------|--------|
| Collapsible sections | Present — click header to expand/collapse with arrow animation | Flat list — always visible | REGRESSION in UX density |
| "All alerts" section | 全部告警 → 显示全部 | All → Show All | MAINTAINED (English) |
| Filter by priority/severity | 按优先级 (P0/P1/P2/P3) | By Severity (info/warning/critical) | ADAPTED |
| Filter by team | 按团队 | By Team | MAINTAINED (English) |
| Filter by category | 按类别 | By Category | MAINTAINED (English) |
| Filter by notification | ABSENT | By Notification | **NEW FEATURE** |
| Alert count badges | Present on all items | Present on all items | MAINTAINED |

### 3.4 Search

| Feature | Old Dashboard | New Dashboard | Status |
|---------|---------------|---------------|--------|
| Search fields | name, category, team, metric, expression, services, id | name, category, team, metric, expression, services, id, **severity**, **notification** | IMPROVED — 2 more fields |
| Search placeholder | "搜索告警名称、类别、团队、指标..." | "Search alerts by name, category, team, metric..." | MAINTAINED (English) |
| Real-time filtering | Present | Present | MAINTAINED |

### 3.5 Card Design

| Feature | Old Dashboard | New Dashboard | Status |
|---------|---------------|---------------|--------|
| Priority/severity indicator | Left border + badge colored by P0-P3 | Left border + badge colored by severity | ADAPTED |
| Card content | ID, name, category tag, team tag, metric tag | ID, name, category tag, team tag, metric tag | MAINTAINED |
| Card selection highlight | Blue border | Blue border | MAINTAINED |
| Empty state | Emoji + Chinese text "未找到匹配的告警" | Emoji + English text "No matching alerts found" | MAINTAINED (English) |

---

## 4. Critical Gaps (Must Fix Before Go-Live)

### 4.1 CRITICAL: Runbook Content Depth

**The single most important gap in the entire migration.**

| Dimension | Old (handbook) | New (runbook) | Gap |
|-----------|----------------|---------------|-----|
| Average length | ~280 lines | ~8 lines | **97% content loss** |
| Language | Chinese (Simplified) | English | Needs bilingual |
| Structure | 12 standardized sections | 2–3 ad-hoc sections | Needs standardization |
| Diagnostic commands | Category-specific bash/kubectl/mysql commands | Minimal or absent | Must add |
| System access info | AWS console, CLI, DB, Redis, K8s, Grafana, VMAlert | Not included | Must add |
| Root cause analysis | Numbered list + Luckin-specific causes + checklist | Brief mention | Must expand |
| Escalation matrix | 3-tier table (DevOps → Lead → AWS) | Not included | Must add |
| Golden flow assessment | Step-by-step for P0/P1 alerts | Not included | Must add |
| Prevention measures | 6-point bullet list | Not included | Must add |
| Related alerts | Cross-reference section | Not included | Must add |

**Impact**: On-call engineers cannot effectively respond to alerts using the new dashboard runbooks. The old dashboard's SOPs, while containing many Tier B (template-generated) entries, still provide actionable guidance.

**Resolution**: Prompt 1.2 (Write Comprehensive Bilingual Runbooks) — must produce full-depth runbooks for all 72 alerts.

### 4.2 HIGH: Bilingual Support Missing

The old dashboard is Chinese-only. The new dashboard is English-only. The Luckin NA team includes both English-speaking US staff and Chinese-speaking team members / China HQ support.

| Element | Old (Chinese) | New (English) | Need |
|---------|---------------|---------------|------|
| Alert names | Chinese with `【】` brackets | English CamelCase | Both |
| Team names | Chinese (全局, DBA, 系统运维) | English (biz-ops, dba, sys-ops) | Both |
| Service names | Chinese (订单服务, 支付服务) | English (order-service) | Both |
| UI labels | All Chinese | All English | Both |
| SOP content | Chinese | English | Both |

**Resolution**: Prompt 1.2 and 1.3 should produce bilingual runbooks. Consider a language toggle in Prompt 4.2.

### 4.3 HIGH: Sidebar Collapsible Sections Removed

The old dashboard has collapsible sidebar sections that allow the user to expand only the section they care about. The new dashboard shows all sections as a flat list, which is less space-efficient for a 72-alert dashboard.

**Old behavior**: Click section header → expand/collapse with arrow animation
**New behavior**: All sections visible at all times

**Resolution**: Prompt 4.2 should restore collapsible sidebar behavior.

### 4.4 HIGH: SOP Section Structure Not Enforced

The old dashboard follows a strict 12-section SOP structure for every alert. The new dashboard's runbook content is free-form with no consistent structure.

**Old structure (12 sections)**:
1. Title line
2. Header block (standard Luckin reference header)
3. Alert Overview (metadata table)
4. Alert Description
5. Alert Analysis (meaning, impact, services, expression, root causes)
6. Immediate Response (3-step: golden flow → diagnosis → deep investigation)
7. System Access Methods (AWS, DB, Redis, K8s, Grafana, VMAlert)
8. Diagnostic Commands
9. Root Cause Analysis (common + Luckin-specific + checklist)
10. Handling Steps (5-step generic)
11. Escalation Standards (3-tier table)
12. Prevention Measures + Related Alerts

**New structure (ad-hoc)**:
- Section header
- Brief analysis note
- 1–3 action items

**Resolution**: Prompt 1.2 must define and enforce a standardized structure for the new runbooks.

---

## 5. New Features in New Dashboard (Improvements)

### 5.1 Routing Pipeline View

**Entirely new view** showing the full alert routing architecture:

```
VMAlert → Alertmanager → Inhibition Rules → Notification Channels → iZeus APM
```

Each stage shows relevant alerts grouped by notification tier. This provides crucial visibility into the alert pipeline that was completely absent in the old dashboard.

### 5.2 Per-Alert Routing Tab

In the detail view, a third tab shows the routing path for the selected alert:

```
VMAlert Rule → Alertmanager Route → [Inhibition Check] → Notification Channel → iZeus
```

The path is dynamically generated based on the alert's `severity` and `notification` fields.

### 5.3 Notification Channel Tracking

Each alert now has an explicit `notification` field (`wecom-only`, `wecom+twilio-lead`, `wecom+twilio-all`) that was implicit in the old system. This makes the escalation behavior visible and auditable.

### 5.4 Tier System

The `tier` field (1/2/3) is independent of `severity` and maps to notification escalation level. This separation is cleaner than the old P0-P3 system where priority conflated severity with notification behavior.

### 5.5 Migration Traceability (oldIds)

Every new alert has an `oldIds` array mapping back to the old `ALR-NNN` identifiers. This is essential for:
- Verifying completeness of migration
- Training staff on the old→new mapping
- Maintaining historical context

### 5.6 Recording Rules in Expressions

New expressions use `lckna:` prefixed recording rules (e.g., `lckna:rds:cpu_avg3m > 90`) instead of raw PromQL. This improves:
- Query performance (pre-computed)
- Consistency (single definition)
- Maintainability (change threshold without changing expression)

---

## 6. Styling & Branding Gaps

### 6.1 Detail Header

| Feature | Old | New |
|---------|-----|-----|
| Background | Luckin blue gradient (`linear-gradient(135deg, #1a56db, #3b82f6)`) | Simple dark (`#2a2f3a`) |
| Alert ID badge | White on blue gradient | Severity-colored dot |
| Priority badge | Colored pill badge | Not shown as badge |
| Visual impact | Strong brand identity | Generic/muted |

### 6.2 Handbook/Runbook Content Styling

| Feature | Old | New |
|---------|-----|-----|
| Blockquotes | Blue-purple left border (`#667eea`) | Standard markdown |
| Code blocks | Dark background with overflow scroll | Standard markdown |
| Tables | Full-width with striped rows | Standard markdown |
| Headings | Luckin blue `#3b82f6` | Standard markdown |
| Overall polish | Production-grade | Minimal |

### 6.3 Color System

| Element | Old | New |
|---------|-----|-----|
| P0 / Critical | `#ef4444` (red) | `#ef4444` (red) | Same |
| P1 / Warning | `#f59e0b` (amber) | `#f59e0b` (amber) | Same |
| P2 / Info | `#3b82f6` (blue) | `#3b82f6` (blue) | Same |
| P3 | `#6b7280` (gray) | *(eliminated)* | N/A |
| Category headers | 8-color gradient set | Not visible in hierarchy | REGRESSION |

---

## 7. JavaScript Architecture Comparison

### 7.1 State Management

| Feature | Old | New |
|---------|-----|-----|
| Filtered alerts state | `filteredAlerts` array | `filteredAlerts` array | Same |
| Selected alert | `selectedAlert` object | `selectedAlert` object | Same |
| Current view | `currentView` string | `currentView` string | Same |
| Expanded team/category | `expandedTeam`, `expandedCategory` | Not used (flat sidebar) | Regression |

### 7.2 Dependencies

| Library | Old | New |
|---------|-----|-----|
| marked.js | CDN (v9.1.6) | CDN (v9.1.6) | Same |
| Noto Sans SC font | Google Fonts import | Not loaded | Gap for Chinese support |

### 7.3 Code Quality

| Dimension | Old | New |
|-----------|-----|-----|
| Lines of JS | ~500 | ~400 | Cleaner |
| Inline HTML generation | Template literals | Template literals | Same |
| Data-attribute usage | `data-team`, `data-category`, `data-view`, `data-tab` | `data-view`, `data-tab` | Simplified |
| Event handling | Inline `onclick` | Inline `onclick` | Same |

---

## 8. Detailed Gap Registry

### Priority: CRITICAL

| ID | Gap | Old Behavior | New Behavior | Impact | Resolution Prompt |
|----|-----|-------------|-------------|--------|-------------------|
| GAP-001 | Runbook content depth | 250–350 lines, 12 sections, Chinese | 5–15 lines, ad-hoc, English | On-call engineers cannot respond effectively | 1.2, 1.3 |

### Priority: HIGH

| ID | Gap | Old Behavior | New Behavior | Impact | Resolution Prompt |
|----|-----|-------------|-------------|--------|-------------------|
| GAP-002 | No bilingual support | Chinese-only | English-only | Non-English speakers cannot use; HQ support disrupted | 1.2, 4.2 |
| GAP-003 | Sidebar collapse removed | Collapsible sections with arrow animation | Flat always-visible list | Less space-efficient navigation | 4.2 |
| GAP-004 | SOP structure not enforced | Strict 12-section template | Free-form 2–3 sections | Inconsistent quality, missing critical sections | 1.2 |

### Priority: MEDIUM

| ID | Gap | Old Behavior | New Behavior | Impact | Resolution Prompt |
|----|-----|-------------|-------------|--------|-------------------|
| GAP-005 | Detail header branding | Luckin blue gradient | Plain dark background | Reduced brand identity | 4.2 |
| GAP-006 | Handbook content CSS | Rich styles (blockquotes, tables, code) | Standard markdown rendering | Less readable | 4.2 |
| GAP-007 | P2/P3 distinction lost | P2 (standard) vs P3 (low priority) | Both → info | Minor — P3 was rarely actionable | N/A |
| GAP-008 | Service level display | Shows L0/L1/L2 in info tab | Not shown | Missing response-time context | 4.2 |
| GAP-009 | Category header colors | 8-color gradient in hierarchy | No distinct colors | Less visual differentiation | 4.2 |

### Priority: LOW

| ID | Gap | Old Behavior | New Behavior | Impact | Resolution Prompt |
|----|-----|-------------|-------------|--------|-------------------|
| GAP-010 | Chinese font not loaded | Noto Sans SC loaded | Not loaded | Affects future Chinese content | 4.2 |
| GAP-011 | Empty state emoji | 🔍 Chinese text | 🔍 English text | Cosmetic | N/A |
| GAP-012 | Responsive breakpoint | `@media (max-width: 768px)` | Similar breakpoint | Minor tuning needed | 4.2 |
| GAP-013 | Scrollbar styling | Custom dark scrollbar | Custom dark scrollbar | Same | N/A |

---

## 9. Migration Risk Assessment

### 9.1 High Risk

| Risk | Description | Mitigation |
|------|-------------|------------|
| On-call response degradation | New runbooks are too thin to guide incident response | Complete Prompt 1.2 before go-live |
| Alert coverage gaps | 135 → 72 may have dropped valid alert scenarios | Complete Prompt 4.3 (completeness audit) |
| Recording rule dependency | New expressions use `lckna:` recording rules that may not exist yet | Complete Prompt 2.2 (recording rule design) |

### 9.2 Medium Risk

| Risk | Description | Mitigation |
|------|-------------|------------|
| Training gap | Staff trained on P0-P3 system must learn info/warning/critical | Document mapping clearly |
| Search behavior change | Different field names may confuse users | UI help text |
| Bilateral communication | English-only dashboard may slow China HQ escalations | Add bilingual support |

### 9.3 Low Risk

| Risk | Description | Mitigation |
|------|-------------|------------|
| Visual confusion | Different branding may cause disorientation during transition | Brief team walkthrough |
| Bookmark/link breakage | Dashboard is a single HTML file — no URL routing to break | N/A |

---

## 10. Recommendations for Subsequent Prompts

### Immediate (Prompt 4.2: Dashboard UX Enhancement)
1. Restore collapsible sidebar sections (GAP-003)
2. Add Luckin blue gradient to detail header (GAP-005)
3. Enhance runbook/handbook content CSS with blockquotes, code styling (GAP-006)
4. Add service level (L0/L1/L2) display in info tab (GAP-008)
5. Add category header colors to hierarchy view (GAP-009)
6. Load Noto Sans SC font for bilingual support (GAP-010)
7. Consider language toggle mechanism

### Next Priority (Prompt 1.2: Bilingual Runbooks)
1. Define a new standardized runbook structure that preserves the best of the old 12-section format
2. Write comprehensive bilingual runbooks for all 72 alerts
3. Ensure all Tier A reference content from old SOPs is preserved and translated

### Validation (Prompt 4.3: Completeness Audit)
1. Verify every ALR-NNN from old dashboard has a corresponding mapping in new `oldIds`
2. Identify any old alert scenarios not covered by new 72-alert set
3. Validate severity/tier assignments against old P0-P3 classifications

---

## Appendix A: Alert Distribution Comparison

### Old Dashboard (135 alerts by priority)
| Priority | Count | % |
|----------|-------|---|
| P0 | ~30 | 22% |
| P1 | ~40 | 30% |
| P2 | ~40 | 30% |
| P3 | ~25 | 18% |

### New Dashboard (72 alerts by severity)
| Severity | Count | % |
|----------|-------|---|
| critical | ~24 | 33% |
| warning | ~24 | 33% |
| info | ~24 | 33% |

The new dashboard has a more uniform distribution across severity levels due to the consistent 3-tier pattern per metric.

## Appendix B: Feature Matrix Summary

| Feature | Old | New | Status |
|---------|:---:|:---:|--------|
| Card view | ✅ | ✅ | Maintained |
| Hierarchy view | ✅ | ✅ | Maintained |
| Relationship view | ✅ | ✅ | Maintained |
| Routing pipeline view | ❌ | ✅ | **New** |
| Detail — info tab | ✅ | ✅ | Maintained |
| Detail — SOP/runbook tab | ✅ | ⚠️ | **Content regression** |
| Detail — routing tab | ❌ | ✅ | **New** |
| Collapsible sidebar | ✅ | ❌ | Regression |
| Notification tracking | ❌ | ✅ | **New** |
| Migration mapping (oldIds) | ❌ | ✅ | **New** |
| Tier system | ❌ | ✅ | **New** |
| Recording rules | ❌ | ✅ | **New** |
| Bilingual support | ❌ | ❌ | Gap in both |
| Luckin branding | ✅ | ⚠️ | Weakened |
| Rich SOP styling | ✅ | ❌ | Regression |
| Chinese font | ✅ | ❌ | Regression |
| Service level (L0/L1/L2) | ✅ | ❌ | Regression |

---

*Analysis completed: 2026-02-16*
*Next prompt in execution order: **4.3 — Alert Definition Completeness Audit***

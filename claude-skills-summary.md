# Claude Alert Investigation Skills Summary

> Generated from SOP analysis | Date: 2026-01-18

---

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [Skill Details](#skill-details)
   - [EC2 Alert Investigation Skill](#1-ec2-alert-investigation-skill)
   - [RDS Alert Investigation Skill](#2-rds-alert-investigation-skill)
   - [K8s Alert Investigation Skill](#3-k8s-alert-investigation-skill)
3. [Comparison Table](#comparison-table)
4. [MCP Tools Matrix](#mcp-tools-matrix)
5. [Service Priority Reference](#service-priority-reference)

---

## Executive Summary

This document summarizes three Claude Code alert investigation skills designed for the Luckin Coffee infrastructure. Each skill provides structured diagnostic workflows for different infrastructure layers:

| Layer | Skill | Version | Primary Focus |
|-------|-------|---------|---------------|
| Compute | EC2 Investigation | v4.0 | VM-level resource alerts |
| Database | RDS Investigation | v1.0 | MySQL/PostgreSQL database alerts |
| Container | K8s Investigation | v1.0 | Kubernetes pod/node alerts |

---

## Skill Details

### 1. EC2 Alert Investigation Skill

#### Basic Information
| Attribute | Value |
|-----------|-------|
| **Skill Name** | EC2 Alert Investigation SOP |
| **Version** | 4.0 |
| **Edition** | EC2 Instance Diagnosis Edition |
| **Target Platform** | AWS EC2 Instances |

#### Target Scenarios
This skill handles the following alert types:

| Alert Category | Specific Alerts |
|----------------|-----------------|
| **Disk Alerts** | `DiskUsedPercent`, `DiskInodesUsedPercent`, disk I/O issues |
| **Memory Alerts** | `MemUsedPercent`, OOM events, memory pressure |
| **CPU Alerts** | `CPUTotalUsedPercent`, CPU throttling, load average |
| **I/O Alerts** | `DiskIOReadBytes`, `DiskIOWriteBytes`, I/O wait |
| **Network Alerts** | `NetBytesIn`, `NetBytesOut`, packet loss, connection issues |

#### Diagnostic Phases (8 Phases)

```
Phase 0: Alert Validation
    └── Extract alert metadata, validate severity, identify instance

Phase 1: Data Availability Check
    └── Verify Prometheus connectivity, check metric availability

Phase 2: Cross-System Health Assessment
    └── Node exporter status, system-wide metrics collection

Phase 3: Sibling Instance Analysis
    └── Compare with peer instances in same service group

Phase 4: Service-Type Specific Investigation
    └── Application-specific metrics (Java heap, process stats)

Phase 5: Database/Cache Correlation
    └── Check related RDS/Redis dependencies

Phase 6: CloudWatch Integration
    └── Cross-reference with AWS CloudWatch metrics

Phase 7: Output Report Generation
    └── Structured investigation report with findings
```

#### MCP Tools Used

| MCP Server | Tools | Purpose |
|------------|-------|---------|
| **Grafana** | `query_prometheus`, `list_prometheus_label_values` | Primary metrics source |
| **MySQL (mcp-db-gateway)** | `mysql_query` | Service topology lookup |
| **Redis (mcp-db-gateway)** | `redis_command` | Cache correlation |
| **CloudWatch** | `get_metric_data`, `execute_log_insights_query` | AWS metrics/logs |

**Key Prometheus Datasource:**
- Name: `UMBQuerier-Luckin`
- UID: `df8o21agxtkw0d`

#### Output Format

```markdown
## EC2 Investigation Report

### Alert Summary
- Alert Name: [name]
- Instance: [instance_id]
- Severity: [L0/L1/L2]
- Timestamp: [time]

### Investigation Findings
#### Phase Results
- [Phase-by-phase findings]

#### Root Cause Analysis
- [Identified cause]

#### Sibling Instance Comparison
- [Peer analysis results]

### Recommendations
- [Action items]

### Evidence
- [Prometheus queries and results]
- [CloudWatch data]
```

---

### 2. RDS Alert Investigation Skill

#### Basic Information
| Attribute | Value |
|-----------|-------|
| **Skill Name** | RDS Alert Investigation SOP |
| **Version** | 1.0 |
| **Edition** | RDS Database Diagnosis Edition |
| **Target Platform** | AWS RDS (MySQL/PostgreSQL) |

#### Target Scenarios
This skill handles the following alert types:

| Alert Category | Specific Alerts |
|----------------|-----------------|
| **Connection Alerts** | `DatabaseConnections`, connection pool exhaustion |
| **Slow Query Alerts** | `SlowQueries`, query performance degradation |
| **Storage Alerts** | `FreeStorageSpace`, `FreeableMemory`, storage capacity |
| **Replication Alerts** | `ReplicaLag`, replication failures, sync issues |
| **CPU Alerts** | `CPUUtilization`, high CPU from queries |

#### Diagnostic Phases (8 Phases)

```
Phase 0: Alert Validation
    └── Parse alert, identify RDS instance, determine DB engine

Phase 1: Data Availability Check
    └── Verify database connectivity, check monitoring status

Phase 2: Database Health Analysis
    ├── 2a: Connection Analysis
    │   └── Active connections, connection pool status
    ├── 2b: Slow Query Investigation
    │   └── Query analysis, execution plans, lock contention
    ├── 2c: Storage Analysis
    │   └── Disk usage, tablespace health, growth trends
    ├── 2d: Replication Status
    │   └── Replica lag, sync status, binlog position
    └── 2e: CPU Analysis
        └── Query CPU impact, process list analysis

Phase 3: Related Cache Analysis
    └── Redis connection from this database's applications

Phase 4: Related Service Analysis
    └── EC2 instances connecting to this database

Phase 5: CloudWatch Integration
    └── RDS-specific CloudWatch metrics

Phase 6: Alert Correlation
    └── Related alerts from same time window

Phase 7: Output Report Generation
    └── Structured database investigation report
```

#### MCP Tools Used

| MCP Server | Tools | Purpose |
|------------|-------|---------|
| **MySQL (mcp-db-gateway)** | `mysql_query` | Direct database queries (60 servers) |
| **PostgreSQL (mcp-db-gateway)** | `postgres_query` | PostgreSQL queries (3 servers) |
| **Grafana** | `query_prometheus` | Database metrics from exporters |
| **Redis (mcp-db-gateway)** | `redis_command` | Related cache analysis |
| **CloudWatch** | `get_metric_data` | RDS CloudWatch metrics |

**Key Database Servers:**
- DevOps DB: `aws-luckyus-devops-rw`
- Total MySQL Servers: 60
- Total PostgreSQL Servers: 3

#### Output Format

```markdown
## RDS Investigation Report

### Alert Summary
- Alert Name: [name]
- Database Instance: [rds_instance]
- Engine: [MySQL/PostgreSQL]
- Severity: [L0/L1/L2]

### Database Health Status
#### Connection Analysis
- Current Connections: [count]
- Max Connections: [limit]
- Connection Pool Status: [status]

#### Query Performance
- Slow Queries: [count]
- Long Running Queries: [list]
- Lock Contention: [status]

#### Storage Status
- Free Space: [GB]
- Growth Rate: [GB/day]

#### Replication Status
- Replica Lag: [seconds]
- Sync Status: [status]

### Root Cause Analysis
- [Identified cause]

### Recommendations
- [Action items with priority]

### Evidence
- [Query results]
- [CloudWatch metrics]
```

---

### 3. K8s Alert Investigation Skill

#### Basic Information
| Attribute | Value |
|-----------|-------|
| **Skill Name** | K8s Alert Investigation SOP |
| **Version** | 1.0 |
| **Edition** | Kubernetes (EKS) Diagnosis Edition |
| **Target Platform** | Amazon EKS Clusters |

#### Target Scenarios
This skill handles the following alert types:

| Alert Category | Specific Alerts |
|----------------|-----------------|
| **OOMKilled** | Container memory limit exceeded (most common) |
| **CrashLoopBackOff** | Pod repeatedly failing to start |
| **Pending Pods** | Pods unable to be scheduled |
| **Node Issues** | Node NotReady, resource pressure |
| **Resource Alerts** | CPU throttling, memory pressure |

#### Diagnostic Phases (9 Phases)

```
Phase 0: Alert Validation
    └── Parse alert, identify cluster/namespace/pod

Phase 1: Cluster & Node Health Assessment
    └── Node status, resource capacity, system pods

Phase 2: Pod Investigation
    └── Pod status, events, restart history

Phase 3: Resource Analysis
    └── CPU/memory requests vs limits vs actual usage

Phase 4: Workload Configuration Review
    └── Deployment/StatefulSet specs, resource quotas

Phase 5: Application Logs Analysis
    └── Container logs, error patterns, stack traces

Phase 6: Dependency Analysis
    └── Service dependencies, database connections

Phase 7: Alert Correlation
    └── Related alerts from same namespace/cluster

Phase 8: Workload-Specific Playbooks
    └── Type-specific investigation (OOMKilled, CrashLoop, etc.)

Phase 9: Output Report Generation
    └── Structured K8s investigation report
```

#### MCP Tools Used

| MCP Server | Tools | Purpose |
|------------|-------|---------|
| **EKS Server** | `list_k8s_resources`, `get_k8s_events`, `get_pod_logs` | K8s resource inspection |
| **EKS Server** | `manage_k8s_resource` | Resource details |
| **Grafana** | `query_prometheus` | Container metrics |
| **CloudWatch** | `get_cloudwatch_logs`, `get_cloudwatch_metrics` | EKS CloudWatch integration |

**Key EKS Operations:**
- List pods: `list_k8s_resources(kind='Pod', api_version='v1')`
- Get events: `get_k8s_events(kind='Pod', name='pod-name')`
- Get logs: `get_pod_logs(pod_name='pod-name')`

#### Output Format

```markdown
## K8s Investigation Report

### Alert Summary
- Alert Name: [name]
- Cluster: [cluster_name]
- Namespace: [namespace]
- Workload: [deployment/statefulset name]
- Severity: [L0/L1/L2]

### Cluster Health
- Node Status: [Ready/NotReady counts]
- Resource Pressure: [status]

### Pod Analysis
#### Current Status
- Pod Phase: [Running/Pending/Failed]
- Restart Count: [count]
- Last Restart Reason: [reason]

#### Resource Usage
| Resource | Request | Limit | Actual |
|----------|---------|-------|--------|
| CPU | [value] | [value] | [value] |
| Memory | [value] | [value] | [value] |

### Event Timeline
- [Kubernetes events with timestamps]

### Root Cause Analysis
- [Identified cause]

### Recommendations
- [Action items]

### Evidence
- [Pod logs]
- [Prometheus metrics]
- [CloudWatch data]
```

---

## Comparison Table

| Aspect | EC2 Skill (v4.0) | RDS Skill (v1.0) | K8s Skill (v1.0) |
|--------|------------------|------------------|------------------|
| **Primary Target** | EC2 Instances | RDS Databases | EKS Pods/Nodes |
| **Alert Types** | Disk, Memory, CPU, I/O, Network | Connections, Slow Query, Storage, Replication, CPU | OOMKilled, CrashLoopBackOff, Pending, Node Issues |
| **Diagnostic Phases** | 8 phases | 8 phases | 9 phases |
| **Primary MCP Server** | Grafana (Prometheus) | MySQL/PostgreSQL Gateway | EKS Server |
| **Metrics Source** | Prometheus (UMBQuerier) | Direct DB queries + Prometheus | EKS API + Prometheus |
| **Log Source** | CloudWatch Logs | CloudWatch + DB logs | Pod logs + CloudWatch |
| **Sibling Analysis** | Yes (peer instances) | Yes (related services) | Yes (pod replicas) |
| **Dependency Check** | DB/Cache correlation | EC2/Cache correlation | Service mesh + DB/Cache |
| **Output Format** | Structured Markdown | Structured Markdown | Structured Markdown |
| **Service Priority** | L0/L1/L2 classification | L0/L1/L2 classification | L0/L1/L2 classification |

---

## MCP Tools Matrix

| MCP Server | EC2 Skill | RDS Skill | K8s Skill |
|------------|:---------:|:---------:|:---------:|
| **Grafana (Prometheus)** | Primary | Secondary | Secondary |
| **MySQL Gateway** | Topology | Primary | - |
| **PostgreSQL Gateway** | - | Primary | - |
| **Redis Gateway** | Correlation | Correlation | - |
| **CloudWatch (Logs)** | Yes | Yes | Yes |
| **CloudWatch (Metrics)** | Yes | Yes | Yes |
| **EKS Server** | - | - | Primary |

### Prometheus Datasources Reference

| Datasource Name | UID | Primary Use |
|-----------------|-----|-------------|
| UMBQuerier-Luckin | `df8o21agxtkw0d` | EC2/Infrastructure metrics |
| prometheus | `ff7hkeec6c9a8e` | General metrics |
| prometheus_redis | `ff6p0gjt24phce` | Redis metrics |

---

## Service Priority Reference

All three skills use the same service level priority classification:

| Priority | Classification | Response Time | Examples |
|----------|----------------|---------------|----------|
| **L0** | Core Business Critical | < 15 minutes | Payment, Order Processing, User Auth |
| **L1** | Important Services | < 30 minutes | Inventory, Notifications, Reporting |
| **L2** | Normal Services | < 2 hours | Background Jobs, Analytics, Dev/Test |

### Priority Determination Flow

```
Alert Received
    │
    ▼
┌─────────────────────────────────────┐
│ Check service_name in alert labels  │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│ Query DevOps DB for service level   │
│ Server: aws-luckyus-devops-rw       │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│ Apply SLA based on priority level   │
└─────────────────────────────────────┘
```

---

## Quick Reference Commands

### EC2 Investigation Quick Start
```
# Prometheus query for instance metrics
mcp__grafana__query_prometheus(
    datasourceUid="df8o21agxtkw0d",
    expr="node_memory_MemAvailable_bytes{instance='<ip>:9100'}"
)
```

### RDS Investigation Quick Start
```
# Check active connections
mcp__mcp-db-gateway__mysql_query(
    server="<rds-server>",
    sql="SHOW PROCESSLIST"
)
```

### K8s Investigation Quick Start
```
# Get pod events
mcp__eks-server__get_k8s_events(
    cluster_name="<cluster>",
    kind="Pod",
    name="<pod-name>",
    namespace="<namespace>"
)
```

---

*Document generated by Claude Code based on SOP analysis*

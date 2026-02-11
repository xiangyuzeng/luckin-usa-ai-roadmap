# MCP Architecture Guide

**Document Version:** 1.0
**Last Updated:** 2026-01-18
**Environment:** Production (LuckyUS)

---

## Table of Contents

1. [Overview](#1-overview)
2. [Components](#2-components)
3. [Connection Flow](#3-connection-flow)
4. [Security Model](#4-security-model)
5. [Data Endpoint Summary](#5-data-endpoint-summary)
6. [Configuration Reference](#6-configuration-reference)

---

## 1. Overview

### What is MCP?

The **Model Context Protocol (MCP)** is an open standard that enables AI assistants like Claude to securely connect to external data sources and tools. MCP provides a standardized way for AI models to:

- Query databases (MySQL, PostgreSQL, Redis)
- Access monitoring systems (Grafana, Prometheus, CloudWatch)
- Interact with cloud infrastructure (AWS services)
- Execute operations through a controlled, auditable interface

### How MCP Works with Claude Code

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CLAUDE CODE CLI                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         Claude AI Model                              │   │
│  │                    (claude-opus-4-5-20251101)                        │   │
│  └──────────────────────────────┬──────────────────────────────────────┘   │
│                                 │                                           │
│                                 ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      MCP Protocol Layer                              │   │
│  │            (JSON-RPC 2.0 over stdio/HTTP transport)                  │   │
│  └──────────────────────────────┬──────────────────────────────────────┘   │
└─────────────────────────────────┼───────────────────────────────────────────┘
                                  │
        ┌─────────────────────────┼─────────────────────────┐
        │                         │                         │
        ▼                         ▼                         ▼
┌───────────────┐       ┌───────────────┐       ┌───────────────┐
│  MCP Server   │       │  MCP Server   │       │  MCP Server   │
│  (Database)   │       │  (Grafana)    │       │  (AWS)        │
└───────┬───────┘       └───────┬───────┘       └───────┬───────┘
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐       ┌───────────────┐       ┌───────────────┐
│ MySQL/PG/Redis│       │ Grafana API   │       │ AWS APIs      │
│   Instances   │       │ Prometheus    │       │ CloudWatch    │
└───────────────┘       └───────────────┘       └───────────────┘
```

### Key Benefits

| Benefit | Description |
|---------|-------------|
| **Standardization** | Unified protocol for all data source interactions |
| **Security** | Credentials isolated in MCP servers, never exposed to AI |
| **Auditability** | All operations logged and traceable |
| **Extensibility** | Easy to add new data sources via MCP servers |
| **Context Awareness** | AI can query real-time data to provide accurate responses |

---

## 2. Components

### 2.1 Claude Code Client

The Claude Code client is the primary interface between the user and the AI system.

```yaml
Component: Claude Code CLI
Role: User Interface & AI Orchestration
Model: claude-opus-4-5-20251101
Capabilities:
  - Natural language understanding
  - Tool selection and orchestration
  - Response synthesis
  - Multi-turn conversation management
```

**Responsibilities:**
- Parse user queries and determine required tools
- Invoke MCP tools with appropriate parameters
- Aggregate responses from multiple data sources
- Present results in human-readable format

### 2.2 MCP Protocol Layer

The protocol layer handles communication between Claude and MCP servers.

```
┌─────────────────────────────────────────────────────────────────┐
│                     MCP Protocol Specification                   │
├─────────────────────────────────────────────────────────────────┤
│  Transport:     stdio (local) / HTTP+SSE (remote)               │
│  Format:        JSON-RPC 2.0                                     │
│  Auth:          Per-server credentials (env vars/config)         │
│  Discovery:     tools/list, resources/list                       │
└─────────────────────────────────────────────────────────────────┘
```

**Message Types:**

| Type | Direction | Purpose |
|------|-----------|---------|
| `initialize` | Client → Server | Establish connection, negotiate capabilities |
| `tools/list` | Client → Server | Discover available tools |
| `tools/call` | Client → Server | Execute a tool with parameters |
| `resources/list` | Client → Server | List available resources |
| `resources/read` | Client → Server | Read resource content |

### 2.3 Docker MCP Bridges

MCP servers run as containerized services, providing isolated access to backend systems.

#### Database Gateway (mcp-db-gateway)

```yaml
Server: mcp-db-gateway
Container: Docker
Purpose: Unified database access layer
Supported Backends:
  - MySQL (61 instances)
  - PostgreSQL (3 instances)
  - Redis (74 clusters)

Tools Provided:
  - mysql_query: Execute SQL on MySQL servers
  - postgres_query: Execute SQL on PostgreSQL servers
  - redis_command: Execute Redis commands
  - list_servers: Enumerate available database servers
```

#### Grafana MCP Server

```yaml
Server: grafana / grafana-lucky
Container: Docker
Purpose: Observability and monitoring integration
Backends:
  - Grafana API (dashboards, alerts, incidents)
  - Prometheus (metrics queries)
  - Loki (log queries)

Tools Provided:
  - search_dashboards: Find dashboards by query
  - query_prometheus: Execute PromQL queries
  - query_loki_logs: Execute LogQL queries
  - list_alert_rules: Retrieve alert configurations
  - list_datasources: Enumerate data sources
```

#### AWS MCP Servers

```yaml
Servers:
  - eks-server: Kubernetes cluster management
  - cloudwatch-server: Logs and metrics
  - cost-explorer: Billing and cost analysis
  - aws-documentation-server: Documentation search
  - aws-pricing-server: Pricing information
  - ccapi-server: Cloud Control API

Tools Provided:
  - describe_log_groups: List CloudWatch log groups
  - execute_log_insights_query: Run log queries
  - get_metric_data: Retrieve CloudWatch metrics
  - list_k8s_resources: List Kubernetes resources
  - get_cost_and_usage: Query AWS costs
```

#### Prometheus MCP Server

```yaml
Server: prometheus
Container: Docker
Purpose: Direct Prometheus metrics access

Tools Provided:
  - prometheus_query: Instant queries
  - prometheus_query_range: Range queries
  - prometheus_list_metrics: Enumerate metrics
  - prometheus_metric_metadata: Get metric metadata
  - prometheus_list_labels: List label names
  - prometheus_label_values: Get label values
```

### 2.4 Backend Services

#### Amazon RDS Instances

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS RDS Fleet                             │
├─────────────────────────────────────────────────────────────┤
│  MySQL Instances:      61 (all -rw read-write endpoints)    │
│  PostgreSQL Instances: 3                                     │
│  Region:               us-east-1 (luckyus)                  │
│  Naming Convention:    aws-luckyus-{service}-rw             │
└─────────────────────────────────────────────────────────────┘
```

#### Amazon ElastiCache (Redis)

```
┌─────────────────────────────────────────────────────────────┐
│                 ElastiCache Redis Fleet                      │
├─────────────────────────────────────────────────────────────┤
│  Total Clusters:       74                                    │
│  Region:               us-east-1 (luckyus)                  │
│  Naming Convention:    luckyus-{service}                    │
│  Use Cases:            Session, Cache, Queue, Pub/Sub       │
└─────────────────────────────────────────────────────────────┘
```

#### Grafana & Prometheus

```
┌─────────────────────────────────────────────────────────────┐
│                 Observability Stack                          │
├─────────────────────────────────────────────────────────────┤
│  Grafana Datasources:                                        │
│    - UMBQuerier-Luckin (Prometheus, default)                │
│    - prometheus (Prometheus)                                 │
│    - prometheus_redis (Prometheus)                           │
│    - MySQL-Ldas, MySQL-luckyhealth, MySQL-iriskcontrol      │
│    - elasticsearch (Log analytics)                           │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Connection Flow

### Step-by-Step Query Processing

```
User Query: "Show me the CPU usage for the auth service in the last hour"

Step 1: Query Analysis
┌────────────────────────────────────────────────────────────┐
│ Claude Code receives natural language query                 │
│ AI determines: Need Prometheus metrics for auth service     │
│ Selected tool: mcp__prometheus__prometheus_query_range      │
└────────────────────────────────────────────────────────────┘
                              │
                              ▼
Step 2: Tool Invocation
┌────────────────────────────────────────────────────────────┐
│ MCP Protocol Layer constructs JSON-RPC request:            │
│ {                                                           │
│   "method": "tools/call",                                   │
│   "params": {                                               │
│     "name": "prometheus_query_range",                       │
│     "arguments": {                                          │
│       "query": "rate(cpu_usage{service='auth'}[5m])",      │
│       "start": "2026-01-18T09:00:00Z",                     │
│       "end": "2026-01-18T10:00:00Z",                       │
│       "step": "60s"                                         │
│     }                                                       │
│   }                                                         │
│ }                                                           │
└────────────────────────────────────────────────────────────┘
                              │
                              ▼
Step 3: MCP Server Processing
┌────────────────────────────────────────────────────────────┐
│ Prometheus MCP Server:                                      │
│ 1. Validates request parameters                             │
│ 2. Authenticates to Prometheus using stored credentials     │
│ 3. Executes PromQL query against Prometheus API             │
│ 4. Transforms response to MCP format                        │
└────────────────────────────────────────────────────────────┘
                              │
                              ▼
Step 4: Backend Query
┌────────────────────────────────────────────────────────────┐
│ Prometheus Server:                                          │
│ HTTP GET /api/v1/query_range                               │
│ → Evaluates PromQL expression                              │
│ → Returns time series data                                  │
└────────────────────────────────────────────────────────────┘
                              │
                              ▼
Step 5: Response Synthesis
┌────────────────────────────────────────────────────────────┐
│ Claude Code:                                                │
│ 1. Receives structured metric data                          │
│ 2. Analyzes trends and patterns                             │
│ 3. Generates human-readable summary                         │
│ 4. Presents results with visualizations if needed           │
└────────────────────────────────────────────────────────────┘
```

### Database Query Flow

```
┌──────────┐    ┌─────────────┐    ┌──────────────┐    ┌─────────┐
│  Claude  │───▶│ MCP Protocol│───▶│ db-gateway   │───▶│  MySQL  │
│   Code   │    │   Layer     │    │   Server     │    │   RDS   │
└──────────┘    └─────────────┘    └──────────────┘    └─────────┘
     │                                    │
     │         JSON-RPC Request           │
     │   ┌─────────────────────────────┐  │
     │   │ {                           │  │
     │   │   "tool": "mysql_query",    │  │
     │   │   "params": {               │  │
     │   │     "server": "aws-luckyus  │  │
     │   │              -salescrm-rw", │  │
     │   │     "sql": "SELECT ..."     │  │
     │   │   }                         │  │
     │   │ }                           │  │
     │   └─────────────────────────────┘  │
     │                                    │
     │◀───────── Query Results ───────────│
```

---

## 4. Security Model

### Credential Isolation Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    SECURITY BOUNDARY                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────┐                                                │
│  │ Claude Code │  ← NO credentials stored here                  │
│  │   (AI)      │  ← Cannot access raw connection strings        │
│  └──────┬──────┘  ← Only sees tool names and parameters         │
│         │                                                        │
│         │ MCP Protocol (credential-free)                        │
│         ▼                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              MCP Server Container                         │   │
│  │  ┌─────────────────────────────────────────────────┐    │   │
│  │  │         Environment Variables                    │    │   │
│  │  │  DB_HOST=******.rds.amazonaws.com               │    │   │
│  │  │  DB_USER=******                                  │    │   │
│  │  │  DB_PASS=******                                  │    │   │
│  │  │  GRAFANA_TOKEN=******                           │    │   │
│  │  └─────────────────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Security Principles

| Principle | Implementation |
|-----------|----------------|
| **Least Privilege** | Each MCP server has minimal required permissions |
| **Credential Isolation** | Secrets stored in container env vars, not exposed to AI |
| **Network Segmentation** | MCP servers in private subnets with security groups |
| **Audit Logging** | All tool invocations logged with timestamps |
| **Input Validation** | SQL injection prevention, parameter sanitization |
| **Read-Write Control** | Separate endpoints for read vs write operations |

### Access Control Matrix

```
┌────────────────────┬─────────┬─────────┬─────────┬──────────┐
│ Component          │ Read    │ Write   │ Delete  │ Admin    │
├────────────────────┼─────────┼─────────┼─────────┼──────────┤
│ MySQL Databases    │ ✓       │ ✓ (rw)  │ ✗       │ ✗        │
│ PostgreSQL         │ ✓       │ ✓ (rw)  │ ✗       │ ✗        │
│ Redis Clusters     │ ✓       │ ✓       │ ✗       │ ✗        │
│ Grafana Dashboards │ ✓       │ ✓       │ ✗       │ ✗        │
│ Prometheus Metrics │ ✓       │ ✗       │ ✗       │ ✗        │
│ CloudWatch Logs    │ ✓       │ ✗       │ ✗       │ ✗        │
│ AWS Resources      │ ✓       │ Limited │ Limited │ ✗        │
└────────────────────┴─────────┴─────────┴─────────┴──────────┘
```

### Credential Storage

```yaml
# MCP Server Configuration (Docker)
services:
  mcp-db-gateway:
    environment:
      # Credentials injected at runtime
      - MYSQL_SERVERS_CONFIG=/secrets/mysql-servers.json
      - REDIS_SERVERS_CONFIG=/secrets/redis-servers.json
      - POSTGRES_SERVERS_CONFIG=/secrets/postgres-servers.json
    secrets:
      - mysql-servers
      - redis-servers
      - postgres-servers

  grafana-mcp:
    environment:
      - GRAFANA_URL=${GRAFANA_URL}
      - GRAFANA_API_KEY=${GRAFANA_API_KEY}  # From secrets manager
```

---

## 5. Data Endpoint Summary

### Total Endpoints by Type

| Category | Type | Count | Status |
|----------|------|------:|--------|
| **Databases** | MySQL | 61 | 🟢 Connected |
| **Databases** | PostgreSQL | 3 | 🟢 Connected |
| **Databases** | Redis | 74 | 🟢 Connected |
| **Observability** | Grafana Datasources | 7 | 🟢 Connected |
| **Observability** | Prometheus Endpoints | 3 | 🟢 Connected |
| **Cloud** | CloudWatch | 1 | 🔴 Limited Access |
| **Cloud** | AWS Services | 6 | 🟢 Connected |
| | **TOTAL** | **155** | **99% Available** |

### Endpoints by Business Domain

```
┌────────────────────────────────────────────────────────────┐
│                  Endpoint Distribution                      │
├────────────────────────────────────────────────────────────┤
│                                                             │
│  Sales & CRM         ████████████████████  22 endpoints    │
│  SCM (Supply Chain)  ██████████████████████████ 28 endpoints│
│  DevOps & Infra      ████████████████  18 endpoints        │
│  Finance             ████████  10 endpoints                 │
│  Operations          ████████████  14 endpoints            │
│  Platform Services   ██████████████████████  24 endpoints  │
│  Big Data & AI       ████████  10 endpoints                │
│  Auth & Security     ████████████  14 endpoints            │
│  Observability       ██████  8 endpoints                   │
│  Other               ██████  7 endpoints                   │
│                                                             │
└────────────────────────────────────────────────────────────┘
```

### MCP Server Tool Summary

| MCP Server | Tools Available | Primary Functions |
|------------|----------------:|-------------------|
| mcp-db-gateway | 4 | Database queries (MySQL, PostgreSQL, Redis) |
| grafana | 45+ | Dashboards, alerts, Prometheus, Loki, incidents |
| grafana-lucky | 45+ | Secondary Grafana instance |
| prometheus | 11 | Direct Prometheus metrics access |
| eks-server | 15+ | Kubernetes management |
| cloudwatch-server | 10+ | Logs, metrics, alarms |
| cost-explorer | 8 | AWS billing and cost analysis |
| aws-pricing-server | 8 | Service pricing information |
| aws-documentation-server | 3 | Documentation search |
| ccapi-server | 15+ | Cloud Control API operations |

---

## 6. Configuration Reference

### Environment Variables

```bash
# Database Gateway
MCP_DB_GATEWAY_MYSQL_CONFIG=/config/mysql-servers.json
MCP_DB_GATEWAY_REDIS_CONFIG=/config/redis-servers.json
MCP_DB_GATEWAY_POSTGRES_CONFIG=/config/postgres-servers.json

# Grafana
GRAFANA_URL=https://grafana.example.com
GRAFANA_API_KEY=glsa_xxxxxxxxxxxx

# AWS
AWS_REGION=us-east-1
AWS_PROFILE=production

# Prometheus
PROMETHEUS_URL=https://prometheus.example.com
```

### Docker Compose Example

```yaml
version: '3.8'

services:
  mcp-db-gateway:
    image: mcp/db-gateway:latest
    environment:
      - CONFIG_PATH=/config
    volumes:
      - ./config:/config:ro
      - ./secrets:/secrets:ro
    networks:
      - mcp-internal

  mcp-grafana:
    image: mcp/grafana:latest
    environment:
      - GRAFANA_URL=${GRAFANA_URL}
      - GRAFANA_API_KEY=${GRAFANA_API_KEY}
    networks:
      - mcp-internal

  mcp-prometheus:
    image: mcp/prometheus:latest
    environment:
      - PROMETHEUS_URL=${PROMETHEUS_URL}
    networks:
      - mcp-internal

networks:
  mcp-internal:
    driver: bridge
```

### Health Check Endpoints

```bash
# Check MCP server health
curl http://localhost:3000/health

# List available tools
curl http://localhost:3000/tools/list

# Test database connectivity
curl -X POST http://localhost:3000/tools/call \
  -H "Content-Type: application/json" \
  -d '{"name": "list_servers", "arguments": {}}'
```

---

## Appendix: Quick Reference

### Common MCP Tool Patterns

```python
# Query MySQL database
mcp__mcp-db-gateway__mysql_query(
    server="aws-luckyus-salescrm-rw",
    sql="SELECT * FROM customers LIMIT 10"
)

# Query Prometheus metrics
mcp__prometheus__prometheus_query(
    query="rate(http_requests_total[5m])"
)

# Search Grafana dashboards
mcp__grafana__search_dashboards(
    query="sales metrics"
)

# Execute Redis command
mcp__mcp-db-gateway__redis_command(
    server="luckyus-session",
    command="GET",
    args=["user:12345:session"]
)
```

---

*Document generated by Claude Code MCP Integration*

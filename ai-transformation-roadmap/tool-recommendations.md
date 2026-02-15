# Claude Code Tool & Plugin Recommendations for Luckin Coffee USA AI Roadmap

> **41 AI Use Cases x Recommended MCP Servers, Skills, Hooks, and Tooling**
> Generated: 2026-02-15

---

## Table of Contents
1. [Platform-Wide Recommendations (Install First)](#platform-wide)
2. [Department 1: Finance (UC-FN-01 to UC-FN-05)](#finance)
3. [Department 2: Marketing & Customer Analytics (UC-MK-01 to UC-MK-10)](#marketing)
4. [Department 3: Product & Menu Innovation (UC-PR-01 to UC-PR-05)](#product)
5. [Department 4: Operations (UC-OP-01 to UC-OP-06)](#operations)
6. [Department 5: Supply Chain & Inventory (UC-SC-01 to UC-SC-05)](#supply-chain)
7. [Department 6: IT Infrastructure & DevOps (UC-IT-01 to UC-IT-06)](#it-infra)
8. [Department 7: Executive & Strategy (UC-EX-01 to UC-EX-04)](#executive)
9. [Claude Code Configuration Best Practices](#best-practices)
10. [Priority Installation Order](#install-order)

---

## <a id="platform-wide"></a>1. Platform-Wide Recommendations (Install First)

These tools benefit **multiple use cases across all departments** and should be installed as foundational infrastructure.

### 1.1 Data Warehouse & Analytics

| Tool | Install Command | Why |
|------|----------------|-----|
| **AWS Redshift MCP Server** (Official) | `uvx awslabs.redshift-mcp-server@latest` | Your roadmap targets Redshift Serverless as the data warehouse. This is the official AWS Labs server for browsing schemas, running SQL queries, and managing clusters. Feeds UC-EX-03, UC-FN-02, UC-MK-01, and any tool needing warehouse queries. |
| **AWS Data Processing MCP Server** (Glue/EMR/Athena) | `uvx awslabs.aws-dataprocessing-mcp-server@latest` | Covers AWS Glue ETL jobs, crawlers, Data Catalog, workflows, triggers, and Athena SQL queries. Critical for the 16 CDC pipelines planned in your roadmap. |
| **DuckDB MCP Server** | `claude mcp add duckdb -- uvx mcp-server-motherduck --db-path :memory: --read-write` | Local analytical queries against CSVs/Parquet without loading into Redshift. Great for ad-hoc analysis during development of any use case. |

### 1.2 ML Platform & Experiment Tracking

| Tool | Install Command | Why |
|------|----------------|-----|
| **MLflow MCP Server** (Official) | Built into MLflow 2.x+ (`pip install mlflow`) | Your roadmap specifies MLflow for model registry. The official MCP server enables natural language queries against experiments, model versions, run comparisons, and artifact management. Feeds all 12 planned ML models. |
| **mlflowMCPServer** (Community, richer features) | `pip install mlflow-mcp-server` (GitHub: [iRahulPandey/mlflowMCPServer](https://github.com/iRahulPandey/mlflowMCPServer)) | Broader experiment management -- browse experiments, compare runs, query metrics via natural language. Complement the official server. |
| **Jupyter MCP Server** | `pip install jupyter-mcp-server` or `uvx jupyter_mcp_server` (GitHub: [datalayer/jupyter-mcp-server](https://github.com/datalayer/jupyter-mcp-server)) | Execute notebook cells, run EDA, train models interactively. Essential for all ML development workflows. |

### 1.3 Monitoring & Observability (Already Installed)

You already have **Grafana MCP**, **Prometheus MCP**, and **CloudWatch MCP** servers installed. These cover UC-IT-01, UC-OP-02, and monitoring for all use cases.

### 1.4 Infrastructure Management

| Tool | Install Command | Why |
|------|----------------|-----|
| **Terraform MCP Server** (HashiCorp Official) | `npx @hashicorp/terraform-mcp-server` (GitHub: [hashicorp/terraform-mcp-server](https://github.com/hashicorp/terraform-mcp-server)) | IaC for provisioning Redshift, SageMaker, Glue, and all AI platform infrastructure. |
| **AWS S3 MCP Server** | `uvx awslabs.s3-tables-mcp-server@latest` | Data lake management (raw/staging/warehouse zones in S3). |
| **Docker MCP Server** | `pip install mcp-server-docker` (GitHub: [ckreiling/mcp-server-docker](https://github.com/ckreiling/mcp-server-docker)) | Container management for ML model serving, microservices deployment. |
| **Kubernetes MCP Server** | `claude mcp add kubernetes -- npx mcp-server-kubernetes` (GitHub: [Flux159/mcp-server-kubernetes](https://github.com/Flux159/mcp-server-kubernetes)) | Broader K8s management beyond EKS -- pod cleanup, Helm support, secrets masking. |

### 1.5 Communication & Collaboration

| Tool | Install Command | Why |
|------|----------------|-----|
| **Slack MCP Server** | GitHub: [korotovsky/slack-mcp-server](https://github.com/korotovsky/slack-mcp-server) | Alert delivery for UC-EX-01 (Daily Briefing), UC-OP-02 (Anomaly Alerts), UC-IT-01 (Infrastructure Alerts). Enable `SLACK_MCP_ADD_MESSAGE_TOOL=true` for posting. |
| **GitHub MCP Server** (Official) | `go install github.com/github/github-mcp-server@latest` (GitHub: [github/github-mcp-server](https://github.com/github/github-mcp-server)) | Project management, issue tracking, PR automation for the 41 use case projects. |

### 1.6 Data Science & Analysis

| Tool | Install Command | Why |
|------|----------------|-----|
| **Pandas MCP Server** | `pip install mcp-pandas` (GitHub: [tonybaloney/mcp-pandas](https://github.com/tonybaloney/mcp-pandas)) | DataFrame operations, statistical analysis for any use case. |
| **DuckDB + Visualization** | `pip install mcp-visualization-duckdb` (GitHub: [xoniks/mcp-visualization-duckdb](https://github.com/xoniks/mcp-visualization-duckdb)) | Natural language to Plotly charts, automatic statistical analysis, pattern detection. |

---

## <a id="finance"></a>2. Department 1: Finance

### UC-FN-01: Tax Compliance Automation (P0, Score: 4.45)
**AI Approach**: Rules-based tax engine + ML audit anomaly detection

| Tool | Why Install |
|------|-------------|
| **Accounting Practice MCP Server** | GitHub: [RealDealCPA-VR/MCP-Accounting](https://glama.ai/mcp/servers/@RealDealCPA-VR/MCP-Accounting). Automated sales tax compliance with nexus monitoring across all US states. Real-time tax liability calculations. Directly addresses NYC sales tax compliance. |
| **TaxBandits MCP Server** | [developer.taxbandits.com/docs/mcp](https://developer.taxbandits.com/docs/mcp/). Remote MCP server for tax filing and compliance automation. |
| **Custom Skill**: `/tax-audit` | Create `.claude/skills/tax-audit/SKILL.md` that queries the `fi_tax` database, cross-references order locations with NYC tax rates, and flags anomalies. |

### UC-FN-02: Revenue Reconciliation (P0, Score: 4.35)
**AI Approach**: Deterministic 3-way matching + ML fuzzy exception classification

| Tool | Why Install |
|------|-------------|
| **Stripe MCP Server** (Official) | `npx -y @stripe/mcp --tools=all --api-key=$STRIPE_KEY` ([docs.stripe.com/mcp](https://docs.stripe.com/mcp)). Full Stripe API access -- list transactions, disputes, refunds, balances. Critical for 3-way matching (orders vs. Stripe payments vs. accounting). |
| **QuickBooks MCP Server** | [coupler.io/mcp/quickbooks](https://www.coupler.io/mcp/quickbooks) or [LokiMCPUniverse/quickbooks-mcp-server](https://github.com/LokiMCPUniverse/quickbooks-mcp-server). Connects to accounting system for reconciliation. |
| **Custom Hook**: Post-reconciliation alert | Create a hook that sends Slack notification when reconciliation exceptions exceed threshold: `PostToolUse` matcher on the reconciliation query. |

### UC-FN-03: Payment Fraud Detection (P1, Score: 3.95)
**AI Approach**: Isolation Forest anomaly detection + supervised classification

| Tool | Why Install |
|------|-------------|
| **Stripe MCP Server** | Same as UC-FN-02. Access Stripe Radar data, dispute history, risk scores. |
| **Elasticsearch MCP Server** (Official) | Docker: [elastic/mcp-server-elasticsearch](https://github.com/elastic/mcp-server-elasticsearch). Query fraud pattern logs, risk control rules (4.1M records), blacklist entries (1,395 records). |
| **Custom Skill**: `/fraud-check` | Query real-time transaction patterns against trained Isolation Forest model via SageMaker endpoint. |

### UC-FN-04: Payment Channel Cost Optimizer (P2, Score: 3.00)
**AI Approach**: Cost analysis by payment channel + routing optimization

| Tool | Why Install |
|------|-------------|
| **Stripe MCP Server** | Compare fee structures across payment methods (Apple Pay, Google Pay, credit cards). |
| **DoorDash MCP Server** | [amannm/doordash-mcp](https://lobehub.com/mcp/amannm-doordash-mcp). Access delivery quotes and commission data for DoorDash channel cost analysis. |

### UC-FN-05: Financial Forecasting & Scenario Modeling (P3, Score: 2.65)
**AI Approach**: Time-series forecasting + Monte Carlo simulation

| Tool | Why Install |
|------|-------------|
| **Nixtla TimeGPT SDK** | `pip install nixtla`. Zero-shot time series forecasting for revenue projections. Trained on 100B+ data points. |
| **Jupyter MCP Server** | Run Monte Carlo simulations interactively for scenario modeling. |
| **AWS Cost Explorer MCP** (Already installed) | Historical AWS cost data feeds into financial models. |

---

## <a id="marketing"></a>3. Department 2: Marketing & Customer Analytics

### UC-MK-01: Customer 360 Unified Profile (P0, Score: 4.15)
**AI Approach**: Entity resolution across 8+ databases

| Tool | Why Install |
|------|-------------|
| **MongoDB MCP Server** (Official) | `npm install mongodb-mcp-server` ([mongodb-js/mongodb-mcp-server](https://github.com/mongodb-js/mongodb-mcp-server)). Natural language queries against MongoDB collections storing CDP/CRM data. Schema inspection for entity resolution mapping. |
| **Elasticsearch MCP Server** | Query customer search/analytics data for profile enrichment. |
| **Custom Skill**: `/customer-lookup` | Federated query across MySQL (orders), Redis (sessions), MongoDB (profiles), PostgreSQL (analytics) to build unified customer view. |

### UC-MK-02: Churn Prediction & Win-Back (P0, Score: 4.30)
**AI Approach**: XGBoost/LightGBM classification, 60-day horizon

| Tool | Why Install |
|------|-------------|
| **MLflow MCP Server** | Track churn model experiments, compare feature importance across runs, manage model versions. |
| **SageMaker MCP Architecture** | [AWS Blog reference architecture](https://aws.amazon.com/blogs/machine-learning/enhance-ai-agents-using-predictive-ml-models-with-amazon-sagemaker-ai-and-model-context-protocol-mcp/). Wrap SageMaker churn prediction endpoint as MCP tool for real-time scoring. |
| **Custom Skill**: `/churn-report` | Generate weekly churn risk report with top at-risk customers and recommended win-back actions. |

### UC-MK-03: Coupon ROI Optimizer (P1, Score: 4.10)
**AI Approach**: T-Learner uplift modeling (causal inference)

| Tool | Why Install |
|------|-------------|
| **Jupyter MCP Server** | Interactive causal inference analysis on 2.42M active coupons and 6.4M A/B experiments. |
| **Custom Skill**: `/coupon-roi` | Query coupon performance, compute uplift metrics, recommend optimal discount levels per customer segment. |

### UC-MK-04: Next-Best-Action Engine (P1, Score: 3.65)
**AI Approach**: Multi-armed bandit / contextual bandit

| Tool | Why Install |
|------|-------------|
| **AWS MSK MCP Server** (Official) | [awslabs.github.io/mcp/servers/aws-msk-mcp-server](https://awslabs.github.io/mcp/servers/aws-msk-mcp-server). Manage/monitor MSK (Kafka) clusters for the real-time event stream needed for <100ms scoring. |
| **Kafka MCP Server** (Community) | `brew install tuannvm/tap/kafka-mcp-server` ([tuannvm/kafka-mcp-server](https://github.com/tuannvm/kafka-mcp-server)). Direct Kafka topic management, produce/consume test messages. |

### UC-MK-05: Customer Lifetime Value Prediction (P2, Score: 3.35)
**AI Approach**: BG/NBD + Gamma-Gamma models

| Tool | Why Install |
|------|-------------|
| **MLflow MCP Server** | Track CLV model experiments and manage model registry. |
| **Jupyter MCP Server** | Develop BG/NBD models using `lifetimes` Python library interactively. |

### UC-MK-06: Push Notification Optimizer (P1, Score: 3.60)
**AI Approach**: Multi-armed bandit for timing/content

| Tool | Why Install |
|------|-------------|
| **Custom Skill**: `/push-optimize` | Query 2.3M push/SMS records, analyze open rates by time/content, recommend optimal send windows per user segment. |
| **Scheduler MCP Server** | [PhialsBasement/scheduler-mcp](https://github.com/PhialsBasement/scheduler-mcp). Schedule push notification batch jobs using cron expressions. |

### UC-MK-07: A/B Test Auto-Optimization (P1, Score: 3.80)
**AI Approach**: Bayesian A/B testing with Thompson Sampling

| Tool | Why Install |
|------|-------------|
| **Jupyter MCP Server** | Run Bayesian statistical analysis on 6.4M experiment records. |
| **Custom Skill**: `/ab-test` | Auto-compute posterior distributions, expected loss, and stopping rules for active experiments. |

### UC-MK-08: Social Listening & Sentiment Analysis (P3, Score: 2.45)
**AI Approach**: NLP sentiment classification

| Tool | Why Install |
|------|-------------|
| **Apify MCP Server** (Critical) | `npx -y @apify/actors-mcp-server` (env: `APIFY_TOKEN`). [github.com/apify/apify-mcp-server](https://github.com/apify/apify-mcp-server). Scrapes TikTok, Instagram, Google Maps/Reviews, and thousands more platforms. This is the **#1 tool** for this use case -- it directly solves the "requires external data collection" blocker. |
| **Google Play Reviews MCP** | [Kirill812/GPlay_reviews_MCP_server](https://github.com/Kirill812/GPlay_reviews_MCP_server). Automated sentiment analytics on app store reviews (rating filters, keyword search). |
| **Xpoz Social Media Intelligence** | [xpoz.ai](https://www.xpoz.ai/). Native MCP support for TikTok/Instagram/Reddit aggregation and trend analysis. |
| **Custom Skill**: `/sentiment-report` | Aggregate social mentions, compute sentiment scores, compare against competitor sentiment. |

### UC-MK-09: Referral Network Analysis (P3, Score: 2.55)
**AI Approach**: Graph analysis on referral chain data

| Tool | Why Install |
|------|-------------|
| **Jupyter MCP Server** | Run NetworkX graph analysis on referral chain data. |

### UC-MK-10: Channel Attribution Modeling (P3, Score: 2.50)
**AI Approach**: Multi-touch attribution

| Tool | Why Install |
|------|-------------|
| **Apify MCP Server** | Collect marketing channel data from external sources. |
| **Custom Skill**: `/attribution` | Once UTM/attribution SDK is deployed, query attribution data and compute Shapley-value multi-touch models. |

---

## <a id="product"></a>4. Department 3: Product & Menu Innovation

### UC-PR-01: Menu Engineering Matrix / BCG Analysis (P1, Score: 3.90)
**AI Approach**: BCG quadrant calculation + ML product affinity

| Tool | Why Install |
|------|-------------|
| **DuckDB + Visualization MCP** | Generate BCG matrix scatter plots and product performance visualizations from 602K order items. |
| **Custom Skill**: `/menu-matrix` | Compute stars/plowhorses/puzzles/dogs classification for all 1,448 products. |

### UC-PR-02: Personalized Product Recommendations (P2, Score: 3.50)
**AI Approach**: Hybrid collaborative filtering + content-based + contextual

| Tool | Why Install |
|------|-------------|
| **SageMaker MCP Architecture** | Serve recommendation model as real-time endpoint queryable via MCP. |
| **Custom Skill**: `/recommend` | Given a customer profile, return top-N product recommendations with explanation. |

### UC-PR-03: Price Elasticity Modeling (P2, Score: 3.25)
**AI Approach**: Instrumental variable regression using coupon randomization

| Tool | Why Install |
|------|-------------|
| **Jupyter MCP Server** | Interactive IV regression analysis. |
| **AWS Pricing MCP Server** (Already installed) | Compare competitor pricing data. |
| **Custom Skill**: `/price-elasticity` | Compute price sensitivity curves per product category, simulate revenue impact of price changes. |

### UC-PR-04: New Product Launch Predictor (P2, Score: 3.05)
**AI Approach**: Analogous product matching + early signal detection

| Tool | Why Install |
|------|-------------|
| **MLflow MCP Server** | Track launch prediction model performance. |
| **Custom Skill**: `/launch-predict` | Given a new product's first 3 days of data, predict 30/60/90-day trajectory. |

### UC-PR-05: Recipe Cost Optimization (P2, Score: 2.95)
**AI Approach**: Constrained optimization for ingredient substitution

| Tool | Why Install |
|------|-------------|
| **Jupyter MCP Server** | Run constrained optimization (scipy.optimize) on 32K formula/recipe records. |
| **Custom Skill**: `/recipe-cost` | Identify ingredient substitution opportunities that maintain quality while reducing COGS. |

---

## <a id="operations"></a>5. Department 4: Operations

### UC-OP-01: Dynamic Staffing Optimizer (P2, Score: 3.55)
**AI Approach**: Integer programming for demand-driven scheduling

| Tool | Why Install |
|------|-------------|
| **Jupyter MCP Server** | Run integer programming (PuLP/OR-Tools) for shift optimization. |
| **Scheduler MCP Server** | [jolks/mcp-cron](https://github.com/jolks/mcp-cron). Schedule weekly schedule generation jobs. |
| **Custom Skill**: `/staffing` | Generate optimal weekly schedules for all 10 stores considering NYC Fair Workweek Law constraints. |

### UC-OP-02: Store Performance Anomaly Detection (P1, Score: 4.00)
**AI Approach**: Statistical process control (X-bar charts, Z-scores)

| Tool | Why Install |
|------|-------------|
| **Grafana MCP** (Already installed) | Create/update dashboards for store performance metrics. |
| **Prometheus MCP** (Already installed) | Query real-time metrics for anomaly detection. |
| **Slack MCP Server** | Send anomaly alerts to store managers and operations team. |
| **Custom Skill**: `/store-health` | Run Z-score analysis across all 10 stores, flag outliers in revenue, orders, AOV, production time. |
| **Custom Hook**: Auto-alert on anomaly | `PostToolUse` hook that triggers Slack notification when anomaly detection query returns results above threshold. |

### UC-OP-03: Production Time Predictor (P1, Score: 3.75)
**AI Approach**: Regression model on product complexity, queue depth, temporal patterns

| Tool | Why Install |
|------|-------------|
| **MLflow MCP Server** | Track production time model experiments (current avg: 204 seconds). |
| **Custom Skill**: `/production-time` | Given current queue depth and product mix, predict wait times for new orders. |

### UC-OP-04: IoT Predictive Maintenance (P2, Score: 3.15)
**AI Approach**: Survival analysis (time-to-failure)

| Tool | Why Install |
|------|-------------|
| **IoT-Edge-MCP-Server** | [poly-mcp/IoT-Edge-MCP-Server](https://github.com/poly-mcp/IoT-Edge-MCP-Server). MQTT sensors, Modbus devices, InfluxDB time-series storage, real-time alarms. Maps to Schaerer Coffee Link IoT data. |
| **ThingsPanel MCP** | [ThingsPanel/thingspanel-mcp](https://github.com/ThingsPanel/thingspanel-mcp). IoT platform integration with predictive maintenance, anomaly detection, automated reporting. |
| **Custom Skill**: `/iot-health` | Query device status for all 216 IoT devices (57% currently offline), predict maintenance needs using survival analysis. |

### UC-OP-05: Queue/Wait Time Management (P3, Score: 2.70)
**AI Approach**: Queuing theory (M/M/c model)

| Tool | Why Install |
|------|-------------|
| **Kafka/MSK MCP Server** | Real-time streaming pipeline for queue depth tracking (required infrastructure). |
| **Custom Skill**: `/queue-status` | Real-time queue simulation using M/M/c model parameters. |

### UC-OP-06: New Store Ramp Predictor (P3, Score: 2.75)
**AI Approach**: Growth curve fitting (logistic/Gompertz)

| Tool | Why Install |
|------|-------------|
| **Jupyter MCP Server** | Fit growth curves to 11 store opening trajectories. |
| **Custom Skill**: `/ramp-predict` | Given a new store location, predict order volume trajectory for first 90 days. |

---

## <a id="supply-chain"></a>6. Department 5: Supply Chain & Inventory

### UC-SC-01: Demand Forecast Accuracy Monitor (P0, Score: 4.20)
**AI Approach**: Join predictions to actuals, compute MAPE/RMSE/bias

| Tool | Why Install |
|------|-------------|
| **Nixtla TimeGPT** | `pip install nixtla`. Enhanced demand forecasting with zero-shot models. Compare against existing 2.5M predictions. |
| **MLflow MCP Server** | Track forecast model drift and accuracy metrics over time. |
| **Custom Skill**: `/forecast-accuracy` | Compute MAPE, RMSE, bias for latest forecast batch. Alert on model drift. |
| **Custom Hook**: Daily forecast accuracy check | `SessionStart` hook that auto-runs forecast accuracy report at 6 AM. |

### UC-SC-02: Waste Prediction & Reduction (P1, Score: 3.85)
**AI Approach**: Consumption forecasting + Poisson regression for spoilage

| Tool | Why Install |
|------|-------------|
| **Custom Skill**: `/waste-report` | Query 9.1M stock events and 136K quality control expiry logs to compute waste rates per store/category. |
| **Jupyter MCP Server** | Develop Poisson regression models for spoilage prediction. |

### UC-SC-03: Supplier Performance Scoring (P2, Score: 3.20)
**AI Approach**: Multi-criteria scoring model

| Tool | Why Install |
|------|-------------|
| **Custom Skill**: `/supplier-score` | Compute composite scores from 694 POs and 1,670 shipment records (on-time delivery, quality, cost). |

### UC-SC-04: Dynamic Par Level Setting (P2, Score: 3.30)
**AI Approach**: Newsvendor model with ML-predicted demand distributions

| Tool | Why Install |
|------|-------------|
| **Jupyter MCP Server** | Newsvendor optimization with demand distribution fitting. |
| **Custom Skill**: `/par-levels` | Compute optimal par levels per store/item considering service level targets and waste costs. |

### UC-SC-05: Perishable Shelf-Life Tracker (P3, Score: 2.60)
**AI Approach**: Batch-level FIFO tracking + expiry prediction

| Tool | Why Install |
|------|-------------|
| **Custom Skill**: `/shelf-life` | FIFO tracking query across inventory batches with expiry alerts. |

---

## <a id="it-infra"></a>7. Department 6: IT Infrastructure & DevOps

### UC-IT-01: Predictive Infrastructure Monitoring (P1, Score: 4.05)
**AI Approach**: Isolation Forest / Prophet time-series anomaly detection

| Tool | Why Install |
|------|-------------|
| **Prometheus MCP** (Already installed) | Query 76 targets, 155 Redis metrics for anomaly detection baselines. |
| **Grafana MCP** (Already installed) | Create predictive monitoring dashboards. |
| **CloudWatch MCP** (Already installed) | Correlate AWS-level metrics with application metrics. |
| **Custom Skill**: `/infra-predict` | Run Prophet/Isolation Forest on infrastructure metrics, predict failures 15 min in advance. |
| **Custom Hook**: Pre-incident alert | `PostToolUse` hook on Prometheus query that triggers Slack alert when anomaly score exceeds threshold. |

### UC-IT-02: Database Cost Optimizer (P1, Score: 3.70)
**AI Approach**: Usage pattern analysis + ML for RI/SP recommendations

| Tool | Why Install |
|------|-------------|
| **AWS Billing & Cost Management MCP** | `uvx awslabs.billing-cost-management-mcp-server@latest`. Natural language cost queries, savings opportunity identification. Addresses $49,645/month spend, 78% idle EC2, 1.3% RDS RI coverage. |
| **AWS FinOps MCP Server** (Community) | [ravikiranvm/aws-finops-mcp-server](https://github.com/ravikiranvm/aws-finops-mcp-server). Finds waste: stopped EC2, unattached EBS, unassociated Elastic IPs. |
| **AWS Cost Explorer MCP** (Already installed) | Historical cost data and forecasting with confidence intervals. |
| **AWS Pricing MCP** (Already installed) | Compare instance pricing for RI/SP optimization. |
| **Custom Skill**: `/cost-optimize` | Identify top cost reduction opportunities across 158 EC2 instances and 97+ database clusters. |

### UC-IT-03: Self-Healing Automation (P2, Score: 3.40)
**AI Approach**: ML-classified incident types + automated runbook execution

| Tool | Why Install |
|------|-------------|
| **Kubernetes MCP Server** (Enhanced) | [containers/kubernetes-mcp-server](https://github.com/containers/kubernetes-mcp-server) (Red Hat). Go-native, direct K8s API, Helm support. Pod cleanup for Evicted/CrashLoopBackOff states. |
| **Docker MCP Server** | Container restart/management for self-healing workflows. |
| **Custom Skill**: `/self-heal` | Given an incident type classification, execute appropriate automated runbook (restart service, scale pods, clear cache, etc.). |
| **Custom Hook**: Auto-remediation | `PostToolUse` hook on monitoring alerts that triggers self-healing scripts via AWS SSM. |

### UC-IT-04: Capacity Planning (50-Store Scale) (P2, Score: 2.85)
**AI Approach**: Regression modeling infrastructure = f(store_count, order_volume)

| Tool | Why Install |
|------|-------------|
| **Terraform MCP Server** | Plan and model infrastructure scaling via IaC. |
| **Custom Skill**: `/capacity-plan` | Project infrastructure needs for 20/30/50-store scenarios based on current per-store resource usage. |

### UC-IT-05: NL Database Query "Ask Lucky" (P2, Score: 2.80)
**AI Approach**: LLM-powered NL-to-SQL via Dify

| Tool | Why Install |
|------|-------------|
| **Dify MCP Integration** (Native, v1.6.0+) | Dify v1.6.0+ has built-in two-way MCP support. Expose Dify workflows as MCP endpoints. Your existing MCP DB Gateway covers all 62 MySQL databases. |
| **Dify MCP Server** (Community) | [YanxingLiu/dify-mcp-server](https://github.com/YanxingLiu/dify-mcp-server). Invoke Dify NL-to-SQL workflows from Claude Code. |
| **Custom Skill**: `/ask-lucky` | Natural language database query interface with read-only guardrails, PII masking, and query timeout enforcement. |

### UC-IT-06: Security Posture Intelligence (P2, Score: 3.10)
**AI Approach**: Graph-based anomaly detection on transaction patterns

| Tool | Why Install |
|------|-------------|
| **MCP Security Scanner** | `npx @anthropic/mcp-scan` or `pip install mcp-scan` ([snyk/agent-scan](https://github.com/invariantlabs-ai/mcp-scan)). Scan all MCP server connections for prompt injection, tool poisoning, toxic flows. Real-time PII detection. |
| **Security Hub MCP** | [FuzzingLabs/mcp-security-hub](https://github.com/FuzzingLabs/mcp-security-hub). Dockerized offensive security tools (Nmap, Nuclei, SQLMap) for vulnerability assessment. |
| **SlowMist MCP Security Checklist** | [slowmist/MCP-Security-Checklist](https://github.com/slowmist/MCP-Security-Checklist). Comprehensive checklist for MCP security audit. |
| **Custom Skill**: `/security-scan` | Run security posture check against 4.1M risk control rules and 1,395 blacklist entries. |

---

## <a id="executive"></a>8. Department 7: Executive & Strategy

### UC-EX-01: Executive AI Daily Briefing (P0, Score: 4.25)
**AI Approach**: Scheduled pipeline: SQL extraction -> LLM summarization -> formatted delivery

| Tool | Why Install |
|------|-------------|
| **Dify MCP Server** | Trigger existing Dify LLM summarization workflow (Claude/GPT-4) from Claude Code. |
| **Slack MCP Server** | Deliver daily briefing to executive Slack channels by 7 AM. |
| **Scheduler MCP Server** | [jolks/mcp-cron](https://github.com/jolks/mcp-cron). Schedule 6 AM SQL extraction, 6:30 AM LLM processing, 7 AM delivery. |
| **Custom Skill**: `/daily-briefing` | On-demand executive briefing: yesterday's KPIs, anomalies, alerts, and recommendations. |
| **Custom Hook**: Morning pipeline | `SessionStart` hook (or cron) to auto-trigger the briefing pipeline. |

### UC-EX-02: Site Selection Enhancement (P2, Score: 2.90)
**AI Approach**: Extend existing model (R-squared=0.94) with external data

| Tool | Why Install |
|------|-------------|
| **Apify MCP Server** | Scrape foot traffic data, competitor density, demographic data from public sources. |
| **Custom Skill**: `/site-score` | Given an address, compute site selection score using the gradient boosting model + external data enrichment. |

### UC-EX-03: Unified KPI Command Center (P2, Score: 3.45)
**AI Approach**: Unified data mart + BI layer with drill-down

| Tool | Why Install |
|------|-------------|
| **Apache Superset MCP Server** | [aptro/superset-mcp](https://github.com/aptro/superset-mcp) or wait for SIP-187 native support (PRs merging into Superset core). Create/manage business-focused dashboards (vs. current DBA-focused Grafana dashboards). |
| **Redshift MCP Server** | Query unified data mart for cross-department KPIs. |
| **Custom Skill**: `/kpi-dashboard` | Generate KPI summary across all departments with drill-down capability. |

### UC-EX-04: Competitive Intelligence Monitor (P3, Score: 2.40)
**AI Approach**: Web scraping + Yelp/Google review NLP sentiment

| Tool | Why Install |
|------|-------------|
| **Apify MCP Server** (Critical) | This is the **#1 tool** for this use case. Scrapes Google Maps (reviews, ratings), Yelp, TikTok competitor mentions, Instagram. |
| **Google Play Reviews MCP** | Monitor competitor app reviews and ratings. |
| **Custom Skill**: `/competitor-intel` | Weekly competitive intelligence report: pricing changes, new locations, sentiment comparison vs. Starbucks/Dunkin'/Blank Street. |

---

## <a id="best-practices"></a>9. Claude Code Configuration Best Practices

### 9.1 CLAUDE.md Configuration for This Project

Create `CLAUDE.md` in the project root with:

```markdown
# Luckin Coffee USA AI Transformation

## Tech Stack
- Database: MySQL (62 clusters), PostgreSQL, Redis, MongoDB, Elasticsearch
- Cloud: AWS (158 EC2, 97+ DB clusters, EKS, S3)
- ML Platform: SageMaker, MLflow, Dify
- Data Warehouse: Redshift Serverless (target)
- ETL: AWS Glue, DMS CDC
- Monitoring: Grafana, Prometheus, CloudWatch
- BI: Apache Superset (target)
- Streaming: Kafka (308 topics), Kinesis

## Key Commands
- Database queries: Use MCP DB Gateway (mcp-db-gateway)
- AWS operations: Use EKS, CloudWatch, Cost Explorer MCP servers
- Monitoring: Use Grafana/Prometheus MCP servers

## Architecture Rules
- All ML models tracked in MLflow with experiment naming: UC-{DEPT}-{NUM}
- Data flows through: Source DB -> DMS CDC -> S3 Raw -> Glue -> Redshift
- Feature Store: SageMaker Feature Store (5 online groups, 4+ offline groups)
- 12 production ML models planned (see 03-architecture-blueprint.md)

## Use Case IDs
- UC-FN-{01-05}: Finance
- UC-MK-{01-10}: Marketing
- UC-PR-{01-05}: Product
- UC-OP-{01-06}: Operations
- UC-SC-{01-05}: Supply Chain
- UC-IT-{01-06}: IT Infrastructure
- UC-EX-{01-04}: Executive

## Safety Rules
- NEVER run write queries on production MySQL without explicit approval
- Always use read-only mode for exploratory queries
- PII masking required for customer data exports
- All Stripe API calls in test mode unless explicitly authorized
```

### 9.2 Custom Skills Directory Structure

```
.claude/skills/
  tax-audit/SKILL.md           # UC-FN-01
  reconciliation/SKILL.md       # UC-FN-02
  fraud-check/SKILL.md         # UC-FN-03
  customer-lookup/SKILL.md     # UC-MK-01
  churn-report/SKILL.md        # UC-MK-02
  coupon-roi/SKILL.md          # UC-MK-03
  ab-test/SKILL.md             # UC-MK-07
  sentiment-report/SKILL.md    # UC-MK-08
  menu-matrix/SKILL.md         # UC-PR-01
  store-health/SKILL.md        # UC-OP-02
  forecast-accuracy/SKILL.md   # UC-SC-01
  waste-report/SKILL.md        # UC-SC-02
  infra-predict/SKILL.md       # UC-IT-01
  cost-optimize/SKILL.md       # UC-IT-02
  ask-lucky/SKILL.md           # UC-IT-05
  security-scan/SKILL.md       # UC-IT-06
  daily-briefing/SKILL.md      # UC-EX-01
  kpi-dashboard/SKILL.md       # UC-EX-03
  competitor-intel/SKILL.md    # UC-EX-04
```

### 9.3 Recommended Hooks

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "mcp__mcp-db-gateway__mysql_query",
        "command": "echo '[$(date)] MySQL query executed' >> /tmp/luckin-query-audit.log"
      }
    ],
    "SessionStart": [
      {
        "command": "echo 'Luckin AI Roadmap session started at $(date)' >> /tmp/luckin-sessions.log"
      }
    ],
    "Stop": [
      {
        "command": "echo 'Session ended at $(date)' >> /tmp/luckin-sessions.log"
      }
    ]
  }
}
```

### 9.4 Context Window Management

- **Keep MCP servers under 10 active** at any time. Rotate based on current use case.
- Use **subagents** for parallel research across departments.
- Batch work by department -- don't try to work on all 41 use cases in one session.
- Use `/clear` between department switches with a progress checkpoint file.

---

## <a id="install-order"></a>10. Priority Installation Order

### Tier 1: Install Immediately (Foundation for all 41 use cases)

```bash
# 1. AWS Redshift MCP (data warehouse - central to everything)
claude mcp add redshift -- uvx awslabs.redshift-mcp-server@latest

# 2. AWS Data Processing MCP (Glue/ETL - data pipeline backbone)
claude mcp add aws-dp -- uvx awslabs.aws-dataprocessing-mcp-server@latest

# 3. Stripe MCP (payment data - UC-FN-02, UC-FN-03, UC-FN-04)
claude mcp add stripe -- npx -y @stripe/mcp --tools=all --api-key=$STRIPE_SECRET_KEY

# 4. MongoDB MCP (customer data - UC-MK-01)
claude mcp add mongodb -- npx -y mongodb-mcp-server

# 5. Elasticsearch MCP (search/analytics - UC-FN-03, UC-MK-01)
# Deploy via Docker: github.com/elastic/mcp-server-elasticsearch

# 6. Jupyter MCP (ML development - all ML use cases)
claude mcp add jupyter -- uvx jupyter_mcp_server

# 7. MLflow MCP (experiment tracking - all 12 ML models)
# Built into MLflow: pip install mlflow
```

### Tier 2: Install for Department-Specific Work

```bash
# 8. Apify MCP (social/competitive data - UC-MK-08, UC-EX-04)
claude mcp add apify -- npx -y @apify/actors-mcp-server
# Requires: APIFY_TOKEN env var

# 9. Slack MCP (alerts/notifications - UC-EX-01, UC-OP-02, UC-IT-01)
# GitHub: korotovsky/slack-mcp-server

# 10. Apache Superset MCP (BI dashboards - UC-EX-03)
# pip install aptro-superset-mcp (GitHub: aptro/superset-mcp)

# 11. Kafka/MSK MCP (streaming - UC-MK-04, UC-OP-05)
claude mcp add msk -- uvx awslabs.aws-msk-mcp-server@latest

# 12. DoorDash MCP (delivery data - UC-FN-04)
# GitHub: amannm/doordash-mcp

# 13. IoT MCP (Schaerer machines - UC-OP-04)
# GitHub: poly-mcp/IoT-Edge-MCP-Server
```

### Tier 3: Install for Infrastructure & Security

```bash
# 14. Terraform MCP (IaC - UC-IT-04)
claude mcp add terraform -- npx @hashicorp/terraform-mcp-server

# 15. AWS FinOps MCP (cost optimization - UC-IT-02)
# GitHub: ravikiranvm/aws-finops-mcp-server

# 16. AWS Billing MCP (cost management - UC-IT-02)
claude mcp add billing -- uvx awslabs.billing-cost-management-mcp-server@latest

# 17. MCP Security Scanner (security audit - UC-IT-06)
# pip install mcp-scan

# 18. Kubernetes MCP (enhanced K8s - UC-IT-03)
claude mcp add k8s -- npx mcp-server-kubernetes

# 19. Docker MCP (container management - UC-IT-03)
# pip install mcp-server-docker

# 20. GitHub MCP (project management - all use cases)
# go install github.com/github/github-mcp-server@latest
```

### Tier 4: Install for Advanced Use Cases

```bash
# 21. Dify MCP (LLM orchestration - UC-IT-05, UC-EX-01)
# Upgrade Dify to v1.6.0+ for native MCP, or use:
# GitHub: YanxingLiu/dify-mcp-server

# 22. DuckDB + Visualization (ad-hoc analysis)
claude mcp add duckdb -- uvx mcp-server-motherduck --db-path :memory: --read-write
# pip install mcp-visualization-duckdb

# 23. Pandas MCP (data science)
# pip install mcp-pandas

# 24. Scheduler/Cron MCP (automation - UC-EX-01, UC-OP-01)
# GitHub: jolks/mcp-cron

# 25. Nixtla TimeGPT (time series forecasting - UC-SC-01, UC-FN-05)
# pip install nixtla

# 26. Accounting MCP (tax compliance - UC-FN-01)
# GitHub: RealDealCPA-VR/MCP-Accounting
```

---

## Key Resource Links

| Resource | URL |
|----------|-----|
| Awesome MCP Servers (Curated) | [github.com/punkpeye/awesome-mcp-servers](https://github.com/punkpeye/awesome-mcp-servers) |
| Awesome Claude Code | [github.com/hesreallyhim/awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) |
| Official AWS MCP Servers | [github.com/awslabs/mcp](https://github.com/awslabs/mcp) |
| Official MCP Servers Repo | [github.com/modelcontextprotocol/servers](https://github.com/modelcontextprotocol/servers) |
| MCP Server Directory (17K+) | [mcp.so](https://mcp.so) |
| Claude Code Skills Docs | [code.claude.com/docs/en/skills](https://code.claude.com/docs/en/skills) |
| Claude Code Hooks Docs | [code.claude.com/docs/en/hooks-guide](https://code.claude.com/docs/en/hooks-guide) |
| Claude Code MCP Config | [code.claude.com/docs/en/mcp](https://code.claude.com/docs/en/mcp) |
| Claude Code Best Practices | [code.claude.com/docs/en/best-practices](https://code.claude.com/docs/en/best-practices) |
| MCP Security Checklist | [github.com/slowmist/MCP-Security-Checklist](https://github.com/slowmist/MCP-Security-Checklist) |

# CloudWatch Cost Optimization Audit Report
## Luckin Coffee North America - AWS Account
**Audit Date:** 2026-02-12
**Report Period:** November 2025 - February 2026

---

## Executive Summary

| Metric | Value |
|--------|-------|
| Total Active Metric Dimensions | 941,865 |
| Total Namespaces | 46 |
| January 2026 CloudWatch Cost | $3,666.78 |
| Annualized Cost | $44,001.36 |
| Estimated Savings Opportunity | $1,042-1,489/month ($12,504-17,868/year) |

### Cost Breakdown (January 2026)

| Usage Type | Description | Cost | % of Total |
|------------|-------------|------|-----------|
| CW:MetricMonitorUsage | Custom Metrics Storage | $1,872.68 | 51.1% |
| CW:Requests | API Requests (Get/PutMetricData) | $1,507.72 | 41.1% |
| CW:GMD-Metrics | GetMetricData Metrics Scanned | $231.91 | 6.3% |
| InternetMonitor | Monitored Resources + City Networks | $43.97 | 1.2% |
| Other | Dashboards, Alarms, Logs, Storage | $10.50 | 0.3% |
| **TOTAL** | | **$3,666.78** | **100%** |

### Critical Alert: GetMetricData Cost Spike

> **CW:GMD-Metrics jumped from $3.60 (Dec) to $231.91 (Jan) -- a 64x increase!**
> This suggests a new monitoring tool, Grafana dashboard, or automated query is scanning far more metric data points than before. Immediate investigation recommended.

---

## Top 10 Costliest Metric Groups

| Rank | Namespace | Metric Count | % of Total | System Category | Issue |
|------|-----------|-------------|-----------|----------------|-------|
| 1 | AWS/EMRServerless | 895,562 | 95.2% | Data Processing | **Per-worker metrics from historical jobs -- MASSIVE cardinality** |
| 2 | AWS/ElastiCache | 17,359 | 1.8% | Redis Cache (156 clusters) | High cluster count, many command-specific metrics |
| 3 | AWS/Kafka | 10,891 | 1.2% | MSK (3 clusters) | Per-topic/consumer-group lag metrics |
| 4 | AWS/EBS | 4,985 | 0.5% | Block Storage (~332 volumes) | Standard per-volume metrics |
| 5 | AWS/EC2 | 4,256 | 0.5% | Compute (233 instances) | Standard per-instance metrics |
| 6 | AWS/ES | 2,011 | 0.2% | OpenSearch (4 domains) | Comprehensive per-node metrics |
| 7 | AWS/RDS | 1,769 | 0.2% | MySQL/PostgreSQL (74 instances) | Standard DB metrics |
| 8 | AWS/DocDB | 1,097 | 0.1% | DocumentDB (3 clusters) | Standard DocDB metrics |
| 9 | AWS/NetworkELB | 953 | 0.1% | Network Load Balancers | Standard NLB metrics |
| 10 | AWS/Usage | 812 | 0.1% | AWS Usage Tracking | API call counts per service |

---

## Namespace Inventory (All 46 Namespaces)

| Namespace | Metrics | Category | Type |
|-----------|---------|----------|------|
| AWS/EMRServerless | 895,562 **<<< CRITICAL** | Data Processing (EMR Serverless) | AWS Native |
| AWS/ElastiCache | 17,359 *HIGH* | Redis Cache Clusters | AWS Native |
| AWS/Kafka | 10,891 *HIGH* | Kafka/MSK Messaging | AWS Native |
| AWS/EBS | 4,985 | Block Storage (EBS) | AWS Native |
| AWS/EC2 | 4,256 | EC2 Compute Instances | AWS Native |
| AWS/ES | 2,011 | OpenSearch/Elasticsearch | AWS Native |
| AWS/RDS | 1,769 | MySQL/PostgreSQL RDS | AWS Native |
| AWS/DocDB | 1,097 | DocumentDB (MongoDB-compatible) | AWS Native |
| AWS/NetworkELB | 953 | Network Load Balancers | AWS Native |
| AWS/Usage | 812 | AWS Usage Tracking | AWS Native |
| AWS/TrustedAdvisor | 489 | Trusted Advisor | AWS Native |
| AWS/Logs | 194 | CloudWatch Logs | AWS Native |
| AWS/TransitGateway | 144 | Transit Gateway Networking | AWS Native |
| AWS/InternetMonitor | 130 | Internet Monitor | AWS Native |
| AWS/CloudFront | 118 | CDN (CloudFront) | AWS Native |
| AWS/EKS | 116 | Kubernetes (EKS) | AWS Native |
| AWS/WorkMail | 104 | WorkMail | AWS Native |
| AWS/Lambda | 94 | Serverless Functions | AWS Native |
| AWS/Route53 | 76 | DNS (Route 53) | AWS Native |
| AWS/PrivateLinkEndpoints | 75 | PrivateLink VPC Endpoints | AWS Native |
| AWS/SQS | 68 | Message Queues (SQS) | AWS Native |
| AWS/S3 | 68 | Object Storage (S3) | AWS Native |
| AWS/AutoScaling | 63 | Auto Scaling Groups | AWS Native |
| AWS/NATGateway | 62 | NAT Gateways | AWS Native |
| AWS/EFS | 62 | Elastic File System | AWS Native |
| AWS/ApplicationELB | 58 | Application Load Balancers | AWS Native |
| AWS/ECR | 49 | Container Registry (ECR) | AWS Native |
| AWS/ElasticMapReduce | 40 | EMR (Hadoop) | AWS Native |
| AWS/Events | 34 | EventBridge | AWS Native |
| AWS/Backup | 20 | AWS Backup | AWS Native |
| AWS/SNS | 14 | Notifications (SNS) | AWS Native |
| AWS/WAFV2 | 13 | Web Application Firewall | AWS Native |
| AWS/SES | 12 | Email (SES) | AWS Native |
| AWS/ApiGateway | 11 | API Gateway | AWS Native |
| AWS/Firehose | 9 | Kinesis Firehose | AWS Native |
| AWS/GuardDuty | 8 | Security (GuardDuty) | AWS Native |
| AWSLicenseManager/licenseUsage | 7 | License Manager | Custom |
| AWS/HealthLake | 6 | HealthLake | AWS Native |
| AWS/Polly | 5 | Text-to-Speech (Polly) | AWS Native |
| AWS/KMS | 5 | Key Management (KMS) | AWS Native |
| AWS/CertificateManager | 5 | Certificate Manager | AWS Native |
| AWS/Bedrock/DataAutomation | 5 | Bedrock Data Automation | AWS Native |
| AWS/SSM-RunCommand | 3 | Systems Manager | AWS Native |
| AWS/X-Ray | 1 | X-Ray Tracing | AWS Native |
| AWS/SecretsManager | 1 | Secrets Manager | AWS Native |
| AWS/IPAM | 1 | IP Address Management | AWS Native |

---

## Detailed Analysis by System Category

### 1. EMR Serverless (895,562 metrics -- 95.2% of all metrics)

**This is the single biggest cost optimization opportunity.**

- **8 per-worker metrics** (CPU, Memory, Storage allocated/used, StorageRead/WriteBytes) each have **~112,000 unique dimension combinations**
- These dimensions represent individual workers from historical EMR Serverless job runs
- EMR Serverless automatically publishes per-worker metrics that persist in CloudWatch even after jobs complete
- Application-level aggregate metrics (CPUAllocated, RunningWorkerCount, etc.) only account for ~36 metrics

**Recommendation:** Investigate EMR Serverless applications and completed job runs. Consider:
1. Cleaning up old EMR Serverless applications to remove retained worker metrics
2. Configuring CloudWatch metric stream filters to exclude per-worker dimensions
3. Using application-level aggregate metrics instead of per-worker tracking

### 2. ElastiCache / Redis (17,359 metrics)

- **156 Redis clusters** (129 x cache.t4g.micro, 15 x cache.t4g.small, 6 x cache.t3.micro, 4 x cache.t4g.medium, 2 x cache.m6g.large)
- 42 standard metrics per cluster + additional command-type metrics
- Command-specific metrics (HashBasedCmds, SetBasedCmds, ListBasedCmds, etc.) add cardinality
- All are AWS-published standard metrics -- no additional custom metric cost

### 3. Kafka/MSK (10,891 metrics)

- **3 MSK clusters:** iprod-kafka-architecture-cluster, iprod-kafka-base-cluster, iprod-kafka-business-cluster
- **OffsetLag** alone has 1,920 dimension combinations (per-topic, per-consumer-group, per-partition)
- EstimatedTimeLag: 1,918 dimensions
- Per-broker metrics: ~80 types x 9 brokers (3 per cluster)
- **Review:** Clean up stale consumer groups to reduce lag metric cardinality

### 4. EC2 Compute (4,256 metrics)

- **233 running instances**, all in us-east-1
- 18 standard metric types per instance
- **8 instances have detailed monitoring enabled** (1-minute resolution) -- mostly unnamed, likely EKS nodes
- 225 instances use basic monitoring (5-minute resolution)
- Detailed monitoring adds ~$2.10/instance/month = $16.80/month for 8 instances

### 5. OpenSearch/Elasticsearch (2,011 metrics)

- **4 domains:** luckycommon, luckylfe-log, luckyur-log, luckyus-opensearch-dify
- 52+ per-node metrics + 100+ cluster-level metrics
- Comprehensive metric coverage including KNN, ML, alerting, dashboards
- All AWS-published standard metrics

### 6. RDS MySQL/PostgreSQL (1,769 metrics)

- **74 DB instances:** 62 MySQL, 3 PostgreSQL (+ 9 DocDB counted separately)
- Instance classes: 41 x db.t4g.micro, 17 x db.t4g.medium, 6 x db.t3.medium
- Standard RDS metrics + MySQL-specific (BinLog, LVM) + PostgreSQL-specific (Checkpoint, TransactionLogs)
- Performance Insights enabled on 6 instances (separate cost)

### 7. DocumentDB (1,097 metrics)

- **3 clusters:** docdb-devops, docdb-gia, docdb-iot (9 instances total)
- 54+ standard metric types per instance/cluster
- Standard AWS-published metrics

---

## CloudWatch Alarms (28 total)

| State | Count |
|-------|-------|
| OK | 25 |
| INSUFFICIENT_DATA | 3 |
| ALARM | 0 |

### Alarm Breakdown

| Alarm Group | Namespace | Count | State | Notes |
|-------------|-----------|-------|-------|-------|
| Kafka partition/disk/offline | AWS/Kafka | 9 | OK | Critical MSK monitoring - keep |
| CloudFront domain 5xx alerts | AWS/CloudFront | 7 | 5 OK, 2 INSUF | Review 2 in INSUFFICIENT_DATA |
| API Gateway img-transform | AWS/ApiGateway | 3 | OK | Image transform pipeline |
| Lambda img-transform | AWS/Lambda | 3 | OK | Image transform pipeline |
| CDN img-transform | AWS/CloudFront | 3 | OK | Image transform pipeline |
| EMR Classic | AWS/ElasticMapReduce | 2 | INSUFFICIENT_DATA | **Review - clusters may be decommissioned** |
| ES disk space | Composite | 1 | OK | OpenSearch monitoring |

---

## EC2 Detailed Monitoring (8 instances)

| Instance ID | Name | Type | Cost Impact |
|-------------|------|------|-------------|
| i-0d9b1e751b082509e | unnamed | m6a.xlarge | $2.10/mo |
| i-0b7168740da06034a | unnamed | m6a.large | $2.10/mo |
| i-031550c05c4eae3e9 | unnamed | m6a.large | $2.10/mo |
| i-0f5b8098e2098d6ec | unnamed | r6i.2xlarge | $2.10/mo |
| i-0d812309d4071771c | unnamed | r6i.2xlarge | $2.10/mo |
| i-0047137d18fc77c35 | velodb-agent | c5.large | $2.10/mo |
| i-0a1e3602ff0d0cccf | unnamed | m6a.xlarge | $2.10/mo |
| i-0418d2213e6688dc0 | unnamed | m6a.large | $2.10/mo |

**Total detailed monitoring cost: ~$16.80/month**

---

## Cost Trend (3-Month)

| Usage Type | Nov 2025 | Dec 2025 | Jan 2026 | Trend |
|------------|----------|----------|----------|-------|
| MetricMonitorUsage | $1,920.66 | $1,891.83 | $1,872.68 | Slight decrease |
| Requests | $982.31 | $1,503.68 | $1,507.72 | Stable (after Nov jump) |
| GMD-Metrics | $3.46 | $3.60 | **$231.91** | **64x SPIKE** |
| InternetMonitor | $42.80 | $43.16 | $43.97 | Stable |
| Other | $10.88 | $8.51 | $10.50 | Stable |
| **TOTAL** | **$2,960.11** | **$3,450.78** | **$3,666.78** | **+6.3% MoM** |

---

## Recommendations & Action Plan

### Quick Wins (< 1 week, ~$237-274/month savings)

| # | Action | Savings | Effort |
|---|--------|---------|--------|
| 1 | **Investigate GMD-Metrics 64x spike** - Identify source of excessive GetMetricData queries (new Grafana dashboards, monitoring tools, automated scripts). Reduce query frequency or scope. | $200-230/mo | 1-3 days |
| 2 | **Review Internet Monitor** - Evaluate if $44/mo Internet Monitor service is actively used or can be replaced by CloudFront + Route53 native monitoring | $37-44/mo | 1 day |
| 3 | **Clean up EMR Classic alarms** - 2 alarms in INSUFFICIENT_DATA, likely from decommissioned clusters | ~$0.20/mo | 1 hour |
| 4 | **Review CloudFront alarms** - 2 alarms in INSUFFICIENT_DATA for potentially inactive distributions | ~$0.20/mo | 1 hour |

### Medium-term (1-2 weeks, ~$805-1,215/month additional)

| # | Action | Savings | Effort |
|---|--------|---------|--------|
| 5 | **EMR Serverless metric cleanup** - Address 895K+ per-worker metrics by cleaning up old applications or configuring metric suppression | $800-1,200/mo | 1-2 weeks |
| 6 | **Kafka consumer group audit** - Clean up stale consumer groups generating 1,920+ OffsetLag dimensions | $5-15/mo | 1 week |
| 7 | **EC2 detailed monitoring review** - Disable detailed monitoring on 8 instances if 1-minute resolution isn't needed | $16.80/mo | 1 hour |

### Longer-term Optimization

| # | Action | Savings | Effort |
|---|--------|---------|--------|
| 8 | **ElastiCache command metrics review** - Evaluate if all per-command-type metrics across 156 clusters are monitored | $0-5/mo | Ongoing |
| 9 | **RDS Performance Insights audit** - Verify PI is enabled only where needed | $0-10/mo | 1 day |
| 10 | **WorkMail ActionDenied investigation** - 79 denied action dimensions may indicate misconfiguration | $0 | 1 day |

### Total Savings Projection

| Timeframe | Monthly Savings | Annual Savings |
|-----------|----------------|----------------|
| Quick Wins | $237-274 | $2,844-3,288 |
| + Medium-term | $1,042-1,489 | $12,504-17,868 |
| Current Spend | $3,667/month | $44,004/year |
| Optimized Spend | ~$2,178-2,625/month | ~$26,136-31,500/year |
| **Savings %** | **28-41%** | **28-41%** |

---

## Infrastructure Summary

| Category | Resource | Count | Notes |
|----------|----------|-------|-------|
| Compute | EC2 Instances | 233 | All running |
| Compute | Lambda Functions | 13 | Image transform + others |
| Database | RDS MySQL | 62 instances | Primarily t4g.micro/medium |
| Database | RDS PostgreSQL | 3 instances | |
| Database | DocumentDB | 3 clusters / 9 instances | devops, gia, iot |
| Cache | ElastiCache Redis | 156 clusters | Mostly t4g.micro |
| Messaging | MSK Kafka | 3 clusters / 9 brokers | architecture, base, business |
| Search | OpenSearch | 4 domains | luckycommon, logs, dify |
| Storage | EBS Volumes | ~332 | |
| Storage | S3 Buckets | 34 | |
| CDN | CloudFront | 11 distributions | |
| Data Processing | EMR Serverless | 2+ applications | Source of 895K metrics |
| Networking | NLB | 50+ | |
| Networking | ALB | 4 | |
| Networking | NAT Gateway | 4 | |
| Networking | Transit Gateway | 9+ attachments | |

---

*Report generated on 2026-02-12 15:38 UTC by CloudWatch Cost Optimization Audit Tool*
*Luckin Coffee North America - DevOps DBA Team*

# Luckin Coffee North America - Kubernetes Architecture Data Collection Toolkit

## ⚠️ Important Notice

**This toolkit does NOT have direct access to your AWS account or Kubernetes clusters.** You must run these scripts on a machine that has:

1. **kubectl** configured with access to your EKS clusters
2. **AWS CLI** configured with appropriate credentials
3. **Network access** to your production clusters

## Overview

This comprehensive toolkit automates the collection, analysis, and documentation of your Kubernetes infrastructure to generate accurate architecture diagrams and documentation.

## Quick Start

```bash
# 1. Clone or download this toolkit
cd luckin-k8s-architecture/scripts

# 2. Make scripts executable
chmod +x *.sh *.py

# 3. Run the master script (collects everything)
./run_all.sh

# 4. Push results to GitHub
./06_push_to_github.sh
```

## What This Toolkit Does

This toolkit will collect and analyze:

### 1. Cluster & Node Data
- Node counts, types, and capacity (CPU/memory)
- Cluster versions and configurations
- Storage classes and persistent volumes

### 2. Namespace & Workload Data
- All deployments, statefulsets, daemonsets
- Pod counts and resource allocations
- Services and endpoints
- Ingresses and routing rules
- HPAs and scaling configurations

### 3. **Service Dependencies (CRITICAL)**
- Environment variable analysis to find service connections
- ConfigMap parsing for service URLs
- Service mesh discovery (Istio/Linkerd if present)
- Network policies defining traffic flows
- Database connection patterns

### 4. External AWS Resources
- RDS database instances
- ElastiCache clusters (Redis/Memcached)
- S3 buckets
- Load Balancers (ALB/NLB)
- SQS queues, SNS topics
- DynamoDB tables
- Lambda functions
- API Gateway APIs

### 5. Data Analysis & Summary
- Structured JSON summary of entire architecture
- Service dependency graph
- Resource totals and capacity planning data
- Ingress routing map

## Prerequisites

### Required Tools

```bash
# Check if you have all required tools
kubectl version --client
aws --version
jq --version
python3 --version
git --version
```

Install missing tools:

**macOS:**
```bash
brew install kubectl awscli jq python3 git
```

**Ubuntu/Debian:**
```bash
apt-get update
apt-get install -y kubectl awscli jq python3 git
```

**Amazon Linux:**
```bash
yum install -y jq python3 git
# kubectl and awscli are usually pre-installed on EC2
```

### AWS & Kubernetes Access

1. **Configure AWS CLI:**
```bash
aws configure
# Enter your AWS Access Key ID and Secret Access Key
```

2. **Configure kubectl for EKS:**
```bash
aws eks update-kubeconfig --name prod-native-eks-us --region us-east-1
aws eks update-kubeconfig --name prod-worker01-eks-us --region us-east-1

# Verify access
kubectl cluster-info
kubectl get nodes
```

3. **Verify Permissions:**

Required AWS IAM permissions:
- `eks:DescribeCluster`
- `rds:DescribeDBInstances`
- `elasticache:DescribeCacheClusters`
- `s3:ListBuckets`
- `elasticloadbalancing:DescribeLoadBalancers`
- `sts:GetCallerIdentity`

Required Kubernetes RBAC:
- Read access to all namespaces
- `get`, `list` permissions for:
  - pods, deployments, services, ingresses
  - configmaps, secrets (metadata only)
  - nodes, namespaces

## Repository Structure

```
luckin-k8s-architecture/
├── scripts/
│   ├── 01_collect_cluster_data.sh         # Collects cluster & node info
│   ├── 02_collect_namespace_data.sh       # Collects namespace workloads
│   ├── 03_collect_service_dependencies.sh # Discovers service relationships
│   ├── 04_collect_external_resources.sh   # Collects AWS resources
│   ├── 05_analyze_data.py                 # Analyzes and structures data
│   ├── 06_push_to_github.sh               # Pushes to GitHub
│   └── run_all.sh                         # Master script (runs all)
├── data/
│   ├── raw/                                # Raw collected data
│   │   ├── clusters/                       # Per-cluster data
│   │   ├── namespaces/                     # Per-namespace data
│   │   ├── dependencies/                   # Service dependency data
│   │   └── external/                       # AWS resources data
│   └── processed/
│       └── architecture_summary.json       # Final analyzed summary
├── logs/                                   # Execution logs
├── docs/                                   # Documentation
└── README.md                               # This file
```

## Detailed Usage

### Option 1: Run Everything (Recommended)

```bash
cd scripts
./run_all.sh
```

This runs all collection and analysis scripts in sequence.

**Options:**
```bash
./run_all.sh --skip-clusters      # Skip cluster data collection
./run_all.sh --skip-external      # Skip AWS resources collection
./run_all.sh --analyze-only       # Only run analysis (requires data)
./run_all.sh --help               # Show help
```

### Option 2: Run Scripts Individually

```bash
cd scripts

# Step 1: Collect cluster data
./01_collect_cluster_data.sh

# Step 2: Collect namespace data
./02_collect_namespace_data.sh

# Step 3: Discover service dependencies (CRITICAL)
./03_collect_service_dependencies.sh

# Step 4: Collect external AWS resources
./04_collect_external_resources.sh

# Step 5: Analyze and structure data
./05_analyze_data.py

# Step 6: Push to GitHub
./06_push_to_github.sh
```

### Push to GitHub

```bash
cd scripts

# Preview what will be pushed (dry run)
./06_push_to_github.sh --dry-run

# Actually push to GitHub
./06_push_to_github.sh
```

**Note:** Make sure the repository exists on GitHub first:
1. Go to https://github.com/xiangyuzeng
2. Create new repository: `luckin-k8s-architecture`
3. Make it private if it contains sensitive info
4. Then run the push script

## Output Files

After running the scripts, you'll have:

### Key Output Files

1. **architecture_summary.json** (`data/processed/`)
   - Complete structured summary of your infrastructure
   - Used for generating diagrams and documentation
   - Schema includes: clusters, namespaces, services, dependencies, external resources

2. **Raw Data** (`data/raw/`)
   - All original collected data in JSON/text format
   - Organized by cluster, namespace, and resource type
   - Useful for debugging and detailed analysis

3. **Logs** (`logs/`)
   - Execution logs for each script
   - Timestamped for tracking multiple runs
   - Useful for troubleshooting failures

### Example architecture_summary.json Structure

```json
{
  "metadata": {
    "generated_at": "2026-01-20T12:00:00",
    "clusters": ["prod-native-eks-us", "prod-worker01-eks-us"]
  },
  "clusters": {
    "prod-native-eks-us": {
      "node_count": 10,
      "total_cpu": 160,
      "total_memory_gb": 640,
      "nodes": [...]
    }
  },
  "namespaces": {
    "rd-frontend": {
      "deployments": [...],
      "services": [...],
      "ingresses": [...]
    }
  },
  "service_dependencies": [
    {
      "source": "rd-frontend",
      "target": "rd-sales.rd-sales",
      "type": "http"
    }
  ],
  "ingress_routes": [...],
  "external_resources": {
    "databases": [...],
    "caches": [...],
    "load_balancers": [...]
  }
}
```

## Security & Privacy

### What Gets Collected

✅ **Safe to collect:**
- Resource metadata (names, counts, types)
- Capacity and resource allocations
- Service DNS names and ports
- Configuration structure
- Labels and annotations

❌ **NOT collected:**
- Actual secret values
- Passwords or API keys
- Certificate private keys
- Application code
- User data
- Environment variable values (unless they're service references)

### Before Pushing to GitHub

The push script (`06_push_to_github.sh`) automatically:
1. Creates a `.gitignore` to exclude sensitive files
2. Scans for common sensitive data patterns
3. Prompts for confirmation if issues found
4. Allows dry-run mode to preview changes

**Manual Review:**
```bash
# Check for sensitive data
grep -r "password" data/ | head -20
grep -r "secret" data/ | head -20
grep -r "api_key" data/ | head -20

# Review what will be pushed
cd scripts
./06_push_to_github.sh --dry-run
```

## Troubleshooting

### Common Issues

**1. "kubectl: command not found"**
```bash
# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

**2. "The connection to the server was refused"**
```bash
# Reconfigure kubectl
aws eks update-kubeconfig --name prod-native-eks-us --region us-east-1

# Verify access
kubectl cluster-info
```

**3. "error: You must be logged in to the server (Unauthorized)"**
```bash
# Check AWS credentials
aws sts get-caller-identity

# Check kubectl context
kubectl config current-context
kubectl config view

# Update kubeconfig
aws eks update-kubeconfig --name prod-native-eks-us --region us-east-1
```

**4. "AWS CLI not found" or "aws: command not found"**
```bash
# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure
aws configure
```

**5. "Permission denied" errors**
```bash
# Make scripts executable
cd scripts
chmod +x *.sh *.py
```

**6. "Failed to retrieve RDS instances" (permission issues)**

This is OK! The script will continue. You may lack IAM permissions for certain AWS resources. The script will collect what it can access and skip the rest.

**7. Python script fails**
```bash
# Check Python version (needs 3.6+)
python3 --version

# If needed, install Python 3
sudo yum install python3  # Amazon Linux
sudo apt-get install python3  # Ubuntu
```

### Getting Help

Check the logs:
```bash
# View latest run_all log
ls -lt logs/run_all_*.log | head -1

# View specific script log
cat logs/01_collect_cluster_data_20260120_120000.log
```

## Next Steps After Collection

1. **Review the Summary**
   ```bash
   # View architecture summary
   cat data/processed/architecture_summary.json | jq .

   # Count resources
   cat data/processed/architecture_summary.json | jq '.resource_totals'
   ```

2. **Update Visualizations**
   - Use `architecture_summary.json` as data source
   - Update React components with real service names
   - Fix service dependency arrows based on actual dependencies
   - Update external resource connections

3. **Document Findings**
   - Create `docs/architecture_findings.md`
   - Document discrepancies from mock data
   - Note any surprises or unexpected configurations
   - List services that need better monitoring/documentation

4. **Share with Team**
   - Push to GitHub
   - Create visualization dashboards
   - Schedule regular re-runs to keep data current

## Keeping Data Current

Run the collection periodically to keep architecture documentation up-to-date:

```bash
# Weekly update (cron job example)
0 2 * * 1 cd /path/to/luckin-k8s-architecture/scripts && ./run_all.sh && ./06_push_to_github.sh

# Or use this one-liner for manual updates
cd luckin-k8s-architecture/scripts && ./run_all.sh && ./06_push_to_github.sh
```

## License

Internal use only - Luckin Coffee North America

## Contact

For questions or issues with this toolkit, contact:
- DevOps Team
- GitHub: @xiangyuzeng

# Luckin Coffee K8s Architecture - Execution Guide

## Step-by-Step Instructions for Running the Toolkit

This guide walks you through the exact steps to collect your Kubernetes architecture data and push it to GitHub.

## Prerequisites Checklist

Before starting, ensure you have:

- [ ] Access to a machine with kubectl configured (bastion host, local machine, or Cloud Shell)
- [ ] AWS CLI installed and configured with valid credentials
- [ ] kubectl configured with access to both EKS clusters
- [ ] jq, python3, and git installed
- [ ] Network access to your production clusters
- [ ] GitHub repository created at: https://github.com/xiangyuzeng/luckin-k8s-architecture

## Phase 1: Setup (5 minutes)

### 1.1 Clone or Download the Toolkit

```bash
# Option A: If you have this as a zip file
unzip luckin-k8s-architecture.zip
cd luckin-k8s-architecture

# Option B: If you're copying files
mkdir -p luckin-k8s-architecture
cd luckin-k8s-architecture
# Copy all files here

# Verify structure
ls -la
# You should see: scripts/, data/, docs/, README.md
```

### 1.2 Verify Tools

```bash
# Check all required tools
kubectl version --client
aws --version
jq --version
python3 --version
git --version

# If any are missing, install them first
```

### 1.3 Verify AWS & Kubernetes Access

```bash
# Check AWS identity
aws sts get-caller-identity
# Should show your AWS account ID and user/role

# Check kubectl access
kubectl cluster-info
kubectl get nodes
# Should show your cluster nodes

# Update kubeconfig for both clusters (if needed)
aws eks update-kubeconfig --name prod-native-eks-us --region us-east-1
aws eks update-kubeconfig --name prod-worker01-eks-us --region us-east-1

# List all contexts
kubectl config get-contexts
```

## Phase 2: Data Collection (15-30 minutes)

### 2.1 Run the Master Script

This is the easiest approach - one script runs everything:

```bash
cd scripts

# Run all collection and analysis
./run_all.sh
```

**What this does:**
1. Collects cluster and node data from both EKS clusters
2. Collects namespace data (deployments, services, pods, etc.)
3. Discovers service dependencies (the critical part!)
4. Collects external AWS resources (RDS, ElastiCache, etc.)
5. Analyzes all data and generates architecture_summary.json

**Expected duration:** 15-30 minutes depending on cluster size

**Output:** You'll see colored progress messages:
- 🟢 **[INFO]** - General information
- 🔵 **[DETAIL]** - Detailed progress
- 🟡 **[WARN]** - Warnings (usually OK to continue)
- 🔴 **[ERROR]** - Errors (may need attention)

### 2.2 Monitor Progress

```bash
# In another terminal, watch the logs
cd luckin-k8s-architecture
tail -f logs/run_all_*.log
```

### 2.3 Handle Common Issues

**Issue: Script stops with permission error**
```bash
# Make scripts executable
chmod +x scripts/*.sh scripts/*.py

# Re-run
./run_all.sh
```

**Issue: "Cannot connect to cluster"**
```bash
# Reconfigure kubectl
aws eks update-kubeconfig --name prod-native-eks-us --region us-east-1
kubectl get nodes  # Verify access

# Re-run
./run_all.sh
```

**Issue: AWS permissions errors**

This is OK! The script will skip resources you can't access and continue. You'll see warnings but it won't stop.

**Issue: Takes too long**

The most time-consuming parts are:
- Collecting pod environment variables (reads from each pod)
- AWS resource discovery (multiple API calls)

This is normal. Let it complete.

## Phase 3: Verify Data Collection (5 minutes)

### 3.1 Check Generated Files

```bash
cd luckin-k8s-architecture

# Check that architecture summary was created
ls -lh data/processed/architecture_summary.json

# View summary statistics
cat data/processed/architecture_summary.json | jq '.resource_totals'

# Expected output:
# {
#   "nodes": 20,
#   "vcpus": 320,
#   "memory_gb": 1280,
#   "pods": 150,
#   "deployments": 45,
#   "services": 60,
#   ...
# }
```

### 3.2 Verify Critical Data

```bash
# Check that we found service dependencies
cat data/processed/architecture_summary.json | jq '.service_dependencies | length'
# Should be > 0

# Check that we found ingress routes
cat data/processed/architecture_summary.json | jq '.ingress_routes | length'
# Should be > 0

# Check namespaces
cat data/processed/architecture_summary.json | jq '.namespaces | keys'
# Should list your namespaces

# Check external resources
cat data/processed/architecture_summary.json | jq '.external_resources'
# Should show RDS, ElastiCache, etc.
```

### 3.3 Review for Sensitive Data

```bash
# Check for passwords/secrets before pushing
grep -r "password" data/ | head -10
grep -r "secret" data/ | head -10

# If you see actual passwords/secrets (not just the word "password"):
# 1. Find the file
# 2. Manually remove or sanitize the sensitive values
# 3. Add the pattern to .gitignore
```

## Phase 4: Push to GitHub (5 minutes)

### 4.1 Create GitHub Repository

1. Go to: https://github.com/xiangyuzeng
2. Click "New repository"
3. Name: `luckin-k8s-architecture`
4. Visibility: **Private** (recommended) or Public
5. Do NOT initialize with README (we already have one)
6. Click "Create repository"

### 4.2 Preview What Will Be Pushed

```bash
cd luckin-k8s-architecture/scripts

# Dry run to see what would be pushed
./06_push_to_github.sh --dry-run

# Review the file list
# Make sure no sensitive files are included
```

### 4.3 Push to GitHub

```bash
# Actually push
./06_push_to_github.sh

# You may be prompted for GitHub credentials
# Username: xiangyuzeng
# Password: [Use a Personal Access Token, not your actual password]
```

**Creating a GitHub Personal Access Token:**

1. Go to: https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. Name: "luckin-k8s-architecture"
4. Scopes: Select **repo** (full control of private repositories)
5. Click "Generate token"
6. **COPY THE TOKEN** (you won't see it again!)
7. Use this token as your password when prompted

### 4.4 Verify Push

```bash
# Check GitHub
# Go to: https://github.com/xiangyuzeng/luckin-k8s-architecture
# You should see:
#   - README.md
#   - scripts/
#   - data/
#   - docs/
```

## Phase 5: Next Steps

### 5.1 Review Architecture Summary

```bash
# Open and review the summary
cat data/processed/architecture_summary.json | jq . | less

# Or copy to your local machine for easier viewing
scp user@bastion:/path/to/luckin-k8s-architecture/data/processed/architecture_summary.json .
```

### 5.2 Document Findings

Create `docs/architecture_findings.md` with:
- Key architectural discoveries
- Differences from expected/mock architecture
- Services that need better documentation
- Potential issues or concerns

### 5.3 Update Visualizations

Use the collected data to update your architecture diagrams:

1. **Service Dependency Diagram**
   - Source: `architecture_summary.json > service_dependencies`
   - Update with actual service-to-service connections

2. **System Overview Diagram**
   - Source: `architecture_summary.json > clusters, namespaces, external_resources`
   - Update with actual node counts, service counts, RDS instances

3. **Ingress/External Access Diagram**
   - Source: `architecture_summary.json > ingress_routes`
   - Update with actual domains and routing rules

### 5.4 Share with Team

```bash
# Share the GitHub URL
echo "Architecture data available at:"
echo "https://github.com/xiangyuzeng/luckin-k8s-architecture"

# Key files to review:
# - README.md (overview)
# - data/processed/architecture_summary.json (all the data)
# - logs/ (execution logs if needed)
```

## Maintenance: Keeping Data Current

### Weekly Updates

```bash
# Re-run collection
cd luckin-k8s-architecture/scripts
./run_all.sh

# Push updates
./06_push_to_github.sh
```

### Automated Updates (Optional)

Add to cron on a bastion host:

```bash
# Edit crontab
crontab -e

# Add this line for weekly Monday 2 AM updates
0 2 * * 1 cd /path/to/luckin-k8s-architecture/scripts && ./run_all.sh && ./06_push_to_github.sh >> /var/log/k8s-collection.log 2>&1
```

## Troubleshooting Reference

### Script Failed - How to Resume

If `run_all.sh` fails partway through:

```bash
# Option 1: Re-run only the failed phase
cd scripts

# Run individual scripts
./03_collect_service_dependencies.sh  # Example: if this one failed
./04_collect_external_resources.sh
./05_analyze_data.py

# Option 2: Re-run everything
./run_all.sh
```

### Check Logs

```bash
# List all logs
ls -lt logs/

# View latest run_all log
cat logs/run_all_*.log | tail -100

# View specific script log
cat logs/03_collect_service_dependencies_*.log
```

### Manual Fixes

If the analysis script fails, you can manually fix data files:

```bash
# Edit collected data (if needed)
vi data/raw/namespaces/rd-frontend/deployments.json

# Re-run just the analysis
./05_analyze_data.py

# Push updates
./06_push_to_github.sh
```

## Getting Help

**Internal:**
- DevOps Team
- GitHub Issues: https://github.com/xiangyuzeng/luckin-k8s-architecture/issues

**Toolkit Issues:**
- Check logs in `logs/` directory
- Review script output for error messages
- Verify prerequisites are met

**AWS/Kubernetes Issues:**
- AWS Support (for IAM/permissions)
- EKS documentation: https://docs.aws.amazon.com/eks/
- Kubernetes documentation: https://kubernetes.io/docs/

## Success Criteria

You've successfully completed this when:

- ✅ `architecture_summary.json` exists and contains data
- ✅ All expected namespaces are present in the summary
- ✅ Service dependencies were discovered (count > 0)
- ✅ External resources (RDS, ElastiCache) are listed
- ✅ Data pushed to GitHub successfully
- ✅ Repository is accessible at https://github.com/xiangyuzeng/luckin-k8s-architecture
- ✅ No sensitive data (passwords, keys) in the repository
- ✅ README and documentation are clear and helpful

## Estimated Total Time

- Setup: 5 minutes
- Data Collection: 15-30 minutes
- Verification: 5 minutes
- GitHub Push: 5 minutes
- **Total: 30-45 minutes**

(Not including time for reviewing findings and updating visualizations)

# Quick Start Guide

## TL;DR - Run This to Get Your Architecture Data

```bash
# 1. Navigate to the toolkit
cd luckin-k8s-architecture/scripts

# 2. Run everything
./run_all.sh

# 3. Push to GitHub
./06_push_to_github.sh
```

**Time required:** 30-45 minutes

## What You Need Before Starting

✅ kubectl configured with EKS access
✅ AWS CLI configured with credentials
✅ Internet access
✅ GitHub account (create repo first: https://github.com/new)

## Check Prerequisites (1 minute)

```bash
# Run these commands to verify you're ready:
kubectl get nodes        # Should show your cluster nodes
aws sts get-caller-identity  # Should show your AWS account
python3 --version       # Should show Python 3.x
jq --version            # Should show jq version
```

If any command fails, see README.md for installation instructions.

## Three Steps to Success

### Step 1: Collect Data (20-30 minutes)

```bash
cd luckin-k8s-architecture/scripts
./run_all.sh
```

This will:
- ✓ Collect cluster and node information
- ✓ Inventory all namespaces and workloads
- ✓ **Discover service dependencies** (the critical part!)
- ✓ Query AWS resources (RDS, ElastiCache, etc.)
- ✓ Analyze and structure all data

**Watch for:** Progress messages. Green = good, Yellow = warnings (usually OK), Red = errors

### Step 2: Verify Data (2 minutes)

```bash
# Check that summary was generated
ls -lh data/processed/architecture_summary.json

# Quick stats
cat data/processed/architecture_summary.json | jq '.resource_totals'
```

You should see counts for nodes, pods, deployments, services, etc.

### Step 3: Push to GitHub (3 minutes)

**First time only:** Create the repository on GitHub:
1. Go to https://github.com/new
2. Repository name: `luckin-k8s-architecture`
3. Visibility: Private (recommended)
4. Do NOT initialize with README
5. Create repository

**Then push:**

```bash
cd luckin-k8s-architecture/scripts
./06_push_to_github.sh
```

When prompted for password, use a GitHub Personal Access Token (not your actual password).

**Create a token:** https://github.com/settings/tokens → Generate new token → Select "repo" scope

## Verify Success

✅ Visit: https://github.com/xiangyuzeng/luckin-k8s-architecture
✅ You should see your data organized in folders
✅ Check `data/processed/architecture_summary.json` contains your infrastructure data

## Common Issues

**"kubectl: command not found"**
→ Install kubectl first (see README.md)

**"Cannot connect to cluster"**
```bash
aws eks update-kubeconfig --name prod-native-eks-us --region us-east-1
kubectl get nodes
```

**"Permission denied"**
```bash
chmod +x scripts/*.sh scripts/*.py
```

**"AWS permission errors during collection"**
→ This is OK! Script will collect what it can access and skip the rest

## What's Next?

1. **Review the data:** Open `data/processed/architecture_summary.json`
2. **Update diagrams:** Use the real data to fix your architecture visualizations
3. **Document findings:** Create `docs/architecture_findings.md`
4. **Share with team:** Send them the GitHub URL

## Need Help?

- **Detailed guide:** Read `docs/EXECUTION_GUIDE.md`
- **Full documentation:** Read `README.md`
- **Troubleshooting:** Check `logs/` directory for error details

## Keep It Updated

Run this weekly to keep architecture docs current:

```bash
cd luckin-k8s-architecture/scripts
./run_all.sh && ./06_push_to_github.sh
```

Or set up a cron job (see docs/EXECUTION_GUIDE.md for details).

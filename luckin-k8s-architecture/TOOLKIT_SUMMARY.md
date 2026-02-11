# Luckin Coffee K8s Architecture Data Collection Toolkit
## Complete Toolkit Summary

---

## 🎯 What This Toolkit Does

This toolkit **automates the collection and analysis** of your Kubernetes infrastructure to generate accurate architecture diagrams and documentation. It replaces manual data gathering with automated scripts.

## ⚠️ Critical Understanding

**I (Claude Code AI) do NOT have direct access to your AWS account or Kubernetes clusters.**

You need to run these scripts on a machine that has:
- kubectl configured with EKS cluster access
- AWS CLI configured with valid credentials
- Network access to your production environment

This is a **toolkit you run**, not something I can execute for you.

---

## 📦 What's Been Created

### Complete Toolkit Structure

```
luckin-k8s-architecture/
├── QUICK_START.md              ← START HERE (1-page quickstart)
├── README.md                    ← Full documentation
├── TOOLKIT_SUMMARY.md          ← This file
│
├── scripts/                     ← Data collection scripts
│   ├── run_all.sh              ← Master script (run this!)
│   ├── 01_collect_cluster_data.sh
│   ├── 02_collect_namespace_data.sh
│   ├── 03_collect_service_dependencies.sh  ← CRITICAL
│   ├── 04_collect_external_resources.sh
│   ├── 05_analyze_data.py
│   └── 06_push_to_github.sh
│
├── data/                        ← Data collection output
│   ├── raw/                     ← Raw collected data
│   │   ├── clusters/            ← Per-cluster node info
│   │   ├── namespaces/          ← Per-namespace workloads
│   │   ├── dependencies/        ← Service dependency data
│   │   └── external/            ← AWS resources
│   └── processed/               ← Analyzed data
│       └── architecture_summary.json  ← Main output file
│
├── docs/                        ← Documentation
│   └── EXECUTION_GUIDE.md      ← Step-by-step walkthrough
│
├── visualization/               ← For future React components
└── logs/                        ← Execution logs (created at runtime)
```

---

## 🚀 How to Use This Toolkit

### Method 1: Ultra-Quick Start (If You're Confident)

```bash
cd luckin-k8s-architecture/scripts
./run_all.sh
./06_push_to_github.sh
```

**Read:** `QUICK_START.md` for details

### Method 2: Step-by-Step with Understanding

**Read:** `docs/EXECUTION_GUIDE.md` for detailed walkthrough

### Method 3: Individual Script Execution

Run each script separately:

```bash
cd scripts
./01_collect_cluster_data.sh         # Clusters & nodes
./02_collect_namespace_data.sh       # Namespaces & workloads
./03_collect_service_dependencies.sh # Service relationships
./04_collect_external_resources.sh   # AWS resources
./05_analyze_data.py                 # Data analysis
./06_push_to_github.sh               # Push to GitHub
```

---

## 📋 What Each Script Does

### 01_collect_cluster_data.sh
**Collects:** Cluster and node information
**Output:** `data/raw/clusters/*/nodes.json`, node summaries
**Duration:** ~2-3 minutes
**What it does:**
- Connects to both EKS clusters
- Gets all node information (CPU, memory, IPs, instance types)
- Collects storage classes, persistent volumes
- Gets API resources and component statuses

### 02_collect_namespace_data.sh
**Collects:** All namespace-level workloads
**Output:** `data/raw/namespaces/*/deployments.json`, services.json, etc.
**Duration:** ~5-10 minutes
**What it does:**
- For each namespace:
  - Deployments, StatefulSets, DaemonSets
  - Services and endpoints
  - Ingresses and routing rules
  - Pods and their metrics
  - ConfigMaps and Secrets (metadata only)
  - HPAs, VPAs, Network Policies

### 03_collect_service_dependencies.sh ⭐ **MOST CRITICAL**
**Collects:** Service-to-service communication patterns
**Output:** `data/raw/dependencies/*_dependencies.txt`
**Duration:** ~5-10 minutes
**What it does:**
- Analyzes pod environment variables for service references
- Parses ConfigMaps for service URLs
- Checks deployment specs for hardcoded connections
- Discovers service mesh configurations (Istio/Linkerd)
- Maps network policies
- Identifies database connections

**This is the KEY to fixing your architecture diagrams!**

### 04_collect_external_resources.sh
**Collects:** AWS resources outside Kubernetes
**Output:** `data/raw/external/*.json`
**Duration:** ~3-5 minutes
**What it does:**
- RDS database instances
- ElastiCache clusters
- S3 buckets
- Load Balancers (ALB/NLB)
- SQS queues, SNS topics
- DynamoDB tables
- Lambda functions
- API Gateway APIs
- CloudFront distributions

### 05_analyze_data.py ⭐ **DATA PROCESSOR**
**Processes:** All collected raw data
**Output:** `data/processed/architecture_summary.json`
**Duration:** ~1-2 minutes
**What it does:**
- Parses all JSON data files
- Extracts key metrics
- Maps service relationships
- Structures data for visualization
- Generates comprehensive summary

**This creates the single source of truth for your architecture!**

### 06_push_to_github.sh
**Pushes:** All data to GitHub repository
**Output:** Git commits and pushes
**Duration:** ~2-3 minutes
**What it does:**
- Creates .gitignore
- Sanitizes sensitive data
- Initializes Git repository
- Commits all files
- Pushes to GitHub

---

## 📊 Key Output: architecture_summary.json

This is the **single most important file** - it contains everything:

```json
{
  "metadata": {
    "generated_at": "2026-01-20T...",
    "clusters": ["prod-native-eks-us", "prod-worker01-eks-us"]
  },
  "clusters": {
    "prod-native-eks-us": {
      "node_count": 20,
      "total_cpu": 320,
      "total_memory_gb": 1280,
      "nodes": [...]
    }
  },
  "namespaces": {
    "rd-frontend": {
      "deployments": [...],  // Actual deployments
      "services": [...],      // Actual services
      "pods_count": 45
    },
    "rd-sales": {...},
    "rd-finance": {...}
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
    "databases": [...],  // RDS instances
    "caches": [...],     // ElastiCache
    "load_balancers": [...]
  },
  "resource_totals": {
    "nodes": 40,
    "vcpus": 640,
    "memory_gb": 2560,
    "pods": 200,
    "deployments": 60,
    "services": 80
  }
}
```

**Use this file to:**
- Update your architecture diagrams with REAL data
- Generate accurate service dependency graphs
- Create capacity planning reports
- Build monitoring dashboards
- Document your infrastructure

---

## 🎯 Three Critical Questions This Answers

### 1. What services do we actually have?
**Answer in:** `architecture_summary.json > namespaces > {namespace} > deployments`

### 2. How do services communicate?
**Answer in:** `architecture_summary.json > service_dependencies`

### 3. What external resources do we use?
**Answer in:** `architecture_summary.json > external_resources`

---

## ✅ Success Checklist

After running the toolkit, verify:

- [ ] `data/processed/architecture_summary.json` exists
- [ ] File size is reasonable (typically 100KB - 5MB)
- [ ] Contains data for all expected namespaces
- [ ] `service_dependencies` array has entries (count > 0)
- [ ] `ingress_routes` array has entries
- [ ] External resources are listed
- [ ] No sensitive data (passwords, keys) in files
- [ ] Successfully pushed to GitHub
- [ ] Repository accessible at: https://github.com/xiangyuzeng/luckin-k8s-architecture

---

## 🔧 Troubleshooting Quick Reference

| Issue | Solution |
|-------|----------|
| "kubectl: command not found" | Install kubectl (see README.md) |
| "Cannot connect to cluster" | Run: `aws eks update-kubeconfig --name prod-native-eks-us --region us-east-1` |
| "Permission denied" | Run: `chmod +x scripts/*.sh scripts/*.py` |
| "AWS permission errors" | OK! Script skips what it can't access |
| Script hangs | Normal for large clusters. Wait up to 30 mins |
| "git push failed" | Create GitHub repo first at https://github.com/new |
| Python errors | Verify Python 3.6+: `python3 --version` |

**Full troubleshooting:** See README.md and docs/EXECUTION_GUIDE.md

---

## 📚 Documentation Hierarchy

1. **QUICK_START.md** ← Start here if you want to run immediately
2. **docs/EXECUTION_GUIDE.md** ← Detailed step-by-step walkthrough
3. **README.md** ← Complete reference documentation
4. **TOOLKIT_SUMMARY.md** ← This file (overview)

---

## 🎨 Using the Data for Visualizations

After collecting data, use `architecture_summary.json` to:

### Update Service Dependency Diagram

```javascript
// Example: Extract service dependencies
const deps = architectureSummary.service_dependencies;

// Create graph edges
const edges = deps.map(dep => ({
  from: dep.source,
  to: dep.target,
  type: dep.type
}));
```

### Update System Overview Diagram

```javascript
// Example: Get resource counts
const totals = architectureSummary.resource_totals;

// Display actual numbers
const stats = {
  nodes: totals.nodes,
  pods: totals.pods,
  services: totals.services
};
```

### Update External Resources Diagram

```javascript
// Example: Map RDS databases
const databases = architectureSummary.external_resources.databases;

// Create nodes for each database
const dbNodes = databases.map(db => ({
  id: db.identifier,
  engine: db.engine,
  endpoint: db.endpoint
}));
```

---

## 🔄 Keeping Data Current

### Option 1: Manual Updates (Recommended to start)

```bash
cd luckin-k8s-architecture/scripts
./run_all.sh && ./06_push_to_github.sh
```

Run this weekly or when infrastructure changes significantly.

### Option 2: Automated Updates (Advanced)

Set up a cron job on a bastion host:

```bash
# Edit crontab
crontab -e

# Add weekly Monday 2 AM updates
0 2 * * 1 cd /path/to/luckin-k8s-architecture/scripts && ./run_all.sh && ./06_push_to_github.sh
```

---

## 📈 Expected Outcomes

After running this toolkit, you will have:

✅ **Accurate Data**: Real infrastructure data, not mock data
✅ **Service Map**: Actual service-to-service communication patterns
✅ **Resource Inventory**: Complete list of all workloads
✅ **External Dependencies**: All AWS resources mapped
✅ **Version Controlled**: All data in GitHub for collaboration
✅ **Repeatable Process**: Scripts you can run anytime
✅ **Documentation**: README and guides for your team

---

## 🚨 Important Reminders

1. **Security**: Never commit passwords, API keys, or secrets
2. **Permissions**: You need read access to clusters and AWS resources
3. **Time**: Allow 30-45 minutes for first run
4. **Review**: Always review data before pushing to GitHub
5. **Updates**: Re-run weekly to keep docs current

---

## 📞 Next Steps After Running

1. **Review the Summary**
   ```bash
   cat data/processed/architecture_summary.json | jq .
   ```

2. **Compare to Mock Data**
   - What's different?
   - What was unexpected?
   - What's missing?

3. **Update Diagrams**
   - Fix service dependency arrows
   - Update resource counts
   - Correct external resource connections

4. **Document Findings**
   - Create `docs/architecture_findings.md`
   - Note discrepancies
   - List action items

5. **Share with Team**
   - GitHub URL
   - Key insights
   - Updated diagrams

---

## 📋 Where to Find Everything

| What You Need | Where to Find It |
|---------------|------------------|
| Quick start instructions | `QUICK_START.md` |
| Complete reference | `README.md` |
| Step-by-step guide | `docs/EXECUTION_GUIDE.md` |
| Scripts to run | `scripts/` directory |
| Collected data | `data/raw/` directory |
| **Architecture summary** | `data/processed/architecture_summary.json` |
| Execution logs | `logs/` directory (created at runtime) |

---

## 💡 Pro Tips

1. **Start with a dry run**: Use `--dry-run` flags to preview
2. **Check logs**: Always review logs if something seems off
3. **Incremental fixes**: If a script fails, fix and re-run just that script
4. **Data validation**: Use `jq` to quickly inspect JSON files
5. **Git history**: Use Git to track changes over time
6. **Automation**: Once comfortable, automate weekly runs

---

## ⏱️ Time Estimates

| Task | Duration |
|------|----------|
| Setup & prerequisites | 5-10 minutes |
| Run data collection | 20-30 minutes |
| Verify data | 5 minutes |
| Push to GitHub | 5 minutes |
| **Total first run** | **35-50 minutes** |
| Subsequent runs | 25-35 minutes |

---

## 🎓 What You've Learned

After using this toolkit, you'll understand:

- How to programmatically query Kubernetes clusters
- How to discover service dependencies
- How to inventory AWS resources
- How to structure and analyze infrastructure data
- How to maintain living documentation
- How to automate data collection

---

## 🏆 Success = Accurate Architecture Documentation

Your goal is achieved when:

1. ✅ Architecture diagrams reflect **actual** infrastructure
2. ✅ Service dependencies are **verified** not assumed
3. ✅ Resource counts are **accurate** not estimated
4. ✅ External resources are **documented** not guessed
5. ✅ Team can **reproduce** your results
6. ✅ Documentation stays **current** with automation

---

## 📝 License & Support

**License:** Internal use only - Luckin Coffee North America

**Support:**
- DevOps Team
- GitHub: @xiangyuzeng
- Repository Issues: https://github.com/xiangyuzeng/luckin-k8s-architecture/issues

---

**Ready to start?** → Read `QUICK_START.md` and run `./scripts/run_all.sh`

**Need details?** → Read `docs/EXECUTION_GUIDE.md`

**Have questions?** → Check `README.md` troubleshooting section

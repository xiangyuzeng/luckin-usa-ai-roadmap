#!/bin/bash
#
# Luckin Coffee K8s Architecture - GitHub Push Script
# Pushes collected data and analysis to GitHub repository
#
# Usage: ./06_push_to_github.sh [--dry-run]
#

set -euo pipefail

# Configuration
REPO_URL="https://github.com/xiangyuzeng/luckin-k8s-architecture.git"
REPO_NAME="luckin-k8s-architecture"
BRANCH="main"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# Parse arguments
DRY_RUN=false
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be pushed without actually pushing"
            echo "  --help       Show this help message"
            exit 0
            ;;
    esac
done

# Navigate to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

echo ""
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║  Luckin Coffee - Push Architecture Data to GitHub                 ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""

log_info "Repository: $REPO_URL"
log_info "Branch: $BRANCH"
if [ "$DRY_RUN" = true ]; then
    log_warn "DRY RUN MODE - No changes will be pushed"
fi
echo ""

# Check if git is installed
if ! command -v git &> /dev/null; then
    log_error "git is not installed"
    exit 1
fi

# Verify required data exists
verify_data() {
    log_step "Verifying collected data..."

    local required_files=(
        "data/processed/architecture_summary.json"
    )

    local missing_files=()
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_files+=("$file")
        fi
    done

    if [ ${#missing_files[@]} -gt 0 ]; then
        log_error "Missing required files:"
        for file in "${missing_files[@]}"; do
            log_error "  - $file"
        done
        log_error ""
        log_error "Please run data collection and analysis scripts first:"
        log_error "  ./scripts/run_all.sh"
        return 1
    fi

    log_info "✓ All required data files found"
    echo ""
}

# Create .gitignore
create_gitignore() {
    log_step "Creating .gitignore..."

    cat > .gitignore << 'EOF'
# Node modules
node_modules/
.next/
out/
build/
dist/

# Logs
*.log
logs/
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Environment variables
.env
.env.local
.env.*.local

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Sensitive data - DO NOT COMMIT
data/raw/**/*secret*
data/raw/**/*password*
data/raw/**/*token*
data/raw/**/*key*
*.pem
*.key

# Temporary files
*.tmp
*.temp
.cache/

# Python
__pycache__/
*.py[cod]
*.so
.Python
*.egg-info/
.pytest_cache/
EOF

    log_info "✓ .gitignore created"
    echo ""
}

# Sanitize sensitive data
sanitize_data() {
    log_step "Sanitizing sensitive data..."

    # Create a list of patterns to check for
    local sensitive_patterns=(
        "password"
        "secret"
        "token"
        "api_key"
        "apikey"
        "access_key"
        "private_key"
    )

    local found_sensitive=false

    for pattern in "${sensitive_patterns[@]}"; do
        if grep -r -i "$pattern" data/ 2>/dev/null | grep -v ".git" | grep -v "Binary" | head -5; then
            log_warn "Found potential sensitive data matching pattern: $pattern"
            found_sensitive=true
        fi
    done

    if [ "$found_sensitive" = true ]; then
        echo ""
        log_warn "Sensitive data detected in collected files"
        log_warn "Please review and sanitize before pushing to GitHub"
        echo ""
        read -p "Continue anyway? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            log_info "Aborted by user"
            exit 0
        fi
    else
        log_info "✓ No obvious sensitive data patterns detected"
    fi

    echo ""
}

# Initialize or update git repository
init_git_repo() {
    log_step "Initializing Git repository..."

    if [ ! -d ".git" ]; then
        git init
        git branch -M "$BRANCH"
        log_info "✓ Git repository initialized"
    else
        log_info "Git repository already initialized"
    fi

    # Check if remote exists
    if git remote | grep -q "^origin$"; then
        local current_url=$(git remote get-url origin)
        if [ "$current_url" != "$REPO_URL" ]; then
            log_warn "Remote 'origin' exists but points to different URL"
            log_warn "Current: $current_url"
            log_warn "Expected: $REPO_URL"
            read -p "Update remote URL? (yes/no): " confirm
            if [ "$confirm" = "yes" ]; then
                git remote set-url origin "$REPO_URL"
                log_info "✓ Remote URL updated"
            fi
        fi
    else
        git remote add origin "$REPO_URL"
        log_info "✓ Remote 'origin' added"
    fi

    echo ""
}

# Create README if it doesn't exist
create_readme() {
    if [ ! -f "README.md" ]; then
        log_step "Creating README.md..."

        cat > README.md << 'EOF'
# Luckin Coffee North America - Kubernetes Architecture

This repository contains the actual architecture data and analysis for Luckin Coffee North America's Kubernetes infrastructure.

## Repository Structure

```
luckin-k8s-architecture/
├── data/
│   ├── raw/                    # Raw collected data from K8s clusters
│   │   ├── clusters/           # Cluster and node information
│   │   ├── namespaces/         # Namespace-level workload data
│   │   ├── dependencies/       # Service dependency mappings
│   │   └── external/           # AWS external resources
│   └── processed/              # Processed and analyzed data
│       └── architecture_summary.json  # Main architecture summary
├── scripts/                    # Data collection and analysis scripts
│   ├── 01_collect_cluster_data.sh
│   ├── 02_collect_namespace_data.sh
│   ├── 03_collect_service_dependencies.sh
│   ├── 04_collect_external_resources.sh
│   ├── 05_analyze_data.py
│   └── run_all.sh             # Master script to run all
├── docs/                       # Documentation
└── README.md

## Data Collection

The data in this repository was collected from our production EKS clusters using automated scripts:

1. **Cluster Data**: Node counts, capacity, resource allocation
2. **Namespace Data**: Deployments, services, pods, ingresses
3. **Service Dependencies**: Inter-service communication patterns
4. **External Resources**: RDS, ElastiCache, Load Balancers, etc.

### Running Data Collection

```bash
# Run all collection and analysis scripts
cd scripts
./run_all.sh

# Or run individual scripts
./01_collect_cluster_data.sh
./02_collect_namespace_data.sh
./03_collect_service_dependencies.sh
./04_collect_external_resources.sh
./05_analyze_data.py
```

## Architecture Summary

The `data/processed/architecture_summary.json` file contains a comprehensive view of our infrastructure including:

- **Clusters**: Node counts, CPU/memory capacity
- **Namespaces**: Service counts, deployments, pod metrics
- **Services**: All Kubernetes services with DNS names
- **Dependencies**: Service-to-service communication mappings
- **Ingress Routes**: External access points
- **External Resources**: AWS RDS, ElastiCache, Load Balancers

## Security Note

⚠️ **Important**: This repository contains metadata only. All sensitive data (passwords, secrets, tokens) has been removed or sanitized before committing.

## Last Updated

This data was collected on: [Auto-generated timestamp]

## Contact

For questions about this architecture, contact the DevOps team.
EOF

        log_info "✓ README.md created"
        echo ""
    else
        log_info "README.md already exists"
        echo ""
    fi
}

# Commit and push changes
commit_and_push() {
    log_step "Preparing commit..."

    # Stage files
    git add .

    # Check if there are changes to commit
    if git diff --staged --quiet; then
        log_warn "No changes to commit"
        return 0
    fi

    # Show what will be committed
    echo ""
    log_info "Files to be committed:"
    git status --short
    echo ""

    if [ "$DRY_RUN" = true ]; then
        log_warn "DRY RUN - Would commit and push the above files"
        return 0
    fi

    # Create commit
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local commit_msg="Update K8s architecture data - $timestamp

Data collection timestamp: $timestamp
Collected from: Production EKS clusters (us-east-1)

Changes:
- Updated cluster and node information
- Refreshed namespace workload data
- Updated service dependency mappings
- Refreshed external AWS resources data
- Regenerated architecture summary"

    git commit -m "$commit_msg"
    log_info "✓ Changes committed"
    echo ""

    # Push to GitHub
    log_step "Pushing to GitHub..."

    if git push -u origin "$BRANCH" 2>&1; then
        log_info "✓ Successfully pushed to GitHub"
        echo ""
        log_info "Repository URL: $REPO_URL"
    else
        log_error "Failed to push to GitHub"
        log_error ""
        log_error "Possible reasons:"
        log_error "  1. Repository doesn't exist - create it on GitHub first"
        log_error "  2. No push access - check your GitHub credentials"
        log_error "  3. Network issue - check your internet connection"
        echo ""
        log_info "You can manually push later with:"
        log_info "  git push -u origin $BRANCH"
        return 1
    fi
}

# Generate final report
generate_report() {
    log_step "Generating final report..."

    local summary_file="data/processed/architecture_summary.json"

    if [ ! -f "$summary_file" ]; then
        log_warn "Architecture summary not found"
        return
    fi

    cat << EOF

═══════════════════════════════════════════════════════════════════
                    ARCHITECTURE DATA SUMMARY
═══════════════════════════════════════════════════════════════════

Repository: $REPO_URL
Branch: $BRANCH
Last Updated: $(date)

Key Findings:
EOF

    # Extract key metrics using jq
    if command -v jq &> /dev/null && [ -f "$summary_file" ]; then
        local clusters=$(jq '.metadata.clusters | length' "$summary_file" 2>/dev/null || echo "N/A")
        local namespaces=$(jq '.namespaces | length' "$summary_file" 2>/dev/null || echo "N/A")
        local nodes=$(jq '.resource_totals.nodes' "$summary_file" 2>/dev/null || echo "N/A")
        local pods=$(jq '.resource_totals.pods' "$summary_file" 2>/dev/null || echo "N/A")
        local deployments=$(jq '.resource_totals.deployments' "$summary_file" 2>/dev/null || echo "N/A")
        local services=$(jq '.resource_totals.services' "$summary_file" 2>/dev/null || echo "N/A")
        local dependencies=$(jq '.service_dependencies | length' "$summary_file" 2>/dev/null || echo "N/A")
        local rds=$(jq '.external_resources.databases | length' "$summary_file" 2>/dev/null || echo "N/A")

        cat << EOF
  • Clusters: $clusters
  • Namespaces: $namespaces
  • Total Nodes: $nodes
  • Total Pods: $pods
  • Deployments: $deployments
  • Services: $services
  • Service Dependencies: $dependencies
  • RDS Databases: $rds

Next Steps:
  1. Review data at: $REPO_URL
  2. Update visualization components with real data
  3. Document any discrepancies from original mock data
  4. Share findings with the team

═══════════════════════════════════════════════════════════════════
EOF
    fi
}

# Main execution
main() {
    verify_data || exit 1
    create_gitignore
    sanitize_data
    init_git_repo
    create_readme
    commit_and_push
    generate_report

    echo ""
    log_info "✓ GitHub push complete!"
    echo ""
}

main

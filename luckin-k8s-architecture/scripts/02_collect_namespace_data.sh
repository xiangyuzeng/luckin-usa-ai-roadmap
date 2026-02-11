#!/bin/bash
#
# Luckin Coffee K8s Data Collection - Phase 2: Namespace & Workload Data
# This script collects namespace-level workload data
#
# Usage: ./02_collect_namespace_data.sh
#

set -euo pipefail

# Configuration
NAMESPACES=(
    "rd-frontend"
    "rd-sales"
    "rd-finance"
    "rd-supplychains"
    "rd-iot"
    "rd-eeop"
    "rd-pub"
    "rd-dt"
    "kube-system"
    "monitor"
    "efk-log"
    "baseservices-cloud-dify"
    "ingress-nginx"
    "cert-manager"
    "external-secrets"
)

OUTPUT_DIR="../data/raw/namespaces"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Create output directory
mkdir -p "$OUTPUT_DIR"

# First, get all namespaces
log_info "Discovering all namespaces..."
kubectl get namespaces -o json > "$OUTPUT_DIR/all_namespaces.json"
kubectl get namespaces -o wide > "$OUTPUT_DIR/all_namespaces.txt"

# Extract namespace names
DISCOVERED_NS=($(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'))
log_info "Found ${#DISCOVERED_NS[@]} namespaces"

# Function to collect namespace data
collect_namespace_data() {
    local ns=$1
    local ns_dir="$OUTPUT_DIR/$ns"

    log_info "Collecting data for namespace: $ns"
    mkdir -p "$ns_dir"

    # Namespace details
    kubectl get namespace "$ns" -o json > "$ns_dir/namespace.json" 2>&1 || log_warn "get namespace failed for $ns"

    # Resource quotas
    log_info "  - Resource quotas..."
    kubectl get resourcequota -n "$ns" -o json > "$ns_dir/resourcequotas.json" 2>&1 || true
    kubectl get resourcequota -n "$ns" -o yaml > "$ns_dir/resourcequotas.yaml" 2>&1 || true

    # Limit ranges
    log_info "  - Limit ranges..."
    kubectl get limitrange -n "$ns" -o json > "$ns_dir/limitranges.json" 2>&1 || true

    # Deployments
    log_info "  - Deployments..."
    kubectl get deployments -n "$ns" -o json > "$ns_dir/deployments.json" 2>&1 || true
    kubectl get deployments -n "$ns" -o wide > "$ns_dir/deployments.txt" 2>&1 || true

    # StatefulSets
    log_info "  - StatefulSets..."
    kubectl get statefulsets -n "$ns" -o json > "$ns_dir/statefulsets.json" 2>&1 || true

    # DaemonSets
    log_info "  - DaemonSets..."
    kubectl get daemonsets -n "$ns" -o json > "$ns_dir/daemonsets.json" 2>&1 || true

    # ReplicaSets
    log_info "  - ReplicaSets..."
    kubectl get replicasets -n "$ns" -o json > "$ns_dir/replicasets.json" 2>&1 || true

    # Jobs
    log_info "  - Jobs..."
    kubectl get jobs -n "$ns" -o json > "$ns_dir/jobs.json" 2>&1 || true

    # CronJobs
    log_info "  - CronJobs..."
    kubectl get cronjobs -n "$ns" -o json > "$ns_dir/cronjobs.json" 2>&1 || true

    # Pods
    log_info "  - Pods..."
    kubectl get pods -n "$ns" -o json > "$ns_dir/pods.json" 2>&1 || true
    kubectl get pods -n "$ns" -o wide > "$ns_dir/pods.txt" 2>&1 || true
    kubectl get pods -n "$ns" --show-labels > "$ns_dir/pods_labels.txt" 2>&1 || true

    # Pod metrics
    log_info "  - Pod metrics..."
    kubectl top pods -n "$ns" > "$ns_dir/pods_metrics.txt" 2>&1 || log_warn "top pods failed (metrics-server may not be installed)"

    # Services
    log_info "  - Services..."
    kubectl get services -n "$ns" -o json > "$ns_dir/services.json" 2>&1 || true
    kubectl get services -n "$ns" -o wide > "$ns_dir/services.txt" 2>&1 || true

    # Endpoints
    log_info "  - Endpoints..."
    kubectl get endpoints -n "$ns" -o json > "$ns_dir/endpoints.json" 2>&1 || true

    # Ingresses
    log_info "  - Ingresses..."
    kubectl get ingress -n "$ns" -o json > "$ns_dir/ingresses.json" 2>&1 || true
    kubectl get ingress -n "$ns" -o wide > "$ns_dir/ingresses.txt" 2>&1 || true

    # ConfigMaps (metadata only, not the data)
    log_info "  - ConfigMaps..."
    kubectl get configmaps -n "$ns" -o json > "$ns_dir/configmaps.json" 2>&1 || true
    kubectl get configmaps -n "$ns" -o name > "$ns_dir/configmaps_names.txt" 2>&1 || true

    # Secrets (metadata only)
    log_info "  - Secrets (metadata)..."
    kubectl get secrets -n "$ns" -o json | jq 'del(.items[].data)' > "$ns_dir/secrets_metadata.json" 2>&1 || true
    kubectl get secrets -n "$ns" -o name > "$ns_dir/secrets_names.txt" 2>&1 || true

    # HPAs
    log_info "  - HPAs..."
    kubectl get hpa -n "$ns" -o json > "$ns_dir/hpa.json" 2>&1 || true

    # VPAs (if installed)
    log_info "  - VPAs..."
    kubectl get vpa -n "$ns" -o json > "$ns_dir/vpa.json" 2>&1 || true

    # PVCs
    log_info "  - PVCs..."
    kubectl get pvc -n "$ns" -o json > "$ns_dir/pvcs.json" 2>&1 || true

    # Network Policies
    log_info "  - Network Policies..."
    kubectl get networkpolicies -n "$ns" -o json > "$ns_dir/networkpolicies.json" 2>&1 || true

    # Service Accounts
    log_info "  - Service Accounts..."
    kubectl get serviceaccounts -n "$ns" -o json > "$ns_dir/serviceaccounts.json" 2>&1 || true

    # Roles and RoleBindings
    log_info "  - RBAC..."
    kubectl get roles -n "$ns" -o json > "$ns_dir/roles.json" 2>&1 || true
    kubectl get rolebindings -n "$ns" -o json > "$ns_dir/rolebindings.json" 2>&1 || true

    # Events (last 1 hour)
    log_info "  - Events..."
    kubectl get events -n "$ns" --sort-by='.lastTimestamp' > "$ns_dir/events.txt" 2>&1 || true
    kubectl get events -n "$ns" -o json > "$ns_dir/events.json" 2>&1 || true

    log_info "Completed data collection for namespace: $ns"
    echo ""
}

# Main execution
log_info "Starting namespace data collection at $TIMESTAMP"
log_info "Target namespaces: ${#NAMESPACES[@]} specified, ${#DISCOVERED_NS[@]} discovered"
echo ""

# Collect data for specified namespaces
for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &>/dev/null; then
        collect_namespace_data "$ns"
    else
        log_warn "Namespace $ns does not exist, skipping..."
    fi
done

# Ask if user wants to collect data for other discovered namespaces
log_info "Discovered additional namespaces beyond the predefined list:"
for ns in "${DISCOVERED_NS[@]}"; do
    if [[ ! " ${NAMESPACES[@]} " =~ " ${ns} " ]]; then
        echo "  - $ns"
    fi
done

log_info "Namespace data collection complete!"
log_info "Data saved to: $OUTPUT_DIR"

# Generate namespace summary
log_info "Generating namespace summary..."
python3 - <<'PYEOF'
import json
import os
from pathlib import Path

output_dir = Path("../data/raw/namespaces")
summary = {}

for ns_dir in output_dir.iterdir():
    if ns_dir.is_dir() and ns_dir.name != "all_namespaces.json":
        ns_name = ns_dir.name
        summary[ns_name] = {
            "deployments": 0,
            "statefulsets": 0,
            "daemonsets": 0,
            "pods": 0,
            "services": 0,
            "ingresses": 0,
            "pvcs": 0
        }

        # Count resources
        for resource_type in ["deployments", "statefulsets", "daemonsets", "pods", "services", "ingresses", "pvcs"]:
            json_file = ns_dir / f"{resource_type}.json"
            if json_file.exists():
                try:
                    with open(json_file) as f:
                        data = json.load(f)
                        summary[ns_name][resource_type] = len(data.get("items", []))
                except:
                    pass

print("\nNamespace Resource Summary:")
print("=" * 80)
print(f"{'Namespace':<30} {'Deploys':<10} {'STS':<8} {'DS':<8} {'Pods':<8} {'Svcs':<8} {'Ing':<8}")
print("-" * 80)

for ns, counts in sorted(summary.items()):
    print(f"{ns:<30} {counts['deployments']:<10} {counts['statefulsets']:<8} {counts['daemonsets']:<8} {counts['pods']:<8} {counts['services']:<8} {counts['ingresses']:<8}")

print("=" * 80)

# Save summary
with open(output_dir / "namespace_summary.json", "w") as f:
    json.dump(summary, f, indent=2)

print(f"\nSummary saved to: {output_dir / 'namespace_summary.json'}")
PYEOF

echo ""
log_info "Next steps:"
log_info "1. Run ./03_collect_service_dependencies.sh to discover service relationships"
log_info "2. Run ./04_collect_external_resources.sh to identify external dependencies"

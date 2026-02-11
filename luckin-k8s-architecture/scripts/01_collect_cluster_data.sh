#!/bin/bash
#
# Luckin Coffee K8s Data Collection - Phase 1: Cluster & Node Information
# This script collects cluster-level data from EKS clusters
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - kubectl installed and configured
#   - Access to EKS clusters: prod-native-eks-us, prod-worker01-eks-us
#
# Usage: ./01_collect_cluster_data.sh [cluster-context-name]
#

set -euo pipefail

# Configuration
CLUSTERS=("prod-native-eks-us" "prod-worker01-eks-us")
REGION="us-east-1"
OUTPUT_DIR="../data/raw/clusters"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Function to collect cluster data
collect_cluster_data() {
    local cluster_name=$1
    local cluster_dir="$OUTPUT_DIR/${cluster_name}"

    log_info "Collecting data for cluster: $cluster_name"
    mkdir -p "$cluster_dir"

    # Update kubeconfig
    log_info "Updating kubeconfig for $cluster_name..."
    if ! aws eks update-kubeconfig --name "$cluster_name" --region "$REGION" 2>"$cluster_dir/kubeconfig_error.log"; then
        log_error "Failed to update kubeconfig for $cluster_name"
        cat "$cluster_dir/kubeconfig_error.log"
        return 1
    fi

    # Get current context
    local context=$(kubectl config current-context)
    log_info "Current context: $context"
    echo "$context" > "$cluster_dir/context.txt"

    # Cluster info
    log_info "Getting cluster info..."
    kubectl cluster-info > "$cluster_dir/cluster_info.txt" 2>&1 || log_warn "cluster-info failed"

    # Version
    log_info "Getting Kubernetes version..."
    kubectl version --output=json > "$cluster_dir/version.json" 2>&1 || log_warn "version failed"

    # Nodes - detailed JSON
    log_info "Getting nodes (JSON)..."
    kubectl get nodes -o json > "$cluster_dir/nodes.json" 2>&1 || log_warn "get nodes json failed"

    # Nodes - human readable
    log_info "Getting nodes (wide format)..."
    kubectl get nodes -o wide > "$cluster_dir/nodes_wide.txt" 2>&1 || log_warn "get nodes wide failed"

    # Node descriptions
    log_info "Describing all nodes..."
    kubectl describe nodes > "$cluster_dir/nodes_describe.txt" 2>&1 || log_warn "describe nodes failed"

    # Node metrics (requires metrics-server)
    log_info "Getting node metrics..."
    kubectl top nodes > "$cluster_dir/nodes_metrics.txt" 2>&1 || log_warn "top nodes failed (metrics-server may not be installed)"

    # Node resource summary
    log_info "Getting node resource summary..."
    kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
CPU:.status.capacity.cpu,\
MEMORY:.status.capacity.memory,\
PODS:.status.capacity.pods,\
INTERNAL-IP:.status.addresses[0].address,\
INSTANCE-TYPE:.metadata.labels.node\\.kubernetes\\.io/instance-type,\
ZONE:.metadata.labels.topology\\.kubernetes\\.io/zone \
    > "$cluster_dir/nodes_summary.txt" 2>&1 || log_warn "custom columns failed"

    # Storage classes
    log_info "Getting storage classes..."
    kubectl get storageclass -o json > "$cluster_dir/storageclasses.json" 2>&1 || log_warn "get storageclass failed"

    # Persistent volumes
    log_info "Getting persistent volumes..."
    kubectl get pv -o json > "$cluster_dir/persistentvolumes.json" 2>&1 || log_warn "get pv failed"

    # API resources
    log_info "Getting API resources..."
    kubectl api-resources > "$cluster_dir/api_resources.txt" 2>&1 || log_warn "api-resources failed"

    # Component statuses
    log_info "Getting component statuses..."
    kubectl get componentstatuses -o json > "$cluster_dir/componentstatuses.json" 2>&1 || log_warn "get componentstatuses failed"

    log_info "Cluster data collection complete for $cluster_name"
    echo ""
}

# Main execution
log_info "Starting cluster data collection at $TIMESTAMP"
log_info "Output directory: $OUTPUT_DIR"
echo ""

# Verify AWS CLI access
log_info "Verifying AWS credentials..."
if ! aws sts get-caller-identity > "$OUTPUT_DIR/aws_identity.json" 2>&1; then
    log_error "AWS credentials not configured properly"
    exit 1
fi

CALLER_IDENTITY=$(cat "$OUTPUT_DIR/aws_identity.json")
log_info "AWS Identity:"
echo "$CALLER_IDENTITY" | jq . || cat "$OUTPUT_DIR/aws_identity.json"
echo ""

# Collect data for each cluster
for cluster in "${CLUSTERS[@]}"; do
    collect_cluster_data "$cluster"
done

log_info "All cluster data collection complete!"
log_info "Data saved to: $OUTPUT_DIR"

# Generate summary
log_info "Generating cluster summary..."
cat > "$OUTPUT_DIR/collection_summary.txt" << EOF
Cluster Data Collection Summary
================================
Timestamp: $TIMESTAMP
Clusters: ${CLUSTERS[@]}
Region: $REGION
Output Directory: $OUTPUT_DIR

Collected data includes:
- Cluster info and version
- Node details (JSON, wide format, descriptions)
- Node metrics
- Storage classes
- Persistent volumes
- API resources
- Component statuses

Next steps:
1. Run ./02_collect_namespace_data.sh to collect namespace-level data
2. Run ./03_collect_service_dependencies.sh to map service relationships
3. Run ./04_analyze_data.py to process and analyze the collected data
EOF

cat "$OUTPUT_DIR/collection_summary.txt"

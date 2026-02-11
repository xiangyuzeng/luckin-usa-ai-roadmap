#!/bin/bash
#
# Luckin Coffee K8s Data Collection - Phase 3: Service Dependencies
# This is the MOST CRITICAL script - it discovers how services communicate
#
# Usage: ./03_collect_service_dependencies.sh
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
)

OUTPUT_DIR="../data/raw/dependencies"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_detail() { echo -e "${BLUE}[DETAIL]${NC} $1"; }

mkdir -p "$OUTPUT_DIR"

log_info "Starting service dependency discovery at $TIMESTAMP"
log_info "This script will discover service-to-service communication patterns"
echo ""

#==============================================================================
# Method 1: Environment Variables Analysis
# Services often inject URLs/hostnames of dependencies via env vars
#==============================================================================
discover_env_dependencies() {
    local ns=$1
    local output_file="$OUTPUT_DIR/${ns}_env_dependencies.txt"

    log_info "Method 1: Analyzing environment variables in namespace: $ns"

    # Get all pods in the namespace
    local pods=($(kubectl get pods -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo ""))

    if [ ${#pods[@]} -eq 0 ]; then
        log_warn "No pods found in namespace $ns"
        return
    fi

    echo "=== Environment Variables Dependencies for $ns ===" > "$output_file"
    echo "Timestamp: $TIMESTAMP" >> "$output_file"
    echo "" >> "$output_file"

    # Sample first 3 pods (or all if less than 3)
    local sample_size=3
    local count=0

    for pod in "${pods[@]}"; do
        if [ $count -ge $sample_size ]; then
            break
        fi

        log_detail "  Checking pod: $pod"

        echo "=== Pod: $pod ===" >> "$output_file"

        # Get environment variables that might indicate service dependencies
        kubectl exec -n "$ns" "$pod" -- env 2>/dev/null | \
            grep -E "(_HOST|_URL|_ENDPOINT|_SERVICE|_PORT|_ADDRESS|DATABASE|REDIS|MONGO|MYSQL|POSTGRES|KAFKA|RABBITMQ|ELASTIC)" | \
            grep -v "KUBERNETES_" | \
            sort >> "$output_file" 2>/dev/null || true

        echo "" >> "$output_file"
        ((count++))
    done

    log_info "  Environment dependencies saved to: $output_file"
}

#==============================================================================
# Method 2: ConfigMap Analysis
# ConfigMaps often contain service URLs and connection strings
#==============================================================================
discover_configmap_dependencies() {
    local ns=$1
    local output_file="$OUTPUT_DIR/${ns}_configmap_dependencies.txt"

    log_info "Method 2: Analyzing ConfigMaps in namespace: $ns"

    echo "=== ConfigMap Dependencies for $ns ===" > "$output_file"
    echo "Timestamp: $TIMESTAMP" >> "$output_file"
    echo "" >> "$output_file"

    # Get all configmaps
    local configmaps=($(kubectl get configmaps -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo ""))

    for cm in "${configmaps[@]}"; do
        # Skip default configmaps
        if [[ "$cm" == "kube-"* ]] || [[ "$cm" == "istio-"* ]]; then
            continue
        fi

        log_detail "  Checking ConfigMap: $cm"

        echo "=== ConfigMap: $cm ===" >> "$output_file"

        # Extract data and look for URLs, hosts, endpoints
        kubectl get configmap "$cm" -n "$ns" -o yaml 2>/dev/null | \
            grep -E "(http://|https://|jdbc:|mongodb://|redis://|mysql://|postgresql://|:\/\/|\.svc\.cluster\.local|_HOST|_URL|_ENDPOINT)" | \
            sed 's/password.*/password: [REDACTED]/' | \
            sed 's/secret.*/secret: [REDACTED]/' >> "$output_file" 2>/dev/null || true

        echo "" >> "$output_file"
    done

    log_info "  ConfigMap dependencies saved to: $output_file"
}

#==============================================================================
# Method 3: Deployment Spec Analysis
# Check deployment specs for hardcoded service references
#==============================================================================
discover_deployment_dependencies() {
    local ns=$1
    local output_file="$OUTPUT_DIR/${ns}_deployment_dependencies.txt"

    log_info "Method 3: Analyzing Deployment specs in namespace: $ns"

    echo "=== Deployment Dependencies for $ns ===" > "$output_file"
    echo "Timestamp: $TIMESTAMP" >> "$output_file"
    echo "" >> "$output_file"

    # Get deployment specs and extract service references
    kubectl get deployments -n "$ns" -o yaml 2>/dev/null | \
        grep -E "(value:|valueFrom:|name:.*service|\.svc\.|http://|https://)" | \
        sed 's/password.*/password: [REDACTED]/' | \
        sed 's/secret.*/secret: [REDACTED]/' >> "$output_file" || true

    log_info "  Deployment dependencies saved to: $output_file"
}

#==============================================================================
# Method 4: Service Mesh Analysis (Istio/Linkerd)
# If using a service mesh, get VirtualServices and DestinationRules
#==============================================================================
discover_service_mesh() {
    log_info "Method 4: Checking for Service Mesh configurations"

    local output_file="$OUTPUT_DIR/service_mesh.json"

    # Check for Istio VirtualServices
    log_detail "  Checking for Istio VirtualServices..."
    kubectl get virtualservices -A -o json > "$OUTPUT_DIR/istio_virtualservices.json" 2>/dev/null || \
        echo '{"items":[]}' > "$OUTPUT_DIR/istio_virtualservices.json"

    # Check for DestinationRules
    log_detail "  Checking for Istio DestinationRules..."
    kubectl get destinationrules -A -o json > "$OUTPUT_DIR/istio_destinationrules.json" 2>/dev/null || \
        echo '{"items":[]}' > "$OUTPUT_DIR/istio_destinationrules.json"

    # Check for ServiceEntries
    log_detail "  Checking for Istio ServiceEntries..."
    kubectl get serviceentries -A -o json > "$OUTPUT_DIR/istio_serviceentries.json" 2>/dev/null || \
        echo '{"items":[]}' > "$OUTPUT_DIR/istio_serviceentries.json"

    # Check for Linkerd ServiceProfiles
    log_detail "  Checking for Linkerd ServiceProfiles..."
    kubectl get serviceprofiles -A -o json > "$OUTPUT_DIR/linkerd_serviceprofiles.json" 2>/dev/null || \
        echo '{"items":[]}' > "$OUTPUT_DIR/linkerd_serviceprofiles.json"

    log_info "  Service mesh configurations saved"
}

#==============================================================================
# Method 5: Network Policies
# Network policies define allowed traffic flows
#==============================================================================
discover_network_policies() {
    log_info "Method 5: Analyzing Network Policies"

    local output_file="$OUTPUT_DIR/network_policies_all.json"

    kubectl get networkpolicies -A -o json > "$output_file" 2>/dev/null || \
        echo '{"items":[]}' > "$output_file"

    # Also get human-readable format
    kubectl get networkpolicies -A -o wide > "$OUTPUT_DIR/network_policies_all.txt" 2>/dev/null || true

    log_info "  Network policies saved to: $output_file"
}

#==============================================================================
# Method 6: Service Endpoints Analysis
# Map services to their endpoints (pods)
#==============================================================================
discover_service_endpoints() {
    log_info "Method 6: Mapping Services to Endpoints"

    local output_file="$OUTPUT_DIR/service_endpoints_all.json"

    kubectl get endpoints -A -o json > "$output_file" 2>/dev/null || \
        echo '{"items":[]}' > "$output_file"

    log_info "  Service endpoints saved to: $output_file"
}

#==============================================================================
# Method 7: DNS Service Discovery
# Extract all services and their DNS names
#==============================================================================
discover_dns_services() {
    log_info "Method 7: Discovering all Kubernetes Services (DNS-based discovery)"

    local output_file="$OUTPUT_DIR/all_services.json"
    local output_txt="$OUTPUT_DIR/all_services.txt"

    kubectl get services -A -o json > "$output_file" 2>/dev/null || \
        echo '{"items":[]}' > "$output_file"

    # Create a readable format with DNS names
    echo "=== All Kubernetes Services ===" > "$output_txt"
    echo "Format: <service-name>.<namespace>.svc.cluster.local" >> "$output_txt"
    echo "" >> "$output_txt"

    kubectl get services -A -o custom-columns=\
NAMESPACE:.metadata.namespace,\
NAME:.metadata.name,\
TYPE:.spec.type,\
CLUSTER-IP:.spec.clusterIP,\
PORTS:.spec.ports[*].port,\
DNS:"<NAME>.<NAMESPACE>.svc.cluster.local" \
        >> "$output_txt" 2>/dev/null || true

    log_info "  Services saved to: $output_file and $output_txt"
}

#==============================================================================
# Method 8: Database Connections from Secrets
# Look for database-related secrets (metadata only, no actual secrets)
#==============================================================================
discover_database_secrets() {
    log_info "Method 8: Discovering database connection secrets (metadata only)"

    local output_file="$OUTPUT_DIR/database_secrets_metadata.txt"

    echo "=== Database-related Secrets (Metadata Only) ===" > "$output_file"
    echo "Timestamp: $TIMESTAMP" >> "$output_file"
    echo "" >> "$output_file"

    for ns in "${NAMESPACES[@]}"; do
        echo "=== Namespace: $ns ===" >> "$output_file"

        kubectl get secrets -n "$ns" -o name 2>/dev/null | \
            grep -E "(db|mysql|postgres|mongo|redis|database|rds|elasticache)" >> "$output_file" || true

        echo "" >> "$output_file"
    done

    log_info "  Database secrets metadata saved to: $output_file"
}

#==============================================================================
# Main Execution
#==============================================================================
main() {
    log_info "Phase 3: Service Dependency Discovery"
    log_info "========================================"
    echo ""

    # Discover DNS-based services first (foundation)
    discover_dns_services
    echo ""

    # Discover service mesh configurations
    discover_service_mesh
    echo ""

    # Discover network policies
    discover_network_policies
    echo ""

    # Discover service endpoints
    discover_service_endpoints
    echo ""

    # For each namespace, discover dependencies
    for ns in "${NAMESPACES[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            echo ""
            log_info "Analyzing namespace: $ns"
            echo "----------------------------------------"

            discover_env_dependencies "$ns"
            discover_configmap_dependencies "$ns"
            discover_deployment_dependencies "$ns"
        else
            log_warn "Namespace $ns does not exist, skipping..."
        fi
    done

    echo ""
    discover_database_secrets

    echo ""
    log_info "Service dependency discovery complete!"
    log_info "Data saved to: $OUTPUT_DIR"

    # Generate quick summary
    echo ""
    log_info "Quick Summary:"
    log_info "=============="

    local total_services=$(kubectl get services -A --no-headers 2>/dev/null | wc -l || echo "0")
    log_info "Total Services: $total_services"

    local virtual_services=$(kubectl get virtualservices -A --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$virtual_services" -gt 0 ]; then
        log_info "Istio VirtualServices: $virtual_services (Service Mesh DETECTED)"
    else
        log_info "Istio VirtualServices: 0 (No service mesh detected)"
    fi

    local network_policies=$(kubectl get networkpolicies -A --no-headers 2>/dev/null | wc -l || echo "0")
    log_info "Network Policies: $network_policies"

    echo ""
    log_info "Next steps:"
    log_info "1. Run ./04_collect_external_resources.sh to discover AWS resources"
    log_info "2. Run ./05_analyze_data.py to parse and structure all collected data"
}

main

#!/bin/bash
#
# Luckin Coffee K8s Data Collection - Master Script
# Runs all data collection and analysis scripts in sequence
#
# Usage: ./run_all.sh [--skip-clusters] [--skip-external] [--analyze-only]
#

set -euo pipefail

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

# Parse command line arguments
SKIP_CLUSTERS=false
SKIP_EXTERNAL=false
ANALYZE_ONLY=false

for arg in "$@"; do
    case $arg in
        --skip-clusters)
            SKIP_CLUSTERS=true
            ;;
        --skip-external)
            SKIP_EXTERNAL=true
            ;;
        --analyze-only)
            ANALYZE_ONLY=true
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --skip-clusters    Skip cluster data collection"
            echo "  --skip-external    Skip external AWS resources collection"
            echo "  --analyze-only     Only run data analysis (requires data already collected)"
            echo "  --help             Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown argument: $arg"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Banner
echo ""
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║  Luckin Coffee North America - Kubernetes Architecture Analysis   ║"
echo "║  Data Collection & Analysis Pipeline                              ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
log_info "Started at: $(date)"
log_info "Timestamp: $TIMESTAMP"
echo ""

# Create log directory
LOG_DIR="../logs"
mkdir -p "$LOG_DIR"
MAIN_LOG="$LOG_DIR/run_all_${TIMESTAMP}.log"

# Function to run a script with logging
run_script() {
    local script_name=$1
    local log_file="$LOG_DIR/${script_name%.sh}_${TIMESTAMP}.log"

    log_step "Running: $script_name"

    if [ ! -f "$script_name" ]; then
        log_error "Script not found: $script_name"
        return 1
    fi

    chmod +x "$script_name"

    if ./"$script_name" 2>&1 | tee "$log_file"; then
        log_info "✓ Completed: $script_name"
        echo ""
        return 0
    else
        log_error "✗ Failed: $script_name"
        log_error "Check log: $log_file"
        echo ""
        return 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."

    local missing_tools=()

    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi

    if ! command -v aws &> /dev/null && [ "$SKIP_EXTERNAL" = false ]; then
        log_warn "aws CLI not found - external resources will be skipped"
        SKIP_EXTERNAL=true
    fi

    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi

    if ! command -v python3 &> /dev/null; then
        missing_tools+=("python3")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install missing tools and try again"
        return 1
    fi

    # Verify kubectl access
    if [ "$SKIP_CLUSTERS" = false ] && [ "$ANALYZE_ONLY" = false ]; then
        if ! kubectl cluster-info &> /dev/null; then
            log_error "Cannot connect to Kubernetes cluster"
            log_error "Please configure kubectl and ensure you have cluster access"
            return 1
        fi
    fi

    log_info "✓ All prerequisites met"
    echo ""
}

# Main execution
main() {
    # Check prerequisites
    if ! check_prerequisites; then
        exit 1
    fi

    local failed_scripts=()

    if [ "$ANALYZE_ONLY" = false ]; then
        # Phase 1: Cluster Data Collection
        if [ "$SKIP_CLUSTERS" = false ]; then
            log_step "═══════════════════════════════════════════════════════════"
            log_step "Phase 1: Cluster & Node Data Collection"
            log_step "═══════════════════════════════════════════════════════════"
            echo ""

            if ! run_script "01_collect_cluster_data.sh"; then
                failed_scripts+=("01_collect_cluster_data.sh")
            fi
        else
            log_info "Skipping cluster data collection (--skip-clusters)"
            echo ""
        fi

        # Phase 2: Namespace Data Collection
        log_step "═══════════════════════════════════════════════════════════"
        log_step "Phase 2: Namespace & Workload Data Collection"
        log_step "═══════════════════════════════════════════════════════════"
        echo ""

        if ! run_script "02_collect_namespace_data.sh"; then
            failed_scripts+=("02_collect_namespace_data.sh")
        fi

        # Phase 3: Service Dependencies
        log_step "═══════════════════════════════════════════════════════════"
        log_step "Phase 3: Service Dependency Discovery (CRITICAL)"
        log_step "═══════════════════════════════════════════════════════════"
        echo ""

        if ! run_script "03_collect_service_dependencies.sh"; then
            failed_scripts+=("03_collect_service_dependencies.sh")
        fi

        # Phase 4: External Resources
        if [ "$SKIP_EXTERNAL" = false ]; then
            log_step "═══════════════════════════════════════════════════════════"
            log_step "Phase 4: External AWS Resources Discovery"
            log_step "═══════════════════════════════════════════════════════════"
            echo ""

            if ! run_script "04_collect_external_resources.sh"; then
                failed_scripts+=("04_collect_external_resources.sh")
                log_warn "External resources collection failed, but continuing..."
            fi
        else
            log_info "Skipping external resources collection (--skip-external)"
            echo ""
        fi
    else
        log_info "Skipping data collection (--analyze-only)"
        echo ""
    fi

    # Phase 5: Data Analysis
    log_step "═══════════════════════════════════════════════════════════"
    log_step "Phase 5: Data Analysis & Summary Generation"
    log_step "═══════════════════════════════════════════════════════════"
    echo ""

    if ! run_script "05_analyze_data.py"; then
        failed_scripts+=("05_analyze_data.py")
    fi

    # Summary
    echo ""
    log_step "═══════════════════════════════════════════════════════════"
    log_step "Execution Summary"
    log_step "═══════════════════════════════════════════════════════════"
    echo ""

    if [ ${#failed_scripts[@]} -eq 0 ]; then
        log_info "✓ All scripts completed successfully!"
    else
        log_error "✗ Some scripts failed:"
        for script in "${failed_scripts[@]}"; do
            log_error "  - $script"
        done
        echo ""
        log_info "Check individual log files in: $LOG_DIR"
    fi

    echo ""
    log_info "Data collection and analysis complete!"
    log_info "Next steps:"
    log_info "  1. Review the generated architecture_summary.json"
    log_info "  2. Run ./06_push_to_github.sh to push results to GitHub"
    log_info "  3. Update visualization components with real data"

    echo ""
    log_info "Completed at: $(date)"

    # Return non-zero if any script failed
    if [ ${#failed_scripts[@]} -gt 0 ]; then
        return 1
    fi
    return 0
}

# Run main with all output logged
main 2>&1 | tee "$MAIN_LOG"
exit_code=${PIPESTATUS[0]}

echo ""
log_info "Full execution log saved to: $MAIN_LOG"

exit $exit_code

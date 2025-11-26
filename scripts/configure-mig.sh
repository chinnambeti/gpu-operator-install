#!/bin/bash
#
# MIG Configuration Script for RTX 6000 Pro
# This script helps manage MIG configurations on nodes
#

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

usage() {
    cat << EOF
Usage: $(basename "$0") <command> [options]

Commands:
  apply <node> <profile>    Apply MIG configuration to a node
  disable <node>            Disable MIG on a node
  status [node]             Show MIG status (all nodes or specific node)
  list-profiles             List available MIG profiles
  validate                  Validate MIG configuration
  help                      Show this help message

MIG Profiles:
  all-disabled          No MIG partitioning
  all-balanced          Balanced workload configuration
  all-1g                Memory-optimized (multiple small instances)
  all-2g                Compute-intensive configuration
  mixed-profile         Mixed workload configuration
  training-optimized    AI/ML training optimized
  inference-optimized   Inference serving optimized

Examples:
  $(basename "$0") apply worker-gpu-1 all-balanced
  $(basename "$0") status
  $(basename "$0") disable worker-gpu-1

EOF
}

list_profiles() {
    log_header "Available MIG Profiles for RTX 6000 Pro"
    echo ""
    echo "Profile Name         | Description"
    echo "---------------------|------------------------------------------"
    echo "all-disabled         | MIG disabled, full GPU access"
    echo "all-balanced         | Balanced config with 3g.24gb profile"
    echo "all-1g               | 7x 1g.6gb instances for parallel workloads"
    echo "all-2g               | 3x 2g.12gb instances"
    echo "mixed-profile        | Mixed configuration per GPU"
    echo "training-optimized   | Optimized for ML training (4g.24gb + 1g.6gb)"
    echo "inference-optimized  | Multiple small instances for inference"
    echo ""
}

apply_mig_config() {
    local node="$1"
    local profile="$2"
    
    log_info "Applying MIG profile '${profile}' to node '${node}'..."
    
    # Validate profile exists
    local valid_profiles="all-disabled all-balanced all-1g all-2g mixed-profile training-optimized inference-optimized"
    if ! echo "${valid_profiles}" | grep -qw "${profile}"; then
        log_error "Invalid profile: ${profile}"
        log_info "Valid profiles: ${valid_profiles}"
        exit 1
    fi
    
    # Apply label to node
    kubectl label node "${node}" nvidia.com/mig.config="${profile}" --overwrite
    
    log_info "MIG configuration applied. The MIG manager will reconfigure the GPUs."
    log_info "This may take a few minutes. Monitor with: kubectl get pods -n gpu-operator -w"
}

disable_mig() {
    local node="$1"
    
    log_info "Disabling MIG on node '${node}'..."
    kubectl label node "${node}" nvidia.com/mig.config=all-disabled --overwrite
    log_info "MIG disabled. GPUs will be available as full devices."
}

show_status() {
    local node="${1:-}"
    
    log_header "MIG Configuration Status"
    echo ""
    
    if [[ -n "${node}" ]]; then
        log_info "Showing status for node: ${node}"
        kubectl get node "${node}" -o jsonpath='{.metadata.labels}' | tr ',' '\n' | grep nvidia || true
        echo ""
        kubectl describe node "${node}" | grep -A 20 "Allocated resources:" || true
    else
        log_info "Showing MIG status for all GPU nodes"
        echo ""
        kubectl get nodes -l nvidia.com/gpu.present=true -o custom-columns=\
'NAME:.metadata.name,MIG-CONFIG:.metadata.labels.nvidia\.com/mig\.config,GPU-COUNT:.status.capacity.nvidia\.com/gpu' 2>/dev/null || \
        kubectl get nodes -o custom-columns=\
'NAME:.metadata.name,MIG-CONFIG:.metadata.labels.nvidia\.com/mig\.config' 2>/dev/null
    fi
    
    echo ""
    log_info "GPU Operator Pods:"
    kubectl get pods -n gpu-operator -l app.kubernetes.io/component=gpu-operator 2>/dev/null || \
    kubectl get pods -n gpu-operator 2>/dev/null || echo "No pods found"
}

validate_config() {
    log_header "Validating MIG Configuration"
    
    # Check GPU Operator is installed
    log_info "Checking GPU Operator installation..."
    if kubectl get deployment -n gpu-operator gpu-operator &>/dev/null; then
        echo "  ✓ GPU Operator deployment found"
    else
        echo "  ✗ GPU Operator deployment not found"
    fi
    
    # Check MIG Manager
    log_info "Checking MIG Manager..."
    if kubectl get daemonset -n gpu-operator nvidia-mig-manager &>/dev/null; then
        echo "  ✓ MIG Manager DaemonSet found"
    else
        echo "  ! MIG Manager DaemonSet not found (may have different name)"
    fi
    
    # Check MIG ConfigMap
    log_info "Checking MIG Configuration ConfigMap..."
    if kubectl get configmap -n gpu-operator mig-parted-config &>/dev/null; then
        echo "  ✓ MIG parted config found"
    else
        echo "  ! MIG parted config not found"
        log_warn "Apply the MIG configuration with: kubectl apply -f configs/mig-config-rtx6000-pro.yaml"
    fi
    
    # Check GPU nodes
    log_info "Checking GPU nodes..."
    local gpu_nodes
    gpu_nodes=$(kubectl get nodes -l nvidia.com/gpu.present=true -o name 2>/dev/null | wc -l || echo 0)
    if [[ "${gpu_nodes}" -gt 0 ]]; then
        echo "  ✓ Found ${gpu_nodes} GPU node(s)"
    else
        echo "  ! No GPU nodes found with label nvidia.com/gpu.present=true"
    fi
    
    echo ""
    log_info "Validation complete"
}

# Main
case "${1:-help}" in
    apply)
        if [[ $# -lt 3 ]]; then
            log_error "Missing arguments for 'apply' command"
            echo "Usage: $(basename "$0") apply <node> <profile>"
            exit 1
        fi
        apply_mig_config "$2" "$3"
        ;;
    disable)
        if [[ $# -lt 2 ]]; then
            log_error "Missing node argument for 'disable' command"
            echo "Usage: $(basename "$0") disable <node>"
            exit 1
        fi
        disable_mig "$2"
        ;;
    status)
        show_status "${2:-}"
        ;;
    list-profiles)
        list_profiles
        ;;
    validate)
        validate_config
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        log_error "Unknown command: $1"
        usage
        exit 1
        ;;
esac

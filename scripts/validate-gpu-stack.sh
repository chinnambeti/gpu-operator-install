#!/bin/bash
#
# Validation Script for NVIDIA GPU Stack
# Validates GPU operator installation and MIG configuration
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
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

check_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "  ${RED}✗${NC} $1"
}

check_warn() {
    echo -e "  ${YELLOW}!${NC} $1"
}

NAMESPACE="${NAMESPACE:-gpu-operator}"
ERRORS=0
WARNINGS=0

validate_kubernetes() {
    log_header "Kubernetes Cluster Validation"
    
    # Check kubectl connectivity
    if kubectl cluster-info &>/dev/null; then
        check_pass "Kubernetes cluster is accessible"
    else
        check_fail "Cannot connect to Kubernetes cluster"
        ((ERRORS++))
        return 1
    fi
    
    # Check Kubernetes version
    local k8s_version
    k8s_version=$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')
    check_pass "Kubernetes client version: ${k8s_version}"
}

validate_namespace() {
    log_header "Namespace Validation"
    
    if kubectl get namespace "${NAMESPACE}" &>/dev/null; then
        check_pass "Namespace '${NAMESPACE}' exists"
    else
        check_fail "Namespace '${NAMESPACE}' does not exist"
        ((ERRORS++))
    fi
}

validate_gpu_operator() {
    log_header "GPU Operator Validation"
    
    # Check GPU Operator deployment
    if kubectl get deployment -n "${NAMESPACE}" -l app.kubernetes.io/component=gpu-operator &>/dev/null; then
        local ready
        ready=$(kubectl get deployment -n "${NAMESPACE}" -l app.kubernetes.io/component=gpu-operator -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null || echo "0")
        if [[ "${ready}" -gt 0 ]]; then
            check_pass "GPU Operator deployment is running (${ready} replicas ready)"
        else
            check_fail "GPU Operator deployment not ready"
            ((ERRORS++))
        fi
    else
        check_warn "GPU Operator deployment not found (may use different labels)"
        ((WARNINGS++))
    fi
    
    # Check all operator pods using jsonpath for reliable parsing
    log_info "Checking GPU Operator pods..."
    local pod_json
    pod_json=$(kubectl get pods -n "${NAMESPACE}" -o json 2>/dev/null || echo '{"items":[]}')
    local pod_count
    pod_count=$(echo "${pod_json}" | jq -r '.items | length')
    
    if [[ "${pod_count}" -gt 0 ]]; then
        echo "${pod_json}" | jq -r '.items[] | "\(.metadata.name) \(.status.phase)"' | while read -r name status; do
            if [[ "${status}" == "Running" || "${status}" == "Succeeded" ]]; then
                check_pass "Pod ${name}: ${status}"
            else
                check_warn "Pod ${name}: ${status}"
            fi
        done
    else
        check_fail "No pods found in ${NAMESPACE}"
        ((ERRORS++))
    fi
}

validate_nvidia_driver() {
    log_header "NVIDIA Driver Validation"
    
    # Check NVIDIA driver daemonset
    if kubectl get daemonset -n "${NAMESPACE}" -l app=nvidia-driver-daemonset &>/dev/null 2>&1; then
        local desired ready
        desired=$(kubectl get daemonset -n "${NAMESPACE}" -l app=nvidia-driver-daemonset -o jsonpath='{.items[0].status.desiredNumberScheduled}' 2>/dev/null || echo "0")
        ready=$(kubectl get daemonset -n "${NAMESPACE}" -l app=nvidia-driver-daemonset -o jsonpath='{.items[0].status.numberReady}' 2>/dev/null || echo "0")
        if [[ "${ready}" -eq "${desired}" && "${desired}" -gt 0 ]]; then
            check_pass "NVIDIA Driver DaemonSet: ${ready}/${desired} ready"
        else
            check_warn "NVIDIA Driver DaemonSet: ${ready}/${desired} ready"
            ((WARNINGS++))
        fi
    else
        check_warn "NVIDIA Driver DaemonSet not found (driver may be pre-installed)"
        ((WARNINGS++))
    fi
}

validate_device_plugin() {
    log_header "Device Plugin Validation"
    
    # Check device plugin
    if kubectl get daemonset -n "${NAMESPACE}" nvidia-device-plugin-daemonset &>/dev/null 2>&1; then
        local desired ready
        desired=$(kubectl get daemonset -n "${NAMESPACE}" nvidia-device-plugin-daemonset -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
        ready=$(kubectl get daemonset -n "${NAMESPACE}" nvidia-device-plugin-daemonset -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
        check_pass "NVIDIA Device Plugin DaemonSet: ${ready}/${desired} ready"
    else
        check_warn "NVIDIA Device Plugin DaemonSet not found"
        ((WARNINGS++))
    fi
}

validate_mig_manager() {
    log_header "MIG Manager Validation"
    
    # Check MIG Manager
    if kubectl get daemonset -n "${NAMESPACE}" nvidia-mig-manager &>/dev/null 2>&1; then
        local desired ready
        desired=$(kubectl get daemonset -n "${NAMESPACE}" nvidia-mig-manager -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
        ready=$(kubectl get daemonset -n "${NAMESPACE}" nvidia-mig-manager -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
        check_pass "MIG Manager DaemonSet: ${ready}/${desired} ready"
    else
        check_warn "MIG Manager DaemonSet not found"
        ((WARNINGS++))
    fi
    
    # Check MIG config
    if kubectl get configmap -n "${NAMESPACE}" mig-parted-config &>/dev/null; then
        check_pass "MIG configuration ConfigMap exists"
    else
        check_warn "MIG configuration ConfigMap not found"
        ((WARNINGS++))
    fi
}

validate_dcgm() {
    log_header "DCGM Validation"
    
    # Check DCGM Exporter
    if kubectl get daemonset -n "${NAMESPACE}" nvidia-dcgm-exporter &>/dev/null 2>&1; then
        local desired ready
        desired=$(kubectl get daemonset -n "${NAMESPACE}" nvidia-dcgm-exporter -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
        ready=$(kubectl get daemonset -n "${NAMESPACE}" nvidia-dcgm-exporter -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
        check_pass "DCGM Exporter DaemonSet: ${ready}/${desired} ready"
    else
        check_warn "DCGM Exporter DaemonSet not found"
        ((WARNINGS++))
    fi
}

validate_gpu_resources() {
    log_header "GPU Resource Validation"
    
    # Check for GPU resources on nodes
    log_info "Checking GPU resources on nodes..."
    
    local gpu_nodes
    gpu_nodes=$(kubectl get nodes -o json | jq -r '.items[] | select(.status.capacity["nvidia.com/gpu"] != null) | .metadata.name' 2>/dev/null || echo "")
    
    if [[ -n "${gpu_nodes}" ]]; then
        echo "${gpu_nodes}" | while read -r node; do
            local gpu_count mig_config
            gpu_count=$(kubectl get node "${node}" -o jsonpath='{.status.capacity.nvidia\.com/gpu}' 2>/dev/null || echo "0")
            mig_config=$(kubectl get node "${node}" -o jsonpath='{.metadata.labels.nvidia\.com/mig\.config}' 2>/dev/null || echo "not set")
            check_pass "Node ${node}: ${gpu_count} GPU(s), MIG config: ${mig_config}"
        done
    else
        check_warn "No nodes with nvidia.com/gpu resource found"
        ((WARNINGS++))
    fi
}

validate_gpu_feature_discovery() {
    log_header "GPU Feature Discovery Validation"
    
    # Check GFD
    if kubectl get daemonset -n "${NAMESPACE}" gpu-feature-discovery &>/dev/null 2>&1; then
        local desired ready
        desired=$(kubectl get daemonset -n "${NAMESPACE}" gpu-feature-discovery -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
        ready=$(kubectl get daemonset -n "${NAMESPACE}" gpu-feature-discovery -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
        check_pass "GPU Feature Discovery DaemonSet: ${ready}/${desired} ready"
    else
        check_warn "GPU Feature Discovery DaemonSet not found"
        ((WARNINGS++))
    fi
}

print_summary() {
    log_header "Validation Summary"
    
    if [[ ${ERRORS} -eq 0 && ${WARNINGS} -eq 0 ]]; then
        echo -e "${GREEN}All checks passed!${NC}"
    else
        if [[ ${ERRORS} -gt 0 ]]; then
            echo -e "${RED}Errors: ${ERRORS}${NC}"
        fi
        if [[ ${WARNINGS} -gt 0 ]]; then
            echo -e "${YELLOW}Warnings: ${WARNINGS}${NC}"
        fi
    fi
    
    echo ""
    if [[ ${ERRORS} -gt 0 ]]; then
        log_error "Validation failed with ${ERRORS} error(s)"
        exit 1
    fi
}

main() {
    log_info "Starting NVIDIA GPU Stack validation..."
    
    validate_kubernetes
    validate_namespace
    validate_gpu_operator
    validate_nvidia_driver
    validate_device_plugin
    validate_mig_manager
    validate_dcgm
    validate_gpu_feature_discovery
    validate_gpu_resources
    print_summary
}

main "$@"

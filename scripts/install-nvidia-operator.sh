#!/bin/bash
#
# NVIDIA GPU Operator Installation Script
# This script installs the NVIDIA GPU Operator on a Kubernetes cluster
# with support for MIG (Multi-Instance GPU) configuration
#

set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-gpu-operator}"
HELM_RELEASE_NAME="${HELM_RELEASE_NAME:-gpu-operator}"
GPU_OPERATOR_VERSION="${GPU_OPERATOR_VERSION:-v24.6.1}"

# Color output
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

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed. Please install helm first."
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    
    log_info "All prerequisites met."
}

add_nvidia_helm_repo() {
    log_info "Adding NVIDIA Helm repository..."
    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia 2>/dev/null || true
    helm repo update
}

create_namespace() {
    log_info "Creating namespace: ${NAMESPACE}..."
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
}

install_node_feature_discovery() {
    log_info "Installing Node Feature Discovery (NFD)..."
    
    # NFD is required for GPU detection
    # Note: NFD version is pinned to a specific release for security
    # GPU Operator can also install NFD automatically (recommended)
    local NFD_VERSION="v0.15.4"
    local NFD_MANIFEST_URL="https://raw.githubusercontent.com/kubernetes-sigs/node-feature-discovery/${NFD_VERSION}/deployment/node-feature-discovery.yaml"
    
    log_warn "Downloading NFD manifest from external URL. Consider using GPU Operator's built-in NFD for production."
    log_info "NFD Version: ${NFD_VERSION}"
    
    kubectl apply -f "${NFD_MANIFEST_URL}" || {
        log_warn "NFD might already be installed or will be installed by GPU Operator"
    }
}

install_gpu_operator() {
    log_info "Installing NVIDIA GPU Operator ${GPU_OPERATOR_VERSION}..."
    
    helm upgrade --install "${HELM_RELEASE_NAME}" nvidia/gpu-operator \
        --namespace "${NAMESPACE}" \
        --version "${GPU_OPERATOR_VERSION}" \
        --set driver.enabled=true \
        --set toolkit.enabled=true \
        --set devicePlugin.enabled=true \
        --set migManager.enabled=true \
        --set migManager.default=all-disabled \
        --set mig.strategy=mixed \
        --set dcgm.enabled=true \
        --set dcgmExporter.enabled=true \
        --set gfd.enabled=true \
        --set operator.defaultRuntime=containerd \
        --wait \
        --timeout 10m
    
    log_info "GPU Operator installed successfully."
}

verify_installation() {
    log_info "Verifying GPU Operator installation..."
    
    # Wait for pods to be ready
    kubectl wait --for=condition=ready pod \
        -l app=gpu-operator \
        -n "${NAMESPACE}" \
        --timeout=300s || {
        log_warn "Some pods may still be initializing. Check manually with: kubectl get pods -n ${NAMESPACE}"
    }
    
    # Show installed components
    echo ""
    log_info "Installed components:"
    kubectl get pods -n "${NAMESPACE}"
}

main() {
    log_info "Starting NVIDIA GPU Operator installation..."
    
    check_prerequisites
    add_nvidia_helm_repo
    create_namespace
    install_node_feature_discovery
    install_gpu_operator
    verify_installation
    
    echo ""
    log_info "Installation complete!"
    log_info "Next steps:"
    echo "  1. Apply MIG configuration: kubectl apply -f configs/mig-config-rtx6000-pro.yaml"
    echo "  2. Label nodes for MIG: kubectl label node <node-name> nvidia.com/mig.config=all-balanced"
    echo "  3. Verify GPU resources: kubectl describe nodes | grep nvidia.com"
}

main "$@"

# NVIDIA GPU Operator Installation with MIG Support for RTX 6000 Pro

This repository provides comprehensive scripts and configurations for installing and configuring the NVIDIA GPU Operator on Kubernetes with Multi-Instance GPU (MIG) support for RTX 6000 Pro GPUs.

## Overview

The NVIDIA GPU Operator simplifies the deployment and management of GPU-accelerated workloads on Kubernetes. This repository includes:

- **GPU Operator Installation**: Automated Helm-based installation
- **MIG Configuration**: Pre-configured MIG profiles for RTX 6000 Pro
- **NVIDIA Blueprint**: Complete AI stack configuration with monitoring
- **Validation Tools**: Scripts to verify the installation

## Prerequisites

- Kubernetes cluster v1.26+
- Helm v3.x
- `kubectl` configured with cluster access
- NVIDIA RTX 6000 Pro GPU(s) on worker nodes
- Container runtime: containerd (recommended) or Docker

## Quick Start

### 1. Install the GPU Operator

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Install NVIDIA GPU Operator
./scripts/install-nvidia-operator.sh
```

### 2. Apply MIG Configuration

```bash
# Apply MIG configuration for RTX 6000 Pro
kubectl apply -f configs/mig-config-rtx6000-pro.yaml

# Configure a node with MIG profile
./scripts/configure-mig.sh apply <node-name> all-balanced
```

### 3. Deploy NVIDIA Blueprint (Optional)

```bash
# Apply the full NVIDIA blueprint with monitoring
kubectl apply -f manifests/nvidia-blueprint.yaml
```

### 4. Validate Installation

```bash
# Run validation script
./scripts/validate-gpu-stack.sh
```

## Directory Structure

```
├── configs/
│   ├── mig-config-rtx6000-pro.yaml  # MIG profiles for RTX 6000 Pro
│   └── values-rtx6000-pro.yaml       # Helm values for GPU Operator
├── manifests/
│   ├── gpu-operator-base.yaml        # Base Kubernetes resources
│   ├── nvidia-blueprint.yaml         # Complete NVIDIA AI stack
│   └── test-workloads.yaml           # Sample GPU workloads
├── scripts/
│   ├── install-nvidia-operator.sh    # GPU Operator installation
│   ├── configure-mig.sh              # MIG configuration utility
│   └── validate-gpu-stack.sh         # Validation script
└── README.md
```

## MIG Profiles for RTX 6000 Pro

The RTX 6000 Pro (Ada Lovelace architecture) supports MIG partitioning. Available profiles:

| Profile | Description | Use Case |
|---------|-------------|----------|
| `all-disabled` | MIG disabled | Full GPU access |
| `all-balanced` | 3g.24gb instance | Balanced workloads |
| `all-1g` | 7x 1g.6gb instances | Parallel inference |
| `all-2g` | 3x 2g.12gb instances | Medium workloads |
| `training-optimized` | 4g.24gb + 2x 1g.6gb | ML training |
| `inference-optimized` | 7x 1g.6gb | Inference serving |

### Applying MIG Configuration

```bash
# List available profiles
./scripts/configure-mig.sh list-profiles

# Apply a profile to a node
./scripts/configure-mig.sh apply worker-gpu-1 all-balanced

# Check MIG status
./scripts/configure-mig.sh status

# Disable MIG
./scripts/configure-mig.sh disable worker-gpu-1
```

## Components Installed

The GPU Operator deploys the following components:

- **NVIDIA Driver** - GPU kernel driver (or use pre-installed)
- **NVIDIA Container Toolkit** - Runtime support for GPU containers
- **NVIDIA Device Plugin** - Kubernetes device plugin for GPUs
- **MIG Manager** - Multi-Instance GPU configuration manager
- **DCGM Exporter** - GPU metrics for Prometheus
- **GPU Feature Discovery** - Node labeling with GPU features
- **Node Feature Discovery** - Hardware feature detection

## NVIDIA Blueprint

The NVIDIA Blueprint (`manifests/nvidia-blueprint.yaml`) provides:

- Namespace and RBAC configuration
- GPU monitoring with Prometheus ServiceMonitor
- Alerting rules for GPU health
- Grafana dashboard for GPU metrics
- Device plugin time-slicing configuration

## Testing GPU Workloads

Deploy test workloads to verify GPU access:

```bash
# Deploy test workloads
kubectl apply -f manifests/test-workloads.yaml

# Check CUDA vector add test
kubectl logs -n gpu-operator cuda-vector-add

# Run nvidia-smi check
kubectl logs -n gpu-operator nvidia-smi-check

# Test PyTorch GPU access
kubectl logs -n gpu-operator -l app=pytorch-test
```

## Custom Installation

For custom configurations, modify the Helm values:

```bash
# Install with custom values
helm upgrade --install gpu-operator nvidia/gpu-operator \
  -n gpu-operator --create-namespace \
  -f configs/values-rtx6000-pro.yaml
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NAMESPACE` | gpu-operator | Kubernetes namespace |
| `GPU_OPERATOR_VERSION` | v24.6.1 | GPU Operator version |
| `HELM_RELEASE_NAME` | gpu-operator | Helm release name |

## Monitoring

GPU metrics are exposed via DCGM Exporter. Key metrics include:

- `DCGM_FI_DEV_GPU_TEMP` - GPU temperature
- `DCGM_FI_DEV_GPU_UTIL` - GPU utilization
- `DCGM_FI_DEV_FB_USED` - Frame buffer memory used
- `DCGM_FI_DEV_FB_FREE` - Frame buffer memory free
- `DCGM_FI_DEV_POWER_USAGE` - Power consumption
- `DCGM_FI_DEV_MIG_MODE` - MIG mode status

## Troubleshooting

### Common Issues

1. **GPU not detected**
   ```bash
   kubectl describe nodes | grep nvidia.com
   kubectl get pods -n gpu-operator
   ```

2. **MIG configuration not applying**
   ```bash
   kubectl logs -n gpu-operator -l app=nvidia-mig-manager
   ./scripts/configure-mig.sh validate
   ```

3. **Driver installation issues**
   ```bash
   kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset
   ```

### Validation

Run the validation script to check all components:

```bash
./scripts/validate-gpu-stack.sh
```

## References

- [NVIDIA GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/)
- [MIG User Guide](https://docs.nvidia.com/datacenter/tesla/mig-user-guide/)
- [NVIDIA Container Toolkit](https://github.com/NVIDIA/nvidia-container-toolkit)
- [DCGM Documentation](https://docs.nvidia.com/datacenter/dcgm/latest/)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
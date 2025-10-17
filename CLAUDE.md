# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository provisions a **management** Azure Kubernetes Service (AKS) cluster for deploying shared organizational resources. The infrastructure is defined using Terraform and follows Azure best practices for security and cost optimization.

## Prerequisites

- terraform (>= 1.11.4)
- tflint
- gitleaks
- checkov
- direnv
- infracost
- kubelogin (for AKS authentication)
- jq (for pre-commit hook cost validation)

## Initial Setup

1. **Configure Git hooks**: Run `./init-dev.sh` to set up pre-commit hooks
2. **Set environment variables**:
   - Create `infrastructure/.env` with Azure credentials (ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_SUBSCRIPTION_ID, ARM_TENANT_ID)
   - Run `direnv allow` in the `infrastructure/` directory to auto-load credentials

## Common Commands

### Terraform Operations

All Terraform commands should be run from the `infrastructure/` directory:

```bash
cd infrastructure/

# Initialize and upgrade providers
terraform init -upgrade

# Validate configuration
terraform validate

# Format all Terraform files
terraform fmt -recursive

# Plan changes
terraform plan

# Apply changes
terraform apply

# Destroy infrastructure
terraform destroy
```

### Testing and Validation

```bash
# Run Gitleaks (secrets scanning) from root
gitleaks dir -v --config gitleaks.toml

# Run Tflint (linting) from root
tflint --chdir=infrastructure/

# Run Checkov (security scanning) from root
checkov --framework terraform -d infrastructure

# Check cost forecast from infrastructure/
cd infrastructure/
infracost breakdown --path . --format json
```

### Kubernetes Access

```bash
# Access Hubble UI for network observability
kubectl port-forward -n kube-system svc/hubble-ui 12000:80
# Then open http://localhost:12000
```

## Architecture Overview

### Core Infrastructure Components

1. **AKS Cluster** (`aks.tf`): The central Kubernetes cluster with:

   - Cilium CNI for networking (Azure CNI mode with network policy and data plane)
   - Cilium observability and security features enabled
   - Azure RBAC integration (local accounts disabled)
   - Disk encryption using Azure Disk Encryption Set
   - Log Analytics integration for monitoring
   - Single node pool (cost optimization)
   - API server restricted to whitelisted IPs

2. **Networking** (`vnet.tf`):

   - VNet with 10.0.0.0/16 address space
   - **Separate subnets for nodes and pods** (Azure CNI overlay pattern):
     - Node subnet (10.0.0.0/22): ~1000 node capacity
     - Pod subnet (10.0.16.0/20): ~4000 IP capacity, delegated to AKS

3. **Security** (`key-vault.tf`, `disk-encryption-set.tf`):

   - Azure Key Vault (Premium SKU with HSM) for encryption keys
   - Disk Encryption Set for AKS node encryption at rest
   - Network ACLs on Key Vault limiting access to whitelisted IPs
   - RBAC-based Key Vault authorization

4. **Kubernetes Providers** (`provider.tf`):

   - Uses `kubelogin` exec plugin for dynamic Azure AD authentication
   - Configured for both Kubernetes and Helm providers

5. **Observability** (`hubble-ui.tf`):
   - Hubble UI deployment for Cilium network visualization
   - Deploys service account, configmap, deployment, and service in kube-system namespace

### State Management

- Remote state stored in Azure Storage
- Backend configured in `provider.tf` (update resource group, storage account, and container name as needed)

### Configuration Variables

Key variables in `variables.tf`:

- `project`: Project name (default: "management")
- `location`: Azure region (default: "northeurope")
- `environment`: Environment tag (default: "prod")
- `vm_size`: Node VM size (validated to Standard_D2s_v3)
- **`ip_range_whitelist`**: Critical for Key Vault and AKS API access - must include your IPs

## Pre-commit Hook Workflow

The `.githooks/pre-commit` hook runs automatically before each commit and executes:

1. Gitleaks (secrets scanning)
2. Tflint (Terraform linting)
3. Checkov (security scanning)
4. Terraform fmt (formatting)
5. Terraform init -upgrade
6. Terraform validate
7. Infracost cost check (fails if monthly cost > $100)
8. Auto-stages all changes with `git add .`

**Important**: If any step fails, the commit is aborted. The hook ensures cost limits and security standards are met before code changes.

## Skipped Security Checks

Checkov checks are skipped for cost optimization reasons (documented in `aks.tf`):

- CKV_AZURE_170: Free SKU tier
- CKV_AZURE_232: Single node pool for system and user workloads
- CKV_AZURE_115: Public cluster (no private endpoint)

## Lifecycle Rules

Resources use `lifecycle { ignore_changes = [tags["Creator"]] }` to prevent in-place updates due to tag drift from external sources. This is critical for AKS, which cannot update tags while stopped.

## Azure Feature Requirements

The subscription must have "EncryptionAtHost" feature enabled:

```powershell
Register-AzProviderFeature -FeatureName "EncryptionAtHost" -ProviderNamespace "Microsoft.Compute"
```

## CI/CD Pipelines

Azure Pipelines are defined in `pipelines/`:

- `azure-pipelines-terraform-apply.yml`: Apply infrastructure changes
- `azure-pipelines-terraform-destroy.yml`: Destroy infrastructure

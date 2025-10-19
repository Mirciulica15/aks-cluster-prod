# Introduction

This project aims to provide a **management** Azure Kubernetes Service (AKS) cluster, to be used for deploying common useful resources for the development teams within the organization.

## Documentation

- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Comprehensive technical architecture documentation covering network design, security, and operational details
- **[OBSERVABILITY.md](docs/OBSERVABILITY.md)** - Complete guide to the observability stack (Prometheus, Loki, Tempo, Grafana, OpenTelemetry)
- **[ARGOCD.md](docs/ARGOCD.md)** - GitOps continuous delivery with Argo CD, including multi-tenancy and team onboarding
- **[INGRESS.md](docs/INGRESS.md)** - HTTPS ingress with NGINX, automatic TLS certificates, and Azure AD SSO for all management services
- **[CLAUDE.md](CLAUDE.md)** - Development guide for working with this repository using Claude Code

## License

This is an **open source** project licensed under the [MIT License](LICENSE).

[![MIT License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Getting Started

### Prerequisites

- [terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
- [tflint](https://github.com/terraform-linters/tflint?tab=readme-ov-file#installation)
- [gitleaks](https://github.com/gitleaks/gitleaks?tab=readme-ov-file#installing)
- [checkov](https://www.checkov.io/2.Basics/Installing%20Checkov.html)
- [direnv](https://direnv.net/docs/installation.html)
- [infracost](https://www.infracost.io/docs/)

### Setup Git pre-commit hooks

1. Open Git Bash
2. Run the `./init-dev.sh` script

This will install the pre-commit **hooks**, which can be later enriched/modified from within the **.githooks** directory. Every time you do a commit, the pre-commit will run and if the **exit status** is different than 0, the commit will be **dropped**.

### Setup environment variables

1. Inside the `infrastructure/` directory, create an `.env` file, which is already ignored by .gitignore.
2. Specify your credentials in the `.env` with the following syntax, e.g. `ARM_CLIENT_ID=<your_client_id>`.
3. Once you are finished, run `direnv allow` inside the `infrastructure/` directory.

Now, whenever you `cd` into the `infrastructure/` directory, the environment variables will be **automatically** loaded into your `Git Bash` terminal, and you will be able to run Terraform commands and authenticate against Azure or other providers.

## Infrastructure

The infrastructure can be found in the `infrastructure/` directory. The main resource in the Terraform configuration is the AKS cluster (`aks.tf`).

### Important attributes of the cluster

- private
- uses disk encryption
- ephemeral OS disk
- uses azure CNI
- connected to a Log Analytics Workspace (`log-analytics-workspace.tf`)
- system-assigned identity
- tagged for production

### Skipped checks

Whenever a Checkov check is skipped, it **must be added** to the list below, along with the file it belongs to.

#### AKS Cluster (`aks.tf`)

- CKV_AZURE_170: Intentionally using a free SKU to avoid costs
- CKV_AZURE_232: Intentionally using a single node pool for both system and user workloads to avoid costs
- CKV_AZURE_115: Intentionally not using private cluster to avoid the cost of setting up a Bastion VM or installing a VPN

#### Key Vault (`key-vault.tf`)

- CKV2_AZURE_32: Intentionally using public endpoint with IP whitelist instead of private endpoint to avoid additional networking costs

#### Virtual Network (`vnet.tf`)

- CKV2_AZURE_31 (nodes subnet): AKS manages network security for node subnet; NSG is not required as AKS applies its own security rules
- CKV2_AZURE_31 (pods subnet): AKS manages network security for pod subnet; delegated subnet cannot have NSG as Cilium handles network policies

#### Hubble UI (`hubble-ui.tf`)

- CKV_K8S_43: Using version tags instead of digests for easier updates and readability
- CKV_K8S_30: TODO - Add security context to pods and containers
- CKV_K8S_28: TODO - Drop NET_RAW capability from containers
- CKV_K8S_29: TODO - Apply security context to deployment
- CKV_K8S_15: TODO - Set imagePullPolicy to Always
- CKV_K8S_8: TODO - Add liveness probes to containers
- CKV_K8S_9: TODO - Add readiness probes to containers

### Configuration

Make sure to set the `variables.tf` values according to your needs.

_Note_: The **ip_range_whitelist** is particularly important, make sure to set it to your proper CIDR ranges, in order to be able to access the Key Vault and the AKS API server.

### Common issues

#### 1. Subscription does not support encryption at rest

**Solution**:

```pwsh
Register-AzProviderFeature -FeatureName "EncryptionAtHost" -ProviderNamespace "Microsoft.Compute"
```

You might have to **wait** for the registration to take place. You can check with the following command:

```pwsh
Get-AzProviderFeature -FeatureName "EncryptionAtHost" -ProviderNamespace "Microsoft.Compute"
```

#### 2. Resources updated in-place because of tag drift

Adding **tags** to any of the Azure resources which support them from outside the Terraform configuration will trigger an **in-place update**. Normally, this is **harmless** as your resources will not be destroyed and recreated. However, certain resources, such as **Azure Kubernetes Service**, cannot have their tags updated when they are **stopped**. As a consequence, if your AKS cluster is stopped and Terraform detects a drift in its tags, it will try to update it in-place. Therefore, you will receive a **400 BadRequest** error, claiming that the only action you can take on the AKS cluster, while it is stopped, is to start it.

**Solution**:

Add your specific external tags in the **lifecycle** block for the desired resource/s

```terraform
lifecycle {
  ignore_changes = [tags["Creator"]]
}
```

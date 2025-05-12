# Introduction

This project aims to provide a **management** Azure Kubernetes Service (AKS) cluster, to be used for deploying common useful resources for the development teams within the organization.

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

- CKV_AZURE_170 (`aks.tf`): Intentionally using a free SKU to avoid costs
- CKV_AZURE_232 (`aks.tf`): Intentionally using a single node pool for both system and user workloads to avoid costs
- CKV_AZURE_115 (`aks.tf`): Intentionally not using private cluster to avoid the cost of setting up a Bastion VM or installing a VPN

### Configuration

Make sure to set the `variables.tf` values according to your needs.

_Note_: The **ip_range_whitelist** is particularly important, make sure to set it to your proper CIDR ranges, in order to be able to access the Key Vault and the AKS API server.

### Common issues

#### 1. Subscription does not support encrpytion at rest

Solution:

```pwsh
Register-AzProviderFeature -FeatureName "EncryptionAtHost" -ProviderNamespace "Microsoft.Compute"
```

You might have to **wait** for the registration to take place. You can check with the following command:

```pwsh
Get-AzProviderFeature -FeatureName "EncryptionAtHost" -ProviderNamespace "Microsoft.Compute"
```

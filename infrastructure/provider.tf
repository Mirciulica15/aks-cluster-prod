terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.48.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }

  required_version = ">= 1.11.4"

  backend "azurerm" {
    resource_group_name  = "rg-mircea-talu"
    storage_account_name = "stmirceatalu"
    container_name       = "terraform"
    key                  = "managementcluster.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }
}

# Use exec plugin for dynamic credentials
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.main.kube_config[0].host
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "kubelogin"
    args = [
      "get-token",
      "--environment",
      "AzurePublicCloud",
      "--server-id",
      "6dae42f8-4368-4678-94ff-3960e28e3630", # Azure Kubernetes Service AAD Server
      "--client-id",
      data.azurerm_client_config.current.client_id,
      "--tenant-id",
      data.azurerm_client_config.current.tenant_id,
      "--login",
      "azurecli"
    ]
  }
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.main.kube_config[0].host
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "kubelogin"
      args = [
        "get-token",
        "--environment",
        "AzurePublicCloud",
        "--server-id",
        "6dae42f8-4368-4678-94ff-3960e28e3630",
        "--client-id",
        data.azurerm_client_config.current.client_id,
        "--tenant-id",
        data.azurerm_client_config.current.tenant_id,
        "--login",
        "azurecli"
      ]
    }
  }
}

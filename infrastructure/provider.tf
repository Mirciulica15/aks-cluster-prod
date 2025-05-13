terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.27.0"
    }

    http = {
      source  = "hashicorp/http"
      version = "3.5.0"
    }

    external = {
      source  = "hashicorp/external"
      version = "2.3.5"
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
  features {}
}

provider "http" {}

provider "external" {}

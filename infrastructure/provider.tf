terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.27.0"
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

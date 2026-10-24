terraform {
  required_version = ">= 1.17"

  backend "azurerm" {
    # storage_account_name, resource_group_name, container_name passed via -backend-config.
    # key is stage.tfstate or prod.tfstate, also passed via -backend-config by `just tf-init`.
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.65"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

terraform {
  required_version = ">= 1.17"

  backend "azurerm" {
    # storage_account_name, resource_group_name, container_name, and key
    # are passed via -backend-config flags by `just tf-init shared`.
    # Values come from .env (captured by `just collect-tf bootstrap`).
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

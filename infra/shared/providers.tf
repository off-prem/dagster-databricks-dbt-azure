# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ Terraform configuration for the SHARED infrastructure stack               │
# │                                                                           │
# │ This block tells Terraform:                                               │
# │   1. Which version of Terraform itself is required                        │
# │   2. Where to store state (the record of what's been created)             │
# │   3. Which "providers" (plugins) to download — each provider knows how    │
# │      to talk to a specific cloud API                                      │
# └─────────────────────────────────────────────────────────────────────────────┘

terraform {
  required_version = ">= 1.17"

  # State backend — Terraform tracks every resource it creates in a "state file."
  # We store that file in an Azure Storage blob so multiple people (and CI) can
  # share the same state. The actual storage account name, resource group, etc.
  # are passed via -backend-config flags by `just tf-init shared`.
  # Values come from .env (captured by `just collect-tf bootstrap`).
  backend "azurerm" {}

  required_providers {
    # azurerm — creates and manages Azure resources (VMs, databases, networks, etc.)
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    # random — generates random strings/passwords so resource names are unique
    # and secrets are strong, without us hardcoding them
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    # time — lets us add deliberate pauses (e.g. waiting for Azure RBAC changes
    # to propagate before using them)
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

# The Azure provider authenticates using whatever credentials `az login` set up.
# subscription_id tells it which Azure subscription to create resources in.
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

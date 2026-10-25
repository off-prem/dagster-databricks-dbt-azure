# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ Terraform configuration for the PER-ENVIRONMENT stack                     │
# │                                                                           │
# │ This stack is applied TWICE — once for stage, once for prod — with        │
# │ different .tfvars files. It creates resources that are unique to each      │
# │ environment: the Databricks workspace, its catalogs/schemas/permissions,  │
# │ and the managed identity Dagster pods use for Key Vault access.           │
# │                                                                           │
# │ More providers are needed here than in shared/ because we also talk to    │
# │ Azure AD (to create service principals) and to the Databricks API (to     │
# │ create catalogs, schemas, SQL warehouses, and grants).                    │
# └─────────────────────────────────────────────────────────────────────────────┘

terraform {
  required_version = ">= 1.17"

  # State is stored per-env: the -backend-config key is "stage.tfstate" or
  # "prod.tfstate", so each env has its own state file in the same storage account.
  backend "azurerm" {}

  required_providers {
    # azurerm — Azure resources (resource groups, workspaces, identities)
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    # azuread — Azure Active Directory / Entra ID (app registrations, service principals)
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    # databricks — Databricks workspace objects (catalogs, schemas, warehouses, grants)
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.65"
    }
    # random — random string generation (not currently used here, but required
    # by the lock file from earlier init)
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    # time — deliberate pauses for RBAC propagation
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Azure AD provider — authenticates via your `az login` session automatically.
provider "azuread" {}

# Databricks workspace-level provider. On Phase 2.1 (Azure resources only),
# databricks_host is empty and every Databricks resource has count = 0 (gated
# by var.metastore_id), so this provider is never actually called. Once the
# workspace exists and you run `just collect-tf env-stage`, the host URL is
# populated and Phase 2.4 can create Databricks objects.
provider "databricks" {
  host = var.databricks_host
}

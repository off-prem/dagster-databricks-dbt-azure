# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ Input variables for the per-environment stack                             │
# │                                                                           │
# │ Most values come from the .tfvars files (stage.tfvars / prod.tfvars).     │
# │ Some are injected as TF_VAR_* environment variables by the justfile,      │
# │ loaded from .env — particularly values that come from prior Terraform     │
# │ outputs (like databricks_host, which doesn't exist until Phase 2.1).     │
# └─────────────────────────────────────────────────────────────────────────────┘

variable "project" {
  type        = string
  default     = "dagster"
  description = "Project name — used as prefix for all resource names"
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

# Needed by the azuread provider and the Entra app registration.
variable "tenant_id" {
  type        = string
  description = "Azure AD tenant ID"
}

# "stage" or "prod" — controls resource names, database names, catalog names, etc.
variable "env" {
  type        = string
  description = "Environment name (stage or prod)"
}

variable "location" {
  type        = string
  default     = "eastus2"
  description = "Azure region"
}

# These default to the naming convention from the shared stack. Override only
# if you renamed the shared resource group or AKS cluster.
variable "shared_rg" {
  type        = string
  default     = ""
  description = "Shared resource group name (defaults to rg-{project}-shared)"
}

variable "aks_name" {
  type        = string
  default     = ""
  description = "AKS cluster name (defaults to aks-{project})"
}

variable "my_ip_cidr" {
  type        = string
  description = "Your public IP as x.x.x.x/32 (Databricks IP access list)"
}

variable "owner" {
  type        = string
  description = "Owner name for resource tags"
}

# Set AFTER step 2.3 (manual metastore assignment). When empty, all Databricks
# resources are skipped (count = 0) so Phase 2.1 can create only Azure resources.
# The guide walks you through setting this.
variable "metastore_id" {
  type        = string
  default     = ""
  description = "Unity Catalog metastore ID (set after step 2.3)"
}

# Set AFTER step 2.1 via `just collect-tf env-stage`. The Databricks provider
# needs this URL to know which workspace API to call. When empty, the provider
# is never invoked (all Databricks resources have count = 0).
variable "databricks_host" {
  type        = string
  default     = ""
  description = "Databricks workspace URL (set after step 2.1 via collect-tf)"
}

locals {
  # Resolve defaults: use the naming convention unless explicitly overridden.
  shared_rg = var.shared_rg != "" ? var.shared_rg : "rg-${var.project}-shared"
  aks_name  = var.aks_name != "" ? var.aks_name : "aks-${var.project}"

  # Strip CIDR suffix to bare IP for APIs that don't accept CIDR notation.
  my_ip = cidrhost(var.my_ip_cidr, 0)

  # Tags applied to every resource for cost tracking and ownership.
  tags = {
    project    = var.project
    env        = var.env
    owner      = var.owner
    managed_by = "terraform"
  }
}

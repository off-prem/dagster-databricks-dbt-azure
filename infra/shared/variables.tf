# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ Input variables for the shared stack                                      │
# │                                                                           │
# │ Variables are parameters you pass in at apply time. They come from:       │
# │   - A .tfvars file (e.g. `terraform plan -var-file=shared.tfvars`)        │
# │   - Environment variables prefixed with TF_VAR_ (e.g. TF_VAR_owner)      │
# │   - The `just` recipes, which load .env and pass values automatically     │
# │                                                                           │
# │ Variables with a `default` are optional; the rest are required.           │
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

variable "location" {
  type        = string
  default     = "eastus2"
  description = "Azure region"
}

# Your public IP, written as a CIDR (e.g. "203.0.113.42/32"). The /32 means
# "just this one IP." Used in firewall rules on AKS, Key Vault, Postgres, and
# ADLS so that only you (and AKS) can reach them from the internet.
variable "my_ip_cidr" {
  type        = string
  description = "Your public IP as x.x.x.x/32 (firewall rules, AKS authorized ranges)"
}

variable "owner" {
  type        = string
  description = "Owner name for resource tags"
}

variable "aks_vm_size" {
  type        = string
  default     = "Standard_D2as_v6"
  description = "AKS node VM size"
}

variable "pg_location" {
  type        = string
  default     = "centralus"
  description = "Region for Postgres (B-series often unavailable in eastus2 — centralus is a reliable fallback)"
}

variable "pg_sku_name" {
  type        = string
  default     = "B_Standard_B2s"
  description = "Postgres Flexible Server SKU"
}

variable "pg_version" {
  type        = string
  default     = "16"
  description = "Postgres major version"
}

# Locals are computed values derived from variables. Unlike variables, you can't
# pass them in — they're calculated here and used throughout the config.
locals {
  tags = {
    project    = var.project
    env        = "shared"
    owner      = var.owner
    managed_by = "terraform"
  }
}

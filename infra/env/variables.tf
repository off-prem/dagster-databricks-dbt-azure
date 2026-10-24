variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "env" {
  type        = string
  description = "Environment name (stage or prod)"
}

variable "location" {
  type        = string
  default     = "eastus2"
  description = "Azure region"
}

variable "shared_rg" {
  type        = string
  description = "Shared resource group name (from tfvars)"
}

variable "aks_name" {
  type        = string
  description = "AKS cluster name (from tfvars)"
}

variable "my_ip_cidr" {
  type        = string
  description = "Your public IP as x.x.x.x/32 (Databricks IP access list)"
}

variable "owner" {
  type        = string
  description = "Owner name for resource tags"
}

locals {
  tags = {
    project    = "dagster"
    env        = var.env
    owner      = var.owner
    managed_by = "terraform"
  }
}

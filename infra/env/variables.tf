variable "project" {
  type        = string
  default     = "dagster"
  description = "Project name — used as prefix for all resource names"
}

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

locals {
  shared_rg = var.shared_rg != "" ? var.shared_rg : "rg-${var.project}-shared"
  aks_name  = var.aks_name != "" ? var.aks_name : "aks-${var.project}"
  tags = {
    project    = var.project
    env        = var.env
    owner      = var.owner
    managed_by = "terraform"
  }
}

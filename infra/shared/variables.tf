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

variable "my_ip_cidr" {
  type        = string
  description = "Your public IP as x.x.x.x/32 (firewall rules, AKS authorized ranges)"
}

variable "owner" {
  type        = string
  description = "Owner name for resource tags"
}

locals {
  tags = {
    project    = var.project
    env        = "shared"
    owner      = var.owner
    managed_by = "terraform"
  }
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "location" {
  type        = string
  default     = "eastus2"
  description = "Azure region"
}

variable "github_repo" {
  type        = string
  description = "GitHub org/repo for OIDC federated credentials"
}

variable "owner" {
  type        = string
  description = "Owner name for resource tags"
}

locals {
  tags = {
    project    = "dagster"
    env        = "shared"
    owner      = var.owner
    managed_by = "terraform"
  }
}

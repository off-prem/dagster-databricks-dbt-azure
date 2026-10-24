output "client_id" {
  value       = azuread_application.github.client_id
  description = "Entra app client ID for GitHub OIDC (→ AZURE_CLIENT_ID)"
}

output "storage_account_name" {
  value       = azurerm_storage_account.tfstate.name
  description = "Terraform state storage account name"
}

output "resource_group_name" {
  value       = azurerm_resource_group.tfstate.name
  description = "Terraform state resource group name"
}

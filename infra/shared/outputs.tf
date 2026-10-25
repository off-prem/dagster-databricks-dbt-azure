# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ Outputs — values exported from this Terraform stack                       │
# │                                                                           │
# │ After `terraform apply`, run `just collect-tf shared` to capture these    │
# │ into your .env file. Other scripts (helm-upgrade.sh, bundle-deploy.sh)    │
# │ and the env/ Terraform stack read them from there.                        │
# └─────────────────────────────────────────────────────────────────────────────┘

# The ACR name (e.g. "acrdagsterab1c") and its login URL (e.g.
# "acrdagsterab1c.azurecr.io"). You'll use these to push Docker images:
#   az acr login -n <acr_name>
#   docker push <acr_login_server>/poc:latest
output "acr_name" {
  value = azurerm_container_registry.this.name
}

output "acr_login_server" {
  value = azurerm_container_registry.this.login_server
}

# Postgres fully qualified domain name. Helm uses this to tell Dagster where
# its metadata database lives (e.g. "pg-dagster.postgres.database.azure.com").
output "pg_fqdn" {
  value = azurerm_postgresql_flexible_server.this.fqdn
}

# Key Vault name — needed by SecretProviderClass manifests so the CSI driver
# knows which vault to read secrets from.
output "kv_name" {
  value = azurerm_key_vault.this.name
}

# Storage account name — needed by the env stack's data source lookup and by
# Databricks' Access Connector for reading/writing data lake files.
output "storage_account_name" {
  value = azurerm_storage_account.this.name
}

# The public IP that AKS uses for outbound traffic. Added to firewall rules on
# Postgres, Key Vault, and Databricks so pods can reach those services.
output "aks_egress_ip" {
  value = data.azurerm_public_ip.aks_egress.ip_address
}

# The OIDC issuer URL — a URL published by AKS that Azure AD uses to verify
# K8s service account tokens. The env stack uses this when setting up the
# federated identity credential (workload identity).
output "aks_oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

# Key Vault resource ID — the env stack uses this to grant the Dagster managed
# identity "Key Vault Secrets User" access.
output "kv_id" {
  value = azurerm_key_vault.this.id
}

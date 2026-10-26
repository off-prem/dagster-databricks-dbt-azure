# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ Outputs from the per-environment stack                                    │
# │                                                                           │
# │ After `terraform apply`, run `just collect-tf env-stage` (or env-prod)    │
# │ to capture these into .env. They're used by helm-upgrade.sh,              │
# │ bundle-deploy.sh, and the SecretProviderClass manifests.                  │
# │                                                                           │
# │ Some outputs use try() because the Databricks resources don't exist on    │
# │ the first apply (Phase 2.1) — try() returns "" instead of erroring.       │
# └─────────────────────────────────────────────────────────────────────────────┘

# The workspace URL (e.g. "https://adb-12345.6.azuredatabricks.net").
# Used by Dagster pods to connect to Databricks and by the Databricks CLI.
output "databricks_host" {
  value = "https://${azurerm_databricks_workspace.this.workspace_url}"
}

# The workspace's numeric ID — useful for Databricks CLI configuration and
# for constructing URLs to jobs/notebooks in the workspace.
output "databricks_workspace_id" {
  value = azurerm_databricks_workspace.this.workspace_id
}

# The Entra app's client_id for the Databricks service principal.
# Empty on Phase 2.1 (before metastore assignment).
output "databricks_sp_client_id" {
  value = try(azuread_application.databricks_sp[0].client_id, "")
}

# The HTTP path for the SQL warehouse — dbt and Dagster use this to route SQL
# queries to the right warehouse. Looks like "/sql/1.0/warehouses/<id>".
# Empty on Phase 2.1.
output "sql_warehouse_http_path" {
  value = try("/sql/1.0/warehouses/${databricks_sql_endpoint.this[0].id}", "")
}

# The client ID of the Azure managed identity that Dagster pods use.
# Needed by the SecretProviderClass manifest and the Helm chart's workload
# identity annotation — it tells Azure which identity the pod's K8s service
# account maps to.
output "dagster_identity_client_id" {
  value = azurerm_user_assigned_identity.dagster.client_id
}

# The resource ID of the Databricks Access Connector — needed when setting up
# Unity Catalog's storage credential (points at this connector so Databricks
# can use its identity to access ADLS).
output "access_connector_id" {
  value = azurerm_databricks_access_connector.this.id
}


# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ Per-environment Azure resources — Phase 2.1 (stage) / Phase 4.1 (prod)   │
# │                                                                           │
# │ This file creates the Azure-side resources for each environment:          │
# │   - A resource group (rg-dagster-stage or rg-dagster-prod)                │
# │   - A Databricks workspace (the environment where Spark jobs run)         │
# │   - An Access Connector (lets Databricks read/write the data lake)        │
# │   - A managed identity (lets Dagster pods read Key Vault secrets)         │
# │                                                                           │
# │ It also looks up shared resources (AKS, Key Vault, storage account)       │
# │ created by the shared/ stack, so it can wire everything together.         │
# └─────────────────────────────────────────────────────────────────────────────┘

# ── Data sources (read-only lookups of existing resources) ───────────────────
# These don't create anything — they find resources that already exist from
# the shared stack and make their attributes available for use below.

# Get the identity of whoever is running Terraform (for RBAC assignments).
data "azurerm_client_config" "current" {}

# ── Shared-stack lookups ─────────────────────────────────────────────────────
# Rather than passing the Key Vault name and storage account name as variables
# between stacks, we discover them by type within the shared resource group.
# This means fewer variables to manage and no risk of typos.

# Look up the AKS cluster — we need its OIDC issuer URL (for workload identity)
# and egress IP (for firewall rules).
data "azurerm_kubernetes_cluster" "this" {
  name                = local.aks_name
  resource_group_name = local.shared_rg
}

# Find the Key Vault in the shared RG by resource type.
data "azurerm_resources" "kv" {
  resource_group_name = local.shared_rg
  type                = "Microsoft.KeyVault/vaults"
}

# Now that we know its name, look up the full Key Vault details (we need its
# resource ID to assign RBAC roles on it).
data "azurerm_key_vault" "shared" {
  name                = data.azurerm_resources.kv.resources[0].name
  resource_group_name = local.shared_rg
}

# Same pattern for the storage account: find by type, then look up details.
data "azurerm_resources" "storage" {
  resource_group_name = local.shared_rg
  type                = "Microsoft.Storage/storageAccounts"
}

data "azurerm_storage_account" "shared" {
  name                = data.azurerm_resources.storage.resources[0].name
  resource_group_name = local.shared_rg
}

# Look up the AKS egress IP — the public IP that all outbound traffic from
# K8s pods appears to come from. Needed for Databricks IP access lists.
locals {
  aks_egress_pip_id = tolist(data.azurerm_kubernetes_cluster.this.network_profile[0].load_balancer_profile[0].effective_outbound_ips)[0]
}

data "azurerm_public_ip" "aks_egress" {
  name                = reverse(split("/", local.aks_egress_pip_id))[0]
  resource_group_name = data.azurerm_kubernetes_cluster.this.node_resource_group
}

# ── Resource group ────────────────────────────────────────────────────────────
# Each environment gets its own resource group, separate from the shared one.

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.project}-${var.env}"
  location = var.location
  tags     = local.tags
}

# ── Databricks workspace ─────────────────────────────────────────────────────
# A Databricks workspace is where you run Spark jobs, notebooks, and SQL
# queries. Each environment gets its own workspace so stage and prod are
# completely isolated. Premium SKU is required for Unity Catalog.
#
# The "managed resource group" is created automatically by Azure to hold
# Databricks' internal resources (VMs, disks, etc.) — you don't manage it.

resource "azurerm_databricks_workspace" "this" {
  name                          = "dbw-${var.project}-${var.env}"
  resource_group_name           = azurerm_resource_group.this.name
  location                      = azurerm_resource_group.this.location
  sku                           = "premium"
  managed_resource_group_name   = "rg-${var.project}-${var.env}-dbx-managed"
  public_network_access_enabled = true
  tags                          = local.tags
}

# ── Access Connector (Databricks → ADLS) ─────────────────────────────────────
# A Databricks Access Connector is an Azure managed identity that Databricks
# uses to read/write files in the data lake (ADLS). Unity Catalog's "external
# locations" and "storage credentials" are backed by this connector.
#
# We grant it "Storage Blob Data Contributor" on the storage account so it can
# read bronze data and write silver data.

resource "azurerm_databricks_access_connector" "this" {
  name                = "dbac-${var.project}-${var.env}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "access_connector_storage" {
  scope                = data.azurerm_storage_account.shared.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.this.identity[0].principal_id
}

# ── Managed identity (Dagster pods → Key Vault) ─────────────────────────────
# A "user-assigned managed identity" is like a service account for Azure.
# We create one per environment and assign it the "Key Vault Secrets User"
# role, so Dagster pods can read secrets (DB passwords, API keys) from KV.
#
# Workload identity flow:
#   1. AKS pod has a K8s service account (SA) annotated with this identity's client ID
#   2. AKS mints an OIDC token for the pod's SA
#   3. Azure AD verifies the token (via the federated credential below)
#   4. Azure exchanges it for a managed identity token
#   5. Pod uses that token to call Key Vault, no passwords involved

resource "azurerm_user_assigned_identity" "dagster" {
  name                = "id-${var.project}-${var.env}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

# The federated credential binds a specific K8s service account to this Azure
# identity. The "subject" must exactly match the SA name and namespace that
# Dagster's Helm chart creates (both are "{project}-{env}").
resource "azurerm_federated_identity_credential" "dagster" {
  name                = "fed-${var.project}-${var.env}"
  resource_group_name = azurerm_resource_group.this.name
  parent_id           = azurerm_user_assigned_identity.dagster.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = data.azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject             = "system:serviceaccount:${var.project}-${var.env}:${var.project}-${var.env}"
}

# Grant this identity read-only access to all secrets in the shared Key Vault.
resource "azurerm_role_assignment" "dagster_kv_reader" {
  scope                = data.azurerm_key_vault.shared.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.dagster.principal_id
}

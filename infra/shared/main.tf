# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ Shared infrastructure — Phase 1                                           │
# │                                                                           │
# │ Resources here are created ONCE and shared across stage and prod:         │
# │   - Virtual network (the private "LAN" all services connect through)      │
# │   - AKS cluster (Kubernetes — runs the Dagster scheduler and web UI)      │
# │   - ACR (container registry — stores Docker images AKS pulls from)        │
# │   - Key Vault (secrets manager — passwords, API keys, SP credentials)     │
# │   - Postgres (database — stores Dagster's run/event/schedule history)     │
# │   - ADLS Gen2 (data lake storage — stores raw and processed data files)   │
# │                                                                           │
# │ Everything lives in one Azure resource group: rg-{project}-shared         │
# └─────────────────────────────────────────────────────────────────────────────┘

# ── Data sources ──────────────────────────────────────────────────────────────
# Data sources read information from Azure without creating anything. This one
# gets the identity of whoever is running Terraform (your Azure AD user),
# which we need for setting up RBAC permissions.

data "azurerm_client_config" "current" {}

# ── Random values ─────────────────────────────────────────────────────────────
# Some Azure resource names must be globally unique (e.g. storage accounts, ACR).
# A random suffix avoids collisions when multiple people deploy from this blueprint.

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

# A strong 32-character password for the Postgres admin user. Terraform
# generates this once and stores it in state — it's also saved to Key Vault
# (see azurerm_key_vault_secret.pg_admin_password below) so pods can retrieve it.
resource "random_password" "pg_admin" {
  length  = 32
  special = true
}

locals {
  # Strip the /32 CIDR suffix to get a bare IP (some Azure APIs want bare IPs).
  my_ip = cidrhost(var.my_ip_cidr, 0)
}

# ── Resource group ────────────────────────────────────────────────────────────
# An Azure resource group is a logical container — like a folder — that holds
# related resources. Deleting the group deletes everything inside it.

resource "azurerm_resource_group" "shared" {
  name     = "rg-${var.project}-shared"
  location = var.location
  tags     = local.tags
}

# ── Network ───────────────────────────────────────────────────────────────────
# A Virtual Network (VNet) is a private address space in Azure, like a LAN.
# Resources inside the VNet can talk to each other; we control internet access
# with firewall rules. The address space 10.0.0.0/16 gives us ~65,000 IPs.

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.project}"
  location            = azurerm_resource_group.shared.location
  resource_group_name = azurerm_resource_group.shared.name
  address_space       = ["10.0.0.0/16"]
  tags                = local.tags
}

# Subnets carve the VNet into smaller ranges. Each subnet is dedicated to one
# type of workload so we can apply different network rules to each.

# AKS nodes live here. /22 = 1,022 usable IPs — enough for AKS pods with Azure CNI.
resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.shared.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.0.0.0/22"]
}

# Private endpoints subnet — reserved for future use (e.g. private links to
# Postgres or Key Vault if you upgrade beyond the POC).
resource "azurerm_subnet" "pe" {
  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.shared.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.0.4.0/24"]
}

# Databricks host subnet — when a Databricks workspace uses VNet injection
# (running compute in YOUR network), it needs two dedicated subnets. The
# "delegation" block tells Azure that only Databricks can use this subnet.
resource "azurerm_subnet" "dbx_host" {
  name                 = "snet-dbx-host"
  resource_group_name  = azurerm_resource_group.shared.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.0.8.0/22"]

  delegation {
    name = "databricks-host"
    service_delegation {
      name    = "Microsoft.Databricks/workspaces"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action", "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action", "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"]
    }
  }
}

# Databricks container subnet — the second required subnet for VNet injection.
# Databricks worker containers (Spark executors) run here.
resource "azurerm_subnet" "dbx_container" {
  name                 = "snet-dbx-container"
  resource_group_name  = azurerm_resource_group.shared.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.0.12.0/22"]

  delegation {
    name = "databricks-container"
    service_delegation {
      name    = "Microsoft.Databricks/workspaces"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action", "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action", "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"]
    }
  }
}

# A Network Security Group (NSG) is a set of firewall rules for a subnet.
# We attach one to the PE and Databricks subnets. By default, Azure NSGs allow
# all traffic within the VNet and deny inbound from the internet.
resource "azurerm_network_security_group" "shared" {
  name                = "nsg-${var.project}-shared"
  location            = azurerm_resource_group.shared.location
  resource_group_name = azurerm_resource_group.shared.name
  tags                = local.tags
}

# Associate the NSG with each subnet that needs it.
resource "azurerm_subnet_network_security_group_association" "pe" {
  subnet_id                 = azurerm_subnet.pe.id
  network_security_group_id = azurerm_network_security_group.shared.id
}

resource "azurerm_subnet_network_security_group_association" "dbx_host" {
  subnet_id                 = azurerm_subnet.dbx_host.id
  network_security_group_id = azurerm_network_security_group.shared.id
}

resource "azurerm_subnet_network_security_group_association" "dbx_container" {
  subnet_id                 = azurerm_subnet.dbx_container.id
  network_security_group_id = azurerm_network_security_group.shared.id
}

# ── AKS (Azure Kubernetes Service) ───────────────────────────────────────────
# AKS is a managed Kubernetes cluster. Kubernetes (K8s) is a container
# orchestrator — it runs Docker containers, restarts them if they crash,
# and handles networking between them. Dagster's web UI, scheduler (daemon),
# and run workers all run as K8s pods (containers) in this cluster.

resource "azurerm_kubernetes_cluster" "this" {
  name                = "aks-${var.project}"
  location            = azurerm_resource_group.shared.location
  resource_group_name = azurerm_resource_group.shared.name
  dns_prefix          = "aks-${var.project}"
  sku_tier            = "Free"    # Free tier — no SLA, fine for a POC

  # The node pool defines the VMs that run containers. One 2-vCPU node
  # is enough for this POC. VM size is configurable via var.aks_vm_size.
  default_node_pool {
    name           = "system"
    node_count     = 1
    vm_size        = var.aks_vm_size
    os_disk_size_gb = 32
    vnet_subnet_id = azurerm_subnet.aks.id   # place nodes in the AKS subnet
  }

  # SystemAssigned identity — AKS gets its own Azure identity (like a service
  # account) so it can pull images from ACR and manage its own load balancers.
  identity {
    type = "SystemAssigned"
  }

  # OIDC + workload identity let K8s pods authenticate to Azure using their
  # K8s service account. This is how Dagster pods read secrets from Key Vault
  # without storing any credentials — Azure trusts the K8s token because the
  # OIDC issuer is registered (see federated_identity_credential in env/main.tf).
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # The CSI Secrets Store driver syncs Azure Key Vault secrets into K8s Secrets,
  # which pods can then mount as files or env vars. secret_rotation_enabled
  # means it periodically checks for updated secret values.
  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  # Azure CNI gives each pod its own VNet IP (vs. kubenet which NATs).
  # service_cidr is the range for K8s "ClusterIP" services (internal-only);
  # dns_service_ip is the cluster DNS resolver address within that range.
  network_profile {
    network_plugin = "azure"
    service_cidr   = "172.16.0.0/16"
    dns_service_ip = "172.16.0.10"
  }

  # Azure RBAC for K8s — lets you grant kubectl access via Azure AD roles
  # instead of managing K8s RBAC manually (kubeconfig uses `az aks get-credentials`).
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }

  # Restrict who can talk to the K8s API server. Only your IP is allowed.
  # Without this, anyone on the internet could probe the API (though they'd
  # still need credentials).
  api_server_access_profile {
    authorized_ip_ranges = [var.my_ip_cidr]
  }

  tags = local.tags
}

# Grant the person running Terraform cluster-admin access via Azure RBAC,
# so `kubectl` works after `az aks get-credentials` + `kubelogin convert-kubeconfig -l azurecli`.
resource "azurerm_role_assignment" "aks_cluster_admin" {
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ── AKS egress IP lookup ─────────────────────────────────────────────────────
# When AKS pods make outbound requests (to Postgres, Key Vault, etc.) they
# appear to come from the cluster's "egress" public IP. We need to know this
# IP so we can whitelist it in firewall rules. AKS creates and manages this IP
# automatically — we just look it up here.

locals {
  aks_egress_pip_id = tolist(azurerm_kubernetes_cluster.this.network_profile[0].load_balancer_profile[0].effective_outbound_ips)[0]
}

data "azurerm_public_ip" "aks_egress" {
  name                = reverse(split("/", local.aks_egress_pip_id))[0]
  resource_group_name = azurerm_kubernetes_cluster.this.node_resource_group
}

# ── ACR (Azure Container Registry) ───────────────────────────────────────────
# ACR is a private Docker registry. You build your Dagster code into a Docker
# image, push it to ACR, and AKS pulls it from there. Basic SKU is cheapest
# (~$5/mo). admin_enabled=false means authentication uses Azure AD, not a
# shared password.

resource "azurerm_container_registry" "this" {
  name                = "acr${var.project}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags
}

# Grant AKS the "AcrPull" role so its nodes can pull images from this registry.
# Without this, `kubectl` would show ImagePullBackOff errors.
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

# ── Key Vault ─────────────────────────────────────────────────────────────────
# Azure Key Vault is a secrets manager — it stores passwords, API keys, and
# certificates encrypted at rest. Pods access it via the CSI Secrets Store
# driver (configured on AKS above) using workload identity (no passwords needed
# to read passwords!).
#
# RBAC authorization means access is controlled by Azure role assignments
# (e.g. "Key Vault Secrets User"), not legacy Vault "access policies."

resource "azurerm_key_vault" "this" {
  name                       = "kv-${var.project}-${random_string.suffix.result}"
  resource_group_name        = azurerm_resource_group.shared.name
  location                   = azurerm_resource_group.shared.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false     # false for POC — lets us fully delete
  soft_delete_retention_days = 7         # minimum retention

  # Firewall: deny all traffic by default, then allow:
  #   - your IP (so you can manage secrets via the CLI)
  #   - the AKS egress IP (so pods can read secrets)
  #   - Azure-internal traffic ("AzureServices" bypass)
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = [local.my_ip, data.azurerm_public_ip.aks_egress.ip_address]
  }

  tags = local.tags
}

# Grant yourself (the person running Terraform) the "Secrets Officer" role,
# which allows creating, reading, and deleting secrets in the vault.
resource "azurerm_role_assignment" "kv_secrets_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Azure RBAC role assignments take up to 30 seconds to propagate. Without this
# wait, the very next step (writing a secret to KV) would fail with 403 Forbidden
# because Azure hasn't registered the permission yet.
resource "time_sleep" "kv_rbac_propagation" {
  depends_on      = [azurerm_role_assignment.kv_secrets_officer]
  create_duration = "30s"
}

# Store the auto-generated Postgres admin password in Key Vault. Dagster pods
# will read this via the CSI Secrets Store driver (see SecretProviderClass in
# deploy/k8s/). This way the password never appears in Helm values or env files.
resource "azurerm_key_vault_secret" "pg_admin_password" {
  depends_on   = [time_sleep.kv_rbac_propagation]
  name         = "pg-admin-password"
  value        = random_password.pg_admin.result
  key_vault_id = azurerm_key_vault.this.id
}

# ── Postgres ──────────────────────────────────────────────────────────────────
# Azure Postgres Flexible Server — a managed PostgreSQL database. Dagster uses
# Postgres to store its own metadata: run history, event logs, schedules, and
# sensor state. This is NOT where your data pipeline data lives (that's in
# Databricks / ADLS).
#
# Two databases are created: one for stage, one for prod — so both environments
# can share the same server without interfering with each other.
# Location and SKU are configurable — Postgres B-series SKUs are unavailable in
# some regions (e.g. eastus2). centralus is the default fallback.

resource "azurerm_postgresql_flexible_server" "this" {
  name                          = "pg-${var.project}-${random_string.suffix.result}"
  resource_group_name           = azurerm_resource_group.shared.name
  location                      = var.pg_location
  version                       = var.pg_version
  sku_name                      = var.pg_sku_name
  storage_mb                    = 32768                # 32 GB storage
  administrator_login           = "pgadmin"
  administrator_password        = random_password.pg_admin.result
  backup_retention_days         = 7
  geo_redundant_backup_enabled  = false     # save cost — single-region is fine for POC
  public_network_access_enabled = true      # reachable from AKS and your machine
  tags                          = local.tags

  lifecycle {
    ignore_changes = [zone]
  }
}

# Postgres firewall rules — only AKS pods and your machine can connect.
resource "azurerm_postgresql_flexible_server_firewall_rule" "aks_egress" {
  name             = "aks-egress"
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = data.azurerm_public_ip.aks_egress.ip_address
  end_ip_address   = data.azurerm_public_ip.aks_egress.ip_address
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "user_ip" {
  name             = "user-ip"
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = local.my_ip
  end_ip_address   = local.my_ip
}

# One database per environment. Dagster's Helm chart points at the right DB name
# via values.stage.yaml / values.prod.yaml (postgresqlDatabase key).
resource "azurerm_postgresql_flexible_server_database" "stage" {
  name      = "${var.project}_stage"
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_postgresql_flexible_server_database" "prod" {
  name      = "${var.project}_prod"
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# ── ADLS Gen2 (Azure Data Lake Storage) ──────────────────────────────────────
# A storage account with "hierarchical namespace" (HNS) enabled, which makes it
# ADLS Gen2 — Azure's data lake. This is where your actual data lives:
#   - metastore/  → Unity Catalog's internal metadata
#   - bronze/     → raw data ingested from APIs by the Databricks pipeline
#   - silver/     → cleaned/transformed data produced by dbt models
#
# LRS (Locally Redundant Storage) is the cheapest replication option.
# shared_access_key_enabled=false forces all access through Azure AD (RBAC) —
# no shared storage keys floating around.

resource "azurerm_storage_account" "this" {
  name                            = "st${var.project}${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.shared.name
  location                        = azurerm_resource_group.shared.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  is_hns_enabled                  = true     # this makes it ADLS Gen2
  shared_access_key_enabled       = false    # RBAC only, no shared keys
  default_to_oauth_authentication = true

  # Firewall: deny all except your IP, Azure services, and Databricks access
  # connectors. Serverless compute (SQL warehouses, serverless jobs) runs on
  # Databricks-managed infra, so "AzureServices" bypass alone is not enough —
  # each access connector needs an explicit resource access rule.
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    ip_rules       = [local.my_ip]

    dynamic "private_link_access" {
      for_each = compact([
        var.access_connector_id_stage, var.access_connector_id_prod,
      ])
      content {
        endpoint_resource_id = private_link_access.value
      }
    }
  }

  tags = local.tags
}

# Grant yourself "Storage Blob Data Contributor" so you can browse/upload files
# via the CLI or Azure portal during development.
resource "azurerm_role_assignment" "storage_blob_contributor" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Containers are top-level "folders" in a storage account (similar to S3 buckets).
resource "azurerm_storage_container" "metastore" {
  name               = "metastore"
  storage_account_id = azurerm_storage_account.this.id
}

# ── Network Security Perimeter (serverless SQL warehouse → ADLS) ────────────
# Serverless compute runs on Databricks-managed infrastructure outside the
# customer subscription. The storage account's firewall (defaultAction: Deny)
# blocks it — resource access rules alone are not enough. An NSP with the
# AzureDatabricksServerless service tag is the Azure-recommended solution.
# Transition mode keeps existing firewall rules working alongside the NSP.

resource "azurerm_network_security_perimeter" "this" {
  name                = "nsp-${var.project}"
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location
  tags                = local.tags
}

resource "azurerm_network_security_perimeter_profile" "this" {
  name                          = "profile-${var.project}"
  network_security_perimeter_id = azurerm_network_security_perimeter.this.id
}

resource "azurerm_network_security_perimeter_access_rule" "dbx_serverless" {
  name                                   = "allow-databricks-serverless"
  network_security_perimeter_profile_id  = azurerm_network_security_perimeter_profile.this.id
  direction                              = "Inbound"
  service_tags                           = ["AzureDatabricksServerless"]
}

resource "azurerm_network_security_perimeter_association" "storage" {
  name                                   = "assoc-${var.project}-storage"
  network_security_perimeter_profile_id  = azurerm_network_security_perimeter_profile.this.id
  resource_id                            = azurerm_storage_account.this.id
  access_mode                            = "Learning"
}

resource "azurerm_storage_container" "bronze" {
  name               = "bronze"
  storage_account_id = azurerm_storage_account.this.id
}

resource "azurerm_storage_container" "silver" {
  name               = "silver"
  storage_account_id = azurerm_storage_account.this.id
}

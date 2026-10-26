# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ Databricks workspace objects — Phase 2.4 (stage) / Phase 4.3 (prod)      │
# │                                                                           │
# │ Everything in this file is GATED by var.metastore_id. On the first apply  │
# │ (Phase 2.1), metastore_id is empty → count = 0 → nothing here runs.      │
# │ After you manually assign the Unity Catalog metastore in the Databricks   │
# │ account console (step 2.3) and paste the ID into your .tfvars, the second │
# │ apply (Phase 2.4) creates all of these.                                   │
# │                                                                           │
# │ This two-phase approach is necessary because:                             │
# │   a) The Databricks workspace must exist before we can call its API       │
# │   b) The metastore must be assigned (a manual step) before we can create  │
# │      Unity Catalog objects (catalogs, schemas, volumes)                   │
# └─────────────────────────────────────────────────────────────────────────────┘

locals {
  # When metastore_id is provided, create all Databricks resources (count = 1).
  # When empty (Phase 2.1), skip them all (count = 0).
  create_dbx = var.metastore_id != "" ? 1 : 0
}

# ── Storage credential ───────────────────────────────────────────────────────
# Registers the Access Connector as a Unity Catalog storage credential so
# Databricks can read/write ADLS on behalf of the catalog. Required when the
# metastore uses Databricks-managed "Default Storage" (the auto-created
# metastore) — without this, CREATE CATALOG fails because there is no
# storage root configured on the metastore itself.

resource "databricks_storage_credential" "this" {
  count = local.create_dbx
  name  = "sc-${var.project}-${var.env}"
  azure_managed_identity {
    access_connector_id = azurerm_databricks_access_connector.this.id
  }
}

resource "databricks_external_location" "this" {
  count           = local.create_dbx
  name            = "el-${var.project}-${var.env}"
  url             = "abfss://metastore@${data.azurerm_storage_account.shared.name}.dfs.core.windows.net/catalogs/${var.env}"
  credential_name = databricks_storage_credential.this[0].name
}

# ── Unity Catalog: catalog, schemas, volume ──────────────────────────────────
# Unity Catalog is Databricks' data governance layer. Think of it as:
#   catalog → database (top-level namespace, one per environment)
#   schema  → schema (groups related tables, e.g. "bronze" and "silver")
#   volume  → a managed directory for raw files (like an S3 prefix)
#
# The hierarchy is: catalog.schema.table or catalog.schema.volume

# One catalog per environment: "stage" or "prod".
# storage_root is required because the auto-created metastore uses Default
# Storage and has no ADLS root of its own. The external location must exist
# first so Databricks can validate the path.
resource "databricks_catalog" "this" {
  count        = local.create_dbx
  name         = var.env
  comment      = "Dagster POC ${var.env} catalog"
  storage_root = "abfss://metastore@${data.azurerm_storage_account.shared.name}.dfs.core.windows.net/catalogs/${var.env}"
  depends_on   = [databricks_external_location.this]
}

# bronze schema — raw data ingested from APIs lands here as Delta tables.
resource "databricks_schema" "bronze" {
  count        = local.create_dbx
  catalog_name = databricks_catalog.this[0].name
  name         = "bronze"
  comment      = "Raw ingested data"
}

# silver schema — cleaned and transformed data (dbt models output here).
resource "databricks_schema" "silver" {
  count        = local.create_dbx
  catalog_name = databricks_catalog.this[0].name
  name         = "silver"
  comment      = "Cleaned and transformed data"
}

# A managed volume is a directory inside Unity Catalog's storage. The SDP
# pipeline writes raw JSON files here before converting them to Delta tables.
resource "databricks_volume" "landing" {
  count        = local.create_dbx
  catalog_name = databricks_catalog.this[0].name
  schema_name  = databricks_schema.bronze[0].name
  name         = "landing"
  volume_type  = "MANAGED"
  comment      = "Landing zone for raw API JSON files"
}

# ── SQL warehouse ────────────────────────────────────────────────────────────
# A serverless SQL warehouse runs SQL queries on Databricks. dbt and Dagster
# use this to read/write Delta tables. "Serverless" means Databricks manages
# the compute — you don't need to configure VMs. 2X-Small is the smallest
# size. auto_stop_mins=5 shuts it down after 5 minutes of inactivity to save
# costs (~$0/hr when stopped).

resource "databricks_sql_endpoint" "this" {
  count                     = local.create_dbx
  name                      = "sql-${var.project}-${var.env}"
  cluster_size              = "2X-Small"
  auto_stop_mins            = 5
  max_num_clusters          = 1
  enable_serverless_compute = true
}

# ── Service principal (Entra app → Databricks SP → OAuth M2M) ───────────────
# Dagster pods need to authenticate to Databricks to launch jobs and run SQL.
# Instead of using a personal access token (PAT) — which is tied to a person
# and expires — we create a "service principal" (SP): a non-human identity.
#
# The chain works like this:
#   1. Create an Entra ID (Azure AD) "app registration" → this gives us a
#      client_id (like a username)
#   2. Create an Entra "service principal" for that app → makes it usable
#   3. Create an "application password" (client secret) → like a password
#   4. Register the SP inside the Databricks workspace → Databricks knows it
#   5. Grant the SP permissions on catalogs/schemas/warehouses → it can work
#
# Dagster authenticates using OAuth M2M (machine-to-machine): client_id +
# client_secret → access token. The credentials are stored in Key Vault and
# synced to K8s Secrets via the CSI driver — pods never see raw credentials.

# Step 1: Entra app registration (creates the client_id)
resource "azuread_application" "databricks_sp" {
  count        = local.create_dbx
  display_name = "sp-${var.project}-${var.env}"
}

# Step 2: Entra service principal (makes the app usable as an identity)
resource "azuread_service_principal" "databricks_sp" {
  count     = local.create_dbx
  client_id = azuread_application.databricks_sp[0].client_id
}

# Step 3: client secret (the "password" half of OAuth M2M)
resource "azuread_application_password" "databricks_sp" {
  count          = local.create_dbx
  application_id = azuread_application.databricks_sp[0].id
  display_name   = "dagster-m2m"
}

# Step 4: register this SP inside the Databricks workspace so Databricks
# recognizes it (Entra identity alone isn't enough — Databricks has its own
# user/SP registry).
resource "databricks_service_principal" "dagster" {
  count                = local.create_dbx
  application_id       = azuread_application.databricks_sp[0].client_id
  display_name         = "sp-${var.project}-${var.env}"
  workspace_access     = true
  databricks_sql_access = true
}

# ── IP access list ───────────────────────────────────────────────────────────
# Restrict which IPs can reach the Databricks workspace API. Only your
# development machine and the AKS cluster (where Dagster runs) are allowed.
# This is a workspace-level firewall, separate from the VNet/NSG rules.

resource "databricks_workspace_conf" "ip_access" {
  count = local.create_dbx
  custom_config = {
    "enableIpAccessLists" = true
  }
}

resource "databricks_ip_access_list" "user" {
  count        = local.create_dbx
  depends_on   = [databricks_workspace_conf.ip_access]
  label        = "user-ip"
  list_type    = "ALLOW"
  ip_addresses = [var.my_ip_cidr]
}

resource "databricks_ip_access_list" "aks_egress" {
  count        = local.create_dbx
  depends_on   = [databricks_ip_access_list.user]
  label        = "aks-egress"
  list_type    = "ALLOW"
  ip_addresses = ["${var.aks_egress_ip}/32"]
}

# ── Unity Catalog grants ────────────────────────────────────────────────────
# Grant the service principal the minimum permissions it needs:
#   - USE_CATALOG: enter the catalog (like `USE database` in SQL)
#   - USE_SCHEMA:  enter a schema
#   - CREATE_TABLE: create/overwrite tables (needed for ingestion and dbt)
#   - READ_VOLUME / WRITE_VOLUME: read/write files in the landing volume
#
# The principal is identified by its Entra client_id.

resource "databricks_grants" "catalog" {
  count   = local.create_dbx
  catalog = databricks_catalog.this[0].name
  grant {
    principal  = azuread_application.databricks_sp[0].client_id
    privileges = ["USE_CATALOG", "CREATE_SCHEMA"]
  }
}

resource "databricks_grants" "bronze" {
  count  = local.create_dbx
  schema = "${databricks_catalog.this[0].name}.${databricks_schema.bronze[0].name}"
  grant {
    principal  = azuread_application.databricks_sp[0].client_id
    privileges = ["USE_SCHEMA", "CREATE_TABLE", "READ_VOLUME", "WRITE_VOLUME"]
  }
}

resource "databricks_grants" "silver" {
  count  = local.create_dbx
  schema = "${databricks_catalog.this[0].name}.${databricks_schema.silver[0].name}"
  grant {
    principal  = azuread_application.databricks_sp[0].client_id
    privileges = ["USE_SCHEMA", "CREATE_TABLE"]
  }
}

# Grant the SP "CAN_USE" on the SQL warehouse so it can run queries.
resource "databricks_permissions" "sql_endpoint" {
  count           = local.create_dbx
  sql_endpoint_id = databricks_sql_endpoint.this[0].id
  access_control {
    service_principal_name = azuread_application.databricks_sp[0].client_id
    permission_level       = "CAN_USE"
  }
}

# ── Key Vault secrets (SP credentials for Dagster pods) ──────────────────────
# Store the service principal's client_id and secret in Key Vault. The CSI
# Secrets Store driver (configured in deploy/k8s/secretproviderclass.yaml)
# syncs these into K8s Secrets, which Dagster pods read as environment variables.
#
# This way the SP credentials flow: Entra → Key Vault → CSI driver → K8s
# Secret → pod env var — never touching any config file or Helm value.

resource "azurerm_key_vault_secret" "dbx_sp_client_id" {
  count        = local.create_dbx
  name         = "dbx-${var.env}-sp-client-id"
  value        = azuread_application.databricks_sp[0].client_id
  key_vault_id = data.azurerm_key_vault.shared.id
}

resource "azurerm_key_vault_secret" "dbx_sp_secret" {
  count        = local.create_dbx
  name         = "dbx-${var.env}-sp-secret"
  value        = azuread_application_password.databricks_sp[0].value
  key_vault_id = data.azurerm_key_vault.shared.id
}

# Unity Catalog objects required by the Dagster + dbt code.
# Applied in Phase 2 after the workspace exists.

resource "databricks_catalog" "this" {
  name    = var.env
  comment = "Dagster POC ${var.env} catalog"
}

resource "databricks_schema" "bronze" {
  catalog_name = databricks_catalog.this.name
  name         = "bronze"
  comment      = "Raw ingested data"
}

resource "databricks_schema" "silver" {
  catalog_name = databricks_catalog.this.name
  name         = "silver"
  comment      = "Cleaned and transformed data"
}

resource "databricks_volume" "landing" {
  catalog_name = databricks_catalog.this.name
  schema_name  = databricks_schema.bronze.name
  name         = "landing"
  volume_type  = "MANAGED"
  comment      = "Landing zone for raw API JSON files"
}

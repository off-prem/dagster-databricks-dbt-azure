# dbt (data build tool)

A SQL transformation tool. You write SQL `SELECT` statements as **models**, and dbt runs
them against a database — in our case, a [Databricks SQL warehouse](../resources/databricks-workspace.md).
dbt handles dependencies between models, generates documentation, and tracks lineage.

## Why we use it

The silver layer (cleaned/transformed data) is a SQL transformation of the bronze layer
(raw ingested data). dbt is the standard tool for this pattern. Using `dagster-dbt`, the
dbt models appear as Dagster assets with lineage connected to the bronze assets.

## Key commands

```bash
just dbt <env> debug    # Test the connection to the SQL warehouse
just dbt <env> build    # Run all models
just dbt <env> parse    # Check syntax without connecting (used in CI)
```

The `justfile` sets the right environment variables (`DATABRICKS_HOST`,
`DBX_WAREHOUSE_HTTP_PATH`, `DBX_CATALOG`, etc.) from `.env` based on the target.

## How it's configured in this project

The dbt project lives in `dbt/`:

| File | Purpose |
|------|---------|
| `profiles.yml` | Connection config — reads `DATABRICKS_HOST`, `DBX_WAREHOUSE_HTTP_PATH`, `DBX_SP_CLIENT_ID`, `DBX_SP_SECRET`, `DBX_CATALOG` from environment variables. Targets: `stage`, `prod`. |
| `models/silver/silver_<model>.sql` | The transformation SQL |
| `models/sources.yml` | Declares the bronze source table so dbt can reference it |
| `dbt_project.yml` | Project settings: materialization strategy (`table`), schema (`silver`) |

### Authentication

dbt connects to Databricks using the service principal credentials (`auth_type: oauth`).
Locally, these come from your `.env`; in the Dagster pod, they come from
[Key Vault](../resources/key-vault.md) via the CSI driver.

### How dbt fits into Dagster

The `dagster-dbt` integration (`DbtProject` + `@dbt_assets`) turns each dbt model into a
Dagster asset. The bronze source is mapped to the Dagster `bronze_<source>` asset, so
Dagster shows one connected graph from API ingestion through to the silver table.

## Related docs

- [Databricks workspace](../resources/databricks-workspace.md) — the SQL warehouse dbt runs against
- [Unity Catalog](../concepts/unity-catalog.md) — the catalog/schema hierarchy
- [Conventions](../conventions.md) — dbt project conventions

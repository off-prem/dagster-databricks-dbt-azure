# dbt (data build tool)

> **Type:** Tool · **Scope:** per-env (runs in the Dagster pod) · **Where:** `dbt/`

A SQL transformation tool. Each model is a `SELECT` that dbt materializes as a table, with
dependency tracking between models.

## Why we use it

The bronze and silver tables are built with dbt against a
[Databricks SQL warehouse](../resources/databricks-sql-warehouse.md).
Through `dagster-dbt`, every model shows up as a Dagster asset in the same lineage graph as
the extract step.

## How it's used here

- **Project:** `dbt/dbt_project.yml` (profile `poc`). Models under `models/bronze/` land in
  schema `bronze`, models under `models/silver/` in schema `silver`. Both are materialized as
  tables.
- **Models:** `bronze_posts` reads the landing-volume JSON with `read_files()`. `silver_posts`
  selects and renames columns from `ref('bronze_posts')`.
- **Schema names:** the `generate_schema_name` macro uses the custom schema as-is instead of
  prefixing it with the target schema.
- **Profile:** `dbt/profiles.yml` reads everything from env vars (`DATABRICKS_HOST`,
  `DBX_WAREHOUSE_HTTP_PATH`, `DBX_CATALOG`, `DBX_SP_CLIENT_ID`, `DBX_SP_SECRET`). Target
  comes from `DAGSTER_ENV`. Auth is OAuth M2M with the
  [Databricks service principal](../resources/databricks-service-principal.md).
- **In Dagster:** `dagster/src/poc/assets/dbt.py` builds a `DbtProject` and a `@dbt_assets`
  function that runs `dbt build`. The `Dockerfile` sets `DAGSTER_DBT_PARSE_PROJECT_ON_LOAD=1`
  so the manifest is generated when the code server starts.

## Key commands & files

```bash
just dbt stage debug     # test the warehouse connection
just dbt stage build     # run models and tests
just dbt stage parse     # syntax check; CI uses placeholder env vars
```

## Gotchas

- `dbt-databricks` needs a live connection even for `dbt parse`. That is why the manifest is
  built at pod start (real credentials) and not at image build time. CI's `dbt parse` works
  only because the placeholder env vars satisfy the profile.
- `bronze_posts` has a `depends_on` comment so dbt links it to the `raw.posts` source.
  Removing it breaks lineage.
- The warehouse auto-stops after 5 minutes, so the first query of a run waits for a cold start.

## Cost

Free tool. Each run costs warehouse time (about $0.30–0.50, see [costs](../costs.md)).

## Managed by

Installed as a Python dependency (`dbt-databricks`) through [uv](uv.md); no separate install.

## Related docs

- [Databricks SQL warehouse](../resources/databricks-sql-warehouse.md): where dbt runs
- [Dagster](dagster.md): runs dbt as assets
- [Medallion architecture](../concepts/medallion-architecture.md): the bronze/silver layers
- [Unity Catalog](../concepts/unity-catalog.md): catalog and schema hierarchy

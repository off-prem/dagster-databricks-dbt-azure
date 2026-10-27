# Databricks Catalog and Schemas

> **Type:** Resource · **Scope:** per-env · **Names:** catalog `<env>`; schemas `bronze`, `silver` · **Stack:** `infra/env` (Databricks provider)

The environment's data namespace in Unity Catalog: catalog `stage` or `prod`, with two schemas inside.

## Why we use it

The catalog is the environment boundary for data. The same SQL and code run against `stage.*` or `prod.*` by changing one variable (`DBX_CATALOG`).

## How it's used here

| Object | Value | Purpose |
|--------|-------|---------|
| Catalog | `<env>` ("Dagster POC <env> catalog") | Storage root is the env's [external location](databricks-storage-credential.md), `metastore/catalogs/<env>` |
| Schema `bronze` | "Raw ingested data" | Holds the [landing volume](databricks-landing-volume.md) and the dbt bronze tables |
| Schema `silver` | "Cleaned and transformed data" | dbt silver tables |

Privileges for the Dagster service principal are in [Databricks grants](databricks-grants.md). The name `<env>` comes from the
`env` Terraform variable; the bundle variable `catalog` and the pod variable `DBX_CATALOG` must match it.

## Key commands & files

```sql
SHOW CATALOGS;
SHOW SCHEMAS IN stage;
```

Terraform: `databricks_catalog.this`, `databricks_schema.bronze`, `databricks_schema.silver`.

## Gotchas

- Only `bronze` and `silver` exist. There is no `ops` schema or `dagster_pipes` volume; the landing volume is `bronze.landing`.
- Catalog names must be unique within the metastore. Stage and prod share a metastore, hence `stage` and `prod`.
- dbt's `generate_schema_name` macro makes `+schema: silver` use that exact schema, so dbt doesn't create `<target>_silver`.
- Dropping a catalog with tables in it requires `CASCADE`; Terraform will refuse unless `force_destroy` is set.

## Cost

Free; storage on ADLS.

## Managed by

[Terraform](../tools/terraform.md), `infra/env/databricks.tf`.

## Related docs

- [Unity Catalog](../concepts/unity-catalog.md), [Medallion architecture](../concepts/medallion-architecture.md)
- [Databricks grants](databricks-grants.md), [Databricks landing volume](databricks-landing-volume.md)
- [Unity Catalog metastore](unity-catalog-metastore.md)

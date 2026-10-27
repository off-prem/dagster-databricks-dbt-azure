# Medallion Architecture (bronze / silver)

> **Type:** Concept · **Scope:** per-env catalog · **Where:** `dbt/models/`

Organizing data into layers of increasing quality: raw (bronze), then cleaned (silver), then business-ready (gold).
This project implements bronze and silver.

## Why we use it

It separates "what we received" from "what we trust". You can rebuild silver from bronze
without calling the source API again.

## How it's used here

| Layer | Schema | Built by | Content |
|-------|--------|----------|---------|
| Landing | `<catalog>.bronze.landing` (volume) | the extract job via [Pipes](dagster-pipes.md) | Raw JSON files, one folder per source |
| Bronze | `<catalog>.bronze` | dbt model `bronze_posts` | Raw rows read from the landing files, plus `_source_file` and `_file_modified_at` |
| Silver | `<catalog>.silver` | dbt model `silver_posts` | Renamed, typed columns (`post_id`, `user_id`, `title`, `body`) |

Both dbt layers are materialized as tables. Models select the catalog through `DBX_CATALOG`, so the
same SQL runs against `stage` or `prod`. No gold layer exists, because it is outside the POC scope.

## Key commands & files

```bash
just dbt stage build
```

Files: `dbt/models/bronze/`, `dbt/models/silver/`, `dbt/dbt_project.yml`.

## Gotchas

- Bronze is a dbt table over files in the volume, not a streaming table from an SDP pipeline ([decision 5](../decisions.md)).
- Silver depends on bronze via `ref()`. Bronze depends on the landing files via a `depends_on` comment, which links it to the Dagster asset.
- The `generate_schema_name` macro makes `+schema: bronze` mean the schema named exactly `bronze`.

## Cost

Storage on [ADLS](../resources/adls.md); compute on the [SQL warehouse](../resources/databricks-sql-warehouse.md).

## Managed by

Schemas by [Terraform](../tools/terraform.md); tables by [dbt](../tools/dbt.md).

## Related docs

- [Unity Catalog](unity-catalog.md), [dbt](../tools/dbt.md), [Asset factory](asset-factory.md)
- [Architecture](../architecture.md)

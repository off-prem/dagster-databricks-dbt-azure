# Databricks Landing Volume

> **Type:** Resource · **Scope:** per-env · **Name:** `<env>.bronze.landing` · **Stack:** `infra/env` (Databricks provider)

A managed Unity Catalog **volume**: a governed folder for files (not tables) inside the `bronze` schema.

## Why we use it

It is the handoff point between Databricks ingestion and dbt, and the transport for [Dagster Pipes](../concepts/dagster-pipes.md) messages.
Raw API JSON lands here, and dbt reads it with `read_files()`.

## How it's used here

- **Path:** `/Volumes/<env>/bronze/landing/`
- **Raw data:** the extract notebook writes `landing/<source>/latest.json` (newline-delimited JSON), for example `landing/posts/latest.json`.
- **Pipes:** Dagster writes the run context and reads message chunks through this volume using the Files REST API.
- **dbt:** `bronze_posts` reads `/Volumes/<catalog>/bronze/landing/posts/` as JSON.
- **Access:** the Dagster service principal has `READ_VOLUME` and `WRITE_VOLUME` on `bronze` ([grants](databricks-grants.md)).

## Key commands & files

```bash
databricks fs ls dbfs:/Volumes/stage/bronze/landing/posts/
```

Terraform: `databricks_volume.landing` in `infra/env/databricks.tf`. Code: `databricks/src/extract/rest_api.py`, `dbt/models/bronze/bronze_posts.sql`.

## Gotchas

- **No FUSE on Azure serverless:** notebooks can't `open("/Volumes/...")`. All access goes through the SDK Files API
  ([details](../dagster-pipes-azure-gotchas.md)).
- Each extract **overwrites** `latest.json`. History isn't kept unless you change `rest_api.py`.
- It is a *managed* volume, so deleting the volume deletes the files.
- Pipes message files accumulate under the volume. Clean them up if the volume grows.

## Cost

Storage on [ADLS](adls.md) only.

## Managed by

[Terraform](../tools/terraform.md), `infra/env/databricks.tf`.

## Related docs

- [Dagster Pipes](../concepts/dagster-pipes.md), [Medallion architecture](../concepts/medallion-architecture.md)
- [Databricks catalog and schemas](databricks-catalog.md), [Databricks grants](databricks-grants.md), [dbt](../tools/dbt.md)

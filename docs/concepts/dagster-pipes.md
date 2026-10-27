# Dagster Pipes

> **Type:** Concept · **Scope:** per-env · **Where:** `dagster/src/poc/assets/extract.py`, `databricks/src/extract/entrypoint.py`

Dagster's protocol for running code in an external system (here Databricks) while keeping
logs, metadata and materialization events visible in Dagster.

## Why we use it

The extract step runs on Databricks serverless compute, not on AKS. Pipes lets Dagster start
that job, wait for it, and receive row counts and results back, so the external run appears as a normal asset
in the lineage graph.

## How it's used here

1. A `raw_<source>` asset creates a `WorkspaceClient` using the
   [service principal](../resources/databricks-service-principal.md) (OAuth M2M from env vars).
2. `PipesDatabricksServerlessClient` submits a one-off **notebook task** that runs the deployed
   `src/extract/entrypoint` from `DBX_BUNDLE_ROOT`.
3. Dagster passes `source_name`, `catalog`, and optional API auth (header and value) as Pipes **extras**.
4. Context and messages travel as files in the Unity Catalog volume `/Volumes/<catalog>/bronze/landing`.
5. The notebook fetches the API and writes JSON to `landing/<source>/latest.json`, then reports a materialization.
6. [dbt](../tools/dbt.md) reads those files in `bronze_posts`.

Because Azure serverless has no FUSE mount for `/Volumes`, the notebook uses custom context-loader and
message-writer classes that call the Files REST API (`_SdkContextLoader` and `_SdkMessageWriter` in
`entrypoint.py`). See Gotchas below for all deviations from the official Dagster Pipes docs.

## Key commands & files

```bash
just smoke-test stage       # runs the whole chain via GraphQL
```

Files: `assets/extract.py` (Dagster side), `entrypoint.py` and `rest_api.py` (Databricks side).

## Gotchas

Deviations from the [official Dagster Pipes serverless guide](https://dagster.io/docs/integrations/libraries/databricks/pipes/serverless-compute) on Azure:

1. **No FUSE on Azure serverless.** `PipesUnityCatalogVolumesContextLoader`/`MessageWriter` use `open("/Volumes/...")` which fails with `FileNotFoundError`. Custom `_SdkContextLoader` and `_SdkMessageWriter` use `WorkspaceClient().files` (REST API) instead. If Databricks adds FUSE to Azure serverless, switch back to the built-in classes.
2. **Bundle strips `.py` from notebooks.** `databricks bundle deploy` imports `.py` files with the `# Databricks notebook source` header as notebooks and drops the extension. Use `notebook_path` without `.py`. Non-notebook files (like `rest_api.py`) keep the extension.
3. **`get_extra()` takes exactly one argument.** `pipes.get_extra("key", None)` raises `TypeError`. Wrap optional extras in `try/except KeyError`.
4. **`SubmitTask.from_dict()` needs SDK objects for environments.** Environment entries must be `jobs.JobEnvironment.from_dict({...})` objects, not raw dicts. Not relevant for `notebook_task`.
5. **SP needs `CAN_RUN` on the bundle directory.** `scripts/bundle-deploy.sh` grants this automatically after each deploy.
6. **SP needs `CREATE_SCHEMA` on the catalog for dbt.** Added in `infra/env/databricks.tf` grants.
7. **`%pip install` needed in the notebook.** Serverless doesn't have `dagster-pipes` pre-installed; the notebook uses a `%pip install` cell.
8. The API secret is passed in extras, so it appears in the Databricks job context. Treat the volume and job run as sensitive.
9. [Decision 5](../decisions.md) records the switch from an SDP pipeline to Pipes.

## Cost

Serverless job about $0.07–0.15 per run.

## Managed by

Code in the repo; the notebook is deployed by the [bundle](../tools/databricks-asset-bundles.md).

## Related docs

- [Asset factory](asset-factory.md), [Dagster](../tools/dagster.md)
- [Databricks Asset Bundles](../tools/databricks-asset-bundles.md), [Unity Catalog](unity-catalog.md)
- [Secrets flow](secrets-flow.md)

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
message-writer classes that call the Files REST API. Details and other deviations from the official guide are in
[Dagster Pipes Azure gotchas](../dagster-pipes-azure-gotchas.md).

## Key commands & files

```bash
just smoke-test stage       # runs the whole chain via GraphQL
```

Files: `assets/extract.py` (Dagster side), `entrypoint.py` and `rest_api.py` (Databricks side).

## Gotchas

- The service principal needs `CAN_RUN` on the bundle directory, and `READ_VOLUME`/`WRITE_VOLUME` on `bronze`.
- `pipes.get_extra(key)` takes one argument and raises `KeyError` when absent.
- The API secret is passed in extras, so it appears in the Databricks job context. Treat the volume and job run as sensitive.
- [Decision 5](../decisions.md) records the switch from an SDP pipeline to Pipes.

## Cost

Serverless job about $0.07–0.15 per run.

## Managed by

Code in the repo; the notebook is deployed by the [bundle](../tools/databricks-asset-bundles.md).

## Related docs

- [Asset factory](asset-factory.md), [Dagster](../tools/dagster.md)
- [Databricks Asset Bundles](../tools/databricks-asset-bundles.md), [Unity Catalog](unity-catalog.md)
- [Secrets flow](secrets-flow.md)

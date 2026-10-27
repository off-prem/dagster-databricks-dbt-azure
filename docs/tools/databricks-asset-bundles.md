# Databricks Asset Bundles

> **Type:** Tool · **Scope:** per-env (targets `stage`, `prod`) · **Where:** `databricks/`

Databricks' deployment unit for workspace code. A bundle is a `databricks.yml` plus the
source files it ships, deployed to a named **target** with the [Databricks CLI](databricks-cli.md).

## Why we use it

The ingestion code runs inside Databricks, not on AKS. The bundle uploads that code to each
workspace and applies per-environment variables. Terraform owns long-lived infrastructure
(catalog, warehouse, grants), and the bundle owns code. If it has a `-t <env>` target, it's a bundle
([decision 7](../decisions.md)).

## How it's used here

`databricks/databricks.yml` defines:

- **Variables:** `catalog`, `ci_sp_client_id`, `run_as_sp_client_id`.
- **Targets:** `stage` (catalog `stage`) and `prod` (catalog `prod`), both `mode: production`.
- **Workspace root:** `/Workspace/.bundle/${bundle.name}/${bundle.target}`. Dagster reads it as
  `DBX_BUNDLE_ROOT`, set by `scripts/helm-upgrade.sh`.
- **Permissions:** `CAN_MANAGE` for the CI principal and the per-env Dagster service principal.

The bundle currently ships **files only**: `src/extract/entrypoint.py` (a notebook) and
`rest_api.py`. It defines **no pipeline or job resources**. Dagster submits the notebook as a
one-off serverless task via [Dagster Pipes](../concepts/dagster-pipes.md).
`databricks/sources.yml` lists the APIs to ingest. See [asset factory](../concepts/asset-factory.md).

## Key commands & files

```bash
just bundle-validate stage
just bundle-deploy prod
```

Files: `databricks/databricks.yml`, `databricks/sources.yml`, `databricks/src/extract/`.

## Gotchas

- The notebook path has **no `.py` extension**. The bundle deploys files with a notebook
  header as notebooks.
- There is no SDP pipeline or job resource. The code path is Pipes ([decision 5](../decisions.md)).
- `sources.yml` is used on both sides (copied into the Docker image for Dagster, and deployed
  with the bundle for the notebook), so changing it needs an image rebuild **and** a bundle deploy.
- `scripts/bundle-deploy.sh` also grants the Dagster service principal `CAN_RUN` on the bundle
  directory after each deploy. Without it the job can't read the notebook.

## Cost

Free. Deploys copy files only.

## Managed by

Deployed by `scripts/bundle-deploy.sh` (local) and the deploy workflows (CI).

## Related docs

- [Databricks CLI](databricks-cli.md): the deploy tool
- [Dagster Pipes](../concepts/dagster-pipes.md): how Dagster runs the shipped code
- [Dagster Pipes Azure gotchas](../dagster-pipes-azure-gotchas.md)
- [Promote, don't rebuild](../concepts/cicd.md): bundles are deployed at the same SHA to prod

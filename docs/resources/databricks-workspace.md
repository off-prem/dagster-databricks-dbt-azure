# Databricks Workspace

> **Type:** Resource · **Scope:** per-env · **Name:** `dbw-<project>-<env>` · **Stack:** `infra/env`

An Azure Databricks environment: the UI, SQL editor and serverless compute, with its own URL.
There is one workspace for stage and one for prod.

## Why we use it

Dagster decides *when* to run; Databricks does the compute. The workspace hosts the ingestion
job (a serverless notebook task) and the [SQL warehouse](databricks-sql-warehouse.md) for dbt.
Two workspaces keep the environments fully isolated.

## How it's used here

| Setting | Value | Why |
|---------|-------|-----|
| SKU | Premium | Required for Unity Catalog |
| Network | Managed VNet (no VNet injection) | Only serverless compute is used; see [decision 12](../decisions.md) |
| Managed resource group | `rg-<project>-<env>-dbx-managed` | Created by Azure for the workspace |
| Public access | Enabled, restricted by an **IP access list** (your IP and the AKS egress IP) | See [network access](../concepts/network-access.md) |

Objects created inside it by the `databricks` Terraform provider (they stay at count 0
until `metastore_id` and `databricks_host` are set):

| Object | Notes |
|--------|-------|
| Storage credential + external location | Backed by the [access connector](databricks-access-connector.md) |
| Catalog `<env>` | Storage root `metastore/catalogs/<env>` in [ADLS](adls.md) |
| Schemas `bronze`, `silver` | See [medallion architecture](../concepts/medallion-architecture.md) |
| Volume `bronze.landing` | Landing zone for raw JSON and Pipes messages |
| [SQL warehouse](databricks-sql-warehouse.md) | `sql-<project>-<env>` |
| [Service principal](databricks-service-principal.md) | What Dagster authenticates as |
| Grants and IP access lists | Least privilege for the service principal |

The Unity Catalog metastore is created manually (see [Unity Catalog](../concepts/unity-catalog.md)).

## Key commands & files

```bash
just bundle-deploy stage          # ship the Databricks-side code
scripts/setup-env.sh collect-tf env-stage
```

Terraform: `infra/env/main.tf`, `infra/env/databricks.tf`.

## Gotchas

- The workspace URL is per user, so it lives in `.env` (`DBX_STAGE_HOST`, `DBX_PROD_HOST`) and never in committed files.
- Two-pass apply: create the workspace first, record its host, then apply again to create the in-workspace objects.
- A changed IP locks you out of the workspace API. Update `TF_VAR_my_ip_cidr` and re-apply.
- New workspaces get a 14-day Premium trial.

## Cost

The workspace is free. Compute is billed per run (serverless job about $0.07–0.15, warehouse about $0.30–0.50) and is $0 when idle.

## Managed by

[Terraform](../tools/terraform.md), `infra/env/` (workspace through `azurerm`, contents through `databricks`).
Code is deployed by [Asset Bundles](../tools/databricks-asset-bundles.md).

## Related docs

- [Unity Catalog](../concepts/unity-catalog.md), [ADLS](adls.md), [Key Vault](key-vault.md)
- [Databricks CLI](../tools/databricks-cli.md), [dbt](../tools/dbt.md)

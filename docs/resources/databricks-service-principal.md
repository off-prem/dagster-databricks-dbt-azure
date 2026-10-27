# Databricks Service Principal

> **Type:** Resource · **Scope:** per-env · **Name:** `sp-<project>-<env>` · **Stack:** `infra/env`

A non-human identity that Dagster uses to call Databricks. It is an Entra app registration
registered inside the workspace.

## Why we use it

Dagster pods need to submit jobs and run SQL without a person's token. A personal access
token is tied to one user and expires. A service principal with OAuth M2M is stable and auditable.

## How it's used here

1. Terraform creates an Entra application, its service principal and a client secret.
2. It registers the principal in the workspace (with `workspace_access`).
3. It writes `dbx-<env>-sp-client-id` and `dbx-<env>-sp-secret` to [Key Vault](key-vault.md).
4. The pod receives them as `DBX_SP_CLIENT_ID` and `DBX_SP_SECRET` through the
   [CSI driver](../tools/secrets-store-csi-driver.md).
5. Dagster ([WorkspaceClient](../concepts/dagster-pipes.md)) and [dbt](../tools/dbt.md) log in with OAuth M2M.

**Grants:** `USE_CATALOG` and `CREATE_SCHEMA` on the catalog; `USE_SCHEMA` and `CREATE_TABLE`
on `bronze` and `silver`, plus `READ_VOLUME`/`WRITE_VOLUME` on `bronze`; `CAN_USE` on the warehouse.
The bundle also gives it `CAN_MANAGE` on the deployed files, so it can run them.

## Key commands & files

Terraform: `infra/env/databricks.tf`. Bundle variable: `run_as_sp_client_id`.

## Gotchas

- The client secret lives in Terraform state as well as Key Vault. Treat state as sensitive.
- The secret has an expiry set by the `azuread` provider default. To rotate it, taint the password resource, re-apply `env`, and restart the pods.
- This is separate from the CI [Entra app](entra-app.md) (`app-dagster-github`). Each has its own purpose.
- Upgrade path: federate the pod's [managed identity](managed-identity.md) and drop the secret
  ([decision 11](../decisions.md)).

## Cost

Free.

## Managed by

[Terraform](../tools/terraform.md), `infra/env/` (`azuread` and `databricks` providers).

## Related docs

- [Key Vault](key-vault.md), [Secrets flow](../concepts/secrets-flow.md)
- [Databricks workspace](databricks-workspace.md), [SQL warehouse](databricks-sql-warehouse.md)
- [Unity Catalog](../concepts/unity-catalog.md)

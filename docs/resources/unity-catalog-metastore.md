# Unity Catalog Metastore

> **Type:** Resource · **Scope:** one per Azure region, shared by both workspaces · **Name:** `metastore-<project>-<region>` · **Created:** manually (guide step 2.3)

The top-level Unity Catalog container: governance metadata plus a root storage location. It lives at the Databricks **account**
level, not inside a workspace.

## Why we use it

Catalogs, schemas, volumes and grants can't exist until a metastore is attached to the workspace. Terraform can't create it here because
that needs account-level admin access on a new Databricks account.

## How it's used here

Created once in the account console ([accounts.azuredatabricks.net](https://accounts.azuredatabricks.net)):

1. **Catalog → Create metastore**
2. **Name:** `metastore-<project>-<region>`; **Region:** the same as the workspaces (`eastus2` by default)
3. **ADLS Gen2 path:** `abfss://metastore@<STORAGE_ACCOUNT_NAME>.dfs.core.windows.net/`
4. **Access connector resource ID:** the stage `access_connector_id` output
5. **Assign** it to the stage workspace
6. Save the ID: `just set-env TF_VAR_metastore_id <id>`

The prod workspace is auto-assigned if it is in the same region. Check **Catalog → Metastore → Workspaces** and assign it by hand if it
isn't there. **Do not create a second metastore.**

Terraform uses `TF_VAR_metastore_id` as the gate: every Databricks-provider resource has `count = 0` until it is set.

## Key commands & files

```bash
just set-env TF_VAR_metastore_id <id>
just tf-apply env-stage      # now creates catalog, SP, warehouse, grants
```

## Gotchas

- Only one metastore per region per account. If your company already has one, attach the workspaces to it and use its ID.
- It needs account-admin rights. The person who signed up for the Azure free account normally has them.
- The metastore root is the `metastore` container, while each catalog's data is under `metastore/catalogs/<env>`.
- `destroy-all` does **not** delete the metastore. Delete it manually in the account console.
- The access connector used at creation must have `Storage Blob Data Contributor` on the account, or the create step fails.

## Cost

Free.

## Managed by

Manual (account console). Everything inside it is managed by [Terraform](../tools/terraform.md).

## Related docs

- [Unity Catalog](../concepts/unity-catalog.md), [ADLS](adls.md), [Databricks access connector](databricks-access-connector.md)
- [Databricks workspace](databricks-workspace.md), [Databricks catalog and schemas](databricks-catalog.md)

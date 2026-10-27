# Databricks Storage Credential and External Location

> **Type:** Resource · **Scope:** per-env · **Names:** `sc-<project>-<env>`, `el-<project>-<env>` · **Stack:** `infra/env` (Databricks provider)

Two Unity Catalog objects that connect the catalog to [ADLS](adls.md). The **storage credential** says *how* to authenticate; the
**external location** says *which path* it may be used for.

## Why we use it

Unity Catalog needs an authorized path to write table and volume files. This pair gives it exactly one: the env's catalog folder.

## How it's used here

| Object | Value |
|--------|-------|
| Storage credential | `sc-<project>-<env>`, an Azure managed identity credential backed by the [access connector](databricks-access-connector.md) |
| External location | `el-<project>-<env>` at `abfss://metastore@<account>.dfs.core.windows.net/catalogs/<env>` |

The [catalog](databricks-catalog.md) uses this location as its `storage_root`, and Terraform makes the catalog depend on it.
Both are created in the second apply, after the metastore is assigned.

## Key commands & files

```sql
SHOW STORAGE CREDENTIALS;
SHOW EXTERNAL LOCATIONS;
```

Terraform: `databricks_storage_credential.this`, `databricks_external_location.this` in `infra/env/databricks.tf`.

## Gotchas

- Creation validates access. If it fails with 403, the access connector role or the storage firewall rule is missing.
- Don't point two environments at the same path. Each env has its own `catalogs/<env>` folder.
- Deleting the external location while the catalog exists is blocked by dependencies, so destroy in the Terraform order.

## Cost

Free.

## Managed by

[Terraform](../tools/terraform.md), `infra/env/databricks.tf`.

## Related docs

- [Databricks access connector](databricks-access-connector.md), [ADLS](adls.md), [Network security perimeter](network-security-perimeter.md)
- [Databricks catalog and schemas](databricks-catalog.md), [Unity Catalog](../concepts/unity-catalog.md)

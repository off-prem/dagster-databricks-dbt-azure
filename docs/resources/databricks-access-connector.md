# Databricks Access Connector

> **Type:** Resource · **Scope:** per-env · **Name:** `dbac-<project>-<env>` · **Stack:** `infra/env`

An Azure resource holding a managed identity that Databricks uses to reach storage.

## Why we use it

Unity Catalog must read and write files in [ADLS](adls.md), but storage key auth is disabled.
The access connector gives Databricks an Azure identity that holds a storage role, so no
keys or passwords are involved.

## How it's used here

- It has a system-assigned managed identity with `Storage Blob Data Contributor` on the ADLS account.
- The **storage credential** `sc-<project>-<env>` in the workspace points at it, and the
  **external location** `el-<project>-<env>` uses that credential for
  `abfss://metastore@<account>.dfs.core.windows.net/catalogs/<env>`.
- Its resource ID is added to the storage firewall's resource access rules, using
  `TF_VAR_access_connector_id_stage` / `_prod`.

## Key commands & files

```bash
scripts/setup-env.sh collect-tf env-stage    # captures the connector ID
```

Terraform: `infra/env/main.tf` (connector and role), `infra/env/databricks.tf` (credential, location),
`infra/shared/main.tf` (firewall rule).

## Gotchas

- The shared stack needs the connector IDs in `.env` and a re-apply, otherwise the storage
  firewall blocks Databricks. Ordering: apply `env`, collect, then re-apply `shared`.
- It is a different identity from the Dagster [managed identity](managed-identity.md) and the
  [Databricks service principal](databricks-service-principal.md). Don't confuse the three.
- Removing the role assignment breaks all table reads and writes at once.

## Cost

Free.

## Managed by

[Terraform](../tools/terraform.md), `infra/env/`.

## Related docs

- [ADLS](adls.md), [Databricks workspace](databricks-workspace.md)
- [Unity Catalog](../concepts/unity-catalog.md), [Azure RBAC](../concepts/azure-rbac.md)

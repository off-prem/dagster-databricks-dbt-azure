# Databricks Grants and Permissions

> **Type:** Resource · **Scope:** per-env · **Principal:** the Dagster [service principal](databricks-service-principal.md) · **Stack:** `infra/env` (Databricks provider)

The privileges that give Dagster and dbt just enough access to work.

## Why we use it

Least privilege: the service principal can create tables and write files in this env's catalog, and use the warehouse. It can do nothing in other catalogs.

## How it's used here

| Grant | On | Privileges |
|-------|----|-----------|
| `databricks_grants.catalog` | catalog `<env>` | `USE_CATALOG`, `CREATE_SCHEMA` |
| `databricks_grants.bronze` | `<env>.bronze` | `USE_SCHEMA`, `CREATE_TABLE`, `READ_VOLUME`, `WRITE_VOLUME` |
| `databricks_grants.silver` | `<env>.silver` | `USE_SCHEMA`, `CREATE_TABLE` |
| `databricks_permissions.sql_endpoint` | the [SQL warehouse](databricks-sql-warehouse.md) | `CAN_USE` |

Two more permissions are set outside this file:
- **Bundle folder:** `CAN_MANAGE` from the bundle's `permissions:` block, and `CAN_RUN` granted by `scripts/bundle-deploy.sh`.
- **Workspace access:** the principal is registered with `workspace_access` and `databricks_sql_access`.

## Key commands & files

```sql
SHOW GRANTS ON CATALOG stage;
SHOW GRANTS ON SCHEMA stage.bronze;
```

Terraform: `infra/env/databricks.tf`.

## Gotchas

- `CREATE_SCHEMA` on the catalog is needed for dbt (`PERMISSION_DENIED ... CREATE SCHEMA`), even though the schemas already exist.
- `databricks_grants` is **authoritative** for each securable. Grants added by hand in the UI are removed on the next apply.
- Grants name the principal by its application (client) ID, not its display name.
- The principal does not own the tables dbt creates unless dbt runs as it, which it does here.

## Cost

Free.

## Managed by

[Terraform](../tools/terraform.md), `infra/env/databricks.tf`; bundle permissions by `databricks.yml` and `scripts/bundle-deploy.sh`.

## Related docs

- [Databricks service principal](databricks-service-principal.md), [Databricks catalog and schemas](databricks-catalog.md)
- [Databricks landing volume](databricks-landing-volume.md), [Unity Catalog](../concepts/unity-catalog.md)

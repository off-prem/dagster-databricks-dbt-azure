# Unity Catalog

> **Type:** Concept · **Scope:** per-env catalog, one metastore per region · **Where:** `infra/env/databricks.tf`

Databricks' governance layer. It organizes data into a hierarchy and controls who can access what.

## Why we use it

It provides one place for permissions, lineage and storage mapping, and gives clean environment
isolation: a `stage` catalog and a `prod` catalog.

## How it's used here

```
Metastore (one per region, shared by workspaces)
  └── Catalog   stage | prod
        └── Schema   bronze | silver
              └── Table / Volume   (e.g. bronze.landing volume)
```

UC stores metadata only; files live in [ADLS](../resources/adls.md):

1. A **storage credential** (`sc-<project>-<env>`) uses the [access connector](../resources/databricks-access-connector.md).
2. An **external location** (`el-<project>-<env>`) maps `metastore/catalogs/<env>`.
3. The **catalog** `<env>` uses that location as its storage root, so tables and volumes land there.

| Object | Created by |
|--------|-----------|
| Metastore | **Manual** (account console) |
| Storage credential, external location, catalog, schemas, landing volume, grants | [Terraform](../tools/terraform.md) |
| Tables | Created at run time by [dbt](../tools/dbt.md) |
| Landing files | Written by the extract job into `bronze.landing` |

The metastore ID goes in `.env` as `TF_VAR_metastore_id`.

## Key commands & files

```sql
SHOW CATALOGS;
SHOW SCHEMAS IN stage;
SHOW GRANTS ON SCHEMA stage.bronze;
```

Terraform: `infra/env/databricks.tf`.

## Gotchas

- The metastore needs account-admin access in the Databricks account console, so it is a manual step.
  One metastore per region: if your company already has one, attach the workspaces to it.
- Only `bronze` and `silver` exist; the landing volume is `bronze.landing` (no `ops` schema).
- The service principal only gets the privileges it needs (see [Databricks SP](../resources/databricks-service-principal.md)).
- Deleting a catalog does not necessarily delete the files in ADLS.

## Cost

Free; storage is billed on ADLS.

## Managed by

Metastore manually; everything below it by Terraform.

## Related docs

- [Databricks workspace](../resources/databricks-workspace.md), [ADLS](../resources/adls.md)
- [Medallion architecture](medallion-architecture.md), [dbt](../tools/dbt.md)

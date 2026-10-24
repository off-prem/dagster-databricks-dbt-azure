# Unity Catalog

Databricks' data governance system. It organizes all your data into a hierarchy and
controls who can access what.

## The hierarchy

```
Metastore (one per Azure region)
  └── Catalog (one per environment: "stage", "prod")
        └── Schema (one per data layer: "bronze", "silver", "ops")
              └── Table / View / Volume
```

- **Metastore** — the top-level container. One per Azure region, shared by all
  [workspaces](../resources/databricks-workspace.md) in that region. Stores governance
  metadata (permissions, lineage, audit logs) and has a root storage location in
  [ADLS](../resources/adls.md).
- **Catalog** — the environment boundary. `stage` catalog for the stage workspace, `prod`
  for prod. A workspace can only see catalogs it's been granted access to.
- **Schema** — groups related tables. `bronze` holds raw ingested data, `silver` holds
  cleaned/transformed data, `ops` holds operational objects.
- **Table** — the actual data (backed by Delta/Parquet files in ADLS).
- **Volume** — a managed storage location for files (not tables). `ops.dagster_pipes` is
  reserved for future use.

## How it connects to storage

Unity Catalog doesn't store data itself — it manages metadata about data stored in
[ADLS](../resources/adls.md). The connection is:

1. **Storage credential** — tells UC how to authenticate to ADLS (via the
   [Databricks workspace](../resources/databricks-workspace.md)'s Access Connector).
2. **External locations** — maps specific ADLS paths to schema-level access rules.
   For example, `bronze` maps to `abfss://bronze@<storage>.dfs.core.windows.net/`.
3. When a pipeline writes to `stage.bronze.my_table`, UC uses the storage credential to
   write Delta files into the `bronze` container.

## How it's set up in this project

| Object | Created by | Phase |
|--------|-----------|-------|
| Metastore | **Manual** (account console) | 2.3 |
| Storage credential | [Terraform](../tools/terraform.md) (Databricks provider) | 2.4 |
| External locations | Terraform | 2.4 |
| Catalogs (`stage`, `prod`) | Terraform | 2.4, 4.3 |
| Schemas (`bronze`, `silver`, `ops`) | Terraform | 2.4, 4.3 |
| Volume (`ops.dagster_pipes`) | Terraform | 2.4 |
| Tables | Created at runtime by the SDP pipeline and [dbt](../tools/dbt.md) | 3.x |

### Why is the metastore manual?

Creating a metastore requires account-level admin access in the Databricks account console
([accounts.azuredatabricks.net](https://accounts.azuredatabricks.net)). On a new account,
this can't be done via Terraform without extra bootstrapping. For the POC, it's a one-time
click. You then record the metastore ID in `.env` and Terraform references it.

## Related docs

- [Databricks workspace](../resources/databricks-workspace.md) — the workspace that hosts
  catalogs and compute
- [ADLS](../resources/adls.md) — where table data physically lives
- [dbt](../tools/dbt.md) — writes to the `silver` schema
- [Databricks CLI](../tools/databricks-cli.md) — deploys the SDP pipeline that writes
  to `bronze`

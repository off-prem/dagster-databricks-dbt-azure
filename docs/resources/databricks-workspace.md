# Databricks Workspace

A Databricks environment — the web UI, notebooks, SQL editor, and compute where your data
pipelines run and SQL queries execute. Each workspace is an Azure resource with its own URL
(like `https://adb-1234567890.12.azuredatabricks.net`).

## Why we need it

This is where the data processing happens. Dagster orchestrates *when* things run, but
Databricks does the actual compute:
- The **SDP (Spark Declarative Pipeline)** ingests data from the source API into bronze tables
- The **SQL warehouse** runs dbt queries that transform bronze into silver

We create two workspaces — one for stage, one for prod — so environments are fully isolated.

## Configuration

| Setting | Value | Why |
|---------|-------|-----|
| Tier | Premium | Required for [Unity Catalog](../concepts/unity-catalog.md) |
| Network | Managed VNet (no VNet injection) | Serverless compute doesn't need VNet injection; simpler setup. See [corporate migration](../corporate-migration.md) for the VNet injection path. |
| IP access list | Your IP | Restricts who can access the workspace API |

### Objects inside the workspace

These are created by [Terraform](../tools/terraform.md) using the Databricks provider
(Phase 2.4):

| Object | What it is |
|--------|-----------|
| **Storage credential** | Tells Unity Catalog how to authenticate to [ADLS](adls.md) (via the Access Connector's managed identity) |
| **External locations** (`bronze`, `silver`) | Maps Unity Catalog schemas to specific ADLS containers |
| **Catalog** (`stage` or `prod`) | Top-level data container in [Unity Catalog](../concepts/unity-catalog.md) |
| **Schemas** (`bronze`, `silver`, `ops`) | Containers for tables within the catalog |
| **Volume** (`ops.dagster_pipes`) | A storage location for exchanging files (future use) |
| **SQL warehouse** | Serverless, 2X-Small, auto-stop 5 min. The compute endpoint [dbt](../tools/dbt.md) runs against. Costs ~$0.30–0.50 per run, $0 when idle. |
| **Service principal** (`sp-dagster-<env>`) | A non-human identity that Dagster authenticates as. Has an OAuth client ID and secret stored in [Key Vault](key-vault.md). Has `USE CATALOG`, `CREATE` on its catalog, `CAN MANAGE` on the pipeline, `CAN USE` on the warehouse. |

### Access Connector

An Azure resource (separate from the workspace) with a system-assigned managed identity.
It has `Storage Blob Data Contributor` on the [ADLS](adls.md) account. Unity Catalog
uses it to read/write table data.

## Cost

The workspace itself is free. You pay for compute (DBUs — Databricks Units):

| Compute | Billing |
|---------|---------|
| SDP pipeline (serverless) | ~$0.25–0.50 per run |
| SQL warehouse (serverless, 2X-Small) | ~$0.30–0.50 per run |
| Idle | $0 |

New workspaces get a 14-day Premium trial with free DBUs.

## Provisioned by

- **The workspace** (Azure resource): [Terraform](../tools/terraform.md) `infra/env/` stack
  via `azurerm_databricks_workspace`
- **Objects inside** (catalog, warehouse, SP, etc.): [Terraform](../tools/terraform.md)
  `infra/env/` stack via the `databricks` provider
- **The SDP pipeline**: [Databricks CLI](../tools/databricks-cli.md) via Asset Bundle

## Related docs

- [Unity Catalog](../concepts/unity-catalog.md) — the governance layer
- [ADLS](adls.md) — where table data physically lives
- [dbt](../tools/dbt.md) — runs SQL against the warehouse
- [Databricks CLI](../tools/databricks-cli.md) — deploys the SDP pipeline
- [Key Vault](key-vault.md) — stores the SP credentials

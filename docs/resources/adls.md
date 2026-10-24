# ADLS Gen2 (Azure Data Lake Storage)

A storage account with the hierarchical namespace feature enabled, optimized for big data
workloads. Think of it as cloud file storage with folders (containers) and files (blobs),
but with performance characteristics suited for Spark and data lake patterns.

## Why we need it

Databricks [Unity Catalog](../concepts/unity-catalog.md) needs somewhere to physically
store the data behind your tables — the actual Parquet/Delta files. ADLS is that storage.
When a pipeline writes to `stage.bronze.my_table`, the data files land in this storage
account.

## Configuration

| Setting | Value | Why |
|---------|-------|-----|
| Account kind | StorageV2 | Standard for ADLS Gen2 |
| HNS (hierarchical namespace) | Enabled | Required for ADLS Gen2 / Unity Catalog |
| Replication | LRS (locally redundant) | Cheapest; sufficient for a POC |
| Key auth | Disabled | Access only via Azure identity (the Databricks Access Connector) |
| Firewall | Enabled | Restricted to your IP + [AKS](aks.md) egress IP |

### Containers

| Container | Purpose |
|-----------|---------|
| `metastore` | Unity Catalog metastore root — internal metadata |
| `bronze` | External location for the `bronze` schema — raw ingested data |
| `silver` | External location for the `silver` schema — transformed data |

## How Databricks accesses it

The [Databricks workspace](databricks-workspace.md) uses an **Access Connector** — an Azure
resource with a managed identity that has `Storage Blob Data Contributor` on this storage
account. Unity Catalog uses the Access Connector's identity when reading/writing table data.

## Cost

~$2/month. Storage is cheap; you're billed per GB stored and per operation.

## Provisioned by

[Terraform](../tools/terraform.md) — `infra/shared/` stack.

## Related docs

- [Unity Catalog](../concepts/unity-catalog.md) — the governance layer on top of this storage
- [Databricks workspace](databricks-workspace.md) — the workspace that accesses this storage
- [Costs](../costs.md) — full cost breakdown

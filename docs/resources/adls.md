# ADLS Gen2 (Azure Data Lake Storage)

> **Type:** Resource · **Scope:** shared · **Name:** `st<project><random>` · **Stack:** `infra/shared`

A storage account with hierarchical namespace enabled. It gives blob storage real folders
and the performance profile Spark and Delta need.

## Why we use it

[Unity Catalog](../concepts/unity-catalog.md) needs somewhere to keep the files behind
tables and volumes. When a job writes `stage.bronze.posts`, the Delta files land here.

## How it's used here

| Setting | Value | Why |
|---------|-------|-----|
| Kind / tier | StorageV2, Standard | Standard for ADLS Gen2 |
| Hierarchical namespace | On | Makes it ADLS Gen2; required by Unity Catalog |
| Replication | LRS | Cheapest; fine for a POC |
| Shared key auth | **Disabled** | Access only through Azure identities |
| Firewall | Default **deny**; allows your IP, `AzureServices` bypass, and each [access connector](databricks-access-connector.md) by resource ID | Serverless compute needs explicit rules |
| Perimeter | [NSP](network-security-perimeter.md) in Learning mode | Admits Databricks serverless |

**Containers:** `metastore` (the Unity Catalog metastore root; each env's catalog root is
`metastore/catalogs/<env>`), plus `bronze` and `silver`.

The access connector's identity holds `Storage Blob Data Contributor` on the account.

## Key commands & files

```bash
az storage account show --name "$STORAGE_ACCOUNT_NAME" --query networkRuleSet
```

Terraform: `infra/shared/main.tf`. The name is captured into `.env` as `STORAGE_ACCOUNT_NAME`.

## Gotchas

- Because key auth is off, `az storage` commands need `--auth-mode login`.
- New access connectors must be added to the firewall's resource rules
  (`TF_VAR_access_connector_id_stage/prod`), or Databricks reads fail with 403.
- The `bronze` and `silver` containers exist, but the catalog and landing volume are
  stored under `metastore/catalogs/<env>`.
- Your IP is allow-listed. If it changes, you lose CLI access until you re-apply `shared`.

## Cost

About $2/month: per GB stored plus operations.

## Managed by

[Terraform](../tools/terraform.md), `infra/shared/`.

## Related docs

- [Databricks access connector](databricks-access-connector.md), [Unity Catalog](../concepts/unity-catalog.md)
- [Network security perimeter](network-security-perimeter.md), [Network access](../concepts/network-access.md)
- [Costs](../costs.md)

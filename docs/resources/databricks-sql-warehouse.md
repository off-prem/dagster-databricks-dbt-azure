# Databricks SQL Warehouse

> **Type:** Resource · **Scope:** per-env · **Name:** `sql-<project>-<env>` · **Stack:** `infra/env`

A Databricks compute endpoint that runs SQL. Ours is **serverless** and starts on demand.

## Why we use it

[dbt](../tools/dbt.md) needs a SQL endpoint to run the bronze and silver models. Serverless
means no cluster to manage and no cost while idle.

## How it's used here

| Setting | Value | Why |
|---------|-------|-----|
| Size | 2X-Small, 1 cluster | Smallest; the data is tiny |
| Serverless | On | No VM cost, fast start |
| Auto-stop | 5 minutes | Cost; don't raise it |
| Permission | The [service principal](databricks-service-principal.md) has `CAN_USE` | Least privilege |

The warehouse's HTTP path is passed to dbt as `DBX_WAREHOUSE_HTTP_PATH`. Terraform outputs it,
`collect-tf` stores it in `.env`, and Helm injects it into the pods.

## Key commands & files

```bash
just dbt stage debug       # confirms the warehouse is reachable
```

Terraform: `databricks_sql_endpoint` and `databricks_permissions.sql_endpoint` in `infra/env/databricks.tf`.

## Gotchas

- The first query after idle waits for a cold start.
- Firewalls on storage must allow Databricks serverless, which is why the
  [NSP](network-security-perimeter.md) exists.
- Leave schedules off when idle, or the warehouse wakes up and bills.

## Cost

About $0.30–0.50 per dbt run; $0 when stopped.

## Managed by

[Terraform](../tools/terraform.md), `infra/env/` (Databricks provider).

## Related docs

- [dbt](../tools/dbt.md), [Databricks workspace](databricks-workspace.md)
- [Medallion architecture](../concepts/medallion-architecture.md)
- [Stop/start](../concepts/stop-start.md)

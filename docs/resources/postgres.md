# Azure Database for PostgreSQL Flexible Server

A managed Postgres database. Azure handles backups, patching, and high availability (though
we disable HA for cost). You connect to it like any Postgres server.

## Why we need it

Dagster stores all of its operational state in Postgres: run history, asset materializations,
schedules, sensor state, event logs. We use one server with two databases (`dagster_stage`,
`dagster_prod`) — one per environment.

## Configuration

| Setting | Value | Why |
|---------|-------|-----|
| SKU | B1ms (1 vCPU, 2 GB RAM) | Smallest tier; Dagster's DB usage is light |
| Storage | 32 GB | Minimum. Dagster's metadata is small; actual data lives in [ADLS](adls.md) |
| HA | Disabled | Cost. Acceptable for a POC |
| Backup | 7-day retention | Default; sufficient for POC |
| Auth | Password (from [Key Vault](key-vault.md)) | Upgrade path: Entra auth with the [managed identity](managed-identity.md) |
| Network | Public access with firewall | Only your IP and the [AKS](aks.md) egress IP are allowed. See [corporate migration](../corporate-migration.md) for private endpoint path. |

## Cost

| State | Est. $/month |
|-------|-------------|
| Running | ~17 |
| Stopped | ~4 (storage only) |

Note: **Postgres auto-restarts after 7 consecutive stopped days** (Azure limitation). If
you're away longer, stop it again weekly or accept the running cost.

New Azure accounts may get 750 free B1ms hours/month for 12 months, which covers this.

## Provisioned by

[Terraform](../tools/terraform.md) — the server is in `infra/shared/`; the per-environment
databases and roles are in `infra/env/`.

## Related docs

- [AKS](aks.md) — the cluster that connects to Postgres
- [Key Vault](key-vault.md) — where the admin password is stored
- [Stop/start](../concepts/stop-start.md) — stopping Postgres to save money
- [Costs](../costs.md) — full cost breakdown

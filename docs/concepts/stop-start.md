# Stop / Start (cost control)

> **Type:** Concept · **Scope:** shared infrastructure · **Where:** `scripts/stop.sh`, `start.sh`, `teardown.sh`, `standup.sh`, `destroy-all.sh`

Pausing or deleting the pieces that bill while idle: the [AKS](../resources/aks.md) node and [Postgres](../resources/postgres.md).

## Why we use it

Databricks serverless, Key Vault, ACR, ADLS and the VNet cost nothing or a small flat fee when idle.
The cluster and database are the big items, so pausing them keeps the POC inside budget.

## How it's used here

| Level | Command | Effect | Recovery |
|-------|---------|--------|----------|
| 1. Stop | `just stop` / `just start` | `az aks stop` + Postgres stop. Data is preserved. Use overnight or weekends. | 3–5 min |
| 2. Teardown | `just teardown` / `just standup` | Deletes AKS, stops Postgres. Removes the load balancer and IP charge. Use for a week or more. | 10–15 min |
| 3. Destroy | `just destroy-all` | Destroys Helm releases, bundle files, `env` (prod then stage), `shared`, `bootstrap`. | Start over |

`standup` runs `terraform apply` for `shared`, starts Postgres, fetches credentials, then
re-runs Helm for each existing namespace. Dagster state is in Postgres, so nothing is lost.

| State | What bills | Approx. $/month |
|-------|-----------|------|
| Running | node + disk + LB/IP + Postgres + fixed items | ~100 |
| Stopped | disk, LB/IP, Postgres storage, fixed items | ~35–40 |
| Torn down | ACR, ADLS, Key Vault, Postgres storage | ~15 |

## Key commands & files

```bash
just stop && just start
just teardown && just standup
just destroy-all
```

## Gotchas

- Azure **restarts Postgres after 7 days stopped**. Re-stop it weekly or use teardown.
- The AKS egress IP can change after standup. Re-apply `env` stacks if they reference it, and re-run `collect-tf shared`.
- **Re-run `scripts/setup-arc.sh` after standup**, since ARC lives in the cluster.
- Keep the SQL warehouse auto-stop at 5 minutes, and keep schedules off while idle.
- `destroy-all` doesn't remove the Unity Catalog metastore, GitHub variables/environments, or local files.

## Cost

This concept *is* the cost lever. Record actual monthly spend in [costs](../costs.md).

## Managed by

The scripts above, wrapped by `just`.

## Related docs

- [AKS](../resources/aks.md), [Postgres](../resources/postgres.md), [ARC](../tools/arc.md)
- [Costs](../costs.md), [Network access](network-access.md)

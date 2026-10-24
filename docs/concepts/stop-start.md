# Stop / Start (cost control)

Two of the resources bill even when you're not using them: the [AKS](../resources/aks.md)
node (the VM) and [Postgres](../resources/postgres.md). Stopping them is like powering off
a computer — data is preserved, but nothing runs and billing drops.

[Databricks](../resources/databricks-workspace.md) serverless compute costs $0 when idle,
so there's nothing to stop there.

## Commands

```bash
just stop    # Stops AKS node pool + Postgres server (~2-3 minutes)
just start   # Starts them back up (~3-5 minutes)
```

Under the hood, these run `az aks stop` / `az aks start` and
`az postgres flexible-server stop` / `az postgres flexible-server start`.

When AKS starts back up, the Dagster pods come back automatically (Kubernetes Deployments
restart). The Dagster daemon catches up on any missed schedules (with `catchup` off, nothing
surprising happens).

## Cost impact

| State | What bills | Est. $/month |
|-------|-----------|-------------|
| **Running** | AKS node + OS disk + LB/IP + Postgres | ~100 |
| **Stopped** (`just stop`) | OS disk + LB/IP + Postgres storage | ~35–40 |
| **AKS deleted** (recreate from Terraform) | Postgres storage + minimal | ~15 |

## Gotchas

- **Postgres auto-restarts after 7 consecutive stopped days.** This is an Azure limitation.
  If you'll be away for more than a week, set a calendar reminder to run `just stop` weekly,
  or accept ~$13/month for the running Postgres.

- **AKS load balancer + public IP keep billing when stopped** (~$20/month). The only way to
  eliminate this is to delete the AKS cluster (`az aks delete`) and recreate it from
  Terraform (`just tf-apply shared`, ~10 min). State is in Postgres, so nothing is lost —
  just re-run the [Helm](../tools/helm.md) installs after.

- **AKS outbound IP may change after delete/recreate.** Terraform handles updating the
  firewall rules if the IP is a data source, but you'll need to re-apply.

- **SQL warehouse auto-stop is set to 5 minutes.** Don't raise it — every minute costs
  money.

- **Dagster schedules:** keep at most one daily run on stage while developing; turn off
  schedules when idle to avoid waking up the warehouse.

## Monthly

Check Azure Cost Management → Cost analysis, group by resource group. Expected floor
~$35–40. Record the actual in [costs.md](../costs.md).

## Related docs

- [AKS](../resources/aks.md) — the cluster being stopped/started
- [Postgres](../resources/postgres.md) — the database being stopped/started
- [Costs](../costs.md) — full cost breakdown

# Stop / Start (cost control)

Two of the resources bill even when you're not using them: the [AKS](../resources/aks.md)
node (the VM) and [Postgres](../resources/postgres.md). Everything else — Databricks
serverless, ACR, Key Vault, ADLS, VNet — costs $0 or a flat fee when idle.

There are two levels of cost control:

## Level 1: Stop (`just stop` / `just start`)

Pause AKS and Postgres. Like powering off a computer — data preserved, billing drops.
Use this for **overnight / weekend** idle.

```bash
just stop    # Stops AKS + Postgres (~2-3 min)
just start   # Starts them back up (~3-5 min)
```

Under the hood: `az aks stop/start` and `az postgres flexible-server stop/start`.
Resource names are derived from `TF_VAR_project` in `.env` (default `dagster`).

When AKS starts back up, Dagster pods come back automatically (Kubernetes Deployments
restart). The daemon catches up on any missed schedules (with `catchup` off, nothing
surprising happens).

## Level 2: Teardown (`just teardown` / `just standup`)

Delete AKS entirely and stop Postgres. Eliminates the load balancer and public IP charges
that keep billing even when stopped. Use this for **extended breaks** (a week+).

```bash
just teardown   # Deletes AKS, stops Postgres (interactive confirm, ~5 min)
just standup    # Recreates AKS via terraform apply, restarts Postgres,
                # re-deploys Helm releases (~10-15 min)
```

Standup runs `terraform apply` (which recreates the cluster), collects updated outputs
(the egress IP may change), and re-runs `helm upgrade` for each existing namespace.
All Dagster state lives in Postgres, so nothing is lost.

## Cost impact

| State | What bills | Est. $/month | Recovery |
|-------|-----------|-------------|----------|
| **Running** | AKS node + OS disk + LB/IP + Postgres | ~100 | — |
| **Stopped** (`just stop`) | OS disk + LB/IP + Postgres storage | ~35–40 | `just start` (~3–5 min) |
| **Torn down** (`just teardown`) | ACR + ADLS + KV + PG storage | ~15 | `just standup` (~10–15 min) |

## Gotchas

- **Postgres auto-restarts after 7 consecutive stopped days.** Azure limitation. If you'll
  be away longer, either run `just stop` weekly (calendar reminder), use `just teardown`
  instead, or accept ~$13/month for the running Postgres.

- **AKS load balancer + public IP keep billing when stopped** (~$20/month). This is why
  `just teardown` exists — deleting AKS is the only way to eliminate that charge.

- **AKS outbound IP may change after teardown/standup.** `just standup` runs
  `terraform apply` which updates firewall rules automatically, but if the `infra/env`
  stacks reference the egress IP, you'll need to re-apply those too.

- **SQL warehouse auto-stop is set to 5 minutes.** Don't raise it — every minute costs
  money.

- **Dagster schedules:** keep at most one daily run on stage while developing; turn off
  schedules when idle to avoid waking up the warehouse.

## Which level to use

| Situation | Command | Why |
|-----------|---------|-----|
| Done for the day, back tomorrow | `just stop` | Fast restart, LB cost is negligible day-to-day |
| Gone for a weekend | `just stop` | Same — ~$1.30 for 2 days of LB is fine |
| Gone for a week+ | `just teardown` | Saves ~$5/week on LB+IP; 10-min standup is worth it |
| Shutting down the POC | `just destroy-all` | Destroys everything in reverse order; see below |

## Full destroy (`just destroy-all`)

Deletes every Azure resource this repo provisioned, in reverse dependency order:
Helm releases → bundle files → `infra/env` (prod, then stage) → `infra/shared` →
`infra/bootstrap`. Terraform prompts for confirmation at each stack.

**Not deleted automatically:**
- Unity Catalog metastore (account-level, manual — the script reminds you)
- GitHub repo variables and environments
- Local `.env` and `infra/bootstrap/terraform.tfstate`

To start fresh after destroy: `scripts/setup-env.sh && just tf-init bootstrap && just tf-apply bootstrap`

## Monthly

Check Azure Cost Management → Cost analysis, group by resource group. Expected floor
~$35–40 stopped, ~$15 torn down. Record the actual in [costs.md](../costs.md).

## Related docs

- [AKS](../resources/aks.md) — the cluster being stopped/started/deleted
- [Postgres](../resources/postgres.md) — the database being stopped/started
- [Costs](../costs.md) — full resource inventory and cost breakdown

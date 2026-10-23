# 06 — Stop / start (cost control)

Databricks serverless costs nothing idle. The two things that bill while idle and can be stopped are
the AKS node and Postgres compute.

## Daily
```
scripts/stop.sh     # az aks stop + az postgres flexible-server stop
scripts/start.sh    # reverse; waits for nodes Ready and Postgres Ready
```
AKS stop takes ~2–3 min; start ~3–5 min. Pods come back on their own (Deployments). Dagster daemon
will catch up schedules per its settings; with `catchup` off nothing surprising happens.

## Gotchas
- **Postgres auto-restarts after 7 consecutive stopped days.** If you'll be away >7 days, set a
  calendar reminder to run `scripts/stop.sh` weekly, or accept ~$13/mo.
- AKS stop keeps the Standard LB and public IP billing (~$20/mo). Only `az aks delete` removes that;
  recreate with `terraform -chdir=infra/shared apply` (~10 min) and re-run Phase 2.6/4.4 Helm installs
  (state is in Postgres, so nothing is lost).
- The AKS outbound IP can change after delete/recreate; re-apply Phase 1.3 firewall rules
  (Terraform handles this if the IP is a data source).
- Serverless SQL warehouse auto-stop is 5 min; don't raise it.
- Dagster schedules on stage: keep at most one daily run while developing; turn off when idle.

## Monthly
Check Cost Management → Cost analysis, group by resource group. Expected floor ~$35–40.
Record the actual in `02-services-and-costs.md`.

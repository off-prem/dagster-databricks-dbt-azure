# AKS Egress IP (load balancer and public IP)

> **Type:** Resource · **Scope:** shared · **Name:** AKS-managed public IP in the `MC_` node resource group · **Stack:** created by AKS, read by `infra/shared`

The public IP address that all outbound traffic from pods and ARC runners appears to come from.

## Why we use it

Key Vault, Postgres, the Databricks workspace and others only accept known callers. Because the cluster has one stable egress IP,
a single `/32` entry per service admits Dagster, the runners and the smoke test.

## How it's used here

- AKS creates a Standard load balancer and a public IP for outbound traffic. There are no inbound rules and no Ingress.
- Terraform **looks up** the IP (`data.azurerm_public_ip.aks_egress`) and uses it in the firewall rules below. It does not create it.
- `scripts/setup-env.sh collect-tf shared` stores it as `AKS_EGRESS_IP` in `.env`, and `env` passes it to the Databricks IP access list.

| Consumer | Rule |
|----------|------|
| [Key Vault](key-vault.md) | firewall `ip_rules` |
| [Postgres](postgres.md) | firewall rule `aks-egress` |
| [Databricks workspace](databricks-ip-access-list.md) | IP access list `aks-egress` |

## Key commands & files

```bash
source scripts/load-env.sh && echo "$AKS_EGRESS_IP"
scripts/setup-env.sh collect-tf shared
```

Terraform: `infra/shared/main.tf` (the lookup and the rules), `infra/shared/outputs.tf` (`aks_egress_ip`).

## Gotchas

- **It bills even when AKS is stopped** (about $20/month with the load balancer). Only deleting the cluster removes it.
- **It can change after `just teardown` / `just standup`.** After standup, re-apply `shared` and both `env` stacks and re-run `collect-tf`.
- If pods suddenly can't reach Key Vault, Postgres or Databricks, compare the live egress IP with the firewall entries first.
- Don't add an inbound rule or Service of type LoadBalancer for Dagster; that violates the no-public-ingress rule.

## Cost

About $20/month with the load balancer (see [costs](../costs.md)).

## Managed by

[AKS](aks.md) creates it; [Terraform](../tools/terraform.md) reads it.

## Related docs

- [Network access](../concepts/network-access.md), [Stop/start](../concepts/stop-start.md)
- [Databricks IP access list](databricks-ip-access-list.md), [Resource groups](resource-groups.md)

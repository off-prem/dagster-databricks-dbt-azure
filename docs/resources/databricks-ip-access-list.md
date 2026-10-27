# Databricks IP Access Lists

> **Type:** Resource · **Scope:** per-env · **Names:** `user-ip`, `aks-egress` · **Stack:** `infra/env` (Databricks provider)

A workspace-level allow-list of IP addresses that may reach the workspace UI and API.

## Why we use it

The workspace has a public URL. Restricting it to your machine and the AKS egress address keeps the control plane gated without private networking.

## How it's used here

| Resource | Contents |
|----------|----------|
| `databricks_workspace_conf.ip_access` | Turns `enableIpAccessLists` on |
| `databricks_ip_access_list.user` | `ALLOW` list: your IP (`TF_VAR_my_ip_cidr`) |
| `databricks_ip_access_list.aks_egress` | `ALLOW` list: `<AKS egress IP>/32` |

Dagster pods, the [ARC](../tools/arc.md) runners and the Databricks CLI in CI all reach the workspace from the AKS egress IP, which is why no per-run whitelisting is needed.

## Key commands & files

```bash
just setup-env           # re-detect your IP
just tf-apply env-stage  # update the list
databricks ip-access-lists list
```

Terraform: `infra/env/databricks.tf`.

## Gotchas

- **Your IP changed:** you are locked out of the workspace API (and Terraform's Databricks provider fails). Fix your IP in `.env` and apply from a network that is still allowed, or use the Azure portal to reach the workspace admin settings.
- **AKS egress IP changed** (after teardown/standup): pods can't reach Databricks until you re-apply `env` with the new `AKS_EGRESS_IP`.
- The lists are applied per workspace, so apply both `env-stage` and `env-prod`.
- Developers on other networks (a coworker, a VPN) need their own entry.

## Cost

Free.

## Managed by

[Terraform](../tools/terraform.md), `infra/env/databricks.tf`.

## Related docs

- [Network access](../concepts/network-access.md), [AKS egress IP](aks-egress-ip.md), [Databricks workspace](databricks-workspace.md)
- [Stop/start](../concepts/stop-start.md)

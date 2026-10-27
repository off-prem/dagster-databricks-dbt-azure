# VNet (Virtual Network)

> **Type:** Resource · **Scope:** shared · **Name:** `vnet-<project>` · **Stack:** `infra/shared`

An isolated private network in Azure, divided into subnets, with a Network Security Group (NSG) as a firewall.

## Why we use it

[AKS](aks.md) needs a network. The POC uses public endpoints behind firewalls, but laying out
subnets now means the [corporate migration](../corporate-migration.md) to private endpoints
and VNet injection doesn't require redesigning the network.

## How it's used here

Address space `10.0.0.0/16`:

| Subnet | Range | Use |
|--------|-------|-----|
| `snet-aks` | `10.0.0.0/22` | AKS nodes (in use) |
| `snet-pe` | `10.0.4.0/24` | Private endpoints (reserved) |
| `snet-dbx-host` | `10.0.8.0/22` | Databricks VNet injection host (reserved) |
| `snet-dbx-container` | `10.0.12.0/22` | Databricks VNet injection container (reserved) |

One NSG, `nsg-<project>-shared`, is associated with the three reserved subnets.
The Databricks subnets are delegated to `Microsoft.Databricks/workspaces`.

## Key commands & files

```bash
az network vnet show --resource-group rg-dagster-shared --name vnet-dagster --query addressSpace
```

Terraform: `infra/shared/main.tf`.

## Gotchas

- Today's workspaces use a managed VNet, so the Databricks subnets are unused. They cost nothing.
- Don't change the address space after resources are attached; it forces replacement.
- Peering to a corporate network later requires non-overlapping ranges. Check `10.0.0.0/16` first.

## Cost

$0.

## Managed by

[Terraform](../tools/terraform.md), `infra/shared/`.

## Related docs

- [AKS](aks.md), [Network access](../concepts/network-access.md)
- [Architecture](../architecture.md), [Corporate migration](../corporate-migration.md)

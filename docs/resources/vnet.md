# VNet (Virtual Network)

An isolated private network in Azure. Resources inside the VNet can talk to each other
over private IPs. Subnets divide the network into segments; a Network Security Group (NSG)
acts as a firewall with rules for what traffic is allowed in and out.

## Why we need it

The [AKS](aks.md) cluster needs a network to run in. Even though the POC uses public
endpoints (gated by firewalls and IP restrictions), having the VNet in place means the
network layout is already correct for the [corporate migration](../corporate-migration.md),
where everything moves to private endpoints.

## Configuration

| Setting | Value |
|---------|-------|
| Address space | `10.10.0.0/16` |
| `snet-aks` | AKS node pool subnet |
| `snet-pe` | Reserved for private endpoints (unused in POC) |
| `snet-dbx-host` | Reserved for Databricks VNet injection host subnet (unused in POC) |
| `snet-dbx-container` | Reserved for Databricks VNet injection container subnet (unused in POC) |
| NSG | Applied to `snet-aks`; default rules |

The reserved subnets cost nothing — they're just address ranges. They're included so you
don't have to redesign the network when adding private endpoints or VNet-injected
Databricks later.

## Cost

$0. Virtual networks are free.

## Provisioned by

[Terraform](../tools/terraform.md) — `infra/shared/` stack.

## Related docs

- [AKS](aks.md) — runs in `snet-aks`
- [Architecture](../architecture.md) — the public-vs-gated table shows which endpoints
  are public and what the corporate posture would be
- [Corporate migration](../corporate-migration.md) — adding private endpoints and VPN

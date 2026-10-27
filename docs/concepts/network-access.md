# Network Access (public but gated)

> **Type:** Concept · **Scope:** shared + per-env · **Where:** firewall settings in `infra/`

The POC has no VPN or private endpoints. Every service has a public endpoint, but each is restricted
by identity and by IP allow-lists. This page lists who may reach what.

## Why we use it

Private networking adds a lot of fixed cost ([decision 10](../decisions.md)) and no application changes
when added later. The gates below give reasonable protection for a POC.

## How it's used here

| Service | Gate |
|---------|------|
| Dagster UI | No ingress. ClusterIP only; reach it by `kubectl port-forward` |
| [AKS](../resources/aks.md) API server | Authorized IP ranges = your IP, plus Entra and Azure RBAC |
| [Key Vault](../resources/key-vault.md) | Firewall default deny: your IP + AKS egress IP |
| [Postgres](../resources/postgres.md) | Firewall rules `user-ip` and `aks-egress`; TLS required |
| [ADLS](../resources/adls.md) | Firewall default deny: your IP + access-connector resource rules; [NSP](../resources/network-security-perimeter.md) in Learning mode; key auth off |
| [Databricks workspace](../resources/databricks-workspace.md) | IP access list: your IP + AKS egress IP |
| [ACR](../resources/acr.md) | Public, Entra auth, admin user disabled |

**Where traffic comes from:**
- You: `TF_VAR_my_ip_cidr` in `.env`.
- Pods and CI runners: the AKS egress IP (looked up by Terraform and captured as `AKS_EGRESS_IP`).
  [ARC](../tools/arc.md) runners live in AKS, so they use the same IP and need no temporary whitelisting.
- Databricks serverless: Databricks-managed ranges, admitted to storage by the access connector and the NSP.

## Key commands & files

```bash
scripts/setup-env.sh              # refreshes TF_VAR_my_ip_cidr
just tf-apply shared              # pushes new IPs into the firewalls
curl -s ifconfig.me
```

## Gotchas

- **When your IP changes** you lose access to AKS, Key Vault, Postgres, storage and the workspace. Update `.env`, then re-apply `shared` and `env`.
- **When the AKS egress IP changes** (after teardown/standup) pods lose access to Key Vault, Postgres and the workspace. Re-apply and re-collect outputs.
- The `0.0.0.0/32` placeholder in `pr-checks.yml` is only for validation and is never applied.
- The [corporate migration](../corporate-migration.md) replaces these gates with private endpoints and a VPN.

## Cost

Free; this is the cheap alternative to private networking.

## Managed by

[Terraform](../tools/terraform.md) (all firewall rules); IPs come from `.env`.

## Related docs

- [VNet](../resources/vnet.md), [Architecture](../architecture.md), [Corporate migration](../corporate-migration.md)
- [Stop/start](stop-start.md), [CI/CD](cicd.md)

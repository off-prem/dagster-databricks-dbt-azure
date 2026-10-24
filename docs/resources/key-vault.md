# Azure Key Vault

A managed secrets store. You put sensitive values in (passwords, API keys, client secrets)
and applications retrieve them at runtime. Access is controlled by Azure RBAC — only
identities with the right role can read secrets.

## Why we need it

Several components need credentials:
- Dagster pods need the Postgres password
- Dagster pods need the Databricks service principal client ID and secret
- The source API may need an API key

Instead of putting these in config files, Helm values, or environment variables (all of
which could leak into git or logs), they live in Key Vault. Dagster pods retrieve them
at startup via the **Secrets Store CSI driver** — a Kubernetes addon that mounts Key Vault
secrets as files inside the pod.

## Secrets stored

| Secret name | What it is | Written by |
|-------------|-----------|-----------|
| `pg-admin-password` | Postgres admin password | You (Phase 1.3) |
| `pg-dagster-<env>-password` | Per-env Postgres role password | Terraform |
| `dbx-<env>-sp-client-id` | [Databricks SP](../resources/databricks-workspace.md) client ID | Terraform |
| `dbx-<env>-sp-secret` | Databricks SP OAuth secret | Terraform |
| `source-api-key` | API key for the data source (if needed) | You (Phase 3.1) |

## Configuration

| Setting | Value | Why |
|---------|-------|-----|
| SKU | Standard | Premium adds HSM-backed keys; not needed |
| Access model | RBAC | Permissions via Azure role assignments (not access policies) |
| Firewall | Your IP + [AKS](aks.md) egress IP | Restricts network access |

## How pods access secrets

1. The pod runs with a Kubernetes service account linked to a [managed identity](managed-identity.md)
   via [workload identity](../concepts/workload-identity.md).
2. The managed identity has the **Key Vault Secrets User** role on this vault.
3. A `SecretProviderClass` (in `deploy/k8s/<env>/`) tells the CSI driver which secrets to
   fetch and where to mount them.
4. On pod startup, the driver fetches the secrets and makes them available as environment
   variables or files inside the pod.

## Cost

Less than $1/month. Billing is per-operation (pennies per 10,000 operations).

## Provisioned by

[Terraform](../tools/terraform.md) — `infra/shared/` stack. Secrets are written by Terraform
(SP credentials) or manually via `az keyvault secret set` (passwords, API keys).

## Related docs

- [Workload identity](../concepts/workload-identity.md) — how pods authenticate to Key Vault
- [Managed identity](managed-identity.md) — the identity that has Key Vault access
- [AKS](aks.md) — the cluster whose pods read from Key Vault
- [Helm](../tools/helm.md) — deploys the SecretProviderClass and pod config

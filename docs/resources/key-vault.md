# Azure Key Vault

> **Type:** Resource · **Scope:** shared · **Name:** `kv-<project>-<random>` · **Stack:** `infra/shared`

A managed secrets store with access controlled by Azure RBAC.

## Why we use it

Secrets must not be in the repo, Helm values or `.env` files that get committed. Pods fetch
them at start through the [CSI driver](../tools/secrets-store-csi-driver.md).

## How it's used here

| Setting | Value |
|---------|-------|
| SKU | Standard |
| Access model | Azure RBAC (not access policies) |
| Firewall | Default **deny**; allows your IP, the AKS egress IP, and the `AzureServices` bypass |
| Purge protection | Off (POC; lets `destroy-all` finish), 7-day soft delete |

**Secrets:**

| Name | Contents | Written by |
|------|----------|-----------|
| `pg-admin-password` | Postgres admin password (random) | Terraform (`shared`) |
| `dbx-<env>-sp-client-id` | [Databricks SP](databricks-service-principal.md) client ID | Terraform (`env`) |
| `dbx-<env>-sp-secret` | Databricks SP OAuth secret | Terraform (`env`) |
| `source-posts-api-key` | API key for the source API | You, with `az keyvault secret set` |
| `arc-github-app-key` | [GitHub App](github-app.md) private key for [ARC](../tools/arc.md) | You |

**Roles:** the Terraform applier has *Secrets Officer*; each env's
[managed identity](managed-identity.md) has *Secrets User*.

## Key commands & files

```bash
az keyvault secret set --vault-name "$KV_NAME" --name source-posts-api-key --value '<value>'
az keyvault secret list --vault-name "$KV_NAME" -o table
```

## Gotchas

- A new role assignment takes time to propagate. Terraform waits 30 s before writing the
  first secret to avoid a 403.
- From a new network you get 403 until your IP is allow-listed (re-apply `shared`).
- Secrets are synced to pods only while a pod mounts the CSI volume.
- Never paste a secret value into chat, commits or logs.

## Cost

Under $1/month.

## Managed by

[Terraform](../tools/terraform.md), `infra/shared/` (vault, roles, Terraform-written secrets); manual `az` for the rest.

## Related docs

- [Secrets flow](../concepts/secrets-flow.md), [Workload identity](../concepts/workload-identity.md)
- [Managed identity](managed-identity.md), [AKS](aks.md)
- [Network access](../concepts/network-access.md)

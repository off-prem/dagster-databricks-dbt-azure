# Secrets Flow

> **Type:** Concept · **Scope:** per-env · **Where:** Key Vault → CSI → pods

The end-to-end path a secret takes from where it is created to where code reads it. No secret is stored in git, in Helm values, or in GitHub.

## Why we use it

Each hop uses a short-lived or managed identity, so there is no long-lived credential to leak
besides the secrets themselves, and those live in one audited place.

## How it's used here

```
Terraform / you  ->  Key Vault  ->  CSI driver (workload identity)  ->  K8s Secret  ->  env var  ->  code
```

| Secret | Created by | Pod env var | Used by |
|--------|-----------|-------------|---------|
| `dbx-<env>-sp-client-id` / `-sp-secret` | Terraform | `DBX_SP_CLIENT_ID`, `DBX_SP_SECRET` | Dagster SDK calls and dbt |
| `source-posts-api-key` | you (`az keyvault secret set`) | `SOURCE_POSTS_API_KEY` | passed to the Databricks job as a Pipes extra |
| `pg-admin-password` | Terraform | via Secret `dagster-postgres` | Dagster's Postgres connection |
| `arc-github-app-key` | you | n/a (copied by `setup-arc.sh`) | [ARC](../tools/arc.md) |

Steps at pod start: the pod's service account is federated to a
[managed identity](../resources/managed-identity.md); the [CSI driver](../tools/secrets-store-csi-driver.md)
uses it to read [Key Vault](../resources/key-vault.md); the `SecretProviderClass` `secretObjects`
sync values into Kubernetes Secrets; Helm `envSecrets` expose them as env vars.

CI has no application secrets: it uses [OIDC](oidc.md) and variables that hold only IDs.

## Key commands & files

```bash
kubectl get secret -n dagster-stage dagster-dbx-stage -o jsonpath='{.data}' | jq 'keys'   # keys only
```

Files: `deploy/k8s/<env>/secretproviderclass.yaml`, `deploy/helm/values.<env>.yaml`.

## Gotchas

- Print key names, not values. Never paste a secret into chat, commits or logs.
- Secrets reach pods only if the pod mounts the CSI volume and has the workload-identity label. Run pods need both set explicitly.
- Changing a Key Vault value doesn't restart pods. Rotation syncs the mount, but env vars are read at start,
  so restart the deployment.
- The Postgres admin password, the SP secret and the API key are all in Terraform state or Key Vault. Protect both.

## Cost

Free.

## Managed by

[Terraform](../tools/terraform.md), manual `az` commands, and [Helm](../tools/helm.md).

## Related docs

- [Key Vault](../resources/key-vault.md), [Workload identity](workload-identity.md)
- [Databricks service principal](../resources/databricks-service-principal.md)
- [Helm deployments](helm-deployments.md)

# SecretProviderClass (`dagster-secrets`)

> **Type:** Resource · **Scope:** per-env (one per Dagster namespace) · **Name:** `dagster-secrets` · **Files:** `deploy/k8s/<env>/secretproviderclass.yaml`

A Kubernetes custom resource that tells the [CSI driver](../tools/secrets-store-csi-driver.md) which Key Vault secrets to fetch, which identity to use, and how to turn them into Kubernetes secrets.

## Why we use it

It is the only place that maps Key Vault secret names to the environment-variable names the pods expect. Helm, the pod specs and the code all depend on it.

## How it's used here

| Part | Value |
|------|-------|
| Provider | `azure` (workload identity; `usePodIdentity` and `useVMManagedIdentity` are false) |
| Identity | the env's [managed identity](managed-identity.md), client ID `${DAGSTER_<ENV>_IDENTITY_CLIENT_ID}` |
| Vault | `${KV_NAME}`, tenant `${TF_VAR_tenant_id}` |
| Objects fetched | `dbx-<env>-sp-client-id`, `dbx-<env>-sp-secret`, `source-posts-api-key`, `pg-admin-password` |
| Secret `dagster-dbx-<env>` | `DBX_SP_CLIENT_ID`, `DBX_SP_SECRET`, `SOURCE_POSTS_API_KEY` |
| Secret `dagster-postgres` | `postgresql-password` (the key the Dagster chart expects) |

Apply it after the namespace exists and before the first Helm install.

## Key commands & files

```bash
envsubst < deploy/k8s/prod/secretproviderclass.yaml | kubectl apply -f -
kubectl get secretproviderclass -n dagster-stage
```

## Gotchas

- The manifests contain `${VAR}` placeholders. Applying them unresolved fails (the guide's stage step edits by hand, while prod uses `envsubst`).
- Adding a secret means editing **both** `objects` and `secretObjects`, then the Helm values (`envSecrets`), then restarting the pods.
- Every pod that needs the secrets must mount the CSI volume. Run pods too.
- A wrong identity client ID or a Key Vault firewall block shows up as a pod stuck in `ContainerCreating` with a mount error.

## Cost

Free.

## Managed by

`kubectl apply` by hand. Not Terraform or Helm.

## Related docs

- [Secrets Store CSI driver](../tools/secrets-store-csi-driver.md), [Secrets flow](../concepts/secrets-flow.md)
- [Kubernetes secrets](kubernetes-secrets.md), [Key Vault](key-vault.md), [Workload identity](../concepts/workload-identity.md)

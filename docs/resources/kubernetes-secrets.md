# Kubernetes Secrets

> **Type:** Resource · **Scope:** per-namespace · **Names:** `dagster-dbx-<env>`, `dagster-postgres`, `arc-github-app`

The Kubernetes `Secret` objects in the cluster. None is written by hand with a literal value from the repo.

## Why we use it

Pods consume credentials as environment variables, and Kubernetes only exposes env vars from `Secret` objects. These are the bridge from [Key Vault](key-vault.md) to the process environment.

## How it's used here

| Secret | Namespace | Keys | Source |
|--------|-----------|------|--------|
| `dagster-dbx-<env>` | `dagster-<env>` | `DBX_SP_CLIENT_ID`, `DBX_SP_SECRET`, `SOURCE_POSTS_API_KEY` | synced from Key Vault by the [SecretProviderClass](secret-provider-class.md) |
| `dagster-postgres` | `dagster-<env>` | `postgresql-password` | synced from `pg-admin-password` |
| `arc-github-app` | `arc-systems` | `github_app_id`, `github_app_installation_id`, `github_app_private_key` | created by `scripts/setup-arc.sh` from `.env` and Key Vault |
| Helm release records | each Helm namespace | release history | created by Helm |

The synced secrets are consumed through `envSecrets` in the Helm values, by both the code server and the run pods. The Postgres secret is referenced by `global.postgresqlSecretName`.

## Key commands & files

```bash
kubectl get secret -n dagster-stage
kubectl get secret -n dagster-stage dagster-dbx-stage -o json | jq '.data | keys'    # keys only
```

## Gotchas

- **Never print values.** Use `jq '.data | keys'`, not `-o yaml` pasted into chat.
- The synced secrets exist only while a pod mounts the CSI volume. With no pod running, they can vanish.
- Rotating a value in Key Vault updates the mount but not running env vars, so restart the pods.
- `setup-arc.sh` deletes and recreates `arc-github-app` on every run to pick up key rotation.
- Anyone with `get secret` rights in a namespace can read these values. The cluster grants that through Azure RBAC.

## Cost

Free.

## Managed by

The CSI driver, `scripts/setup-arc.sh`, and Helm.

## Related docs

- [Secret provider class](secret-provider-class.md), [Secrets flow](../concepts/secrets-flow.md), [GitHub App](github-app.md)
- [Secrets Store CSI driver](../tools/secrets-store-csi-driver.md), [Kubernetes namespaces](kubernetes-namespaces.md)

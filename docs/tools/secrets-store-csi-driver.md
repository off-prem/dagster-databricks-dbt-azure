# Secrets Store CSI driver

> **Type:** Tool · **Scope:** shared (AKS add-on), configured per-env · **Where:** `deploy/k8s/<env>/`

A Kubernetes add-on that mounts secrets from an external vault into pods. The Azure
provider reads from [Key Vault](../resources/key-vault.md).

## Why we use it

Secrets must not live in the repo, in Helm values or in hand-made Kubernetes secrets. The
driver fetches them at pod start using the pod's [workload identity](../concepts/workload-identity.md),
and the application never handles Azure credentials.

## How it's used here

- **Enabled on AKS** through the `key_vault_secrets_provider` block in Terraform, with
  secret rotation on.
- **`SecretProviderClass` `dagster-secrets`** (one per namespace, in `deploy/k8s/<env>/`)
  lists the Key Vault objects to fetch (`dbx-<env>-sp-client-id`, `dbx-<env>-sp-secret`,
  `source-posts-api-key`, `pg-admin-password`) and the managed identity's client ID.
- **`secretObjects`** sync the mounted values into two Kubernetes secrets:
  `dagster-dbx-<env>` (`DBX_SP_CLIENT_ID`, `DBX_SP_SECRET`, `SOURCE_POSTS_API_KEY`) and
  `dagster-postgres` (`postgresql-password`).
- The code server and run pods mount the CSI volume at `/mnt/secrets-store` and load
  `dagster-dbx-<env>` through `envSecrets`.

## Key commands & files

```bash
kubectl get secretproviderclass -n dagster-stage
kubectl describe pod -n dagster-stage <pod>      # look for mount errors in Events
```

Files: `deploy/k8s/stage/secretproviderclass.yaml`, `deploy/k8s/prod/secretproviderclass.yaml`.

## Gotchas

- Kubernetes secrets are created **only while a pod mounts the volume**. A pod without the
  CSI volume sees no secrets, which is why run pods need the volume repeated in their config.
- The pod needs the label `azure.workload.identity/use: "true"` or the mount fails to authenticate.
- The `SecretProviderClass` contains `${...}` placeholders for the Key Vault name, tenant and
  identity client ID. Resolve them first, for example
  `envsubst < deploy/k8s/prod/secretproviderclass.yaml | kubectl apply -f -`.
  The per-env READMEs in `deploy/k8s/` describe this flow.
- Role assignments take a few minutes to propagate. A fresh deploy can fail the first mount.

## Cost

Free.

## Managed by

Add-on enabled by [Terraform](terraform.md) (`infra/shared/`); `SecretProviderClass` applied with kubectl.

## Related docs

- [Secrets flow](../concepts/secrets-flow.md): end-to-end path of a secret
- [Key Vault](../resources/key-vault.md), [Managed identity](../resources/managed-identity.md)
- [Workload identity](../concepts/workload-identity.md)

# User-Assigned Managed Identity

> **Type:** Resource · **Scope:** per-env · **Name:** `id-<project>-<env>` · **Stack:** `infra/env`

An Azure identity you create and attach to workloads. Azure manages its credentials, so no
password exists.

## Why we use it

Dagster pods must read [Key Vault](key-vault.md) without storing a credential. The pod acts
as this identity through [workload identity](../concepts/workload-identity.md).

## How it's used here

1. Terraform creates `id-<project>-<env>`.
2. It receives *Key Vault Secrets User* on the shared vault.
3. A federated credential `fed-<project>-<env>` links it to the Kubernetes service account
   `<project>-<env>` in namespace `<project>-<env>` (for example `dagster-stage/dagster-stage`),
   using the AKS OIDC issuer.
4. The service account is annotated with the identity's client ID
   (`azure.workload.identity/client-id`, from `DAGSTER_<ENV>_IDENTITY_CLIENT_ID`), and pods
   carry the label `azure.workload.identity/use: "true"`.

## Key commands & files

```bash
scripts/setup-env.sh collect-tf env-stage     # stores the identity's client ID
```

Terraform: `infra/env/main.tf`. Consumers: `deploy/helm/values.<env>.yaml` and `deploy/k8s/<env>/secretproviderclass.yaml`.

## Gotchas

- The federated subject must match the service account name **and** namespace exactly.
  Renaming the Helm release breaks authentication silently (the mount fails).
- The service account name is `<project>-<env>` (the Helm release name), not
  `dagster-user-deployments`.
- Stage and prod have separate identities. Don't share one across namespaces.

## Cost

Free.

## Managed by

[Terraform](../tools/terraform.md), `infra/env/` (`modules/identity` is only a README so far).

## Related docs

- [Workload identity](../concepts/workload-identity.md), [Secrets flow](../concepts/secrets-flow.md)
- [Key Vault](key-vault.md), [AKS](aks.md), [Azure RBAC](../concepts/azure-rbac.md)
- [Entra app](entra-app.md): the equivalent for GitHub Actions

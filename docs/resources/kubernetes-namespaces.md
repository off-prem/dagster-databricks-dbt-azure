# Kubernetes Namespaces

> **Type:** Resource · **Scope:** in the one AKS cluster · **Names:** `dagster-stage`, `dagster-prod`, `arc-systems`, `arc-runners`

Logical partitions of the cluster. Two hold the Dagster environments; two hold the CI runner system.

## Why we use it

One cluster serves both environments ([decision 2](../decisions.md)). Namespaces keep stage and prod releases, secrets and service accounts separate.

## How it's used here

| Namespace | Holds | Created by |
|-----------|-------|-----------|
| `<project>-stage` | Dagster stage release, `SecretProviderClass`, secrets, service account | `kubectl create namespace` in guide 2.5, and `helm --create-namespace` |
| `<project>-prod` | Same for prod | guide 4.4, and `helm --create-namespace` |
| `arc-systems` | ARC controller, listener, `arc-github-app` secret | `scripts/setup-arc.sh` |
| `arc-runners` | `arc-runner-set` and ephemeral runner pods | `scripts/setup-arc.sh` |

The Dagster namespace is `<project>-<env>`, which is also the Helm release name and the service-account name, and the federated credential subject uses all three.
The `SecretProviderClass` must be applied **before** the Helm install, so the namespace is created ahead of Helm.

## Key commands & files

```bash
kubectl get ns
kubectl get all -n dagster-stage
kubectl create namespace dagster-stage --dry-run=client -o yaml | kubectl apply -f -
```

## Gotchas

- Renaming a namespace changes the [managed identity](managed-identity.md) subject and breaks Key Vault access.
- Deleting AKS deletes all namespaces. `just standup` recreates the Dagster ones through Helm, and the ARC ones through `setup-arc.sh`.
- `standup.sh` only re-deploys a namespace that already exists, so create it again by hand if you destroyed it.
- Each namespace has its own copy of secrets. A secret in `dagster-stage` isn't visible in `dagster-prod`.

## Cost

Free; they only use node capacity.

## Managed by

`kubectl` (guide), `helm --create-namespace`, and `scripts/setup-arc.sh`. Not Terraform.

## Related docs

- [Helm releases](helm-releases.md), [Secret provider class](secret-provider-class.md), [Kubernetes secrets](kubernetes-secrets.md)
- [AKS](aks.md), [ARC](../tools/arc.md), [Helm deployments](../concepts/helm-deployments.md)

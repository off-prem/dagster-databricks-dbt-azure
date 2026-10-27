# Workload Identity

> **Type:** Concept · **Scope:** per-env · **Where:** `infra/env/main.tf`, `deploy/helm/`

How a Kubernetes pod gets an Azure identity with no stored credential. It is the pod-side
equivalent of [OIDC](oidc.md) for GitHub Actions.

## Why we use it

Pods need to read [Key Vault](../resources/key-vault.md). The alternatives are worse: a stored
credential is another secret to protect, and a node-wide identity gives every pod the same permissions.
Workload identity gives each service account its own, short-lived identity.

## How it's used here

```
Pod starts
  -> AKS injects a service-account token (signed by the cluster's OIDC issuer)
  -> token is exchanged with Entra: "I am dagster-stage/dagster-stage"
  -> Entra matches a federated credential and returns a token for the managed identity
  -> CSI driver uses it to read Key Vault
```

| Piece | Where |
|-------|-------|
| OIDC issuer + workload identity enabled | [AKS](../resources/aks.md) |
| [Managed identity](../resources/managed-identity.md) `id-<project>-<env>` with *Key Vault Secrets User* | `infra/env/` |
| Federated credential for subject `system:serviceaccount:<project>-<env>:<project>-<env>` | `infra/env/` |
| Service account annotation `azure.workload.identity/client-id` | `values.<env>.yaml` |
| Pod label `azure.workload.identity/use: "true"` | code server **and** run pods |

## Key commands & files

```bash
kubectl get sa -n dagster-stage dagster-stage -o yaml
kubectl describe pod -n dagster-stage <pod>      # check the mount and token projection
```

## Gotchas

- Subject mismatch (wrong namespace or service account name) shows up as a failed secret mount, not a clear auth error.
- The label has to be on every pod that mounts secrets, including run pods.
- Tokens are short-lived and refreshed automatically; there is nothing to rotate.

## Cost

Free.

## Managed by

[Terraform](../tools/terraform.md) for Azure parts; [Helm](../tools/helm.md) for the annotation and labels.

## Related docs

- [Managed identity](../resources/managed-identity.md), [Key Vault](../resources/key-vault.md)
- [Secrets Store CSI driver](../tools/secrets-store-csi-driver.md), [Secrets flow](secrets-flow.md)
- [OIDC](oidc.md)

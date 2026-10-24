# Workload Identity

A mechanism that lets Kubernetes pods authenticate to Azure services without stored
credentials. It's the pod-side equivalent of [OIDC](oidc.md) for GitHub Actions.

## The problem it solves

Dagster pods need to read secrets from [Key Vault](../resources/key-vault.md) (database
passwords, Databricks credentials). Without workload identity, you'd either:
- Put the Key Vault credentials in a Kubernetes Secret (another secret to manage and rotate)
- Use a node-level identity (every pod on the node gets the same permissions — no isolation)

Workload identity gives each pod its own Azure identity with only the permissions it needs.

## How it works

The flow connects three systems: **Azure**, **Kubernetes**, and the **pod**:

```
Pod starts
  → Kubernetes injects a service account token (JWT signed by AKS's OIDC issuer)
  → Pod presents the token to Azure: "I am dagster-stage/dagster-user-deployments"
  → Azure checks: "Is this token from a trusted OIDC issuer?
                    Does a federated credential match this service account?"
  → Azure issues an access token for the managed identity
  → Pod uses the access token to read Key Vault secrets
```

### Setup steps (handled by Terraform)

1. **AKS OIDC issuer** — the cluster is created with OIDC issuer enabled, which gives it a
   public URL that Azure can verify tokens against.
2. **Managed identity** — `id-dagster-<env>` is created with the **Key Vault Secrets User**
   role on the vault.
3. **Federated credential** — links the managed identity to the Kubernetes service account
   `dagster-<env>/dagster-user-deployments`, using the AKS OIDC issuer URL.
4. **Pod labels** — [Helm](../tools/helm.md) adds `azure.workload.identity/use: "true"` to
   the pod spec, which tells the AKS webhook to inject the token.

### At runtime

The Secrets Store CSI driver (an AKS addon) uses the workload identity token to fetch
secrets from Key Vault and mount them inside the pod as environment variables or files.
The application code never sees the Azure credentials — it just reads the mounted secrets.

## Why not a service principal secret?

A service principal secret is a long-lived password. Workload identity tokens are
short-lived (hours) and automatically refreshed. No secret to rotate, no secret to leak.

## Related docs

- [Managed identity](../resources/managed-identity.md) — the Azure identity pods use
- [Key Vault](../resources/key-vault.md) — what the identity accesses
- [AKS](../resources/aks.md) — the cluster with the OIDC issuer
- [OIDC](oidc.md) — the same concept for GitHub Actions
- [Helm](../tools/helm.md) — adds the pod labels and SecretProviderClass

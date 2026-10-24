# User-Assigned Managed Identity

An Azure identity that you create and assign to resources (like Kubernetes pods). The
resource can then authenticate to Azure services using this identity — no passwords or
secrets needed. Azure manages the credentials behind the scenes.

## Why we need it

Dagster pods running in [AKS](aks.md) need to read secrets from [Key Vault](key-vault.md)
(database passwords, Databricks credentials). Instead of storing a Key Vault password
inside the pod, the pod authenticates as a managed identity that has permission on the
vault. This is more secure and eliminates credential rotation.

## How it works

The flow is called [workload identity](../concepts/workload-identity.md):

1. We create a managed identity `id-dagster-<env>` in Azure.
2. We give it the **Key Vault Secrets User** role on our [Key Vault](key-vault.md).
3. We create a **federated credential** linking it to the Kubernetes service account
   `dagster-<env>/dagster-user-deployments` (namespace/service-account).
4. When a Dagster pod starts, Kubernetes injects a token. The pod exchanges this token
   for an Azure access token via the managed identity. Azure trusts the exchange because
   of the federated credential.
5. The pod uses the Azure token to read secrets from Key Vault.

## Configuration

| Setting | Value |
|---------|-------|
| Name | `id-dagster-<env>` (one per environment) |
| Roles | Key Vault Secrets User on `kv-dagster-<random>` |
| Federated credential | Linked to K8s service account `dagster-<env>/dagster-user-deployments` via the AKS OIDC issuer |

## Cost

Free. Managed identities have no cost.

## Provisioned by

[Terraform](../tools/terraform.md) — `infra/env/` stack, `modules/identity`.

## Related docs

- [Workload identity](../concepts/workload-identity.md) — the full authentication flow
- [Key Vault](key-vault.md) — what the identity accesses
- [AKS](aks.md) — where the pods run
- [Entra app](entra-app.md) — a similar concept, but for GitHub Actions instead of pods

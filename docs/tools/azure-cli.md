# Azure CLI (`az`)

Microsoft's command-line tool for managing Azure resources. Used for authentication,
one-off queries, and operations that don't belong in Terraform (like building Docker
images in ACR).

## Why we use it

- **Authentication** — `az login` establishes your identity. Terraform, Helm, kubectl,
  and the Databricks CLI all piggyback on this session.
- **Image builds** — `az acr build` sends the Dagster Dockerfile to [ACR](../resources/acr.md)
  for cloud-based building (no local Docker needed).
- **Ad-hoc queries** — checking resource status, managing secrets in [Key Vault](../resources/key-vault.md).
- **AKS credentials** — `az aks get-credentials` downloads the kubeconfig so [kubectl](kubectl.md)
  can talk to the cluster.

## Key commands

```bash
# Authentication
az login                          # Browser-based login
az account show                   # Show current subscription and tenant
az account set --subscription ID  # Switch subscriptions

# Resource providers (Phase 0.6)
az provider register -n Microsoft.Databricks   # Enable a service on your subscription
az provider show -n Microsoft.Databricks       # Check registration status

# Docker images (Phase 2.5)
az acr build --registry NAME --image poc:latest dagster/   # Build in the cloud

# AKS (Phase 1.3)
az aks get-credentials --resource-group RG --name NAME     # Get kubeconfig

# Key Vault secrets
az keyvault secret set --vault-name NAME --name KEY --value VAL
az keyvault secret show --vault-name NAME --name KEY
```

## How it's installed

`scripts/setup-tools.sh` installs the version pinned in `.tool-versions`. On
Debian/Ubuntu it uses Microsoft's apt repo (needs `sudo`); on macOS it uses Homebrew;
elsewhere it installs via `uv tool`. Override with `AZ_INSTALL=apt|brew|pip`.

## Related docs

- [OIDC](../concepts/oidc.md) — how GitHub Actions authenticates via `az login` with
  federated credentials
- [Entra app](../resources/entra-app.md) — the app registration `az` authenticates against
  in CI
- [ACR](../resources/acr.md) — where `az acr build` pushes images

# Azure CLI (`az`)

> **Type:** Tool · **Scope:** local + CI · **Pinned:** 2.91.0 (`.tool-versions`)

Microsoft's command-line tool for Azure. It establishes your identity and covers the
operations that don't belong in Terraform (building images, stopping the cluster).

## Why we use it

- **Authentication.** `az login` creates the session that Terraform, kubectl (via
  kubelogin) and the Databricks CLI all reuse.
- **Image builds.** `az acr build` builds the Dagster image inside [ACR](../resources/acr.md),
  so no local Docker is needed.
- **Cluster credentials.** `az aks get-credentials` writes the kubeconfig for [kubectl](kubectl.md).
- **Cost control.** `az aks stop/start` and `az postgres flexible-server stop/start` back
  [stop/start](../concepts/stop-start.md).
- **Secrets.** Ad-hoc writes to [Key Vault](../resources/key-vault.md).

## How it's used here

- Locally you sign in interactively. In CI, `azure/login@v2` signs in through
  [OIDC](../concepts/oidc.md) using the IDs in GitHub repository variables.
- `scripts/setup-env.sh` reads `az account show` to detect tenant and subscription.
- CI installs it on ARC runners with Microsoft's install script.

## Key commands & files

```bash
az login                                   # browser sign-in
az account show                            # current subscription and tenant
az provider register -n Microsoft.Databricks
az acr build --registry NAME --image poc:TAG --file dagster/Dockerfile .
az aks get-credentials --resource-group rg-dagster-shared --name aks-dagster
az keyvault secret set --vault-name NAME --name KEY --value VAL
```

`scripts/setup-tools.sh` handles installation.

## Gotchas

- `az acr build` takes the repo root as build context (the Dockerfile copies `dagster/`,
  `dbt/` and `databricks/sources.yml`), so run it from the root.
- The KV firewall only admits your IP and the AKS egress IP. If `az keyvault secret set`
  is refused, your IP has changed. Re-run `scripts/setup-env.sh` and re-apply `shared`.
- **`AADSTS530035` / expired session:** new accounts with security defaults expire CLI tokens quickly. Run `az logout`, then
  `az login --tenant "$TF_VAR_tenant_id" --scope "https://management.azure.com/.default"`.
- Providers must be [registered](../resources/azure-resource-providers.md) before first use.
- Install method varies by platform: apt on Debian/Ubuntu, Homebrew on macOS, `uv tool`
  elsewhere. Override with `AZ_INSTALL=apt|brew|pip`.

## Cost

Free.

## Managed by

Installed by `scripts/setup-tools.sh` at the version in `.tool-versions`.

## Related docs

- [kubelogin](kubelogin.md), [kubectl](kubectl.md), [Databricks CLI](databricks-cli.md): all reuse the `az` session
- [OIDC](../concepts/oidc.md), [Entra app](../resources/entra-app.md): how CI signs in
- [ACR](../resources/acr.md): where `az acr build` pushes

# Azure Container Registry (ACR)

> **Type:** Resource · **Scope:** shared · **Name:** `acr<project><random>` · **Stack:** `infra/shared`

A private Docker image registry. [AKS](aks.md) pulls the Dagster image from here.

## Why we use it

The Dagster code, dbt project and dependencies are packaged as one [Docker](../tools/docker.md)
image. ACR stores it, and `az acr build` builds it in the cloud so no local Docker is needed.

## How it's used here

| Setting | Value | Why |
|---------|-------|-----|
| SKU | Basic | Cheapest; enough for one image. Premium is out of scope. |
| Admin user | Disabled | AKS pulls with its own identity; no shared password. |

- **Build:** `az acr build --registry <name> --image poc:<git-sha> --file dagster/Dockerfile .`
  in `deploy-stage.yml`.
- **Pull:** the AKS kubelet identity has the `AcrPull` role on the registry
  ([RBAC](../concepts/azure-rbac.md)).
- **Promotion:** prod deploys the same `poc:<git-sha>` that stage built. Nothing is rebuilt.

## Key commands & files

```bash
az acr repository show-tags --name "$ACR_NAME" --repository poc -o table
```

`ACR_NAME` and the login server (`ACR_LOGIN_SERVER`) are in `.env`.

## Gotchas

- The registry name is random-suffixed and globally unique. Never hardcode it; read it from `.env`.
- Old tags accumulate (Basic has 10 GB). Delete stale ones if storage fills.
- `imagePullPolicy: Always` in the Helm values means every pod start pulls the tag again.

## Cost

About $5/month, and it bills even when AKS is stopped or deleted.

## Managed by

[Terraform](../tools/terraform.md), `infra/shared/`.

## Related docs

- [Docker](../tools/docker.md), [AKS](aks.md)
- [CI/CD](../concepts/cicd.md): builds and tags
- [Costs](../costs.md)

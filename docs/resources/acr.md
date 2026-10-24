# Azure Container Registry (ACR)

A private Docker image registry. When you build a Docker image, it's stored here, and
[AKS](aks.md) pulls from it when starting pods.

## Why we need it

The Dagster application (your Python code, dbt project, and dependencies) is packaged as
a Docker image. ACR stores these images. Using `az acr build`, you can build images in the
cloud without Docker installed locally — ACR runs the Docker build on its servers.

## Configuration

| Setting | Value | Why |
|---------|-------|-----|
| SKU | Basic | Cheapest tier. 10 GB storage, sufficient for a POC |
| Admin user | Disabled | AKS uses its managed identity to pull images (more secure than a password) |
| Auth | Entra (Azure identity) | No stored credentials needed |

## How images get built and pulled

1. **Build:** `az acr build --registry <name> --image poc:<tag> dagster/` sends the
   `dagster/` directory to ACR, which runs `docker build` in the cloud and stores the result.
2. **Pull:** AKS has an `AcrPull` role assignment on the registry. When a pod starts and
   needs the image, kubelet pulls it automatically.

In CI, the image is tagged with the git SHA (`poc:<sha>`) so each deploy is traceable.

## Cost

~$5/month (Basic tier).

## Provisioned by

[Terraform](../tools/terraform.md) — `infra/shared/` stack.

## Related docs

- [AKS](aks.md) — pulls images from ACR
- [Azure CLI](../tools/azure-cli.md) — `az acr build` builds images
- [CI/CD](../concepts/cicd.md) — how CI builds and tags images
- [Costs](../costs.md) — full cost breakdown

# AKS (Azure Kubernetes Service)

A managed Kubernetes cluster. Azure runs the control plane (the API server, scheduler, etc.)
for free; you pay for the worker node VMs that actually run your containers.

## Why we need it

Dagster needs somewhere to run. AKS gives us a Kubernetes cluster where [Helm](../tools/helm.md)
deploys the Dagster webserver, daemon, code server, and run pods. We use a single cluster
with two namespaces (`dagster-stage`, `dagster-prod`) to keep costs low.

## Configuration

| Setting | Value | Why |
|---------|-------|-----|
| Control plane | Free tier | No SLA needed for a POC |
| Node pool | 1× Standard_B2ms (2 vCPU, 8 GB RAM) | Smallest node that fits Dagster's components |
| OS disk | 32 GB Premium SSD | Default 128 GB costs ~$20/month; 32 GB is ~$5 |
| Autoscaler | Disabled | Single node is enough; autoscaler adds complexity |
| Auth | Entra RBAC | Who can access the cluster is managed by Azure identity, not Kubernetes' own RBAC |
| Authorized IP ranges | Your IP only | Only your machine can reach the API server |
| OIDC issuer + workload identity | Enabled | Lets pods authenticate to Azure without stored credentials — see [workload identity](../concepts/workload-identity.md) |
| Secrets Store CSI addon | Enabled, with rotation | Lets pods mount [Key Vault](key-vault.md) secrets as files or env vars |
| ACR pull | Role assigned | The cluster can pull images from [ACR](acr.md) without extra credentials |

## Cost

| State | Est. $/month |
|-------|-------------|
| Running | ~60 (node VM) + ~5 (OS disk) + ~20 (load balancer + public IP) |
| Stopped (`just stop`) | ~25 (OS disk + LB + IP still bill) |
| Deleted | 0 (recreate with `just tf-apply shared`, ~10 min) |

The load balancer and public IP are the annoying floor cost — they bill even when the node
is stopped. The only way to eliminate them is `az aks delete` and recreate from Terraform.

## Provisioned by

[Terraform](../tools/terraform.md) — `infra/shared/` stack, `modules/aks`.

## Related docs

- [Helm](../tools/helm.md) — deploys Dagster into the cluster
- [kubectl](../tools/kubectl.md) — inspects what's running
- [Workload identity](../concepts/workload-identity.md) — how pods authenticate to Azure
- [Key Vault](key-vault.md) — secrets mounted via the CSI driver
- [Stop/start](../concepts/stop-start.md) — stopping the node pool to save money
- [Costs](../costs.md) — full cost breakdown

# AKS (Azure Kubernetes Service)

> **Type:** Resource · **Scope:** shared (one cluster) · **Name:** `aks-<project>` · **Stack:** `infra/shared`

A managed Kubernetes cluster. Azure runs the control plane; you pay for the node VMs.

## Why we use it

Dagster OSS needs somewhere to run. One cluster hosts both environments as separate
namespaces (`dagster-stage`, `dagster-prod`) and the [ARC](../tools/arc.md) runners.
A second cluster is out of scope ([decision 2](../decisions.md)).

## How it's used here

| Setting | Value | Why |
|---------|-------|-----|
| Control plane | Free tier | No SLA needed |
| Node pool | 1 node, `Standard_D2as_v6` (variable `aks_vm_size`), 32 GB OS disk | B-series VMs are unavailable in this region; 32 GB keeps disk cost down |
| Networking | Azure CNI in `snet-aks`; service CIDR `172.16.0.0/16` | See [VNet](vnet.md) |
| Auth | Entra ID with **Azure RBAC** for Kubernetes | Roles come from Azure, not Kubernetes RBAC |
| API server access | Authorized IP ranges = your IP | See [network access](../concepts/network-access.md) |
| OIDC issuer + workload identity | On | [Workload identity](../concepts/workload-identity.md) |
| Key Vault secrets provider | On, with rotation | [CSI driver](../tools/secrets-store-csi-driver.md) |

The kubelet identity has `AcrPull` on [ACR](acr.md). The Terraform applier and the CI
principal have *AKS RBAC Cluster Admin*. Egress goes through an AKS-managed public IP
that is allow-listed on Key Vault, Postgres and Databricks.

## Key commands & files

```bash
az aks get-credentials --resource-group rg-dagster-shared --name aks-dagster
kubelogin convert-kubeconfig -l azurecli
kubectl get nodes
just stop / just start / just teardown / just standup
```

## Gotchas

- The load balancer and public IP bill even while the node is stopped. Only deleting the
  cluster removes them.
- The egress IP can change after a teardown/standup. Re-apply `shared` and `env` so the firewall
  rules follow it, and run `collect-tf shared`.
- The node is small. Dagster, ARC and runner pods share it, so keep memory requests low
  (see the 512Mi values in Helm).
- Deleting the cluster removes ARC. Re-run `scripts/setup-arc.sh`.

## Cost

See [costs](../costs.md) (its node estimate is from the earlier B2ms size; re-measure for D2as_v6). Rough shape: the node VM dominates
while running; the OS disk, load balancer and public IP (about $25) remain when stopped.

## Managed by

[Terraform](../tools/terraform.md), `infra/shared/` (the `modules/aks` directory is only a README so far).

## Related docs

- [Helm](../tools/helm.md), [kubectl](../tools/kubectl.md), [kubelogin](../tools/kubelogin.md), [ARC](../tools/arc.md)
- [Stop/start](../concepts/stop-start.md), [Workload identity](../concepts/workload-identity.md), [Azure RBAC](../concepts/azure-rbac.md)
- [Key Vault](key-vault.md), [Postgres](postgres.md)

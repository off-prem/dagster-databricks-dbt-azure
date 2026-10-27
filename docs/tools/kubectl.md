# kubectl

> **Type:** Tool · **Scope:** local + CI · **Pinned:** 1.36.5 (`.tool-versions`)

The Kubernetes command-line client. It talks to the [AKS](../resources/aks.md) API server.

## Why we use it

After [Helm](helm.md) deploys Dagster, kubectl is how you check pods, read logs and reach
the UI through a port-forward (there is no public ingress).

## How it's used here

- `az aks get-credentials` writes the kubeconfig, and [kubelogin](kubelogin.md) converts it
  to reuse your `az` session. The cluster uses Azure RBAC, so your Azure role decides what you can do.
- Namespaces: `dagster-stage`, `dagster-prod`, plus `arc-systems` and `arc-runners`.
- `scripts/port-forward.sh <env>` forwards the webserver service to `localhost:3000`.

## Key commands & files

```bash
az aks get-credentials --resource-group rg-dagster-shared --name aks-dagster
kubelogin convert-kubeconfig -l azurecli
kubectl get nodes
kubectl get pods -n dagster-stage
kubectl logs -n dagster-stage <pod>
kubectl describe pod -n dagster-stage <pod>
just port-forward stage
```

## Gotchas

- The pin must stay within one minor version of the AKS Kubernetes version.
- The API server only accepts your IP (authorized ranges). If you get a timeout after moving
  networks, update `TF_VAR_my_ip_cidr` and re-apply `shared`. See [network access](../concepts/network-access.md).
- A stopped cluster refuses connections. Run `just start` first.

## Cost

Free.

## Managed by

Installed by `scripts/setup-tools.sh`.

## Related docs

- [AKS](../resources/aks.md), [kubelogin](kubelogin.md), [Helm](helm.md)
- [Stop/start](../concepts/stop-start.md)

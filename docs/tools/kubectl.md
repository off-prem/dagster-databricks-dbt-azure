# kubectl

The Kubernetes command-line tool. Talks to your [AKS](../resources/aks.md) cluster to
check on pods, view logs, and manage resources.

## Why we use it

After [Helm](helm.md) deploys Dagster, kubectl is how you inspect what's running, debug
issues, and access the Dagster UI via port-forwarding.

## Key commands

```bash
# Get credentials (run once after AKS is created)
az aks get-credentials --resource-group rg-dagster-shared --name aks-dagster

# Check node health
kubectl get nodes                             # Should show one node, status "Ready"

# Check Dagster pods
kubectl get pods -n dagster-stage             # List pods in the stage namespace
kubectl logs -n dagster-stage <pod-name>      # View logs for a specific pod

# Port-forward the Dagster UI (or use `just port-forward stage`)
kubectl port-forward -n dagster-stage svc/dagster-stage-webserver 3000:80

# Debug a failing pod
kubectl describe pod -n dagster-stage <pod-name>   # Events, status, restart reasons
```

## How it authenticates

`az aks get-credentials` writes a kubeconfig file (`~/.kube/config`) that kubectl reads.
The cluster uses Entra RBAC, so your Azure identity determines what you can do. Locally
this is your `az login` session; in CI it's the [OIDC](../concepts/oidc.md) identity.

## How it's installed

`scripts/setup-tools.sh` installs the version pinned in `.tool-versions`. The version
must stay within one minor of the AKS server version.

## Related docs

- [AKS](../resources/aks.md) — the cluster kubectl talks to
- [Helm](helm.md) — deploys the resources kubectl inspects
- [Stop/start](../concepts/stop-start.md) — uses `az` to stop/start the cluster, then
  kubectl to verify

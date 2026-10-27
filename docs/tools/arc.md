# Actions Runner Controller (ARC)

> **Type:** Tool · **Scope:** shared (one install on the cluster) · **Pinned:** 0.10.1 (`scripts/setup-arc.sh`)

A Kubernetes operator that runs **self-hosted GitHub Actions runners** as ephemeral pods.

## Why we use it

GitHub-hosted runners have changing IPs, which the AKS authorized IP ranges and the
Databricks IP access list block. Runner pods inside AKS reach the API server directly and
egress through the AKS IP that is already allow-listed. One runner can deploy to both AKS
(Helm) and Databricks (bundle). See [decision 16](../decisions.md).

## How it's used here

`scripts/setup-arc.sh` installs two Helm charts from `ghcr.io/actions`:

- **Controller** (`gha-runner-scale-set-controller`) in namespace `arc-systems`.
- **Runner scale set** named `arc-runner-set` in namespace `arc-runners`, with `minRunners=0` and `maxRunners=3`.
  Workflows target it with `runs-on: arc-runner-set`.

ARC authenticates to GitHub with a [GitHub App](../resources/github-app.md). Its private key lives in
[Key Vault](../resources/key-vault.md) (`arc-github-app-key`) and is copied into a Kubernetes
secret by the script. App ID and installation ID come from `.env`.

## Key commands & files

```bash
just setup-arc              # install or re-install (idempotent)
scripts/setup-arc.sh teardown
kubectl get pods -n arc-systems
kubectl get pods -n arc-runners
```

## Gotchas

- Re-run `setup-arc.sh` after `just standup` because deleting AKS removes ARC with it.
- The controller and listener always run (about 200m CPU / 256Mi). Runner pods exist only
  during a job (about 500m CPU / 1Gi), so the node must have headroom.
- `pr-checks.yml` stays on hosted runners and doesn't need ARC.
- Do not commit the GitHub App key. It stays in Key Vault.

## Cost

$0 extra. Runs on the existing node and scales runners to zero.

## Managed by

`scripts/setup-arc.sh` (Helm); not Terraform.

## Related docs

- [GitHub Actions](github-actions.md), [CI/CD](../concepts/cicd.md)
- [GitHub App](../resources/github-app.md), [Helm releases](../resources/helm-releases.md), [Kubernetes namespaces](../resources/kubernetes-namespaces.md)
- [Network access](../concepts/network-access.md): why hosted runners don't work
- [Helm](helm.md), [AKS](../resources/aks.md)

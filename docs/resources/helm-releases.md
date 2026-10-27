# Helm Releases

> **Type:** Resource · **Scope:** in the AKS cluster · **Names:** `<project>-stage`, `<project>-prod`, `arc`, `arc-runner-set`

The installed instances of Helm charts. Each release is one deployed copy of a chart with its own values.

## Why we use it

Releases are the unit you upgrade and roll back. Dagster is one release per environment, and ARC is two releases.

## How it's used here

| Release | Chart | Namespace | Installed by |
|---------|-------|-----------|--------------|
| `<project>-stage` | `dagster/dagster` 1.13.26 (repo `https://dagster-io.github.io/helm`) | `<project>-stage` | `scripts/helm-upgrade.sh stage` |
| `<project>-prod` | same | `<project>-prod` | `scripts/helm-upgrade.sh prod` |
| `arc` | `gha-runner-scale-set-controller` 0.10.1 (OCI, `ghcr.io/actions`) | `arc-systems` | `scripts/setup-arc.sh` |
| `arc-runner-set` | `gha-runner-scale-set` 0.10.1 | `arc-runners` | `scripts/setup-arc.sh` (`minRunners=0`, `maxRunners=3`) |

Dagster releases use `--install --wait --timeout 3m0s`, values from `deploy/helm/`, and the image tag set by CI. Terraform never manages Helm releases ([decision 8](../decisions.md)).

## Key commands & files

```bash
helm list -A
helm status <project>-stage -n <project>-stage
helm history <project>-prod -n <project>-prod
helm rollback <project>-prod
```

## Gotchas

- Run `helm repo add dagster https://dagster-io.github.io/helm` once, or the chart can't be found (CI does this in the workflow).
- The release name is also the service-account name. Changing it breaks workload identity.
- Rolling back a release does not roll back the Databricks bundle or the database schema.
- Prod upgrades need explicit go-ahead.
- Release history is stored as Kubernetes secrets, so they are lost if the cluster is deleted.

## Cost

Free.

## Managed by

[Helm](../tools/helm.md) via the scripts above and the deploy workflows.

## Related docs

- [Helm deployments](../concepts/helm-deployments.md), [ARC](../tools/arc.md), [Kubernetes namespaces](kubernetes-namespaces.md)
- [CI/CD](../concepts/cicd.md), [Managed identity](managed-identity.md)

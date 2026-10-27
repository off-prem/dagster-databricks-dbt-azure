# Helm

> **Type:** Tool · **Scope:** per-env · **Pinned:** 3.22.1 (`.tool-versions`); Dagster chart 1.13.26

The package manager for Kubernetes. A **chart** bundles the YAML templates for an app, and
**values files** fill in the settings.

## Why we use it

Dagster needs many coordinated Kubernetes objects. The official chart provides them, and we
override only what differs from the defaults.

## How it's used here

`scripts/helm-upgrade.sh <env>` runs `helm upgrade --install dagster-<env> dagster/dagster
--version 1.13.26 -n dagster-<env> --create-namespace --wait --timeout 3m0s` with two values files:

| File | Purpose |
|------|---------|
| `deploy/helm/values.base.yaml` | Shared: external Postgres, ClusterIP webserver, `K8sRunLauncher`, 512Mi resource limits |
| `deploy/helm/values.<env>.yaml` | Per-env: database name, service account, run-pod and code-server env vars, secrets, CSI volume |

Per-user values appear as `${VAR}` placeholders in the per-env file. The script fills them
from `.env` with `envsubst`, so committed files stay free of personal values. CI passes
`--set dagster-user-deployments.deployments[0].image.tag=<sha>`.

Helm also installs the [ARC](arc.md) charts through `scripts/setup-arc.sh`.

## Key commands & files

```bash
just helm-upgrade stage
helm list -n dagster-stage
helm rollback dagster-prod
```

Files: `scripts/helm-upgrade.sh`, `deploy/helm/`, `deploy/k8s/<env>/secretproviderclass.yaml`.

## Gotchas

- Helm replaces arrays instead of merging them, so each per-env file carries the full
  `deployments` list.
- `--wait` makes the command return only when the rollout finishes. A failed pod therefore
  fails the deploy, and that is what CI relies on.
- Helm never creates the `SecretProviderClass`. Apply `deploy/k8s/<env>/` separately (see its README).
- Never set the webserver service to `LoadBalancer` or add an Ingress.

## Cost

Free.

## Managed by

Installed by `scripts/setup-tools.sh`; CI uses `azure/setup-helm@v4` at the same version.

## Related docs

- [Helm deployments](../concepts/helm-deployments.md): the deploy flow in detail
- [Secrets Store CSI driver](secrets-store-csi-driver.md), [Secrets flow](../concepts/secrets-flow.md)
- [Dagster](dagster.md), [AKS](../resources/aks.md)
- [Environment parametrization](../concepts/environment-parametrization.md)

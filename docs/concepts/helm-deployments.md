# Helm Deployments

> **Type:** Concept · **Scope:** per-env · **Where:** `scripts/helm-upgrade.sh`, `deploy/helm/`

How Dagster gets onto [AKS](../resources/aks.md) and what `just helm-upgrade <env>` does.

## Why we use it

One chart, one script and layered values give identical deployments in stage and prod, while
personal values stay out of the repo.

## How it's used here

```
just helm-upgrade stage
  -> scripts/helm-upgrade.sh stage
     -> source .env
     -> envsubst resolves ${VAR} in values.stage.yaml -> temp file
     -> helm upgrade --install dagster-stage dagster/dagster --version 1.13.26
          -n dagster-stage --create-namespace --wait --timeout 3m0s
          -f values.base.yaml -f <resolved temp file>  [extra flags]
```

**Values layering** (later wins): chart defaults, then `values.base.yaml` (external Postgres,
ClusterIP, run launcher, limits), then `values.<env>.yaml` (database, service account, env vars,
secrets, CSI volume). Helm replaces lists whole, so the complete `deployments` list lives in each
per-env file.

**What gets deployed** per release:

| Component | Pods | Purpose |
|-----------|------|---------|
| Webserver | 1 | UI; ClusterIP only |
| Daemon | 1 | Schedules, sensors, run queue |
| Code server | 1 | Loads `poc.definitions` from the image |
| Run pods | 0–N | One per run (`K8sRunLauncher`), removed afterwards |

**Run pods** inherit only the image. Under `runLauncher.config.k8sRunLauncher` each env file repeats
the env vars, `envSecrets`, the `azure.workload.identity/use` label, and the CSI volume and mount.

**Updating code:** build and push a new image tag, then re-run Helm with
`--set dagster-user-deployments.deployments[0].image.tag=<sha>` (CI does this).

## Key commands & files

```bash
just helm-upgrade stage
helm status dagster-stage -n dagster-stage
kubectl rollout status deploy -n dagster-stage
```

## Gotchas

- Missing run-pod config is the usual cause of "credentials not found" in runs, even when the code server has them.
- `--wait` fails the deploy if pods don't become ready in 3 minutes. Check `kubectl describe pod`.
- Apply the `SecretProviderClass` before the first Helm install, or pods hang in `ContainerCreating`.
- Prod upgrades need explicit go-ahead.

## Cost

Free; pods use existing node capacity.

## Managed by

`scripts/helm-upgrade.sh`, run locally or by the deploy workflows.

## Related docs

- [Helm](../tools/helm.md), [Dagster](../tools/dagster.md)
- [Secrets flow](secrets-flow.md), [Workload identity](workload-identity.md)
- [Environment parametrization](environment-parametrization.md), [CI/CD](cicd.md)

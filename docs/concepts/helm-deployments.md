# Helm Deployments

How Dagster gets deployed to [AKS](../resources/aks.md) and what happens when you run
`just helm-upgrade <env>`.

## The deploy flow

```
just helm-upgrade stage
  → scripts/helm-upgrade.sh stage
    → reads .env for per-user values (Postgres host, Databricks host, image repo, etc.)
    → helm upgrade --install dagster-stage dagster/dagster \
        -n dagster-stage \
        -f deploy/helm/values.base.yaml \
        -f deploy/helm/values.stage.yaml \
        --set <per-user overrides from .env> \
        --wait
```

### What the flags mean

| Flag | Purpose |
|------|---------|
| `--install` | Create the release if it doesn't exist; update if it does |
| `-n dagster-stage` | Target Kubernetes namespace |
| `-f values.base.yaml` | Shared settings (resource limits, Postgres config, etc.) |
| `-f values.stage.yaml` | Environment-specific settings (catalog, DB name, secret names) |
| `--set` | Per-user values from `.env` that aren't in the committed YAML |
| `--wait` | Block until all pods are running |

### Values layering

[Helm](../tools/helm.md) merges values files in order (later files override earlier ones):

1. **Chart defaults** — from the Dagster Helm chart
2. **`values.base.yaml`** — our shared overrides (external Postgres, resource limits,
   K8sRunLauncher, service account, etc.)
3. **`values.<env>.yaml`** — environment-specific (env name, catalog, DB name). Per-user
   fields are left blank.
4. **`--set` flags** — per-user values from `.env` (Postgres host, Databricks host, image
   repository/tag)

This means committed files never contain per-user values. The `--set` flags inject them at
deploy time from `.env`.

## What gets deployed

Each Helm release (`dagster-stage`, `dagster-prod`) creates these in its namespace:

| Component | Pods | Purpose |
|-----------|------|---------|
| Webserver | 1 | Dagster UI. ClusterIP only — access via `just port-forward <env>` |
| Daemon | 1 | Runs schedules, sensors, run coordinator |
| Code server | 1 | Loads asset definitions from the Docker image |
| Run pods | 0–N | Spun up per-run by the K8sRunLauncher; cleaned up after |

### Secrets injection

Pods get credentials from [Key Vault](../resources/key-vault.md) via a `SecretProviderClass`
(defined in `deploy/k8s/<env>/secretproviderclass.yaml`). The Secrets Store CSI driver
mounts secrets as environment variables. The pod never talks to Key Vault directly — the
CSI driver does it using [workload identity](workload-identity.md).

## Updating Dagster

To deploy new code:

1. Build a new image: `az acr build --registry <acr> --image poc:<tag> dagster/`
2. Re-run Helm with the new tag: `just helm-upgrade <env>` (or pass `--set ...image.tag=<tag>`)
3. Helm performs a rolling update — new pods start, old pods drain

In [CI/CD](cicd.md), the tag is the git SHA, ensuring traceability.

## Related docs

- [Helm](../tools/helm.md) — the tool and chart configuration
- [AKS](../resources/aks.md) — the cluster Helm deploys into
- [Key Vault](../resources/key-vault.md) — secrets mounted by the CSI driver
- [Workload identity](workload-identity.md) — how pods authenticate to Key Vault
- [CI/CD](cicd.md) — automated deploys
- [Conventions](../conventions.md) — values file structure and resource limits

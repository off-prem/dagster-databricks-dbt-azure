# Helm

A package manager for Kubernetes. The Dagster project publishes a Helm **chart** — a bundle
of YAML templates that define all the Kubernetes resources Dagster needs (pods, services,
config maps, etc.). You customize the chart with **values files** that fill in the
template variables.

## Why we use it

Deploying Dagster on Kubernetes requires dozens of coordinated YAML manifests. Writing them
by hand would be error-prone and hard to maintain. Helm lets us use the officially maintained
chart and override only the settings that differ from defaults.

## Key commands

```bash
just helm-upgrade <env>   # Deploy or update Dagster (env: stage or prod)
```

Under the hood this runs `scripts/helm-upgrade.sh`, which calls `helm upgrade --install`
with the right values files and `--set` flags populated from your `.env`.

## How it's configured in this project

The Helm configuration lives in `deploy/helm/`:

| File | Purpose |
|------|---------|
| `values.base.yaml` | Settings shared by all environments: external Postgres (not the chart's built-in one), resource limits, run launcher type, service account config |
| `values.stage.yaml` | Stage-specific: environment name, catalog name, database name, secret names. Per-user values (Postgres host, Databricks host, image repo) are left blank and filled by `--set` flags from `.env` |
| `values.prod.yaml` | Same shape as stage, with `prod` names |

The chart deploys these components into the `dagster-<env>` namespace:

| Component | What it does |
|-----------|-------------|
| **Webserver** | The Dagster UI (port 3000). Not exposed to the internet — access via [port-forward](../concepts/stop-start.md). |
| **Daemon** | Runs schedules, sensors, and the run coordinator |
| **Code server** (user deployments) | Loads your asset definitions from the Docker image |
| **Run pods** | Spun up per-run by the K8sRunLauncher, then cleaned up |

### Secrets

Dagster pods need credentials (Postgres password, Databricks SP secret, etc.). These
come from [Key Vault](../resources/key-vault.md) via the Secrets Store CSI driver, not
from Kubernetes Secrets or Helm values. The `SecretProviderClass` YAML in `deploy/k8s/`
defines which Key Vault secrets to mount.

## Related docs

- [AKS](../resources/aks.md) — the cluster Helm deploys into
- [Key Vault](../resources/key-vault.md) — where secrets live
- [Helm deployments](../concepts/helm-deployments.md) — how the deploy flow works
- [Conventions](../conventions.md) — Helm values structure and resource limits

# Helm Deployments

How Dagster gets deployed to [AKS](../resources/aks.md) and what happens when you run
`just helm-upgrade <env>`.

## The deploy flow

```
just helm-upgrade stage
  → scripts/helm-upgrade.sh stage
    → reads .env for per-user values (Postgres host, Databricks host, image repo, etc.)
    → envsubst resolves ${VAR} placeholders in values.stage.yaml → temp file
    → helm upgrade --install dagster-stage dagster/dagster \
        -n dagster-stage \
        -f deploy/helm/values.base.yaml \
        -f <resolved temp file>
```

### What the flags mean

| Flag | Purpose |
|------|---------|
| `--install` | Create the release if it doesn't exist; update if it does |
| `-n dagster-stage` | Target Kubernetes namespace |
| `-f values.base.yaml` | Shared settings (resource limits, Postgres config, etc.) |
| `-f <resolved>` | Per-env file after envsubst replaces `${VAR}` with `.env` values |

### Values layering

[Helm](../tools/helm.md) merges values files in order (later files override earlier ones):

1. **Chart defaults** — from the Dagster Helm chart
2. **`values.base.yaml`** — our shared overrides (external Postgres, resource limits,
   K8sRunLauncher, service account, etc.). Does **not** include the `deployments` array.
3. **`values.<env>.yaml`** (after envsubst) — the **complete** deployment spec plus
   environment-specific settings (catalog, DB name, secret names), with per-user values
   resolved from `.env`.

Helm replaces arrays wholesale rather than merging elements, so the full deployment
definition (image, port, volumes, env, etc.) lives in each per-env file. `envsubst`
resolves `${VAR}` placeholders at deploy time so committed files never contain per-user
values.

## What gets deployed

Each Helm release (`dagster-stage`, `dagster-prod`) creates these in its namespace:

| Component | Pods | Purpose |
|-----------|------|---------|
| Webserver | 1 | Dagster UI. ClusterIP only — access via `just port-forward <env>` |
| Daemon | 1 | Runs schedules, sensors, run coordinator |
| Code server | 1 | Loads asset definitions from the Docker image |
| Run pods | 0–N | Spun up per-run by the K8sRunLauncher; cleaned up after |

### Run pod configuration

Run pods do **not** inherit env vars, volumes, labels, or secrets from the user
code deployment. They only inherit the image. Everything else must be configured
separately under `runLauncher.config.k8sRunLauncher` in the per-env values file:

- `envVars` — environment variables (Databricks host, catalog, etc.)
- `envSecrets` — K8s Secrets to load (e.g. `dagster-dbx-stage`)
- `labels` — must include `azure.workload.identity/use: "true"` for Key Vault access
- `volumes` / `volumeMounts` — CSI secrets-store volume for Key Vault

If a run pod is missing credentials, check this config first — the user deployment
having them does not mean the run pod does.

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

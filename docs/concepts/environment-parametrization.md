# Environment Parametrization

> **Type:** Concept · **Scope:** repo-wide · **Where:** `.env`, `*.tfvars`, `deploy/helm/`, `scripts/`

The rule that nothing environment- or person-specific is hardcoded. Code never knows whether it runs in stage or prod.

## Why we use it

The repo is a blueprint others clone, and the same artifacts are promoted from stage to prod.
Both require that differences come from configuration, not from code.

## How it's used here

Per-user and per-account values live in the git-ignored `.env`, created by `scripts/setup-env.sh`
(`.env.example` lists every key). Each tool reads it differently:

| Tool | How values arrive |
|------|-------------------|
| Terraform | `TF_VAR_*` (and `ARM_*`); committed `*.tfvars` hold only `env = "stage"` or `"prod"` |
| Helm | `scripts/helm-upgrade.sh` runs `envsubst` on `${VAR}` placeholders in `values.<env>.yaml` |
| dbt | `env_var()` in `profiles.yml` |
| Databricks bundle | `DATABRICKS_HOST` set by `scripts/bundle-deploy.sh`; `catalog` is a bundle variable per target |
| Dagster | Env vars from Helm (`DBX_CATALOG`, `DATABRICKS_HOST`, `DBX_BUNDLE_ROOT`, `DBX_WAREHOUSE_HTTP_PATH`) |
| CI | GitHub repository variables, synced from `.env` by `scripts/setup-ci.sh` |

After each `terraform apply`, run `scripts/setup-env.sh collect-tf <stack>` to capture outputs.
Naming follows `<thing>-<project>-<env>`, so `project` and `env` are enough to derive most names.

## Key commands & files

```bash
source scripts/load-env.sh            # use when `just` isn't available
just show-env
scripts/setup-env.sh collect-tf shared
scripts/setup-env.sh collect-bundle stage
```

## Gotchas

- Never commit tenant/subscription IDs, IPs, personal handles or org names. Use a `.env` key.
- A blank `.env` value gives a "blank in .env" warning from Helm. Fix it before deploying.
- Adding a new per-user value means updating `.env.example`, `setup-env.sh`, and (for CI) `setup-ci.sh`.
- [Architecture](../architecture.md) has the per-value table of where each setting is set and read.

## Cost

Free.

## Managed by

`scripts/setup-env.sh`, `scripts/load-env.sh`, and the [justfile](../tools/just.md).

## Related docs

- [just](../tools/just.md), [Terraform](../tools/terraform.md), [Helm](../tools/helm.md), [dbt](../tools/dbt.md)
- [GitHub environments](../resources/github-environments.md), [Conventions](../conventions.md)

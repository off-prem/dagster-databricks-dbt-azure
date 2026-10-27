# GitHub Actions

> **Type:** Tool · **Scope:** CI · **Where:** `.github/workflows/`

GitHub's built-in automation. Workflows are YAML files that run jobs on **runners** when
events such as a pull request or a push occur.

## Why we use it

It is free, signs in to Azure with [OIDC](../concepts/oidc.md) (no stored secrets), and has
**environments** that can require approval. See [decision 9](../decisions.md).

## How it's used here

| Workflow | Trigger | Runner | What it does |
|----------|---------|--------|--------------|
| `pr-checks.yml` | pull request to `main` | `ubuntu-latest` (hosted) | `terraform fmt`/`validate`, bundle validate, `dbt parse`, Dagster definitions load, `docker build` |
| `deploy-stage.yml` | push to `main` | `arc-runner-set` (self-hosted) | build and push image, Helm upgrade, bundle deploy, smoke test on stage |
| `promote-prod.yml` | `deploy-stage` succeeds, or manual `workflow_dispatch` with a SHA | `arc-runner-set` | same image SHA to prod, bundle deploy, smoke test |

- Deploys use [ARC runners](arc.md) inside AKS because hosted runners have dynamic IPs that
  the AKS authorized ranges and Databricks IP access list would block.
- Non-secret IDs (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `ACR_NAME`, hosts, ...) are
  repository **variables**, synced by `scripts/setup-ci.sh`.
- The `stage` and `prod` [GitHub environments](../resources/github-environments.md) match the
  federated credentials, and `prod` requires a reviewer.
- Deploy workflows use `concurrency` groups with `cancel-in-progress: false`.

## Key commands & files

```bash
just setup-ci                          # sync .env -> repo variables, create environments
gh workflow run promote-prod.yml -f sha=<sha>    # manual promote / rollback
```

## Gotchas

- Workflows need `permissions: id-token: write` or `azure/login` can't get a token.
- Pull-request runs from forks can't use the federated credentials.
- Each deploy step installs its own tools (Azure CLI, kubelogin, Databricks CLI) because
  the runner image is bare. Keep the versions aligned with `.tool-versions`.

## Cost

Free tier for hosted runners. Self-hosted ARC runners have no per-minute charge.

## Managed by

Workflow files are in the repo; repository variables and environments by `scripts/setup-ci.sh`.

## Related docs

- [CI/CD](../concepts/cicd.md): the full flow and rollback
- [OIDC](../concepts/oidc.md), [Entra app](../resources/entra-app.md)
- [ARC](arc.md), [GitHub environments](../resources/github-environments.md)

# CI/CD

> **Type:** Concept · **Scope:** repo-wide · **Where:** `.github/workflows/`

Automated workflows that validate every change, deploy `main` to stage, and promote the
same build to prod after approval.

## Why we use it

Deploys must be repeatable and identical across environments. The rule is **promote, don't
rebuild**: the image built once on `main` is the artifact that reaches stage and then prod.

## How it's used here

```
PR opened         -> pr-checks   (validate everything, build image, deploy nothing)
merge to main     -> deploy-stage (build+push image -> helm stage -> bundle stage -> smoke test)
deploy-stage OK   -> promote-prod (approval -> same SHA -> helm prod -> bundle prod -> smoke test)
```

**Authentication.** Workflows sign in to Azure with [OIDC](oidc.md) via `azure/login@v2`, using IDs
from repository variables. The Databricks CLI reuses that session.

**Runners.** `pr-checks` uses GitHub-hosted runners. Deploys use [ARC](../tools/arc.md) runners
inside AKS (`runs-on: arc-runner-set`), so they can reach the IP-restricted API server and the
Databricks workspace without temporary IP changes.

| Workflow | Steps |
|----------|-------|
| `pr-checks.yml` | `terraform fmt -check`; `init -backend=false` + `validate` for `shared` and `env`; `bundle validate` (non-blocking); `dbt deps` + `dbt parse` with placeholder env; Dagster definitions load; `docker build` |
| `deploy-stage.yml` | `az acr build` (tag = git SHA); kubelogin + AKS credentials; `scripts/helm-upgrade.sh stage` (`--wait`); `scripts/bundle-deploy.sh stage`; `scripts/smoke-test.sh stage` |
| `promote-prod.yml` | Triggered by `deploy-stage` success or manual dispatch with a SHA; `environment: prod` needs approval; same steps against prod with the **same SHA** and no rebuild |

Both deploy workflows use `concurrency: deploy-<env>` with `cancel-in-progress: false`.

## Key commands & files

```bash
gh workflow run promote-prod.yml -f sha=<sha>    # promote or roll back to a SHA
helm rollback dagster-prod
scripts/smoke-test.sh stage
```

## Gotchas

- `pr-checks` does **not** run `terraform plan` or `pytest`; it validates only. Plan locally before applying.
- Infrastructure is never applied by CI. Terraform runs from a person's machine.
- Rollback options: `helm rollback`, redeploy the bundle from an older SHA, or re-run
  `promote-prod` with a previous SHA.
- The smoke test launches a real run (20-minute timeout), so it uses warehouse time.

## Cost

Free: hosted-runner free tier for PRs, no per-minute charge for ARC. Smoke tests cost one pipeline run (about $0.50–1).

## Managed by

Workflow files in the repo; variables and environments by `scripts/setup-ci.sh`.

## Related docs

- [GitHub Actions](../tools/github-actions.md), [ARC](../tools/arc.md), [OIDC](oidc.md)
- [Entra app](../resources/entra-app.md), [GitHub environments](../resources/github-environments.md)
- [Helm deployments](helm-deployments.md), [ACR](../resources/acr.md)
- [Network access](network-access.md)

# CI/CD

Continuous Integration and Continuous Deployment — automated workflows that validate,
build, and deploy your code when you push changes. In this project, GitHub Actions handles
everything: checking PRs, deploying to stage on merge, and promoting to prod with approval.

## The flow

```
PR opened → pr-checks (validate everything, build image, no deploy)
PR merged to main → deploy-stage (build+push image → helm stage → bundle stage → smoke test)
deploy-stage succeeds → promote-prod (your approval → same image → helm prod → bundle prod → smoke test)
```

The key principle: **promote, don't rebuild.** The image built once on `main` is the exact
artifact that goes to stage, then to prod. No second build, no "it worked in stage but this
is a different binary in prod."

## Authentication

Workflows authenticate to Azure via [OIDC](oidc.md) — no stored secrets. The
[Entra app](../resources/entra-app.md) `app-dagster-github` has federated credentials
for `main`, `environment:stage`, and `environment:prod`. The workflow calls `azure/login@v2`
with `client-id`, `tenant-id`, `subscription-id` from GitHub repository **variables** (not
secrets — these are non-sensitive IDs).

The [Databricks CLI](../tools/databricks-cli.md) authenticates using the same Azure session
(`DATABRICKS_HOST` + `azure-cli` auth type after `az login`).

## Workflows

### `pr-checks.yml` (every pull request)

Validates everything without deploying:

| Check | What it catches |
|-------|----------------|
| `terraform fmt -check` + `terraform validate` | Malformed Terraform |
| `terraform plan -var-file=stage.tfvars` | Infra changes preview |
| `databricks bundle validate -t stage` | Bundle config errors |
| `dbt deps && dbt parse` | dbt syntax errors (no warehouse connection needed) |
| `uv run dg check defs && uv run pytest` | Dagster definition errors, test failures |
| `docker build dagster/` (no push) | Dockerfile errors |

### `deploy-stage.yml` (push to `main`)

Triggered when a PR is merged:

1. `az acr build` — builds and pushes the Docker image tagged with the git SHA
2. `az aks get-credentials` — gets [AKS](../resources/aks.md) access
3. `helm upgrade --install` — deploys Dagster to stage with the new image tag
4. `databricks bundle deploy -t stage` — deploys/updates the SDP pipeline
5. `scripts/smoke-test.sh stage` — launches both assets via GraphQL, polls to success
   (20-minute timeout)

### `promote-prod.yml` (after deploy-stage succeeds)

Triggered by `deploy-stage` success, with `environment: prod` (requires your approval):

1. Resolves the `<sha>` from the triggering run
2. `helm upgrade --install` — deploys to prod with the **same image SHA** (no rebuild)
3. `databricks bundle deploy -t prod` — at the same git SHA
4. `scripts/smoke-test.sh prod` — verifies prod is working

### Concurrency

Both deploy workflows use `concurrency: { group: deploy-<env>, cancel-in-progress: false }`
so only one deploy runs at a time per environment.

## Rollback

- **Helm:** `helm rollback dagster-prod` reverts to the previous release.
- **Bundle:** `databricks bundle deploy -t prod` from the previous SHA.
- **Full:** Re-run `promote-prod.yml` with a previous SHA via `workflow_dispatch`.

## Network caveat

The workflows assume GitHub-hosted runners can reach [AKS](../resources/aks.md),
[ACR](../resources/acr.md), and the [Databricks workspaces](../resources/databricks-workspace.md).
If IP access lists exclude GitHub's IP ranges, you'll need self-hosted runners. See
[corporate migration](../corporate-migration.md) for that path.

## Related docs

- [OIDC](oidc.md) — how workflows authenticate to Azure
- [Entra app](../resources/entra-app.md) — the identity workflows use
- [Helm deployments](helm-deployments.md) — what `helm upgrade` does
- [ACR](../resources/acr.md) — where images are built and stored

# 05 — CI/CD

## Flow
```
PR → pr-checks (validate everything, build image, no deploy)
merge to main → deploy-stage (build+push <sha> → helm stage → bundle stage → smoke test)
deploy-stage success → promote-prod (env `prod`, required reviewer → same <sha> → helm prod → bundle prod → smoke test)
```
The artifact promoted is the **image digest built once** on main and the **same git SHA** of the bundle/dbt.

## Auth
`azure/login@v2` with `client-id`, `tenant-id`, `subscription-id` from repo **variables** (not secrets),
federated credentials created in Phase 0.5. Databricks CLI auth: `DATABRICKS_HOST` +
`ARM_CLIENT_ID`/`ARM_TENANT_ID` with OIDC token exchange via `azure-cli` auth type after `az login`.

## Workflows
### `pr-checks.yml` (pull_request)
- `terraform fmt -check`, `terraform validate` in `infra/shared`, `infra/env`
- `terraform plan -var-file=stage.tfvars` (read-only role is enough) — post plan summary as comment (optional)
- `databricks bundle validate -t stage`
- `dbt deps && dbt parse` (no warehouse needed)
- `uv run dg check defs && uv run pytest` in `dagster/`
- `docker build dagster/` (no push)

### `deploy-stage.yml` (push to main)
1. `az acr build -r $ACR -t poc:${{ github.sha }} dagster/` (also tag `stage`)
2. `az aks get-credentials --admin false` + `kubelogin convert-kubeconfig -l azurecli`
3. `helm upgrade --install dagster-stage dagster/dagster -n dagster-stage -f base -f stage --set ...tag=${{ github.sha }} --wait`
4. `databricks bundle deploy -t stage` (from `databricks/`)
5. `scripts/smoke-test.sh stage` — port-forward in background, GraphQL `launchRun` for job
   `bronze_silver_job`, poll `runOrError.status` until `SUCCESS`/`FAILURE`, timeout 20 min.

### `promote-prod.yml` (workflow_run: deploy-stage, completed, success)
- `environment: prod` (required reviewer)
- Resolve `<sha>` from the triggering run; `az acr import` or just retag `poc:<sha>` → `poc:prod`
- `helm upgrade --install dagster-prod ... --set ...tag=<sha>`
- `databricks bundle deploy -t prod` at the same SHA (`actions/checkout` with `ref: <sha>`)
- `scripts/smoke-test.sh prod`

## Concurrency
`concurrency: { group: deploy-<env>, cancel-in-progress: false }` on both deploy workflows.

## Network caveat
All of the above assumes GitHub-hosted runners can reach AKS API, ACR, and both Databricks workspaces.
Enabling Databricks IP access lists or AKS authorized IP ranges that exclude GitHub's ranges breaks
steps 2–5. Options, in order of preference for the POC:
1. Keep stage open, lock prod, run prod steps from a Container Apps job self-hosted runner.
2. Self-hosted runner for both (same change the corporate version needs).
3. `az aks command invoke` for helm steps (works through the control plane) — but bundle deploy still needs network path.

## Rollback
Prod rollback = re-run `promote-prod.yml` with a previous SHA via `workflow_dispatch` input, or
`helm rollback dagster-prod`. Bundles: `databricks bundle deploy -t prod` from the previous SHA.

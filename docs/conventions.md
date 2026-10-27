# Conventions

## Naming
Pattern: `<type>-dagster-<env|shared>[-suffix]`. Lowercase, hyphens, except where Azure forbids.

| Resource | Name |
|---|---|
| Resource groups | `rg-dagster-shared`, `rg-dagster-stage`, `rg-dagster-prod`, `rg-dagster-tfstate` |
| VNet / subnets | `vnet-dagster` / `snet-aks`, `snet-pe`, `snet-dbx-host`, `snet-dbx-container` |
| AKS | `aks-dagster` (node RG auto `MC_...`; leave default) |
| ACR | `acrdagster<4 random>` (alphanumeric only, globally unique) |
| Key Vault | `kv-dagster-<4 random>` |
| Postgres | `pg-dagster-<4 random>` ; DBs `dagster_stage`, `dagster_prod`; one admin login `pgadmin` |
| Storage (ADLS) | `stdagster<4 random>` ; containers `metastore`, `bronze`, `silver` |
| Databricks workspace | `dbw-dagster-<env>` |
| Access Connector | `dbac-dagster-<env>` |
| Managed identities | `id-dagster-<env>` (pods), `id-dagster-github` not needed (Entra app instead) |
| Entra app | `app-dagster-github` |
| Databricks SP | `sp-dagster-<env>` |
| K8s namespaces | `dagster-<env>` ; Helm releases `dagster-<env>` |
| Key Vault secrets | `pg-admin-password`, `dbx-<env>-sp-client-id`, `dbx-<env>-sp-secret`, `source-<source>-api-key` (e.g. `source-posts-api-key`), `arc-github-app-key` |

Tags on everything: `project=dagster`, `env=<env|shared>`, `owner=<you>`, `managed_by=terraform`.
See [resource naming](concepts/resource-naming.md) for the full pattern table, including the random suffix.

## Region
`eastus2` by default (`TF_VAR_location`). Serverless SQL must be available in the region; verify in Phase 2.
Exceptions on a trial subscription: Postgres in `centralus` (`pg_location`) and AKS VM `Standard_D2as_v6` (`aks_vm_size`).

## Terraform
- One state per stack: `bootstrap` (local), `shared`, `env` (workspace-free; separate state keys per tfvars).
- `infra/env` is applied twice: `-var-file=stage.tfvars -state-key stage` and prod likewise. Use
  `-backend-config="key=<env>.tfstate"` at init, with separate `.terraform` dirs
  (`TF_DATA_DIR=.terraform-<env>`).
- Providers: `azurerm`, `azuread`, `databricks` (workspace-level), `random`, `time`.
- Databricks provider auth: `az` CLI locally; in CI, `azure-client-id` with OIDC.
- `infra/modules/*` are placeholders; resources are defined inline in each stack. If modules are added, inputs are plain values, not resource objects. After every apply, run
  `scripts/setup-env.sh collect-tf <stack>` to capture outputs into `.env`.
- Never `-auto-approve` on prod.

## Helm (Dagster chart)
- `values.base.yaml`: `postgresql.enabled: false`, `generatePostgresqlPasswordSecret: false`,
  chart structure and resource limits; `dagster-user-deployments` with one deployment `poc`;
  `serviceAccount.create: true`; webserver `service.type: ClusterIP`; `runLauncher: K8sRunLauncher`;
  resources: webserver, daemon, code server and run pods each request 100m CPU and 512Mi memory (limit 512Mi).
- `values.<env>.yaml`: fixed per-env values (`DAGSTER_ENV`, `DBX_CATALOG`, DB name/user, secret
  names). Per-user values (`postgresqlHost`, `DATABRICKS_HOST`, `DBX_BUNDLE_ROOT`,
  `DBX_WAREHOUSE_HTTP_PATH`, `image.repository`, identity client ID) are `${VAR}` placeholders in the YAML,
  resolved with `envsubst` by `scripts/helm-upgrade.sh` from `.env`. Run pods need their own env, secrets, label and CSI volume.
- Deploy locally: `scripts/helm-upgrade.sh <env> [extra --set flags]`.
- Image tag set by CI or extra flag: `scripts/helm-upgrade.sh stage --set ...image.tag=<sha>`.

## Dagster code
- Package `poc` under `dagster/src/poc`; `definitions.py` is the only entry point.
- Assets: `raw_<source>` (Python, Pipes-driven; generated from `databricks/sources.yml`, key `raw/<source>`), and one asset per dbt model (`bronze_<source>`, `silver_<source>`).
- Resources: `DbtCliResource` pointing at `dbt/`. The Databricks `WorkspaceClient` is built inside the extract asset from env vars.
- No env-specific literals; everything comes from env vars set by Helm.
- There are no tests yet (`just test` runs an empty `pytest`).

## Databricks Asset Bundle
- `databricks.yml` targets `stage` and `prod`, `mode: production` on both, permissions for the CI and per-env service principals.
- Workspace host is NOT in the YAML; the bundle CLI reads `DATABRICKS_HOST` from `.env`.
  Deploy via `scripts/bundle-deploy.sh <env>`, which sets the right host.
- Variables: `catalog`, `ci_sp_client_id`, `run_as_sp_client_id`. The bundle ships files only (no pipeline or job resources); Dagster submits the notebook via Pipes.
- `scripts/bundle-deploy.sh` also grants the Dagster service principal `CAN_RUN` on the bundle directory.
- `scripts/setup-env.sh collect-bundle <env>` only prints the bundle root; Helm computes `DBX_BUNDLE_ROOT` itself.

## dbt
- Adapter `dbt-databricks`. `profiles.yml` profile `poc`, targets `stage`/`prod` read
  `DATABRICKS_HOST`, `DBX_WAREHOUSE_HTTP_PATH`, `DBX_SP_CLIENT_ID`, `DBX_SP_SECRET`, `DBX_CATALOG`;
  `auth_type: oauth`.
- Models under `models/bronze/` and `models/silver/` land in schemas `bronze` and `silver` (the `generate_schema_name` macro uses the custom schema as-is), materialized as `table`.
- One `sources.yml` (`models/bronze/sources.yml`) declares the `raw` source for the landing files.

## Git
- Trunk-based: `main` is deployable. PRs required, squash merge. Conventional commit prefixes
  (`infra:`, `dagster:`, `dbt:`, `dbx:`, `ci:`, `docs:`).

# 04 — Conventions

## Naming
Pattern: `<type>-dagsterpoc-<env|shared>[-suffix]`. Lowercase, hyphens, except where Azure forbids.

| Resource | Name |
|---|---|
| Resource groups | `rg-dagsterpoc-shared`, `rg-dagsterpoc-stage`, `rg-dagsterpoc-prod`, `rg-dagsterpoc-tfstate` |
| VNet / subnets | `vnet-dagsterpoc` / `snet-aks`, `snet-pe`, `snet-dbx-host`, `snet-dbx-container` |
| AKS | `aks-dagsterpoc` (node RG auto `MC_...`; leave default) |
| ACR | `acrdagsterpoc<4 random>` (alphanumeric only, globally unique) |
| Key Vault | `kv-dagsterpoc-<4 random>` |
| Postgres | `pg-dagsterpoc` ; DBs `dagster_stage`, `dagster_prod`; roles `dagster_stage`, `dagster_prod` |
| Storage (ADLS) | `stdagsterpoc<4 random>` ; containers `metastore`, `bronze`, `silver` |
| Databricks workspace | `dbw-dagsterpoc-<env>` |
| Access Connector | `dbac-dagsterpoc-<env>` |
| Managed identities | `id-dagster-<env>` (pods), `id-dagsterpoc-github` not needed (Entra app instead) |
| Entra app | `app-dagsterpoc-github` |
| Databricks SP | `sp-dagster-<env>` |
| K8s namespaces | `dagster-<env>` ; Helm releases `dagster-<env>` |
| Key Vault secrets | `pg-admin-password`, `pg-dagster-<env>-password`, `dbx-<env>-sp-client-id`, `dbx-<env>-sp-secret`, `source-api-key` |

Tags on everything: `project=dagsterpoc`, `env=<env|shared>`, `owner=<you>`, `managed_by=terraform`.

## Region
`eastus2` everywhere. Serverless SQL and SDP must be available in the region; verify in Phase 2.

## Terraform
- One state per stack: `bootstrap` (local), `shared`, `env` (workspace-free; separate state keys per tfvars).
- `infra/env` is applied twice: `-var-file=stage.tfvars -state-key stage` and prod likewise. Use
  `-backend-config="key=<env>.tfstate"` at init, with separate `.terraform` dirs
  (`TF_DATA_DIR=.terraform-<env>`).
- Providers: `azurerm`, `azuread`, `databricks` (account + workspace aliases), `random`.
- Databricks provider auth: `az` CLI locally; in CI, `azure-client-id` with OIDC.
- Module interfaces: inputs are plain values, not resource objects. After every apply, run
  `scripts/setup-env.sh collect-tf <stack>` to capture outputs into `.env`.
- Never `-auto-approve` on prod.

## Helm (Dagster chart)
- `values.base.yaml`: `postgresql.enabled: false`, `generatePostgresqlPasswordSecret: false`,
  chart structure and resource limits; `dagster-user-deployments` with one deployment `poc`;
  `serviceAccount.create: true`; webserver `service.type: ClusterIP`; `runLauncher: K8sRunLauncher`;
  resources ~ webserver 250m/512Mi, daemon 250m/512Mi, code server 250m/512Mi, run pods 500m/1Gi.
- `values.<env>.yaml`: fixed per-env values (`DAGSTER_ENV`, `DBX_CATALOG`, DB name/user, secret
  names). Per-user values (`postgresqlHost`, `DATABRICKS_HOST`, `DBX_BRONZE_PIPELINE_ID`,
  `DBX_WAREHOUSE_HTTP_PATH`, `image.repository`) are empty in the YAML and overridden by
  `scripts/helm-upgrade.sh` from `.env`.
- Deploy locally: `scripts/helm-upgrade.sh <env> [extra --set flags]`.
- Image tag set by CI or extra flag: `scripts/helm-upgrade.sh stage --set ...image.tag=<sha>`.

## Dagster code
- Package `poc` under `dagster/src/poc`; `definitions.py` is the only entry point.
- Assets: `bronze_<source>` (Python, SDK-driven), `silver_<model>` (dbt). Asset keys match UC
  table names: `AssetKey([catalog_layer, table])` where layer ∈ {bronze, silver}.
- Resources: `DatabricksResource` wrapping `WorkspaceClient` built from env vars;
  `DbtCliResource` with `project_dir=/app/dbt`, `profiles_dir=/app/dbt`, `target=os.environ["DAGSTER_ENV"]`.
- No env-specific literals. `pytest` asserts no string starting with `adb-` or `https://` in `src/`.

## Databricks Asset Bundle
- `databricks.yml` targets `stage` and `prod`, `mode: production` on both, `run_as` the env SP.
- Workspace host is NOT in the YAML; the bundle CLI reads `DATABRICKS_HOST` from `.env`.
  Deploy via `scripts/bundle-deploy.sh <env>`, which sets the right host.
- Variables: `catalog`, `warehouse_id`, `source_url`. Pipeline name `bronze_<source>_pipeline`.
- Pipelines serverless, `development: false`, `continuous: false`, `edition: CORE`.
- After deploy: `scripts/setup-env.sh collect-bundle <env>` captures the pipeline ID into `.env`.

## dbt
- Adapter `dbt-databricks`. `profiles.yml` profile `poc`, targets `stage`/`prod` read
  `DATABRICKS_HOST`, `DBX_WAREHOUSE_HTTP_PATH`, `DBX_SP_CLIENT_ID`, `DBX_SP_SECRET`, `DBX_CATALOG`;
  `auth_type: oauth`.
- Schema `silver`; models materialized as `table`. One `sources.yml` for `bronze`.

## Git
- Trunk-based: `main` is deployable. PRs required, squash merge. Conventional commit prefixes
  (`infra:`, `dagster:`, `dbt:`, `dbx:`, `ci:`, `docs:`).

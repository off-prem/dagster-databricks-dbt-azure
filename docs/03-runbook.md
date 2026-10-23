# 03 — Runbook

Source of truth for progress. Each step is tagged **[CLAUDE]** (Claude Code executes) or
**[MANUAL]** (you do it in a portal/browser/console; Claude gives instructions and waits for values).
Check boxes as you go. Each phase ends with a **Done when** check.

Conventions: `<env>` ∈ {stage, prod}. Region `eastus2` unless changed in `04-conventions.md`.
Shared values go into `infra/env/<env>.tfvars` or `deploy/helm/values.<env>.yaml`; per-user values (subscription, tenant, IP) come from `source scripts/tf-env.sh`, and account outputs (e.g. metastore ID) go in gitignored `infra/env/local.auto.tfvars` — never secrets.

---

## Phase 0 — Accounts and bootstrap

- [x] **0.1 [MANUAL] Azure account.** Create a free Azure account at azure.microsoft.com/free. Note the
  $200/30-day credit and 12-month free services (B1ms Postgres, B-series VM hours may apply).
  Bring back: **Subscription ID**, **Tenant ID** (`az account show`).
- [x] **0.2 [MANUAL] GitHub.** Create an org (or use personal), create this repo, push.
  Bring back: **org/repo** name.
- [x] **0.3 [MANUAL] Local tools.** Run `scripts/setup-tools.sh` (installs the pins in `.tool-versions`; binaries go to `~/.local/bin` (ensure it is on PATH); `az` uses Microsoft's apt repo on Debian/Ubuntu (needs sudo), else pip — override with `AZ_INSTALL=apt|brew|pip`).
  Run `az login`, `az account set --subscription <id>`. Claude verifies versions against `.tool-versions`.
- [ ] **0.4 [CLAUDE] Register resource providers.**
  `Microsoft.Databricks`, `Microsoft.ContainerService`, `Microsoft.ContainerRegistry`,
  `Microsoft.DBforPostgreSQL`, `Microsoft.KeyVault`, `Microsoft.ManagedIdentity`, `Microsoft.Storage`.
  Notes:
- [ ] **0.5 [CLAUDE] Terraform bootstrap** (`infra/bootstrap`): RG `rg-dagsterpoc-tfstate`, storage account
  + container `tfstate`; Entra app `app-dagsterpoc-github` with federated credentials for
  `repo:<org>/<repo>:ref:refs/heads/main`, `...:environment:stage`, `...:environment:prod`;
  Contributor + User Access Administrator on the subscription (tighten later). Output client ID.
  Local state for this one stack is acceptable; commit nothing sensitive.
  Notes:
- [ ] **0.6 [MANUAL] GitHub variables.** (Then `git mv ci/pending-workflows/pr-checks.yml .github/workflows/`.) Repo → Settings → Secrets and variables → Actions → Variables:
  `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`. Create Environments `stage` and
  `prod`; on `prod` add yourself as a required reviewer.
- [ ] **0.7 [CLAUDE] Backend config.** Point `infra/shared` and `infra/env` at the tfstate backend
  (`key = shared.tfstate`, `key = <env>.tfstate`). `terraform init` both.

**Done when:** `az account show` works, `terraform init` succeeds in `infra/shared` and `infra/env`,
GitHub variables are set, `pr-checks.yml` (moved from `ci/pending-workflows/` to `.github/workflows/` in 0.6) passes `az login` via OIDC on a test PR.

---

## Phase 1 — Shared infrastructure

- [ ] **1.1 [CLAUDE] `infra/shared` apply:** RG, VNet/subnets/NSG, ACR Basic, Key Vault (RBAC),
  Postgres Flexible B1ms (public access, firewall rule for your IP; AKS egress IP added in 1.3),
  ADLS Gen2 account + containers `metastore`, `bronze`, `silver`.
  Notes:
- [ ] **1.2 [CLAUDE] AKS** (module `aks`): Free tier, 1× B2ms, osdisk 32, Entra RBAC, authorized IP =
  your IP, OIDC issuer, workload identity, Secrets Store CSI addon with rotation, ACR pull role.
  Output: OIDC issuer URL, outbound public IP.
  Notes:
- [ ] **1.3 [CLAUDE] Firewalls.** Add AKS outbound IP to Postgres, Key Vault, and storage firewalls.
- [ ] **1.4 [CLAUDE] Verify.** `az aks get-credentials`, `kubectl get nodes`; `psql` to Postgres
  from your machine. Store Postgres admin password in Key Vault (`pg-admin-password`).
- [ ] **1.5 [CLAUDE] Scripts.** Fill `scripts/start.sh`, `scripts/stop.sh`, `scripts/port-forward.sh`
  with real resource names. Test stop → start.

**Done when:** `kubectl get nodes` shows Ready; `scripts/stop.sh && scripts/start.sh` round-trips.

---

## Phase 2 — Stage environment

- [ ] **2.1 [CLAUDE] `infra/env` apply with `stage.tfvars`:** RG, Databricks workspace (Premium,
  managed VNet), Access Connector, user-assigned identity `id-dagster-stage` + federated credential
  for SA `dagster-stage/dagster-user-deployments`, Key Vault Secrets User role, Postgres DB
  `dagster_stage` + role, K8s namespace `dagster-stage`.
  Notes:
- [ ] **2.2 [MANUAL] Databricks first login + trial.** Open the workspace URL from Terraform output,
  log in, accept the trial if offered. Bring back: **workspace URL**, **workspace ID**.
- [ ] **2.3 [MANUAL] Unity Catalog metastore** (first env only). accounts.azuredatabricks.net →
  Catalog → Create metastore: region, ADLS path `abfss://metastore@<acct>.dfs.core.windows.net/`,
  Access Connector resource ID from 2.1. Assign to the stage workspace.
  Bring back: **metastore ID**. (Later: Terraform `databricks_metastore` can own this; for POC, import it.)
- [ ] **2.4 [CLAUDE] Workspace objects via Terraform** (databricks provider, auth via `az` CLI):
  storage credential + external locations `bronze`/`silver`; catalog `stage`; schemas `bronze`,
  `silver`, `ops`; volume `ops.dagster_pipes`; SQL warehouse (serverless 2X-Small, auto-stop 5);
  service principal `sp-dagster-stage` with OAuth secret → Key Vault `dbx-stage-sp-client-id` /
  `dbx-stage-sp-secret`; grants; IP access list with your IP.
  Notes:
- [ ] **2.5 [CLAUDE] Dagster image.** `dagster/` scaffold with `dg`, `pyproject.toml` with
  `dagster`, `dagster-databricks`, `dagster-dbt`, `dbt-databricks`, `databricks-sdk`. One trivial
  asset `databricks_whoami` calling `current_user.me()`. Dockerfile copies `dbt/`. `az acr build`.
- [ ] **2.6 [CLAUDE] Helm.** `deploy/helm/values.base.yaml` (external Postgres, CSI
  SecretProviderClass env injection, workload identity labels, resources sized for B2ms) +
  `values.stage.yaml`. `deploy/k8s/stage/secretproviderclass.yaml`. `helm upgrade --install`.
- [ ] **2.7 [CLAUDE] Smoke.** `scripts/port-forward.sh stage`, open UI, materialize
  `databricks_whoami`. Fix until green.

**Done when:** `databricks_whoami` materializes on stage and its metadata shows `sp-dagster-stage`.
**→ Goal 1 achieved.**

---

## Phase 3 — The two assets

- [ ] **3.1 [MANUAL] Pick the source API.** Something public, keyless or free-key, JSON, paginated
  or not. Default suggestion: a public open-data endpoint. If keyed, put the key in Key Vault as
  `source-api-key` and bring back its name only.
- [ ] **3.2 [CLAUDE] Databricks Asset Bundle.** `databricks/databricks.yml` with targets `stage`/`prod`
  and variables `catalog`, `warehouse_id`. `resources/bronze_pipeline.yml`: serverless SDP pipeline,
  triggered, target schema `bronze`. `src/bronze_ingest.py`: `@dp.table` (or `@dlt.table` depending on
  runtime) reading the API with `requests`, returning a DataFrame with `_ingested_at`.
  `databricks bundle validate && databricks bundle deploy -t stage`. Output pipeline ID →
  `values.stage.yaml` `DBX_BRONZE_PIPELINE_ID`.
  Notes:
- [ ] **3.3 [CLAUDE] Dagster asset #1** `bronze_<source>`: start pipeline update via SDK, poll,
  fail on failed update, emit `update_id`, `rows` (via SQL count on the warehouse) as metadata.
- [ ] **3.4 [CLAUDE] dbt.** `dbt/` project; `profiles.yml` from env vars; one model
  `silver/silver_<model>.sql` selecting/cleaning from `{{ source('bronze', '<source>') }}`;
  `sources.yml`. `dbt debug && dbt build` locally against stage with your own creds.
- [ ] **3.5 [CLAUDE] Dagster asset #2** via `dagster-dbt` `DbtProject` + `@dbt_assets`, with the
  bronze source mapped to `bronze_<source>` so lineage is one graph. Optional: a daily schedule on stage.
- [ ] **3.6 [CLAUDE] Rebuild image, helm upgrade stage, materialize both in order.**

**Done when:** `select count(*) from stage.silver.silver_<model>` > 0 and Dagster shows both assets
materialized with lineage. **→ Goal 2 achieved.**

---

## Phase 4 — Prod environment

- [ ] **4.1 [CLAUDE] Copy `stage.tfvars` → `prod.tfvars`,** change env values only. `terraform apply`.
- [ ] **4.2 [MANUAL] Prod workspace first login;** assign existing metastore to it in the account console.
- [ ] **4.3 [CLAUDE] Workspace objects for prod** (catalog `prod`, SP `sp-dagster-prod`, warehouse, grants).
- [ ] **4.4 [CLAUDE] `databricks bundle deploy -t prod`;** `values.prod.yaml`; helm install
  `dagster-prod` with the **same image tag** currently on stage. Materialize both assets once, manually.

**Done when:** prod mirrors stage and the only diffs are `git diff --no-index` between
`stage.tfvars`/`prod.tfvars` and `values.stage.yaml`/`values.prod.yaml`. **→ Goal 3 achieved.**

---

## Phase 5 — CI/CD

- [ ] **5.1 [CLAUDE] `pr-checks.yml`:** terraform fmt/validate + plan (stage), `databricks bundle
  validate`, `dbt parse` (no warehouse), `dg check defs`, `uv run pytest`, `az acr build --no-push`
  equivalent (docker build only).
- [ ] **5.2 [CLAUDE] `deploy-stage.yml`** (parked in `ci/pending-workflows/`; move to `.github/workflows/`) on push to `main`: `az acr build` tagged `${{ github.sha }}`
  → `helm upgrade dagster-stage --set ...image.tag=<sha>` → `bundle deploy -t stage` →
  `scripts/smoke-test.sh stage` (GraphQL launch of both assets, poll to success, 20-min timeout).
- [ ] **5.3 [CLAUDE] `promote-prod.yml`** (parked in `ci/pending-workflows/`; move to `.github/workflows/`) triggered by `workflow_run` success of deploy-stage,
  environment `prod` (required reviewer gate): same `<sha>` → `helm upgrade dagster-prod`,
  `bundle deploy -t prod`, `scripts/smoke-test.sh prod`.
- [ ] **5.4 [MANUAL] Approve the first prod promotion** in GitHub → Actions.
- [ ] **5.5 [CLAUDE] Harden.** Restrict the GitHub app's RBAC to the three RGs + ACR + AKS user role.
  Copy `.github/CODEOWNERS.example` to `.github/CODEOWNERS` with your handle/team.

**Done when:** a trivial PR (e.g., a dbt model comment) flows main → stage → approval → prod with no
manual steps other than the approval. **→ Goal 4 achieved.**

---

## Phase 6 — Wrap-up (optional)
- [ ] Run `scripts/stop.sh`. Note the actual month's cost in `02-services-and-costs.md`.
- [ ] Review `08-corporate-migration.md` against what you learned; update.
- [ ] Try the upgrade path: federate `id-dagster-stage` as the Databricks SP identity (no secret).

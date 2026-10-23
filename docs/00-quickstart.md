# 00 — Quickstart checklist

Everything a new person needs, in order, to stand up the POC from a fresh clone. Each item points to its
step in [`03-runbook.md`](03-runbook.md), which holds the detail and is the source of truth for progress.
**[You]** = browser, portal or credential work. **[Claude Code]** = run it in a Claude Code session in this
repo (it reads `CLAUDE.md` and follows the runbook); the commands are in the runbook if you do it by hand.

Expect roughly $50–100/month while it runs (`02-services-and-costs.md`). Stop it when idle (step 6).

## 0. Prerequisites
- [ ] An email and a card for an Azure free account, a GitHub account, and rights to create a repo or fork.
- [ ] Linux, WSL or macOS with `git`, `curl` and `python3`.
- [ ] Fork or clone this repo and work on branches. Never commit to `main`; merge by PR.

## 1. Tools and accounts (Phase 0)
- [ ] **[You]** Run `scripts/setup-tools.sh`; put `~/.local/bin` on your `PATH`. (0.3)
- [ ] **[You]** Create the Azure free account. Run `az login`, then
      `az account show --query "{subscription:id, tenant:tenantId}" -o tsv`. (0.1)
- [ ] **[You]** Before any Terraform command run `source scripts/tf-env.sh`. It exports your subscription, tenant
      and public IP as `TF_VAR_*`, so nothing personal is committed. Re-run it if your IP changes.
- [ ] **[Claude Code]** Register the Azure resource providers. (0.4)
- [ ] **[Claude Code]** Terraform bootstrap: state storage plus the GitHub OIDC app. Keep its client ID. (0.5)
- [ ] **[You]** GitHub → Settings → Variables: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`.
      Create Environments `stage` and `prod`; add yourself as required reviewer on `prod`. (0.6)
- [ ] **[Claude Code]** Point `infra/shared` and `infra/env` at the state backend; `terraform init`. (0.7)
- [ ] `git mv ci/pending-workflows/pr-checks.yml .github/workflows/`; a test PR should pass `az login`.

## 2. Shared infrastructure (Phase 1)
- [ ] **[Claude Code]** Apply `infra/shared`: network, ACR, Key Vault, Postgres, ADLS, then AKS and firewalls. (1.1–1.3)
- [ ] **[Claude Code]** Verify `kubectl get nodes` is Ready and Postgres is reachable. (1.4)
- [ ] **[Claude Code]** Fill the `scripts/` helpers; `scripts/stop.sh && scripts/start.sh` round-trips. (1.5)

## 3. Stage (Phase 2): Goal 1
- [ ] **[Claude Code]** Apply `infra/env` with `stage.tfvars`: Databricks workspace, identity, Postgres DB, namespace. (2.1)
- [ ] **[You]** Open the workspace URL, log in, accept the trial. Bring back workspace URL and ID. (2.2)
- [ ] **[You]** accounts.azuredatabricks.net → create the Unity Catalog metastore and assign it to the
      stage workspace. Bring back the metastore ID. (2.3)
- [ ] **[Claude Code]** Workspace objects: catalog, schemas, warehouse, service principal, secrets in Key Vault. (2.4)
- [ ] **[Claude Code]** Build the Dagster image, install via Helm, port-forward. (2.5–2.7)
- [ ] **Check:** `scripts/port-forward.sh stage`, open http://localhost:3000, materialize `databricks_whoami`.

## 4. The two assets (Phase 3): Goal 2
- [ ] **[You]** Pick a public source API; if it needs a key, put it in Key Vault as `source-api-key`. (3.1)
- [ ] **[Claude Code]** Databricks bundle, `bronze` asset, dbt model, `silver` asset, image rebuild and Helm upgrade. (3.2–3.6)
- [ ] **Check:** `select count(*) from stage.silver.silver_<model>` > 0, and Dagster shows both assets with lineage.

## 5. Prod and CI/CD (Phases 4–5): Goals 3 and 4
- [ ] **[Claude Code]** Apply prod config, then **[You]** log in to the prod workspace and assign the metastore. (4.1–4.2)
- [ ] **[Claude Code]** Prod workspace objects, bundle deploy, and Helm install with the **same image tag** as stage. (4.3–4.4)
      Prod applies and upgrades need your explicit go-ahead.
- [ ] **[Claude Code]** Move the parked `deploy-stage.yml` and `promote-prod.yml` into `.github/workflows/`
      and complete them. (5.1–5.3)
- [ ] **[You]** Approve the first prod promotion in GitHub → Actions. (5.4)
- [ ] **[Claude Code]** Restrict the GitHub app's RBAC, add `CODEOWNERS`. (5.5)
- [ ] **Check:** a trivial PR flows main → stage → your approval → prod.

## 6. Cost control (always)
- [ ] Run `scripts/stop.sh` when you finish for the day, `scripts/start.sh` to resume (`06-stop-start.md`).
- [ ] Postgres restarts itself after 7 stopped days; stop it again weekly if you're away.
- [ ] Monthly: check Cost Management and record the actual in `02-services-and-costs.md`.

## If something goes wrong
Read the error, fix the root cause, and add a gotcha to that runbook step's `Notes:` line.
Design rationale is in `07-decisions.md`; check it before adding anything not in `02-services-and-costs.md`.

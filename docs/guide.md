# Setup guide

Stand up the full POC from a fresh clone. Each phase is a single command
(`just phase <N>`) that runs every step, verifies the result, and pauses at
manual steps with instructions. Re-running a phase safely skips completed work.

New to Azure or Terraform? The `tools/`, `resources/`, and `concepts/` directories explain
each component in detail — this guide links to them as they come up. Start here and follow
the links when you want to understand something deeper.

**Cost:** ~$50–100/month while running; ~$35–40/month stopped. Phase 0 is free. Costs start
in Phase 1. Run `just stop` when idle (see [stop/start](concepts/stop-start.md)).

**Naming:** Resource names use the `TF_VAR_project` prefix (default `dagster`). The phase
runner prompts you to choose this in Phase 0. Examples below show the default — substitute
your project name if you changed it (e.g. `rg-myproject-shared` instead of `rg-dagster-shared`).

**Reference docs:**
[Index of every tool, resource and concept](README.md) ·
[Architecture](architecture.md) ·
[Costs](costs.md) ·
[Conventions](conventions.md) ·
[Decisions](decisions.md)

---

## Quick start

```bash
git clone git@github.com:<your-org>/<your-repo>.git && cd <your-repo>
scripts/setup-tools.sh               # install all CLIs (one-time)
export PATH="$HOME/.local/bin:$PATH"  # add to ~/.bashrc to persist
just phase 0                          # accounts, tools, bootstrap (~20 min)
just phase 1                          # shared infrastructure (~15 min, costs begin)
just phase 2                          # stage environment (~20 min)
just phase 3                          # dbt and lineage (~5 min)
just phase 4                          # prod environment (~15 min)
just phase 5                          # CI/CD (~15 min)
```

Each phase pauses at manual steps (browser logins, metastore creation, GitHub App
setup) with instructions and verifies your work before continuing.

---

## Prerequisites

- **An email and credit card** for an Azure free account ($200/30-day credit).
- **A GitHub account** with rights to create a repository.
- **Linux, WSL, or macOS** with `git`, `curl`, and `python3`.

---

## Phase 0 — Accounts, tools, and bootstrap

```bash
just phase 0
```

This phase costs nothing. The phase runner:

| Step | What it does | Automated? |
|------|-------------|------------|
| 0.1 | Verify repo clone | ✓ |
| 0.2 | Install CLI tools (`setup-tools.sh`) | ✓ |
| 0.3 | Azure account and login | Manual — prints instructions, verifies `az login` |
| 0.4 | GitHub CLI login | Manual — prints instructions, verifies `gh auth status` |
| 0.5 | Generate `.env` with project settings | Interactive — prompts for project name and region |
| 0.6 | Register Azure resource providers | ✓ (idempotent, waits for completion) |
| 0.7 | Terraform bootstrap | ✓ with confirmation — shows plan, asks `Apply? [y/N]` |
| 0.8 | Configure Terraform backends | ✓ |
| 0.9 | Sync GitHub variables | ✓ (`setup-ci.sh`) |
| 0.10 | Validate code projects (dbt parse, Dagster definitions) | ✓ |

### What it creates

| Resource | Name | Cost |
|----------|------|------|
| Resource group | `rg-dagster-tfstate` | Free |
| Storage account + container | `stdagstertf<random>/tfstate` | ~$0.01/month |
| [Entra app](resources/entra-app.md) | `app-dagster-github` | Free |
| 4 federated credentials | `main`, `environment:stage`, `environment:prod`, `pull_request` | Free |
| 2 role assignments | Contributor + User Access Administrator | Free |

### Decision point: naming

Step 0.5 prompts you to choose:

| Variable | Default | What it controls |
|----------|---------|-----------------|
| `TF_VAR_project` | `dagster` | Resource name prefix: `rg-{project}-shared`, `aks-{project}`, `dbw-{project}-stage`, etc. |
| `TF_VAR_location` | `eastus2` | Azure region for all resources |

These are baked into resource names. **Changing them later means recreating resources.**

### Manual steps

**Azure account (0.3):** Create at [azure.microsoft.com/free](https://azure.microsoft.com/free),
then `az login`. The runner verifies your login before continuing.

**GitHub CLI (0.4):** Run `gh auth login`. Used to detect OIDC settings and sync CI variables.

### Troubleshooting

**Session expired:** Azure CLI tokens expire quickly on new accounts (security defaults).
Re-authenticate:
```bash
source scripts/load-env.sh
az logout
az login --tenant "$TF_VAR_tenant_id" --scope "https://management.azure.com/.default"
```

**Done when:** All 10 steps pass. State files in blob storage, GitHub variables synced.

---

## Phase 1 — Shared infrastructure

```bash
just phase 1
```

This is where costs begin. See [costs](costs.md) for the full breakdown and
[stop/start](concepts/stop-start.md) for halting resources when idle.

| Step | What it does | Automated? |
|------|-------------|------------|
| 1.1 | Pre-flight: SKU availability checks | ✓ |
| 1.2 | Apply shared Terraform (`~10-15 min`) | ✓ with confirmation |
| 1.3 | Verify AKS + Key Vault connectivity | ✓ |
| 1.4 | Test stop/start (optional) | Skipped — run `just stop`/`just start` manually |

### What it creates

| Resource | Est. $/month | Details |
|----------|-------------|---------|
| [VNet](resources/vnet.md) + subnets + NSG | 0 | Network layout |
| [ACR](resources/acr.md) (Basic) | ~5 | Docker image store |
| [Key Vault](resources/key-vault.md) | <1 | Secrets store |
| [Postgres](resources/postgres.md) (B2s) | ~25 running, ~6 stopped | Dagster state |
| [ADLS Gen2](resources/adls.md) | ~2 | Data lake storage |
| [AKS](resources/aks.md) (1× `Standard_D2as_v6` by default) | see [costs](costs.md) | Kubernetes cluster |

### Troubleshooting

**SKU not available:** The pre-flight check (1.1) catches this. If AKS or Postgres SKUs
aren't available in your region/subscription:
```bash
just set-env TF_VAR_aks_vm_size Standard_D2as_v6    # or another available size
just set-env TF_VAR_pg_location centralus            # B-series often available here
```

**Done when:** `kubectl get nodes` shows Ready, all resources in `rg-dagster-shared`.

---

## Phase 2 — Stage environment (Goal 1: Dagster talks to Databricks)

```bash
just phase 2
```

| Step | What it does | Automated? |
|------|-------------|------------|
| 2.1 | Apply stage Terraform (workspace, identity) | ✓ with confirmation |
| 2.2 | First login to Databricks workspace | Manual — prints URL, verifies CLI access |
| 2.3 | Create Unity Catalog metastore | Manual — prints detailed instructions |
| 2.4 | Re-apply stage Terraform (catalog, SP, warehouse) | ✓ with confirmation |
| 2.5 | Apply SecretProviderClass | ✓ |
| 2.6 | Store dummy API key in Key Vault | ✓ |
| 2.7 | Verify Databricks CLI auth | ✓ |
| 2.8 | Deploy Databricks bundle | ✓ |
| 2.9 | Build and push Docker image (ACR) | ✓ |
| 2.10 | Deploy Dagster via Helm | ✓ |
| 2.11 | Smoke test | ✓ (prompted — runs `smoke-test.sh`) |

### Manual steps

**Databricks login (2.2):** Open the workspace URL (printed by the runner), log in
with Azure credentials, accept the Premium trial.

**Unity Catalog metastore (2.3):** One-time setup in the Databricks account console.
The runner prints the exact values to fill in (ADLS path, Access Connector ID, region).
See [Unity Catalog](concepts/unity-catalog.md) for background.

### What it creates

- Resource group (`rg-dagster-stage`), Databricks workspace, Access Connector,
  managed identity
- Catalog `stage`, schemas `bronze`/`silver`, managed volume `landing`
- Serverless SQL warehouse, service principal, IP access list, UC grants
- SP credentials in Key Vault
- Dagster deployment in `dagster-stage` namespace

### Troubleshooting

**Serverless SQL warehouse + ADLS firewall:** The storage account firewall blocks
serverless compute. You need an Azure Network Security Perimeter (NSP) with the
`AzureDatabricksServerless` service tag. This is configured in `infra/shared/main.tf`.

**dbt-databricks auth warning:** The adapter warns about `azure_client_id` vs `client_id`.
Both work; we use `client_id`/`client_secret` per the [official docs](https://learn.microsoft.com/en-us/azure/databricks/integrations/configure-oauth-dbt).

**Done when:** `raw_posts` materializes and data appears in the landing volume.
**→ Goal 1: Dagster on AKS talks to Databricks.**

---

## Phase 3 — dbt and end-to-end lineage (Goal 2: end-to-end pipeline)

```bash
just phase 3
```

| Step | What it does | Automated? |
|------|-------------|------------|
| 3.1 | Verify dbt connection to stage warehouse | ✓ |
| 3.2 | Build dbt models (bronze + silver) | ✓ (prompted) |
| 3.3 | Validate Dagster definitions with live credentials | ✓ |

The phase runner fetches the SP secret from Key Vault automatically.

**dbt models:**
- **`bronze_posts`** — `read_files()` from the landing volume
- **`silver_posts`** — selects from `bronze_posts` with column renames

**Done when:** `SELECT count(*) FROM stage.silver.silver_posts` > 0 and Dagster shows
the full lineage: `raw_posts` → `bronze_posts` → `silver_posts`.
**→ Goal 2: end-to-end data pipeline.**

---

## Phase 4 — Prod (Goal 3: stage/prod parity)

```bash
just phase 4
```

| Step | What it does | Automated? |
|------|-------------|------------|
| 4.1 | Apply prod Terraform (workspace, identity) | ✓ with confirmation |
| 4.2 | First login to prod workspace | Manual — prints URL, verifies CLI access |
| 4.3 | Re-apply prod Terraform (catalog, SP, warehouse) | ✓ with confirmation |
| 4.4 | Apply prod SecretProviderClass | ✓ |
| 4.5 | Verify dummy API key in Key Vault | ✓ |
| 4.6 | Deploy to prod (bundle + Helm) | ✓ |

### Manual step

**Prod workspace login (4.2):** Same as stage — open the URL, log in, verify metastore
is assigned. If the prod workspace is in the same region as the metastore, Databricks
auto-assigns it. If not, assign manually in the account console.

**Done when:** Prod mirrors stage. `kubectl get pods -n dagster-prod` all Running.
**→ Goal 3: stage/prod parity.**

---

## Phase 5 — CI/CD (Goal 4: automated promotion)

```bash
just phase 5
```

See [CI/CD](concepts/cicd.md) for the full workflow architecture.

| Step | What it does | Automated? |
|------|-------------|------------|
| 5.1 | Sync GitHub variables and environments | ✓ (`setup-ci.sh`) |
| 5.2 | Grant OIDC SP access to AKS + Databricks | ✓ |
| 5.3 | Create GitHub App for ARC | Manual — detailed instructions |
| 5.4 | Install ARC on AKS | ✓ (`setup-arc.sh`) |
| 5.5 | Verify workflow files | ✓ |
| 5.6 | First prod promotion | Manual — push a PR, approve the deploy |

### Manual steps

**GitHub App (5.3):** Create a GitHub App for ARC authentication. The runner prints
step-by-step instructions including the Key Vault name and the `just set-env` commands
to record the App ID and Installation ID. See [decision #16](decisions.md) for why ARC
over GitHub-hosted runners.

**First promotion (5.6):** Push a trivial PR to test the full flow:
merge → `deploy-stage` → approval → `promote-prod`.

### Workflows

- **pr-checks.yml** — terraform fmt/validate, bundle validate, dbt parse, Dagster
  definitions load, docker build. Runs on GitHub-hosted runners.
- **deploy-stage.yml** — ACR build → helm upgrade (stage) → bundle deploy (stage) →
  smoke test. Runs on ARC.
- **promote-prod.yml** — same image SHA → helm upgrade (prod) → bundle deploy (prod) →
  smoke test. Requires `environment: prod` approval. Runs on ARC.

**Pushing workflow files** requires the `workflow` scope:
```bash
gh auth refresh -s workflow --web=false
```

**Done when:** A trivial PR flows `main → stage → approval → prod`.
**→ Goal 4: automated promotion.**

---

## After setup

See **[operations.md](operations.md)** for day-to-day commands: cost control,
deploying changes, running dbt, IP changes, and the full command reference.

---

## What's next

- **Phase 6 (optional):** Record actual costs in [costs.md](costs.md), review
  [corporate migration](corporate-migration.md), try workload identity federation
  (drop the SP secret).
- **Going corporate:** Every change is infra config, not application code. See
  [corporate-migration.md](corporate-migration.md).

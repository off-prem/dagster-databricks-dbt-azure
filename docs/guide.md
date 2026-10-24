# Setup guide

Step-by-step instructions to stand up the full POC from a fresh clone. Every command is
listed with what it does and what to expect.

New to Azure or Terraform? The `tools/`, `resources/`, and `concepts/` directories explain
each component in detail — this guide links to them as they come up. Start here and follow
the links when you want to understand something deeper.

**Cost:** ~$50–100/month while running; ~$35–40/month stopped. Phase 0 is free. Costs start
in Phase 1. Run `just stop` when idle (see [stop/start](concepts/stop-start.md)).

**Reference docs:**
[Architecture](architecture.md) ·
[Costs](costs.md) ·
[Conventions](conventions.md) ·
[Decisions](decisions.md)

---

## Prerequisites

- **An email and credit card** for an Azure free account ($200/30-day credit).
- **A GitHub account** with rights to create a repository.
- **Linux, WSL, or macOS** with `git`, `curl`, and `python3`.

---

## Phase 0 — Accounts, tools, and bootstrap

This phase costs nothing.

### 0.1 Create your own copy of this repo ✅

Fork or "Use this template," then clone **your fork** — `origin` must point to a repo you
control. Later, GitHub Actions gets permission to deploy to Azure scoped to the repo in
your `origin` remote.

```bash
git clone git@github.com:<your-org>/<your-repo>.git
cd <your-repo>
```

Work on branches; merge via PR; never commit directly to `main`.

### 0.2 Create an Azure free account ✅

Go to [azure.microsoft.com/free](https://azure.microsoft.com/free) and sign up. No
resources are created yet.

### 0.3 Install CLI tools ✅

```bash
scripts/setup-tools.sh
```

Installs pinned versions of all tools into `~/.local/bin`. See [tools/](tools/) for what
each one does. Add the bin directory to your PATH:

```bash
export PATH="$HOME/.local/bin:$PATH"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc   # persist
```

Verify: `just --version`, `terraform version`, `az version`.

### 0.4 Log in to Azure ✅

```bash
az login
az account set --subscription <subscription-id>    # if you have multiple
az account show --query '{subscription:id, tenant:tenantId}' -o table
```

See [Azure CLI](tools/azure-cli.md) for more detail. You'll see a **subscription ID**
(your billing container) and **tenant ID** (your identity directory).

### 0.5 Generate your `.env` file ✅

```bash
just setup-env
```

Detects your subscription, tenant, public IP, GitHub repo, and name. Writes them to a
git-ignored `.env` and scaffolds blank keys for future phases. See [just](tools/just.md)
for how `.env` auto-loading works.

Verify: `just show-env` — you should see filled-in `TF_VAR_*` values plus blank placeholders.

### 0.6 Register Azure resource providers ✅

Azure groups services into **resource providers** that must be registered on your
subscription before you can create resources from them. This is free and permanent.

```bash
for ns in Microsoft.Databricks Microsoft.ContainerService Microsoft.ContainerRegistry \
  Microsoft.DBforPostgreSQL Microsoft.KeyVault Microsoft.ManagedIdentity Microsoft.Storage; do
  az provider register -n "$ns"
done
```

Verify (all should say `Registered`; wait and re-run if any say `Registering`):

```bash
for ns in Microsoft.Databricks Microsoft.ContainerService Microsoft.ContainerRegistry \
  Microsoft.DBforPostgreSQL Microsoft.KeyVault Microsoft.ManagedIdentity Microsoft.Storage; do
  printf "%-40s %s\n" "$ns" "$(az provider show -n $ns --query registrationState -o tsv)"
done
```

### 0.7 Terraform bootstrap ✅

Creates two things: a storage account for [Terraform state](concepts/terraform-state.md)
(~$0.01/month), and an [Entra app](resources/entra-app.md) for
[GitHub Actions OIDC](concepts/oidc.md) (free).

This is the only stack that uses local state — see
[Terraform state](concepts/terraform-state.md) for why.

```bash
just tf-init bootstrap     # download providers (no resources created)
just tf-plan bootstrap     # preview — review the + lines
just tf-apply bootstrap    # create resources (type "yes" to confirm)
```

See [Terraform](tools/terraform.md) for what init/plan/apply do.

**What it creates:**

| Resource | Name | Cost |
|----------|------|------|
| Resource group | `rg-dagster-tfstate` | Free |
| Storage account + container | `stdagstertf<random>/tfstate` | ~$0.01/month |
| [Entra app](resources/entra-app.md) | `app-dagster-github` | Free |
| 3 federated credentials | `main`, `environment:stage`, `environment:prod` | Free |
| 2 role assignments | Contributor + User Access Administrator | Free |

Capture outputs:

```bash
just collect-tf bootstrap    # writes AZURE_CLIENT_ID to .env
```

### 0.8 Set up GitHub repository variables

These tell GitHub how to authenticate to Azure via [OIDC](concepts/oidc.md).

Go to your repo → **Settings** → **Secrets and variables** → **Actions** → **Variables**.
Create:

| Variable | Value (from `just show-env`) |
|----------|----------------------------|
| `AZURE_CLIENT_ID` | `AZURE_CLIENT_ID` |
| `AZURE_TENANT_ID` | `TF_VAR_tenant_id` |
| `AZURE_SUBSCRIPTION_ID` | `TF_VAR_subscription_id` |

Create **Environments** `stage` and `prod`. On `prod`, add yourself as **required reviewer**
(gates prod deploys to your approval). Note: required reviewers on environments need a
public repo or a paid GitHub plan (Team/Enterprise). If you're on the free plan with a
private repo, either make it public or skip this — you can add the gate later.

Activate PR checks:

```bash
git mv ci/pending-workflows/pr-checks.yml .github/workflows/
git add .github/workflows/pr-checks.yml
git commit -m "ci: activate pr-checks workflow"
```

Push a test PR to verify the workflow passes.

### 0.9 Configure Terraform backends

Point the remaining stacks at the remote [state backend](concepts/terraform-state.md):

```bash
just tf-init shared       # connects to remote state in the storage account
just tf-init env-stage    # separate state key (stage.tfstate)
just tf-init env-prod     # separate state key (prod.tfstate)
```

**Done when:** All three `init` commands succeed.

---

## Phase 1 — Shared infrastructure

This is where costs begin. See [costs](costs.md) for the full breakdown and
[stop/start](concepts/stop-start.md) for halting resources when idle.

### 1.1 Apply shared infrastructure

```bash
just tf-plan shared       # preview
just tf-apply shared      # create (~10-15 min)
```

**What it creates:**

| Resource | Est. $/month | Details |
|----------|-------------|---------|
| [VNet](resources/vnet.md) + subnets + NSG | 0 | Network layout |
| [ACR](resources/acr.md) (Basic) | ~5 | Docker image store |
| [Key Vault](resources/key-vault.md) | <1 | Secrets store |
| [Postgres](resources/postgres.md) (B1ms) | ~17 running, ~4 stopped | Dagster state |
| [ADLS Gen2](resources/adls.md) | ~2 | Data lake storage |
| [AKS](resources/aks.md) (1× B2ms) | ~60 running, ~25 stopped | Kubernetes cluster |

Capture outputs:

```bash
just collect-tf shared    # writes ACR_NAME, PG_FQDN, KV_NAME, etc. to .env
```

### 1.2 Verify connectivity

```bash
az aks get-credentials --resource-group rg-dagster-shared --name aks-dagster
kubectl get nodes                    # should show one node, status "Ready"
```

Store the Postgres admin password in [Key Vault](resources/key-vault.md):

```bash
az keyvault secret set \
  --vault-name "$(just show-env | grep KV_NAME | cut -d= -f2 | tr -d '"')" \
  --name pg-admin-password \
  --value '<your-password>'
```

### 1.3 Test stop/start

```bash
just stop          # stops AKS + Postgres (~2-3 min)
just start         # restarts (~3-5 min)
kubectl get nodes  # verify Ready
```

See [stop/start](concepts/stop-start.md) for gotchas.

**Done when:** `kubectl get nodes` shows Ready and stop/start round-trips.

---

## Phase 2 — Stage environment (Goal 1: Dagster talks to Databricks)

### 2.1 Apply stage

```bash
just tf-plan env-stage
just tf-apply env-stage
just collect-tf env-stage
```

Creates: [Databricks workspace](resources/databricks-workspace.md) (`dbw-dagster-stage`),
Access Connector, [managed identity](resources/managed-identity.md) (`id-dagster-stage`),
Postgres DB `dagster_stage`, K8s namespace `dagster-stage`.

### 2.2 First login to the Databricks workspace

1. `just show-env` → find `DBX_STAGE_HOST` (the workspace URL)
2. Open it in a browser, log in with your Azure credentials
3. Accept the Premium trial if prompted
4. If workspace ID wasn't captured: `just set-env DBX_STAGE_WORKSPACE_ID <id>`
   (the number after `?o=` in the workspace URL)

### 2.3 Create the Unity Catalog metastore

One-time manual step — see [Unity Catalog](concepts/unity-catalog.md) for what this is.

1. Go to [accounts.azuredatabricks.net](https://accounts.azuredatabricks.net)
2. **Catalog** → **Create metastore**
3. Fill in:
   - **Name:** `metastore-dagster-eastus2`
   - **Region:** `eastus2`
   - **ADLS Gen2 path:** `abfss://metastore@<storage-account>.dfs.core.windows.net/`
     (`<storage-account>` from `just show-env` → `STORAGE_ACCOUNT_NAME`)
   - **Access Connector resource ID:** from the Terraform output in 2.1
4. **Assign** the metastore to the stage workspace
5. `just set-env TF_VAR_metastore_id <metastore-id>`

### 2.4 Create workspace objects

```bash
just tf-plan env-stage
just tf-apply env-stage
```

Creates catalog, schemas, SQL warehouse, service principal, secrets in Key Vault, IP access
list — see [Databricks workspace](resources/databricks-workspace.md) for the full list.

### 2.5 Build and push the Dagster image

```bash
az acr build \
  --registry "$(just show-env | grep ACR_NAME | cut -d= -f2 | tr -d '"')" \
  --image poc:latest \
  dagster/
```

Builds the Docker image in the cloud via [ACR](resources/acr.md) — no local Docker needed.

### 2.6 Deploy Dagster via Helm

```bash
just helm-upgrade stage
```

Deploys Dagster into `dagster-stage`. See [Helm deployments](concepts/helm-deployments.md)
for what gets created and how values are layered.

### 2.7 Smoke test

```bash
just port-forward stage    # Dagster UI at http://localhost:3000
```

In the UI: find `databricks_whoami`, click **Materialize**. It should succeed and show
`sp-dagster-stage` in its metadata.

**Done when:** `databricks_whoami` materializes.
**→ Goal 1: Dagster on AKS talks to Databricks.**

---

## Phase 3 — The two assets (Goal 2: end-to-end pipeline)

### 3.1 Pick a source API

Choose a public JSON API (free, ideally keyless). If keyed, store in
[Key Vault](resources/key-vault.md):

```bash
az keyvault secret set \
  --vault-name "$(just show-env | grep KV_NAME | cut -d= -f2 | tr -d '"')" \
  --name source-api-key --value '<key>'
```

### 3.2 Deploy the Databricks bundle

```bash
just bundle-validate stage    # check config
just bundle-deploy stage      # deploy pipeline
just collect-bundle stage     # capture pipeline ID
```

See [Databricks CLI](tools/databricks-cli.md) for bundle structure. The pipeline writes
raw data to `stage.bronze.<source>` — see [Unity Catalog](concepts/unity-catalog.md).

### 3.3–3.5 Build assets and dbt model

```bash
just dbt stage debug       # verify connection
just dbt stage build       # run the model
just check-defs            # validate Dagster definitions
just test                  # run tests
```

See [dbt](tools/dbt.md) for project structure and how it integrates with Dagster.

### 3.6 Rebuild and redeploy

```bash
az acr build \
  --registry "$(just show-env | grep ACR_NAME | cut -d= -f2 | tr -d '"')" \
  --image poc:latest dagster/
just helm-upgrade stage
just port-forward stage    # materialize bronze, then silver
```

**Done when:** `select count(*) from stage.silver.silver_<model>` > 0 and Dagster shows
lineage from bronze to silver.
**→ Goal 2: end-to-end data pipeline.**

---

## Phase 4 — Prod (Goal 3: stage/prod parity)

### 4.1 Apply prod

```bash
just tf-plan env-prod
just tf-apply env-prod
just collect-tf env-prod
```

### 4.2 First login to prod workspace

Open `DBX_PROD_HOST`, log in, accept trial. In the account console, **assign the existing
metastore** to the prod workspace (don't create a new one).

### 4.3 Prod workspace objects

```bash
just tf-plan env-prod
just tf-apply env-prod
```

### 4.4 Deploy to prod

**Promote, don't rebuild** — prod gets the exact image that passed on stage.

```bash
just bundle-deploy prod
just collect-bundle prod
just helm-upgrade prod
just port-forward prod    # materialize both assets
```

**Done when:** Prod mirrors stage.
**→ Goal 3: stage/prod parity.**

---

## Phase 5 — CI/CD (Goal 4: automated promotion)

See [CI/CD](concepts/cicd.md) for the full workflow architecture.

### 5.1–5.3 Activate workflows

```bash
git mv ci/pending-workflows/deploy-stage.yml .github/workflows/
git mv ci/pending-workflows/promote-prod.yml .github/workflows/
git add .github/workflows/
git commit -m "ci: activate deploy and promote workflows"
```

### 5.4 First prod promotion

Push a trivial PR. After merge: `deploy-stage` runs automatically → `promote-prod` waits
for your approval in GitHub → Actions → **Review deployments** → **Approve and deploy**.

### 5.5 Harden

- Restrict the Entra app's RBAC to just the three resource groups + ACR + AKS
- Copy `.github/CODEOWNERS.example` to `.github/CODEOWNERS`

**Done when:** A trivial PR flows `main → stage → approval → prod`.
**→ Goal 4: automated promotion.**

---

## Day-to-day operations

### Cost control

```bash
just stop     # stop AKS + Postgres when done for the day
just start    # restart when ready to work
```

See [stop/start](concepts/stop-start.md) for gotchas and cost details.

### Useful commands

```bash
just --list              # all commands
just show-env            # current .env
just port-forward stage  # Dagster UI
just dbt stage build     # run dbt
just check-defs          # validate Dagster
just test                # run tests
just smoke-test stage    # automated end-to-end test
```

### IP changes

```bash
just setup-env           # re-detect IP
just tf-apply shared     # update firewall rules
just tf-apply env-stage  # update Databricks IP access list
```

---

## What's next

- **Phase 6 (optional):** Record actual costs in [costs.md](costs.md), review
  [corporate migration](corporate-migration.md), try workload identity federation
  (drop the SP secret).
- **Going corporate:** Every change is infra config, not application code. See
  [corporate-migration.md](corporate-migration.md).

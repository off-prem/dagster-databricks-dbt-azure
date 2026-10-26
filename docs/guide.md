# Setup guide

Step-by-step instructions to stand up the full POC from a fresh clone. Every command is
listed with what it does and what to expect.

New to Azure or Terraform? The `tools/`, `resources/`, and `concepts/` directories explain
each component in detail — this guide links to them as they come up. Start here and follow
the links when you want to understand something deeper.

**Cost:** ~$50–100/month while running; ~$35–40/month stopped. Phase 0 is free. Costs start
in Phase 1. Run `just stop` when idle (see [stop/start](concepts/stop-start.md)).

**Naming:** Resource names use the `TF_VAR_project` prefix (default `dagster`). Examples
below show the default — if you changed it in step 0.5, substitute your project name
(e.g. `rg-myproject-shared` instead of `rg-dagster-shared`).

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

Installs pinned versions of all tools into `~/.local/bin` and runs `uv sync` in `dagster/`
to set up its virtualenv (includes dbt). See [tools/](tools/) for what each tool does.
Add the bin directory to your PATH:

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

**Review project settings** — two values have defaults you may want to change **before
any `terraform apply`** (changing them later means recreating resources):

| Variable | Default | What it controls |
|----------|---------|-----------------|
| `TF_VAR_project` | `dagster` | Resource name prefix: `rg-{project}-shared`, `aks-{project}`, `dbw-{project}-stage`, etc. |
| `TF_VAR_location` | `eastus2` | Azure region for all resources |

Edit `.env` directly if you want different values:

```bash
# Example: rename everything from dagster → myproject, deploy to West US 2
sed -i 's/TF_VAR_project="dagster"/TF_VAR_project="myproject"/' .env
sed -i 's/TF_VAR_location="eastus2"/TF_VAR_location="westus2"/' .env
```

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
| 4 federated credentials | `main`, `environment:stage`, `environment:prod`, `pull_request` | Free |
| 2 role assignments | Contributor + User Access Administrator | Free |

Capture outputs:

```bash
just collect-tf bootstrap    # writes AZURE_CLIENT_ID, TF_BACKEND_* to .env
```

Verify in Azure:

```bash
# Resource group exists
az group show -n rg-dagster-tfstate --query name -o tsv

# Entra app exists
az ad app list --display-name app-dagster-github --query '[0].displayName' -o tsv

# Storage account reachable
az storage blob list --account-name "$(grep TF_BACKEND_STORAGE_ACCOUNT .env | cut -d'"' -f2)" \
  --container-name tfstate --auth-mode key -o table
```

### 0.8 Set up GitHub repository variables ✅

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

Verify: the PR check in the **Actions** tab should show a green checkmark. The log should
show `azure/login@v2` succeeding (not `AADSTS700213`).

### 0.9 Configure Terraform backends ✅

Point the remaining stacks at the remote [state backend](concepts/terraform-state.md):

```bash
just tf-init shared       # connects to remote state in the storage account
just tf-init env-stage    # separate state key (stage.tfstate)
just tf-init env-prod     # separate state key (prod.tfstate)
```

Each should print `Successfully configured the backend "azurerm"!`

Verify the state files were created in blob storage:

```bash
az storage blob list \
  --account-name "$(grep TF_BACKEND_STORAGE_ACCOUNT .env | cut -d'"' -f2)" \
  --container-name tfstate --auth-mode key -o table
```

You should see `shared.tfstate`, `stage.tfstate`, and `prod.tfstate`.

**Done when:** All three `init` commands succeed and state files appear in the container.

### 0.10 Validate code projects

```bash
just verify 0
```

The verify script checks code projects (`dbt parse`, `dagster definitions validate`).
Both must pass before moving on.

**Preview the asset graph** — `dagster dev` requires a reachable Databricks host (the dbt
adapter validates credentials at startup), so it won't work with dummy values. You'll see
the full lineage graph in Phase 2 after `just port-forward stage`.

---

## Phase 1 — Shared infrastructure

This is where costs begin. See [costs](costs.md) for the full breakdown and
[stop/start](concepts/stop-start.md) for halting resources when idle.

> **Session expired?** Azure CLI tokens expire quickly on new accounts (security defaults).
> If any command fails with `AADSTS530035`, re-authenticate:
> ```bash
> source scripts/load-env.sh
> az logout
> az login --tenant "$TF_VAR_tenant_id" --scope "https://management.azure.com/.default"
> ```

> **SKU not available?** Azure restricts which VM sizes are available per subscription
> and region. Free-trial subscriptions are especially limited — consider upgrading to
> Pay-As-You-Go (keeps your remaining credit). If Postgres B-series SKUs aren't available
> in your region, set `pg_location` to a region where they are (e.g. `centralus`). If AKS
> B-series VMs aren't available, set `aks_vm_size` to a D-series alternative (e.g.
> `Standard_D2as_v6`). These variables are in `infra/shared/variables.tf`.

### 1.1 Pre-flight check ✅

Before spending money, verify that the AKS VM size and Postgres SKU you'll
use are actually available on your subscription. `terraform plan` does not
catch SKU restrictions — you'd only find out after a multi-minute apply fails.

```bash
just verify 1    # the SKU pre-flight section runs first
```

If either SKU fails, the output tells you what to set in `.env` (e.g.
`TF_VAR_aks_vm_size`, `TF_VAR_pg_location`, `TF_VAR_pg_sku_name`).
See the "SKU not available?" callout above for details.

### 1.2 Apply shared infrastructure ✅

```bash
just tf-init shared -upgrade   # pick up new providers (time)
just tf-plan shared            # preview
just tf-apply shared           # create (~10-15 min)
```

**What it creates:**

| Resource | Est. $/month | Details |
|----------|-------------|---------|
| [VNet](resources/vnet.md) + subnets + NSG | 0 | Network layout |
| [ACR](resources/acr.md) (Basic) | ~5 | Docker image store |
| [Key Vault](resources/key-vault.md) | <1 | Secrets store |
| [Postgres](resources/postgres.md) (B2s) | ~25 running, ~6 stopped | Dagster state |
| [ADLS Gen2](resources/adls.md) | ~2 | Data lake storage |
| [AKS](resources/aks.md) (1× B2ms) | ~60 running, ~25 stopped | Kubernetes cluster |

Capture outputs:

```bash
just collect-tf shared    # writes ACR_NAME, PG_FQDN, KV_NAME, etc. to .env
```

Verify the resources exist:

```bash
# List all resources in the shared resource group
az resource list -g rg-dagster-shared -o table

# Check outputs were captured
just show-env | grep -E 'ACR_NAME|PG_FQDN|KV_NAME|STORAGE_ACCOUNT|AKS_EGRESS'
```

### 1.3 Verify connectivity ✅

```bash
az aks get-credentials --resource-group rg-dagster-shared --name aks-dagster
kubectl get nodes                    # should show one node, status "Ready"
```

The Postgres admin password was generated automatically by Terraform and stored in
Key Vault as `pg-admin-password`. You can retrieve it for debugging:

```bash
az keyvault secret show \
  --vault-name "$(just show-env | grep KV_NAME | cut -d= -f2 | tr -d '"')" \
  --name pg-admin-password --query value -o tsv
```

### 1.4 Test stop/start ✅

```bash
just stop          # stops AKS + Postgres (~2-3 min)
just start         # restarts (~3-5 min)
kubectl get nodes  # verify Ready
```

See [stop/start](concepts/stop-start.md) for gotchas.

**Done when:** `kubectl get nodes` shows Ready and stop/start round-trips.

**Verify the entire phase before proceeding:**

```bash
just verify 1
```

---

## Phase 2 — Stage environment (Goal 1: Dagster talks to Databricks)

### 2.1 Apply stage ✅

```bash
just tf-init env-stage -upgrade   # pick up new providers (azuread, databricks, time)
just tf-plan env-stage
just tf-apply env-stage
just collect-tf env-stage
```

Creates: resource group (`rg-dagster-stage`),
[Databricks workspace](resources/databricks-workspace.md) (`dbw-dagster-stage`),
Access Connector (`dbac-dagster-stage`),
[managed identity](resources/managed-identity.md) (`id-dagster-stage`) with federated
credential and Key Vault access.

Databricks objects (catalog, SP, warehouse) are **deferred to step 2.4** — they require
the metastore from step 2.3.

Verify:

```bash
# Workspace exists
az resource show --resource-group rg-dagster-stage --name dbw-dagster-stage --resource-type "Microsoft.Databricks/workspaces" --query name -o tsv

# Stage outputs captured
just show-env | grep DBX_STAGE
```

### 2.2 First login to the Databricks workspace ✅

1. `just show-env` → find `DBX_STAGE_HOST` (the workspace URL)
2. Open it in a browser, log in with your Azure credentials
3. Accept the Premium trial if prompted
4. If workspace ID wasn't captured: `just set-env DBX_STAGE_WORKSPACE_ID <id>`
   (the number after `?o=` in the workspace URL)

### 2.3 Create the Unity Catalog metastore ✅

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

### 2.4 Create workspace objects ✅

Now that the metastore is assigned, re-apply to create all Databricks objects:

```bash
just tf-plan env-stage       # should show catalog, SP, warehouse, grants, KV secrets
just tf-apply env-stage
just collect-tf env-stage    # captures SP client ID and warehouse HTTP path
```

Creates: catalog `stage`, schemas `bronze`/`silver`, managed volume `landing`,
serverless SQL warehouse, service principal (`sp-dagster-stage`), IP access list,
UC grants, and SP credentials in Key Vault.

Verify:

```bash
# Secrets landed in Key Vault
az keyvault secret list \
  --vault-name "$(just show-env | grep KV_NAME | cut -d'"' -f2)" \
  --query '[].name' -o tsv

# Should include: dbx-stage-sp-client-id, dbx-stage-sp-secret, pg-admin-password
```

### 2.5 Apply the SecretProviderClass ✅

The SecretProviderClass tells the CSI Secrets Store driver which Key Vault secrets
to sync into K8s Secrets for the Dagster pods.

1. Edit `deploy/k8s/stage/secretproviderclass.yaml` — replace the three placeholders
   with values from `just show-env`:
   - `<KV_NAME>` → KV_NAME
   - `<TF_VAR_tenant_id>` → TF_VAR_tenant_id
   - `<DAGSTER_STAGE_IDENTITY_CLIENT_ID>` → DAGSTER_STAGE_IDENTITY_CLIENT_ID

2. Create the namespace (Helm will also create it, but we need it now):

   ```bash
   kubectl create namespace dagster-stage --dry-run=client -o yaml | kubectl apply -f -
   ```

3. Apply:

   ```bash
   kubectl apply -f deploy/k8s/stage/secretproviderclass.yaml
   ```

### 2.6 Store dummy API key in Key Vault ✅

The `posts` source in `databricks/sources.yml` points to a public API that doesn't need
a key, but we store a dummy value anyway to test the full Key Vault → pod env → Pipes
extras → Databricks auth chain. If the chain breaks, you'll know before adding a real
keyed API later.

```bash
az keyvault secret set \
  --vault-name "$(just show-env | grep KV_NAME | cut -d= -f2 | tr -d '"')" \
  --name source-posts-api-key \
  --value 'dummy-test-key'
```

The SecretProviderClass mounts this as `SOURCE_POSTS_API_KEY` on the Dagster pod.
The extract asset reads it from the pod env and forwards it to Databricks via Pipes extras.
The entrypoint adds it as an `X-Api-Key` header — jsonplaceholder ignores the header, so
the extract still succeeds.

### 2.7 Authenticate the Databricks CLI ✅

The bundle deploy and `databricks workspace list` commands need CLI auth. The
deploy scripts set `DATABRICKS_AUTH_TYPE=azure-cli` so the Databricks CLI reuses
your existing `az login` session — no separate login step is needed.

Verify:

```bash
source scripts/load-env.sh && DATABRICKS_HOST="$DBX_STAGE_HOST" DATABRICKS_AUTH_TYPE=azure-cli databricks workspace list /
```

This should list workspace root contents (`/Users`, `/Shared`, etc.).

### 2.8 Deploy the Databricks bundle ✅

```bash
just bundle-validate stage    # check config
just bundle-deploy stage      # deploy extract code to workspace
```

This deploys `databricks/src/` to `/Workspace/.bundle/dagster/stage/files/`. No DLT
pipeline is created — the bundle just uploads the Python code that Dagster will submit
as serverless jobs via Pipes.

Verify the files are in the workspace:

```bash
databricks workspace ls /Workspace/.bundle/dagster/stage/files/src/extract
```

### 2.9 Build and push the Dagster image

```bash
az acr build \
  --registry "$(just show-env | grep ACR_NAME | cut -d= -f2 | tr -d '"')" \
  --image poc:latest \
  dagster/
```

Builds the Docker image in the cloud via [ACR](resources/acr.md) — no local Docker needed.

Verify the image was pushed:

```bash
az acr repository show-tags \
  --name "$(just show-env | grep ACR_NAME | cut -d'"' -f2)" \
  --repository poc -o tsv
```

### 2.10 Deploy Dagster via Helm

```bash
just helm-upgrade stage
```

Deploys Dagster into `dagster-stage`. The Helm values inject `DBX_BUNDLE_ROOT`
(computed from project name + env) and `DATABRICKS_HOST` into the pod. See
[Helm deployments](concepts/helm-deployments.md) for how values are layered.

Verify pods are running:

```bash
kubectl get pods -n dagster-stage    # all pods should be Running/Ready
```

### 2.11 Smoke test

```bash
just port-forward stage    # Dagster UI at http://localhost:3000
```

In the UI: find `raw_posts` in the asset graph, click **Materialize**. Dagster submits a
serverless job to Databricks via Pipes — the entrypoint fetches the JSONPlaceholder API
and writes NDJSON to the landing volume.

**What to check:**

- **Dagster UI:** `raw_posts` materializes successfully, metadata shows `num_records` and
  `volume_path`.
- **Databricks workspace:** In Catalog → Volumes → `stage.bronze.landing`, a `posts/`
  directory exists containing a `.json` file.
- **Auth chain:** The X-Api-Key header was sent (jsonplaceholder ignores it, but the
  code path is exercised). If the secret wasn't mounted, you'll see a blank header value
  in the Pipes extras — check the Dagster run logs.

**Done when:** `raw_posts` materializes and data appears in the landing volume.
**→ Goal 1: Dagster on AKS talks to Databricks.**

**Verify the entire phase before proceeding:**

```bash
just verify 2
```

---

## Phase 3 — dbt and end-to-end lineage (Goal 2: end-to-end pipeline)

### 3.1 Verify dbt connection ✅

`just dbt` auto-fetches `DBX_SP_SECRET` from Key Vault, so no manual export needed:

```bash
just dbt stage debug       # verify credentials and warehouse connection
```

(Inside K8s, pods get `DBX_SP_SECRET` from the SecretProviderClass automatically.)

**Gotcha — serverless SQL warehouse + ADLS firewall:** The storage account firewall
(`defaultAction: Deny`) blocks serverless compute. Resource access rules for the
access connector alone are NOT sufficient. You must create an Azure Network Security
Perimeter (NSP) with the `AzureDatabricksServerless` service tag and associate the
storage account in Learning/Transition mode. This is done in `infra/shared/main.tf`.

**Gotcha — dbt-databricks auth fields:** The adapter warns to use `azure_client_id`/
`azure_client_secret`, but the [official Microsoft docs](https://learn.microsoft.com/en-us/azure/databricks/integrations/configure-oauth-dbt)
show `client_id`/`client_secret` with `auth_type: oauth` for Databricks OAuth M2M.
Both work; we use `client_id`/`client_secret` per the docs. The warning is cosmetic.

### 3.2 Build the silver model ✅

```bash
just dbt stage build       # builds bronze table + silver table
```

This runs two dbt models:

- **`bronze/posts`** — `read_files()` from the landing volume (JSON files written by `raw_posts`).
- **`silver/silver_source`** — selects from the bronze table with column renames.

Verify the data landed:

```bash
# From the Databricks SQL editor or CLI:
# SELECT count(*) FROM stage.silver.silver_source
# Should return > 0 rows
```

### 3.3 End-to-end lineage ✅

```bash
just port-forward stage    # Dagster UI at http://localhost:3000
```

In the UI: select both `raw_posts` and the dbt assets, click **Materialize all**. Dagster
shows the full lineage graph: `raw_posts` → `posts` (bronze) → `silver_source`.

**Done when:** `SELECT count(*) FROM stage.silver.silver_source` > 0 and Dagster shows
the full lineage from raw to silver.
**→ Goal 2: end-to-end data pipeline.**

**Verify the entire phase before proceeding:**

```bash
just verify 3
```

---

## Phase 4 — Prod (Goal 3: stage/prod parity)

### 4.1 Apply prod ✅

```bash
just tf-init env-prod -upgrade    # pick up providers if not already done
just tf-plan env-prod
just tf-apply env-prod            # Databricks workspace-level resources will fail — expected
just collect-tf env-prod
```

The apply creates Azure resources (RG, workspace, identity, KV secrets) but Databricks
workspace-level resources (catalog, schemas, warehouse) fail because you haven't logged
into the new workspace yet. That's normal — they're created in step 4.3 after the login.

Verify:

```bash
az resource show --resource-group rg-dagster-prod --name dbw-dagster-prod --resource-type "Microsoft.Databricks/workspaces" --query name -o tsv
just show-env | grep DBX_PROD
```

### 4.2 First login to prod workspace ✅

Open `DBX_PROD_HOST`, log in, accept trial. If the workspace is in the same region as
your existing metastore, Databricks auto-assigns it — verify in the account console under
**Catalog → Metastore → Workspaces** that `dbw-dagster-prod` appears. If not, assign it
manually (don't create a new metastore).

### 4.3 Prod workspace objects ✅

```bash
just tf-plan env-prod      # should show catalog, SP, warehouse, etc.
just tf-apply env-prod
just collect-tf env-prod   # captures SP client ID and warehouse HTTP path
```

### 4.4 Apply prod SecretProviderClass ✅

Same as step 2.5, but for prod. The template uses `${VAR}` placeholders resolved
via envsubst from `.env`:

```bash
source scripts/load-env.sh
kubectl create namespace dagster-prod --dry-run=client -o yaml | kubectl apply -f -
envsubst < deploy/k8s/prod/secretproviderclass.yaml | kubectl apply -f -
```

### 4.5 Store dummy API key for prod ✅

```bash
az keyvault secret set \
  --vault-name "$(just show-env | grep KV_NAME | cut -d= -f2 | tr -d '"')" \
  --name source-posts-api-key \
  --value 'dummy-test-key'
```

(This secret is shared across envs; if you already set it in Phase 2, skip this.)

### 4.6 Deploy to prod ✅

**Promote, don't rebuild** — prod gets the exact image that passed on stage.

```bash
just bundle-deploy prod     # deploy extract code to prod workspace (uses az login)
just helm-upgrade prod      # deploy Dagster with prod env vars
```

Verify:

```bash
kubectl get pods -n dagster-prod    # all pods Running/Ready
just port-forward prod              # materialize raw_posts, then dbt assets
```

**Done when:** Prod mirrors stage.
**→ Goal 3: stage/prod parity.**

**Verify the entire phase before proceeding:**

```bash
just verify 4
```

---

## Phase 5 — CI/CD (Goal 4: automated promotion)

See [CI/CD](concepts/cicd.md) for the full workflow architecture.

### 5.1 Sync GitHub variables and environments ✅

The workflows read configuration from **GitHub repository variables** (not secrets — these
are non-sensitive IDs and URLs). `scripts/setup-ci.sh` reads your `.env` and pushes
everything CI needs in one shot. It also creates the `stage` and `prod` GitHub environments,
with you as the required reviewer for `prod`.

```bash
just setup-ci --dry-run   # preview what will be set
just setup-ci             # sync .env → GitHub variables + create environments
```

Re-run any time after a terraform apply adds new values to `.env`.

**Verify:** `gh variable list` should show ~18 variables. Settings → Environments should
show `stage` and `prod` (with your username under required reviewers for `prod`).

### 5.2–5.3 Activate workflows ✅

Workflow skeletons replaced with full implementations and moved to `.github/workflows/`:

- **pr-checks.yml** — terraform fmt/validate, bundle validate, dbt parse, dg check defs,
  pytest, docker build (no push)
- **deploy-stage.yml** — `az acr build` → helm upgrade (stage) → bundle deploy (stage) →
  smoke test
- **promote-prod.yml** — same image SHA → helm upgrade (prod) → bundle deploy (prod) →
  smoke test; requires `environment: prod` approval

All workflows authenticate via OIDC (`azure/login@v2`) using GitHub repository variables.
Scripts get a stub `.env` (`touch .env`) so `load-env.sh` doesn't fail when vars come from
the CI environment.

### 5.4 First prod promotion

Push a trivial PR. After merge: `deploy-stage` runs automatically → `promote-prod` waits
for your approval in GitHub → Actions → **Review deployments** → **Approve and deploy**.

### 5.5 Harden

- Restrict the Entra app's RBAC to just the three resource groups + ACR + AKS
- Copy `.github/CODEOWNERS.example` to `.github/CODEOWNERS`

**Done when:** A trivial PR flows `main → stage → approval → prod`.
**→ Goal 4: automated promotion.**

**Verify the entire phase:**

```bash
just verify 5
```

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

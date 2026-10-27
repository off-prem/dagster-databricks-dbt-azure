# Adapting this repo

This repo is a **blueprint**, not a library. There are two ways to use it:

## Path 1: Fork

Clone or fork the repo and follow `docs/guide.md` from Phase 0. You get the entire
stack — Terraform, Dagster, dbt, Databricks bundles, CI/CD — wired together and working.
Customize names, regions, and sources as you go.

**Best when:** starting from scratch with no existing infrastructure or data platform.

## Path 2: Adopt into an existing repo

Pull specific components from this repo into your team's existing codebase. Use Claude
(with access to both repos) to generate a tailored adoption plan.

**Best when:** you already have a mono-repo, existing Databricks workspaces, an
orchestrator, or corporate infrastructure constraints.

### How to generate an adoption plan

Open Claude Code in your target repo and give it access to this POC repo (clone it
alongside, or point Claude at it). Then ask:

> Read the POC repo at `<path>`, especially `docs/adapt.md`, and help me create an
> adoption plan for bringing pieces of it into this repo.

Claude will ask the intake questions below, compare both repos, and produce a plan
that maps POC components to your existing structure — what to copy, what to adapt, and
what to skip.

See [adoption-plan-example.md](adoption-plan-example.md) for a real example: a team
with 30+ people migrating off Synapse/ADF into an existing mono-repo with shared
Databricks workspaces.

---

## Intake questions

Claude: ask these when someone wants to adapt this repo. Use the answers to generate a
tailored adoption plan. Don't ask all at once — group them conversationally.

### Team and organization

1. **Team composition.** How many DevOps / platform engineers, data engineers, and data
   scientists? Is there a dedicated platform team separate from data engineering?
2. **Ownership boundaries.** Who owns Databricks workspace provisioning? Azure
   infrastructure? CI/CD pipelines? Is there a central platform team, or does each
   domain team own their slice?

### Existing infrastructure

3. **Azure subscription.** Corporate or personal? Any Azure Policy restrictions (deny
   public endpoints, required tags, allowed SKUs, required regions)?
4. **Networking.** Is there an existing VNet you must attach to? VPN/ExpressRoute?
   Private endpoint requirements?
5. **Databricks.** Do workspaces and a Unity Catalog metastore already exist? Who owns
   them? Serverless allowed, or must you use classic compute?
6. **Kubernetes.** Existing AKS cluster(s), or new? Shared with other workloads?
7. **Secrets management.** Existing Key Vault? Other secrets manager?
8. **CI/CD system.** GitHub Actions, Azure DevOps, Jenkins, other? Self-hosted runners
   available?

### Existing codebase

9. **Repo structure.** Mono-repo or multi-repo? Where does infrastructure code live
   relative to application code?
10. **Orchestrator.** Already using Dagster, Airflow, ADF, or starting fresh? If
    migrating, what are you migrating from?
11. **dbt.** Existing dbt project? Which adapter (Databricks, Synapse, other)?
12. **Databricks code.** Existing notebooks, jobs, or bundles? How are they deployed
    today?

### Requirements

13. **Environments.** How many? (dev/stage/prod, or just stage/prod?) Do developers
    need personal environments?
14. **Data in stage.** Does stage need real production data? Subset? Synthetic? What
    are the PII/compliance constraints?
15. **Timeline.** Aggressive (weeks), realistic (months), or thorough (quarters)?
16. **What's driving this?** Migration off a legacy system? New platform build?
    Compliance deadline? Cost reduction?

---

## Component map

Each component can be adopted independently. The table shows what it needs and what
it provides to other components.

### Infrastructure (`infra/`)

| Component | What it provisions | Requires | Can skip if |
|-----------|--------------------|----------|-------------|
| `bootstrap/` | Terraform state storage, Entra app + OIDC federation | Azure subscription, Entra ID | You have existing state storage and CI identity |
| `shared/` | VNet, AKS, Postgres, Key Vault, ACR, ADLS, NSP | `bootstrap/` outputs | You have existing AKS, Postgres, etc. — adapt the Terraform or skip it |
| `env/` | Databricks workspace, access connector, managed identity, UC objects | `shared/` outputs, UC metastore | Another team provisions workspaces; adopt only the UC object definitions (catalogs, schemas, grants) |

**Adoption notes:**
- If your org has existing Terraform modules for AKS/networking, use them. Copy the
  Databricks-specific resources (`infra/env/databricks.tf`) into your modules.
- If another team owns workspace provisioning, you likely only need `infra/env/`'s
  Databricks provider resources (catalogs, schemas, grants, volumes, service principals).
- The VNet layout (`snet-aks`, `snet-pe`, `snet-dbx-*`) is designed for the corporate
  migration path. Keep it even if you don't need private endpoints yet.

### Dagster (`dagster/`, `deploy/helm/`)

| Component | What it does | Requires | Can skip if |
|-----------|-------------|----------|-------------|
| `dagster/src/poc/` | Code location: asset definitions, dbt integration, Pipes extract | Databricks workspace, dbt project, bundle deployed | You write your own assets from scratch (but study the patterns) |
| `deploy/helm/values.*.yaml` | Helm chart configuration: resources, env vars, secrets, workload identity | AKS cluster, Key Vault, managed identity, Postgres | You already have a Dagster deployment (but study the run pod config) |
| `deploy/k8s/` | SecretProviderClass manifests | Key Vault, Secrets Store CSI driver | You have an existing secrets flow |

**Adoption notes:**
- The Helm values are the hardest part to get right. The POC documents every field.
  Study `values.base.yaml` comments and [Helm deployments](concepts/helm-deployments.md).
- Run pods do NOT inherit env/volumes/labels from user deployments. This is the #1
  gotcha. See [Decision #17](decisions.md).
- The asset factory pattern (`sources.yml` → generated assets) is optional. You can
  write assets by hand. But it scales well for 50+ sources.

### dbt (`dbt/`)

| Component | What it does | Requires | Can skip if |
|-----------|-------------|----------|-------------|
| `dbt/profiles.yml` | Connection config via env vars | SQL warehouse, SP credentials | You have an existing dbt project (but adopt the env var pattern) |
| `dbt/models/` | Bronze/silver models | Landing volume with data | You write your own models |
| `dbt/macros/generate_schema_name.sql` | Schema routing (model goes to its declared schema) | — | Your project already handles this |

**Adoption notes:**
- The key pattern is `profiles.yml` reading everything from env vars. Copy this approach
  even if you don't copy the models.
- `dagster-dbt` integration lives in `dagster/src/poc/assets/dbt.py`. It's ~15 lines.

### Databricks Asset Bundle (`databricks/`)

| Component | What it does | Requires | Can skip if |
|-----------|-------------|----------|-------------|
| `databricks.yml` | Bundle config: targets, permissions, variables | Databricks workspace, CI SP | You don't use Pipes or have your own bundle |
| `src/extract/` | Notebook + helpers for API ingestion via Pipes | Landing volume, Dagster Pipes | Your extraction pattern is different |

**Adoption notes:**
- The bundle ships files only (no pipeline or job resources). Dagster submits the
  notebook via Pipes.
- The custom `_SdkContextLoader`/`_SdkMessageWriter` work around Azure serverless
  lacking FUSE. You'll need these on Azure. See [Dagster Pipes](concepts/dagster-pipes.md#gotchas).

### CI/CD (`.github/workflows/`, `scripts/`)

| Component | What it does | Requires | Can skip if |
|-----------|-------------|----------|-------------|
| `pr-checks.yml` | Validate on PR: fmt, lint, parse, check defs, test, docker build | GitHub Actions | You use Azure DevOps (translate the steps) |
| `deploy-stage.yml` | Build + deploy to stage on merge | ARC runners, AKS, ACR, Databricks | You have existing CD pipelines (but study the deploy sequence) |
| `promote-prod.yml` | Same image → prod with approval gate | `deploy-stage` succeeded | Same |
| `scripts/helm-upgrade.sh` | Helm deploy with envsubst | `.env` or CI env vars | You have an existing deploy script |
| `scripts/bundle-deploy.sh` | Bundle deploy + grant CAN_RUN | Databricks workspace | Same |
| `scripts/setup-arc.sh` | Install ARC runners on AKS | AKS, GitHub App | You use hosted runners or ADO agents |

**Adoption notes:**
- The deploy sequence matters: image build → Helm upgrade → bundle deploy → smoke test.
  Copy this order even if you rewrite the scripts.
- ARC runners solve the "CI can't reach AKS/Databricks" problem. If your CI already
  runs inside the network, you don't need ARC.
- `scripts/setup-env.sh` and `scripts/load-env.sh` handle the `.env` ↔ CI environment
  variable bridge. This pattern is worth adopting regardless.

### Phase runners and scripts (`scripts/`)

| Component | What it does | Adopt if |
|-----------|-------------|----------|
| `scripts/phases/phase-*.sh` | Guided, self-verifying setup (one command per phase) | You want the `just phase N` experience for your adopters |
| `scripts/lib/common.sh` | Shared library: colored output, `tf_plan_confirm_apply`, `wait_for_manual`, provider registration, phase summary | You adopt the phase runners, or want the patterns for your own scripts |
| `justfile` | Task runner with dotenv-load, phase commands, dbt/Helm/bundle wrappers | You want a single entry point for all commands |
| `setup-env.sh` / `load-env.sh` | `.env` scaffolding, Terraform output collection, interactive project naming | You need the `.env` ↔ CI variable bridge |
| `helm-upgrade.sh` | Helm deploy with envsubst | You deploy Dagster via Helm |
| `bundle-deploy.sh` | Bundle deploy + permission grants | You use Databricks Asset Bundles |
| `smoke-test.sh` | Post-deploy validation via Dagster GraphQL | You want automated post-deploy checks |
| `stop.sh` / `start.sh` / `teardown.sh` / `standup.sh` | Cost control: pause, teardown, rebuild | You want cost control scripts |
| `setup-ci.sh` | Sync local `.env` to GitHub repo variables + create environments | You use GitHub Actions CI |
| `setup-arc.sh` | Install ARC self-hosted runners on AKS | You need self-hosted runners inside AKS |
| `verify.sh` | Read-only phase verification (check a phase is healthy) | You follow the phased setup guide |

**Adoption notes:**
- The phase runner pattern (`just phase N`) is the primary setup experience. If you adopt
  the infra and deploy patterns, consider adopting the phase runners too — they eliminate
  manual errors and make setup reproducible.
- `lib/common.sh` contains reusable functions (`tf_plan_confirm_apply`, `wait_for_manual`,
  colored output) that work independently of the phase runners. You can source it from
  your own scripts.
- The `justfile` loads `.env` automatically. If you already use `make` or another task
  runner, translate the recipes rather than running both.

---

## Instructions for Claude

When generating an adoption plan from these intake answers:

1. **Read both repos.** Understand the target repo's existing structure, tooling, and
   conventions before proposing changes.
2. **Map components.** For each component in the table above, determine: adopt as-is,
   adapt, or skip. Explain why.
3. **Identify conflicts.** Where the POC's patterns conflict with the existing repo
   (different Terraform structure, different CI system, existing Helm charts), call it
   out and recommend a resolution.
4. **Respect existing ownership.** If another team owns infrastructure or Databricks
   workspaces, the plan should work within those boundaries — not propose taking them over.
5. **Produce a phased plan** with parallel tracks where possible. The phases should be:
   - Decisions and security review (serial — blocks everything)
   - Platform build (parallel tracks by component)
   - Migration / integration (parallel — teams work independently)
   - Steady state
6. **Include a team ownership map** assigning areas to roles based on the team composition.
7. **Address the stage data question** using the options from the POC's adoption plan example.
8. **List open questions** — things you couldn't determine from the two repos alone.
9. **Save the plan** as `docs/adoption-plan.md` in the target repo (not this one).

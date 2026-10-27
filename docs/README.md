# System overview

Dagster OSS on AKS orchestrates Azure Databricks. A serverless notebook task (submitted
via Dagster Pipes) ingests an API into a Unity Catalog landing volume; dbt models build
bronze and silver tables from it. Two environments (stage, prod) share infrastructure
but isolate data by catalog. CI promotes merged PRs through stage → approval gate → prod.

Nothing is exposed via public ingress. All control planes are Entra-gated and IP-restricted.
Every environment-specific value comes from configuration, never from code.

## Architecture

```
┌──────────────┐      ┌──────────────────────────────────────────────┐
│ GitHub       │      │ AKS cluster                                 │
│  Actions     │──────│  dagster-stage (webserver, daemon, code svr) │
│  (OIDC)      │      │  dagster-prod  (webserver, daemon, code svr) │
│              │      │  arc-runners   (CI deploy pods)              │
└──────────────┘      └─────────┬──────────────────┬─────────────────┘
                                │                  │
                    ┌───────────▼──┐    ┌──────────▼──────────┐
                    │ Key Vault    │    │ Postgres Flexible   │
                    │ (SP secrets) │    │ (dagster_stage/prod)│
                    └──────────────┘    └─────────────────────┘
                                │
              ┌─────────────────▼─────────────────┐
              │ Databricks (per env)              │
              │  Workspace → Serverless notebook  │
              │  SQL warehouse ← dbt              │
              │  Unity Catalog (stage/prod)       │
              └─────────────────┬─────────────────┘
                                │
                    ┌───────────▼──────────┐
                    │ ADLS Gen2            │
                    │ (metastore + tables) │
                    └──────────────────────┘
```

See [architecture.md](architecture.md) for the full Mermaid diagram, identity flow, and
parametrization contract.

## Data flow (per environment)

1. **Extract** — Dagster materializes `raw_<source>`. Pipes submits a serverless notebook to
   Databricks; the notebook calls the source API and writes JSON to the landing volume.
2. **Bronze** — dbt reads the landing files into `<catalog>.bronze.<source>`.
3. **Silver** — dbt transforms bronze into `<catalog>.silver.<source>`.

dbt runs inside the Dagster run pod against a serverless SQL warehouse.

## Documentation map

### Getting started

| Doc | Purpose |
|-----|---------|
| [guide.md](guide.md) | Setup reference: what each phase creates, decisions, troubleshooting |
| [operations.md](operations.md) | Day-to-day: commands, cost control, IP changes, deploying |
| [architecture.md](architecture.md) | System diagram, data flow, identity flow |
| [costs.md](costs.md) | Resource inventory, monthly cost breakdown, scope boundary |

### Design & conventions

| Doc | Purpose |
|-----|---------|
| [decisions.md](decisions.md) | Settled choices (ADR-lite) — don't re-litigate |
| [conventions.md](conventions.md) | Naming, tagging, Terraform/Helm/dbt/git patterns |
| [corporate-migration.md](corporate-migration.md) | What changes in a corporate network |
| [improvements.md](improvements.md) | TODO tracker: security, performance, scaling, monitoring |

### Adopting this repo

| Doc | Purpose |
|-----|---------|
| [adapt.md](adapt.md) | Component map, intake questions, and Claude instructions for adopting into an existing repo |
| [adoption-plan-example.md](adoption-plan-example.md) | Example adoption plan (Synapse/ADF migration, 30+ person team) |

### Reference pages

Every tool, resource, and concept has a one-page reference using the same
[template](#doc-template).

#### Tools

The CLIs and systems used to build and operate the platform.

| Tool | Role |
|------|------|
| [Terraform](tools/terraform.md) | Provision Azure + Databricks infrastructure |
| [Helm](tools/helm.md) | Deploy Dagster to AKS |
| [Azure CLI](tools/azure-cli.md) | Identity, image builds, stop/start |
| [Databricks CLI](tools/databricks-cli.md) | Deploy asset bundles |
| [Databricks Asset Bundles](tools/databricks-asset-bundles.md) | Package workspace code |
| [kubectl](tools/kubectl.md) | Inspect and debug the cluster |
| [kubelogin](tools/kubelogin.md) | Entra tokens for kubectl |
| [Dagster](tools/dagster.md) | The orchestrator |
| [dbt](tools/dbt.md) | SQL transformations (bronze → silver) |
| [Docker](tools/docker.md) | Build the code-location image |
| [uv](tools/uv.md) | Python dependency management |
| [just](tools/just.md) | Task runner, loads `.env` |
| [GitHub Actions](tools/github-actions.md) | CI/CD workflows |
| [ARC](tools/arc.md) | Self-hosted runners inside AKS |
| [GitHub CLI](tools/github-cli.md) | Repo variables and environments |
| [Secrets Store CSI driver](tools/secrets-store-csi-driver.md) | Mount Key Vault secrets in pods |
| [jq](tools/jq.md) | JSON processing in scripts |
| [Project scripts](tools/project-scripts.md) | Every script in `scripts/` |

#### Azure resources

| Resource | Role |
|----------|------|
| [Azure subscription](resources/azure-subscription.md) | The account and directory |
| [Resource groups](resources/resource-groups.md) | Grouping and cost boundaries |
| [Azure resource providers](resources/azure-resource-providers.md) | One-time service registration |
| [VNet](resources/vnet.md) | Network layout (AKS, private endpoints, Databricks subnets) |
| [AKS](resources/aks.md) | Kubernetes cluster hosting Dagster |
| [AKS egress IP](resources/aks-egress-ip.md) | Outbound address used in allow-lists |
| [ACR](resources/acr.md) | Container image registry |
| [Key Vault](resources/key-vault.md) | Secrets storage |
| [Managed identity](resources/managed-identity.md) | Pod-to-Azure identity (workload identity) |
| [Postgres](resources/postgres.md) | Dagster run/event storage |
| [ADLS](resources/adls.md) | Unity Catalog table storage |
| [Network security perimeter](resources/network-security-perimeter.md) | Storage access for serverless |
| [Entra app](resources/entra-app.md) | CI service principal (OIDC) |
| [Terraform state storage](resources/tfstate-storage.md) | Remote state backend |

#### Kubernetes resources

| Resource | Role |
|----------|------|
| [Kubernetes namespaces](resources/kubernetes-namespaces.md) | `dagster-stage`, `dagster-prod`, runners |
| [Helm releases](resources/helm-releases.md) | Dagster and ARC chart installs |
| [SecretProviderClass](resources/secret-provider-class.md) | Key Vault → K8s secret mapping |
| [Kubernetes secrets](resources/kubernetes-secrets.md) | Secrets the pods consume |

#### Databricks resources

| Resource | Role |
|----------|------|
| [Databricks workspace](resources/databricks-workspace.md) | Compute and catalog host (per env) |
| [Unity Catalog metastore](resources/unity-catalog-metastore.md) | Account-level governance root |
| [Catalog and schemas](resources/databricks-catalog.md) | `stage`/`prod` catalogs, `bronze`/`silver` schemas |
| [Landing volume](resources/databricks-landing-volume.md) | Raw files and Pipes transport |
| [Storage credential](resources/databricks-storage-credential.md) | Catalog-to-ADLS path |
| [Access connector](resources/databricks-access-connector.md) | Workspace-to-storage identity |
| [SQL warehouse](resources/databricks-sql-warehouse.md) | dbt's SQL endpoint |
| [Service principal](resources/databricks-service-principal.md) | Dagster's Databricks identity |
| [Grants](resources/databricks-grants.md) | Least-privilege UC access |
| [IP access lists](resources/databricks-ip-access-list.md) | Workspace allow-list |
| [CI principal](resources/databricks-ci-principal.md) | OIDC app inside each workspace |

#### GitHub resources

| Resource | Role |
|----------|------|
| [GitHub repository](resources/github-repository.md) | Source repo and OIDC subject |
| [GitHub App](resources/github-app.md) | ARC's identity toward GitHub |
| [GitHub environments](resources/github-environments.md) | `stage`/`prod` gates and variables |

#### Concepts

How the pieces fit together.

| Concept | What it explains |
|---------|-----------------|
| [Environment parametrization](concepts/environment-parametrization.md) | No hardcoded env or personal values |
| [Resource naming](concepts/resource-naming.md) | `<type>-<project>-<env>` pattern |
| [Repo config files](concepts/repo-config-files.md) | `.tool-versions`, `.env.example`, ignores |
| [OIDC](concepts/oidc.md) | CI to Azure without secrets |
| [Workload identity](concepts/workload-identity.md) | Pods to Azure without secrets |
| [Azure RBAC](concepts/azure-rbac.md) | Who has which role where |
| [Secrets flow](concepts/secrets-flow.md) | Key Vault → CSI → pod env vars |
| [Network access](concepts/network-access.md) | Public-but-gated posture |
| [Terraform state](concepts/terraform-state.md) | How Terraform remembers |
| [Helm deployments](concepts/helm-deployments.md) | The Dagster deploy flow |
| [CI/CD](concepts/cicd.md) | Validate → deploy stage → promote prod |
| [Stop / start](concepts/stop-start.md) | Three levels of cost control |
| [Unity Catalog](concepts/unity-catalog.md) | Metastore → catalog → schema hierarchy |
| [Medallion architecture](concepts/medallion-architecture.md) | Bronze and silver data layers |
| [Dagster Pipes](concepts/dagster-pipes.md) | Running Databricks jobs from Dagster |
| [Asset factory](concepts/asset-factory.md) | `sources.yml` drives asset creation |

## Repo layout

```
infra/          Terraform — bootstrap/, shared/, env/, modules/
dagster/        Dagster code location + Docker image
databricks/     Databricks Asset Bundle (extract notebook + sources.yml)
dbt/            dbt project (landing files → bronze → silver)
deploy/         Helm values (base + per env) + K8s manifests
scripts/        Setup, deploy, verify, start/stop helpers
.github/        CI workflows (pr-checks, deploy-stage, promote-prod)
docs/           All documentation (this directory)
```

## Key operational commands

```bash
just stop / just start           # pause/resume AKS + Postgres
just teardown / just standup     # delete/recreate AKS (lower idle cost)
just port-forward stage          # Dagster UI at localhost:3000
just smoke-test stage            # end-to-end validation
just verify <phase>              # check a phase is complete (0–5)
```

See the [root README](../README.md) for the full command table.

---

## Doc template

Every tool, resource, and concept page follows this structure:

```markdown
# Name

> **Type:** Tool | Resource | Concept · **Scope:** ... · **Pinned / Name / Where:** ...

One short paragraph: what it is.

## Why we use it
## How it's used here
## Key commands & files
## Gotchas
## Cost
## Managed by
## Related docs
```

Granularity: one page per thing you can name, provision or configure by hand; Terraform
sub-resources (role assignments, federated credentials, firewall rules, database names)
are documented in their parent's page.

Rules: keep the section names and order exactly; write "Free." under Cost when it is free;
state versions and names from the code, not from memory; link related pages with relative
paths. A new tool, resource or concept gets a page here and a row in the tables above.

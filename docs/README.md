# Reference docs

Start with [guide.md](guide.md) for setup. This directory also holds one reference page for every
**tool**, **resource** and **concept** in the repo. All of them use the same template, so you
can jump to the section you need.

## Template

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

Granularity: one page per thing you can name, provision or configure by hand; Terraform sub-resources
(role assignments, federated credentials, firewall rules, database names) are documented in their parent's page.

Rules: keep the section names and order exactly; write "Free." under Cost when it is free;
state versions and names from the code, not from memory; link related pages with relative paths.
A new tool, resource or concept gets a page here and a row below.

## Tools (`tools/`)

| Page | One-liner |
|------|-----------|
| [Azure CLI](tools/azure-cli.md) | Identity, image builds, stop/start |
| [kubelogin](tools/kubelogin.md) | Entra tokens for kubectl |
| [kubectl](tools/kubectl.md) | Inspect the cluster |
| [Helm](tools/helm.md) | Deploy Dagster |
| [Secrets Store CSI driver](tools/secrets-store-csi-driver.md) | Mount Key Vault secrets in pods |
| [Terraform](tools/terraform.md) | Azure and Databricks infrastructure |
| [Databricks CLI](tools/databricks-cli.md) | Deploy bundles |
| [Databricks Asset Bundles](tools/databricks-asset-bundles.md) | Workspace code packaging |
| [Dagster](tools/dagster.md) | The orchestrator |
| [dbt](tools/dbt.md) | SQL transformations |
| [Docker](tools/docker.md) | The code-location image |
| [uv](tools/uv.md) | Python dependencies |
| [just](tools/just.md) | Task runner, loads `.env` |
| [jq](tools/jq.md) | JSON in shell scripts |
| [GitHub Actions](tools/github-actions.md) | Workflows |
| [ARC](tools/arc.md) | Self-hosted runners in AKS |
| [GitHub CLI](tools/github-cli.md) | Repo variables and environments |
| [Project scripts](tools/project-scripts.md) | Every script in `scripts/` |

## Resources (`resources/`)

| Page | One-liner |
|------|-----------|
| [Resource groups](resources/resource-groups.md) | Grouping and cost boundaries |
| [Azure subscription and tenant](resources/azure-subscription.md) | The account and directory (manual) |
| [Azure resource providers](resources/azure-resource-providers.md) | One-time service registration (manual) |
| [GitHub repository](resources/github-repository.md) | Your fork; the OIDC subject |
| [GitHub App](resources/github-app.md) | ARC's identity toward GitHub (manual) |
| [Terraform state storage](resources/tfstate-storage.md) | Remote state |
| [Entra app](resources/entra-app.md) | CI identity |
| [GitHub environments](resources/github-environments.md) | `stage`/`prod` gates and variables |
| [VNet](resources/vnet.md) | Network layout |
| [AKS](resources/aks.md) | Kubernetes cluster |
| [AKS egress IP](resources/aks-egress-ip.md) | Outbound address used in allow-lists |
| [Kubernetes namespaces](resources/kubernetes-namespaces.md) | Env and runner partitions |
| [Helm releases](resources/helm-releases.md) | Dagster and ARC installs |
| [SecretProviderClass](resources/secret-provider-class.md) | Key Vault to secret mapping |
| [Kubernetes secrets](resources/kubernetes-secrets.md) | Secrets the pods consume |
| [ACR](resources/acr.md) | Image registry |
| [Key Vault](resources/key-vault.md) | Secrets |
| [Managed identity](resources/managed-identity.md) | Pod identity |
| [Postgres](resources/postgres.md) | Dagster state |
| [ADLS](resources/adls.md) | Table storage |
| [Network security perimeter](resources/network-security-perimeter.md) | Storage access for serverless |
| [Databricks workspace](resources/databricks-workspace.md) | Compute and catalog host |
| [Unity Catalog metastore](resources/unity-catalog-metastore.md) | Account-level root (manual) |
| [Storage credential and external location](resources/databricks-storage-credential.md) | Catalog-to-ADLS path |
| [Catalog and schemas](resources/databricks-catalog.md) | `stage`/`prod`, `bronze`, `silver` |
| [Landing volume](resources/databricks-landing-volume.md) | Raw files and Pipes transport |
| [Grants](resources/databricks-grants.md) | Least-privilege access |
| [IP access lists](resources/databricks-ip-access-list.md) | Workspace allow-list |
| [CI principal](resources/databricks-ci-principal.md) | OIDC app inside each workspace (manual) |
| [Databricks access connector](resources/databricks-access-connector.md) | Workspace-to-storage identity |
| [Databricks SQL warehouse](resources/databricks-sql-warehouse.md) | dbt's SQL endpoint |
| [Databricks service principal](resources/databricks-service-principal.md) | Dagster's Databricks identity |

## Concepts (`concepts/`)

| Page | One-liner |
|------|-----------|
| [Environment parametrization](concepts/environment-parametrization.md) | No hardcoded env or personal values |
| [Resource naming](concepts/resource-naming.md) | `project`, `env`, random suffix |
| [Repo config files](concepts/repo-config-files.md) | Pins, ignores, examples |
| [Terraform state](concepts/terraform-state.md) | How Terraform remembers |
| [Azure RBAC](concepts/azure-rbac.md) | Who has which role where |
| [OIDC](concepts/oidc.md) | CI to Azure without secrets |
| [Workload identity](concepts/workload-identity.md) | Pods to Azure without secrets |
| [Secrets flow](concepts/secrets-flow.md) | Key Vault to code |
| [Network access](concepts/network-access.md) | Public-but-gated posture |
| [Helm deployments](concepts/helm-deployments.md) | The deploy flow |
| [CI/CD](concepts/cicd.md) | Validate, deploy, promote |
| [Stop / start](concepts/stop-start.md) | Cost control levels |
| [Unity Catalog](concepts/unity-catalog.md) | Data governance hierarchy |
| [Medallion architecture](concepts/medallion-architecture.md) | Bronze and silver layers |
| [Dagster Pipes](concepts/dagster-pipes.md) | Running Databricks jobs from Dagster |
| [Asset factory](concepts/asset-factory.md) | `sources.yml` drives assets |

## Other docs

[architecture](architecture.md) · [costs](costs.md) · [conventions](conventions.md) ·
[decisions](decisions.md) · [corporate migration](corporate-migration.md) ·
[optimization](optimization.md) · [Pipes on Azure gotchas](dagster-pipes-azure-gotchas.md)

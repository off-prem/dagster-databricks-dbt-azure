# Terraform

An infrastructure-as-code tool by HashiCorp. You describe the resources you want in `.tf`
files (a database, a cluster, a storage account), and Terraform creates, updates, or deletes
them to match. This replaces clicking through the Azure portal — everything is repeatable,
reviewable, and version-controlled.

## Why we use it

Every Azure resource in this project is defined in Terraform. This means:
- The infrastructure is documented by the code itself
- Anyone can recreate the full environment from scratch
- Changes go through PR review like application code
- There's no "what did someone click in the portal?" ambiguity

## Key commands

Terraform has three main commands you'll run repeatedly:

| Command | What it does |
|---------|-------------|
| `terraform init` | Downloads **providers** (plugins that talk to Azure, Databricks, etc.) and connects to the [state backend](../concepts/terraform-state.md). Run once per stack, or after changing backend config. **Makes no changes to infrastructure.** |
| `terraform plan` | Compares your `.tf` files to the current [state](../concepts/terraform-state.md) and shows what it *would* create, change, or destroy. **Makes no changes.** Always run this before `apply` to review. |
| `terraform apply` | Actually creates/changes/destroys resources. Shows the plan first and asks you to type "yes." **This is the command that costs money and makes real changes.** |

The `justfile` wraps these so you don't have to remember flags:

```bash
just tf-init <stack>     # terraform init for a stack
just tf-plan <stack>     # terraform plan
just tf-apply <stack>    # terraform apply
```

Where `<stack>` is one of: `bootstrap`, `shared`, `env-stage`, `env-prod`.

## How it's configured in this project

We have three **stacks** (independent Terraform working directories, each with their own
state):

| Stack | Directory | What it manages | State |
|-------|-----------|----------------|-------|
| `bootstrap` | `infra/bootstrap/` | [Terraform state storage](../concepts/terraform-state.md), [Entra app for OIDC](../resources/entra-app.md) | Local (file on disk) |
| `shared` | `infra/shared/` | [VNet](../resources/vnet.md), [AKS](../resources/aks.md), [ACR](../resources/acr.md), [Key Vault](../resources/key-vault.md), [Postgres](../resources/postgres.md), [ADLS](../resources/adls.md) | Remote (Azure storage) |
| `env` | `infra/env/` | [Databricks workspace](../resources/databricks-workspace.md), [managed identity](../resources/managed-identity.md), per-env Postgres DB, K8s namespace — applied twice with different `.tfvars` | Remote (separate keys: `stage.tfstate`, `prod.tfstate`) |

Reusable logic lives in `infra/modules/` (e.g., `modules/aks`, `modules/databricks-workspace`).

### Variables and `.env`

Terraform reads variables from environment variables prefixed `TF_VAR_*`. For example,
`TF_VAR_subscription_id` in your `.env` becomes the Terraform variable `subscription_id`.
The [justfile](just.md) auto-loads `.env`, so these are always available.

### Providers

| Provider | What it talks to |
|----------|-----------------|
| `azurerm` | Azure Resource Manager (most Azure resources) |
| `azuread` | Entra ID / Azure Active Directory (app registrations, service principals) |
| `databricks` | Databricks workspace objects (catalogs, warehouses, service principals) |
| `random` | Generates random suffixes for globally-unique resource names |

## Key files

- `infra/bootstrap/main.tf` — state storage + GitHub OIDC app
- `infra/shared/` — all shared Azure resources
- `infra/env/` — per-environment resources; `stage.tfvars` and `prod.tfvars` provide the settings
- `infra/modules/` — reusable modules

## Related docs

- [Terraform state](../concepts/terraform-state.md) — how state works and why it matters
- [Costs](../costs.md) — what each resource costs
- [Conventions](../conventions.md) — naming patterns, tagging, module interface rules

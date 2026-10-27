# Terraform

> **Type:** Tool · **Scope:** all stacks · **Pinned:** 1.17.0 (`.tool-versions`)

HashiCorp's infrastructure-as-code tool. You describe resources in `.tf` files, and Terraform
creates, changes or deletes real resources to match.

## Why we use it

Every Azure resource, and the long-lived Databricks objects, are defined in code. That makes
the environment repeatable, reviewable in PRs, and free of "what did someone click in the portal?".

## How it's used here

Three independent **stacks**, each with its own state:

| Stack | Directory | Manages | State |
|-------|-----------|---------|-------|
| `bootstrap` | `infra/bootstrap/` | [Terraform state storage](../resources/tfstate-storage.md), [Entra app](../resources/entra-app.md) for CI | local (git-ignored) |
| `shared` | `infra/shared/` | [VNet](../resources/vnet.md), [AKS](../resources/aks.md), [ACR](../resources/acr.md), [Key Vault](../resources/key-vault.md), [Postgres](../resources/postgres.md), [ADLS](../resources/adls.md), [NSP](../resources/network-security-perimeter.md) | remote `shared.tfstate` |
| `env` | `infra/env/` | Per-env workspace, access connector, identity, and Databricks objects. Applied twice with `stage.tfvars` / `prod.tfvars`. | remote `stage.tfstate` / `prod.tfstate` |

**Providers:** `azurerm` (~> 4.0), `azuread` (~> 3.0), `databricks` (~> 1.65), `random` (~> 3.6), `time` (~> 0.12).

**Variables** come from `TF_VAR_*` entries in `.env`. Committed `.tfvars` hold only non-personal
values (`env = "stage"`). Databricks resources use `count` and stay at zero until `metastore_id`
and `databricks_host` are set.

## Key commands & files

```bash
source scripts/load-env.sh               # Claude's shell has no `just`
terraform -chdir=infra/env init
terraform -chdir=infra/env plan -var-file=stage.tfvars
just tf-plan env-stage
scripts/setup-env.sh collect-tf shared   # capture outputs into .env
```

`init` and `plan` change nothing. `apply` is what costs money. Apply to **prod** only with explicit approval.

## Gotchas

- `infra/modules/*` contain only READMEs. No module code exists yet, so each stack defines resources inline.
- Random name suffixes ([naming](../concepts/resource-naming.md)) and the 30 s `time_sleep` for Key Vault role propagation are Terraform resources too.
- Run `collect-tf` after every apply; Helm and Dagster read those values from `.env`.
- Stage and prod use separate `.terraform` directories so providers and backends don't collide.
- Lock files (`.terraform.lock.hcl`) are committed; commit lock-file changes deliberately.

## Cost

Free. The resources it creates are what bill (see [costs](../costs.md)).

## Managed by

Installed by `scripts/setup-tools.sh`; validated in CI with `hashicorp/setup-terraform`.

## Related docs

- [Terraform state](../concepts/terraform-state.md)
- [Environment parametrization](../concepts/environment-parametrization.md)
- [Azure RBAC](../concepts/azure-rbac.md)
- [Conventions](../conventions.md), [Costs](../costs.md)

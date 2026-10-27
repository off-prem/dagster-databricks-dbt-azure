# Resource Naming

> **Type:** Concept · **Scope:** all Azure and Databricks resources · **Where:** `infra/*/main.tf`, `TF_VAR_project`

How resource names are built so they are predictable, unique and derivable from two inputs: `project` and `env`.

## Why we use it

Scripts and docs need to guess names (`rg-dagster-shared`, `aks-dagster`). Some Azure names must also be globally unique, which needs a random part.

## How it's used here

- **`project`** (`TF_VAR_project`, default `dagster`) prefixes everything. Set it **before** the first apply, because changing it later recreates resources.
- **`env`** is `stage` or `prod` for per-environment resources.
- **A 4-character random suffix** (`random_string`) is added to globally unique names, such as ACR, Key Vault, storage and Postgres.

| Resource | Pattern |
|----------|---------|
| Resource groups | `rg-<project>-{tfstate,shared,<env>}` |
| VNet / NSG | `vnet-<project>` / `nsg-<project>-shared` |
| AKS | `aks-<project>` |
| ACR | `acr<project><suffix>` |
| Key Vault | `kv-<project>-<suffix>` |
| Postgres | `pg-<project>-<suffix>` (databases `<project>_<env>`) |
| ADLS / state storage | `st<project><suffix>` / `st<project>tf<suffix>` |
| Databricks workspace / access connector | `dbw-<project>-<env>` / `dbac-<project>-<env>` |
| SQL warehouse | `sql-<project>-<env>` |
| Managed identity | `id-<project>-<env>` (federated credential `fed-<project>-<env>`) |
| Entra apps | `app-<project>-github` (CI); `sp-<project>-<env>` (Dagster's Databricks app and principal; client-secret label `dagster-m2m`) |
| Storage credential / external location | `sc-<project>-<env>` / `el-<project>-<env>` |
| NSP | `nsp-<project>` |
| Kubernetes namespace and Helm release | `<project>-<env>` |

Tags on resources: `project`, `env`, `owner`, `managed_by`.

## Key commands & files

```bash
az resource list -g rg-dagster-shared -o table
scripts/setup-env.sh collect-tf shared      # captures the suffixed names into .env
```

## Gotchas

- Tools find suffixed names through `.env` (`ACR_NAME`, `KV_NAME`, `STORAGE_ACCOUNT_NAME`, `PG_FQDN`). Never hardcode them.
- The `env` stack discovers the shared Key Vault and storage account by **type** within the shared resource group, which assumes exactly one of each.
- The suffix lives in Terraform state. Losing the state means new random names on re-apply.
- Storage names are limited to 24 lowercase alphanumerics, so a long `project` can break the name.

## Cost

Free.

## Managed by

[Terraform](../tools/terraform.md) and `.env`.

## Related docs

- [Environment parametrization](environment-parametrization.md), [Resource groups](../resources/resource-groups.md)
- [Terraform state](terraform-state.md), [Conventions](../conventions.md)

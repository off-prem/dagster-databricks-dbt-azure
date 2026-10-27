# Terraform State Storage

> **Type:** Resource · **Scope:** shared · **Name:** `st<project>tf<random>` / container `tfstate` · **Stack:** `infra/bootstrap`

A storage account and blob container holding the remote [Terraform state](../concepts/terraform-state.md)
for the `shared` and `env` stacks.

## Why we use it

State must outlive your laptop and be reachable from CI. Azure Blob Storage supports
locking so two applies can't collide.

## How it's used here

| Setting | Value |
|---------|-------|
| Resource group | `rg-<project>-tfstate` |
| Tier / replication | Standard, LRS |
| Minimum TLS | 1.2 |
| Container | `tfstate` |
| Blobs | `shared.tfstate`, `stage.tfstate`, `prod.tfstate` |

The `bootstrap` stack creates this account, so its own state stays **local**
(`infra/bootstrap/terraform.tfstate`, git-ignored). `just tf-init` configures the other
stacks' backend to point here.

## Key commands & files

```bash
az storage blob list --account-name <name> --container-name tfstate --auth-mode login -o table
```

Terraform: `infra/bootstrap/main.tf`.

## Gotchas

- State may contain secrets (for example the Databricks SP secret). Restrict who has Blob
  Data access to it.
- Losing the local bootstrap state means re-importing resources. Back it up or keep the disk safe.
- `destroy-all` removes this last, because the other stacks need it while they are destroyed.

## Cost

Under $0.01/month.

## Managed by

[Terraform](../tools/terraform.md), `infra/bootstrap/` (applied once).

## Related docs

- [Terraform state](../concepts/terraform-state.md), [Terraform](../tools/terraform.md)
- [Resource groups](resource-groups.md)

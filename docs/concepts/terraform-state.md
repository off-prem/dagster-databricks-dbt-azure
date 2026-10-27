# Terraform State

> **Type:** Concept · **Scope:** all stacks · **Where:** `infra/*/`, [state storage](../resources/tfstate-storage.md)

The record of what [Terraform](../tools/terraform.md) has created. Without it, Terraform
can't tell what already exists.

## Why we use it

After `apply`, Terraform stores each resource's ID and attributes in a JSON **state** file.
`plan` compares code, state and reality to decide what to change. Remote state makes it durable and shareable.

## How it's used here

| Stack | State location | Why |
|-------|---------------|-----|
| `bootstrap` | **Local**, `infra/bootstrap/terraform.tfstate` (git-ignored) | It creates the storage account, so it can't use it (chicken and egg) |
| `shared` | Remote, `tfstate/shared.tfstate` | Durable, shareable, locked |
| `env` (stage) | Remote, `tfstate/stage.tfstate` | Own key |
| `env` (prod) | Remote, `tfstate/prod.tfstate` | Own key |

`infra/env/` is applied twice with different `.tfvars`, so each env needs its own state key and
its own `.terraform` directory to avoid mixing resources and cached providers.

**Outputs** (resource names with random suffixes, IDs, hosts) are captured into `.env` by
`scripts/setup-env.sh collect-tf <stack>`, where Helm, dbt and the Databricks CLI read them.

## Key commands & files

```bash
just tf-init shared
terraform -chdir=infra/shared output
scripts/setup-env.sh collect-tf shared
```

## Gotchas

- State can hold secrets (passwords, SP client secrets). Never commit it, and limit access to the storage account.
- If local `bootstrap` state is lost, existing resources can be re-adopted with `terraform import`, but it is manual.
- Two people applying the same stack at once is blocked by blob locking. A crashed run may leave a lock.
- Never edit state by hand; use `terraform state` commands.

## Cost

Negligible (a few KB of blob storage).

## Managed by

`infra/bootstrap/` creates the storage; `just tf-init` configures each stack's backend.

## Related docs

- [Terraform](../tools/terraform.md), [State storage](../resources/tfstate-storage.md)
- [just](../tools/just.md), [Environment parametrization](environment-parametrization.md)

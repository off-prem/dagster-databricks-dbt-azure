# Resource Groups

> **Type:** Resource · **Scope:** shared + per-env · **Name:** `rg-<project>-{tfstate,shared,<env>}` · **Stacks:** all

Azure's folder for related resources. Everything in a group shares a lifecycle and can be
inspected, tagged and costed together.

## Why we use it

Groups follow the Terraform stack boundaries, so cost reports and cleanup map to the code.

## How it's used here

| Group | Created by | Contains |
|-------|-----------|----------|
| `rg-<project>-tfstate` | `bootstrap` | [State storage](tfstate-storage.md) |
| `rg-<project>-shared` | `shared` | VNet, AKS, ACR, Key Vault, Postgres, ADLS, NSP |
| `rg-<project>-<env>` | `env` | Workspace, [access connector](databricks-access-connector.md), [managed identity](managed-identity.md) |
| `rg-<project>-<env>-dbx-managed` | Azure | Managed resources of the Databricks workspace (do not edit) |
| `MC_...` node group | AKS | Node VM, disk, load balancer, egress IP (managed by AKS) |

Resources carry tags from `local.tags`: `project`, `env`, `owner`, `managed_by`.

## Key commands & files

```bash
az group list --query "[?starts_with(name,'rg-dagster')].name" -o tsv
```

## Gotchas

- Don't manually delete the AKS-managed `MC_` group or the Databricks managed group; delete the owning resource.
- For cost review, group by resource group in Cost Management. The `MC_` group holds most of the AKS bill.
- The AKS egress IP lives in the `MC_` group, and Terraform looks it up from there.

## Cost

Free.

## Managed by

[Terraform](../tools/terraform.md): `infra/bootstrap/`, `infra/shared/`, `infra/env/`.

## Related docs

- [Terraform state](../concepts/terraform-state.md), [Conventions](../conventions.md) (naming and tags)
- [Costs](../costs.md), [Stop/start](../concepts/stop-start.md)

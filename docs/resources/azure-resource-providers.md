# Azure Resource Providers

> **Type:** Resource · **Scope:** subscription · **Names:** 7 `Microsoft.*` namespaces · **Created:** manually (guide step 0.6)

The namespaces through which Azure offers each service. A provider must be **registered** on a subscription before you can create
its resources.

## Why we use it

Without registration, `terraform apply` fails with a "subscription is not registered to use namespace" error. Registration is free and permanent.

## How it's used here

Registered once, before the first apply:

| Provider | Needed for |
|----------|-----------|
| `Microsoft.Databricks` | Workspaces and access connectors |
| `Microsoft.ContainerService` | AKS |
| `Microsoft.ContainerRegistry` | ACR |
| `Microsoft.DBforPostgreSQL` | Postgres Flexible Server |
| `Microsoft.KeyVault` | Key Vault |
| `Microsoft.ManagedIdentity` | User-assigned managed identities |
| `Microsoft.Storage` | Terraform state and ADLS |

## Key commands & files

```bash
az provider register -n Microsoft.Databricks
az provider show -n Microsoft.Databricks --query registrationState -o tsv   # Registered
```

The guide has a loop for all seven. `scripts/verify.sh 0` also checks the phase-0 prerequisites.

## Gotchas

- Registration is asynchronous. `Registering` can last several minutes; re-run `show` until all say `Registered`.
- The network and authorization providers (`Microsoft.Network`, `Microsoft.Authorization`) are normally registered by default.
  The network security perimeter and perimeter association use `Microsoft.Network`, so if they fail, check it too.
- Registering a provider requires permission at subscription scope (Owner or Contributor).
- Registering does not create anything billable.

## Cost

Free.

## Managed by

Manual `az provider register` commands from the guide. Not Terraform.

## Related docs

- [Azure subscription and tenant](azure-subscription.md), [Azure CLI](../tools/azure-cli.md)
- [Terraform](../tools/terraform.md)

# Azure Subscription and Tenant

> **Type:** Resource · **Scope:** one · **Values:** `TF_VAR_subscription_id`, `TF_VAR_tenant_id` · **Created:** manually (guide steps 0.2, 0.4)

The Azure account everything is billed to (the **subscription**) and the Entra directory that holds identities (the **tenant**).

## Why we use it

All Azure resources live inside a subscription, and all identities (people, apps, managed identities) live in the tenant.
Terraform, `az`, CI and the Databricks account all need these two IDs.

## How it's used here

- **Free account:** sign up at azure.microsoft.com/free ($200 credit for 30 days). No resources are created yet.
- **Detected automatically:** `scripts/setup-env.sh` reads `az account show` and writes the IDs into `.env`
  (`TF_VAR_subscription_id`, `TF_VAR_tenant_id`, `ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID`).
- **CI:** the same IDs are published as the repository variables `AZURE_SUBSCRIPTION_ID` and `AZURE_TENANT_ID`.
  They are identifiers, not secrets, but they are personal, so they are never committed.
- **Provider registration:** each service must be [registered](azure-resource-providers.md) on the subscription once.
- **Roles:** the CI app gets Contributor and User Access Administrator at subscription scope ([RBAC](../concepts/azure-rbac.md)).

## Key commands & files

```bash
az login
az account set --subscription <subscription-id>
az account show --query '{subscription:id, tenant:tenantId}' -o table
```

## Gotchas

- **Free-trial limits:** VM sizes and database SKUs are restricted per subscription and region. This is why AKS uses
  `Standard_D2as_v6` and Postgres is in `centralus`. Upgrading to Pay-As-You-Go keeps your remaining credit and lifts many limits.
- **Session expiry:** new accounts with security defaults expire CLI tokens quickly. If a command fails with `AADSTS530035`, run
  `az logout` and `az login --tenant "$TF_VAR_tenant_id" --scope "https://management.azure.com/.default"`.
- Several `az` and Terraform steps need to act on the right subscription. Check `az account show` if resources appear in an unexpected place.
- Do not commit these IDs, even though they aren't secrets.

## Cost

The account is free. See [costs](../costs.md) for the resources.

## Managed by

Created by hand in the Azure portal. Not Terraform.

## Related docs

- [Azure resource providers](azure-resource-providers.md), [Azure CLI](../tools/azure-cli.md)
- [Entra app](entra-app.md), [Azure RBAC](../concepts/azure-rbac.md)
- [Environment parametrization](../concepts/environment-parametrization.md)

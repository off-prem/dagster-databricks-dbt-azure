# Azure RBAC (role assignments)

> **Type:** Concept · **Scope:** subscription + per-resource · **Where:** `azurerm_role_assignment` in `infra/`

Azure's permission system. A **role assignment** says: this identity has this role on this scope.

## Why we use it

Every identity here gets the minimum role it needs, and access is granted in code. Key Vault, AKS
and storage all use Azure RBAC, with no separate access policies or local accounts.

## How it's used here

| Identity | Role | Scope | Why |
|----------|------|-------|-----|
| CI [Entra app](../resources/entra-app.md) | Contributor | Subscription | Create and change resources |
| CI Entra app | User Access Administrator | Subscription | Assign roles in Terraform |
| CI Entra app | AKS RBAC Cluster Admin | [AKS](../resources/aks.md) | Helm and kubectl in deploys |
| You (Terraform applier) | AKS RBAC Cluster Admin | AKS | Local kubectl |
| You | Key Vault Secrets Officer | [Key Vault](../resources/key-vault.md) | Write secrets |
| AKS kubelet identity | AcrPull | [ACR](../resources/acr.md) | Pull images |
| Dagster [managed identity](../resources/managed-identity.md) | Key Vault Secrets User | Key Vault | Read secrets |
| Databricks [access connector](../resources/databricks-access-connector.md) | Storage Blob Data Contributor | [ADLS](../resources/adls.md) | Read and write table files |

Databricks has its own permission layer on top ([Unity Catalog](unity-catalog.md) grants, workspace ACLs),
managed with the `databricks` provider.

## Key commands & files

```bash
az role assignment list --assignee <object-id> --all -o table
az role assignment list --scope <resource-id> -o table
```

## Gotchas

- Role assignments take up to a few minutes to propagate. A 403 right after an apply often resolves itself.
- Contributor + User Access Administrator on a subscription is broad. For a corporate subscription,
  scope it to the resource groups.
- Data-plane roles (Blob Data, Key Vault Secrets) are separate from control-plane roles such as Contributor.
  Contributor alone can't read secrets.
- You need Owner or User Access Administrator yourself to apply the `bootstrap` stack.

## Cost

Free.

## Managed by

[Terraform](../tools/terraform.md), all stacks.

## Related docs

- [OIDC](oidc.md), [Workload identity](workload-identity.md), [Secrets flow](secrets-flow.md)
- [kubelogin](../tools/kubelogin.md)

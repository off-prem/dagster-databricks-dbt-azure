# Entra App Registration (CI identity)

> **Type:** Resource · **Scope:** shared (one app) · **Name:** `app-<project>-github` · **Stack:** `infra/bootstrap`

An identity in Microsoft Entra ID that represents GitHub Actions. Workflows sign in as this
app to deploy.

## Why we use it

CI must push images, upgrade Helm releases and deploy bundles. Instead of a stored password,
the app trusts short-lived GitHub tokens through [OIDC](../concepts/oidc.md), so there is
no secret to leak or rotate.

## How it's used here

| Item | Detail |
|------|--------|
| Federated credentials (4) | `github-main` (`ref:refs/heads/main`), `github-env-stage`, `github-env-prod` (`environment:<env>`), `github-pull-request` |
| Subject prefix | `TF_VAR_github_oidc_prefix` (includes org and repo IDs), detected by `setup-env.sh` |
| Subscription roles | Contributor and User Access Administrator ([RBAC](../concepts/azure-rbac.md)) |
| Cluster role | AKS RBAC Cluster Admin, granted from `shared` when `github_sp_client_id` is set |
| Databricks | Needs `workspace-access` and `CAN_MANAGE` on the bundle folder |

The three IDs (client, tenant, subscription) are stored as GitHub repository **variables**,
not secrets.

## Key commands & files

```bash
just tf-apply bootstrap
scripts/setup-env.sh collect-tf bootstrap
just setup-ci
```

Terraform: `infra/bootstrap/main.tf`.

## Gotchas

- A federated credential matches the subject **exactly**. A new environment or branch
  pattern needs a new credential.
- User Access Administrator is powerful because the app can grant roles. Keep the repo's
  `main` protected by review, since `main` can deploy.
- The Databricks side of the identity is set up in the workspace (entitlement, bundle permissions),
  not in Azure.

## Cost

Free.

## Managed by

[Terraform](../tools/terraform.md), `infra/bootstrap/` (applied once, state kept locally).

## Related docs

- [OIDC](../concepts/oidc.md), [CI/CD](../concepts/cicd.md), [GitHub environments](github-environments.md)
- [Azure RBAC](../concepts/azure-rbac.md)
- [Databricks service principal](databricks-service-principal.md): the *other* principal, used by Dagster

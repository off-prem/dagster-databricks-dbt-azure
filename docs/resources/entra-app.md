# Entra App Registration

An identity in Microsoft Entra ID (formerly Azure Active Directory) that represents an
application — in this case, GitHub Actions. When a GitHub Actions workflow runs, it
authenticates as this app to create and manage Azure resources.

## Why we need it

CI/CD workflows need permission to deploy to Azure (push Docker images, run Helm upgrades,
deploy Databricks bundles). Instead of storing a password or secret in GitHub, we use
[OIDC](../concepts/oidc.md) — GitHub proves its identity with a short-lived token, and
Azure trusts it because we've pre-registered the trust relationship.

## Configuration

| Setting | What it is |
|---------|-----------|
| Display name | `app-dagster-github` |
| Federated credentials (×3) | Trust rules for `repo:<org>/<repo>:ref:refs/heads/main`, `...:environment:stage`, `...:environment:prod`. Only these specific GitHub contexts can authenticate. |
| Contributor role | Can create, update, and delete Azure resources in the subscription |
| User Access Administrator role | Can assign roles to other identities (needed to grant AKS, managed identities, etc. their permissions) |

### What are federated credentials?

Normally, an app would authenticate with a client secret (a password). Federated credentials
replace this — instead of a shared secret, they say "I trust tokens issued by GitHub's OIDC
provider, but only when the token says it came from this specific repo and branch/environment."
This means:
- No secret is stored in GitHub (nothing to rotate or leak)
- Only the specific repo/branch/environment combinations you registered can authenticate
- Tokens are short-lived (valid for minutes, not months)

## Cost

Free. App registrations, service principals, and federated credentials have no cost.

## Provisioned by

[Terraform](../tools/terraform.md) — `infra/bootstrap/` stack.

## Related docs

- [OIDC](../concepts/oidc.md) — how the authentication flow works
- [CI/CD](../concepts/cicd.md) — the workflows that authenticate as this app
- [Terraform](../tools/terraform.md) — the bootstrap stack that creates the app

# OIDC (OpenID Connect)

A protocol that lets one system prove its identity to another without sharing a password.
In this project, it's how GitHub Actions authenticates to Azure.

## The problem it solves

GitHub Actions workflows need to deploy to Azure (push Docker images, run Helm upgrades,
manage Terraform resources). The traditional approach is to create a secret (a password)
in Azure and store it in GitHub Secrets. This has downsides:
- The secret is long-lived (months or years) — if it leaks, an attacker has access until
  someone notices and rotates it
- The secret must be manually rotated
- Anyone with access to the GitHub repo settings can see and copy it

## How OIDC works instead

With OIDC, there's no shared secret at all:

1. **Setup (once):** You create an [Entra app](../resources/entra-app.md) in Azure with
   **federated credentials** that say: "I trust tokens from GitHub's OIDC provider, but
   only when the token says it came from `repo:my-org/my-repo` and a specific
   branch/environment."

2. **At runtime (every workflow run):**
   - GitHub Actions generates a short-lived JWT token (valid for minutes)
   - The token says: "I am a workflow running in repo `my-org/my-repo`, branch `main`"
   - The workflow presents this token to Azure
   - Azure checks: "Is this token from GitHub's OIDC provider? Does it match one of my
     federated credentials?" If yes, Azure issues an access token.
   - The workflow uses the access token to manage Azure resources

## Federated credentials in this project

The [Entra app](../resources/entra-app.md) `app-dagster-github` has three federated
credentials:

| Credential | Matches | Used by |
|-----------|---------|---------|
| `github-main` | `repo:<org>/<repo>:ref:refs/heads/main` | Workflows triggered by pushes to `main` |
| `github-env-stage` | `repo:<org>/<repo>:environment:stage` | Workflows targeting the `stage` environment |
| `github-env-prod` | `repo:<org>/<repo>:environment:prod` | Workflows targeting the `prod` environment |

This means only these specific contexts can authenticate — a workflow from a fork or a
different branch can't.

## What the workflows need in GitHub

Three **repository variables** (not secrets — these are non-sensitive IDs):

| Variable | What it identifies |
|----------|-------------------|
| `AZURE_CLIENT_ID` | The Entra app |
| `AZURE_TENANT_ID` | Your Azure directory |
| `AZURE_SUBSCRIPTION_ID` | Your billing container |

The workflow uses `azure/login@v2` with these variables to authenticate.

## Related docs

- [Entra app](../resources/entra-app.md) — the identity that GitHub authenticates as
- [CI/CD](cicd.md) — the workflows that use OIDC
- [Workload identity](workload-identity.md) — a similar concept, but for Kubernetes pods
  authenticating to Azure (instead of GitHub)

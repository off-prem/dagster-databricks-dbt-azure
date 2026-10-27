# OIDC (OpenID Connect)

> **Type:** Concept · **Scope:** CI → Azure · **Where:** `infra/bootstrap/`, workflows

A protocol that lets one system prove its identity to another without a shared password.
Here it is how GitHub Actions authenticates to Azure.

## Why we use it

The usual alternative is a long-lived client secret stored in GitHub. It can leak, needs manual
rotation, and is visible to anyone with repo admin access. With OIDC there is no secret at all.

## How it's used here

1. **Setup (once):** the [Entra app](../resources/entra-app.md) gets **federated credentials**
   that say "trust tokens from GitHub's issuer, only for these subjects".
2. **Each run:** GitHub issues a short-lived JWT for the workflow. `azure/login@v2` presents it to
   Entra, which checks the issuer and subject against a credential and returns an access token.

| Credential | Subject | Used when |
|-----------|---------|-----------|
| `github-main` | `<prefix>:ref:refs/heads/main` | pushes to `main` |
| `github-env-stage` | `<prefix>:environment:stage` | jobs with `environment: stage` |
| `github-env-prod` | `<prefix>:environment:prod` | jobs with `environment: prod` |
| `github-pull-request` | `<prefix>:pull_request` | PR workflows |

`<prefix>` is your org/repo subject prefix. `setup-env.sh` detects it as `TF_VAR_github_oidc_prefix`.
Three **repository variables** hold the non-secret IDs: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
`AZURE_SUBSCRIPTION_ID`. The workflow needs `permissions: id-token: write`.

## Key commands & files

```bash
just tf-apply bootstrap         # creates app + credentials
just setup-ci                   # publishes the IDs as repo variables
```

## Gotchas

- Subjects match exactly. Renaming an environment or the repo breaks sign-in until the credential is updated.
- A fork's PR can't get a token for these credentials, by design.
- Tokens last minutes, so long jobs that call Azure late may need a fresh `azure/login`.

## Cost

Free.

## Managed by

[Terraform](../tools/terraform.md) (`infra/bootstrap/`) and `scripts/setup-ci.sh`.

## Related docs

- [Entra app](../resources/entra-app.md), [GitHub Actions](../tools/github-actions.md), [CI/CD](cicd.md)
- [Workload identity](workload-identity.md): the same idea for pods
- [Azure RBAC](azure-rbac.md)

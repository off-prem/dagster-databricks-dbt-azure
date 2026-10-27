# GitHub Environments and Repository Variables

> **Type:** Resource · **Scope:** per-env + repo · **Names:** `stage`, `prod` · **Managed by:** `scripts/setup-ci.sh`

GitHub's deployment targets. An environment can require approval and is part of the OIDC
token that Azure checks.

## Why we use it

It makes `prod` a gated target and gives workflows a non-secret place to read IDs. The
environment name appears in the token subject (`environment:prod`), which lets the
[Entra app](entra-app.md) trust only that context.

## How it's used here

- **Environments:** `stage` (no reviewers) and `prod` (you as required reviewer).
  `promote-prod.yml` declares `environment: prod`, so it pauses for approval.
- **Repository variables** (never secrets): `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
  `AZURE_SUBSCRIPTION_ID`, `ACR_NAME`, `PG_FQDN`, the per-env Databricks hosts, warehouse paths,
  SP client IDs and identity client IDs, and the project/OIDC settings. They come from `.env`.
- Workflows read them as `${{ vars.NAME }}`.

## Key commands & files

```bash
just setup-ci --dry-run
just setup-ci
gh variable list --repo <owner/repo>
```

## Gotchas

- Re-run `just setup-ci` after every Terraform apply that changes an ID (for example a rebuilt workspace).
- Missing variables produce blank values in Helm, so check the "WARNING: ... is blank" output.
- The main branch has no branch protection, so approval on `prod` is the only gate.
  Never push directly to `main`.

## Cost

Free.

## Managed by

`scripts/setup-ci.sh` using the [GitHub CLI](../tools/github-cli.md).

## Related docs

- [GitHub Actions](../tools/github-actions.md), [CI/CD](../concepts/cicd.md)
- [OIDC](../concepts/oidc.md), [Entra app](entra-app.md)

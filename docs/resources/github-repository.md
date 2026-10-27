# GitHub Repository

> **Type:** Resource · **Scope:** one · **Name:** your fork (`TF_VAR_github_repo`) · **Created:** manually (guide step 0.1)

The repo that holds the code and runs the workflows. Everything else (the OIDC trust, the ARC runners, the
variables) is tied to its exact name.

## Why we use it

The repo is both the source of truth and the CI/CD control plane. Its identity is baked into the
[Entra app's](entra-app.md) federated credentials, so it must be a repo you control.

## How it's used here

- **Your own copy:** fork or "Use this template", then clone. `origin` must point at it, because
  `scripts/setup-env.sh` reads `origin` to set `TF_VAR_github_repo` and the OIDC subject prefix.
- **Branches and PRs:** all work happens on branches and merges via PR. There is no branch protection, so this is a convention.
- **Actions:** workflows live in `.github/workflows/`. The `workflow` token scope is needed to push them.
- **Variables and environments:** see [GitHub environments](github-environments.md).
- **Runners:** the [ARC](../tools/arc.md) scale set is registered to the repo URL through the [GitHub App](github-app.md).
- **Hardening (guide step 5.7):** copy `.github/CODEOWNERS.example` to `.github/CODEOWNERS` with your handle or team.

## Key commands & files

```bash
git remote -v                          # origin must be your fork
gh repo view --json nameWithOwner
gh variable list --repo <owner/repo>
```

Files: `.github/workflows/`, `.github/CODEOWNERS.example`.

## Gotchas

- **Renaming or transferring the repo** changes the OIDC subject. Update `TF_VAR_github_oidc_prefix` and re-apply `bootstrap`.
- Required reviewers on environments need a public repo or a paid plan. On the free plan with a private repo, the `prod` gate won't work.
- The immutable subject format includes org and repo IDs, so a deleted-and-recreated repo with the same name gets different IDs.
- Never commit secrets, tenant/subscription IDs, IPs or org names. See [repo config files](../concepts/repo-config-files.md).

## Cost

Free tier.

## Managed by

Created manually. Settings are partly scripted by `scripts/setup-ci.sh`.

## Related docs

- [GitHub environments](github-environments.md), [GitHub App](github-app.md), [Entra app](entra-app.md)
- [GitHub Actions](../tools/github-actions.md), [GitHub CLI](../tools/github-cli.md), [OIDC](../concepts/oidc.md)

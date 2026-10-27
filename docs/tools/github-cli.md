# GitHub CLI (`gh`)

> **Type:** Tool · **Scope:** local · **Pinned:** not pinned (install from cli.github.com)

GitHub's command-line tool for repositories, variables, environments and the API.

## Why we use it

CI needs a set of non-secret IDs as repository variables and two environments. Doing that
by hand in the web UI is error-prone, so `scripts/setup-ci.sh` does it with `gh`.

## How it's used here

- `scripts/setup-ci.sh` runs `gh variable set` for each value in `.env` and creates the
  `stage` and `prod` [environments](../resources/github-environments.md) with `gh api`.
  `prod` gets you as required reviewer.
- `scripts/setup-env.sh` uses the API to compute the OIDC subject prefix
  (`TF_VAR_github_oidc_prefix`).
- Day to day: `gh pr create`, `gh pr checks`, `gh run watch`.

## Key commands & files

```bash
gh auth login
just setup-ci --dry-run        # show what would be set
just setup-ci
gh variable list --repo <owner/repo>
```

## Gotchas

- `gh` must be authenticated before `setup-ci.sh`; the script exits early otherwise.
- Only IDs go into variables. Never put a secret in a GitHub variable.
- Pushing workflow files needs the `workflow` token scope. If a push is rejected, run `gh auth refresh -s workflow --web=false` or push over SSH.
- `gh` isn't in `.tool-versions`, so its version is whatever you installed.

## Cost

Free.

## Managed by

Installed manually by the user.

## Related docs

- [GitHub Actions](github-actions.md)
- [GitHub environments](../resources/github-environments.md)
- [OIDC](../concepts/oidc.md)

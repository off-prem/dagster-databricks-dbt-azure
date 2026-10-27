# Repo Config Files

> **Type:** Concept · **Scope:** repo root · **Where:** `.tool-versions`, `.env.example`, `.gitignore`, `.dockerignore`, `.github/CODEOWNERS.example`, `.claude/settings.json`, `CLAUDE.md`

The small files that keep the repo clean, reproducible and safe to share.

## Why we use it

The repo is a blueprint others will clone. These files pin versions, keep personal values and secrets out of git, and keep images small.

## How it's used here

| File | Role |
|------|------|
| `.tool-versions` | Single source of truth for CLI versions. `setup-tools.sh` installs from it; the Dockerfile and workflows use the same numbers |
| `.env.example` | Lists every per-user key, grouped by the guide phase that fills it. The real `.env` is generated and git-ignored |
| `.gitignore` | Excludes `.env*`, `*.tfstate*`, `.terraform*`, `*.pem`, `*.key`, `.databrickscfg`, `kubeconfig*`, `*.auto.tfvars`, build output |
| `.dockerignore` | Keeps `.env`, `infra`, `deploy`, `scripts`, `docs`, state files and caches out of the image |
| `.github/CODEOWNERS.example` | Template for required reviewers on `/infra/`. Copy it to `CODEOWNERS` during hardening (guide 5.7) |
| `.claude/settings.json` | Claude Code project settings (model) |
| `CLAUDE.md` | Rules and current state for Claude Code |
| `infra/*/.terraform.lock.hcl` | Pins provider versions (committed) |
| `dagster/uv.lock` | Pins Python dependencies (committed) |

## Key commands & files

```bash
git check-ignore -v .env infra/bootstrap/terraform.tfstate
git status --short        # nothing personal should appear
```

## Gotchas

- `.dockerignore` excludes `databricks/src` but not `databricks/sources.yml`, which the image needs. Don't broaden it carelessly.
- Adding a directory the image needs? Update the Dockerfile **and** check `.dockerignore`.
- `.gitignore` covers `*.pem`, which is why the ARC GitHub App key must go to Key Vault, never into the repo.
- `CODEOWNERS.example` is inert until copied. Without branch protection it is advice, not enforcement.
- A modified `.terraform.lock.hcl` is a real change. Review it before committing.

## Cost

Free.

## Managed by

Edited by hand and reviewed in PRs.

## Related docs

- [Environment parametrization](environment-parametrization.md), [Docker](../tools/docker.md), [uv](../tools/uv.md)
- [GitHub repository](../resources/github-repository.md), [Project scripts](../tools/project-scripts.md)

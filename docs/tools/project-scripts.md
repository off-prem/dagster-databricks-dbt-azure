# Project Scripts (`scripts/`)

> **Type:** Tool · **Scope:** local + CI · **Where:** `scripts/*.sh` (wrapped by the [justfile](just.md))

The repo's own shell scripts. They hold the logic that the `justfile` recipes and CI workflows call.

## Why we use it

Logic that needs to run the same way locally and in CI lives in scripts, not in YAML. `just` gives them short names; workflows call them directly.

## How it's used here

| Script | Purpose | Called by |
|--------|---------|-----------|
| `setup-tools.sh` | Installs the CLIs pinned in `.tool-versions` into `~/.local/bin` (checksums verified), then `uv sync` in `dagster/` | `just setup-tools` |
| `setup-env.sh` | Creates and maintains the git-ignored `.env`; subcommands `set`, `show`, `collect-tf <stack>`, `collect-bundle <env>` | `just setup-env`, `collect-*` |
| `load-env.sh` | *Sourced* to export `.env` into the shell | every other script |
| `verify.sh <0-5>` | Checks that a phase is complete (tools, `.env` keys, SKU availability, resources) | `just verify` |
| `setup-ci.sh` | Syncs `.env` to GitHub repository variables and creates the `stage`/`prod` environments | `just setup-ci` |
| `setup-arc.sh` | Installs or removes [ARC](arc.md); idempotent | `just setup-arc`, `standup.sh` |
| `helm-upgrade.sh <env>` | Resolves `${VAR}` placeholders with `envsubst`, then `helm upgrade --install` | `just helm-upgrade`, workflows |
| `bundle-deploy.sh <env>` | Sets `DATABRICKS_HOST`, deploys the bundle, grants `CAN_RUN` to the Dagster principal | `just bundle-deploy`, workflows |
| `smoke-test.sh <env>` | Launches the job through GraphQL and polls to success (20-minute timeout) | `just smoke-test`, workflows |
| `port-forward.sh <env>` | Forwards the Dagster UI to `localhost:3000` | `just port-forward` |
| `stop.sh` / `start.sh` | Stop or start AKS and Postgres | `just stop`, `just start` |
| `teardown.sh` / `standup.sh` | Delete or recreate AKS | `just teardown`, `just standup` |
| `destroy-all.sh` | Destroys everything in reverse order | `just destroy-all` |

## Key commands & files

```bash
just --list
scripts/verify.sh 1        # includes the AKS / Postgres SKU pre-flight check
```

## Gotchas

- `load-env.sh` must be **sourced**, not executed, or the variables are lost when it exits.
- In CI there is no real `.env`, so the workflows `touch .env` and pass values through the environment.
- `setup-tools.sh` pins most tools, but not `gh` and not the Databricks CLI in CI.
- `destroy-all.sh` is destructive. Read its prompts before confirming.
- Scripts that touch prod need an explicit go-ahead (`helm-upgrade.sh prod`, `bundle-deploy.sh prod`).

## Cost

Free; the actions they trigger may not be.

## Managed by

Versioned in the repo.

## Related docs

- [just](just.md), [Environment parametrization](../concepts/environment-parametrization.md)
- [Stop/start](../concepts/stop-start.md), [CI/CD](../concepts/cicd.md), [Helm](helm.md)

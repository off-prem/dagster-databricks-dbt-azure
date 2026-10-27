# just

> **Type:** Tool · **Scope:** local · **Pinned:** 1.36.0 (`.tool-versions`)

A command runner, like `make` but simpler. The root `justfile` holds a named recipe for every
common operation.

## Why we use it

The project uses many CLIs with different flags and env vars. `just` wraps them in consistent
commands and **loads `.env` automatically**, so you don't have to remember to source it.

## How it's used here

The top of the `justfile` sets `set dotenv-load` and `set dotenv-required := false`. Every
key in `.env` is exported before a recipe runs. If `.env` is missing, recipes still run
(useful for `setup-env`). It also puts `~/.local/bin` on `PATH` so pinned tools are found.

Without `just` (for example in Claude's shell, or in CI), load the env yourself:

```bash
source scripts/load-env.sh
```

and run the underlying command shown in the recipe.

## Key commands & files

`just --list` shows everything. Groups:

| Group | Recipes |
|-------|---------|
| Setup | `setup-tools`, `setup-env`, `set-env`, `show-env`, `collect-tf`, `collect-bundle`, `setup-arc`, `setup-ci` |
| Terraform | `tf-init`, `tf-plan`, `tf-apply` (stack: `bootstrap`, `shared`, `env-stage`, `env-prod`) |
| Deploy | `helm-upgrade`, `bundle-validate`, `bundle-deploy` |
| Develop | `dbt <env> <cmd>`, `check-defs`, `test`, `verify <phase>` |
| Operate | `port-forward`, `smoke-test`, `stop`, `start`, `teardown`, `standup`, `destroy-all` |

## Gotchas

- `just` isn't available in Claude's shell, so scripts that need `.env` must source
  `scripts/load-env.sh` themselves.
- `.env` is git-ignored. Never move per-user values into the `justfile`.
- Recipe names take positional arguments, for example `just tf-plan env-stage`, not flags.

## Cost

Free.

## Managed by

Installed by `scripts/setup-tools.sh`.

## Related docs

- [Environment parametrization](../concepts/environment-parametrization.md): how `.env` feeds every tool
- [Terraform](terraform.md), [Helm](helm.md)
- [Conventions](../conventions.md)

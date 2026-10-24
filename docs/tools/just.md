# just

A command runner (similar to `make`, but simpler). The `justfile` at the repo root defines
shortcuts for every common operation in the project.

## Why we use it

This project uses many tools (Terraform, Helm, az, dbt, databricks, kubectl) with different
flags and environment variables. `just` wraps them into simple, consistent commands and
**automatically loads your `.env` file** so you never have to remember to source it.

## Key commands

Run `just --list` to see everything. Highlights:

### Setup
```bash
just setup-tools          # Install all CLIs from .tool-versions
just setup-env            # Detect values and scaffold .env
just show-env             # Print current .env
just set-env KEY VALUE    # Set one key in .env
just collect-tf <stack>   # Capture Terraform outputs into .env
just collect-bundle <env> # Capture pipeline ID after bundle deploy
```

### Terraform
```bash
just tf-init <stack>      # terraform init (stack: bootstrap, shared, env-stage, env-prod)
just tf-plan <stack>      # terraform plan
just tf-apply <stack>     # terraform apply
```

### Deploy
```bash
just helm-upgrade <env>       # Deploy Dagster via Helm
just bundle-validate <env>    # Validate Databricks bundle
just bundle-deploy <env>      # Deploy Databricks bundle
```

### Develop and test
```bash
just dbt <env> <cmd>      # Run dbt (e.g., just dbt stage build)
just check-defs           # Validate Dagster definitions
just test                 # Run Python tests
```

### Operate
```bash
just port-forward <env>   # Dagster UI at http://localhost:3000
just smoke-test <env>     # Automated end-to-end test
just stop                 # Stop AKS + Postgres (save money)
just start                # Start them back up
```

## How `.env` loading works

The `justfile` has these settings at the top:

```just
set dotenv-load
set dotenv-required := false
```

This tells `just` to automatically read `.env` and export every key as an environment
variable before running any recipe. If `.env` doesn't exist yet, it continues without
error (`dotenv-required := false`).

It also prepends `~/.local/bin` to `PATH`, so tools installed by `scripts/setup-tools.sh`
are always found.

## Without `just`

If you can't use `just` (e.g., in a CI environment), source the env file manually:

```bash
source scripts/load-env.sh
```

Then run the underlying commands directly (check the `justfile` to see what each recipe runs).

## Related docs

- [Conventions](../conventions.md) — the full list of `just` recipes and when to use them

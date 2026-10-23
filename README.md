# Dagster on AKS orchestrating Azure Databricks — POC

Lean proof of concept. Dagster runs on AKS via Helm; assets trigger a Databricks
Spark Declarative Pipeline (API → bronze) and a dbt model (bronze → silver).
Stage and prod environments; CI promotes merged PRs through them.

New here? Follow `docs/00-quickstart.md`. Progress and detail live in `docs/03-runbook.md`. Costs and scope are in `docs/02-services-and-costs.md`.
Design rationale is in `docs/07-decisions.md`. What changes when this moves into a
corporate network is in `docs/08-corporate-migration.md`.

## Getting started

Install the CLIs (Linux or macOS). Versions come from `.tool-versions`:

```bash
scripts/setup-tools.sh
```

- Safe to re-run: a tool already at its pinned version is skipped, and nothing is reinstalled.
- Binaries go to `~/.local/bin` with no `sudo`. Make sure that directory is on your `PATH`:
  `export PATH="$HOME/.local/bin:$PATH"` in `~/.bashrc` or `~/.zshrc`.
- `az` is installed from Microsoft's apt repo on Debian/Ubuntu (this step prompts for `sudo`),
  via Homebrew on macOS, and from PyPI via `uv` elsewhere. Force one with
  `AZ_INSTALL=apt|brew|pip scripts/setup-tools.sh`.
- To change a version, edit `.tool-versions` and re-run the script.

After `az login`, generate your per-user settings (git-ignored `.env`) with `scripts/setup-env.sh`.
It auto-detects your subscription, tenant, IP, repo and owner, and scaffolds every future key
as blank (see `.env.example` for the full list). As you progress through the runbook, `collect-tf`
and `collect-bundle` subcommands fill in values from Terraform outputs and bundle deploys — no
manual copy-paste. Committed files reference these values via `TF_VAR_*`, `scripts/helm-upgrade.sh`,
`scripts/bundle-deploy.sh`, and `dbt env_var()`. Nothing personal is ever committed.

The `justfile` loads `.env` automatically — run `just --list` to see all commands.
Without `just`, `source scripts/load-env.sh` in each shell.
Then continue with `docs/00-quickstart.md`.

Built with Claude Code; `CLAUDE.md` holds its operating rules.

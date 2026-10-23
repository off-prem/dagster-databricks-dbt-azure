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

After `az login`, generate your per-user settings (git-ignored `.env`) with `scripts/setup-env.sh`,
then continue with `docs/00-quickstart.md`.

Built with Claude Code; `CLAUDE.md` holds its operating rules.

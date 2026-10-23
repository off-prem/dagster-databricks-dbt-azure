# Dagster on AKS orchestrating Azure Databricks — POC

Lean proof of concept. Dagster runs on AKS via Helm; assets trigger a Databricks
Spark Declarative Pipeline (API → bronze) and a dbt model (bronze → silver).
Stage and prod environments; CI promotes merged PRs through them.

Start with `docs/03-runbook.md`. Costs and scope are in `docs/02-services-and-costs.md`.
Design rationale is in `docs/07-decisions.md`. What changes when this moves into a
corporate network is in `docs/08-corporate-migration.md`.

Built with Claude Code; `CLAUDE.md` holds its operating rules.

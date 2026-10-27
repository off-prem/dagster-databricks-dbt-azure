# Dagster on AKS orchestrating Azure Databricks

Lean proof of concept. Dagster runs on AKS via Helm. One asset submits a serverless
Databricks job through Dagster Pipes (API → landing volume), and dbt models build
bronze and silver tables from it.
Stage and prod environments; CI promotes merged PRs through them.

**[System overview](docs/)** — architecture, data flow, and links to every
tool, resource, and concept in one page.

**[Setup guide](docs/guide.md)** — step-by-step from fresh clone to fully running,
with `just verify <phase>` gates between phases.

**[Adoption plan](docs/adoption-plan.md)** — phased plan for moving this POC into
production with team ownership, migration strategy, and developer experience.

## Docs

| Doc | What it covers |
|-----|----------------|
| [docs/](docs/) | **System overview** — architecture, every tool/resource/concept with links |
| [guide.md](docs/guide.md) | End-to-end setup walkthrough (start here) |
| [adoption-plan.md](docs/adoption-plan.md) | POC → production: phases, team ownership, migration strategy |
| [architecture.md](docs/architecture.md) | System diagram, data flow, identity flow |
| [costs.md](docs/costs.md) | Monthly cost breakdown and scope |
| [decisions.md](docs/decisions.md) | Design rationale and trade-offs |
| [conventions.md](docs/conventions.md) | Naming, tagging, branching rules |
| [improvements.md](docs/improvements.md) | TODO tracker: security, performance, scaling |
| [corporate-migration.md](docs/corporate-migration.md) | What changes in a corporate network |

## Repo layout

```
infra/          Terraform — bootstrap/, shared/, env/, modules/
dagster/        Dagster code location + Docker image
databricks/     Databricks Asset Bundle (extract notebook + sources.yml)
dbt/            dbt project (landing files → bronze → silver)
deploy/         Helm values + K8s manifests
scripts/        Setup, deploy, verify, start/stop helpers
.github/        CI workflows (pr-checks, deploy-stage, promote-prod)
docs/           All documentation
```

## Commands

The `justfile` loads `.env` automatically. Run `just <command>`:

| Command | What it does |
|---------|-------------|
| `setup-tools` | Install all CLIs from `.tool-versions` |
| `setup-env` | Detect env values, scaffold all keys into `.env` |
| `set-env <key> <value>` | Set a single key in `.env` |
| `collect-tf <stack>` | Capture Terraform outputs into `.env` |
| `collect-bundle <env>` | Print the bundle root for an env (no `.env` key is written) |
| `show-env` | Print current `.env` values |
| `tf-init <stack>` | `terraform init` (bootstrap, shared, env-stage, env-prod) |
| `tf-plan <stack>` | `terraform plan` |
| `tf-apply <stack>` | `terraform apply` |
| `helm-upgrade <env>` | Deploy Dagster via Helm |
| `bundle-deploy <env>` | Deploy the Databricks Asset Bundle |
| `bundle-validate <env>` | Validate bundle without deploying |
| `dbt <env> <args>` | Run dbt commands against an environment |
| `check-defs` | Check Dagster definitions |
| `test` | Run Dagster tests (`pytest`; no tests exist yet) |
| `verify <phase>` | Verify a phase is complete (0–5) |
| `setup-ci` | Sync `.env` to GitHub variables and create environments |
| `setup-arc` | Install self-hosted GitHub runners (ARC) on AKS |
| `port-forward <env>` | Dagster UI at localhost:3000 |
| `smoke-test <env>` | Post-deploy smoke test |
| `stop` / `start` | Stop/start AKS + Postgres (cost control) |
| `teardown` / `standup` | Delete/recreate AKS for lower idle cost |
| `destroy-all` | Destroy all provisioned resources (start fresh) |

## Cost control

Three levels, depending on how long you'll be away. See
[stop/start](docs/concepts/stop-start.md) for details.

| Command | Idle cost | Recovery | When to use |
|---------|-----------|----------|-------------|
| `just stop` | ~$35–40/mo | `just start` (~3–5 min) | Overnight, weekends |
| `just teardown` | ~$15/mo | `just standup` (~10–15 min) | Gone for a week+ |
| `just destroy-all` | $0 | Re-run guide from Phase 0.5 | Starting fresh |

Built with Claude Code; `CLAUDE.md` holds its operating rules.

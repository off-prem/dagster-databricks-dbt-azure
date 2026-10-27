# Dagster on AKS orchestrating Azure Databricks

Lean proof of concept. Dagster runs on AKS via Helm. One asset submits a serverless
Databricks job through Dagster Pipes (API → landing volume), and dbt models build
bronze and silver tables from it.
Stage and prod environments; CI promotes merged PRs through them.

**[System overview](docs/)** — architecture, data flow, and links to every
tool, resource, and concept in one page.

## Two ways to use this repo

### Fork it

Clone or fork, install tools, and run the phase scripts — six commands from fresh
clone to running system:

```bash
git clone git@github.com:<your-org>/<your-repo>.git && cd <your-repo>
scripts/setup-tools.sh               # install all CLIs (one-time)
export PATH="$HOME/.local/bin:$PATH"  # add to ~/.bashrc to persist

just phase 0    # accounts, tools, bootstrap       (~20 min, free)
just phase 1    # shared infrastructure             (~15 min, costs begin)
just phase 2    # stage environment                 (~20 min)
just phase 3    # dbt and end-to-end lineage        (~5 min)
just phase 4    # prod environment                  (~15 min)
just phase 5    # CI/CD with automated promotion    (~15 min)
```

Each phase handles everything automatically — runs terraform, deploys services,
verifies results. It pauses at manual steps (browser logins, metastore creation)
with instructions and verifies your work before continuing. Re-running a phase
skips completed steps.

See the [setup guide](docs/guide.md) for what each phase creates, decision points,
costs, and troubleshooting.

### Adopt into an existing repo

Pull specific components (Terraform, Helm, dbt, CI/CD) into your team's codebase.
Read **[docs/adapt.md](docs/adapt.md)** for the component map and intake questions.
Use Claude with access to both repos to generate a tailored adoption plan.
See the [example plan](docs/adoption-plan-example.md) for what the output looks like.

## After setup

See [operations](docs/operations.md) for day-to-day commands.

| Command | What it does |
|---------|-------------|
| `just stop` / `just start` | Stop/start AKS + Postgres (cost control) |
| `just port-forward stage` | Dagster UI at localhost:3000 |
| `just dbt stage build` | Run dbt models |
| `just smoke-test stage` | Automated end-to-end test |
| `just helm-upgrade stage` | Redeploy Dagster after code changes |
| `just bundle-deploy stage` | Redeploy extract code to Databricks |
| `just phase <N>` | Re-run a phase (skips completed steps) |

Run `just --list` for the full command reference.

## Cost control

Three levels, depending on how long you'll be away. See
[stop/start](docs/concepts/stop-start.md) for details.

| Command | Idle cost | Recovery | When to use |
|---------|-----------|----------|-------------|
| `just stop` | ~$35–40/mo | `just start` (~3–5 min) | Overnight, weekends |
| `just teardown` | ~$15/mo | `just standup` (~10–15 min) | Gone for a week+ |
| `just destroy-all` | $0 | Re-run from `just phase 0` | Starting fresh |

## Docs

| Doc | What it covers |
|-----|----------------|
| [docs/](docs/) | **System overview** — architecture, every tool/resource/concept with links |
| [guide.md](docs/guide.md) | Setup reference: what each phase creates, decisions, troubleshooting |
| [operations.md](docs/operations.md) | Day-to-day: commands, cost control, IP changes, adding data sources |
| [adapt.md](docs/adapt.md) | Component map, intake questions, and Claude instructions (adopt path) |
| [adoption-plan-example.md](docs/adoption-plan-example.md) | Example adoption plan (Synapse/ADF migration) |
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
scripts/        Phase runners, setup, deploy, verify, start/stop helpers
.github/        CI workflows (pr-checks, deploy-stage, promote-prod)
docs/           All documentation
```

Built with Claude Code; `CLAUDE.md` holds its operating rules.

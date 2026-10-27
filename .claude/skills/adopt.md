---
name: adopt
description: >
  Guide adoption of this POC repo's components into a target repo. Use this skill
  whenever someone mentions adopting, migrating, adapting, or pulling components from
  this repo into their existing codebase — even if they say "help me use parts of this"
  or "integrate this into our repo" or "what do we need from this POC." Also trigger
  when someone opens this repo alongside another and asks about differences, compatibility,
  or how to merge patterns. The skill covers the full lifecycle: understanding both repos,
  analyzing incompatibilities, generating a phased adoption plan, and executing the
  migration upon approval.
---

# Adopt: migrate POC components into a target repo

This skill walks through adopting components from this POC (Dagster on AKS orchestrating
Azure Databricks) into an existing codebase. It covers everything from understanding both
repos through generating a plan to actually executing the migration.

The POC is a blueprint — every directory is designed to be adopted independently:
`infra/`, `dagster/`, `dbt/`, `databricks/`, `deploy/`, `scripts/` (including phase
runners and `lib/common.sh`), `.github/workflows/`, `justfile`, and the documentation
patterns.

## Before you start

Read these two files from the POC repo — they contain the component map, intake
questions, and an example of the output you'll produce:

1. **`docs/adapt.md`** — Component map (what each piece does, what it requires, when to
   skip it), intake questions (team, infra, codebase, requirements), and instructions
   for generating adoption plans.
2. **`docs/adoption-plan-example.md`** — A real adoption plan for a 30+ person team
   migrating off Synapse/ADF. Use its structure (context, principles, team ownership
   map, phased tracks, stage data strategy, developer experience, risks, open questions)
   as the template for the plan you generate.

Also skim `docs/README.md` for the full documentation map — you'll reference specific
concept/tool/resource pages when explaining components to the user.

## The five stages

### Stage 1: Understand the target repo

Before proposing anything, deeply understand what already exists. Read broadly, not just
the files the user points you to.

**What to investigate:**

- **Repo structure** — mono-repo or multi-repo? Where does infra live relative to app
  code? Is there a `packages/`, `libs/`, or domain-based layout?
- **Infrastructure** — Terraform, Pulumi, Bicep, ARM, CDK, or click-ops? What
  providers and modules exist? State backend location and structure.
- **Orchestration** — Dagster, Airflow, ADF, Prefect, or none? How are DAGs/assets
  defined? How are they deployed?
- **Data transformations** — dbt, Spark notebooks, stored procedures, or custom ETL?
  Which adapter/connection pattern?
- **Databricks** — Existing workspaces, catalogs, bundles, jobs? How are they managed
  (Terraform, CLI, UI, another tool)?
- **CI/CD** — GitHub Actions, Azure DevOps, Jenkins, GitLab CI? What does the pipeline
  look like? Self-hosted runners?
- **Secrets management** — Key Vault, HashiCorp Vault, environment variables, other?
- **Kubernetes** — Existing AKS clusters? Shared with other workloads? Helm charts?
- **Conventions** — naming patterns, tagging policies, branching strategy, PR workflow,
  code style, documentation patterns.
- **Dependencies and tooling** — package managers, task runners, linters, formatters,
  Docker setup.

Don't just list what you find — form an understanding of the team's conventions and
constraints so your recommendations feel native to their codebase, not grafted on.

### Stage 2: Understand the POC repo

Read the POC's documentation and code to understand every adoptable component. The key
docs to read (beyond adapt.md which you already have):

- `docs/architecture.md` — system diagram, data flow, identity flow
- `docs/conventions.md` — naming, tagging, parametrization patterns
- `docs/decisions.md` — design rationale (important: understand *why* choices were made
  so you can judge whether the same reasoning applies to the target repo)
- `docs/corporate-migration.md` — what changes in a corporate network (private
  endpoints, VNet injection, egress control)
- `docs/improvements.md` — known gaps and planned enhancements
- `docs/concepts/dagster-pipes.md` — the Azure-specific Pipes gotchas are critical
- `docs/concepts/helm-deployments.md` — run pod configuration is the #1 gotcha

Skim the actual code in `infra/`, `dagster/`, `dbt/`, `databricks/`, `deploy/`,
`scripts/`, and `.github/workflows/` to understand implementation details — the docs
explain the what and why, but the code shows the how.

**Adoptable components** (from `docs/adapt.md` component map):

| Component | Key pattern worth adopting |
|-----------|--------------------------|
| `infra/bootstrap/` | Entra OIDC federation, Terraform state in blob storage |
| `infra/shared/` | VNet layout, AKS + supporting services |
| `infra/env/` | Per-environment Databricks + UC objects |
| `dagster/` | Asset factory, Pipes integration, dbt integration |
| `deploy/helm/` | Helm values with envsubst, run pod config |
| `deploy/k8s/` | SecretProviderClass pattern |
| `dbt/` | profiles.yml env var pattern, schema routing macro |
| `databricks/` | Asset Bundle with no job resources (Dagster submits via Pipes) |
| `.github/workflows/` | PR checks → deploy stage → promote prod sequence |
| `scripts/phases/` | Phase runner pattern for guided, self-verifying setup |
| `scripts/lib/common.sh` | Shared library: colored output, tf_plan_confirm_apply, wait_for_manual |
| `scripts/setup-env.sh` | .env scaffolding and Terraform output collection |
| `scripts/helm-upgrade.sh` | Helm deploy with envsubst |
| `scripts/bundle-deploy.sh` | Bundle deploy + permission grants |
| `scripts/smoke-test.sh` | Post-deploy validation via Dagster GraphQL |
| `scripts/stop.sh` / `start.sh` | Cost control |
| `justfile` | Task runner with dotenv-load, phase commands, dbt wrapper |

### Stage 3: Analyze incompatibilities

Compare what you found in both repos. For each POC component, determine one of:

- **Adopt as-is** — the target repo has nothing equivalent; copy and customize names/regions.
- **Adapt** — the target repo has something similar but different; merge the POC's pattern
  into the existing structure. Explain specifically what changes.
- **Skip** — the target repo already has a better or equivalent solution, or the component
  doesn't apply. Explain why.

For each "adapt" case, identify the specific conflict and recommend a resolution:

- **Different Terraform structure** — e.g., target uses a module registry or different
  state layout. Recommend where POC resources slot in.
- **Different CI system** — e.g., Azure DevOps instead of GitHub Actions. Map the workflow
  steps; the deploy *sequence* matters even if the syntax changes.
- **Existing Helm charts** — merge POC's values (especially run pod config) into existing
  chart configuration.
- **Existing dbt project** — adopt the env var pattern from `profiles.yml` and the
  `generate_schema_name` macro; leave existing models alone.
- **Different secrets management** — map the Key Vault + CSI driver pattern to whatever
  the target uses.
- **Ownership boundaries** — if another team owns workspaces or infrastructure, scope the
  plan to what this team controls.

Present the analysis as a clear table: component, recommendation (adopt/adapt/skip),
rationale, and any open questions.

### Stage 4: Generate the adoption plan

Produce a phased adoption plan and save it as `docs/adoption-plan.md` in the **target
repo** (not the POC repo).

Use the structure from `docs/adoption-plan-example.md`:

```
# Adoption plan: [descriptive title]

## Context
(team size, current state, what's driving this, key constraints)

## Principles
(3-5 guiding principles — "platform enables, teams consume" etc.)

## Team ownership map
(table: area, owner(s), scope, POC reference)

## Component decisions
(table: component, decision (adopt/adapt/skip), rationale)

## Phases

### Phase 0 — Decisions and security review (serial, blocks everything)
### Phase 1 — Platform build (parallel tracks)
  Track A: Infrastructure
  Track B: Databricks integration
  Track C: CI/CD & developer experience
  Track D: Security hardening
  Track E: Code patterns (Dagster + dbt)
### Phase 2 — Migration / integration (parallel, teams work independently)
### Phase 3 — Steady state

## Stage environment strategy
(pick from the options in the POC example)

## Developer experience
(what a developer's day looks like after adoption)

## Risks
(table: risk, mitigation)

## Open questions
(things that couldn't be determined from the repos alone)
```

Adapt this structure to the target team's situation — not every section applies, and
some teams need additional sections (e.g., compliance, data governance, cost modeling).

### Stage 5: Execute the adoption

Only proceed after the user approves the plan from Stage 4. This is where the actual
work happens — copying, adapting, and wiring up components.

**Execution principles:**

1. **Work phase by phase.** Don't jump ahead. Each phase builds on the previous one.
2. **Respect target repo conventions.** Adapted code should look like it belongs in the
   target repo — follow their naming, file layout, code style, and documentation patterns.
3. **Parametrize everything.** Never hardcode environment-specific values. Use the same
   pattern the target repo already uses (env vars, tfvars, Helm values, etc.).
4. **Test each component.** After copying/adapting a component, verify it works in the
   target repo's context (terraform validate, dbt parse, dagster check defs, etc.).
5. **Document what you changed.** For each adapted component, note what was changed from
   the POC and why, either in the adoption plan or in code comments where the divergence
   is non-obvious.

**For each adopted component:**

1. Copy the relevant files into the target repo at the agreed location.
2. Rename resources, variables, and references to match target conventions.
3. Update paths, imports, and cross-references.
4. Adapt configuration for the target's infrastructure (different resource names, regions,
   subscription IDs, etc.).
5. Wire up dependencies (if component A depends on component B's outputs, make sure
   the references are correct).
6. Validate: run the appropriate check command (terraform validate, dbt parse, etc.).

**When adapting scripts and phase runners:**

The phase runner pattern (`scripts/phases/`, `scripts/lib/common.sh`, `justfile`) is
worth adopting if the target repo needs a guided setup experience. Adapt the phases to
match what the target actually provisions — don't copy phases for resources that are
being skipped.

**Commits:** Make one commit per logical unit of adoption (e.g., "Adopt Terraform
bootstrap from POC", "Adapt Helm values for existing AKS cluster"). This keeps the
history reviewable and makes it easy to revert individual components.

## Guardrails

These come from the POC's CLAUDE.md and apply during execution:

- **No secrets in the repo.** Secrets live in the secrets manager. Committed files
  reference env vars, never values.
- **Nothing unique to one person or account is committed.** No personal handles,
  subscription IDs, IPs, or org names in tracked files.
- **Never run `terraform apply` or `helm upgrade` against prod** without explicit
  user approval.
- **Don't over-adopt.** If the target repo has a working solution for something, don't
  replace it with the POC's version just because it's there. Only adopt what adds value.

## Asking intake questions

Use the intake questions from `docs/adapt.md` § "Intake questions" but ask them
conversationally, not as a checklist. Group related questions together:

1. Start with team and organization (who's doing what)
2. Then existing infrastructure (what's already there)
3. Then existing codebase (what code exists)
4. Then requirements (environments, timeline, constraints)

Many answers will be obvious from reading the target repo — don't ask questions you
can answer yourself by reading the code. Focus questions on things that aren't in the
code: team structure, ownership boundaries, timeline, compliance constraints, and
strategic decisions.

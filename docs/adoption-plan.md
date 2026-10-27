# Adoption plan: POC → production

How to move from this POC to a production data platform supporting migration off
Synapse/ADF. The goal is to get a functioning system as fast as possible so data
engineers can begin migrating, then improve through observation.

## Context

- **Teams:** 5–10 DevOps, 10–20 data engineers, 20+ data scientists
- **Current state:** Mono-repo with some Dagster/dbt code but no infra provisioning or
  deployment automation. Existing Databricks sandbox set up by another team.
- **Databricks ownership:** Another team may own workspace provisioning; we own catalogs,
  schemas, and everything inside them. Assume we'll own it all eventually.
- **Migration:** Synapse Analytics + Azure Data Factory → Dagster + dbt + Databricks
- **Driver:** DE/DS velocity — they need a working platform to start migrating stored
  procedures and ADF pipelines into dbt models and Dagster assets.

## Principles

1. **Platform team enables, migration team consumes.** DevOps builds and operates the
   platform; DEs use it to migrate ELT; DSs validate outputs. The interface between
   them is: a code location template, a CI pipeline that deploys on merge, and a
   `profiles.yml` / env vars contract.
2. **Get the loop running first.** A DE should be able to write a dbt model, push a PR,
   and see it run in stage within the first sprint. Hardening and optimization follow.
3. **Adopt what fits, rewrite what doesn't.** The POC patterns (Helm values, bundle
   structure, Pipes extract, CI workflows) are starting points. Adapt to corporate
   constraints; don't force-fit.
4. **Own what you operate.** If we operate Databricks day-to-day, we should own its
   Terraform. Negotiate this early — shared ownership of Terraform state creates merge
   conflicts and blame gaps.

## Team ownership map

Assign each area to a DevOps engineer (or pair). They own it, improve it, and are the
escalation point for DEs who hit issues in that area.

| Area | Owner(s) | Scope | POC reference |
|------|----------|-------|---------------|
| **Terraform & Azure infra** | 1–2 DevOps | VNet, AKS, Postgres, Key Vault, ACR, ADLS, managed identities, RBAC. Adapt `infra/` to corporate subscription, private endpoints, naming policies. | `infra/`, [architecture](architecture.md) |
| **Databricks provisioning** | 1 DevOps | Workspaces (if we own them), catalogs, schemas, volumes, grants, access connectors, storage credentials, service principals. Work with the team that currently owns the sandbox. | `infra/env/databricks.tf`, [Unity Catalog](concepts/unity-catalog.md) |
| **AKS & Dagster operations** | 1–2 DevOps | Helm chart, node sizing, autoscaler, run concurrency, monitoring, pod scheduling, image optimization. | `deploy/helm/`, [Helm deployments](concepts/helm-deployments.md), [improvements](improvements.md) |
| **CI/CD & developer experience** | 1 DevOps | GitHub Actions (or Azure DevOps), ARC runners, PR checks, deploy/promote pipelines, local dev workflow, branch strategy for mono-repo. | `.github/workflows/`, [CI/CD](concepts/cicd.md) |
| **Security & networking** | 1 DevOps + Security team | Private endpoints, RBAC scoping, workload identity, secrets rotation, image scanning, network policies. | [corporate-migration](corporate-migration.md), [improvements](improvements.md) |
| **Dagster code patterns** | 1 senior DE + 1 DevOps | Code location structure, asset patterns, resource configuration, Pipes integration, dbt integration. Template that other DEs clone. | `dagster/`, [Dagster Pipes](concepts/dagster-pipes.md), [asset factory](concepts/asset-factory.md) |
| **dbt project structure** | 1 senior DE | Project layout, model naming, source definitions, testing strategy, profiles/env var contract. | `dbt/` |
| **Migration coordination** | 1 DE lead | Prioritize which ADF pipelines / Synapse sprocs to migrate first. Track progress, resolve blockers between DE pairs. | — |

## Phases

### Phase 0 — Security review & decisions (weeks 1–2, serial)

Nothing moves into the corporate subscription without Security sign-off on the pattern.
This is the critical path — start it immediately.

**Deliverables:**
- [ ] Security review of [architecture.md](architecture.md) and [corporate-migration.md](corporate-migration.md)
- [ ] Decision: private endpoints required from day one, or phased in?
- [ ] Decision: who owns Databricks workspace provisioning? (us, platform team, shared?)
- [ ] Decision: CI system — GitHub Actions + ARC, or Azure DevOps? (if corporate is on ADO, translate workflows)
- [ ] Decision: mono-repo structure — where does infra/, dagster/, dbt/, databricks/ live relative to existing code?
- [ ] Decision: environments — stage + prod, or dev + stage + prod? (dev = per-developer or shared sandbox?)
- [ ] Decision: Dagster OSS or Dagster+ hybrid? (POC proves OSS; Dagster+ is viable if managed control plane is preferred)
- [ ] RBAC plan: which roles, which scopes, which identities (see [Azure RBAC](concepts/azure-rbac.md))
- [ ] Network plan: required egress destinations, firewall rules (see corporate-migration.md § egress control)

**Parallel prep (DevOps, doesn't need Security):**
- [ ] Fork/adapt POC `infra/bootstrap/` for the corporate subscription (naming, region, tenant)
- [ ] Inventory existing Databricks sandbox: workspaces, catalogs, compute, principals, grants
- [ ] Inventory ADF pipelines and Synapse sprocs to estimate migration scope and prioritize

### Phase 1 — Platform build (weeks 2–5, parallel tracks)

Security decisions unblock these tracks. All five run in parallel.

#### Track A: Infrastructure (DevOps — Terraform & Azure)

Adapt the POC's `infra/` stacks to the corporate subscription.

- [ ] Apply `bootstrap/` (Entra app, federated credentials, state storage)
- [ ] Apply `shared/` (VNet, AKS, Postgres, Key Vault, ACR, ADLS)
  - Private endpoints if required by Phase 0 decision (add `modules/private-endpoints`)
  - Corporate naming conventions and tags (update `conventions.md`)
  - Attach to existing VNet/subnets if corporate provides them
- [ ] Apply `env/` for stage (catalogs, schemas, grants, service principals, managed identities)
- [ ] Apply `env/` for prod (same shape, different tfvars)
- [ ] `scripts/setup-env.sh collect-tf` to capture outputs
- [ ] Verify: `scripts/verify.sh 1` and `scripts/verify.sh 2` pass

#### Track B: Databricks integration (DevOps — Databricks)

Work with the team that owns the sandbox to establish boundaries.

- [ ] Attach existing workspaces to the (existing) Unity Catalog metastore, or confirm already attached
- [ ] Provision `stage` and `prod` catalogs with `ISOLATED` workspace bindings (see [improvements](improvements.md))
- [ ] Create schemas: `bronze`, `silver`, `gold` (add gold if DSs need it)
- [ ] Create landing volumes per schema
- [ ] Create storage credentials and external locations pointing to ADLS
- [ ] Create service principals (`sp-dagster-stage`, `sp-dagster-prod`) with least-privilege grants
- [ ] Set up IP access lists for AKS egress and corporate network
- [ ] Deploy the Databricks Asset Bundle (`scripts/bundle-deploy.sh stage`)
- [ ] Decision: serverless compute, or classic clusters? (corporate may require VNet-injected classic)

#### Track C: CI/CD & developer experience (DevOps)

The most impactful track for DE velocity — this is what makes "push a PR, see it run"
possible.

- [ ] Adapt CI workflows to the mono-repo (path filters so dbt-only changes don't rebuild the image)
- [ ] Set up ARC runners (or ADO agents) inside AKS
- [ ] PR checks: `dbt parse`, `dg check defs`, linting, unit tests
- [ ] Deploy-stage pipeline: image build → Helm upgrade → bundle deploy → smoke test
- [ ] Promote-prod pipeline: environment gate → same image SHA → prod
- [ ] **Local dev workflow doc**: how a DE runs dbt locally against stage, how they test a Dagster asset
  - Option: shared dev workspace with per-user catalogs (`dev_<username>`)
  - Option: Dagster `materialize` from CLI against stage (read-only for most DEs)
- [ ] Branch strategy: trunk-based (this POC) vs feature branches with per-branch preview environments
- [ ] Secrets: set up Key Vault secrets, SecretProviderClass, CI environment variables

#### Track D: Security hardening (DevOps + Security)

Runs in parallel with Tracks A–C; may produce requirements that modify them.

- [ ] Private endpoints for Postgres, Key Vault, ACR, ADLS (if decided in Phase 0)
- [ ] Private AKS cluster (if required — changes CI runner access pattern)
- [ ] Scope CI SP RBAC to resource groups (see [improvements](improvements.md))
- [ ] Workload identity federation for Dagster pods → Databricks (drop SP secret from Key Vault)
- [ ] Image scanning in CI (Trivy, Defender for Containers)
- [ ] Secrets scanning (gitleaks or similar in PR checks)
- [ ] Network policies on AKS namespaces
- [ ] Entra auth for Postgres (replace password auth)
- [ ] CODEOWNERS for `infra/` (require DevOps review)

#### Track E: Dagster & dbt patterns (senior DE + DevOps)

Define the patterns DEs will use to migrate. This track produces the **template** that
Phase 2 scales.

- [ ] Code location structure for the mono-repo (one location? one per domain? per team?)
  - Recommendation: start with one, split when it gets slow to load
- [ ] Asset naming convention: `raw_<source>`, `bronze_<source>`, `silver_<entity>`
- [ ] dbt project structure: one project or multiple? How to handle 100+ models?
  - Sources: one `sources.yml` per source system (ADF pipeline → source)
  - Models: `models/bronze/<source>/`, `models/silver/<domain>/`
- [ ] Resource configuration: how assets get Databricks credentials, SQL warehouse path, catalog name
- [ ] Pipes extract pattern: generalize the POC's asset factory for more source types
  - API sources (the POC pattern)
  - ADLS file sources (landing zone from other systems)
  - Synapse/SQL Server sources (if direct extraction is needed during migration)
- [ ] Testing strategy: dbt tests, Dagster asset checks, integration tests
- [ ] Scheduling: which assets run on schedule vs. sensor-triggered
- [ ] Write a "Migration cookbook" doc: for each ADF pipeline type (Copy Activity, Data Flow,
  Stored Procedure), the equivalent Dagster/dbt pattern

### Phase 2 — Migration (weeks 5+, parallel)

The platform is running. DEs begin migrating. DSs validate.

#### Migration workflow (per ADF pipeline / Synapse sproc)

1. DE picks next item from the prioritized backlog
2. DE writes dbt model(s) and/or Dagster asset following the Track E patterns
3. DE pushes PR → CI runs checks → deploys to stage on merge
4. DE verifies output in stage catalog (compare with Synapse/ADF output)
5. DS validates business logic and data quality
6. Promote to prod via environment gate
7. Decommission old ADF pipeline / Synapse sproc

#### Parallel activities during migration

- **DevOps — observe and improve:** monitor run failures, OOM kills, queue depth,
  warehouse costs. Tune node pool, concurrency limits, resource requests. Items from
  [improvements.md](improvements.md) get prioritized based on what's actually failing.
- **DevOps — scaling:** enable cluster autoscaler, add run node pool, configure
  `QueuedRunCoordinator` as concurrent runs increase.
- **DS — validation dashboards:** build reporting on migrated vs. legacy data to
  catch regressions.
- **DE lead — migration tracking:** which pipelines are migrated, in-progress, blocked.

### Phase 3 — Steady state (ongoing)

- Synapse/ADF decommissioned (or reduced to only what hasn't migrated)
- Dagster schedules run all ELT
- Monitoring and alerting in place (Container Insights or Prometheus)
- Runbooks for common failures (OOM, disk pressure, Databricks quota limits)
- Cost tracking against budget (see [costs.md](costs.md) for the model)
- Regular review of [improvements.md](improvements.md) backlog

## Stage environment with real data

The POC uses identical environments with trivial data. For migration, stage needs real
(or representative) data so DEs can validate transformations.

**Options (pick one or combine):**

| Approach | Pros | Cons |
|----------|------|------|
| **Stage reads prod data (read-only cross-catalog)** | No duplication; always current. Stage catalog grants `READ` on prod's external location. | DEs can see prod PII; need column masking or row filters in UC. |
| **Nightly prod → stage copy** | Stage has yesterday's data; no prod access needed. | Storage cost doubles; copy job to maintain. |
| **Subset via views** | Small, fast, cheap. Stage has views/tables sampling N% of prod. | May miss edge cases; views need maintenance. |
| **Shared external location, separate catalogs** | Both catalogs point to the same ADLS containers (different schemas). Stage writes are isolated; reads see prod data. | Requires careful grants to prevent stage writes to prod tables. |

**Recommendation:** Start with **shared external location + separate catalogs**. Stage
and prod catalogs share the same ADLS storage, but UC grants enforce that stage compute
can only write to stage schemas. DEs see prod bronze data in stage for validation without
a copy job. Isolate via `ISOLATED` workspace-catalog bindings and schema-level grants.

Add column masking / row filters in Unity Catalog if PII restrictions apply.

## Developer experience

What a data engineer's day looks like:

```
1. Clone the mono-repo, run setup script (installs tools, scaffolds .env)
2. Write a dbt model in models/silver/my_entity.sql
3. Test locally:  dbt build --target dev --select my_entity
   (dev target hits a shared dev workspace or their personal catalog)
4. Push PR → CI validates (dbt parse, lint, Dagster check defs)
5. Merge → deploy-stage runs automatically
6. Verify in Databricks: query stage.silver.my_entity
7. Approve promote-prod → production
```

**What DEs should NOT need to do:** touch Terraform, Helm values, Kubernetes, Docker,
or CI workflow files. Those are the platform team's domain.

**What DEs should own:** dbt models, Dagster asset definitions, `sources.yml` entries,
dbt tests, and their own scheduling config (asset metadata / sensors).

## Risks

| Risk | Mitigation |
|------|------------|
| Security review blocks for weeks | Start Phase 0 immediately; present architecture.md and corporate-migration.md in the first meeting, not as a request for review but as a proposal with specific questions |
| Databricks ownership unclear | Document the boundary in writing: "we own catalogs and below; workspace provisioning is TBD." Get sign-off from both teams. |
| DEs blocked waiting for platform | Track E (patterns) can start on the existing sandbox while Tracks A–D build production infra. Have DEs prototype migrations in the sandbox. |
| Mono-repo CI becomes slow | Path filters in CI (only rebuild what changed). Consider splitting to per-domain code locations if load time exceeds 60s. |
| Stage data doesn't match prod | Use shared external location so stage reads the same physical data. Validate with row counts and checksums during migration. |
| AKS node capacity with 20+ concurrent runs | Plan for this early (Track A). Cluster autoscaler + dedicated run node pool + `QueuedRunCoordinator`. |
| Dagster Prefect acquisition uncertainty | OSS continues under same license; no action needed. Note for leadership. ([Decision #15](decisions.md)) |

## Open questions

- [ ] Does the corporate subscription have Azure Policy restrictions that would block any POC resources? (e.g., deny public endpoints, require specific SKUs, mandatory tags)
- [ ] Is there an existing VNet we must attach to, or do we provision our own?
- [ ] What's the Synapse/ADF pipeline count? (10? 100? 500? — determines migration timeline)
- [ ] Do DEs need a personal dev environment, or is a shared dev workspace sufficient?
- [ ] Will data scientists need write access to a `gold` layer, or only read access to `silver`?
- [ ] Is there a data classification / PII policy that affects what stage can see?
- [ ] Budget for steady-state Azure + Databricks costs?

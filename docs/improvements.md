# Improvements

Tracks TODOs, optimizations, and hardening work across the project.
Items are categorized and roughly prioritized within each section.
Mark items ~~strikethrough~~ when resolved (with a note on the resolution).

## Security & access control

### Unity Catalog workspace-catalog isolation
- **Status:** TODO
- **Problem:** Both stage and prod workspaces can see both catalogs. A stage workspace user could read or write prod data if they have catalog-level grants.
- **Fix:** Bind each catalog exclusively to its workspace using `ISOLATED` mode:
  ```
  databricks workspace-bindings set-bindings catalog stage --json '{"bindings": [{"workspace_id": <stage_ws_id>, "binding_type": "BINDING_TYPE_READ_WRITE"}]}'
  databricks workspace-bindings set-bindings catalog prod  --json '{"bindings": [{"workspace_id": <prod_ws_id>,  "binding_type": "BINDING_TYPE_READ_WRITE"}]}'
  ```
  This can be done in Terraform (`databricks_workspace_binding` resource) or via `infra/env` with per-workspace variables.
- **See also:** [Decision #13](decisions.md) (one metastore, catalog-per-env)

### Scope CI service principal RBAC to resource groups
- **Status:** TODO (deferred from guide step 5.7)
- **Problem:** The GitHub OIDC SP (`app-dagster-github`) has Contributor + User Access Administrator at subscription scope. Should be scoped to the four dagster resource groups (`rg-dagster-tfstate`, `rg-dagster-shared`, `rg-dagster-stage`, `rg-dagster-prod`).
- **Complexity:** The role assignments live in `infra/bootstrap/main.tf` (lines 99–109), which runs before the resource groups exist. Either move them to `infra/shared`/`infra/env` or do a two-pass bootstrap.
- **See also:** [Azure RBAC concept](concepts/azure-rbac.md)

### CODEOWNERS
- **Status:** TODO (deferred from guide step 5.7)
- **Problem:** No code review requirements. `.github/CODEOWNERS.example` exists but isn't active.
- **Fix:** Copy to `.github/CODEOWNERS`, fill in team handles, enable branch protection on `main`.

### Databricks CI/CD auth: switch to GitHub OIDC
- **Status:** TODO
- **Problem:** `azure-cli` auth requires the OIDC SP to be manually added as a Databricks workspace user, and piggybacks on the Azure Login session.
- **Workaround:** Manually add the SP to each workspace via `databricks service-principals create`.
- **Fix:** Switch to [Databricks workload identity federation](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/auth/provider-github) (`DATABRICKS_AUTH_TYPE: github-oidc`). Uses GitHub's OIDC token directly with Databricks — no Azure Login needed for bundle steps.

## Performance & resources

### Run pod memory sizing (OOM history)
- **Status:** Monitor — currently 512Mi, measured usage ~320Mi
- **Problem:** Run pods were originally killed with OOMKilled at 512Mi. Resources were raised to 1Gi, then 2Gi, but 2Gi requests starved the single node during rolling updates. Cut back to 512Mi after `kubectl top pods` showed ~320Mi actual usage.
- **Risk:** The original OOM happened at 512Mi, so watch `kubectl top pods` and run-pod exit codes. If OOMKilled returns, raise the user-deployment limit (which propagates to run pods via `includeConfigInLaunchedRuns`). See [Decision #17](decisions.md).
- **Proper fix:** Right-size from measurements. For complex pipelines, consider `k8s_job_executor` (one pod per step). When run pod needs diverge from the gRPC server, decouple by setting `runK8sConfig.containerConfig.resources` on the user deployment.

### Node disk pressure at 32GB
- **Status:** TODO
- **Problem:** Each image pull is ~2GB; the 32GB OS disk fills with layers and failed pod artifacts. Pods stuck Pending with `disk-pressure` taint.
- **Workaround:** Delete failed pods, manually untaint the node.
- **Fix:** Increase `os_disk_size_gb` from 32 to 64 in `infra/shared/main.tf`. Also reduce image size (strip dev deps, multi-stage build) and consider an image pre-pull DaemonSet.

### Azure serverless compute lacks FUSE for UC Volumes
- **Status:** Mitigated (SDK workaround)
- **Problem:** `FileNotFoundError` for Pipes context files on `/Volumes/` paths. Azure serverless compute does not mount UC Volumes via FUSE.
- **Workaround:** Custom `_SdkContextLoader` and `_SdkMessageWriter` in `entrypoint.py` use `WorkspaceClient().files` (REST API) instead of FUSE.
- **Proper fix:** Switch back to built-in `PipesUnityCatalogVolumes*` classes if/when Databricks adds FUSE support to Azure serverless.

## Compatibility

### SQLAlchemy pinned below 2.1
- **Status:** Mitigated (version pin)
- **Problem:** `dagster-postgres` NOTIFY SQL fails with psycopg v3's server-side parameter binding. SQLAlchemy 2.1 changed the default driver from psycopg2 to psycopg v3.
- **Workaround:** Pin `sqlalchemy>=2.0,<2.1` in `dagster/pyproject.toml`.
- **Proper fix:** Wait for dagster-postgres to specify `postgresql+psycopg2://` in its connection strings, then drop the pin.

## Scaling

Items to investigate before running concurrent workloads. Not blocking the POC.

### Node pool and autoscaling
- **Status:** TODO
- Current: single node (D2as_v6, 2 vCPU, 8GB RAM), no autoscaler
- Plan: enable cluster autoscaler (`min_count`/`max_count`), consider a dedicated "dagster-runs" user node pool
- Check Azure CNI subnet sizing (`/24` = 254 pod IPs) against max concurrent pods

### Run concurrency and queuing
- **Status:** TODO
- Current: no run queue limits — daemon launches every run immediately
- Plan: configure `QueuedRunCoordinator` with `max_concurrent_runs`, tag-based limits for expensive Databricks jobs
- Helm path: `dagsterDaemon.runCoordinator`

### Per-asset resource overrides
- **Status:** TODO
- Current: all run pods get the same resource limits
- Plan: use `dagster-k8s/config` tags on individual assets for per-asset CPU/memory, or switch to `k8s_job_executor` for step-level pod isolation

### AKS tier
- **Status:** TODO
- Current: Free (no SLA, control plane may be slow under load)
- Plan: Standard tier for production uptime SLA

### Pod scheduling
- **Status:** TODO
- Current: everything on one node, no anti-affinity or disruption budgets
- Plan: PDBs for daemon/webserver, anti-affinity to spread across nodes

## Setup efficiency

### Parallel provisioning and pre-flight validation
- **Status:** TODO
- **Problem:** The phase runner executes everything serially: Phase 2 (stage) must fully complete before Phase 4 (prod) begins, and within Phase 2, steps like Docker image build block on Terraform and manual steps they don't depend on. A full setup takes ~90 minutes wall clock, much of it waiting.
- **Opportunity:** The dependency graph allows significant parallelism:
  - **Docker image build** only needs ACR (Phase 1). It can run alongside the entire Phase 2 TF apply + manual steps chain, saving 2–3 minutes.
  - **After metastore creation**, prod TF apply is independent of stage deploy. Both environments' infra could provision in parallel.
  - **Within each env**, SecretProviderClass, Key Vault secrets, and bundle deploy are independent of each other and could run in parallel after TF apply completes. Helm waits for all three.
  - **GitHub App creation** (Phase 5) is pure browser clicking with no cloud dependency — it could be prompted during Phase 0.
- **Approach:** Validate before deploying, then deploy in parallel. The phases currently interleave validation with provisioning (create a resource, check it, create the next). A better model:
  1. **Pre-flight**: verify prerequisites, check resource availability (region capacity, provider registration, quota), validate all Terraform and configuration up front
  2. **Confirm**: show the user what will be created and the estimated cost
  3. **Provision**: run independent steps in parallel (backgrounded subshells or `&` with `wait`)
  4. **Verify**: confirm everything is healthy
- **Trade-off:** The current serial approach catches problems early — a broken stage stops you before spending money on prod. Parallel provisioning should be opt-in (e.g. `just phase 2 --with-prod` or a `just setup-all` fast path) with the serial path remaining the default for first-time users.
- **See also:** Phase reorganization — merging Phase 3 (dbt verification) into Phase 2, and splitting Phase 0 (workstation vs cloud bootstrap) would also improve the flow.

## Monitoring & observability

### No monitoring stack
- **Status:** TODO
- Current: manual `kubectl` checks
- Plan: Azure Container Insights or Prometheus + Grafana; alerts for OOM kills, disk pressure, pending pods, run queue depth
- Databricks side: system tables export, usage dashboards

## CI/CD

### Secrets scanning / SBOM / image signing
- **Status:** TODO
- Add steps to `pr-checks.yml` / `deploy-stage.yml` for secrets scanning, SBOM generation, and image signing.

## Corporate migration

Infrastructure changes needed when moving from a personal subscription into corporate Security/IT/Networking constraints. The design goal was that every item below is **infrastructure config**, not application code.

See [corporate-migration.md](corporate-migration.md) for the full constraint-response table and IT handover checklist.

Key items:
- Private AKS cluster + private endpoints for ACR, Key Vault, Postgres, Storage, Databricks
- Egress control via NAT Gateway or UDR to corporate firewall
- Separate subscriptions/clusters per environment
- Self-hosted CI runners inside the VNet (ARC already in place — may need Container Apps or VMSS in corporate network)
- Replace SP secrets with workload identity federation
- Classic Databricks compute if serverless is forbidden (VNet-injected workspaces)

### Two things the POC did not exercise
1. **Private DNS resolution from pods.** `privatelink.*.net` zones must be linked to the AKS VNet. Budget a day.
2. **Private image pull.** AKS kubelet → ACR over private endpoint; needs ACR private DNS zone and `AcrPull` role.

## Resolved

### ~~AKS IP whitelisting adds ~4 min to deploy workflows~~
- **Resolution:** Self-hosted runners via ARC run inside AKS — direct API server access, no IP whitelisting needed. See [Decision #16](decisions.md).

### ~~Databricks IP access list blocks CI runners~~
- **Resolution:** ARC runner pods egress through the AKS public IP, already on the Databricks workspace allow list.

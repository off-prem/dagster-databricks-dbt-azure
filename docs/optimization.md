# Optimization

Tracks performance issues, resource constraints, and scaling improvements.
Add entries as they're discovered — each one should explain the problem,
the current workaround (if any), and the proper fix.

## Active issues

### Run pod OOM at 512Mi
- **Discovered:** Phase 2.11 smoke test
- **Symptom:** Run pods killed with OOMKilled before Databricks job is submitted
- **Cause:** The multiprocess executor spawns a parent process + child subprocess per step, each loading the full code location (including dbt parse via `DAGSTER_DBT_PARSE_PROJECT_ON_LOAD`). Two processes exceed 512Mi.
- **Workaround:** Set user deployment `resources` to 1Gi in per-env values files. The Dagster Helm chart bakes user deployment resources into `DAGSTER_CLI_API_GRPC_CONTAINER_CONTEXT`, which deep-merges on top of the run launcher config — so run launcher `resources` and `runK8sConfig` are both overridden. The user deployment resources control both the code server pod and run pods.
- **Proper fix:** Profile actual memory usage with `kubectl top pods` once running, right-size the limit. For complex pipelines, consider the `k8s_job_executor` (one pod per step) instead of multiprocess.

### Node disk pressure at 32GB
- **Discovered:** Phase 2 debugging (repeated image rebuilds)
- **Symptom:** Pods stuck Pending with `node.kubernetes.io/disk-pressure` taint
- **Cause:** Each image pull is ~2GB; the 32GB OS disk fills up with layers and failed pod artifacts
- **Workaround:** Delete failed pods, manually untaint the node
- **Proper fix:** Increase `os_disk_size_gb` from 32 to 64 in `infra/shared/main.tf:168`. Also reduce image size (strip dev deps, use multi-stage build) and consider an image pre-pull DaemonSet.

### SQLAlchemy pinned below 2.1
- **Discovered:** Phase 2.11 smoke test
- **Symptom:** `dagster-postgres` NOTIFY SQL fails with psycopg v3's server-side parameter binding (`$1` syntax error)
- **Cause:** `dagster-postgres` uses bare `postgresql://` connection URLs (no `+psycopg2` driver suffix). SQLAlchemy 2.1 changed the default driver from psycopg2 to psycopg v3. Legacy NOTIFY code in `event_log.py:202` passes parameters that psycopg3 tries to bind server-side, which PostgreSQL rejects.
- **Workaround:** Pin `sqlalchemy>=2.0,<2.1` in `dagster/pyproject.toml`
- **Proper fix:** Wait for dagster-postgres to specify `postgresql+psycopg2://` in its connection strings or remove the legacy NOTIFY code. Then drop the pin.

### Azure serverless compute lacks FUSE for UC Volumes
- **Discovered:** Phase 2.11 smoke test
- **Symptom:** `FileNotFoundError: context.json` at `/Volumes/.../tmp/.../context.json` when Dagster Pipes context loader calls `open()`. Affects both `spark_python_task` and `notebook_task` on serverless.
- **Cause:** Azure Databricks serverless compute (standard access mode) does not mount `/Volumes/` via FUSE. The built-in `PipesUnityCatalogVolumesContextLoader`/`MessageWriter` use `open()` on FUSE paths. See [standard compute limitations](https://learn.microsoft.com/en-us/azure/databricks/compute/standard-limitations).
- **Workaround:** Custom `_SdkContextLoader` and `_SdkMessageWriter` in `entrypoint.py` that use `WorkspaceClient().files` (REST API) instead of FUSE. `rest_api.py` also uses the SDK for file writes. The notebook inherits the SP identity via `WorkspaceClient()` (no explicit credentials).
- **Proper fix:** If Databricks adds FUSE support to Azure serverless, switch back to the built-in `PipesUnityCatalogVolumes*` classes. Alternatively, investigate `spark_python_task` + `environment_key` (cleaner script format, explicit dependencies) once FUSE or an official SDK-based Pipes transport is available.

### AKS IP whitelisting adds ~4 min to deploy workflows
- **Discovered:** Phase 5 deploy-stage debugging
- **Symptom:** `az aks update` to add/remove the GitHub runner IP takes ~2 min each way, and the API server may not be reachable for up to 2 min after the update completes (propagation delay).
- **Workaround:** A retry loop polls `kubectl cluster-info` after the IP update until the API server responds (up to 3 min), then proceeds with helm. The cleanup step restores original IPs with `if: always()`.
- **Proper fix:** Use [`az aks command invoke`](https://learn.microsoft.com/en-us/azure/aks/access-private-cluster) to run helm/kubectl through the Azure API, bypassing the network entirely. This is Microsoft's recommended approach for CI/CD with restricted AKS clusters. Requires packaging values files for upload via `--file`. For corporate environments, self-hosted runners on the VNet eliminate the problem entirely (see [corporate-migration.md](corporate-migration.md)).

### Databricks CI/CD uses azure-cli auth instead of github-oidc
- **Discovered:** Phase 5 deploy-stage debugging
- **Symptom:** Not a bug — the current setup works. But `azure-cli` auth requires the OIDC SP to be manually added as a Databricks workspace user, and piggybacks on the Azure Login session.
- **Workaround:** Manually add the SP to each workspace via `databricks service-principals create`.
- **Proper fix:** Switch to [Databricks workload identity federation](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/auth/provider-github) (`DATABRICKS_AUTH_TYPE: github-oidc`). This uses GitHub's OIDC token directly with Databricks, requires no Azure Login for bundle steps, and is [Databricks' recommended approach](https://learn.microsoft.com/en-us/azure/databricks/developers/best-practices) for CI/CD. Setup: create a federation policy on the Databricks SP with issuer `https://token.actions.githubusercontent.com` and subject scoped to the repo/environment.

## Scaling considerations

Items to investigate before running concurrent workloads. Not blocking the POC.

### Node pool and autoscaling
- Current: single node (D2as_v6, 2 vCPU, 8GB RAM), no autoscaler
- Plan: enable cluster autoscaler (`min_count`/`max_count`), consider a dedicated "dagster-runs" user node pool separate from the system pool
- Check Azure CNI subnet sizing (`/24` = 254 pod IPs) against max concurrent pods

### Run concurrency and queuing
- Current: no run queue limits — daemon launches every run immediately
- Plan: configure `QueuedRunCoordinator` with `max_concurrent_runs` based on node capacity, tag-based limits for expensive Databricks jobs
- Helm path: `dagsterDaemon.runCoordinator`

### Per-asset resource overrides
- Current: all run pods get the same resource limits from `values.base.yaml`
- Plan: use `dagster-k8s/config` tags on individual assets to set per-asset CPU/memory, or switch to `k8s_job_executor` for step-level pod isolation

### AKS tier
- Current: Free (no SLA, control plane may be slow under load)
- Plan: Standard for production uptime SLA

### Pod scheduling
- Current: everything on one node, no anti-affinity or disruption budgets
- Plan: PDBs for daemon/webserver, anti-affinity to spread across nodes when autoscaler adds them

### Monitoring
- Current: manual `kubectl` checks
- Plan: Azure Container Insights or Prometheus + Grafana, alerts for OOM kills, disk pressure, pending pods, run queue depth

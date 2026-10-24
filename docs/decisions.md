# Decisions (ADR-lite)

Settled choices. Don't re-litigate during the build; add a new entry if something must change.

| # | Decision | Why | Revisit when |
|---|---|---|---|
| 1 | Dagster OSS via Helm on AKS, not Dagster+ | The POC is specifically about self-hosting on AKS; Dagster+ hybrid would remove the thing being proven. | Company prefers managed control plane. |
| 2 | One AKS cluster, two namespaces | Cost. Env boundary is already fully expressed in Helm values; moving to two clusters is a kube-context change. | Corporate requires cluster-level isolation. |
| 3 | Azure Database for PostgreSQL Flexible (B1ms) over in-cluster Postgres | Durable Dagster state across cluster delete/recreate; matches what IT will expect; ~$4/mo stopped. | Never for this POC. |
| 4 | Serverless Databricks compute only (SDP + SQL warehouse) | $0 idle, no VM cost, no cluster plane networking to design yet. | Corporate forbids serverless or needs classic SCC in their VNet. |
| 5 | SDP (Spark Declarative Pipelines) for bronze, triggered via Databricks SDK `pipelines.start_update` — not Pipes | Pipes targets Python/notebook tasks; a pipeline update is a first-class API call and needs no Pipes bootstrap. | A Python ingestion task appears; then use `PipesDatabricksServerlessClient` with the `ops.dagster_pipes` volume. |
| 6 | dbt runs inside the Dagster run pod via `dagster-dbt`, against a serverless SQL warehouse | Simplest lineage integration; one image. | dbt runtime grows; move to Databricks dbt task launched via Pipes. |
| 7 | Databricks Asset Bundles for all Databricks code; Terraform for Databricks *infra* (catalog, SP, warehouse, grants) | Bundles are the native deploy unit for code; Terraform for long-lived objects. Clear line: if it has a `-t <env>` target, it's a bundle. | — |
| 8 | Terraform for Azure; Helm for Dagster; no Terraform-managed Helm releases | Keeps image promotion in CI, not in Terraform state. | — |
| 9 | GitHub + Actions + Environments | Free, OIDC to Azure, environment gates built in. | Company is on Azure DevOps — translate workflows; structure unchanged. |
| 10 | Public-but-gated control planes; no private endpoints/VPN in POC | ~$300/mo saved; zero application-code impact when added later. See [corporate-migration.md](corporate-migration.md). | Moving into corporate network. |
| 11 | Databricks SP with OAuth M2M secret in Key Vault | Works everywhere today. Upgrade path: federate `id-dagster-<env>` as the SP identity, drop the secret. | Phase 6 or corporate. |
| 12 | Managed-VNet Databricks workspaces (no VNet injection) | Serverless doesn't need it; VNet injection matters for classic compute, which isn't used. Subnets reserved anyway. | Classic compute or corporate requirement. |
| 13 | One Unity Catalog metastore, catalogs `stage`/`prod` | UC is one metastore per region; env isolation is at catalog level, which is also how corporate UC deployments usually work. | Company already has a metastore — attach workspaces to it. |
| 14 | Region `eastus2` | Serverless SQL/SDP availability and price. | Company region. |
| 15 | Dagster is now owned by Prefect (acquisition July 2026); OSS continues under same license, Dagster+ continues | No action; noted for IT questions. | Roadmap announcements. |

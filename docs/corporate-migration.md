# Corporate migration

What changes when this moves from a personal subscription into the company's Security/IT/Networking
constraints. The design goal of the POC was that every row below is **infrastructure config**, not
application code.

## Expected constraints and responses

| Constraint | Change | Where | App impact |
|---|---|---|---|
| No public control-plane endpoints | Private AKS cluster; private endpoints + private DNS zones for ACR, Key Vault, Postgres, Storage; Databricks front-end Private Link, `public_network_access_enabled = false` | `infra/shared`, `infra/env`, new `modules/private-endpoints` | None. Hostnames unchanged; DNS resolves privately. |
| Access via corporate network only | Remove authorized-IP ranges and IP access lists; rely on VPN/ExpressRoute/Bastion the company provides | `infra/` | None. |
| Private image registry | ACR Premium (for PE), or company's registry | `infra/shared`, Helm `image.repository` | None. |
| Egress control | NAT Gateway or UDR to company firewall on `snet-aks`; allowlist Databricks, PyPI (or internal mirror), ACR | `modules/aks` outbound type | Possibly pin PyPI mirror in Dockerfile. |
| Separate subscriptions per env | `infra/env` applied with a different `subscription_id`; `shared` split into hub items (ACR, DNS) and per-env items (Postgres becomes per env) | `infra/` backends + providers | None. |
| Separate AKS cluster per env | Second cluster from the same module; Helm context changes | `modules/aks`, CI `az aks get-credentials` | None. |
| Classic Databricks compute / no serverless | VNet-injected workspaces, Secure Cluster Connectivity, NAT; submit the extract task on classic compute instead of serverless (add a cluster spec to the Pipes task); SQL warehouse Pro | `infra/env`, `dagster/src/poc/assets/extract.py` | Task spec in the extract asset; the Pipes FUSE workaround may no longer be needed. |
| Existing Unity Catalog metastore | Skip metastore creation; attach workspaces; request catalogs | Guide step 2.3 | None. |
| Existing identity standards | Replace SP secret with workload-identity federation to the Databricks SP; Entra auth for Postgres | Key Vault secrets removed; Helm env | Minor: auth type in `assets/extract.py` and `dbt/profiles.yml`. |
| CI must run inside the network | Already satisfied for deploys: [ARC](tools/arc.md) runners run inside AKS. Make `pr-checks` self-hosted too, or use Azure DevOps agents | `.github/workflows` `runs-on` | None. |
| Logging/monitoring mandates | Container Insights / Log Analytics, Databricks system tables export, Dagster → OTEL | `infra/`, Helm | None. |
| Tagging/naming/policy (Azure Policy) | Adjust [conventions.md](conventions.md); policy may require specific SKUs, encryption, or deny public access (which this design already tolerates) | `infra/` | None. |
| Secrets scanning / SBOM / image signing | Add steps to `pr-checks.yml` / `deploy-stage.yml` | CI | None. |

## The two things the POC did not exercise
1. **Private DNS resolution from pods.** `privatelink.azuredatabricks.net`, `privatelink.vaultcore.azure.net`, etc. must be linked to the AKS VNet. Symptom when wrong: pods resolve public IPs and get 403/timeout. Budget a day.
2. **Private image pull.** AKS kubelet → ACR over PE; needs the ACR private DNS zone linked and the `AcrPull` role. Symptom: `ImagePullBackOff`.

## Hand-over checklist for IT/Security
- Architecture: [architecture.md](architecture.md) (public-vs-gated table shows the intended private posture).
- Identity: no long-lived cloud secrets in CI; one SP secret per env in Key Vault with documented upgrade path.
- Data: Unity Catalog governs all tables; storage is UC-only, key auth disabled.
- Network: list of required egress destinations (Databricks control plane, ACR, PyPI, GitHub).
- Cost: [costs.md](costs.md) with actuals.

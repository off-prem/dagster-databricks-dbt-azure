# Services and costs (lean POC)

Budget target: **$50–100/month** with the cluster and Postgres stopped when not in use.
This list is the build spec. Anything not here is out of scope unless [decisions.md](decisions.md) is updated first.

## Resource inventory

Every resource the POC provisions, the phase that creates it, what it costs, and whether
[stop/start](concepts/stop-start.md) applies.

### Phase 0 — Bootstrap (free)

| Resource | Name | Purpose | Est. $/mo | Stop/start? |
|----------|------|---------|-----------|-------------|
| Resource group | `rg-{project}-tfstate` | Terraform state container | 0 | — |
| Storage account + container | `st{project}tf<random>/tfstate` | Terraform remote state | <0.01 | — |
| Entra app registration | `app-{project}-github` | GitHub Actions OIDC | 0 | — |
| 4 federated credentials | `main`, `environment:stage/prod`, `pull_request` | OIDC subject bindings | 0 | — |
| 2 role assignments | Contributor + User Access Administrator (subscription) | CI deploys | 0 | — |

Manual one-time items (free): [Azure resource providers](resources/azure-resource-providers.md),
the [Unity Catalog metastore](resources/unity-catalog-metastore.md), and the [GitHub App](resources/github-app.md) for ARC.

### Phase 1 — Shared infrastructure (costs begin)

| Resource | Name | Purpose | Est. $/mo | Stop/start? |
|----------|------|---------|-----------|-------------|
| Resource group | `rg-{project}-shared` | Shared resource boundary | 0 | — |
| VNet + subnets + NSG | `vnet-{project}` / `snet-aks`, `snet-pe`, `snet-dbx-*` | Network layout (matches corporate) | 0 | — |
| AKS cluster (Free tier) | `aks-{project}` | Hosts Dagster; Entra RBAC, authorized IPs, OIDC, workload identity, Secrets Store CSI | 0 (control plane) | `az aks stop/start` |
| AKS node pool | 1× Standard_D2as_v6 (2 vCPU / 8 GB; variable `aks_vm_size`), 32 GB OS disk | Only compute Dagster needs | ~60 running (B2ms-era estimate; re-measure for D2as_v6) | **Stopped by `just stop`** |
| Node OS disk (P4 32 GB) | (attached to node pool) | Persists while pool exists | ~5 | Bills when stopped |
| Standard LB + public IP | (AKS default outbound) | Pod egress. **No inbound rules.** | ~20 | Bills when stopped |
| Postgres Flexible Server | `pg-{project}-<random>` — B2s, 32 GB, no HA, 7-day backup (may be cross-region) | Dagster state; DBs `{project}_stage`, `{project}_prod` | ~25 running, ~6 stopped | **Stopped by `just stop`** |
| ACR (Basic) | `acr{project}<random>` | Dagster code image | ~5 | — |
| Key Vault (Standard) | `kv-{project}-<random>` | SP secrets, PG password, API key | <1 | — |
| Storage account (ADLS Gen2) | `st{project}<random>` — LRS, HNS, key auth off, firewall | UC metastore root + external location | ~2 | — |
| Network security perimeter | `nsp-{project}` (Learning mode on the ADLS account) | Admits Databricks serverless to the locked-down storage | 0 | — |

### Phase 2 — Stage environment (per-env, ×1)

| Resource | Name | Purpose | Est. $/mo | Stop/start? |
|----------|------|---------|-----------|-------------|
| Resource group | `rg-{project}-stage` | Stage resource boundary | 0 | — |
| Databricks workspace (Premium) | `dbw-{project}-stage` | Managed VNet, SCC on | 0 fixed | — |
| Access Connector | `dbac-{project}-stage` | UC storage credential → ADLS | 0 | — |
| Managed identity | `id-{project}-stage` + federated cred to K8s SA | Pods → Key Vault via workload identity | 0 | — |
| Unity Catalog metastore | `metastore-{project}-<region>` | Governance (one per region, manual) | 0 | — |
| Catalog + schemas + landing volume | `stage` / `bronze`, `silver`; volume `bronze.landing` | Data layers and raw file landing | 0 | — |
| SQL warehouse (Serverless) | 2X-Small, 1 cluster, auto-stop 5 min | dbt target | ~0.30–0.50/run | Auto-stops at 5 min |
| Service principal | `sp-{project}-stage` | Dagster identity, OAuth M2M | 0 | — |
| IP access list | your IP (+ CI runner later) | Workspace network posture | 0 | — |
| K8s namespace | `{project}-stage` | Helm release boundary | 0 | — |

### Phase 4 — Prod environment (per-env, ×1)

Same shape as stage with `prod` substituted. No additional fixed cost.

### Phase 5 — CI/CD

| Resource | Name | Purpose | Est. $/mo | Stop/start? |
|----------|------|---------|-----------|-------------|
| GitHub Actions (Free tier) | — | PR checks (hosted runners, free tier) | 0 | — |
| ARC controller + listener | 2 pods in `arc-systems` namespace | Manages runner lifecycle; always running, ~200m CPU / 256Mi total | 0 (on existing node) | Stops/starts with AKS |
| ARC runner scale set | pods in `arc-runners` namespace | Ephemeral runner pods for deploy-stage and promote-prod; scale from 0 | 0 (on existing node) | Scale to zero when idle |
| GitHub App or PAT | — | ARC authenticates to GitHub to pick up jobs | 0 | — |

Self-hosted runners have no per-minute GitHub Actions charges. The ARC controller
and listener add ~200m CPU and ~256Mi memory to the AKS node baseline. Runner pods
are ephemeral (exist only during a workflow run, ~5–10 min) and need ~500m CPU / 1Gi
memory. All run on the existing AKS node with no incremental Azure cost.

See [decision #16](decisions.md) for why ARC was chosen over GitOps and hosted runners.

### Not provisioned (explicitly out of scope)

VPN gateway, Bastion, private endpoints, private DNS zones, ACR Premium, NAT gateway,
VNet-injected Databricks, second AKS cluster, Postgres HA, Container Insights, Dagster+,
Log Analytics.

## Databricks compute costs (DBUs billed via Azure)

| Compute | Trigger | Est. $/run |
|---------|---------|-----------|
| Serverless job (extract via Pipes) | Dagster asset materialization | ~0.07–0.15 |
| SQL warehouse (dbt) | Dagster dbt asset | ~0.30–0.50 |
| **Per full pipeline run** | bronze + silver | **~0.50–1.00** |

New workspaces get a 14-day Premium trial with free DBUs; serverless bundles compute into
the DBU, so Databricks is ~$0 for the first two weeks.

## GitHub
Free tier for PR checks (hosted runners). Deploy and promote workflows use self-hosted
runners via ARC on the existing AKS cluster — no per-minute charges. $0.

## Cost model

| State | What's billing | Est. $/mo |
|-------|----------------|-----------|
| Everything stopped (`just stop`) | LB+IP ~20, OS disk ~5, ACR 5, PG storage ~4, storage/KV ~3 | **~35–40** |
| Per day running | node VM + Postgres compute | +2.60/day |
| Per pipeline run | serverless job + SQL warehouse | +0.50–1.00 |
| AKS deleted + recreated from TF | Drops LB+IP line | floor **~15** |

8 working days, ~3 runs each ≈ $80. 15 days with a daily stage schedule ≈ $105. 24/7 ≈ $125–140.
To lower the floor, `az aks delete` + recreate from Terraform (~10 min) removes the LB line → floor ≈ $15.

# Services and costs (lean POC)

Budget target: **$50–100/month** with the cluster and Postgres stopped when not in use.
This list is the build spec. Anything not here is out of scope unless [decisions.md](decisions.md) is updated first.

## Azure

| Service | SKU / config | Purpose | Est. $/mo |
|---|---|---|---|
| Resource groups | `rg-dagster-shared`, `rg-dagster-stage`, `rg-dagster-prod` | Lifecycle boundaries that map to future subscriptions | 0 |
| AKS control plane | Free tier, Entra RBAC, authorized IP ranges, OIDC issuer + workload identity enabled, Secrets Store CSI addon | Hosts Dagster | 0 |
| AKS node pool | 1× Standard_B2ms (2 vCPU/8 GB), `--node-osdisk-size 32`, no autoscaler | Only compute Dagster needs | ~60 running, ~25–30 with stop/start |
| Node OS disk | 32 GB Premium SSD (P4) | Default 128 GB is ~$20; shrink it | ~5 |
| Standard LB + public IP | AKS default outbound | Pod egress to Databricks/ACR/PyPI. **No inbound rules.** | ~20 |
| Azure Database for PostgreSQL Flexible Server | B1ms, 32 GB, no HA, 7-day backup, Entra + password auth, public access w/ firewall | Dagster storage; DBs `dagster_stage`, `dagster_prod` | ~17 running, ~4 stopped (750 free hrs/mo for 12 months on new accounts may apply) |
| Azure Container Registry | Basic, admin user disabled | Dagster code image | ~5 |
| Key Vault | Standard, RBAC mode, firewall | Databricks SP secrets, Postgres password, source API key | <1 |
| User-assigned managed identity | one per env (`id-dagster-<env>`) + federated credential to the Dagster service account | Pods → Key Vault | 0 |
| Entra app registration | `app-dagster-github` + federated credentials for `main`, `environment:stage`, `environment:prod` | GitHub OIDC | 0 |
| VNet + subnets + NSG | `10.10.0.0/16`; `snet-aks`; reserve `snet-pe`, `snet-dbx-host/container` (unused for now) | Layout identical to corporate version | 0 |
| Storage account (ADLS Gen2) | StorageV2, LRS, HNS on, key auth disabled, firewall | UC metastore root + external location `bronze`/`silver` | ~2 |
| Azure Databricks workspace ×2 | Premium, managed VNet (no injection), SCC on | Stage and prod workspaces | 0 fixed |
| Access Connector for Azure Databricks ×2 | system-assigned identity, Storage Blob Data Contributor on ADLS | UC storage credential | 0 |
| Log Analytics / Container Insights | **not deployed** | `kubectl logs` suffices | 0 |

## Databricks (DBUs billed via Azure)

| Object | Config | Purpose | Est. $ |
|---|---|---|---|
| Unity Catalog metastore | one per region, root on ADLS | Governance | 0 |
| Catalogs `stage`, `prod`; schemas `bronze`, `silver`, `ops` | per workspace | Data layers; `ops` holds a `dagster_pipes` volume for later | 0 |
| Spark Declarative Pipeline (serverless) | triggered mode, Core edition unless expectations needed | API → `bronze.<source>` streaming table | ~0.25–0.50/run |
| SQL warehouse | Serverless, 2X-Small, 1 cluster, auto-stop 5 min | dbt target | ~0.30–0.50/run |
| Service principal ×2 | `sp-dagster-<env>`, OAuth M2M secret, `USE CATALOG`/`CREATE` on its catalog, `CAN MANAGE` on pipeline, `CAN USE` on warehouse | Dagster identity | 0 |
| IP access list | your IP (+ runner later) | Cheap network posture | 0 |
| **Compute total** | ~1 run/day stage, manual prod, plus dev | | **~20–40/mo** |

New workspaces get a 14-day Premium trial with free DBUs; serverless bundles compute into the DBU, so Databricks is ~$0 for the first two weeks.

## GitHub
Free tier; hosted runners (nothing private yet). $0.

## Cost model
| State | Billing | Est. $/mo |
|---|---|---|
| Everything stopped (floor) | LB+IP ~20, OS disk ~5, ACR 5, PG storage ~4, storage/KV ~3 | **~35–40** |
| Per day running | node + Postgres | +2.60/day |
| Per pipeline run | SDP + warehouse | +0.50–1.00 |

8 working days, ~3 runs each ≈ $80. 15 days with a daily stage schedule ≈ $105. 24/7 ≈ $125–140.
To lower the floor, `az aks delete` + recreate from Terraform (~10 min) removes the LB line → floor ≈ $15.

## Explicitly NOT in the POC (cost or complexity)
VPN gateway, Bastion, private endpoints, private DNS zones, ACR Premium, NAT gateway, VNet-injected
Databricks, second AKS cluster, Azure Postgres HA, Container Insights, Dagster+, self-hosted runner
(until IP access lists block hosted runners).

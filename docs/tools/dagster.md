# Dagster

> **Type:** Tool · **Scope:** per-env (one Helm release each) · **Pinned:** `dagster~=1.13.26` (`dagster/pyproject.toml`)

An open-source data orchestrator. You declare **assets** (data objects) in Python, and
Dagster tracks lineage, launches runs, and records history. This project runs the OSS
version, self-hosted on [AKS](../resources/aks.md).

## Why we use it

Dagster is the point of the POC: it decides *when* things run, while Databricks does the
heavy compute. It orchestrates the extract job and the dbt build as one connected asset graph.

## How it's used here

- **One code location**, `dagster/src/poc/`, loaded by a gRPC code server
  (`dagsterApiGrpcArgs: ["-m", "poc.definitions"]`). `definitions.py` registers all assets and the dbt resource.
- **Assets:** `raw_<source>` assets come from the [asset factory](../concepts/asset-factory.md)
  and submit a Databricks job via [Dagster Pipes](../concepts/dagster-pipes.md). dbt models
  come from `dagster-dbt` (see [dbt](dbt.md)).
- **Deployment:** the official Dagster Helm chart (version `1.13.26`), once per environment. See
  [Helm deployments](../concepts/helm-deployments.md). Components are webserver, daemon, code
  server, and one **run pod** per run (`K8sRunLauncher`).
- **State:** an external [Postgres](../resources/postgres.md) database per env. The chart's
  bundled Postgres is disabled.
- **Image:** one image from `dagster/Dockerfile`, tagged with the git SHA. See [Docker](docker.md).
- **Access:** ClusterIP service only. Use `just port-forward <env>`; never an Ingress or LoadBalancer.

## Key commands & files

```bash
just check-defs              # cd dagster && uv run dg check defs
just test                    # cd dagster && uv run pytest
just port-forward stage      # UI at http://localhost:3000
just smoke-test stage        # launch the job through GraphQL and wait for success
```

Files: `dagster/src/poc/definitions.py`, `dagster/src/poc/assets/`, `deploy/helm/values.*.yaml`.

## Gotchas

- Run pods inherit only the image from the code deployment. Env vars, secrets, labels and
  the CSI volume must be repeated under `runLauncher.config.k8sRunLauncher`.
- `sqlalchemy` is pinned below 2.1 because `dagster-postgres` breaks with psycopg v3 defaults.
- Dagster is now owned by Prefect ([decision 15](../decisions.md)). OSS continues under the same licence.

## Cost

Free software. Runs on the existing AKS node; see [AKS](../resources/aks.md) for the node cost.

## Managed by

Python dependencies via [uv](uv.md); deployed by `scripts/helm-upgrade.sh` and the CI workflows.

## Related docs

- [Dagster Pipes](../concepts/dagster-pipes.md), [asset factory](../concepts/asset-factory.md)
- [Helm](helm.md), [Helm deployments](../concepts/helm-deployments.md)
- [Postgres](../resources/postgres.md): run history store
- [Dagster Pipes](../concepts/dagster-pipes.md)

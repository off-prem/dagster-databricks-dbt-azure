# dagster/

Single Dagster code location, package `poc`, built into one Docker image.

- `src/poc/definitions.py` — the `Definitions` object Dagster loads (`-m poc.definitions`).
- `src/poc/assets/extract.py` — asset factory: one `raw_<source>` asset per entry in
  `databricks/sources.yml`, each submitting a serverless Databricks job via Dagster Pipes.
- `src/poc/assets/dbt.py` — `@dbt_assets` over `dbt/`, one Dagster asset per dbt model.
- `Dockerfile` — build context is the **repo root** (it copies `dbt/` and `databricks/sources.yml`).
  The dbt manifest is generated when the pod starts (`DAGSTER_DBT_PARSE_PROJECT_ON_LOAD=1`),
  because `dbt parse` needs warehouse credentials.

Dependencies are pinned in `pyproject.toml` / `uv.lock` (manage with `uv`).
No environment literals in `src/`; everything comes from env vars set by Helm.

See [docs/tools/dagster.md](../docs/tools/dagster.md),
[docs/concepts/dagster-pipes.md](../docs/concepts/dagster-pipes.md) and
[docs/concepts/asset-factory.md](../docs/concepts/asset-factory.md).

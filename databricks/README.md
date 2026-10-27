# databricks/

Databricks Asset Bundle, targets `stage` and `prod`. It deploys **files only**; it defines no
pipeline or job resources.

- `databricks.yml` — bundle name, variables (`catalog`, `ci_sp_client_id`, `run_as_sp_client_id`),
  targets and permissions.
- `sources.yml` — the APIs to ingest. Read by both Dagster and the notebook.
- `src/extract/entrypoint.py` — notebook that Dagster submits as a serverless task via Pipes.
- `src/extract/rest_api.py` — fetches the API and writes JSON to the landing volume.

Deploy with `scripts/bundle-deploy.sh <env>` (sets `DATABRICKS_HOST` from `.env`).
CI runs `databricks bundle validate -t stage` as a non-blocking check (it needs workspace access).

See [docs/tools/databricks-asset-bundles.md](../docs/tools/databricks-asset-bundles.md) and
[docs/concepts/dagster-pipes.md](../docs/concepts/dagster-pipes.md).

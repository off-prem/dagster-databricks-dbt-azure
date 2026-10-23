# dagster/
Single Dagster code location, package `poc`. Scaffold with `uvx create-dagster project .` or `dg`.
Dependencies: dagster, dagster-k8s, dagster-postgres, dagster-databricks, dagster-dbt, dbt-databricks, databricks-sdk, requests.
Dockerfile must `COPY ../dbt /app/dbt` (build context is repo root) and run `dbt deps` + `dbt parse` at build time.
No environment literals in `src/`. See docs/04-conventions.md.

extract.py — asset factory: one `raw_<source>` asset per entry in `databricks/sources.yml`;
submits a serverless notebook job via `PipesDatabricksServerlessClient`.
dbt.py — `@dbt_assets` over `dbt/`; the `raw.posts` dbt source maps to the `raw_posts` asset key.

# dbt/

dbt project `poc`, adapter `dbt-databricks`, targets `stage` and `prod` driven entirely by env vars
(`profiles.yml`). Models:

- `models/bronze/bronze_posts.sql` — reads the landing-volume JSON with `read_files()`.
- `models/silver/silver_posts.sql` — renamed columns from `ref('bronze_posts')`.
- `models/bronze/sources.yml` — declares the `raw.posts` source that links to the Dagster `raw_posts` asset.
- `macros/generate_schema_name.sql` — use the custom schema name exactly.

Run with `just dbt <env> <command>` (it reads the SP secret from Key Vault).

See [docs/tools/dbt.md](../docs/tools/dbt.md) and
[docs/concepts/medallion-architecture.md](../docs/concepts/medallion-architecture.md).

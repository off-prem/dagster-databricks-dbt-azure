# Databricks CLI

The official CLI for Databricks. In this project it's used exclusively for **Asset Bundle**
operations — deploying and validating the SDP (Spark Declarative Pipeline) that ingests
data into the bronze layer.

## Why we use it

Databricks Asset Bundles are the native way to deploy pipeline code to Databricks. The CLI
handles packaging your Python source, resolving variables per target (stage/prod), and
creating or updating the pipeline in the workspace.

## Key commands

```bash
just bundle-validate <env>   # Check bundle config syntax and variable references
just bundle-deploy <env>     # Deploy the pipeline to the workspace
just collect-bundle <env>    # Capture the pipeline ID into .env
```

The wrapper script `scripts/bundle-deploy.sh` sets `DATABRICKS_HOST` from your `.env`
before calling the CLI — the workspace URL is never hardcoded in the bundle YAML.

## How it authenticates

Locally, the CLI uses your `az` CLI session (the Databricks SDK detects Azure CLI auth
automatically). In CI, it uses [OIDC](../concepts/oidc.md) via the Entra app.

## How it's configured in this project

The bundle lives in `databricks/`:

| File | Purpose |
|------|---------|
| `databricks.yml` | Bundle definition: name, variables (`catalog`, `source_url`), targets (`stage`, `prod`) |
| `resources/bronze_pipeline.yml` | SDP pipeline resource: serverless, triggered, target schema `bronze` |
| `src/bronze_ingest.py` | Pipeline code: reads the source API, returns a DataFrame |

### Targets

Each target maps to an environment:

```yaml
targets:
  stage:
    mode: production
    variables:
      catalog: stage
  prod:
    mode: production
    variables:
      catalog: prod
```

The workspace URL comes from the environment (`DATABRICKS_HOST`), not the YAML.

## Related docs

- [Databricks workspace](../resources/databricks-workspace.md) — where bundles deploy to
- [Unity Catalog](../concepts/unity-catalog.md) — the catalog/schema hierarchy the pipeline writes to
- [Conventions](../conventions.md) — bundle naming and variable patterns

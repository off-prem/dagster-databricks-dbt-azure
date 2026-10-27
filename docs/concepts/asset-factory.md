# Asset Factory (`sources.yml`)

> **Type:** Concept · **Scope:** all envs · **Where:** `databricks/sources.yml`, `dagster/src/poc/assets/extract.py`

A pattern where a config file drives asset creation, so adding an API source needs no Python changes.

## Why we use it

New sources should be a configuration change that is reviewed and deployed, not a new asset
function. One list is the single source of truth for both Dagster and Databricks.

## How it's used here

`databricks/sources.yml` has a `sources:` list. Each entry has `name` and `url`, and optionally
`headers`, `params` and `auth`. `extract.py` loops over the list and builds a `raw_<name>` asset
(key `raw/<name>`, group `extract`) for each entry. The Databricks notebook reads the same file to find the URL.

Current source: `posts` (the JSONPlaceholder `/posts` endpoint), with an `X-Api-Key` header whose value comes
from the pod env var `SOURCE_POSTS_API_KEY`.

**Adding a source:**

1. Add an entry to `sources.yml`.
2. If it needs a key, store it in [Key Vault](../resources/key-vault.md) and expose it through the `SecretProviderClass`.
3. Add a dbt source and model for the new table.
4. Merge. CI rebuilds the image and redeploys the bundle.

## Key commands & files

```bash
just check-defs          # confirms the new asset loads
```

## Gotchas

- `sources.yml` is used by both the image and the bundle, so both must be redeployed after a change.
- `auth.secret_env` names an environment variable, not the secret itself. Never put a key in `sources.yml`.
- Each asset is named `raw_<name>`. The dbt side refers to it as source `raw.<name>`.

## Cost

No direct cost. Each source adds one serverless job per run.

## Managed by

Edited in the repo; deployed by CI.

## Related docs

- [Dagster Pipes](dagster-pipes.md), [dbt](../tools/dbt.md)
- [Databricks Asset Bundles](../tools/databricks-asset-bundles.md)
- [Secrets flow](secrets-flow.md)

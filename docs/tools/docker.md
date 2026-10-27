# Docker

> **Type:** Tool · **Scope:** CI + ACR (not required locally) · **Where:** `dagster/Dockerfile`

Container images package an app with its dependencies. The single image here holds the
Dagster code, the dbt project and `sources.yml`.

## Why we use it

Kubernetes runs containers, so the Dagster code location has to be an image. The same image
is promoted from stage to prod unchanged ([promote, don't rebuild](../concepts/cicd.md)).

## How it's used here

`dagster/Dockerfile` is built from the **repo root** as context:

1. Starts from `python:3.12-slim` and copies the pinned `uv` binary from Astral's image.
2. Installs dependencies from `dagster/uv.lock` first so that layer caches.
3. Copies `dagster/src`, `dbt/`, and `databricks/sources.yml`.
4. Sets `DAGSTER_HOME`, `DBT_PROFILES_DIR` and `DAGSTER_DBT_PARSE_PROJECT_ON_LOAD=1`.

Production builds happen in the cloud with `az acr build` ([ACR](../resources/acr.md)),
tagged `poc:<git-sha>`. `pr-checks.yml` runs `docker build` (no push) on the GitHub-hosted
runner to catch Dockerfile errors.

## Key commands & files

```bash
az acr build --registry "$ACR_NAME" --image poc:<sha> --file dagster/Dockerfile .
docker build -f dagster/Dockerfile .      # optional local check
```

## Gotchas

- The build context is the repo root, not `dagster/`. A build run from inside `dagster/`
  can't see `dbt/`.
- Anything not copied by the Dockerfile is missing at runtime. A new top-level directory
  that Dagster reads needs a `COPY` line.
- The dbt manifest is generated when the pod starts, not in the image, because `dbt parse`
  needs warehouse credentials.
- `.dockerignore` controls what enters the context.

## Cost

Free. Image storage is billed under [ACR](../resources/acr.md).

## Managed by

Built by `deploy-stage.yml` (`az acr build`). Promoted by digest and tag to prod, never rebuilt.

## Related docs

- [ACR](../resources/acr.md): stores the image
- [Dagster](dagster.md): what's inside it
- [uv](uv.md): installs dependencies in the image
- [CI/CD](../concepts/cicd.md)

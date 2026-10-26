# Dagster Pipes on Azure Databricks — deviations from official docs

The [Dagster Pipes serverless compute docs](https://dagster.io/docs/integrations/libraries/databricks/pipes/serverless-compute)
assume a setup that doesn't fully match Azure Databricks serverless. This page
documents what we changed and why, so anyone following the official guide on
Azure can avoid the same issues.

## 1. FUSE is not available on Azure serverless compute

**Docs assume:** `PipesUnityCatalogVolumesContextLoader` and
`PipesUnityCatalogVolumesMessageWriter` read/write context and messages via
`open("/Volumes/...")` (FUSE filesystem access).

**Azure reality:** Serverless compute (standard access mode) does not mount
`/Volumes/` via FUSE. Both `spark_python_task` and `notebook_task` fail with
`FileNotFoundError` on any `/Volumes/` path. See
[standard compute limitations](https://learn.microsoft.com/en-us/azure/databricks/compute/standard-limitations).

**Our fix:** Custom `_SdkContextLoader` and `_SdkMessageWriter` in
`databricks/src/extract/entrypoint.py` that use `WorkspaceClient().files`
(REST API) instead of FUSE. The notebook inherits the SP identity
automatically — no credentials to pass. The data write in `rest_api.py` also
uses the SDK Files API.

## 2. Notebook deployed via bundle loses `.py` extension

**Docs assume:** `notebook_path` in the task points to a known path.

**Bundle behavior:** When `databricks bundle deploy` encounters a `.py` file
with the `# Databricks notebook source` header, it imports it as a Databricks
notebook and **strips the `.py` extension**. So the `notebook_path` must omit
`.py`:

```python
"notebook_path": f"{bundle_root}/src/extract/entrypoint",  # not entrypoint.py
```

Non-notebook `.py` files (like `rest_api.py`, no header) keep their extension.

## 3. `get_extra()` takes exactly one argument

**Docs example:** `pipes.get_extra("some_parameter")` — no default shown.

**Gotcha:** Calling `pipes.get_extra("key", None)` raises `TypeError: takes 2
positional arguments but 3 were given`. There is no default-value parameter.

**Our fix:** Wrap optional extras in `try/except KeyError`.

## 4. `SubmitTask.from_dict()` requires SDK objects for environments

**Docs show:** A simple dict passed to `SubmitTask.from_dict()`.

**Gotcha:** If you use `spark_python_task` with an `environments` spec, the
environment entries must be `jobs.JobEnvironment.from_dict({...})` objects, not
raw dicts. Raw dicts cause `'dict' object has no attribute 'as_dict'` when the
SDK serializes the request.

**Not relevant for `notebook_task`** (no `environments` needed — dependencies
go in a `%pip install` cell).

## 5. SP needs `CREATE_SCHEMA` on the catalog for dbt

**Docs don't cover dbt.** But if you run dbt against Databricks from the same
pipeline, the SP needs `CREATE_SCHEMA` on the catalog in addition to
`USE_CATALOG`. Without it, `dbt build` fails with:

```
PERMISSION_DENIED: Principal does not have CREATE SCHEMA on Catalog
```

Added to `infra/env/databricks.tf` in the `databricks_grants.catalog` resource.

## 6. SP needs workspace CAN_RUN on the bundle directory

**Docs don't mention this.** When the job runs as an SP, the SP must have
`CAN_RUN` permission on the workspace directory containing the deployed
notebook. Without it: `Cannot read the python file ... lacks the required
permissions`.

**Our fix:** `scripts/bundle-deploy.sh` automatically grants `CAN_RUN` on the
bundle directory after each deploy.

## 7. `%pip install` needed in the notebook

**Docs show** `dagster-pipes` imported in the notebook but don't show how it
gets installed.

**On serverless:** The notebook needs a `%pip install dagster-pipes
databricks-sdk requests pyyaml` cell before the code cell. This is handled by
the Databricks notebook source format with `# MAGIC %pip install ...`.

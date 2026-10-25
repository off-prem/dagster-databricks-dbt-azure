"""
Dagster definitions — the entry point that Dagster loads.

This module creates the top-level Definitions object, which is how Dagster
discovers everything it needs to run:
  - assets: data objects Dagster knows how to create (raw API extracts + dbt models)
  - resources: shared services assets can use (the dbt CLI runner)

When Dagster starts (via the gRPC code server in K8s), it imports this module
(configured by dagsterApiGrpcArgs: ["-m", "poc.definitions"] in the Helm values).
It reads the Definitions object to build its catalog of assets, schedules, etc.

The two asset groups come from:
  - raw_assets: dynamically generated from databricks/sources.yml — one asset per
    API source. Each one submits a Databricks serverless job via Dagster Pipes.
  - dbt_project_assets: auto-generated from the dbt project's manifest — one asset
    per dbt model. Dagster runs `dbt build` to materialize them.
"""
from dagster import Definitions
from dagster_dbt import DbtCliResource

from .assets.extract import raw_assets
from .assets.dbt import DBT_PROJECT_DIR, dbt_project_assets

defs = Definitions(
    assets=[*raw_assets, dbt_project_assets],
    resources={
        # DbtCliResource wraps the `dbt` CLI. When an asset calls dbt.cli(["build"]),
        # it runs `dbt build` in the project directory. The dbt profile
        # (dbt/profiles.yml) reads connection details from env vars.
        "dbt": DbtCliResource(project_dir=DBT_PROJECT_DIR),
    },
)

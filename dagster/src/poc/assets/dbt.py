"""
dbt assets — wraps the dbt project as Dagster assets.

Dagster's dbt integration reads the dbt manifest (a JSON file describing all
models, sources, tests, etc.) and creates one Dagster asset per dbt model.
This means:
  - Each dbt model appears in the Dagster UI asset graph
  - Dagster can track dependencies between dbt models and non-dbt assets
  - You can trigger dbt runs from Dagster (manually, on schedule, or as
    downstream of the extract assets)

The dbt project lives at the repo root under dbt/. It connects to Databricks
via a SQL warehouse (configured in dbt/profiles.yml using env vars).
"""
import os
from pathlib import Path

from dagster import AssetExecutionContext
from dagster_dbt import DbtCliResource, DbtProject, dbt_assets

# The dbt project directory — 4 levels up from this file to the repo root,
# then into dbt/.
REPO_ROOT = Path(__file__).parents[4]
DBT_PROJECT_DIR = REPO_ROOT / "dbt"

dbt_project = DbtProject(project_dir=DBT_PROJECT_DIR)

if os.getenv("DAGSTER_DBT_PARSE_PROJECT_ON_LOAD"):
    # In a deployed pod: run dbt parse unconditionally using real credentials
    # from the pod env. prepare_if_dev() only fires under `dagster dev`.
    dbt_project.preparer.prepare(dbt_project)
else:
    dbt_project.prepare_if_dev()


@dbt_assets(manifest=dbt_project.manifest_path)
def dbt_project_assets(context: AssetExecutionContext, dbt: DbtCliResource):
    """
    Run `dbt build` and yield Dagster events for each model/test.

    dbt.cli(["build"]) runs all models and tests. .stream() yields Dagster
    events (AssetMaterialization, AssetCheckResult) as dbt outputs them,
    so the Dagster UI shows progress in real time.
    """
    yield from dbt.cli(["build"], context=context).stream()

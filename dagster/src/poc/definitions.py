from dagster import Definitions
from dagster_dbt import DbtCliResource

from .assets.extract import raw_assets
from .assets.dbt import DBT_PROJECT_DIR, dbt_project_assets

defs = Definitions(
    assets=[*raw_assets, dbt_project_assets],
    resources={
        "dbt": DbtCliResource(project_dir=DBT_PROJECT_DIR),
    },
)

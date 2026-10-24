import os
from pathlib import Path

import yaml
from dagster import AssetExecutionContext, AssetKey, asset

REPO_ROOT = Path(__file__).parents[4]
SOURCES_YML = REPO_ROOT / "databricks" / "sources.yml"


def load_sources():
    with open(SOURCES_YML) as f:
        return yaml.safe_load(f)["sources"]


def _make_raw_asset(source_config):
    name = source_config["name"]
    url = source_config["url"]

    @asset(
        key=AssetKey(["raw", name]),
        group_name="extract",
        kinds={"python", "databricks"},
        description=f"Ingest {name} from {url} into landing volume via Databricks serverless.",
    )
    def _asset(context: AssetExecutionContext) -> None:
        from databricks.sdk import WorkspaceClient
        from databricks.sdk.service import jobs
        from dagster_databricks.pipes import PipesDatabricksServerlessClient

        bundle_root = os.environ["DBX_BUNDLE_ROOT"]
        catalog = os.environ["DBX_CATALOG"]
        ws = WorkspaceClient()

        client = PipesDatabricksServerlessClient(
            client=ws,
            volume_path=f"/Volumes/{catalog}/bronze/landing",
        )

        task = jobs.SubmitTask.from_dict({
            "task_key": f"ingest_{name}",
            "spark_python_task": {
                "python_file": f"{bundle_root}/files/src/extract/entrypoint.py",
            },
            "environment_key": "Default",
        })

        extras = {"source_name": name, "catalog": catalog}
        auth = source_config.get("auth")
        if auth:
            secret_val = os.environ.get(auth["secret_env"], "")
            extras["auth_header"] = auth["header"]
            extras["auth_value"] = secret_val

        client.run(
            task=task,
            extras=extras,
            submit_args={
                "environments": [{
                    "environment_key": "Default",
                    "spec": {
                        "client": "1",
                        "dependencies": ["dagster-pipes", "requests", "pyyaml"],
                    },
                }],
            },
            context=context,
        ).get_materialize_result()

    _asset.__name__ = f"raw_{name}"
    _asset.__qualname__ = f"raw_{name}"
    return _asset


def build_raw_assets():
    return [_make_raw_asset(source) for source in load_sources()]


raw_assets = build_raw_assets()

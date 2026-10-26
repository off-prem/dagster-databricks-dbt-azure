"""
Extract assets — one Dagster asset per API source in databricks/sources.yml.

This module uses the "asset factory" pattern: instead of defining each asset
by hand, we read sources.yml and programmatically create an asset for each entry.
Adding a new API source to sources.yml automatically creates a new Dagster asset
with no code changes needed.

Each asset, when materialized (run), does the following:
  1. Creates a Databricks WorkspaceClient (authenticates via env vars:
     DATABRICKS_HOST + DBX_SP_CLIENT_ID + DBX_SP_SECRET, all from Key Vault)
  2. Creates a PipesDatabricksServerlessClient (Dagster's integration for
     submitting and monitoring Databricks jobs)
  3. Submits a serverless notebook task that runs the entrypoint notebook
     (databricks/src/extract/entrypoint.py) inside Databricks
  4. Passes the source name, catalog, and any auth credentials as "extras"
     (Dagster Pipes' mechanism for sending data to the remote job)
  5. Waits for the job to complete and collects the materialization result

The Databricks job itself (running on Databricks serverless compute) fetches the
API data and writes it to a Unity Catalog Volume. The asset factory here is just
the orchestration — the actual data extraction happens in Databricks.
"""
import os
from pathlib import Path

import yaml
from dagster import AssetExecutionContext, AssetKey, MaterializeResult, asset

# Navigate from this file up to the repo root to find sources.yml.
# This file: dagster/src/poc/assets/extract.py → repo root is 4 levels up.
REPO_ROOT = Path(__file__).parents[4]
SOURCES_YML = REPO_ROOT / "databricks" / "sources.yml"


def load_sources():
    """Read all source definitions from databricks/sources.yml."""
    with open(SOURCES_YML) as f:
        return yaml.safe_load(f)["sources"]


def _make_raw_asset(source_config):
    """
    Factory function: creates one Dagster asset for a single API source.

    The returned asset, when run, submits a Databricks serverless job that
    fetches data from the API and writes it to the landing volume.
    """
    name = source_config["name"]
    url = source_config["url"]

    @asset(
        key=AssetKey(["raw", name]),
        group_name="extract",
        kinds={"python", "databricks"},
        description=f"Ingest {name} from {url} into landing volume via Databricks serverless.",
    )
    def _asset(context: AssetExecutionContext) -> MaterializeResult:
        # Imports are inside the function so they only load when the asset
        # actually runs (not at definition time when Dagster starts up).
        from databricks.sdk import WorkspaceClient
        from databricks.sdk.service import jobs
        from dagster_databricks.pipes import PipesDatabricksServerlessClient

        # These env vars are set by the Helm chart (values.stage.yaml) and
        # come from Terraform outputs captured in .env.
        bundle_root = os.environ["DBX_BUNDLE_ROOT"]
        catalog = os.environ["DBX_CATALOG"]

        ws = WorkspaceClient(
            host=os.environ["DATABRICKS_HOST"],
            azure_client_id=os.environ["DBX_SP_CLIENT_ID"],
            azure_client_secret=os.environ["DBX_SP_SECRET"],
            azure_tenant_id=os.environ["AZURE_TENANT_ID"],
        )

        # PipesDatabricksServerlessClient handles the Dagster Pipes protocol:
        # writing context files to the volume, submitting the job, and reading
        # result messages back.
        client = PipesDatabricksServerlessClient(
            client=ws,
            volume_path=f"/Volumes/{catalog}/bronze/landing",
        )

        # Define the Databricks task — a notebook to run on serverless compute.
        # The notebook_path points to the bundled entrypoint in the workspace
        # (deployed by `scripts/bundle-deploy.sh`). No .py extension — the
        # bundle deploys files with the notebook header as notebooks.
        task = jobs.SubmitTask.from_dict({
            "task_key": f"ingest_{name}",
            "notebook_task": {
                "notebook_path": f"{bundle_root}/src/extract/entrypoint",
                "source": "WORKSPACE",
            },
        })

        # Pass source config and auth credentials to the Databricks job via
        # Pipes "extras" — key-value pairs the remote script can read.
        extras = {"source_name": name, "catalog": catalog}
        auth = source_config.get("auth")
        if auth:
            # Read the secret from the pod's env var (synced from Key Vault
            # via the CSI Secrets Store driver → K8s Secret → envSecrets).
            secret_val = os.environ.get(auth["secret_env"], "")
            extras["auth_header"] = auth["header"]
            extras["auth_value"] = secret_val

        # Submit the job and wait for it to complete. Dependencies are installed
        # via %pip install in the notebook's first cell.
        return client.run(
            task=task,
            extras=extras,
            context=context,
        ).get_materialize_result()

    # Override __name__ so Dagster displays a clean name in the UI
    # (e.g. "raw_posts" instead of "_asset").
    _asset.__name__ = f"raw_{name}"
    _asset.__qualname__ = f"raw_{name}"
    return _asset


def build_raw_assets():
    """Build one asset per source defined in sources.yml."""
    return [_make_raw_asset(source) for source in load_sources()]


# Module-level list — Dagster discovers these when it imports this module.
raw_assets = build_raw_assets()

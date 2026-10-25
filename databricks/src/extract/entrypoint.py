"""
Databricks-side entrypoint for the extract pipeline.

This script runs INSIDE Databricks (on serverless compute), not on AKS.
Dagster submits it as a Spark Python Task via Dagster Pipes. The flow is:

  1. Dagster (on AKS) calls PipesDatabricksServerlessClient.run()
  2. Databricks starts a serverless compute instance and runs THIS script
  3. This script opens a Dagster Pipes connection back to the Dagster pod
  4. It calls rest_api.extract_to_volume() to fetch data and write JSON files
  5. It reports the result (metadata) back to Dagster via the Pipes connection

Dagster Pipes communication uses Unity Catalog Volumes:
  - PipesUnityCatalogVolumesContextLoader: reads context (run ID, asset key, etc.)
    from a file that Dagster wrote to a UC Volume before submitting the job
  - PipesUnityCatalogVolumesMessageWriter: writes result messages (metadata,
    materialization events) to a UC Volume file that Dagster reads after the job
  - PipesCliArgsParamsLoader: reads the Volume paths from CLI arguments that
    Dagster passes when submitting the job

"extras" are arbitrary key-value pairs Dagster passes to the script — we use
them for the source name, catalog, and auth credentials (so secrets flow through
Pipes, never through code or config files).
"""
from rest_api import extract_to_volume
from dagster_pipes import (
    PipesCliArgsParamsLoader,
    PipesUnityCatalogVolumesContextLoader,
    PipesUnityCatalogVolumesMessageWriter,
    open_dagster_pipes,
)

# open_dagster_pipes() establishes the bidirectional communication channel
# between this Databricks job and the Dagster orchestrator.
with open_dagster_pipes(
    params_loader=PipesCliArgsParamsLoader(),
    context_loader=PipesUnityCatalogVolumesContextLoader(),
    message_writer=PipesUnityCatalogVolumesMessageWriter(),
) as pipes:
    # Retrieve auth credentials passed from Dagster via Pipes extras.
    # These originate from Key Vault → K8s Secret → Dagster pod env var.
    auth_header = pipes.get_extra("auth_header", None)
    auth_value = pipes.get_extra("auth_value", None)
    auth = {auth_header: auth_value} if auth_header and auth_value else None

    # Fetch data from the API and write it as newline-delimited JSON
    # into the Unity Catalog landing volume.
    metadata = extract_to_volume(
        pipes.get_extra("source_name"),
        pipes.get_extra("catalog"),
        auth_headers=auth,
    )

    # Report the result back to Dagster — this becomes metadata on the
    # asset materialization event (visible in the Dagster UI).
    pipes.report_asset_materialization(metadata=metadata)

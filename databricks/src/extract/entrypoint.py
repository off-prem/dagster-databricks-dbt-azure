# Databricks notebook source

# COMMAND ----------

# MAGIC %pip install dagster-pipes databricks-sdk requests pyyaml

# COMMAND ----------

"""
Databricks-side entrypoint for the extract pipeline.

This notebook runs INSIDE Databricks (on serverless compute), not on AKS.
Dagster submits it as a Notebook Task via Dagster Pipes.

Dagster Pipes communication uses Unity Catalog Volumes as the transport.
Dagster writes context/reads messages via the SDK (REST API). This notebook
reads context/writes messages via the SDK too, because Azure serverless
compute does not support FUSE access to /Volumes/ paths.
"""
import io
import json
from contextlib import contextmanager

from databricks.sdk import WorkspaceClient
from dagster_pipes import (
    PipesBlobStoreMessageWriter,
    PipesBlobStoreMessageWriterChannel,
    PipesContextLoader,
    PipesDatabricksNotebookWidgetsParamsLoader,
    PipesParams,
    open_dagster_pipes,
)

_ws = WorkspaceClient()


class _SdkContextLoader(PipesContextLoader):
    """Read Pipes context from a UC Volume file via the REST API."""

    @contextmanager
    def load_context(self, params):
        resp = _ws.files.download(params["path"])
        yield json.loads(resp.contents.read())


class _SdkMessageWriterChannel(PipesBlobStoreMessageWriterChannel):
    """Write Pipes message chunks to a UC Volume directory via the REST API."""

    def __init__(self, path, *, interval=10):
        super().__init__(interval=interval)
        self._path = path

    def upload_messages_chunk(self, payload, index):
        _ws.files.upload(
            f"{self._path}/{index}.json",
            io.BytesIO(payload.read().encode("utf-8")),
            overwrite=True,
        )


class _SdkMessageWriter(PipesBlobStoreMessageWriter):
    """Write Pipes messages to a UC Volume directory via the REST API."""

    def make_channel(self, params):
        return _SdkMessageWriterChannel(path=params["path"], interval=self.interval)


# COMMAND ----------

from rest_api import extract_to_volume

with open_dagster_pipes(
    params_loader=PipesDatabricksNotebookWidgetsParamsLoader(dbutils.widgets),
    context_loader=_SdkContextLoader(),
    message_writer=_SdkMessageWriter(),
) as pipes:
    try:
        auth_header = pipes.get_extra("auth_header")
        auth_value = pipes.get_extra("auth_value")
        auth = {auth_header: auth_value}
    except KeyError:
        auth = None

    metadata = extract_to_volume(
        pipes.get_extra("source_name"),
        pipes.get_extra("catalog"),
        auth_headers=auth,
    )

    pipes.report_asset_materialization(metadata=metadata)

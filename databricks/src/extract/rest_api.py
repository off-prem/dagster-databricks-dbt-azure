"""
REST API extraction — fetches data from an HTTP endpoint and writes it to a
Unity Catalog Volume as newline-delimited JSON.

This module runs INSIDE Databricks (serverless compute). It's called by
entrypoint.py, which is submitted by Dagster via Pipes.

The data flow is:
  1. Read the source config from sources.yml (URL, headers, params)
  2. HTTP GET the API endpoint
  3. Write the response as newline-delimited JSON to:
     /Volumes/{catalog}/bronze/landing/{source_name}/{timestamp}.json
  4. Return metadata (record count, file path) for Dagster to log

The Volume path follows Unity Catalog's three-level namespace:
  /Volumes/<catalog>/<schema>/<volume>/<your-path>
  e.g. /Volumes/stage/bronze/landing/posts/20261024_153000.json
"""
import json
from pathlib import Path

import requests
import yaml

# sources.yml lives two directories up from this file (databricks/sources.yml).
SOURCES_PATH = Path(__file__).parents[2] / "sources.yml"


def load_source_config(source_name):
    """Look up a source by name from sources.yml."""
    with open(SOURCES_PATH) as f:
        sources = yaml.safe_load(f)["sources"]
    return next(s for s in sources if s["name"] == source_name)


def extract_to_volume(source_name, catalog, auth_headers=None):
    """
    Fetch data from an API and write it to the landing volume.

    Args:
        source_name: key in sources.yml (e.g. "posts")
        catalog: Unity Catalog catalog name (e.g. "stage" or "prod")
        auth_headers: optional dict of auth headers (e.g. {"X-Api-Key": "..."})

    Returns:
        dict with num_records, volume_path, and source_url for Dagster metadata.
    """
    source = load_source_config(source_name)

    # Merge any static headers from sources.yml with auth headers from Dagster.
    headers = source.get("headers", {})
    if auth_headers:
        headers.update(auth_headers)

    response = requests.get(
        source["url"],
        headers=headers,
        params=source.get("params", {}),
        timeout=30,
    )
    response.raise_for_status()
    data = response.json()

    # Normalize: if the API returns a single object, wrap it in a list.
    if isinstance(data, dict):
        data = [data]

    # Write as newline-delimited JSON (one JSON object per line) — the standard
    # format for loading into Delta tables via Databricks.
    volume_path = f"/Volumes/{catalog}/bronze/landing/{source_name}/latest.json"

    with open(volume_path, "w") as f:
        f.write("\n".join(json.dumps(record) for record in data))

    return {"num_records": len(data), "volume_path": volume_path, "source_url": source["url"]}

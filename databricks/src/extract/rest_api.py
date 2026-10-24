import json
from datetime import datetime, timezone
from pathlib import Path

import requests
import yaml

SOURCES_PATH = Path(__file__).parents[2] / "sources.yml"


def load_source_config(source_name):
    with open(SOURCES_PATH) as f:
        sources = yaml.safe_load(f)["sources"]
    return next(s for s in sources if s["name"] == source_name)


def extract_to_volume(source_name, catalog, auth_headers=None):
    source = load_source_config(source_name)

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

    if isinstance(data, dict):
        data = [data]

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    volume_path = f"/Volumes/{catalog}/bronze/landing/{source_name}/{timestamp}.json"

    with open(volume_path, "w") as f:
        f.write("\n".join(json.dumps(record) for record in data))

    return {"num_records": len(data), "volume_path": volume_path, "source_url": source["url"]}

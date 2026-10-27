# uv

> **Type:** Tool · **Scope:** local + CI + Docker image · **Pinned:** 0.11.14 (`.tool-versions`); Python 3.12.13

A fast Python package and project manager from Astral. It replaces `pip`, `venv` and `pyenv`.

## Why we use it

The repo standardizes on `uv` for all Python. It gives reproducible installs from `uv.lock`
and manages the Python version, so local, CI and Docker environments match.

## How it's used here

- `dagster/pyproject.toml` declares dependencies (Dagster, `dagster-databricks`, `dagster-dbt`,
  `dbt-databricks`, `dagster-postgres`, `dagster-k8s`). `dagster/uv.lock` pins them exactly.
- The [Dockerfile](docker.md) runs `uv sync --frozen --no-dev`.
- `pr-checks.yml` uses `astral-sh/setup-uv` and `uv sync --frozen`.
- `setup-tools.sh` uses it to install Python and, where no native package exists, the Azure CLI.

## Key commands & files

```bash
cd dagster
uv sync                     # create .venv from uv.lock
uv run pytest
uv run dg check defs        # or: just check-defs
uv add <package>            # then commit the updated uv.lock
```

## Gotchas

- Use `--frozen` in CI and images so a stale lock file fails instead of silently updating.
- `requires-python` is `>=3.12,<3.13` to match the image.
- Commit `uv.lock` with any dependency change, or the image build uses outdated pins.

## Cost

Free.

## Managed by

Installed by `scripts/setup-tools.sh`; the Docker image copies a pinned binary from `ghcr.io/astral-sh/uv`.

## Related docs

- [Dagster](dagster.md), [Docker](docker.md), [dbt](dbt.md)
- [Conventions](../conventions.md)

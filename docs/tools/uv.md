# uv

A fast Python package manager by Astral (the Ruff team). Replaces `pip`, `venv`, and
`pyenv` with a single tool that's 10–100× faster.

## Why we use it

The Dagster code location (`dagster/`) is a Python project. `uv` manages its dependencies,
virtual environment, and Python version. It's also used to install the Azure CLI on
platforms without a native package (via `uv tool`).

## Key commands

```bash
# Run a command inside the project's virtual environment
uv run pytest                  # Run tests
uv run dg check defs           # Check Dagster definitions

# Install/sync dependencies from pyproject.toml
uv sync                        # in dagster/

# Install a standalone tool (like azure-cli)
uv tool install azure-cli==2.91.0
```

The `justfile` uses `uv run` for Dagster commands:

```bash
just check-defs   # → cd dagster && uv run dg check defs
just test         # → cd dagster && uv run pytest
```

## How it's installed

`scripts/setup-tools.sh` installs the version pinned in `.tool-versions` using Astral's
install script, placing the binary in `~/.local/bin`.

## How it's configured in this project

The Dagster Python project is in `dagster/`. Its `pyproject.toml` defines dependencies
(dagster, dagster-databricks, dagster-dbt, dbt-databricks, databricks-sdk). `uv` reads
this file to create the virtual environment and install packages.

## Related docs

- [Conventions](../conventions.md) — Python and dependency management conventions

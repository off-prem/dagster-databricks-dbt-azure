FROM python:3.12-slim AS base

COPY --from=ghcr.io/astral-sh/uv:0.11.14 /uv /usr/local/bin/uv

WORKDIR /app

# Install dependencies first (cached layer).
COPY dagster/pyproject.toml dagster/uv.lock ./dagster/
RUN cd dagster && uv sync --frozen --no-dev --no-install-project

# Copy the dagster code location, dbt project, and databricks sources.
COPY dagster/src ./dagster/src
COPY dbt ./dbt
COPY databricks/sources.yml ./databricks/sources.yml

# Install the project itself.
RUN cd dagster && uv sync --frozen --no-dev

# The dbt manifest (target/manifest.json) is generated at pod startup rather
# than build time because dbt-databricks requires a live connection even for
# `dbt parse`. DAGSTER_DBT_PARSE_PROJECT_ON_LOAD tells dagster-dbt to run
# the parse when the code server loads, using real credentials from the pod env.
# Phase 5 CI will pre-build the manifest and remove this.
ENV DAGSTER_DBT_PARSE_PROJECT_ON_LOAD=1
ENV DBT_PROFILES_DIR="/app/dbt"

ENV PATH="/app/dagster/.venv/bin:${PATH}"
ENV DAGSTER_HOME="/opt/dagster/dagster_home"

WORKDIR /app/dagster

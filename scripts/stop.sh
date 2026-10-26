#!/usr/bin/env bash
# Cost control: stop the two things that bill while idle (docs/concepts/stop-start.md).
# Databricks serverless and Dagster-on-K8s need no stop step.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/scripts/load-env.sh"

PROJECT="${TF_VAR_project:-dagster}"
RG_SHARED="rg-${PROJECT}-shared"
AKS_NAME="aks-${PROJECT}"
PG_NAME="${PG_FQDN%%.*}"   # e.g. pg-dagster-ffkc from pg-dagster-ffkc.postgres.database.azure.com

echo "Stopping AKS cluster ${AKS_NAME} in ${RG_SHARED}..."
az aks stop --resource-group "${RG_SHARED}" --name "${AKS_NAME}" 2>&1 || echo "  (already stopped or stopping)"

echo "Stopping Postgres Flexible Server ${PG_NAME} in ${RG_SHARED}..."
az postgres flexible-server stop --resource-group "${RG_SHARED}" --name "${PG_NAME}" 2>&1 || echo "  (already stopped or stopping)"

echo "Stopped. Postgres auto-restarts after 7 consecutive stopped days (docs/concepts/stop-start.md)."

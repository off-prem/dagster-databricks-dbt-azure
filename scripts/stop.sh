#!/usr/bin/env bash
# Cost control: stop the two things that bill while idle (docs/06-stop-start.md).
# Databricks serverless and Dagster-on-K8s need no stop step.
set -euo pipefail

RG_SHARED="rg-dagsterpoc-shared"
AKS_NAME="aks-dagsterpoc"
PG_NAME="pg-dagsterpoc"

echo "Stopping AKS cluster ${AKS_NAME} in ${RG_SHARED}..."
az aks stop --resource-group "${RG_SHARED}" --name "${AKS_NAME}"

echo "Stopping Postgres Flexible Server ${PG_NAME} in ${RG_SHARED}..."
az postgres flexible-server stop --resource-group "${RG_SHARED}" --name "${PG_NAME}"

echo "Stopped. Postgres auto-restarts after 7 consecutive stopped days (docs/06-stop-start.md)."

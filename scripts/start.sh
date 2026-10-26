#!/usr/bin/env bash
# Reverse of stop.sh: bring AKS and Postgres back in parallel, wait for both to be ready
# (docs/concepts/stop-start.md: "waits for nodes Ready and Postgres Ready").
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/scripts/load-env.sh"

PROJECT="${TF_VAR_project:-dagster}"
RG_SHARED="rg-${PROJECT}-shared"
AKS_NAME="aks-${PROJECT}"
PG_NAME="${PG_FQDN%%.*}"   # e.g. pg-dagster-ffkc from pg-dagster-ffkc.postgres.database.azure.com

echo "Starting Postgres and AKS in parallel..."

az postgres flexible-server start --resource-group "${RG_SHARED}" --name "${PG_NAME}" &
PG_PID=$!

az aks start --resource-group "${RG_SHARED}" --name "${AKS_NAME}" &
AKS_PID=$!

PG_OK=0
AKS_OK=0

wait "${PG_PID}" || PG_OK=1
wait "${AKS_PID}" || AKS_OK=1

if [ "${PG_OK}" -ne 0 ]; then echo "⚠ Postgres start returned an error (may already be running)"; fi
if [ "${AKS_OK}" -ne 0 ]; then echo "⚠ AKS start returned an error (may already be running)"; fi

echo "Fetching kubeconfig..."
az aks get-credentials --resource-group "${RG_SHARED}" --name "${AKS_NAME}" --overwrite-existing

echo "Waiting for nodes to be Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

echo "Waiting for Postgres to report Ready..."
for i in $(seq 1 30); do
  state=$(az postgres flexible-server show \
    --resource-group "${RG_SHARED}" --name "${PG_NAME}" --query "state" -o tsv)
  if [[ "${state}" == "Ready" ]]; then
    echo "Postgres is Ready."
    break
  fi
  echo "Postgres state: ${state}. Waiting..."
  sleep 10
done

echo "Started. Pods come back on their own (Deployments); no action needed for Dagster."

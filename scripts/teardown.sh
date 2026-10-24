#!/usr/bin/env bash
# Delete AKS and Postgres entirely to minimize idle cost (docs/concepts/stop-start.md).
# Recreate with: just standup
#
# This drops the floor from ~$35-40/mo to ~$15/mo by eliminating the load balancer,
# public IP, and Postgres compute charges. All Dagster state lives in Postgres storage
# (retained by Terraform) and is restored on standup.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/scripts/load-env.sh"

PROJECT="${TF_VAR_project:-dagster}"
RG_SHARED="rg-${PROJECT}-shared"
AKS_NAME="aks-${PROJECT}"
PG_NAME="pg-${PROJECT}"

echo "=== Teardown ==="
echo "This DELETES AKS and Postgres to minimize idle cost."
echo "Dagster state is preserved — recreate with: just standup"
echo ""
echo "  AKS:      ${AKS_NAME} in ${RG_SHARED}"
echo "  Postgres:  ${PG_NAME} in ${RG_SHARED}"
echo ""
read -r -p "Continue? [y/N] " confirm
case "${confirm}" in
  [yY]) ;;
  *) echo "Aborted."; exit 0 ;;
esac

echo ""
echo "Deleting AKS cluster ${AKS_NAME}..."
az aks delete --resource-group "${RG_SHARED}" --name "${AKS_NAME}" --yes --no-wait

echo "Stopping Postgres Flexible Server ${PG_NAME} (stop, not delete — data preserved)..."
az postgres flexible-server stop --resource-group "${RG_SHARED}" --name "${PG_NAME}"

echo ""
echo "Done. AKS deletion is async (~5 min). Floor cost is now ~$15/mo."
echo "Recreate with: just standup"

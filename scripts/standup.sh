#!/usr/bin/env bash
# Recreate AKS (and start Postgres) after a teardown (docs/concepts/stop-start.md).
# This is the reverse of: just teardown
#
# Steps:
#   1. terraform apply shared  — recreates AKS (Postgres already exists, just stopped)
#   2. Start Postgres
#   3. Fetch kubeconfig + wait for nodes
#   4. Collect new terraform outputs (AKS egress IP may change)
#   5. Re-install ARC (self-hosted runners)
#   6. Re-deploy Helm releases
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/scripts/load-env.sh"

PROJECT="${TF_VAR_project:-dagster}"
RG_SHARED="rg-${PROJECT}-shared"
AKS_NAME="aks-${PROJECT}"
PG_NAME="${PG_FQDN%%.*}"

echo "=== Standup ==="
echo "Recreates AKS and starts Postgres after a teardown."
echo "This will run terraform apply, setup-arc, and helm upgrade (~10-15 min)."
echo ""
read -r -p "Continue? [y/N] " confirm
case "${confirm}" in
  [yY]) ;;
  *) echo "Aborted."; exit 0 ;;
esac

echo ""
echo "Step 1/6: Starting Postgres..."
az postgres flexible-server start --resource-group "${RG_SHARED}" --name "${PG_NAME}"

echo ""
echo "Step 2/6: Recreating AKS via terraform apply..."
echo "  (This also updates firewall rules if the egress IP changed)"
echo "  Review the plan and type 'yes' to apply."
echo ""
terraform -chdir="${ROOT}/infra/shared" apply

echo ""
echo "Step 3/6: Collecting updated outputs..."
"${ROOT}/scripts/setup-env.sh" collect-tf shared
source "${ROOT}/scripts/load-env.sh"

echo ""
echo "Step 4/6: Fetching kubeconfig and waiting for nodes..."
az aks get-credentials --resource-group "${RG_SHARED}" --name "${AKS_NAME}" --overwrite-existing
kubectl wait --for=condition=Ready nodes --all --timeout=300s

echo ""
echo "Step 5/6: Re-installing ARC (self-hosted runners)..."
"${ROOT}/scripts/setup-arc.sh"

echo ""
echo "Step 6/6: Re-deploying Helm releases..."
for env in stage prod; do
  ns="${PROJECT}-${env}"
  if kubectl get namespace "${ns}" &>/dev/null; then
    echo "  Deploying ${env}..."
    "${ROOT}/scripts/helm-upgrade.sh" "${env}"
  else
    echo "  Skipping ${env} — namespace ${ns} does not exist yet"
  fi
done

echo ""
echo "Standup complete. Verify with: kubectl get nodes && kubectl get pods -A"

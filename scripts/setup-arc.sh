#!/usr/bin/env bash
# Install ARC (Actions Runner Controller) on AKS for self-hosted GitHub Actions runners.
# Idempotent — safe to re-run after cluster recreate (teardown/standup).
#
# Prerequisites:
#   - AKS credentials in kubeconfig (az aks get-credentials)
#   - GitHub App private key stored in Key Vault (guide step 5.3)
#
# The script:
#   1. Creates arc-systems and arc-runners namespaces (if missing)
#   2. Pulls the GitHub App private key from Key Vault
#   3. Creates the K8s secret (if missing)
#   4. Installs ARC controller via Helm (if missing)
#   5. Installs runner scale set via Helm (if missing)
#
# Usage:
#   scripts/setup-arc.sh              # install / re-install after cluster recreate
#   scripts/setup-arc.sh teardown     # remove ARC (before cluster delete, optional)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/scripts/load-env.sh"

ARC_VERSION="0.10.1"
CONTROLLER_CHART="oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller"
RUNNER_CHART="oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set"
NS_SYSTEMS="arc-systems"
NS_RUNNERS="arc-runners"
SECRET_NAME="arc-github-app"
KV_SECRET_NAME="arc-github-app-key"

: "${KV_NAME:?KV_NAME not set — run: source scripts/load-env.sh}"
: "${ARC_GITHUB_APP_ID:?ARC_GITHUB_APP_ID not set — add it to .env}"
: "${ARC_GITHUB_APP_INSTALLATION_ID:?ARC_GITHUB_APP_INSTALLATION_ID not set — add it to .env}"
: "${TF_VAR_github_repo:?TF_VAR_github_repo not set — run: scripts/setup-env.sh}"

GITHUB_CONFIG_URL="https://github.com/${TF_VAR_github_repo}"

teardown() {
  echo "Removing ARC..."
  helm uninstall arc-runner-set --namespace "${NS_RUNNERS}" 2>/dev/null || true
  helm uninstall arc --namespace "${NS_SYSTEMS}" 2>/dev/null || true
  kubectl delete secret "${SECRET_NAME}" --namespace "${NS_SYSTEMS}" 2>/dev/null || true
  kubectl delete namespace "${NS_RUNNERS}" 2>/dev/null || true
  kubectl delete namespace "${NS_SYSTEMS}" 2>/dev/null || true
  echo "ARC removed."
}

if [ "${1:-}" = "teardown" ]; then
  teardown
  exit 0
fi

echo "=== Setting up ARC (Actions Runner Controller) ==="

# 1. Namespaces
for ns in "${NS_SYSTEMS}" "${NS_RUNNERS}"; do
  if kubectl get namespace "${ns}" &>/dev/null; then
    echo "Namespace ${ns} exists"
  else
    kubectl create namespace "${ns}"
    echo "Created namespace ${ns}"
  fi
done

# 2. Pull private key from Key Vault
echo "Fetching GitHub App private key from Key Vault (${KV_NAME})..."
PRIVATE_KEY="$(az keyvault secret show --vault-name "${KV_NAME}" --name "${KV_SECRET_NAME}" --query value -o tsv)"
if [ -z "${PRIVATE_KEY}" ]; then
  echo "ERROR: Key Vault secret '${KV_SECRET_NAME}' not found in ${KV_NAME}."
  echo "Store it first:  az keyvault secret set --vault-name '${KV_NAME}' --name '${KV_SECRET_NAME}' --file <path-to-pem>"
  exit 1
fi

# 3. K8s secret
if kubectl get secret "${SECRET_NAME}" --namespace "${NS_SYSTEMS}" &>/dev/null; then
  echo "Secret ${SECRET_NAME} exists — deleting and recreating to pick up any key rotation"
  kubectl delete secret "${SECRET_NAME}" --namespace "${NS_SYSTEMS}"
fi
kubectl create secret generic "${SECRET_NAME}" \
  --namespace "${NS_SYSTEMS}" \
  --from-literal=github_app_id="${ARC_GITHUB_APP_ID}" \
  --from-literal=github_app_installation_id="${ARC_GITHUB_APP_INSTALLATION_ID}" \
  --from-literal=github_app_private_key="${PRIVATE_KEY}"
echo "Created secret ${SECRET_NAME}"

# 4. ARC controller
if helm status arc --namespace "${NS_SYSTEMS}" &>/dev/null; then
  echo "ARC controller already installed — upgrading"
  helm upgrade arc --namespace "${NS_SYSTEMS}" "${CONTROLLER_CHART}" --version "${ARC_VERSION}"
else
  echo "Installing ARC controller..."
  helm install arc --namespace "${NS_SYSTEMS}" "${CONTROLLER_CHART}" --version "${ARC_VERSION}"
fi

# 5. Runner scale set
if helm status arc-runner-set --namespace "${NS_RUNNERS}" &>/dev/null; then
  echo "Runner scale set already installed — upgrading"
  helm upgrade arc-runner-set --namespace "${NS_RUNNERS}" "${RUNNER_CHART}" \
    --version "${ARC_VERSION}" \
    --set "githubConfigUrl=${GITHUB_CONFIG_URL}" \
    --set "githubConfigSecret.github_app_id=${ARC_GITHUB_APP_ID}" \
    --set "githubConfigSecret.github_app_installation_id=${ARC_GITHUB_APP_INSTALLATION_ID}" \
    --set "githubConfigSecret.github_app_private_key=${PRIVATE_KEY}" \
    --set minRunners=0 \
    --set maxRunners=3
else
  echo "Installing runner scale set..."
  helm install arc-runner-set --namespace "${NS_RUNNERS}" "${RUNNER_CHART}" \
    --version "${ARC_VERSION}" \
    --set "githubConfigUrl=${GITHUB_CONFIG_URL}" \
    --set "githubConfigSecret.github_app_id=${ARC_GITHUB_APP_ID}" \
    --set "githubConfigSecret.github_app_installation_id=${ARC_GITHUB_APP_INSTALLATION_ID}" \
    --set "githubConfigSecret.github_app_private_key=${PRIVATE_KEY}" \
    --set minRunners=0 \
    --set maxRunners=3
fi

echo ""
echo "=== ARC setup complete ==="
echo "Controller + listener: kubectl get pods -n ${NS_SYSTEMS}"
echo "Runners (scale to zero): kubectl get pods -n ${NS_RUNNERS}"

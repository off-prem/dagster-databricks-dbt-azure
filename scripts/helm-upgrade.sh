#!/usr/bin/env bash
# Deploy Dagster to AKS via Helm, injecting per-user values from .env.
# Usage: scripts/helm-upgrade.sh <stage|prod> [extra helm flags ...]
#
# Reads .env (via load-env.sh) and resolves ${VAR} placeholders in the
# per-env values file with envsubst before passing it to Helm.
# Extra flags (e.g. --set image.tag=sha-abc from CI) are appended.
set -euo pipefail

ENV="${1:?Usage: scripts/helm-upgrade.sh <stage|prod> [extra helm flags ...]}"
shift
case "${ENV}" in
  stage|prod) ;;
  *) echo "env must be 'stage' or 'prod'" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/scripts/load-env.sh"

PROJECT="${TF_VAR_project:-dagster}"
NAMESPACE="${PROJECT}-${ENV}"
RELEASE="${PROJECT}-${ENV}"

# Map env-specific .env keys to generic names used in values templates
if [ "${ENV}" = stage ]; then
  DBX_HOST="${DBX_STAGE_HOST:-}"
  DBX_WAREHOUSE="${DBX_STAGE_WAREHOUSE_HTTP_PATH:-}"
  IDENTITY_CLIENT_ID="${DAGSTER_STAGE_IDENTITY_CLIENT_ID:-}"
else
  DBX_HOST="${DBX_PROD_HOST:-}"
  DBX_WAREHOUSE="${DBX_PROD_WAREHOUSE_HTTP_PATH:-}"
  IDENTITY_CLIENT_ID="${DAGSTER_PROD_IDENTITY_CLIENT_ID:-}"
fi
DBX_BUNDLE_ROOT="/Workspace/.bundle/${PROJECT}/${ENV}/files"

# Warn on missing values (not fatal — partial deploys are useful during setup)
for var in PG_FQDN ACR_LOGIN_SERVER DBX_HOST; do
  eval "val=\${${var}:-}"
  [ -n "${val}" ] || echo "WARNING: ${var} is blank in .env — helm values will be incomplete" >&2
done

# Resolve ${VAR} placeholders in the per-env values file
export PG_FQDN ACR_LOGIN_SERVER DBX_HOST DBX_WAREHOUSE DBX_BUNDLE_ROOT RELEASE IDENTITY_CLIENT_ID
RESOLVED="$(mktemp)"
trap 'rm -f "${RESOLVED}"' EXIT
envsubst < "${ROOT}/deploy/helm/values.${ENV}.yaml" > "${RESOLVED}"

set -x
helm upgrade --install "${RELEASE}" dagster/dagster \
  --version 1.13.26 \
  -n "${NAMESPACE}" --create-namespace \
  --wait --timeout 3m0s \
  -f "${ROOT}/deploy/helm/values.base.yaml" \
  -f "${RESOLVED}" \
  "$@"

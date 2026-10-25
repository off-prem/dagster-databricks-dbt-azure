#!/usr/bin/env bash
# Deploy Dagster to AKS via Helm, injecting per-user values from .env.
# Usage: scripts/helm-upgrade.sh <stage|prod> [--set key=val ...]
#
# Reads .env (via load-env.sh) and overrides the per-user placeholders in the committed
# values files. Extra --set flags (e.g. image.tag from CI) are appended.
set -euo pipefail

ENV="${1:?Usage: scripts/helm-upgrade.sh <stage|prod> [--set key=val ...]}"
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

# Map env-specific .env keys
if [ "${ENV}" = stage ]; then
  DBX_HOST="${DBX_STAGE_HOST:-}"
  DBX_WAREHOUSE="${DBX_STAGE_WAREHOUSE_HTTP_PATH:-}"
  IDENTITY_CLIENT_ID="${DAGSTER_STAGE_IDENTITY_CLIENT_ID:-}"
else
  DBX_HOST="${DBX_PROD_HOST:-}"
  DBX_WAREHOUSE="${DBX_PROD_WAREHOUSE_HTTP_PATH:-}"
  IDENTITY_CLIENT_ID="${DAGSTER_PROD_IDENTITY_CLIENT_ID:-}"
fi

# Warn on missing values (not fatal — partial deploys are useful during setup)
for var in PG_FQDN ACR_LOGIN_SERVER DBX_HOST; do
  eval "val=\${${var}:-}"
  [ -n "${val}" ] || echo "WARNING: ${var} is blank in .env — helm values will be incomplete" >&2
done

set -x
helm upgrade --install "${RELEASE}" dagster/dagster \
  -n "${NAMESPACE}" --create-namespace \
  -f "${ROOT}/deploy/helm/values.base.yaml" \
  -f "${ROOT}/deploy/helm/values.${ENV}.yaml" \
  --set "postgresql.postgresqlHost=${PG_FQDN:-}" \
  --set "dagster-user-deployments.deployments[0].image.repository=${ACR_LOGIN_SERVER:-}/poc" \
  --set "serviceAccount.name=${RELEASE}" \
  --set "serviceAccount.annotations.azure\.workload\.identity/client-id=${IDENTITY_CLIENT_ID}" \
  --set "dagster-user-deployments.deployments[0].env[2].name=DATABRICKS_HOST" \
  --set "dagster-user-deployments.deployments[0].env[2].value=${DBX_HOST}" \
  --set "dagster-user-deployments.deployments[0].env[3].name=DBX_BUNDLE_ROOT" \
  --set "dagster-user-deployments.deployments[0].env[3].value=/Workspace/.bundle/${PROJECT}/${ENV}/files" \
  --set "dagster-user-deployments.deployments[0].env[4].name=DBX_WAREHOUSE_HTTP_PATH" \
  --set "dagster-user-deployments.deployments[0].env[4].value=${DBX_WAREHOUSE}" \
  "$@"

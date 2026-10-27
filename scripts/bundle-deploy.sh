#!/usr/bin/env bash
# Deploy the Databricks Asset Bundle, setting DATABRICKS_HOST from .env.
# Usage: scripts/bundle-deploy.sh <stage|prod> [extra databricks bundle flags...]
#
# After deploy, run `scripts/setup-env.sh collect-bundle <env>` to capture the pipeline ID.
set -euo pipefail

ENV="${1:?Usage: scripts/bundle-deploy.sh <stage|prod> [extra flags...]}"
shift
case "${ENV}" in
  stage|prod) ;;
  *) echo "env must be 'stage' or 'prod'" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/scripts/load-env.sh"

if [ "${ENV}" = stage ]; then
  export DATABRICKS_HOST="${DBX_STAGE_HOST:?DBX_STAGE_HOST is blank in .env — run infra/env stage first}"
else
  export DATABRICKS_HOST="${DBX_PROD_HOST:?DBX_PROD_HOST is blank in .env — run infra/env prod first}"
fi
export DATABRICKS_AUTH_TYPE="${DATABRICKS_AUTH_TYPE:-azure-cli}"

export BUNDLE_VAR_ci_sp_client_id="${AZURE_CLIENT_ID:-}"
if [ "${ENV}" = stage ]; then
  export BUNDLE_VAR_run_as_sp_client_id="${DBX_STAGE_SP_CLIENT_ID:-}"
else
  export BUNDLE_VAR_run_as_sp_client_id="${DBX_PROD_SP_CLIENT_ID:-}"
fi

echo "Deploying bundle to ${ENV} (host: ${DATABRICKS_HOST})"

# Ensure the bundle root directory exists in the Workspace API before deploying.
# The bundle CLI uploads via the Files API, which on new workspaces may not
# create a directory visible to the Workspace API (needed for permission grants).
BUNDLE_NAME="$(awk '/^bundle:/{found=1;next} found && /name:/{print $2;exit}' "${ROOT}/databricks/databricks.yml")"
BUNDLE_DIR="/Workspace/.bundle/${BUNDLE_NAME}/${ENV}"
cd "${ROOT}" && databricks workspace mkdirs "${BUNDLE_DIR}" 2>/dev/null || true

cd "${ROOT}/databricks"
set -x
databricks bundle deploy -t "${ENV}" "$@"
set +x

# Grant the service principal CAN_RUN on the bundle directory so Databricks
# serverless jobs (which run as the SP) can read the deployed Python files.
sp_var="DBX_$(echo "${ENV}" | tr '[:lower:]' '[:upper:]')_SP_CLIENT_ID"
SP_CLIENT_ID="${!sp_var:-}"
if [ -n "${SP_CLIENT_ID}" ]; then
  echo "Granting SP ${SP_CLIENT_ID} CAN_RUN on ${BUNDLE_DIR}"
  # Run workspace commands from repo root to avoid the CLI picking up
  # databricks.yml and requiring a bundle target.
  if OBJ_ID="$(cd "${ROOT}" && databricks workspace get-status "${BUNDLE_DIR}" -o json 2>/dev/null | python3 -I -c 'import sys,json; print(json.load(sys.stdin)["object_id"])' 2>/dev/null)"; then
    cd "${ROOT}" && databricks workspace update-permissions directories "${OBJ_ID}" \
      --json "{\"access_control_list\":[{\"service_principal_name\":\"${SP_CLIENT_ID}\",\"permission_level\":\"CAN_RUN\"}]}" \
      || echo "WARNING: could not set workspace permissions — grant manually in the Databricks UI"
  else
    echo "WARNING: bundle directory not yet visible in Workspace API — re-run to set permissions, or grant manually in the Databricks UI"
  fi
else
  echo "WARNING: DBX_SP_CLIENT_ID not set — skipping workspace permission grant"
fi

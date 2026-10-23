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

echo "Deploying bundle to ${ENV} (host: ${DATABRICKS_HOST})"
cd "${ROOT}/databricks"
set -x
databricks bundle deploy -t "${ENV}" "$@"

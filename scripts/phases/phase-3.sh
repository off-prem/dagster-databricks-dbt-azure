#!/usr/bin/env bash
# Phase 3 — dbt and end-to-end lineage (Goal 2: end-to-end pipeline)
#
# Verifies dbt connectivity, builds the silver model, and shows the
# full lineage graph: raw_posts → bronze_posts → silver_posts.
# Re-running safely skips completed steps.
#
# Usage: scripts/phases/phase-3.sh
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_env_if_exists

phase_header 3 "dbt and end-to-end lineage"
echo "  Goal: end-to-end data pipeline with full lineage."
echo "  Re-running safely skips completed steps."

# ── Pre-flight ───────────────────────────────────────────────────────────────

require_az_login || exit 1

for key in DBX_STAGE_HOST DBX_STAGE_WAREHOUSE_HTTP_PATH DBX_STAGE_SP_CLIENT_ID KV_NAME; do
  require_env "${key}" "Run 'just phase 2' first" || exit 1
done

local_project="$(project_name)"

# Set up dbt environment
export DATABRICKS_HOST="$(env_val DBX_STAGE_HOST)"
export DBX_WAREHOUSE_HTTP_PATH="$(env_val DBX_STAGE_WAREHOUSE_HTTP_PATH)"
export DBX_SP_CLIENT_ID="$(env_val DBX_STAGE_SP_CLIENT_ID)"
export DBX_CATALOG=stage
export DAGSTER_ENV=stage

# Fetch SP secret from Key Vault if not already set
if [[ -z "${DBX_SP_SECRET:-}" ]]; then
  kv="$(kv_name)"
  if [[ -n "${kv}" ]]; then
    export DBX_SP_SECRET="$(az keyvault secret show --vault-name "${kv}" --name "dbx-stage-sp-secret" --query value -o tsv 2>/dev/null || true)"
  fi
fi

# ── 3.1 Verify dbt connection ───────────────────────────────────────────────

step_header "3.1" "Verify dbt connection"

if (cd "${ROOT}/dagster" && uv run dbt debug --project-dir "${ROOT}/dbt" --profiles-dir "${ROOT}/dbt" --target stage >/dev/null 2>&1); then
  pass "dbt debug connects to stage warehouse"
else
  fail "dbt debug failed"
  echo ""
  echo "  Common issues:"
  echo "  - Serverless SQL warehouse + ADLS firewall: needs Azure Network Security"
  echo "    Perimeter (NSP) with AzureDatabricksServerless service tag."
  echo "    See docs/guide.md step 3.1 for details."
  echo "  - SP credentials: check that dbx-stage-sp-secret is in Key Vault."
  echo ""
  echo "  Debug manually:"
  echo "    just dbt stage debug"
fi

# ── 3.2 Build the silver model ──────────────────────────────────────────────

step_header "3.2" "Build dbt models (bronze + silver)"

echo "  This runs two dbt models:"
echo "    bronze_posts — read_files() from the landing volume"
echo "    silver_posts — selects from bronze_posts with column renames"
echo ""
read -r -p "Run dbt build now? [Y/n] " reply
if [[ ! "${reply}" =~ ^[nN] ]]; then
  info "Running dbt build..."
  if (cd "${ROOT}" && just dbt stage build); then
    pass "dbt build succeeded"
  else
    fail "dbt build failed"
    echo "        Check: just dbt stage build --debug"
  fi
else
  skip "dbt build (run 'just dbt stage build' when ready)"
fi

# ── 3.3 End-to-end lineage ──────────────────────────────────────────────────

step_header "3.3" "End-to-end lineage"

echo "  The full lineage: raw_posts → bronze_posts → silver_posts"
echo ""
echo "  To see it in the Dagster UI:"
echo "    just port-forward stage    # http://localhost:3000"
echo "    Select all assets → Materialize all"
echo ""
echo "  To verify data landed:"
echo "    SELECT count(*) FROM stage.silver.silver_posts"
echo "    (via Databricks SQL editor or CLI)"
echo ""

# Verify Dagster definitions load correctly with real credentials
export DAGSTER_DBT_PARSE_PROJECT_ON_LOAD=1
export DBT_PROFILES_DIR="${ROOT}/dbt"
export DBX_BUNDLE_ROOT="/Workspace/.bundle/${local_project}/stage/files"

if (cd "${ROOT}/dagster" && uv run dagster definitions validate -m poc.definitions >/dev/null 2>&1); then
  pass "Dagster definitions validate with live credentials"
else
  fail "Dagster definitions validate failed"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "  → Goal 2: end-to-end data pipeline."

phase_summary 3

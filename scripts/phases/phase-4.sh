#!/usr/bin/env bash
# Phase 4 — Prod (Goal 3: stage/prod parity)
#
# Mirrors the stage environment into prod: workspace, catalog, SP, warehouse,
# Dagster deployment. Re-running safely skips completed steps.
#
# Usage: scripts/phases/phase-4.sh
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_env_if_exists

phase_header 4 "Prod environment"
echo "  Goal: stage/prod parity."
echo "  Re-running safely skips completed steps."

# ── Pre-flight ───────────────────────────────────────────────────────────────

require_az_login || exit 1

for key in TF_VAR_project TF_VAR_metastore_id ACR_NAME KV_NAME AKS_EGRESS_IP; do
  require_env "${key}" "Run 'just phase 2' first" || exit 1
done

local_project="$(project_name)"

# ── 4.1 Apply prod (Azure resources) ────────────────────────────────────────

step_header "4.1" "Apply prod (Azure resources)"

prod_rg_exists=false
if az resource show --resource-group "rg-${local_project}-prod" \
    --name "dbw-${local_project}-prod" \
    --resource-type "Microsoft.Databricks/workspaces" >/dev/null 2>&1; then
  prod_rg_exists=true
fi

if [[ "${prod_rg_exists}" == "true" ]] && check_env DBX_PROD_HOST; then
  skip "Prod workspace exists (dbw-${local_project}-prod)"
else
  info "Initializing Terraform for prod..."
  (cd "${ROOT}" && just tf-init env-prod -upgrade)

  echo ""
  echo "This creates the prod workspace and identity. Databricks workspace-level"
  echo "resources (catalog, SP, warehouse) will fail until you log in and the"
  echo "metastore is assigned — that's expected and handled in step 4.3."
  echo ""

  tf_plan_confirm_apply env-prod

  info "Capturing prod outputs..."
  "${ROOT}/scripts/setup-env.sh" collect-tf env-prod
  source "${ROOT}/scripts/load-env.sh"
  pass "Prod outputs captured to .env"
fi

# ── 4.2 First login to prod workspace ───────────────────────────────────────

step_header "4.2" "First login to prod workspace"

load_env_if_exists
dbx_host="$(env_val DBX_PROD_HOST)"

if [[ -z "${dbx_host}" ]]; then
  fail "DBX_PROD_HOST not set — step 4.1 may have failed"
  exit 1
fi

if dbx_auth_check "${dbx_host}"; then
  skip "Databricks CLI can access prod workspace"
else
  wait_for_manual \
"1. Open the prod workspace in your browser:
     ${dbx_host}

2. Log in with your Azure credentials, accept the trial

3. Verify the metastore is assigned:
   Account console → Catalog → Metastore → Workspaces
   dbw-${local_project}-prod should appear.
   If not, assign it manually (don't create a new metastore)." \
    dbx_auth_check "${dbx_host}"
fi

# ── 4.3 Prod workspace objects ───────────────────────────────────────────────

step_header "4.3" "Create prod workspace objects"

load_env_if_exists

ws_objects_done=false
if check_env DBX_PROD_SP_CLIENT_ID && check_env DBX_PROD_WAREHOUSE_HTTP_PATH; then
  ws_objects_done=true
fi

if [[ "${ws_objects_done}" == "true" ]]; then
  skip "Prod workspace objects exist (SP client ID and warehouse path set)"
else
  echo "Re-applying creates all Databricks objects: catalog, schemas, warehouse, SP, grants."
  echo ""

  tf_plan_confirm_apply env-prod

  info "Capturing prod workspace object outputs..."
  "${ROOT}/scripts/setup-env.sh" collect-tf env-prod
  source "${ROOT}/scripts/load-env.sh"
  pass "Prod workspace objects created and outputs captured"
fi

# ── 4.4 Apply prod SecretProviderClass ───────────────────────────────────────

step_header "4.4" "Apply prod SecretProviderClass"

load_env_if_exists
ns="${local_project}-prod"

spc_exists=false
if kubectl get secretproviderclass -n "${ns}" 2>/dev/null | grep -q dagster; then
  spc_exists=true
fi

if [[ "${spc_exists}" == "true" ]]; then
  skip "SecretProviderClass exists in ${ns}"
else
  info "Creating namespace and applying SecretProviderClass..."
  apply_secret_provider_class prod
  pass "SecretProviderClass applied to ${ns}"
fi

# ── 4.5 Store dummy API key for prod ────────────────────────────────────────

step_header "4.5" "Verify dummy API key for prod"

kv="$(kv_name)"
if [[ -n "${kv}" ]] && kv_secret_exists "${kv}" source-posts-api-key; then
  skip "source-posts-api-key already in Key Vault (shared across envs)"
else
  info "Setting dummy API key..."
  kv_set_secret "${kv}" source-posts-api-key "dummy-test-key"
  pass "source-posts-api-key stored in Key Vault"
fi

# ── 4.6 Deploy to prod ──────────────────────────────────────────────────────

step_header "4.6" "Deploy to prod"

load_env_if_exists

echo "  Promote, don't rebuild — prod gets the exact image that passed on stage."
echo ""

# Bundle deploy
info "Deploying bundle to prod..."
(cd "${ROOT}" && just bundle-deploy prod)
pass "Bundle deployed to prod"

# Helm deploy
info "Deploying Dagster to prod via Helm..."
(cd "${ROOT}" && just helm-upgrade prod)
pass "Dagster deployed to prod"

# Verify pods
ns="${local_project}-prod"
info "Waiting for pods..."
kubectl wait --for=condition=Ready pods --all -n "${ns}" --timeout=300s 2>/dev/null || true

not_ready="$(kubectl get pods -n "${ns}" --no-headers 2>/dev/null | grep -cv "Running\|Completed" || true)"
if [[ "${not_ready}" -eq 0 ]]; then
  pass "All pods Running in ${ns}"
else
  fail "${not_ready} pod(s) not Running in ${ns}"
  echo "        Check: kubectl get pods -n ${ns}"
fi

# ── Verify and summarize ────────────────────────────────────────────────────

step_header "4.✓" "Phase verification"

load_env_if_exists

for key in DBX_PROD_HOST DBX_PROD_SP_CLIENT_ID DBX_PROD_WAREHOUSE_HTTP_PATH; do
  if check_env "${key}"; then
    pass "${key} set in .env"
  else
    fail "${key} blank in .env"
  fi
done

echo ""
echo "  Verify manually:"
echo "    just port-forward prod   # Dagster UI at http://localhost:3000"
echo "    Materialize raw_posts, then dbt assets"
echo ""
echo "  → Goal 3: stage/prod parity."

phase_summary 4

#!/usr/bin/env bash
# Phase 2 — Stage environment (Goal 1: Dagster talks to Databricks)
#
# Creates the stage Databricks workspace, deploys the bundle and Dagster,
# and runs the first end-to-end test.
# Re-running safely skips completed steps.
#
# Usage: scripts/phases/phase-2.sh
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_env_if_exists

phase_header 2 "Stage environment"
echo "  Goal: Dagster on AKS talks to Databricks."
echo "  Re-running safely skips completed steps."

# ── Pre-flight ───────────────────────────────────────────────────────────────

require_az_login || exit 1

for key in TF_VAR_project ACR_NAME KV_NAME AKS_EGRESS_IP; do
  require_env "${key}" "Run 'just phase 1' first" || exit 1
done

local_project="$(project_name)"

# ── 2.1 Apply stage (Azure resources) ───────────────────────────────────────

step_header "2.1" "Apply stage (Azure resources)"

stage_rg_exists=false
if az resource show --resource-group "rg-${local_project}-stage" \
    --name "dbw-${local_project}-stage" \
    --resource-type "Microsoft.Databricks/workspaces" >/dev/null 2>&1; then
  stage_rg_exists=true
fi

if [[ "${stage_rg_exists}" == "true" ]] && check_env DBX_STAGE_HOST; then
  skip "Stage workspace exists (dbw-${local_project}-stage)"
else
  info "Initializing Terraform for stage..."
  (cd "${ROOT}" && just tf-init env-stage -upgrade)

  echo ""
  echo "This creates: resource group, Databricks workspace, Access Connector,"
  echo "managed identity with federated credential and Key Vault access."
  echo "Databricks workspace-level objects (catalog, SP, warehouse) are created"
  echo "in step 2.4 after you log into the workspace and assign the metastore."
  echo ""

  tf_plan_confirm_apply env-stage

  info "Capturing stage outputs..."
  "${ROOT}/scripts/setup-env.sh" collect-tf env-stage
  source "${ROOT}/scripts/load-env.sh"
  pass "Stage outputs captured to .env"
fi

# ── 2.2 First login to Databricks workspace ─────────────────────────────────

step_header "2.2" "First login to Databricks workspace"

load_env_if_exists
dbx_host="$(env_val DBX_STAGE_HOST)"

if [[ -z "${dbx_host}" ]]; then
  fail "DBX_STAGE_HOST not set — step 2.1 may have failed"
  exit 1
fi

# Try to verify CLI access (indicates login has happened)
if dbx_auth_check "${dbx_host}"; then
  skip "Databricks CLI can access stage workspace"
else
  wait_for_manual \
"1. Open the stage workspace in your browser:
     ${dbx_host}

2. Log in with your Azure credentials

3. Accept the Premium trial if prompted

4. If the workspace ID wasn't captured, find it in the URL after '?o='
   and run:
     just set-env DBX_STAGE_WORKSPACE_ID <id>" \
    dbx_auth_check "${dbx_host}"
fi

# ── 2.3 Create the Unity Catalog metastore ──────────────────────────────────

step_header "2.3" "Create Unity Catalog metastore"

if check_env TF_VAR_metastore_id; then
  skip "Metastore ID already set: $(env_val TF_VAR_metastore_id)"
else
  load_env_if_exists
  storage_acct="$(env_val STORAGE_ACCOUNT_NAME)"
  ac_id="$(env_val TF_VAR_access_connector_id_stage)"
  location="$(env_val TF_VAR_location)"
  location="${location:-eastus2}"

  wait_for_manual \
"One-time manual step — create the Unity Catalog metastore:

1. Go to https://accounts.azuredatabricks.net
2. Catalog → Create metastore
3. Fill in:
   - Name: metastore-${local_project}-${location}
   - Region: ${location}
   - ADLS Gen2 path: abfss://metastore@${storage_acct}.dfs.core.windows.net/
   - Access Connector ID: ${ac_id:-<from terraform output>}
4. Assign the metastore to the stage workspace
5. Copy the metastore ID and run:
     just set-env TF_VAR_metastore_id <metastore-id>" \
    check_env TF_VAR_metastore_id

  source "${ROOT}/scripts/load-env.sh"
fi

# ── 2.4 Create workspace objects ─────────────────────────────────────────────

step_header "2.4" "Create workspace objects (catalog, SP, warehouse)"

load_env_if_exists

ws_objects_done=false
if check_env DBX_STAGE_SP_CLIENT_ID && check_env DBX_STAGE_WAREHOUSE_HTTP_PATH; then
  ws_objects_done=true
fi

if [[ "${ws_objects_done}" == "true" ]]; then
  skip "Workspace objects exist (SP client ID and warehouse path set)"
else
  echo "Now that the metastore is assigned, re-applying creates all Databricks objects:"
  echo "catalog, schemas, managed volume, SQL warehouse, service principal, grants."
  echo ""

  tf_plan_confirm_apply env-stage

  info "Capturing workspace object outputs..."
  "${ROOT}/scripts/setup-env.sh" collect-tf env-stage
  source "${ROOT}/scripts/load-env.sh"
  pass "Workspace objects created and outputs captured"
fi

# Verify KV secrets
kv="$(kv_name)"
if [[ -n "${kv}" ]]; then
  for secret in dbx-stage-sp-client-id dbx-stage-sp-secret; do
    if kv_secret_exists "${kv}" "${secret}"; then
      pass "${secret} in Key Vault"
    else
      fail "${secret} not found in Key Vault"
    fi
  done
fi

# ── 2.5 Apply SecretProviderClass ────────────────────────────────────────────

step_header "2.5" "Apply SecretProviderClass"

load_env_if_exists
ns="${local_project}-stage"

spc_exists=false
if kubectl get secretproviderclass -n "${ns}" 2>/dev/null | grep -q dagster; then
  spc_exists=true
fi

if [[ "${spc_exists}" == "true" ]]; then
  skip "SecretProviderClass exists in ${ns}"
else
  info "Creating namespace and applying SecretProviderClass..."
  apply_secret_provider_class stage
  pass "SecretProviderClass applied to ${ns}"
fi

# ── 2.6 Store dummy API key ─────────────────────────────────────────────────

step_header "2.6" "Store dummy API key in Key Vault"

kv="$(kv_name)"
if [[ -n "${kv}" ]] && kv_secret_exists "${kv}" source-posts-api-key; then
  skip "source-posts-api-key already in Key Vault"
else
  info "Setting dummy API key (tests the full Key Vault → pod → Pipes auth chain)..."
  kv_set_secret "${kv}" source-posts-api-key "dummy-test-key"
  pass "source-posts-api-key stored in Key Vault"
fi

# ── 2.7 Verify Databricks CLI auth ──────────────────────────────────────────

step_header "2.7" "Verify Databricks CLI auth"

load_env_if_exists
dbx_host="$(env_val DBX_STAGE_HOST)"

if dbx_auth_check "${dbx_host}"; then
  pass "Databricks CLI can access stage workspace"
else
  fail "Databricks CLI cannot access stage workspace"
  echo "        The deploy scripts use azure-cli auth (your existing az login session)."
  echo "        Verify your login: az account show"
  echo "        Then test: DATABRICKS_HOST=${dbx_host} DATABRICKS_AUTH_TYPE=azure-cli databricks workspace list /"
fi

# ── 2.8 Deploy Databricks bundle ────────────────────────────────────────────

step_header "2.8" "Deploy Databricks bundle"

load_env_if_exists
dbx_host="$(env_val DBX_STAGE_HOST)"

bundle_deployed=false
if DATABRICKS_HOST="${dbx_host}" DATABRICKS_AUTH_TYPE=azure-cli \
    databricks workspace ls "/Workspace/.bundle/${local_project}/stage/files/src/extract" >/dev/null 2>&1; then
  bundle_deployed=true
fi

if [[ "${bundle_deployed}" == "true" ]]; then
  skip "Bundle already deployed to stage"
else
  info "Validating bundle..."
  (cd "${ROOT}" && just bundle-validate stage)

  info "Deploying bundle to stage..."
  (cd "${ROOT}" && just bundle-deploy stage)
  pass "Bundle deployed to stage"
fi

# ── 2.9 Build and push Docker image ─────────────────────────────────────────

step_header "2.9" "Build and push Docker image"

load_env_if_exists
acr="$(env_val ACR_NAME)"

image_exists=false
if [[ -n "${acr}" ]] && az acr repository show-tags --name "${acr}" --repository poc >/dev/null 2>&1; then
  image_exists=true
fi

if [[ "${image_exists}" == "true" ]]; then
  skip "poc image already in ACR"
else
  acr_build
  pass "Docker image built and pushed to ACR"
fi

# ── 2.10 Deploy Dagster via Helm ─────────────────────────────────────────────

step_header "2.10" "Deploy Dagster via Helm"

load_env_if_exists
ns="${local_project}-stage"

pods_ok=false
if kubectl get ns "${ns}" >/dev/null 2>&1; then
  not_ready="$(kubectl get pods -n "${ns}" --no-headers 2>/dev/null | grep -cv "Running\|Completed" || true)"
  if [[ "${not_ready}" -eq 0 ]] && kubectl get pods -n "${ns}" --no-headers 2>/dev/null | grep -q "Running"; then
    pods_ok=true
  fi
fi

if [[ "${pods_ok}" == "true" ]]; then
  skip "Dagster pods running in ${ns}"
else
  info "Deploying Dagster to stage via Helm..."
  (cd "${ROOT}" && just helm-upgrade stage)
  pass "Dagster deployed to ${ns}"

  info "Waiting for pods..."
  kubectl wait --for=condition=Ready pods --all -n "${ns}" --timeout=300s 2>/dev/null || true

  not_ready="$(kubectl get pods -n "${ns}" --no-headers 2>/dev/null | grep -cv "Running\|Completed" || true)"
  if [[ "${not_ready}" -eq 0 ]]; then
    pass "All pods Running in ${ns}"
  else
    fail "${not_ready} pod(s) not Running in ${ns}"
    echo "        Check: kubectl get pods -n ${ns}"
  fi
fi

# ── 2.11 Smoke test ─────────────────────────────────────────────────────────

step_header "2.11" "Smoke test"

echo "  The automated smoke test materializes raw_posts → bronze_posts → silver_posts"
echo "  and verifies the pipeline succeeds end-to-end."
echo ""
read -r -p "Run the automated smoke test now? [Y/n] " reply
if [[ ! "${reply}" =~ ^[nN] ]]; then
  info "Running smoke test (this launches a port-forward, triggers the pipeline, and waits)..."
  if (cd "${ROOT}" && just smoke-test stage); then
    pass "Smoke test passed — Dagster talks to Databricks!"
  else
    fail "Smoke test failed"
    echo "        Try manually: just port-forward stage"
    echo "        Then materialize raw_posts in the Dagster UI at http://localhost:3000"
  fi
else
  skip "Smoke test (run 'just smoke-test stage' when ready)"
  echo ""
  echo "  To test manually:"
  echo "    just port-forward stage   # Dagster UI at http://localhost:3000"
  echo "    Materialize raw_posts in the asset graph"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "  → Goal 1: Dagster on AKS talks to Databricks."

phase_summary 2

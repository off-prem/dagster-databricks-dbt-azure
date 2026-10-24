#!/usr/bin/env bash
# Phase verification — run at the end of each phase to confirm everything is ready
# before proceeding. Usage: scripts/verify.sh <0|1|2|3|4|5>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/scripts/load-env.sh"

PASS=0
FAIL=0
WARN=0

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
warn() { WARN=$((WARN + 1)); echo "  ? $1"; }

check_env() {
  local key="$1" desc="${2:-$1}"
  local val
  val="$(grep "^${key}=" "${ROOT}/.env" 2>/dev/null | head -1 | cut -d'"' -f2)"
  if [ -n "${val}" ]; then pass "${desc} is set"; else fail "${desc} is blank in .env"; fi
}

check_cmd() {
  local cmd="$1" desc="${2:-$1}"
  if command -v "${cmd}" >/dev/null 2>&1; then pass "${desc} installed"; else fail "${desc} not found"; fi
}

summary() {
  echo ""
  echo "  ${PASS} passed, ${FAIL} failed, ${WARN} warnings"
  if [ "${FAIL}" -gt 0 ]; then
    echo "  ⚠ Fix the failures above before proceeding to the next phase."
    exit 1
  else
    echo "  Phase $1 verified — ready to proceed."
  fi
}

# ── Phase 0 ─────────────────────────────────────────────────────────────────

verify_0() {
  echo "Phase 0 — Accounts, tools, and bootstrap"
  echo ""

  echo "Tools:"
  for tool in az terraform helm kubectl databricks just uv gh; do
    check_cmd "${tool}" "${tool}"
  done
  if (cd "${ROOT}/dagster" && uv run dg --version >/dev/null 2>&1); then
    pass "dg installed (via uv in dagster/)"
  else
    fail "dg not found (run: just setup-tools)"
  fi
  if (cd "${ROOT}/dagster" && uv run dbt --version >/dev/null 2>&1); then
    pass "dbt installed (via uv in dagster/)"
  else
    fail "dbt not found (run: just setup-tools)"
  fi

  echo ""
  echo "Azure login:"
  if az account show >/dev/null 2>&1; then pass "az login active"; else fail "not logged in (run az login)"; fi

  echo ""
  echo "Resource providers:"
  for ns in Microsoft.Databricks Microsoft.ContainerService Microsoft.ContainerRegistry \
    Microsoft.DBforPostgreSQL Microsoft.KeyVault Microsoft.ManagedIdentity Microsoft.Storage; do
    local state
    state="$(az provider show -n "${ns}" --query registrationState -o tsv 2>/dev/null || echo "Unknown")"
    if [ "${state}" = "Registered" ]; then pass "${ns}"; else fail "${ns} (${state})"; fi
  done

  echo ""
  echo ".env values (Phase 0):"
  check_env TF_VAR_subscription_id "subscription_id"
  check_env TF_VAR_tenant_id "tenant_id"
  check_env TF_VAR_my_ip_cidr "my_ip_cidr"
  check_env TF_VAR_github_repo "github_repo"
  check_env TF_VAR_github_oidc_prefix "github_oidc_prefix"
  check_env TF_VAR_owner "owner"

  echo ""
  echo "Bootstrap resources:"
  if az group show -n rg-dagster-tfstate >/dev/null 2>&1; then
    pass "rg-dagster-tfstate exists"
  else
    fail "rg-dagster-tfstate not found (run just tf-apply bootstrap)"
  fi

  if az ad app list --display-name app-dagster-github --query '[0].displayName' -o tsv 2>/dev/null | grep -q "app-dagster-github"; then
    pass "Entra app app-dagster-github exists"
  else
    fail "Entra app not found"
  fi

  check_env AZURE_CLIENT_ID "AZURE_CLIENT_ID"
  check_env TF_BACKEND_STORAGE_ACCOUNT "TF_BACKEND_STORAGE_ACCOUNT"
  check_env TF_BACKEND_RESOURCE_GROUP "TF_BACKEND_RESOURCE_GROUP"

  echo ""
  echo "Remote state:"
  local sa
  sa="$(grep "^TF_BACKEND_STORAGE_ACCOUNT=" "${ROOT}/.env" 2>/dev/null | head -1 | cut -d'"' -f2)"
  if [ -n "${sa}" ]; then
    local blobs
    blobs="$(az storage blob list --account-name "${sa}" --container-name tfstate --auth-mode key --query '[].name' -o tsv 2>/dev/null || true)"
    for key in shared.tfstate stage.tfstate prod.tfstate; do
      if echo "${blobs}" | grep -q "^${key}$"; then pass "${key} in blob storage"; else fail "${key} not found in blob storage"; fi
    done
  else
    fail "TF_BACKEND_STORAGE_ACCOUNT not set — cannot check state files"
  fi

  echo ""
  echo "GitHub:"
  if [ -f "${ROOT}/.github/workflows/pr-checks.yml" ]; then
    pass "pr-checks.yml activated"
  else
    fail "pr-checks.yml not in .github/workflows/"
  fi

  local client_id_var
  client_id_var="$(gh api "repos/$(grep "^TF_VAR_github_repo=" "${ROOT}/.env" | head -1 | cut -d'"' -f2)/actions/variables/AZURE_CLIENT_ID" --jq '.value' 2>/dev/null || true)"
  if [ -n "${client_id_var}" ]; then pass "GitHub variable AZURE_CLIENT_ID set"; else warn "Could not verify GitHub variables (check manually)"; fi

  summary 0
}

# ── Phase 1 ─────────────────────────────────────────────────────────────────

verify_1() {
  echo "Phase 1 — Shared infrastructure"
  echo ""

  echo "Resource group:"
  if az group show -n rg-dagster-shared >/dev/null 2>&1; then
    pass "rg-dagster-shared exists"
  else
    fail "rg-dagster-shared not found"
  fi

  echo ""
  echo "Resources:"
  local resources
  resources="$(az resource list -g rg-dagster-shared --query '[].type' -o tsv 2>/dev/null || true)"
  for rtype in "Microsoft.ContainerService/managedClusters" \
    "Microsoft.ContainerRegistry/registries" \
    "Microsoft.KeyVault/vaults" \
    "Microsoft.DBforPostgreSQL/flexibleServers" \
    "Microsoft.Storage/storageAccounts" \
    "Microsoft.Network/virtualNetworks"; do
    if echo "${resources}" | grep -q "${rtype}"; then
      pass "$(echo "${rtype}" | sed 's|.*/||')"
    else
      fail "$(echo "${rtype}" | sed 's|.*/||') not found in rg-dagster-shared"
    fi
  done

  echo ""
  echo ".env values (Phase 1):"
  check_env ACR_NAME "ACR_NAME"
  check_env ACR_LOGIN_SERVER "ACR_LOGIN_SERVER"
  check_env PG_FQDN "PG_FQDN"
  check_env KV_NAME "KV_NAME"
  check_env STORAGE_ACCOUNT_NAME "STORAGE_ACCOUNT_NAME"

  echo ""
  echo "AKS connectivity:"
  if kubectl get nodes >/dev/null 2>&1; then
    local status
    status="$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    if [ "${status}" = "True" ]; then pass "AKS node Ready"; else fail "AKS node not Ready (${status})"; fi
  else
    fail "kubectl cannot reach AKS (run: az aks get-credentials -g rg-dagster-shared -n aks-dagster)"
  fi

  echo ""
  echo "Key Vault:"
  local kv
  kv="$(grep "^KV_NAME=" "${ROOT}/.env" 2>/dev/null | head -1 | cut -d'"' -f2)"
  if [ -n "${kv}" ]; then
    if az keyvault secret show --vault-name "${kv}" --name pg-admin-password >/dev/null 2>&1; then
      pass "pg-admin-password in Key Vault"
    else
      fail "pg-admin-password not found in Key Vault (see guide step 1.2)"
    fi
  else
    fail "KV_NAME not set"
  fi

  summary 1
}

# ── Phase 2 ─────────────────────────────────────────────────────────────────

verify_2() {
  echo "Phase 2 — Stage environment"
  echo ""

  echo "Workspace:"
  if az databricks workspace show -g rg-dagster-stage -n dbw-dagster-stage >/dev/null 2>&1; then
    pass "dbw-dagster-stage exists"
  else
    fail "dbw-dagster-stage not found"
  fi

  echo ""
  echo ".env values (Phase 2):"
  check_env DBX_STAGE_HOST "DBX_STAGE_HOST"
  check_env DBX_STAGE_SP_CLIENT_ID "DBX_STAGE_SP_CLIENT_ID"
  check_env DBX_STAGE_WAREHOUSE_HTTP_PATH "DBX_STAGE_WAREHOUSE_HTTP_PATH"
  check_env TF_VAR_metastore_id "metastore_id"

  echo ""
  echo "Key Vault secrets:"
  local kv
  kv="$(grep "^KV_NAME=" "${ROOT}/.env" 2>/dev/null | head -1 | cut -d'"' -f2)"
  if [ -n "${kv}" ]; then
    for secret in dbx-stage-sp-client-id dbx-stage-sp-secret; do
      if az keyvault secret show --vault-name "${kv}" --name "${secret}" >/dev/null 2>&1; then
        pass "${secret} in Key Vault"
      else
        fail "${secret} not found in Key Vault"
      fi
    done
  fi

  echo ""
  echo "Docker image:"
  local acr
  acr="$(grep "^ACR_NAME=" "${ROOT}/.env" 2>/dev/null | head -1 | cut -d'"' -f2)"
  if [ -n "${acr}" ]; then
    if az acr repository show-tags --name "${acr}" --repository poc >/dev/null 2>&1; then
      pass "poc image in ACR"
    else
      fail "poc image not found in ACR (run az acr build)"
    fi
  fi

  echo ""
  echo "Dagster pods:"
  if kubectl get ns dagster-stage >/dev/null 2>&1; then
    local not_ready
    not_ready="$(kubectl get pods -n dagster-stage --no-headers 2>/dev/null | grep -cv "Running\|Completed" || true)"
    if [ "${not_ready}" -eq 0 ]; then
      pass "All pods Running in dagster-stage"
    else
      fail "${not_ready} pod(s) not Running in dagster-stage"
    fi
  else
    fail "Namespace dagster-stage not found (run just helm-upgrade stage)"
  fi

  summary 2
}

# ── Phase 3 ─────────────────────────────────────────────────────────────────

verify_3() {
  echo "Phase 3 — End-to-end pipeline"
  echo ""

  echo "Bundle:"
  check_env DBX_STAGE_PIPELINE_ID "DBX_STAGE_PIPELINE_ID"

  echo ""
  echo "Dagster definitions:"
  if (cd "${ROOT}/dagster" && uv run dg check defs >/dev/null 2>&1); then
    pass "dg check defs passes"
  else
    fail "dg check defs failed"
  fi

  echo ""
  echo "Tests:"
  if (cd "${ROOT}/dagster" && uv run pytest -q >/dev/null 2>&1); then
    pass "pytest passes"
  else
    fail "pytest failed"
  fi

  echo ""
  echo "dbt:"
  if (cd "${ROOT}/dagster" && uv run dbt debug --project-dir "${ROOT}/dbt" --target stage >/dev/null 2>&1); then
    pass "dbt debug connects to stage warehouse"
  else
    fail "dbt debug failed (check DBX_STAGE_* env vars)"
  fi

  summary 3
}

# ── Phase 4 ─────────────────────────────────────────────────────────────────

verify_4() {
  echo "Phase 4 — Prod"
  echo ""

  echo "Workspace:"
  if az databricks workspace show -g rg-dagster-prod -n dbw-dagster-prod >/dev/null 2>&1; then
    pass "dbw-dagster-prod exists"
  else
    fail "dbw-dagster-prod not found"
  fi

  echo ""
  echo ".env values (Phase 4):"
  check_env DBX_PROD_HOST "DBX_PROD_HOST"
  check_env DBX_PROD_SP_CLIENT_ID "DBX_PROD_SP_CLIENT_ID"
  check_env DBX_PROD_WAREHOUSE_HTTP_PATH "DBX_PROD_WAREHOUSE_HTTP_PATH"
  check_env DBX_PROD_PIPELINE_ID "DBX_PROD_PIPELINE_ID"

  echo ""
  echo "Dagster pods:"
  if kubectl get ns dagster-prod >/dev/null 2>&1; then
    local not_ready
    not_ready="$(kubectl get pods -n dagster-prod --no-headers 2>/dev/null | grep -cv "Running\|Completed" || true)"
    if [ "${not_ready}" -eq 0 ]; then
      pass "All pods Running in dagster-prod"
    else
      fail "${not_ready} pod(s) not Running in dagster-prod"
    fi
  else
    fail "Namespace dagster-prod not found"
  fi

  summary 4
}

# ── Phase 5 ─────────────────────────────────────────────────────────────────

verify_5() {
  echo "Phase 5 — CI/CD"
  echo ""

  echo "Workflows:"
  for wf in pr-checks deploy-stage promote-prod; do
    if [ -f "${ROOT}/.github/workflows/${wf}.yml" ]; then
      pass "${wf}.yml activated"
    else
      fail "${wf}.yml not in .github/workflows/"
    fi
  done

  echo ""
  echo "GitHub environments:"
  local repo
  repo="$(grep "^TF_VAR_github_repo=" "${ROOT}/.env" 2>/dev/null | head -1 | cut -d'"' -f2)"
  if [ -n "${repo}" ]; then
    for env_name in stage prod; do
      if gh api "repos/${repo}/environments/${env_name}" >/dev/null 2>&1; then
        pass "Environment '${env_name}' exists"
      else
        fail "Environment '${env_name}' not found"
      fi
    done
  fi

  summary 5
}

# ── Main ────────────────────────────────────────────────────────────────────

case "${1:-}" in
  0) verify_0 ;;
  1) verify_1 ;;
  2) verify_2 ;;
  3) verify_3 ;;
  4) verify_4 ;;
  5) verify_5 ;;
  *) echo "Usage: $0 <0|1|2|3|4|5>"; exit 1 ;;
esac

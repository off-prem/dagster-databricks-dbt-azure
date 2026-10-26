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
  for tool in az terraform helm kubectl kubelogin databricks just uv gh; do
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
  echo "Project settings:"
  check_env TF_VAR_project "project"
  check_env TF_VAR_location "location"

  local project
  project="$(grep "^TF_VAR_project=" "${ROOT}/.env" 2>/dev/null | head -1 | cut -d'"' -f2)"
  project="${project:-dagster}"

  echo ""
  echo "Bootstrap resources:"
  if az group show -n "rg-${project}-tfstate" >/dev/null 2>&1; then
    pass "rg-${project}-tfstate exists"
  else
    fail "rg-${project}-tfstate not found (run just tf-apply bootstrap)"
  fi

  if az ad app list --display-name "app-${project}-github" --query '[0].displayName' -o tsv 2>/dev/null | grep -q "app-${project}-github"; then
    pass "Entra app app-${project}-github exists"
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

  echo ""
  echo "Code projects:"
  local dagster_venv="${ROOT}/dagster/.venv/bin"
  local dummy_env="DATABRICKS_HOST=https://dummy.azuredatabricks.net DATABRICKS_TOKEN=dapi_dummy DBX_CATALOG=stage DBX_WAREHOUSE_HTTP_PATH=/sql/dummy DBX_SP_CLIENT_ID=dummy DBX_SP_SECRET=dummy DBX_BUNDLE_ROOT=/Workspace/.bundle/dagster/stage"
  if [ ! -f "${dagster_venv}/dbt" ]; then
    fail "dagster venv not found (run: cd dagster && uv sync)"
  else
    if (cd "${ROOT}" && PATH="${dagster_venv}:${PATH}" env ${dummy_env} \
        dbt parse --project-dir dbt --profiles-dir dbt >/dev/null 2>&1); then
      pass "dbt parse succeeds"
    else
      fail "dbt parse failed (check dbt models and sources)"
    fi
    if (cd "${ROOT}/dagster" && PATH="${dagster_venv}:${PATH}" env ${dummy_env} \
        dagster definitions validate -m poc -d src 2>&1 | grep -q "passed validation"); then
      pass "dagster definitions validate succeeds"
    else
      fail "dagster definitions validate failed (check Dagster assets)"
    fi
  fi

  summary 0
}

# ── Phase 1 ─────────────────────────────────────────────────────────────────

check_skus() {
  echo "SKU pre-flight:"

  local location
  location="$(grep "^TF_VAR_location=" "${ROOT}/.env" 2>/dev/null | head -1 | cut -d'"' -f2)"
  location="${location:-eastus2}"

  local aks_vm_size
  aks_vm_size="$(grep "^TF_VAR_aks_vm_size=" "${ROOT}/.env" 2>/dev/null | head -1 | cut -d'"' -f2 || true)"
  aks_vm_size="${aks_vm_size:-Standard_D2as_v6}"

  local pg_location
  pg_location="$(grep "^TF_VAR_pg_location=" "${ROOT}/.env" 2>/dev/null | head -1 | cut -d'"' -f2 || true)"
  pg_location="${pg_location:-centralus}"

  local pg_sku_name
  pg_sku_name="$(grep "^TF_VAR_pg_sku_name=" "${ROOT}/.env" 2>/dev/null | head -1 | cut -d'"' -f2 || true)"
  pg_sku_name="${pg_sku_name:-B_Standard_B2s}"

  # ── AKS VM size ──
  local aks_sku_json
  aks_sku_json="$(az vm list-skus --size "${aks_vm_size}" --location "${location}" -o json 2>/dev/null || echo "[]")"
  local aks_sku_count
  aks_sku_count="$(echo "${aks_sku_json}" | python3 -c "import json,sys; data=json.load(sys.stdin); print(len(data))" 2>/dev/null || echo "0")"

  if [ "${aks_sku_count}" = "0" ]; then
    fail "AKS VM size ${aks_vm_size} not found in ${location}"
    echo "        Try: az vm list-skus --location ${location} --size Standard_D2 -o table"
    echo "        Then set TF_VAR_aks_vm_size in .env to an available size"
  else
    local aks_restricted
    aks_restricted="$(echo "${aks_sku_json}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for sku in data:
    for r in sku.get('restrictions', []):
        if r.get('reasonCode') == 'NotAvailableForSubscription' and r.get('type') == 'Location':
            print('blocked')
            sys.exit(0)
print('ok')
" 2>/dev/null || echo "unknown")"

    if [ "${aks_restricted}" = "blocked" ]; then
      fail "AKS VM size ${aks_vm_size} is blocked for your subscription in ${location}"
      echo "        Try: az vm list-skus --location ${location} --size Standard_D2 -o table"
      echo "        Then set TF_VAR_aks_vm_size in .env to an unrestricted size"
    else
      pass "AKS VM size ${aks_vm_size} available in ${location}"
    fi
  fi

  # ── Postgres SKU ──
  local pg_tier pg_compute
  pg_tier="$(echo "${pg_sku_name}" | cut -d_ -f1)"
  pg_compute="$(echo "${pg_sku_name}" | cut -d_ -f2-)"

  local pg_edition
  case "${pg_tier}" in
    B)  pg_edition="Burstable" ;;
    GP) pg_edition="GeneralPurpose" ;;
    MO) pg_edition="MemoryOptimized" ;;
    *)  pg_edition="" ;;
  esac

  local pg_skus_json
  pg_skus_json="$(az postgres flexible-server list-skus --location "${pg_location}" -o json 2>/dev/null || echo "[]")"

  local pg_match
  pg_match="$(echo "${pg_skus_json}" | python3 -c "
import json, sys
edition = '${pg_edition}'
compute = '${pg_compute}'
data = json.load(sys.stdin)
for cap in data:
    for ed in cap.get('supportedServerEditions', []):
        if ed['name'] == edition:
            for sku in ed.get('supportedServerSkus', []):
                if sku['name'] == compute:
                    print('found')
                    sys.exit(0)
print('missing')
" 2>/dev/null || echo "error")"

  if [ "${pg_match}" = "found" ]; then
    pass "Postgres SKU ${pg_sku_name} available in ${pg_location}"
  elif [ "${pg_match}" = "missing" ]; then
    fail "Postgres SKU ${pg_sku_name} not available in ${pg_location}"

    local alt_regions=""
    for region in centralus eastus eastus2 westus2 northeurope westeurope; do
      [ "${region}" = "${pg_location}" ] && continue
      local check
      check="$(az postgres flexible-server list-skus --location "${region}" -o json 2>/dev/null || echo "[]")"
      local found
      found="$(echo "${check}" | python3 -c "
import json, sys
edition = '${pg_edition}'
compute = '${pg_compute}'
data = json.load(sys.stdin)
for cap in data:
    for ed in cap.get('supportedServerEditions', []):
        if ed['name'] == edition:
            for sku in ed.get('supportedServerSkus', []):
                if sku['name'] == compute:
                    print('yes')
                    sys.exit(0)
print('no')
" 2>/dev/null || echo "no")"
      if [ "${found}" = "yes" ]; then
        alt_regions="${alt_regions} ${region}"
      fi
    done

    if [ -n "${alt_regions}" ]; then
      echo "        Available in:${alt_regions}"
      echo "        Set TF_VAR_pg_location in .env to one of these regions"
    else
      echo "        No B-series Postgres found — upgrade to Pay-As-You-Go or use GP tier"
      echo "        Set TF_VAR_pg_sku_name=GP_Standard_D2ds_v5 in .env (costs more)"
    fi
  else
    warn "Could not check Postgres SKU availability (API error)"
  fi
}

verify_1() {
  echo "Phase 1 — Shared infrastructure"
  echo ""

  check_skus

  echo ""
  local project
  project="$(grep "^TF_VAR_project=" "${ROOT}/.env" 2>/dev/null | head -1 | cut -d'"' -f2)"
  project="${project:-dagster}"

  echo "Resource group:"
  if az group show -n "rg-${project}-shared" >/dev/null 2>&1; then
    pass "rg-${project}-shared exists"
  else
    fail "rg-${project}-shared not found"
  fi

  echo ""
  echo "Resources:"
  local resources
  resources="$(az resource list -g "rg-${project}-shared" --query '[].type' -o tsv 2>/dev/null || true)"
  for rtype in "Microsoft.ContainerService/managedClusters" \
    "Microsoft.ContainerRegistry/registries" \
    "Microsoft.KeyVault/vaults" \
    "Microsoft.DBforPostgreSQL/flexibleServers" \
    "Microsoft.Storage/storageAccounts" \
    "Microsoft.Network/virtualNetworks"; do
    if echo "${resources}" | grep -q "${rtype}"; then
      pass "$(echo "${rtype}" | sed 's|.*/||')"
    else
      fail "$(echo "${rtype}" | sed 's|.*/||') not found in rg-${project}-shared"
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
    fail "kubectl cannot reach AKS (run: az aks get-credentials -g rg-${project}-shared -n aks-${project})"
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

  local project
  project="$(grep "^TF_VAR_project=" "${ROOT}/.env" 2>/dev/null | head -1 | cut -d'"' -f2)"
  project="${project:-dagster}"

  echo "Workspace:"
  if az databricks workspace show -g "rg-${project}-stage" -n "dbw-${project}-stage" >/dev/null 2>&1; then
    pass "dbw-${project}-stage exists"
  else
    fail "dbw-${project}-stage not found"
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
  echo "Dummy API key:"
  if [ -n "${kv}" ]; then
    if az keyvault secret show --vault-name "${kv}" --name source-posts-api-key >/dev/null 2>&1; then
      pass "source-posts-api-key in Key Vault"
    else
      fail "source-posts-api-key not found in Key Vault (see guide step 2.5)"
    fi
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
  if kubectl get ns "${project}-stage" >/dev/null 2>&1; then
    local not_ready
    not_ready="$(kubectl get pods -n "${project}-stage" --no-headers 2>/dev/null | grep -cv "Running\|Completed" || true)"
    if [ "${not_ready}" -eq 0 ]; then
      pass "All pods Running in ${project}-stage"
    else
      fail "${not_ready} pod(s) not Running in ${project}-stage"
    fi
  else
    fail "Namespace ${project}-stage not found (run just helm-upgrade stage)"
  fi

  summary 2
}

# ── Phase 3 ─────────────────────────────────────────────────────────────────

verify_3() {
  echo "Phase 3 — End-to-end pipeline"
  echo ""

  # dbt and dagster-dbt need Databricks env vars to connect / parse
  export DATABRICKS_HOST="${DBX_STAGE_HOST:-}"
  export DBX_WAREHOUSE_HTTP_PATH="${DBX_STAGE_WAREHOUSE_HTTP_PATH:-}"
  export DBX_SP_CLIENT_ID="${DBX_STAGE_SP_CLIENT_ID:-}"
  export DBX_CATALOG=stage
  export DAGSTER_ENV=stage
  if [ -z "${DBX_SP_SECRET:-}" ]; then
    local kv
    kv="$(grep "^KV_NAME=" "${ROOT}/.env" 2>/dev/null | head -1 | cut -d'"' -f2)"
    if [ -n "${kv}" ]; then
      export DBX_SP_SECRET="$(az keyvault secret show --vault-name "${kv}" --name "dbx-stage-sp-secret" --query value -o tsv 2>/dev/null || true)"
    fi
  fi

  echo "dbt connection:"
  if (cd "${ROOT}/dagster" && uv run dbt debug --project-dir "${ROOT}/dbt" --profiles-dir "${ROOT}/dbt" --target stage >/dev/null 2>&1); then
    pass "dbt debug connects to stage warehouse"
  else
    fail "dbt debug failed (check DBX_STAGE_* env vars)"
  fi

  echo ""
  echo "Dagster definitions:"
  export DAGSTER_DBT_PARSE_PROJECT_ON_LOAD=1
  export DBT_PROFILES_DIR="${ROOT}/dbt"
  export DBX_BUNDLE_ROOT="/Workspace/.bundle/${TF_VAR_project:-dagster}/stage/files"
  if (cd "${ROOT}/dagster" && uv run dagster definitions validate -m poc.definitions >/dev/null 2>&1); then
    pass "dagster definitions validate passes"
  else
    fail "dagster definitions validate failed"
  fi

  summary 3
}

# ── Phase 4 ─────────────────────────────────────────────────────────────────

verify_4() {
  echo "Phase 4 — Prod"
  echo ""

  local project
  project="$(grep "^TF_VAR_project=" "${ROOT}/.env" 2>/dev/null | head -1 | cut -d'"' -f2)"
  project="${project:-dagster}"

  echo "Workspace:"
  if az databricks workspace show -g "rg-${project}-prod" -n "dbw-${project}-prod" >/dev/null 2>&1; then
    pass "dbw-${project}-prod exists"
  else
    fail "dbw-${project}-prod not found"
  fi

  echo ""
  echo ".env values (Phase 4):"
  check_env DBX_PROD_HOST "DBX_PROD_HOST"
  check_env DBX_PROD_SP_CLIENT_ID "DBX_PROD_SP_CLIENT_ID"
  check_env DBX_PROD_WAREHOUSE_HTTP_PATH "DBX_PROD_WAREHOUSE_HTTP_PATH"

  echo ""
  echo "Dagster pods:"
  if kubectl get ns "${project}-prod" >/dev/null 2>&1; then
    local not_ready
    not_ready="$(kubectl get pods -n "${project}-prod" --no-headers 2>/dev/null | grep -cv "Running\|Completed" || true)"
    if [ "${not_ready}" -eq 0 ]; then
      pass "All pods Running in ${project}-prod"
    else
      fail "${not_ready} pod(s) not Running in ${project}-prod"
    fi
  else
    fail "Namespace ${project}-prod not found"
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

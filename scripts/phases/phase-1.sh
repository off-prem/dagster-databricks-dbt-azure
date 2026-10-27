#!/usr/bin/env bash
# Phase 1 — Shared infrastructure
#
# This is where costs begin (~$50-100/month running, ~$35-40/month stopped).
# Creates: VNet, ACR, Key Vault, Postgres, ADLS, AKS.
# Re-running safely skips completed steps.
#
# Usage: scripts/phases/phase-1.sh
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_env_if_exists

phase_header 1 "Shared infrastructure"
echo "  This is where costs begin. See docs/costs.md for the full breakdown."
echo "  Run 'just stop' when idle to reduce costs."
echo ""
echo "  Re-running safely skips completed steps."

# ── Pre-flight checks ───────────────────────────────────────────────────────

step_header "1.1" "Pre-flight checks"

require_az_login || exit 1

# Check .env prerequisites from Phase 0
for key in TF_VAR_subscription_id TF_VAR_project TF_VAR_location TF_BACKEND_STORAGE_ACCOUNT; do
  require_env "${key}" "Run 'just phase 0' first" || exit 1
done

# SKU availability check (from verify.sh)
local_project="$(project_name)"
location="$(env_val TF_VAR_location)"
location="${location:-eastus2}"

aks_vm_size="$(env_val TF_VAR_aks_vm_size)"
aks_vm_size="${aks_vm_size:-Standard_D2as_v6}"

pg_location="$(env_val TF_VAR_pg_location)"
pg_location="${pg_location:-centralus}"

pg_sku_name="$(env_val TF_VAR_pg_sku_name)"
pg_sku_name="${pg_sku_name:-B_Standard_B2s}"

info "Checking SKU availability..."

# AKS VM size
aks_sku_json="$(az vm list-skus --size "${aks_vm_size}" --location "${location}" -o json 2>/dev/null || echo "[]")"
aks_blocked="$(echo "${aks_sku_json}" | python3 -I -c "
import json, sys
data = json.load(sys.stdin)
if not data:
    print('missing')
    sys.exit(0)
for sku in data:
    for r in sku.get('restrictions', []):
        if r.get('reasonCode') == 'NotAvailableForSubscription' and r.get('type') == 'Location':
            print('blocked')
            sys.exit(0)
print('ok')
" 2>/dev/null || echo "unknown")"

case "${aks_blocked}" in
  ok) pass "AKS VM size ${aks_vm_size} available in ${location}" ;;
  missing)
    fail "AKS VM size ${aks_vm_size} not found in ${location}"
    echo "        Try: az vm list-skus --location ${location} --size Standard_D2 -o table"
    echo "        Then: just set-env TF_VAR_aks_vm_size <available-size>"
    ;;
  blocked)
    fail "AKS VM size ${aks_vm_size} blocked for your subscription in ${location}"
    echo "        Try: az vm list-skus --location ${location} --size Standard_D2 -o table"
    echo "        Then: just set-env TF_VAR_aks_vm_size <unrestricted-size>"
    ;;
  *) warn "Could not check AKS VM size (API error)" ;;
esac

# Postgres SKU
pg_tier="$(echo "${pg_sku_name}" | cut -d_ -f1)"
pg_compute="$(echo "${pg_sku_name}" | cut -d_ -f2-)"
case "${pg_tier}" in
  B)  pg_edition="Burstable" ;;
  GP) pg_edition="GeneralPurpose" ;;
  MO) pg_edition="MemoryOptimized" ;;
  *)  pg_edition="" ;;
esac

pg_match="$(az postgres flexible-server list-skus --location "${pg_location}" -o json 2>/dev/null | python3 -I -c "
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

case "${pg_match}" in
  found) pass "Postgres SKU ${pg_sku_name} available in ${pg_location}" ;;
  missing)
    fail "Postgres SKU ${pg_sku_name} not available in ${pg_location}"
    echo "        Try setting TF_VAR_pg_location to centralus, eastus, or westus2"
    echo "        just set-env TF_VAR_pg_location centralus"
    ;;
  *) warn "Could not check Postgres SKU (API error)" ;;
esac

if [[ ${_FAIL} -gt 0 ]]; then
  echo ""
  printf "  ${RED}Fix the SKU issues above before continuing.${NC}\n"
  echo "  Re-run this phase after updating .env."
  exit 1
fi

# ── 1.2 Apply shared infrastructure ─────────────────────────────────────────

step_header "1.2" "Apply shared infrastructure"

shared_done=false
if az group show -n "rg-${local_project}-shared" >/dev/null 2>&1 \
   && check_env ACR_NAME \
   && check_env PG_FQDN \
   && check_env KV_NAME; then
  shared_done=true
fi

if [[ "${shared_done}" == "true" ]]; then
  skip "Shared infrastructure exists (rg-${local_project}-shared with ACR, PG, KV, AKS)"
else
  info "Initializing Terraform for shared stack..."
  (cd "${ROOT}" && just tf-init shared -upgrade)

  echo ""
  echo "This creates: VNet, ACR (~\$5/mo), Key Vault (<\$1/mo), Postgres (~\$25/mo),"
  echo "ADLS (~\$2/mo), AKS (see docs/costs.md). Takes ~10-15 minutes."
  echo ""

  tf_plan_confirm_apply shared

  info "Capturing shared outputs..."
  "${ROOT}/scripts/setup-env.sh" collect-tf shared
  source "${ROOT}/scripts/load-env.sh"
  pass "Shared outputs captured to .env"
fi

# ── 1.3 Verify connectivity ─────────────────────────────────────────────────

step_header "1.3" "Verify connectivity"

load_env_if_exists
local_project="$(project_name)"

# Get kubeconfig
if ! kubectl get nodes >/dev/null 2>&1; then
  info "Fetching AKS credentials..."
  az aks get-credentials \
    --resource-group "rg-${local_project}-shared" \
    --name "aks-${local_project}" \
    --overwrite-existing
fi

if kubectl get nodes >/dev/null 2>&1; then
  node_status="$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  if [[ "${node_status}" == "True" ]]; then
    pass "AKS node Ready"
  else
    fail "AKS node not Ready (status: ${node_status})"
  fi
else
  fail "kubectl cannot reach AKS"
fi

# Check Key Vault
kv="$(env_val KV_NAME)"
if [[ -n "${kv}" ]] && kv_secret_exists "${kv}" pg-admin-password; then
  pass "pg-admin-password in Key Vault"
else
  fail "pg-admin-password not found in Key Vault"
fi

# ── 1.4 Test stop/start ─────────────────────────────────────────────────────

step_header "1.4" "Test stop/start (optional)"

echo "  You can test the cost-saving stop/start cycle now:"
echo "    just stop     # stops AKS + Postgres (~2-3 min)"
echo "    just start    # restarts (~3-5 min)"
echo "    kubectl get nodes  # verify Ready"
echo ""
echo "  Skipping this test — you can run it anytime."
echo "  See docs/concepts/stop-start.md for details."
skip "Stop/start test (run manually when convenient)"

# ── Verify and summarize ────────────────────────────────────────────────────

step_header "1.✓" "Phase verification"

load_env_if_exists
local_project="$(project_name)"

# Resources
resources="$(az resource list -g "rg-${local_project}-shared" --query '[].type' -o tsv 2>/dev/null || true)"
for rtype in "Microsoft.ContainerService/managedClusters" \
  "Microsoft.ContainerRegistry/registries" \
  "Microsoft.KeyVault/vaults" \
  "Microsoft.DBforPostgreSQL/flexibleServers" \
  "Microsoft.Storage/storageAccounts" \
  "Microsoft.Network/virtualNetworks"; do
  short="$(echo "${rtype}" | sed 's|.*/||')"
  if echo "${resources}" | grep -q "${rtype}"; then
    pass "${short} exists in rg-${local_project}-shared"
  else
    fail "${short} not found in rg-${local_project}-shared"
  fi
done

# .env values
for key in ACR_NAME ACR_LOGIN_SERVER PG_FQDN KV_NAME STORAGE_ACCOUNT_NAME AKS_EGRESS_IP; do
  if check_env "${key}"; then
    pass "${key} set in .env"
  else
    fail "${key} blank in .env"
  fi
done

phase_summary 1

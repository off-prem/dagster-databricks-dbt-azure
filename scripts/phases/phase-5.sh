#!/usr/bin/env bash
# Phase 5 — CI/CD (Goal 4: automated promotion)
#
# Sets up GitHub Actions with self-hosted runners (ARC), syncs variables,
# and validates the full main → stage → approval → prod flow.
# Re-running safely skips completed steps.
#
# Usage: scripts/phases/phase-5.sh
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_env_if_exists

phase_header 5 "CI/CD"
echo "  Goal: automated promotion (main → stage → approval → prod)."
echo "  Re-running safely skips completed steps."

# ── Pre-flight ───────────────────────────────────────────────────────────────

require_az_login || exit 1
require_gh_login || exit 1

for key in TF_VAR_project TF_VAR_github_repo AZURE_CLIENT_ID \
           DBX_STAGE_HOST DBX_PROD_HOST KV_NAME; do
  require_env "${key}" "Run previous phases first" || exit 1
done

local_project="$(project_name)"
repo="$(env_val TF_VAR_github_repo)"

# ── 5.1 Sync GitHub variables and environments ──────────────────────────────

step_header "5.1" "Sync GitHub variables and environments"

info "Syncing all .env values to GitHub repository variables..."
"${ROOT}/scripts/setup-ci.sh"
pass "GitHub variables and environments synced"

# Verify
var_count="$(gh variable list --repo "${repo}" --json name --jq 'length' 2>/dev/null || echo 0)"
if [[ "${var_count}" -ge 15 ]]; then
  pass "${var_count} repository variables set"
else
  warn "Only ${var_count} variables set (expected ~18)"
fi

for env_name in stage prod; do
  if gh api "repos/${repo}/environments/${env_name}" >/dev/null 2>&1; then
    pass "Environment '${env_name}' exists"
  else
    fail "Environment '${env_name}' not found"
  fi
done

# ── 5.2 Grant OIDC SP access to AKS and Databricks ──────────────────────────

step_header "5.2" "Grant OIDC SP access to AKS and Databricks"

load_env_if_exists
client_id="$(env_val AZURE_CLIENT_ID)"

# AKS RBAC — re-apply shared stack (includes the role assignment)
info "Ensuring OIDC SP has AKS RBAC Cluster Admin (via shared Terraform)..."
echo "  If the shared stack already includes this role assignment, the plan"
echo "  will show no changes."
echo ""

# Check if plan shows changes
plan_output="$(cd "${ROOT}" && just tf-plan shared 2>&1 || true)"
if echo "${plan_output}" | grep -q "No changes\|0 to add, 0 to change"; then
  skip "Shared stack has no pending changes (OIDC SP role assignment already in place)"
else
  echo "${plan_output}"
  echo ""
  read -r -p "Apply these changes? [y/N] " confirm
  case "${confirm}" in
    [yY]|[yY][eE][sS])
      (cd "${ROOT}" && just tf-apply shared -auto-approve)
      pass "Shared stack updated"
      ;;
    *)
      warn "Skipped shared stack apply"
      ;;
  esac
fi

# Databricks workspace user + entitlement
info "Ensuring OIDC SP is a workspace user with workspace-access entitlement..."
for host_var in DBX_STAGE_HOST DBX_PROD_HOST; do
  host="$(env_val "${host_var}")"
  [[ -z "${host}" ]] && continue
  env_label="${host_var#DBX_}"
  env_label="${env_label%_HOST}"

  echo "  ${env_label}: ${host}"

  # Create SP in workspace (idempotent — errors on duplicate are OK)
  DATABRICKS_HOST="${host}" DATABRICKS_AUTH_TYPE=azure-cli \
    databricks service-principals create \
      --application-id "${client_id}" --display-name "app-${local_project}-github" 2>/dev/null || true

  # Get the SP's workspace ID
  sp_id="$(DATABRICKS_HOST="${host}" DATABRICKS_AUTH_TYPE=azure-cli \
    databricks service-principals list \
      --filter "applicationId eq '${client_id}'" -o json 2>/dev/null | jq -r '.[0].id' 2>/dev/null || true)"

  if [[ -n "${sp_id}" && "${sp_id}" != "null" ]]; then
    # Grant workspace-access entitlement
    DATABRICKS_HOST="${host}" DATABRICKS_AUTH_TYPE=azure-cli \
      databricks service-principals patch "${sp_id}" \
        --json '{"Operations": [{"op": "add", "path": "entitlements", "value": [{"value": "workspace-access"}]}], "schemas": ["urn:ietf:params:scim:api:messages:2.0:PatchOp"]}' 2>/dev/null || true
    pass "${env_label}: SP has workspace-access entitlement"
  else
    warn "${env_label}: Could not find SP in workspace — verify manually"
  fi
done

# ── 5.3 Create GitHub App for ARC ───────────────────────────────────────────

step_header "5.3" "Create GitHub App for ARC"

if check_env ARC_GITHUB_APP_ID && check_env ARC_GITHUB_APP_INSTALLATION_ID; then
  skip "GitHub App IDs already set"
else
  kv="$(kv_name)"

  wait_for_manual \
"Create a GitHub App for ARC (self-hosted runners):

1. GitHub → Settings → Developer settings → GitHub Apps → New GitHub App
   - Name: arc-runner-${local_project}
   - Homepage URL: https://github.com/${repo}
   - Uncheck 'Webhook → Active'
   - Permissions → Repository: Administration (Read & Write), Metadata (Read-only)
   - Permissions → Organization: Self-hosted runners (Read & Write)
   - Where can this be installed: Only on this account
   - Create, then Install on your repo

2. Generate a private key (Settings → Private keys → Generate)
   Downloads a .pem file

3. Store the private key in Key Vault:
     az keyvault secret set --vault-name '${kv}' \\
       --name arc-github-app-key \\
       --file <path-to-downloaded-pem-file>

4. Record the App ID and Installation ID:
     just set-env ARC_GITHUB_APP_ID <app-id>
     just set-env ARC_GITHUB_APP_INSTALLATION_ID <installation-id>
   (Installation ID: Settings → Installations → click → number in the URL)" \
    bash -c "grep -q 'ARC_GITHUB_APP_ID=\"[^\"]\+\"' '${ROOT}/.env' && grep -q 'ARC_GITHUB_APP_INSTALLATION_ID=\"[^\"]\+\"' '${ROOT}/.env'"

  source "${ROOT}/scripts/load-env.sh"
fi

# ── 5.4 Install ARC on AKS ──────────────────────────────────────────────────

step_header "5.4" "Install ARC on AKS"

arc_running=false
if kubectl get pods -n arc-systems --no-headers 2>/dev/null | grep -q "Running"; then
  arc_running=true
fi

if [[ "${arc_running}" == "true" ]]; then
  skip "ARC controller already running in arc-systems"
else
  load_env_if_exists
  info "Fetching AKS credentials..."
  az aks get-credentials --resource-group "rg-${local_project}-shared" \
    --name "aks-${local_project}" --overwrite-existing

  info "Installing ARC..."
  "${ROOT}/scripts/setup-arc.sh"
  pass "ARC installed"
fi

# Verify
if kubectl get pods -n arc-systems --no-headers 2>/dev/null | grep -q "Running"; then
  pass "ARC controller + listener running"
else
  fail "ARC pods not running in arc-systems"
fi

# ── 5.5 Verify workflows ────────────────────────────────────────────────────

step_header "5.5" "Verify workflow files"

for wf in pr-checks deploy-stage promote-prod; do
  if [[ -f "${ROOT}/.github/workflows/${wf}.yml" ]]; then
    if grep -q "TODO" "${ROOT}/.github/workflows/${wf}.yml" 2>/dev/null; then
      warn "${wf}.yml still has TODO stubs"
    else
      pass "${wf}.yml present and activated"
    fi
  else
    fail "${wf}.yml not in .github/workflows/"
  fi
done

# ── 5.6 First prod promotion ────────────────────────────────────────────────

step_header "5.6" "First prod promotion"

echo "  Push a trivial PR to test the full CI/CD flow:"
echo ""
echo "  1. Create a branch with a small change"
echo "  2. Open a PR → pr-checks runs on GitHub-hosted runners"
echo "  3. Merge → deploy-stage runs on ARC"
echo "  4. GitHub → Actions → promote-prod → Review deployments → Approve"
echo ""
echo "  The workflow scope token may need refreshing:"
echo "    gh auth refresh -s workflow --web=false"
echo ""
skip "First promotion (run manually)"

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "  → Goal 4: automated promotion (main → stage → approval → prod)."

phase_summary 5

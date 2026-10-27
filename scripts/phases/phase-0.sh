#!/usr/bin/env bash
# Phase 0 — Accounts, tools, and bootstrap
#
# This phase costs nothing. It sets up accounts, installs tools, bootstraps
# Terraform state, and configures CI. Re-running skips completed steps.
#
# Usage: scripts/phases/phase-0.sh
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

phase_header 0 "Accounts, tools, and bootstrap"
echo "  This phase costs nothing."
echo "  Re-running safely skips completed steps."

# ── 0.1 Verify repo clone ───────────────────────────────────────────────────

step_header "0.1" "Verify repo clone"

if git -C "${ROOT}" remote get-url origin >/dev/null 2>&1; then
  pass "Git remote 'origin': $(git -C "${ROOT}" remote get-url origin)"
else
  fail "No git remote 'origin' — clone the repo first (see docs/guide.md step 0.1)"
  exit 1
fi

# ── 0.2 Install CLI tools ───────────────────────────────────────────────────

step_header "0.2" "Install CLI tools"

all_tools_ok=true
for tool in az terraform helm kubectl kubelogin databricks just uv gh jq; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    all_tools_ok=false
    break
  fi
done

if [[ "${all_tools_ok}" == "true" ]]; then
  skip "All CLI tools installed"
else
  info "Installing tools (this takes a few minutes on first run)..."
  "${ROOT}/scripts/setup-tools.sh"
  # Re-export PATH so newly installed tools are available
  export PATH="${HOME}/.local/bin:${PATH}"
  pass "CLI tools installed"
fi

if ! command -v just >/dev/null 2>&1; then
  fail "~/.local/bin not on PATH"
  echo "        Add to your shell profile:"
  echo "          export PATH=\"\$HOME/.local/bin:\$PATH\""
  echo "          echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
  echo "        Then re-run this script."
  exit 1
fi

# ── 0.3 Azure account and login ─────────────────────────────────────────────

step_header "0.3" "Azure account and login"

if az account show >/dev/null 2>&1; then
  skip "Azure login active ($(az account show --query name -o tsv 2>/dev/null))"
else
  wait_for_manual \
"1. Create a free Azure account at https://azure.microsoft.com/free
   (skip if you already have one)

2. Log in:
     az login

3. If you have multiple subscriptions, select one:
     az account list -o table
     az account set --subscription <subscription-id>" \
    az account show
fi

# ── 0.4 GitHub CLI login ────────────────────────────────────────────────────

step_header "0.4" "GitHub CLI login"

if gh auth status >/dev/null 2>&1; then
  skip "GitHub CLI authenticated ($(gh auth status 2>&1 | grep 'Logged in' | head -1 | sed 's/.*as //' | sed 's/ .*//'))"
else
  wait_for_manual \
"Log in to GitHub so the setup can detect your repo's OIDC settings:

  gh auth login

Follow the prompts to authenticate." \
    gh auth status
fi

# ── 0.5 Generate .env with project settings ─────────────────────────────────

step_header "0.5" "Generate .env with project settings"

if [[ -f "${ROOT}/.env" ]] && check_env TF_VAR_subscription_id && check_env TF_VAR_project; then
  skip ".env exists with project settings"
  echo ""
  info "Current settings:"
  printf "  %-25s %s\n" "Project name:" "$(env_val TF_VAR_project)"
  printf "  %-25s %s\n" "Region:" "$(env_val TF_VAR_location)"
  printf "  %-25s %s\n" "Subscription:" "$(env_val TF_VAR_subscription_id)"
  echo ""
  read -r -p "Keep these settings? [Y/n] " reply
  if [[ "${reply}" =~ ^[nN] ]]; then
    info "Re-running setup-env in interactive mode..."
    "${ROOT}/scripts/setup-env.sh" --interactive
    source "${ROOT}/scripts/load-env.sh"
  fi
else
  info "Running interactive setup..."
  "${ROOT}/scripts/setup-env.sh" --interactive
  source "${ROOT}/scripts/load-env.sh"
  pass ".env generated"
fi

# ── 0.6 Register Azure resource providers ────────────────────────────────────

step_header "0.6" "Register Azure resource providers"

register_providers

# ── 0.7 Terraform bootstrap ─────────────────────────────────────────────────

step_header "0.7" "Terraform bootstrap"

load_env_if_exists
local_project="$(project_name)"

bootstrap_done=false
if az group show -n "rg-${local_project}-tfstate" >/dev/null 2>&1 \
   && check_env AZURE_CLIENT_ID \
   && check_env TF_BACKEND_STORAGE_ACCOUNT; then
  bootstrap_done=true
fi

if [[ "${bootstrap_done}" == "true" ]]; then
  skip "Bootstrap resources exist (rg-${local_project}-tfstate, Entra app, state storage)"
else
  info "Initializing Terraform for bootstrap..."
  (cd "${ROOT}" && just tf-init bootstrap)

  tf_plan_confirm_apply bootstrap

  info "Capturing bootstrap outputs..."
  "${ROOT}/scripts/setup-env.sh" collect-tf bootstrap
  source "${ROOT}/scripts/load-env.sh"
  pass "Bootstrap outputs captured"
fi

# Verify bootstrap
load_env_if_exists
local_project="$(project_name)"

if az group show -n "rg-${local_project}-tfstate" >/dev/null 2>&1; then
  pass "rg-${local_project}-tfstate exists"
else
  fail "rg-${local_project}-tfstate not found"
fi

if az ad app list --display-name "app-${local_project}-github" --query '[0].displayName' -o tsv 2>/dev/null | grep -q "app-${local_project}-github"; then
  pass "Entra app app-${local_project}-github exists"
else
  fail "Entra app not found"
fi

for key in AZURE_CLIENT_ID TF_BACKEND_STORAGE_ACCOUNT TF_BACKEND_RESOURCE_GROUP; do
  if check_env "${key}"; then
    pass "${key} set in .env"
  else
    fail "${key} blank in .env"
  fi
done

# ── 0.8 Configure Terraform backends ────────────────────────────────────────

step_header "0.8" "Configure Terraform backends"

load_env_if_exists

backends_done=true
sa="$(env_val TF_BACKEND_STORAGE_ACCOUNT)"
if [[ -n "${sa}" ]]; then
  blobs="$(az storage blob list --account-name "${sa}" --container-name tfstate --auth-mode key --query '[].name' -o tsv 2>/dev/null || true)"
  for key in shared.tfstate stage.tfstate prod.tfstate; do
    if ! echo "${blobs}" | grep -q "^${key}$"; then
      backends_done=false
      break
    fi
  done
else
  backends_done=false
fi

if [[ "${backends_done}" == "true" ]]; then
  skip "All Terraform backends configured (shared, stage, prod state files exist)"
else
  for stack in shared env-stage env-prod; do
    info "Initializing ${stack} backend..."
    (cd "${ROOT}" && just tf-init "${stack}")
  done
  pass "All Terraform backends initialized"
fi

# ── 0.9 Sync GitHub variables ───────────────────────────────────────────────

step_header "0.9" "Sync GitHub variables"

if gh auth status >/dev/null 2>&1; then
  info "Syncing available .env values to GitHub repository variables..."
  "${ROOT}/scripts/setup-ci.sh"
  pass "GitHub variables synced (re-run after each phase to add new values)"
else
  warn "Skipping GitHub variable sync — gh not authenticated"
  echo "        Run 'gh auth login' and then 'just setup-ci' to sync manually."
fi

# ── 0.10 Validate code projects ─────────────────────────────────────────────

step_header "0.10" "Validate code projects"

load_env_if_exists
dagster_venv="${ROOT}/dagster/.venv/bin"
dummy_env=(
  DATABRICKS_HOST=https://dummy.azuredatabricks.net
  DATABRICKS_TOKEN=dapi_dummy
  DBX_CATALOG=stage
  DBX_WAREHOUSE_HTTP_PATH=/sql/dummy
  DBX_SP_CLIENT_ID=dummy
  DBX_SP_SECRET=dummy
  DBX_BUNDLE_ROOT="/Workspace/.bundle/$(project_name)/stage/files"
)

if [[ ! -f "${dagster_venv}/dbt" ]]; then
  fail "dagster venv not found (run: cd dagster && uv sync)"
else
  if (cd "${ROOT}" && PATH="${dagster_venv}:${PATH}" env "${dummy_env[@]}" \
      dbt parse --project-dir dbt --profiles-dir dbt >/dev/null 2>&1); then
    pass "dbt parse succeeds"
  else
    fail "dbt parse failed (check dbt models and sources)"
  fi

  if (cd "${ROOT}/dagster" && PATH="${dagster_venv}:${PATH}" env "${dummy_env[@]}" \
      dagster definitions validate -m poc -d src 2>&1 | grep -q "passed validation"); then
    pass "dagster definitions validate succeeds"
  else
    fail "dagster definitions validate failed (check Dagster assets)"
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────

phase_summary 0

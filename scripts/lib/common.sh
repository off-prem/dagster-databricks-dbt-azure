#!/usr/bin/env bash
# Shared functions for phase runners.
# Source this at the top of every scripts/phases/phase-*.sh.
#
# Provides: colored output helpers, step management, terraform workflow,
# manual-step verification loops, .env helpers.

# Guard against double-sourcing
[[ -n "${_PHASE_COMMON_LOADED:-}" ]] && return
_PHASE_COMMON_LOADED=1

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="${HOME}/.local/bin:${PATH}"

# ── Colors ───────────────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  BOLD='\033[1m'
  DIM='\033[2m'
  NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' BOLD='' DIM='' NC=''
fi

# ── Counters ─────────────────────────────────────────────────────────────────

_PASS=0
_FAIL=0
_WARN=0
_SKIP=0

pass()  { _PASS=$((_PASS + 1)); printf "  ${GREEN}✓${NC} %s\n" "$1"; }
fail()  { _FAIL=$((_FAIL + 1)); printf "  ${RED}✗${NC} %s\n" "$1"; }
warn()  { _WARN=$((_WARN + 1)); printf "  ${YELLOW}?${NC} %s\n" "$1"; }
skip()  { _SKIP=$((_SKIP + 1)); printf "  ${DIM}– %s (already done)${NC}\n" "$1"; }
info()  { printf "${BLUE}→${NC} %s\n" "$1"; }

# ── Headers ──────────────────────────────────────────────────────────────────

phase_header() {
  local num="$1" title="$2"
  echo ""
  printf "${BOLD}══════════════════════════════════════════════════════════════${NC}\n"
  printf "${BOLD}  Phase %s — %s${NC}\n" "${num}" "${title}"
  printf "${BOLD}══════════════════════════════════════════════════════════════${NC}\n"
}

step_header() {
  local num="$1" title="$2"
  echo ""
  printf "${BOLD}── Step %s: %s ──${NC}\n" "${num}" "${title}"
  echo ""
}

# ── .env helpers ─────────────────────────────────────────────────────────────

load_env_if_exists() {
  [[ -f "${ROOT}/.env" ]] && source "${ROOT}/scripts/load-env.sh" || true
}

env_val() {
  grep "^${1}=" "${ROOT}/.env" 2>/dev/null | head -1 | sed 's/^[^=]*=//; s/^"//; s/"$//'
}

check_env() {
  local val
  val="$(env_val "$1")"
  [[ -n "${val}" ]]
}

require_env() {
  local key="$1" hint="${2:-}"
  if ! check_env "${key}"; then
    fail "${key} is blank in .env"
    [[ -n "${hint}" ]] && printf "        %s\n" "${hint}"
    return 1
  fi
}

project_name() {
  env_val TF_VAR_project 2>/dev/null || echo "dagster"
}

# ── Pre-condition checks ────────────────────────────────────────────────────

require_az_login() {
  if ! az account show >/dev/null 2>&1; then
    fail "Not logged in to Azure"
    echo "        Run: az login"
    return 1
  fi
}

require_gh_login() {
  if ! command -v gh >/dev/null 2>&1; then
    fail "gh CLI not installed"
    return 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    fail "Not logged in to GitHub"
    echo "        Run: gh auth login"
    return 1
  fi
}

require_kubectl() {
  if ! kubectl get nodes >/dev/null 2>&1; then
    local project
    project="$(project_name)"
    fail "kubectl cannot reach AKS"
    echo "        Run: az aks get-credentials -g rg-${project}-shared -n aks-${project}"
    return 1
  fi
}

# ── Terraform workflow ───────────────────────────────────────────────────────

# Run terraform plan, show output, ask for confirmation, then apply.
# Usage: tf_plan_confirm_apply <stack>
tf_plan_confirm_apply() {
  local stack="$1"
  echo ""
  info "Running terraform plan for ${stack}..."
  echo ""

  # Run plan (output goes to terminal)
  if ! (cd "${ROOT}" && just tf-plan "${stack}"); then
    fail "terraform plan failed for ${stack}"
    return 1
  fi

  echo ""
  read -r -p "Apply this plan? [y/N] " confirm
  case "${confirm}" in
    [yY]|[yY][eE][sS]) ;;
    *)
      warn "Skipped terraform apply for ${stack}"
      return 1
      ;;
  esac

  echo ""
  info "Running terraform apply for ${stack}..."
  echo ""
  if ! (cd "${ROOT}" && just tf-apply "${stack}" -auto-approve); then
    fail "terraform apply failed for ${stack}"
    return 1
  fi

  pass "terraform apply ${stack} succeeded"
}

# ── Manual step helper ───────────────────────────────────────────────────────

# Print instructions, wait for user, verify, loop on failure.
# Usage: wait_for_manual "instructions" verify_command [args...]
#
# The verify command is run after each Enter press. If it fails, the user
# sees an error and can retry. They can also type 'skip' to skip.
wait_for_manual() {
  local instructions="$1"
  shift

  printf "\n${YELLOW}╭─ Manual step ─────────────────────────────────────────────╮${NC}\n"
  printf "${YELLOW}│${NC}\n"
  # Print each line of instructions indented inside the box
  while IFS= read -r line; do
    printf "${YELLOW}│${NC}  %s\n" "${line}"
  done <<< "${instructions}"
  printf "${YELLOW}│${NC}\n"
  printf "${YELLOW}╰───────────────────────────────────────────────────────────╯${NC}\n"
  echo ""

  while true; do
    read -r -p "Press Enter when done (or type 'skip' to skip)... " reply
    if [[ "${reply}" == "skip" ]]; then
      warn "Manual step skipped"
      return 0
    fi

    if "$@" 2>/dev/null; then
      pass "Verified"
      return 0
    else
      echo ""
      printf "  ${RED}Verification failed.${NC} Please check the instructions and try again.\n"
      echo ""
    fi
  done
}

# ── ACR build helper ─────────────────────────────────────────────────────────

acr_build() {
  local acr tag
  acr="$(env_val ACR_NAME)"
  tag="${1:-latest}"
  if [[ -z "${acr}" ]]; then
    fail "ACR_NAME not set in .env"
    return 1
  fi
  info "Building Docker image in ACR (cloud build, no local Docker needed)..."
  az acr build \
    --registry "${acr}" \
    --image "poc:${tag}" \
    --file dagster/Dockerfile \
    "${ROOT}"
}

# ── SecretProviderClass helper ───────────────────────────────────────────────

apply_secret_provider_class() {
  local env="$1"
  load_env_if_exists
  kubectl create namespace "$(project_name)-${env}" --dry-run=client -o yaml | kubectl apply -f -
  envsubst < "${ROOT}/deploy/k8s/${env}/secretproviderclass.yaml" | kubectl apply -f -
}

# ── Provider registration ───────────────────────────────────────────────────

REQUIRED_PROVIDERS=(
  Microsoft.Databricks
  Microsoft.ContainerService
  Microsoft.ContainerRegistry
  Microsoft.DBforPostgreSQL
  Microsoft.KeyVault
  Microsoft.ManagedIdentity
  Microsoft.Storage
)

register_providers() {
  local all_registered=true
  for ns in "${REQUIRED_PROVIDERS[@]}"; do
    local state
    state="$(az provider show -n "${ns}" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")"
    if [[ "${state}" != "Registered" ]]; then
      all_registered=false
      break
    fi
  done

  if [[ "${all_registered}" == "true" ]]; then
    skip "All resource providers already registered"
    return 0
  fi

  info "Registering Azure resource providers..."
  for ns in "${REQUIRED_PROVIDERS[@]}"; do
    local state
    state="$(az provider show -n "${ns}" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")"
    if [[ "${state}" == "Registered" ]]; then
      printf "  ${DIM}%-45s Registered${NC}\n" "${ns}"
    else
      az provider register -n "${ns}" >/dev/null
      printf "  %-45s Registering...\n" "${ns}"
    fi
  done

  info "Waiting for providers to register (this can take a few minutes)..."
  local max_wait=300 elapsed=0
  while (( elapsed < max_wait )); do
    local all_done=true
    for ns in "${REQUIRED_PROVIDERS[@]}"; do
      local state
      state="$(az provider show -n "${ns}" --query registrationState -o tsv 2>/dev/null || echo "Unknown")"
      if [[ "${state}" != "Registered" ]]; then
        all_done=false
        break
      fi
    done
    if [[ "${all_done}" == "true" ]]; then
      pass "All resource providers registered"
      return 0
    fi
    sleep 10
    elapsed=$((elapsed + 10))
    printf "  ${DIM}Still waiting... (%ds)${NC}\n" "${elapsed}"
  done

  fail "Timed out waiting for providers to register"
  return 1
}

# ── Key Vault helper ─────────────────────────────────────────────────────────

kv_name() {
  env_val KV_NAME
}

kv_secret_exists() {
  local vault="$1" secret="$2"
  az keyvault secret show --vault-name "${vault}" --name "${secret}" >/dev/null 2>&1
}

kv_set_secret() {
  local vault="$1" name="$2" value="$3"
  az keyvault secret set --vault-name "${vault}" --name "${name}" --value "${value}" >/dev/null
}

# ── Databricks CLI auth ─────────────────────────────────────────────────────

dbx_auth_check() {
  local host="$1"
  DATABRICKS_HOST="${host}" DATABRICKS_AUTH_TYPE=azure-cli \
    databricks workspace list / >/dev/null 2>&1
}

# ── Summary ──────────────────────────────────────────────────────────────────

phase_summary() {
  local phase="$1"
  echo ""
  printf "${BOLD}──────────────────────────────────────────────────────────────${NC}\n"
  printf "  ${GREEN}%d passed${NC}" "${_PASS}"
  [[ ${_SKIP} -gt 0 ]] && printf ", ${DIM}%d skipped${NC}" "${_SKIP}"
  [[ ${_WARN} -gt 0 ]] && printf ", ${YELLOW}%d warnings${NC}" "${_WARN}"
  [[ ${_FAIL} -gt 0 ]] && printf ", ${RED}%d failed${NC}" "${_FAIL}"
  echo ""

  if [[ ${_FAIL} -gt 0 ]]; then
    printf "  ${RED}Phase %s has failures. Fix them and re-run.${NC}\n" "${phase}"
    printf "${BOLD}──────────────────────────────────────────────────────────────${NC}\n"
    exit 1
  else
    printf "  ${GREEN}Phase %s complete — ready for the next phase.${NC}\n" "${phase}"
    printf "${BOLD}──────────────────────────────────────────────────────────────${NC}\n"
  fi
}

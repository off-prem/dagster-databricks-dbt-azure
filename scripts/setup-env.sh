#!/usr/bin/env bash
# Generate the per-user, git-ignored .env at the repo root. Nothing personal or account-specific is
# committed; committed files and scripts read these values instead (see .env.example for every key).
#
#   scripts/setup-env.sh                 detect values from `az login`, the git remote and your network;
#                                        write/refresh them in .env (other keys already there are kept)
#   scripts/setup-env.sh set KEY VALUE   add or update one key (e.g. a metastore ID collected later)
#   scripts/setup-env.sh show            print .env
#
# Load into your shell with:  source scripts/load-env.sh
# Re-run after your IP changes. Override detection: MY_IP_CIDR=x.x.x.x/32, GITHUB_REPO=org/repo, OWNER=name.
# In CI none of this runs: the same names come from GitHub repo variables.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/.env"

env_set() { # env_set KEY VALUE  (idempotent, in-place)
  local key="$1" val="$2" tmp
  touch "${ENV_FILE}"
  tmp="$(mktemp)"
  awk -v k="${key}" -v v="${val}" 'BEGIN { done = 0 }
    index($0, k "=") == 1 { print k "=\"" v "\""; done = 1; next }
    { print }
    END { if (!done) print k "=\"" v "\"" }' "${ENV_FILE}" > "${tmp}"
  mv "${tmp}" "${ENV_FILE}"
  chmod 600 "${ENV_FILE}"
}

die() { echo "$*" >&2; exit 1; }

detect() {
  command -v az >/dev/null || die "az not found: run scripts/setup-tools.sh first."
  az account show >/dev/null 2>&1 || die "Not logged in: run 'az login' first."

  local sub tenant ip repo owner
  sub="$(az account show --query id -o tsv)"
  tenant="$(az account show --query tenantId -o tsv)"
  ip="${MY_IP_CIDR:-$(curl -fsS https://ifconfig.me)/32}" || die "Could not detect public IP; set MY_IP_CIDR=x.x.x.x/32."
  repo="${GITHUB_REPO:-$(git -C "${ROOT}" remote get-url origin 2>/dev/null | sed -E 's#.*github\.com[:/]([^/]+/[^/]+)$#\1#; s#\.git$##')}"
  [ -n "${repo}" ] || die "No git remote 'origin'; set GITHUB_REPO=org/repo."
  owner="${OWNER:-$(git -C "${ROOT}" config user.name || true)}"
  owner="${owner:-${USER:-unknown}}"

  env_set TF_VAR_subscription_id "${sub}"
  env_set TF_VAR_tenant_id "${tenant}"
  env_set TF_VAR_my_ip_cidr "${ip}"
  env_set TF_VAR_github_repo "${repo}"
  env_set TF_VAR_owner "${owner}"
  # The azurerm/azuread providers read these.
  env_set ARM_SUBSCRIPTION_ID "${sub}"
  env_set ARM_TENANT_ID "${tenant}"
  echo "Wrote ${ENV_FILE}: subscription ${sub}, ip ${ip}, repo ${repo}, owner ${owner}"
  echo "Load it with: source scripts/load-env.sh"
}

case "${1:-}" in
  set)  [ $# -eq 3 ] || die "usage: $0 set KEY VALUE"; env_set "$2" "$3" ;;
  show) cat "${ENV_FILE}" ;;
  "")   detect ;;
  *)    die "usage: $0 [set KEY VALUE | show]" ;;
esac

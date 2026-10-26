#!/usr/bin/env bash
# Sync .env values to GitHub repository variables and create GitHub environments.
# Run this once after Phase 4 (both stage and prod are provisioned) to prepare CI/CD.
# Idempotent — safe to re-run after adding new values or changing environments.
#
#   scripts/setup-ci.sh            sync all variables + create environments
#   scripts/setup-ci.sh --dry-run  show what would be set without changing anything
#
# Requires: gh (authenticated), .env populated through Phase 4.
# In CI none of this runs — it's a one-time local setup step.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/scripts/load-env.sh"

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

die() { echo "ERROR: $*" >&2; exit 1; }

command -v gh >/dev/null || die "gh CLI not found. Install: https://cli.github.com"
gh auth status >/dev/null 2>&1 || die "Not logged in to GitHub. Run: gh auth login"

REPO="${TF_VAR_github_repo:?TF_VAR_github_repo is blank in .env — run scripts/setup-env.sh}"

SET=0
SKIP=0
WARN=0

sync_var() {
  local name="$1" value="$2"
  if [ -z "${value}" ]; then
    echo "  ? ${name} — blank in .env, skipping"
    WARN=$((WARN + 1))
    return
  fi
  if $DRY_RUN; then
    echo "  → ${name}=${value}"
  else
    gh variable set "${name}" --body "${value}" --repo "${REPO}" 2>/dev/null \
      && echo "  ✓ ${name}" \
      || { echo "  ✗ ${name} — gh variable set failed" >&2; WARN=$((WARN + 1)); return; }
  fi
  SET=$((SET + 1))
}

# ── Repository variables ─────────────────────────────────────────────────────

echo "Syncing repository variables → ${REPO}"
echo ""

echo "Identity (OIDC):"
sync_var AZURE_CLIENT_ID         "${AZURE_CLIENT_ID:-}"
sync_var AZURE_TENANT_ID         "${ARM_TENANT_ID:-${TF_VAR_tenant_id:-}}"
sync_var AZURE_SUBSCRIPTION_ID   "${ARM_SUBSCRIPTION_ID:-${TF_VAR_subscription_id:-}}"

echo ""
echo "Project settings:"
sync_var TF_VAR_PROJECT              "${TF_VAR_project:-}"
sync_var TF_VAR_LOCATION             "${TF_VAR_location:-}"
sync_var TF_VAR_GITHUB_OIDC_PREFIX   "${TF_VAR_github_oidc_prefix:-}"
sync_var TF_VAR_METASTORE_ID         "${TF_VAR_metastore_id:-}"
sync_var TF_VAR_ACCESS_CONNECTOR_ID_STAGE  "${TF_VAR_access_connector_id_stage:-}"

echo ""
echo "Shared infrastructure:"
sync_var ACR_NAME  "${ACR_NAME:-}"
sync_var PG_FQDN   "${PG_FQDN:-}"

echo ""
echo "Stage environment:"
sync_var DBX_STAGE_HOST                    "${DBX_STAGE_HOST:-}"
sync_var DBX_STAGE_WAREHOUSE_HTTP_PATH     "${DBX_STAGE_WAREHOUSE_HTTP_PATH:-}"
sync_var DBX_STAGE_SP_CLIENT_ID            "${DBX_STAGE_SP_CLIENT_ID:-}"
sync_var DAGSTER_STAGE_IDENTITY_CLIENT_ID  "${DAGSTER_STAGE_IDENTITY_CLIENT_ID:-}"

echo ""
echo "Prod environment:"
sync_var DBX_PROD_HOST                     "${DBX_PROD_HOST:-}"
sync_var DBX_PROD_WAREHOUSE_HTTP_PATH      "${DBX_PROD_WAREHOUSE_HTTP_PATH:-}"
sync_var DBX_PROD_SP_CLIENT_ID             "${DBX_PROD_SP_CLIENT_ID:-}"
sync_var DAGSTER_PROD_IDENTITY_CLIENT_ID   "${DAGSTER_PROD_IDENTITY_CLIENT_ID:-}"

# ── GitHub environments ──────────────────────────────────────────────────────

echo ""
echo "GitHub environments:"

create_environment() {
  local env_name="$1" reviewers="${2:-}"
  if $DRY_RUN; then
    echo "  → would create environment '${env_name}'"
    if [ -n "${reviewers}" ]; then echo "    with required reviewer: ${reviewers}"; fi
    return
  fi

  if [ -n "${reviewers}" ]; then
    # Get the user's GitHub ID for the reviewer setting
    local user_id
    user_id="$(gh api "users/${reviewers}" --jq '.id' 2>/dev/null || true)"
    if [ -n "${user_id}" ]; then
      gh api --method PUT "repos/${REPO}/environments/${env_name}" \
        --input - <<PAYLOAD >/dev/null 2>&1
{
  "reviewers": [{"type": "User", "id": ${user_id}}],
  "deployment_branch_policy": null
}
PAYLOAD
      echo "  ✓ ${env_name} (required reviewer: ${reviewers})"
    else
      # Create without reviewers, warn
      gh api --method PUT "repos/${REPO}/environments/${env_name}" \
        --input - <<< '{}' >/dev/null 2>&1
      echo "  ✓ ${env_name} (WARNING: could not resolve reviewer '${reviewers}' — add manually)"
      WARN=$((WARN + 1))
    fi
  else
    gh api --method PUT "repos/${REPO}/environments/${env_name}" \
      --input - <<< '{}' >/dev/null 2>&1
    echo "  ✓ ${env_name}"
  fi
}

# Get the current GitHub username for the prod reviewer
GH_USER="$(gh api user --jq '.login' 2>/dev/null || true)"

create_environment "stage"
create_environment "prod" "${GH_USER}"

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
if $DRY_RUN; then
  echo "Dry run: ${SET} variables would be set, ${WARN} warnings."
  echo "Run without --dry-run to apply."
else
  echo "Done: ${SET} variables set, ${WARN} warnings."
  if [ "${WARN}" -gt 0 ]; then
    echo "Warnings indicate blank .env values — fill them and re-run this script."
  fi
  echo ""
  echo "Verify: gh variable list --repo ${REPO}"
fi

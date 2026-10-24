#!/usr/bin/env bash
# Generate and maintain the per-user, git-ignored .env at the repo root.
# Nothing personal or account-specific is committed; committed files reference these values
# via TF_VAR_*, Helm --set, dbt env_var(), and DATABRICKS_HOST (see .env.example for every key).
#
#   scripts/setup-env.sh                       detect Phase 0 values from az/git/network;
#                                              scaffold all future keys as blank (idempotent)
#   scripts/setup-env.sh set KEY VALUE         add or update one key
#   scripts/setup-env.sh show                  print .env
#   scripts/setup-env.sh collect-tf <stack>    capture terraform outputs into .env
#                                              stack: bootstrap | shared | env-stage | env-prod
#   scripts/setup-env.sh collect-bundle <env>  capture pipeline ID after bundle deploy
#
# Load into your shell:  source scripts/load-env.sh  (just does this automatically)
# Re-run after your IP changes. Override detection: MY_IP_CIDR=x.x.x.x/32, GITHUB_REPO=org/repo, OWNER=name.
# In CI none of this runs: the same names come from GitHub repo variables.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="${HOME}/.local/bin:${PATH}"
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

# env_scaffold KEY COMMENT — add key with blank value ONLY if it is not already in .env.
# Preserves any value the user or a collect-* subcommand already wrote.
env_scaffold() {
  local key="$1" comment="${2:-}"
  touch "${ENV_FILE}"
  if grep -q "^${key}=" "${ENV_FILE}" 2>/dev/null; then return; fi
  if [ -n "${comment}" ]; then
    echo "# ${comment}" >> "${ENV_FILE}"
  fi
  echo "${key}=" >> "${ENV_FILE}"
}

die() { echo "$*" >&2; exit 1; }

scaffold_future_keys() {
  # Phase 0.5
  local section
  section="Phase 0.5 — bootstrap outputs"
  grep -q "^AZURE_CLIENT_ID=" "${ENV_FILE}" 2>/dev/null || echo "" >> "${ENV_FILE}"
  env_scaffold AZURE_CLIENT_ID "${section}"

  # Phase 1
  section="Phase 1 — shared infra outputs (collect-tf shared)"
  env_scaffold ACR_NAME "${section}"
  env_scaffold ACR_LOGIN_SERVER ""
  env_scaffold PG_FQDN ""
  env_scaffold KV_NAME ""
  env_scaffold STORAGE_ACCOUNT_NAME ""
  env_scaffold AKS_EGRESS_IP ""

  # Phase 2 — stage
  section="Phase 2 — stage environment"
  env_scaffold TF_VAR_metastore_id "${section}"
  env_scaffold DBX_STAGE_HOST ""
  env_scaffold DBX_STAGE_WORKSPACE_ID ""
  env_scaffold DBX_STAGE_SP_CLIENT_ID ""
  env_scaffold DBX_STAGE_WAREHOUSE_HTTP_PATH ""
  env_scaffold DBX_STAGE_PIPELINE_ID ""
  env_scaffold DAGSTER_STAGE_IDENTITY_CLIENT_ID ""

  # Phase 4 — prod
  section="Phase 4 — prod environment"
  env_scaffold DBX_PROD_HOST "${section}"
  env_scaffold DBX_PROD_WORKSPACE_ID ""
  env_scaffold DBX_PROD_SP_CLIENT_ID ""
  env_scaffold DBX_PROD_WAREHOUSE_HTTP_PATH ""
  env_scaffold DBX_PROD_PIPELINE_ID ""
  env_scaffold DAGSTER_PROD_IDENTITY_CLIENT_ID ""
}

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
  env_set ARM_SUBSCRIPTION_ID "${sub}"
  env_set ARM_TENANT_ID "${tenant}"

  scaffold_future_keys

  echo "Wrote ${ENV_FILE}: subscription ${sub}, ip ${ip}, repo ${repo}, owner ${owner}"
  echo "Load it with: source scripts/load-env.sh"
  echo "Future-phase keys are scaffolded as blank; fill them as you progress through the guide."
}

collect_tf() {
  local stack="${1:?usage: $0 collect-tf <bootstrap|shared|env-stage|env-prod>}"
  local tf_dir
  case "${stack}" in
    bootstrap)  tf_dir="${ROOT}/infra/bootstrap" ;;
    shared)     tf_dir="${ROOT}/infra/shared" ;;
    env-stage)  tf_dir="${ROOT}/infra/env"; export TF_DATA_DIR="${tf_dir}/.terraform-stage" ;;
    env-prod)   tf_dir="${ROOT}/infra/env"; export TF_DATA_DIR="${tf_dir}/.terraform-prod" ;;
    *) die "Unknown stack '${stack}'. Use: bootstrap, shared, env-stage, env-prod." ;;
  esac
  [ -d "${tf_dir}" ] || die "Terraform directory not found: ${tf_dir}"

  local val
  tf_out() { terraform -chdir="${tf_dir}" output -raw "$1" 2>/dev/null || true; }

  case "${stack}" in
    bootstrap)
      val="$(tf_out client_id)"
      [ -n "${val}" ] && env_set AZURE_CLIENT_ID "${val}" && echo "AZURE_CLIENT_ID=${val}"
      ;;
    shared)
      for pair in \
        "acr_name:ACR_NAME" \
        "acr_login_server:ACR_LOGIN_SERVER" \
        "pg_fqdn:PG_FQDN" \
        "kv_name:KV_NAME" \
        "storage_account_name:STORAGE_ACCOUNT_NAME" \
        "aks_egress_ip:AKS_EGRESS_IP" \
      ; do
        local tf_key="${pair%%:*}" env_key="${pair##*:}"
        val="$(tf_out "${tf_key}")"
        [ -n "${val}" ] && env_set "${env_key}" "${val}" && echo "${env_key}=${val}"
      done
      ;;
    env-stage)
      for pair in \
        "databricks_host:DBX_STAGE_HOST" \
        "databricks_workspace_id:DBX_STAGE_WORKSPACE_ID" \
        "databricks_sp_client_id:DBX_STAGE_SP_CLIENT_ID" \
        "sql_warehouse_http_path:DBX_STAGE_WAREHOUSE_HTTP_PATH" \
        "dagster_identity_client_id:DAGSTER_STAGE_IDENTITY_CLIENT_ID" \
      ; do
        local tf_key="${pair%%:*}" env_key="${pair##*:}"
        val="$(tf_out "${tf_key}")"
        [ -n "${val}" ] && env_set "${env_key}" "${val}" && echo "${env_key}=${val}"
      done
      ;;
    env-prod)
      for pair in \
        "databricks_host:DBX_PROD_HOST" \
        "databricks_workspace_id:DBX_PROD_WORKSPACE_ID" \
        "databricks_sp_client_id:DBX_PROD_SP_CLIENT_ID" \
        "sql_warehouse_http_path:DBX_PROD_WAREHOUSE_HTTP_PATH" \
        "dagster_identity_client_id:DAGSTER_PROD_IDENTITY_CLIENT_ID" \
      ; do
        local tf_key="${pair%%:*}" env_key="${pair##*:}"
        val="$(tf_out "${tf_key}")"
        [ -n "${val}" ] && env_set "${env_key}" "${val}" && echo "${env_key}=${val}"
      done
      ;;
  esac
  echo "Updated ${ENV_FILE} from terraform outputs (${stack})."
}

collect_bundle() {
  local env="${1:?usage: $0 collect-bundle <stage|prod>}"
  case "${env}" in
    stage|prod) ;;
    *) die "env must be 'stage' or 'prod'" ;;
  esac
  command -v databricks >/dev/null || die "databricks CLI not found."
  local pipeline_id
  pipeline_id="$(databricks pipelines list-pipelines --output json 2>/dev/null \
    | python3 -c "
import json, sys
for p in json.load(sys.stdin).get('statuses', []):
    if 'bronze' in p.get('name', '').lower():
        print(p['pipeline_id']); break
" 2>/dev/null || true)"
  if [ -z "${pipeline_id}" ]; then
    echo "No bronze pipeline found. Deploy the bundle first, then re-run." >&2
    return 1
  fi
  local key
  case "${env}" in
    stage) key="DBX_STAGE_PIPELINE_ID" ;;
    prod)  key="DBX_PROD_PIPELINE_ID" ;;
  esac
  env_set "${key}" "${pipeline_id}"
  echo "${key}=${pipeline_id}"
  echo "Updated ${ENV_FILE}."
}

case "${1:-}" in
  set)            [ $# -eq 3 ] || die "usage: $0 set KEY VALUE"; env_set "$2" "$3" ;;
  show)           cat "${ENV_FILE}" ;;
  collect-tf)     shift; collect_tf "$@" ;;
  collect-bundle) shift; collect_bundle "$@" ;;
  "")             detect ;;
  *)              die "usage: $0 [set KEY VALUE | show | collect-tf <stack> | collect-bundle <env>]" ;;
esac

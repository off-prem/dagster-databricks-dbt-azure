#!/usr/bin/env bash
# Destroy everything this repo provisioned so you can start fresh.
#
# Destroy order (reverse of creation):
#   1. Helm releases (Dagster pods)
#   2. Databricks bundle files
#   3. infra/env prod
#   4. infra/env stage
#   5. infra/shared (AKS, Postgres, ACR, Key Vault, ADLS, VNet)
#   6. infra/bootstrap (Entra app, TF state storage account)
#   7. Databricks-managed resource groups (rg-*-dbx-managed)
#   8. Manual: Unity Catalog metastore (if created)
#
# What this does NOT delete:
#   - The Unity Catalog metastore (account-level, manual — see step at the end)
#   - Your Azure subscription or Entra tenant
#   - GitHub repo variables or environments
#   - The local .env file or Terraform local state (infra/bootstrap/terraform.tfstate)
#
# After destroy, to start over: just setup-env && just tf-init bootstrap && just tf-apply bootstrap
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/scripts/load-env.sh"

PROJECT="${TF_VAR_project:-dagster}"
AUTO_APPROVE=false
FORCE_BOOTSTRAP=false
for arg in "$@"; do
  case "${arg}" in
    -y|--yes)     AUTO_APPROVE=true ;;
    --force)      FORCE_BOOTSTRAP=true ;;
  esac
done

echo "============================================"
echo "  DESTROY ALL — ${PROJECT}"
echo "============================================"
echo ""
echo "This will destroy every Azure resource this repo created."
echo ""
echo "Stacks to destroy (in order):"
echo "  1. Helm releases (dagster-stage, dagster-prod)"
echo "  2. Databricks bundle workspace files"
echo "  3. infra/env prod   → Databricks workspace, access connector, managed identity"
echo "  4. infra/env stage  → same"
echo "  5. infra/shared     → AKS, Postgres, ACR, Key Vault, ADLS, VNet"
echo "  6. infra/bootstrap  → Entra app, TF state storage account"
echo "  7. Databricks-managed resource groups (rg-*-dbx-managed)"
echo ""
if [[ "${AUTO_APPROVE}" == "true" ]]; then
  echo "Auto-approve enabled — no prompts."
else
  read -r -p "Continue? [y/N] " confirm
  case "${confirm}" in
    [yY]) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

TF_APPROVE=()
if [[ "${AUTO_APPROVE}" == "true" ]]; then
  TF_APPROVE=("-auto-approve")
fi

ERRORS=()

# ── 1. Helm releases ────────────────────────────────────────────────────────

echo ""
echo "── Step 1/6: Uninstalling Helm releases ──"

# AKS might already be deleted or stopped — try to get credentials first
if az aks show --resource-group "rg-${PROJECT}-shared" --name "aks-${PROJECT}" --query "name" -o tsv &>/dev/null; then
  # AKS might be stopped — start it so we can reach the API server
  aks_state=$(az aks show --resource-group "rg-${PROJECT}-shared" --name "aks-${PROJECT}" \
    --query "powerState.code" -o tsv 2>/dev/null || echo "unknown")
  if [[ "${aks_state}" == "Stopped" ]]; then
    echo "  AKS is stopped. Starting it to uninstall Helm releases..."
    az aks start --resource-group "rg-${PROJECT}-shared" --name "aks-${PROJECT}"
  fi
  az aks get-credentials --resource-group "rg-${PROJECT}-shared" --name "aks-${PROJECT}" --overwrite-existing 2>/dev/null

  for env in prod stage; do
    release="${PROJECT}-${env}"
    ns="${PROJECT}-${env}"
    if helm status "${release}" -n "${ns}" &>/dev/null; then
      echo "  Uninstalling Helm release ${release}..."
      helm uninstall "${release}" -n "${ns}" --wait || ERRORS+=("helm uninstall ${release}")
    else
      echo "  Helm release ${release} not found — skipping"
    fi
  done
else
  echo "  AKS cluster not found — skipping Helm uninstall"
fi

# ── 2. Databricks bundle ───────────────────────────────────────────────────

echo ""
echo "── Step 2/6: Destroying Databricks bundle files ──"

for env in prod stage; do
  host_var="DBX_$(echo "${env}" | tr '[:lower:]' '[:upper:]')_HOST"
  sp_var="DBX_$(echo "${env}" | tr '[:lower:]' '[:upper:]')_SP_CLIENT_ID"
  host="${!host_var:-}"
  sp_id="${!sp_var:-dummy}"
  if [[ -n "${host}" ]]; then
    echo "  Destroying bundle for ${env} (host: ${host})..."
    (cd "${ROOT}/databricks" && \
      DATABRICKS_HOST="${host}" \
      BUNDLE_VAR_ci_sp_client_id="${AZURE_CLIENT_ID:-dummy}" \
      BUNDLE_VAR_run_as_sp_client_id="${sp_id}" \
      databricks bundle destroy -t "${env}" --auto-approve) \
      || ERRORS+=("bundle destroy ${env}")
  else
    echo "  ${host_var} is blank — skipping ${env} bundle destroy"
  fi
done

# ── 3. infra/env prod ──────────────────────────────────────────────────────

echo ""
echo "── Step 3/6: Terraform destroy infra/env (prod) ──"

if [[ -d "${ROOT}/infra/env/.terraform-prod" ]]; then
  export TF_VAR_databricks_host="${DBX_PROD_HOST:-}"
  export TF_VAR_aks_egress_ip="${AKS_EGRESS_IP:-0.0.0.0}"
  TF_DATA_DIR="${ROOT}/infra/env/.terraform-prod" \
    terraform -chdir="${ROOT}/infra/env" destroy -var-file=prod.tfvars "${TF_APPROVE[@]}" \
    || ERRORS+=("terraform destroy env-prod")
else
  echo "  infra/env not initialized for prod — skipping"
fi

# ── 4. infra/env stage ─────────────────────────────────────────────────────

echo ""
echo "── Step 4/6: Terraform destroy infra/env (stage) ──"

if [[ -d "${ROOT}/infra/env/.terraform-stage" ]]; then
  export TF_VAR_databricks_host="${DBX_STAGE_HOST:-}"
  export TF_VAR_aks_egress_ip="${AKS_EGRESS_IP:-0.0.0.0}"
  TF_DATA_DIR="${ROOT}/infra/env/.terraform-stage" \
    terraform -chdir="${ROOT}/infra/env" destroy -var-file=stage.tfvars "${TF_APPROVE[@]}" \
    || ERRORS+=("terraform destroy env-stage")
else
  echo "  infra/env not initialized for stage — skipping"
fi

# ── 5. infra/shared ────────────────────────────────────────────────────────

echo ""
echo "── Step 5/6: Terraform destroy infra/shared ──"

if [[ -d "${ROOT}/infra/shared/.terraform" ]]; then
  terraform -chdir="${ROOT}/infra/shared" destroy "${TF_APPROVE[@]}" \
    || ERRORS+=("terraform destroy shared")
else
  echo "  infra/shared not initialized — skipping"
fi

# ── 6. infra/bootstrap ─────────────────────────────────────────────────────
#
# Bootstrap owns the TF state storage account. If earlier stacks failed to
# destroy, their state still lives there — deleting it orphans the resources
# and makes terraform destroy impossible to retry. Abort unless everything
# above succeeded, or the operator passes --force.

echo ""
echo "── Step 6/6: Terraform destroy infra/bootstrap ──"
echo "  This deletes the Entra app and the TF state storage account."
echo "  After this, remote state for shared/env stacks is gone."
echo ""

if [[ ${#ERRORS[@]} -gt 0 && "${FORCE_BOOTSTRAP}" != "true" ]]; then
  echo "  ⚠ Skipping bootstrap destroy — earlier steps failed:"
  for e in "${ERRORS[@]}"; do
    echo "      ✗ ${e}"
  done
  echo ""
  echo "  Fix the errors above and re-run, or pass --force to destroy bootstrap anyway."
  echo "  Destroying bootstrap now would delete the remote state needed to retry."
elif [[ -f "${ROOT}/infra/bootstrap/terraform.tfstate" ]]; then
  terraform -chdir="${ROOT}/infra/bootstrap" destroy "${TF_APPROVE[@]}" \
    || ERRORS+=("terraform destroy bootstrap")
else
  echo "  No local state file — skipping"
fi

# ── 7. Databricks-managed resource groups ──────────────────────────────────
#
# Azure creates rg-*-dbx-managed groups for each Databricks workspace.
# They don't auto-delete when the parent group is removed outside of
# Terraform, so clean them up explicitly.

echo ""
echo "── Step 7: Cleaning up Databricks-managed resource groups ──"

for env in prod stage; do
  dbx_rg="rg-${PROJECT}-${env}-dbx-managed"
  if az group show -n "${dbx_rg}" &>/dev/null; then
    echo "  Deleting ${dbx_rg}..."
    az group delete -n "${dbx_rg}" --yes || ERRORS+=("delete ${dbx_rg}")
  else
    echo "  ${dbx_rg} not found — skipping"
  fi
done

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "============================================"
if [[ ${#ERRORS[@]} -eq 0 ]]; then
  echo "  Destroy complete."
else
  echo "  Destroy finished with errors:"
  for e in "${ERRORS[@]}"; do
    echo "    ✗ ${e}"
  done
fi
echo "============================================"
echo ""
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "If Terraform state is intact, fix the errors and re-run this script."
  echo ""
  echo "If state is lost (bootstrap already destroyed), delete resource groups manually:"
  echo "  az group delete -n rg-${PROJECT}-prod --yes --no-wait"
  echo "  az group delete -n rg-${PROJECT}-stage --yes --no-wait"
  echo "  az group delete -n rg-${PROJECT}-shared --yes --no-wait"
  echo "  # Databricks-managed groups (rg-*-dbx-managed) are deleted with their parent"
  echo ""
fi
echo "Manual follow-up:"
echo "  • Unity Catalog metastore: delete at https://accounts.azuredatabricks.net"
echo "    (Catalog → metastore → Delete)"
echo "  • GitHub repo variables/environments: remove from Settings → Actions if desired"
echo "  • Local files: .env and infra/bootstrap/terraform.tfstate remain (not deleted)"
echo ""
echo "To start fresh: scripts/setup-env.sh && just tf-init bootstrap && just tf-apply bootstrap"

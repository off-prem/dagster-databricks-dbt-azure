#!/usr/bin/env bash
# Source this before terraform: `source scripts/tf-env.sh`
# Exports the values that belong to the person running it, so none are committed:
#   subscription / tenant  from the active `az login` context
#   my_ip_cidr             your current public IP as /32 (override: MY_IP_CIDR=x.x.x.x/32)
# Re-source it whenever your network changes. Account-specific outputs (metastore_id, ...) go in the
# gitignored infra/env/local.auto.tfvars.

if ! az account show >/dev/null 2>&1; then
  echo "Not logged in: run 'az login' first." >&2
  return 1 2>/dev/null || exit 1
fi

TF_VAR_subscription_id="$(az account show --query id -o tsv)"
TF_VAR_tenant_id="$(az account show --query tenantId -o tsv)"
if [ -z "${MY_IP_CIDR:-}" ]; then
  MY_IP_CIDR="$(curl -fsS https://ifconfig.me)/32" || { echo "Could not detect public IP; set MY_IP_CIDR." >&2; return 1 2>/dev/null || exit 1; }
fi
TF_VAR_my_ip_cidr="${MY_IP_CIDR}"

export TF_VAR_subscription_id TF_VAR_tenant_id TF_VAR_my_ip_cidr
export ARM_SUBSCRIPTION_ID="${TF_VAR_subscription_id}" ARM_TENANT_ID="${TF_VAR_tenant_id}"
echo "terraform env set: subscription ${TF_VAR_subscription_id}, ip ${TF_VAR_my_ip_cidr}"

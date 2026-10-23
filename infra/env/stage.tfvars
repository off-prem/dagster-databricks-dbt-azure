# Shared, non-personal values only. Nothing here is specific to one person or Azure account.
# subscription_id, tenant_id and my_ip_cidr come from `source scripts/tf-env.sh` (TF_VAR_*).
# Account-specific outputs (e.g. metastore_id) go in gitignored infra/env/local.auto.tfvars.
env             = "stage"
location        = "eastus2"
shared_rg       = "rg-dagsterpoc-shared"
aks_name        = "aks-dagsterpoc"

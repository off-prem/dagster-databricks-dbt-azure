SecretProviderClass for the dagster-stage namespace.

Syncs Key Vault secrets → K8s Secrets via the CSI Secrets Store driver:
- `dagster-dbx-stage`: DBX_SP_CLIENT_ID, DBX_SP_SECRET, SOURCE_POSTS_API_KEY
- `dagster-postgres`: postgresql-password (pg-admin-password from KV)

Before applying, replace the three placeholders with values from `just show-env`:
- `<KV_NAME>` → KV_NAME
- `<TF_VAR_tenant_id>` → TF_VAR_tenant_id
- `<DAGSTER_STAGE_IDENTITY_CLIENT_ID>` → DAGSTER_STAGE_IDENTITY_CLIENT_ID

Apply: `kubectl apply -f deploy/k8s/stage/secretproviderclass.yaml`

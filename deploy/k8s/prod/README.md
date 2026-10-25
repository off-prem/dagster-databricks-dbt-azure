SecretProviderClass for the dagster-prod namespace — same structure as stage.
See deploy/k8s/stage/README.md for details.

Replace placeholders with prod-specific values from `just show-env`:
- `<KV_NAME>` → KV_NAME
- `<TF_VAR_tenant_id>` → TF_VAR_tenant_id
- `<DAGSTER_PROD_IDENTITY_CLIENT_ID>` → DAGSTER_PROD_IDENTITY_CLIENT_ID

Apply: `kubectl apply -f deploy/k8s/prod/secretproviderclass.yaml`

SecretProviderClass for the dagster-prod namespace. Same structure as stage.

Syncs Key Vault secrets → K8s Secrets via the CSI Secrets Store driver:
- `dagster-dbx-prod`: DBX_SP_CLIENT_ID, DBX_SP_SECRET, SOURCE_POSTS_API_KEY
- `dagster-postgres`: postgresql-password (pg-admin-password from KV)

The manifest contains `${VAR}` placeholders (`KV_NAME`, `TF_VAR_tenant_id`,
`DAGSTER_PROD_IDENTITY_CLIENT_ID`) resolved from `.env`. Create the namespace first, then:

    source scripts/load-env.sh
    kubectl create namespace dagster-prod --dry-run=client -o yaml | kubectl apply -f -
    envsubst < deploy/k8s/prod/secretproviderclass.yaml | kubectl apply -f -

See docs/resources/secret-provider-class.md.

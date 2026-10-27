SecretProviderClass for the dagster-stage namespace.

Syncs Key Vault secrets → K8s Secrets via the CSI Secrets Store driver:
- `dagster-dbx-stage`: DBX_SP_CLIENT_ID, DBX_SP_SECRET, SOURCE_POSTS_API_KEY
- `dagster-postgres`: postgresql-password (pg-admin-password from KV)

The manifest contains `${VAR}` placeholders (`KV_NAME`, `TF_VAR_tenant_id`,
`DAGSTER_STAGE_IDENTITY_CLIENT_ID`) resolved from `.env`. Create the namespace first, then:

    source scripts/load-env.sh
    kubectl create namespace dagster-stage --dry-run=client -o yaml | kubectl apply -f -
    envsubst < deploy/k8s/stage/secretproviderclass.yaml | kubectl apply -f -

See docs/resources/secret-provider-class.md.

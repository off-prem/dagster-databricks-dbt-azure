# Databricks CI Principal (`app-dagster-github` in each workspace)

> **Type:** Resource · **Scope:** per-workspace (stage and prod) · **Name:** `app-<project>-github` · **Created:** manually (guide step 5.2)

The GitHub OIDC [Entra app](entra-app.md) registered *inside* each Databricks workspace, so CI can deploy bundles.

## Why we use it

Azure RBAC does not carry into Databricks. `databricks bundle deploy` calls the workspace's SCIM `/Me` endpoint, which only works for a
workspace user with the `workspace-access` entitlement. Without this step, CI deploys fail even though `az login` succeeded.

## How it's used here

For each workspace host (`DBX_STAGE_HOST`, `DBX_PROD_HOST`) the guide runs:

1. `databricks service-principals create --application-id $AZURE_CLIENT_ID --display-name app-dagster-github`
2. Look up its ID with `service-principals list --filter "applicationId eq '…'"`.
3. `service-principals patch` to add the `workspace-access` entitlement.

The bundle then grants it `CAN_MANAGE` on the bundle folder through its `permissions:` block (`ci_sp_client_id` variable, set to `AZURE_CLIENT_ID`).
It is a different principal from the per-env Dagster [service principal](databricks-service-principal.md).

## Key commands & files

```bash
source scripts/load-env.sh
DATABRICKS_HOST="$DBX_STAGE_HOST" databricks service-principals list --filter "applicationId eq '$AZURE_CLIENT_ID'"
```

## Gotchas

- **Manual and not in Terraform.** A rebuilt workspace must repeat it.
- It must be done in **both** workspaces. A passing stage deploy followed by a prod failure usually means prod was skipped.
- After changing the bundle's `permissions:` block, redeploy once from your own account so the existing folder picks them up.
- It needs your own workspace-admin rights to run. The CLI authenticates with your `az` session.

## Cost

Free.

## Managed by

Manual Databricks CLI commands from the guide.

## Related docs

- [Entra app](entra-app.md), [OIDC](../concepts/oidc.md), [Databricks CLI](../tools/databricks-cli.md)
- [Databricks Asset Bundles](../tools/databricks-asset-bundles.md), [Databricks service principal](databricks-service-principal.md)
- [CI/CD](../concepts/cicd.md)

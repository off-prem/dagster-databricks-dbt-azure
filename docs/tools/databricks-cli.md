# Databricks CLI

> **Type:** Tool · **Scope:** local + CI · **Pinned:** 1.22.1 (`.tool-versions`)

The official Databricks command-line tool. This project uses it only for
[Asset Bundle](databricks-asset-bundles.md) commands (`validate`, `deploy`, `destroy`).

## Why we use it

It is the native way to push the Databricks-side code (`databricks/src/extract/`) to a
workspace. Dagster submits that code as a serverless job at run time, so it has to be
deployed to the workspace first.

## How it's used here

- `scripts/bundle-deploy.sh <env>` sets `DATABRICKS_HOST` from `.env` and then runs
  `databricks bundle deploy -t <env>`. The workspace URL is never in the bundle YAML.
- **Local auth:** the Databricks SDK picks up your `az login` session (`azure-cli` auth type).
- **CI auth:** the same OIDC-authenticated `az` session. The CI service principal
  (`AZURE_CLIENT_ID`) needs `workspace-access` entitlement and `CAN_MANAGE` on the bundle
  folder. The bundle grants the latter through its `permissions:` block.
- `scripts/setup-env.sh collect-bundle <env>` captures bundle outputs into `.env`.

## Key commands & files

```bash
just bundle-validate stage      # databricks bundle validate -t stage
just bundle-deploy stage        # scripts/bundle-deploy.sh stage
```

Files: `databricks/databricks.yml` (the bundle), `scripts/bundle-deploy.sh`.

## Gotchas

- Deploying as yourself first, then as CI, can fail with a permissions error on the bundle
  folder. Redeploy once from your own account after changing the `permissions:` block.
- `pr-checks.yml` runs `bundle validate` with `continue-on-error: true`, because PR runners
  can't always reach the workspace (IP access list).
- The CLI is a standalone binary, not a pip package. CI installs it with Databricks'
  `setup-cli` install script.

## Cost

Free. Deployments only copy files.

## Managed by

Installed by `scripts/setup-tools.sh` (pinned) locally and by the `setup-cli` install script in CI.

## Related docs

- [Databricks Asset Bundles](databricks-asset-bundles.md): what the CLI deploys
- [Databricks workspace](../resources/databricks-workspace.md): the deploy target
- [CI/CD](../concepts/cicd.md): where bundle deploy runs
- [Azure CLI](azure-cli.md): supplies the auth session

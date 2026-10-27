# env

Applied once per environment (`-var-file=stage.tfvars` / `prod.tfvars`): Databricks workspace, access connector, managed identity, and (after the metastore exists) the Databricks objects. Remote state `<env>.tfstate`.

See docs/conventions.md (Terraform section). Do not add resources not listed in docs/costs.md.

# Terraform State

When [Terraform](../tools/terraform.md) creates resources, it needs to remember what it
created. Otherwise, the next time you run `terraform plan`, it has no idea what already
exists and would try to create everything from scratch (or worse, create duplicates).

## What the state file is

After `terraform apply` creates resources, Terraform writes a JSON file called
`terraform.tfstate` that records every resource's ID, properties, and the relationships
between them. This is the **state file**.

For example, after creating a Postgres server, the state file contains the server's Azure
resource ID, its FQDN, the admin username, and other attributes. When you run
`terraform plan` next, Terraform reads this file, queries Azure for the current state of
those resources, and shows you what (if anything) has changed.

**The state file can contain sensitive values** (passwords, connection strings, secret IDs),
so it should never be committed to git.

## Local state vs. remote state

### Local state (file on disk)

By default, Terraform stores the state file in the working directory
(`terraform.tfstate`). This is simple but fragile:
- If your disk dies, the state is lost
- If someone else needs to run Terraform, they don't have the state
- CI systems can't access it

### Remote state (cloud storage)

**Remote state** stores the file in a cloud storage service. In this project, we use an
Azure storage account (created by the `bootstrap` stack) with a blob container called
`tfstate`. This means:
- State survives if your laptop dies
- A CI system or teammate can use the same state
- Azure handles locking so two people can't modify state at the same time

## How it's set up in this project

| Stack | State location | Why |
|-------|---------------|-----|
| `bootstrap` | **Local** (`infra/bootstrap/terraform.tfstate`) | This stack *creates* the storage account for remote state. It can't store its own state there because the storage account doesn't exist yet (chicken-and-egg). This file is git-ignored. |
| `shared` | **Remote** (`tfstate/shared.tfstate` in the storage account) | Durable, shareable |
| `env` (stage) | **Remote** (`tfstate/stage.tfstate`) | Separate key from prod |
| `env` (prod) | **Remote** (`tfstate/prod.tfstate`) | Separate key from stage |

### Why separate state keys for stage and prod?

The `infra/env/` directory contains one set of `.tf` files that's applied twice — once
for stage (with `stage.tfvars`) and once for prod (with `prod.tfvars`). Each needs its
own state file so Terraform doesn't confuse stage resources with prod resources. They
also get separate `.terraform` directories (`.terraform-stage` and `.terraform-prod`)
so the initialized providers and cached modules don't collide.

## What to do if you lose the state file

If the local `bootstrap` state file is lost, you can **import** existing resources:
Terraform can adopt resources it didn't create by mapping them to your `.tf` definitions.
This is a manual process but fully recoverable.

Remote state in the storage account is durable (replicated by Azure) and versioned
(blob versioning), so loss is unlikely.

## Outputs

After creating resources, Terraform can **output** specific values. For example, the
storage account name includes a random suffix (because Azure requires globally unique
names), so Terraform outputs it so other tools can use it.

We capture outputs into `.env` with:

```bash
just collect-tf <stack>
```

This runs `terraform output` and writes the values to your `.env` file, where
[Helm](../tools/helm.md), [dbt](../tools/dbt.md), and the [Databricks CLI](../tools/databricks-cli.md)
can read them.

## Related docs

- [Terraform](../tools/terraform.md) — the tool that uses state
- [just](../tools/just.md) — `just tf-init/plan/apply` commands

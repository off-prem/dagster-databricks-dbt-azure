# Network Security Perimeter (NSP)

> **Type:** Resource · **Scope:** shared · **Name:** `nsp-<project>` · **Stack:** `infra/shared`

An Azure feature that puts a logical network boundary around PaaS resources, with
rules for which traffic may cross it.

## Why we use it

Databricks serverless compute runs on Databricks-managed infrastructure with changing IPs.
For the locked-down [ADLS](adls.md) account, the storage firewall's `AzureServices` bypass and
access-connector rules weren't enough, so a perimeter rule admits the `AzureDatabricksServerless` service tag.

## How it's used here

| Item | Value |
|------|-------|
| Perimeter | `nsp-<project>` |
| Profile | `profile-<project>` |
| Access rule | `allow-databricks-serverless`, inbound, service tag `AzureDatabricksServerless` |
| Association | The storage account, mode **Learning** (`assoc-<project>-storage`) |

Learning (transition) mode logs would-be denials but keeps the existing storage firewall in
force, so both layers work together.

## Key commands & files

Terraform: `azurerm_network_security_perimeter*` resources in `infra/shared/main.tf`.

## Gotchas

- In Learning mode the NSP is not the enforcer. Don't remove the firewall rules on the
  assumption that it is.
- Moving to **Enforced** mode needs rules for every legitimate caller (your IP, access connectors).
  Test it on a non-critical account first.
- If serverless jobs start failing with 403 on storage, check the NSP logs and the access-connector rules.

## Cost

Free.

## Managed by

[Terraform](../tools/terraform.md), `infra/shared/`.

## Related docs

- [ADLS](adls.md), [Databricks access connector](databricks-access-connector.md)
- [Network access](../concepts/network-access.md)

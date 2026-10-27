# jq

> **Type:** Tool · **Scope:** local + CI · **Pinned:** 1.7.1 (`.tool-versions`)

A command-line JSON processor.

## Why we use it

The smoke test talks to the Dagster webserver's GraphQL API and has to parse JSON
responses in shell. `jq` does that without a Python dependency.

## How it's used here

- `scripts/smoke-test.sh` exits early if `jq` is missing. It uses it to read the launched
  run ID and poll the run status until `SUCCESS` or `FAILURE` (20-minute timeout).
- Deploy workflows install it on the ARC runner with `apt-get`.

## Key commands & files

```bash
jq -r '.data.launchRun.run.runId' response.json
az account show | jq -r .tenantId
```

File: `scripts/smoke-test.sh`.

## Gotchas

- The bare ARC runner image has no `jq`, so the workflow's "Install system dependencies"
  step must stay.
- Prefer `jq -r` for raw strings in scripts; without it you get quoted JSON.

## Cost

Free.

## Managed by

Installed by `scripts/setup-tools.sh` locally and by apt in CI.

## Related docs

- [CI/CD](../concepts/cicd.md): the smoke test step
- [Dagster](dagster.md): the GraphQL API being called

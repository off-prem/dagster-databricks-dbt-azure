# GitHub App (for ARC)

> **Type:** Resource · **Scope:** one per GitHub account/org · **Name:** `arc-runner-<project>` · **Created:** manually (guide step 5.3)

A GitHub App that lets the [ARC](../tools/arc.md) controller register self-hosted runners and pick up
workflow jobs. It is the identity ARC uses *toward GitHub*. It has no access to Azure.

## Why we use it

ARC has to authenticate to GitHub. A GitHub App is scoped, auditable, and its credentials don't expire the
way a personal access token can. A PAT would also be tied to one person's account.

## How it's used here

**Creation (manual, click-by-click in guide step 5.3):**

| Setting | Value |
|---------|-------|
| Name | `arc-runner-<project>` |
| Homepage URL | your repo URL |
| Webhook | **Inactive** (ARC polls; no webhook is needed) |
| Repository permissions | Administration: Read & write; Metadata: Read-only |
| Organization permissions | Self-hosted runners: Read & write |
| Installable on | Only this account |

Then **install** it on the repository, generate a **private key** (a `.pem` download), and note the
**App ID** and **Installation ID**.

**Where each value lives:**

| Value | Location | Why there |
|-------|----------|-----------|
| Private key | [Key Vault](key-vault.md) secret `arc-github-app-key` | It is a secret |
| App ID | `.env` as `ARC_GITHUB_APP_ID` | An identifier, not a secret |
| Installation ID | `.env` as `ARC_GITHUB_APP_INSTALLATION_ID` | An identifier, not a secret |

`scripts/setup-arc.sh` reads the key from Key Vault, then installs the ARC controller and the `arc-runner-set`
runner scale set with the App credentials. The runner scale set points at `https://github.com/<TF_VAR_github_repo>`.

## Key commands & files

```bash
az keyvault secret set --vault-name "$KV_NAME" --name arc-github-app-key --file <path-to-pem>
scripts/setup-env.sh set ARC_GITHUB_APP_ID <app-id>
scripts/setup-env.sh set ARC_GITHUB_APP_INSTALLATION_ID <installation-id>
scripts/setup-arc.sh        # re-run to pick up a rotated key
```

## Gotchas

- **Delete the downloaded `.pem`** after storing it in Key Vault. `*.pem` is git-ignored, but don't leave it lying around.
- **Rotating the key:** generate a new key in the App settings, overwrite the Key Vault secret, then re-run
  `scripts/setup-arc.sh` (it recreates the Kubernetes secret and upgrades the runner set).
- The script passes the App credentials to Helm as inline values, so they are visible to anyone who can read
  the `arc-runners` release's values. Limit cluster access accordingly.
- The runner scale set is scoped to a **repository** URL, so the repository **Administration** permission is the one that matters.
  The organization permission is only needed if you later register at org level.
- If runners never appear, check that the App is installed on this repo and that the App ID and Installation ID in `.env` match.
- The App is created once per account, so a teardown/standup of AKS does **not** require recreating it; just re-run `setup-arc.sh`.

## Cost

Free.

## Managed by

Created by hand in GitHub (not Terraform). Credentials are consumed by `scripts/setup-arc.sh`.

## Related docs

- [ARC](../tools/arc.md), [GitHub Actions](../tools/github-actions.md), [Decision 16](../decisions.md)
- [Key Vault](key-vault.md), [Kubernetes secrets](kubernetes-secrets.md), [Secrets flow](../concepts/secrets-flow.md)
- [GitHub repository](github-repository.md)

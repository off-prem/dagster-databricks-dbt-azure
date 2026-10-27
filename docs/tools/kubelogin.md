# kubelogin

> **Type:** Tool · **Scope:** local + CI · **Pinned:** 0.2.22 (`.tool-versions`)

A kubectl credential plugin for Azure. It turns your `az` session into the Entra token the
AKS API server expects.

## Why we use it

AKS here uses Azure RBAC for Kubernetes (no local accounts). A plain kubeconfig has nothing
to authenticate with, so `kubelogin` supplies the token.

## How it's used here

After `az aks get-credentials`, run `kubelogin convert-kubeconfig -l azurecli`. kubectl then
asks `kubelogin` for a token, which reuses the existing `az login` (locally) or the OIDC
`azure/login` session (CI). The deploy workflows download the pinned release from GitHub.

## Key commands & files

```bash
kubelogin convert-kubeconfig -l azurecli
kubelogin --version
```

## Gotchas

- Skipping the convert step gives an interactive device-code prompt, which hangs in CI.
- Re-run the convert step after every `az aks get-credentials --overwrite-existing`.
- The signed-in identity needs an *Azure Kubernetes Service RBAC* role. Terraform grants
  Cluster Admin to the applier and to the CI principal.

## Cost

Free.

## Managed by

Installed by `scripts/setup-tools.sh`; downloaded from GitHub releases in workflows.

## Related docs

- [kubectl](kubectl.md), [Azure CLI](azure-cli.md)
- [AKS](../resources/aks.md), [Azure RBAC](../concepts/azure-rbac.md)

#!/usr/bin/env bash
# Source (don't execute) to load the git-ignored .env into your shell:  source scripts/load-env.sh
# Terraform picks up the TF_VAR_* values; the azure providers read ARM_*.
_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ ! -f "${_root}/.env" ]; then
  echo ".env not found: run scripts/setup-env.sh first." >&2
  return 1 2>/dev/null || exit 1
fi
set -a
# shellcheck disable=SC1091
. "${_root}/.env"
set +a

export TF_VAR_github_sp_client_id="${AZURE_CLIENT_ID:-}"

unset _root

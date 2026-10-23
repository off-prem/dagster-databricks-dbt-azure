#!/usr/bin/env bash
# Install the CLIs listed in .tool-versions into ~/.local/bin (no sudo). Idempotent: skips a tool
# already at the pinned version. Linux x86_64/arm64. Checksums verified for downloaded binaries.
# azure-cli and python come via uv; uv itself is installed from astral if missing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${HOME}/.local/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
mkdir -p "${BIN}"
export PATH="${BIN}:${PATH}"

case "$(uname -m)" in
  x86_64)  ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "Unsupported arch $(uname -m)" >&2; exit 1 ;;
esac

ver() { awk -v t="$1" '$1 == t { print $2 }' "${ROOT}/.tool-versions"; }

verify() { # verify <file> <expected sha256>
  echo "$2  $1" | sha256sum -c --quiet - || { echo "Checksum mismatch for $1" >&2; exit 1; }
}

# have <cmd> <version> <current-version-command...>: true if already at the pinned version
have() {
  local cmd="$1" want="$2"; shift 2
  command -v "${cmd}" >/dev/null 2>&1 && "$@" 2>&1 | grep -qF "${want}"
}

install_terraform() {
  local v; v="$(ver terraform)"
  if have terraform "${v}" terraform version; then echo "terraform ${v} ok"; return; fi
  echo "Installing terraform ${v}"
  local base="https://releases.hashicorp.com/terraform/${v}" zip="terraform_${v}_linux_${ARCH}.zip"
  curl -fsSL -o "${TMP}/${zip}" "${base}/${zip}"
  verify "${TMP}/${zip}" "$(curl -fsSL "${base}/terraform_${v}_SHA256SUMS" | awk -v f="${zip}" '$2 == f { print $1 }')"
  python3 -m zipfile -e "${TMP}/${zip}" "${TMP}/tf"
  install -m 0755 "${TMP}/tf/terraform" "${BIN}/terraform"
}

install_helm() {
  local v; v="$(ver helm)"
  if have helm "v${v}" helm version --short; then echo "helm ${v} ok"; return; fi
  echo "Installing helm ${v}"
  local tgz="helm-v${v}-linux-${ARCH}.tar.gz" base="https://get.helm.sh"
  curl -fsSL -o "${TMP}/${tgz}" "${base}/${tgz}"
  verify "${TMP}/${tgz}" "$(curl -fsSL "${base}/${tgz}.sha256sum" | awk '{ print $1 }')"
  tar -xzf "${TMP}/${tgz}" -C "${TMP}" "linux-${ARCH}/helm"
  install -m 0755 "${TMP}/linux-${ARCH}/helm" "${BIN}/helm"
}

install_kubectl() {
  local v; v="$(ver kubectl)"
  if have kubectl "v${v}" kubectl version --client; then echo "kubectl ${v} ok"; return; fi
  echo "Installing kubectl ${v}"
  local base="https://dl.k8s.io/release/v${v}/bin/linux/${ARCH}"
  curl -fsSL -o "${TMP}/kubectl" "${base}/kubectl"
  verify "${TMP}/kubectl" "$(curl -fsSL "${base}/kubectl.sha256")"
  install -m 0755 "${TMP}/kubectl" "${BIN}/kubectl"
}

install_databricks() {
  local v; v="$(ver databricks-cli)"
  if have databricks "${v}" databricks --version; then echo "databricks ${v} ok"; return; fi
  echo "Installing databricks-cli ${v}"
  local base="https://github.com/databricks/cli/releases/download/v${v}" zip="databricks_cli_${v}_linux_${ARCH}.zip"
  curl -fsSL -o "${TMP}/${zip}" "${base}/${zip}"
  verify "${TMP}/${zip}" "$(curl -fsSL "${base}/databricks_cli_${v}_SHA256SUMS" | awk -v f="${zip}" '$2 == f { print $1 }')"
  python3 -m zipfile -e "${TMP}/${zip}" "${TMP}/dbx"
  install -m 0755 "${TMP}/dbx/databricks" "${BIN}/databricks"
}

install_uv() {
  local v; v="$(ver uv)"
  if have uv "${v}" uv --version; then echo "uv ${v} ok"; return; fi
  echo "Installing uv ${v}"
  curl -fsSL "https://astral.sh/uv/${v}/install.sh" | UV_INSTALL_DIR="${BIN}" UV_NO_MODIFY_PATH=1 sh
}

install_python() {
  local v; v="$(ver python)"
  echo "Ensuring python ${v}"
  uv python install "${v}"
}

install_azure_cli() {
  local v py; v="$(ver azure-cli)"; py="$(ver python)"
  if have az "${v}" az version --query '"azure-cli"' -o tsv; then echo "azure-cli ${v} ok"; return; fi
  echo "Installing azure-cli ${v}"
  # azure-cli itself depends on beta packages (azure-appconfiguration, azure-mgmt-appconfiguration), so pre-releases must be allowed; azure-cli stays pinned.
  uv tool install --force --python "${py}" --prerelease allow "azure-cli==${v}"
}

install_uv
install_python
install_terraform
install_helm
install_kubectl
install_databricks
install_azure_cli

echo
echo "Done. Ensure ${BIN} is on your PATH (e.g. add 'export PATH=\"\$HOME/.local/bin:\$PATH\"' to ~/.bashrc)."

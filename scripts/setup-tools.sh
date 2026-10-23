#!/usr/bin/env bash
# Install the CLIs listed in .tool-versions. Idempotent: skips a tool already at the pinned version.
# Linux and macOS, x86_64/arm64. terraform, helm, kubectl, databricks-cli and uv are downloaded from
# their official release hosts into ~/.local/bin (no sudo), checksums verified. Python comes via uv.
#
# azure-cli has no standalone binary, so the install method depends on the platform
# (override with AZ_INSTALL=apt|brew|pip):
#   apt   Debian/Ubuntu: Microsoft's official apt repo, version-pinned (needs sudo)   [default there]
#   brew  macOS with Homebrew (cannot pin a version; warns if it differs)             [default there]
#   pip   any other Unix: PyPI package into an isolated uv tool environment (no sudo)  [fallback]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${HOME}/.local/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
mkdir -p "${BIN}"
export PATH="${BIN}:${PATH}"

case "$(uname -s)" in
  Linux)  OS=linux ;;
  Darwin) OS=darwin ;;
  *) echo "Unsupported OS $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64)  ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "Unsupported arch $(uname -m)" >&2; exit 1 ;;
esac

ver() { awk -v t="$1" '$1 == t { print $2 }' "${ROOT}/.tool-versions"; }

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi; }

verify() { # verify <file> <expected sha256>
  [ "$(sha256 "$1" | awk '{ print $1 }')" = "$2" ] || { echo "Checksum mismatch for $1" >&2; exit 1; }
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
  local base="https://releases.hashicorp.com/terraform/${v}" zip="terraform_${v}_${OS}_${ARCH}.zip"
  curl -fsSL -o "${TMP}/${zip}" "${base}/${zip}"
  verify "${TMP}/${zip}" "$(curl -fsSL "${base}/terraform_${v}_SHA256SUMS" | awk -v f="${zip}" '$2 == f { print $1 }')"
  python3 -m zipfile -e "${TMP}/${zip}" "${TMP}/tf"
  install -m 0755 "${TMP}/tf/terraform" "${BIN}/terraform"
}

install_helm() {
  local v; v="$(ver helm)"
  if have helm "v${v}" helm version --short; then echo "helm ${v} ok"; return; fi
  echo "Installing helm ${v}"
  local tgz="helm-v${v}-${OS}-${ARCH}.tar.gz" base="https://get.helm.sh"
  curl -fsSL -o "${TMP}/${tgz}" "${base}/${tgz}"
  verify "${TMP}/${tgz}" "$(curl -fsSL "${base}/${tgz}.sha256sum" | awk '{ print $1 }')"
  tar -xzf "${TMP}/${tgz}" -C "${TMP}" "${OS}-${ARCH}/helm"
  install -m 0755 "${TMP}/${OS}-${ARCH}/helm" "${BIN}/helm"
}

install_kubectl() {
  local v; v="$(ver kubectl)"
  if have kubectl "v${v}" kubectl version --client; then echo "kubectl ${v} ok"; return; fi
  echo "Installing kubectl ${v}"
  local base="https://dl.k8s.io/release/v${v}/bin/${OS}/${ARCH}"
  curl -fsSL -o "${TMP}/kubectl" "${base}/kubectl"
  verify "${TMP}/kubectl" "$(curl -fsSL "${base}/kubectl.sha256")"
  install -m 0755 "${TMP}/kubectl" "${BIN}/kubectl"
}

install_databricks() {
  local v; v="$(ver databricks-cli)"
  if have databricks "${v}" databricks --version; then echo "databricks ${v} ok"; return; fi
  echo "Installing databricks-cli ${v}"
  local base="https://github.com/databricks/cli/releases/download/v${v}" zip="databricks_cli_${v}_${OS}_${ARCH}.zip"
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

install_direnv() {
  local v; v="$(ver direnv)"
  if have direnv "${v}" direnv version; then echo "direnv ${v} ok"; return; fi
  echo "Installing direnv ${v}"
  local asset="direnv.${OS}-${ARCH}" api="https://api.github.com/repos/direnv/direnv/releases/tags/v${v}"
  curl -fsSL -o "${TMP}/direnv" "https://github.com/direnv/direnv/releases/download/v${v}/${asset}"
  # direnv publishes no checksum file; use the sha256 digest GitHub records for each release asset.
  verify "${TMP}/direnv" "$(curl -fsSL "${api}" | python3 -c "
import json, sys
name = sys.argv[1]
print(next(a['digest'].split(':', 1)[1] for a in json.load(sys.stdin)['assets'] if a['name'] == name))" "${asset}")"
  install -m 0755 "${TMP}/direnv" "${BIN}/direnv"
}

install_python() {
  local v; v="$(ver python)"
  echo "Ensuring python ${v}"
  uv python install "${v}"
}

az_method() {
  if [ -n "${AZ_INSTALL:-}" ]; then echo "${AZ_INSTALL}"; return; fi
  if [ "${OS}" = darwin ] && command -v brew >/dev/null; then echo brew; return; fi
  if [ "${OS}" = linux ] && [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case " ${ID:-} ${ID_LIKE:-} " in *" debian "*|*" ubuntu "*) command -v apt-get >/dev/null && { echo apt; return; } ;; esac
  fi
  echo pip
}

install_azure_cli_apt() {
  local v="$1" codename suite
  # shellcheck disable=SC1091
  codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
  suite="$(curl -fsS "https://packages.microsoft.com/repos/azure-cli/dists/${codename}/main/binary-$(dpkg --print-architecture)/Packages" \
    | grep -c "^Version: ${v}-1~${codename}$" || true)"
  if [ "${suite}" = 0 ]; then
    echo "Microsoft's apt repo has no azure-cli ${v} for '${codename}'; falling back to pip." >&2
    install_azure_cli_pip "${v}"; return
  fi
  echo "Adding Microsoft's azure-cli apt repo (sudo required)"
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/keyrings/microsoft.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/microsoft.gpg
  sudo tee /etc/apt/sources.list.d/azure-cli.sources >/dev/null <<SRC
Types: deb
URIs: https://packages.microsoft.com/repos/azure-cli/
Suites: ${codename}
Components: main
Architectures: $(dpkg --print-architecture)
Signed-by: /etc/apt/keyrings/microsoft.gpg
SRC
  sudo apt-get update -qq
  sudo apt-get install -y --allow-downgrades "azure-cli=${v}-1~${codename}"
  sudo apt-mark hold azure-cli >/dev/null
  # A pip-installed copy in ~/.local/bin would shadow the apt one.
  uv tool uninstall azure-cli >/dev/null 2>&1 || true
}

install_azure_cli_brew() {
  local v="$1"
  brew list azure-cli >/dev/null 2>&1 || brew install azure-cli
  have az "${v}" az version --query '"azure-cli"' -o tsv \
    || echo "WARNING: Homebrew installed azure-cli $(az version --query '"azure-cli"' -o tsv), pinned is ${v}. Homebrew cannot pin; use AZ_INSTALL=pip for an exact version." >&2
}

install_azure_cli_pip() {
  local v="$1" py; py="$(ver python)"
  # azure-cli itself depends on beta packages (azure-appconfiguration, azure-mgmt-appconfiguration),
  # so pre-releases must be allowed; azure-cli stays pinned.
  uv tool install --force --python "${py}" --prerelease allow "azure-cli==${v}"
}

install_azure_cli() {
  local v method; v="$(ver azure-cli)"; method="$(az_method)"
  if have az "${v}" az version --query '"azure-cli"' -o tsv; then echo "azure-cli ${v} ok"; return; fi
  echo "Installing azure-cli ${v} via ${method}"
  case "${method}" in
    apt)  install_azure_cli_apt "${v}" ;;
    brew) install_azure_cli_brew "${v}" ;;
    pip)  install_azure_cli_pip "${v}" ;;
    *) echo "Unknown AZ_INSTALL=${method}" >&2; exit 1 ;;
  esac
}

install_uv
install_python
install_terraform
install_helm
install_kubectl
install_databricks
install_azure_cli
install_direnv

echo
echo "Done. Ensure ${BIN} is on your PATH (e.g. add 'export PATH=\"\$HOME/.local/bin:\$PATH\"' to ~/.bashrc)."
echo
echo "To load .env automatically in this repo (one-time): add the hook for your shell to its rc file, then run 'direnv allow' in the repo."
echo "  bash: echo 'eval \"\$(direnv hook bash)\"' >> ~/.bashrc"
echo "  zsh:  echo 'eval \"\$(direnv hook zsh)\"' >> ~/.zshrc"

#!/usr/bin/env bash
# Idempotent installer of pinned CLI tooling into ./bin (no sudo, no apt, no pip).
#
# Usage:   scripts/install_tools.sh [helm] [ruff]   (default: all tools)
# Prints nothing but progress to stderr; safe to call repeatedly: a tool already present
# in ./bin with the pinned version is kept, any other version is replaced.
# Target platform: Linux amd64/arm64 (Ubuntu/Debian/Astra); macOS is best effort.
#
# Environment overrides:
#   HELM_VERSION   (default v3.15.4 — keep in sync with scripts/up.sh and .github/workflows/ci-cd.yml)
#   RUFF_VERSION   (default: the ruff==X.Y.Z pin from app/requirements-dev.txt, shared with CI)
#   HELM_BASE_URL  (default https://get.helm.sh)                          — for offline/corporate mirrors
#   RUFF_BASE_URL  (default https://github.com/astral-sh/ruff/releases/download)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BIN_DIR="${ROOT_DIR}/bin"

HELM_VERSION="${HELM_VERSION:-v3.15.4}"
RUFF_VERSION="${RUFF_VERSION:-$(sed -n 's/^ruff==\([0-9][0-9.]*\).*/\1/p' "${ROOT_DIR}/app/requirements-dev.txt")}"
HELM_BASE_URL="${HELM_BASE_URL:-https://get.helm.sh}"
RUFF_BASE_URL="${RUFF_BASE_URL:-https://github.com/astral-sh/ruff/releases/download}"

log() { echo "[deps] $*" >&2; }
die() { echo "[deps] ERROR: $*" >&2; exit 1; }

detect_platform() {
  case "$(uname -s)" in
    Linux)  OS=linux ;;
    Darwin) OS=darwin ;;
    *) die "unsupported OS '$(uname -s)'; supported: Linux (Ubuntu/Debian/Astra), macOS" ;;
  esac
  case "$(uname -m)" in
    x86_64 | amd64)  GO_ARCH=amd64; RUST_ARCH=x86_64 ;;
    aarch64 | arm64) GO_ARCH=arm64; RUST_ARCH=aarch64 ;;
    *) die "unsupported CPU architecture '$(uname -m)'" ;;
  esac
}

download() { # download <url> <dest>
  if command -v curl &>/dev/null; then
    curl -fsSL --retry 3 --connect-timeout 15 -o "$2" "$1"
  elif command -v wget &>/dev/null; then
    wget -q --tries=3 --timeout=15 -O "$2" "$1"
  else
    die "neither curl nor wget is available (sudo apt-get install -y curl)"
  fi
}

sha256_of() {
  if command -v sha256sum &>/dev/null; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# fetch_verified <archive-url> <checksum-url> <dest-file>
fetch_verified() {
  local url="$1" sum_url="$2" dest="$3" expected actual
  log "Downloading ${url}"
  download "${url}" "${dest}" || die "cannot download ${url} (offline, HTTP error or unknown version? set *_BASE_URL to a mirror)"
  download "${sum_url}" "${dest}.sha256" || die "cannot download checksum ${sum_url}"
  expected="$(awk '{print $1; exit}' "${dest}.sha256")"
  actual="$(sha256_of "${dest}")"
  [[ -n "${expected}" && "${expected}" == "${actual}" ]] \
    || die "checksum mismatch for $(basename "${url}"): expected '${expected}', got '${actual}'"
}

# extract_binary <archive> <binary-name> — puts the binary into ${BIN_DIR} atomically
extract_binary() {
  local archive="$1" name="$2" unpack="${TMP_DIR}/unpack-${2}" found staged
  mkdir -p "${unpack}"
  tar -xzf "${archive}" -C "${unpack}"
  found="$(find "${unpack}" -type f -name "${name}" -print -quit)"
  [[ -n "${found}" ]] || die "'${name}' not found inside $(basename "${archive}")"
  staged="$(mktemp "${BIN_DIR}/.${name}.XXXXXX")" # unique name: parallel runs never clash
  install -m 0755 "${found}" "${staged}"
  mv -f "${staged}" "${BIN_DIR}/${name}"
  log "Installed ${BIN_DIR}/${name}"
}

install_helm() {
  [[ "$("${BIN_DIR}/helm" version --template '{{.Version}}' 2>/dev/null)" == "${HELM_VERSION}" ]] && return 0
  local file="helm-${HELM_VERSION}-${OS}-${GO_ARCH}.tar.gz"
  fetch_verified "${HELM_BASE_URL}/${file}" "${HELM_BASE_URL}/${file}.sha256sum" "${TMP_DIR}/${file}"
  extract_binary "${TMP_DIR}/${file}" helm
}

install_ruff() {
  [[ "$("${BIN_DIR}/ruff" --version 2>/dev/null)" == "ruff ${RUFF_VERSION}" ]] && return 0
  local target file
  if [[ "${OS}" == "darwin" ]]; then
    target="${RUST_ARCH}-apple-darwin"
  else
    target="${RUST_ARCH}-unknown-linux-musl" # static build: works on any glibc (Ubuntu, Debian, Astra)
  fi
  file="ruff-${target}.tar.gz"
  fetch_verified "${RUFF_BASE_URL}/${RUFF_VERSION}/${file}" \
    "${RUFF_BASE_URL}/${RUFF_VERSION}/${file}.sha256" "${TMP_DIR}/${file}"
  extract_binary "${TMP_DIR}/${file}" ruff
}

main() {
  [[ -n "${RUFF_VERSION}" ]] || die "ruff version is not pinned (expected 'ruff==X.Y.Z' in app/requirements-dev.txt)"
  local tools=("$@")
  [[ ${#tools[@]} -gt 0 ]] || tools=(helm ruff)

  detect_platform
  mkdir -p "${BIN_DIR}"
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${TMP_DIR}"' EXIT

  local tool
  for tool in "${tools[@]}"; do
    case "${tool}" in
      helm) install_helm ;;
      ruff) install_ruff ;;
      *) die "unknown tool '${tool}' (supported: helm, ruff)" ;;
    esac
  done
}

main "$@"

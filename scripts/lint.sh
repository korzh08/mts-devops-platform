#!/usr/bin/env bash
# Static checks, identical to the CI quality gates (.github/workflows/ci-cd.yml):
#   1. ruff check app/                       (pinned ruff from app/requirements-dev.txt, rules in ruff.toml)
#   2. helm lint + helm template (stable and canary values)
# Missing tools are installed automatically into ./bin by scripts/install_tools.sh,
# so `make lint` works on a clean Ubuntu machine right after `git clone`.
#
# Overrides: RUFF=/path/to/ruff HELM=/path/to/helm make lint
set -euo pipefail
shopt -s inherit_errexit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BIN_DIR="${ROOT_DIR}/bin"
CHART_DIR="${ROOT_DIR}/deploy/helm/demo-api"
cd "${ROOT_DIR}"

die() { echo "[lint] ERROR: $*" >&2; exit 1; }

# Explicit overrides must point to an executable; never silently fall back.
for var in RUFF HELM; do
  [[ -z "${!var:-}" || -x "${!var}" ]] || die "${var}=${!var} is not an executable file"
done

# ruff results depend on its version, so (like CI) always use the pinned one.
if [[ -n "${RUFF:-}" ]]; then
  RUFF_BIN="${RUFF}"
else
  bash "${SCRIPT_DIR}/install_tools.sh" ruff # no-op when ./bin/ruff already has the pinned version
  RUFF_BIN="${BIN_DIR}/ruff"
fi

# helm lint barely depends on the version: reuse ./bin/helm or a system-wide helm,
# download the pinned one only if neither exists.
if [[ -n "${HELM:-}" ]]; then
  HELM_BIN="${HELM}"
elif [[ -x "${BIN_DIR}/helm" ]]; then
  HELM_BIN="${BIN_DIR}/helm"
elif command -v helm &>/dev/null; then
  HELM_BIN="$(command -v helm)"
else
  bash "${SCRIPT_DIR}/install_tools.sh" helm
  HELM_BIN="${BIN_DIR}/helm"
fi

failed=()
run_check() { # run_check <title> <command...>
  local title="$1"
  shift
  echo "=== ${title}"
  if "$@"; then
    echo "--> OK"
  else
    echo "--> FAILED: ${title}" >&2
    failed+=("${title}")
  fi
}

helm_template() { # helm_template [extra helm args...] — render the chart, discard manifests
  "${HELM_BIN}" template demo-api "${CHART_DIR}" --values "${CHART_DIR}/values.yaml" "$@" >/dev/null
}

echo "[lint] ruff: ${RUFF_BIN} ($("${RUFF_BIN}" --version))"
echo "[lint] helm: ${HELM_BIN} ($("${HELM_BIN}" version --short 2>/dev/null || echo unknown))"

run_check "ruff check app/" "${RUFF_BIN}" check app/
run_check "helm lint deploy/helm/demo-api" "${HELM_BIN}" lint "${CHART_DIR}"
run_check "helm template (stable values)" helm_template
run_check "helm template (canary values)" helm_template --values "${CHART_DIR}/values-canary.yaml"

if [[ ${#failed[@]} -gt 0 ]]; then
  echo "[lint] ${#failed[@]} check(s) failed: ${failed[*]}" >&2
  exit 1
fi
echo "[lint] All checks passed."

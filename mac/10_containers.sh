#!/bin/bash
# Phase 10 — Container & Kubernetes tools (macOS)
# Installs: ctop, dive, lazydocker, k9s, kubectl, helm, k3d, kind, minikube
#
# Soft-fail per formula so one broken package never aborts the rest.
set -euo pipefail

command -v brew &>/dev/null || { echo "ERROR: brew not found — run 01_basics.sh first"; exit 1; }

FAILED=()
brew_install() {
  local name="${1##*/}"
  if brew list --formula --versions "$name" &>/dev/null; then
    echo "  ✓ ${name} (already installed)"; return 0
  fi
  echo "  → installing $1 ..."
  brew install "$1" || { echo "  ✗ FAILED: $1"; FAILED+=("$1"); }
}

for f in ctop dive lazydocker k9s kubectl helm k3d kind minikube; do
  brew_install "$f"
done

echo ""
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "✅ Container tools installed: ctop, dive, lazydocker, k9s, kubectl, helm, k3d, kind, minikube"
else
  echo "⚠️  Completed with failure(s): ${FAILED[*]}"
fi
echo "NOTE: Docker Desktop must be installed manually from https://www.docker.com/products/docker-desktop/"

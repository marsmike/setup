#!/bin/bash
# Phase 3 — Optional
# Installs kind (Kubernetes IN Docker) — latest version from GitHub.
set -euo pipefail

KIND_VERSION=$(curl -sL "https://api.github.com/repos/kubernetes-sigs/kind/releases/latest" \
  | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

echo "Installing kind v${KIND_VERSION}..."

# For AMD64 / x86_64
[ "$(uname -m)" = x86_64 ] && \
  curl -Lo ./kind "https://kind.sigs.k8s.io/dl/v${KIND_VERSION}/kind-linux-amd64"

# For ARM64 — uncomment if needed:
# [ "$(uname -m)" = aarch64 ] && \
#   curl -Lo ./kind "https://kind.sigs.k8s.io/dl/v${KIND_VERSION}/kind-linux-arm64"

chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

echo "kind v${KIND_VERSION} installed."

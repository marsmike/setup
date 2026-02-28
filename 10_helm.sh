#!/bin/bash
# Phase 2 — Dev tools
# Installs Helm 3 via the official installer script.
set -euo pipefail

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
rm ./get_helm.sh

echo "helm $(helm version --short) installed."

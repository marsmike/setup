#!/bin/bash
# Phase 2 — Dev tools
# Installs the latest stable kubectl.
set -euo pipefail

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod u+x kubectl
sudo mv kubectl /usr/local/bin/kubectl

echo "kubectl $(kubectl version --client) installed."

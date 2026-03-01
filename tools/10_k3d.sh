#!/bin/bash
# Phase 2 — Dev tools
# Installs k3d (lightweight k3s in Docker).
set -euo pipefail

curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

echo "k3d $(k3d version) installed."

#!/bin/bash
# Phase 3 — Optional
# Installs Teleport v17 via the official installer.
set -euo pipefail

TELEPORT_VERSION="${1:-17}"

echo "Installing Teleport v${TELEPORT_VERSION}..."
curl https://goteleport.com/static/install.sh | bash -s "${TELEPORT_VERSION}"

echo "Teleport installed. See: https://goteleport.com/docs/"

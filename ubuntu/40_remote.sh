#!/bin/bash
# Remote access tools (low-priority / optional)
# Installs: Coder (self-hosted dev environments), Teleport
set -euo pipefail

# --- Coder ---
echo "Installing Coder..."
curl -fsSL https://coder.com/install.sh | sh
echo "Coder installed. Run 'coder server' to start."

# --- Teleport ---
TELEPORT_VERSION="${1:-17}"
echo "Installing Teleport v${TELEPORT_VERSION}..."
curl https://goteleport.com/static/install.sh | bash -s "${TELEPORT_VERSION}"
echo "Teleport installed. See: https://goteleport.com/docs/"

echo ""
echo "Remote tools installed: coder, teleport"

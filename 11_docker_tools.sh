#!/bin/bash
# Phase 2 — Dev tools
# Installs ctop, dive, and lazydocker.
set -euo pipefail

# --- ctop (latest from GitHub) ---
echo "Installing ctop..."
CTOP_VERSION=$(curl -sL "https://api.github.com/repos/bcicen/ctop/releases/latest" \
  | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
sudo curl -Lo /usr/local/bin/ctop \
  "https://github.com/bcicen/ctop/releases/download/v${CTOP_VERSION}/ctop-${CTOP_VERSION}-linux-amd64"
sudo chmod +x /usr/local/bin/ctop
echo "ctop v${CTOP_VERSION} installed."

# --- dive ---
echo "Installing dive..."
DIVE_VERSION=$(curl -sL "https://api.github.com/repos/wagoodman/dive/releases/latest" \
  | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
curl -OL "https://github.com/wagoodman/dive/releases/download/v${DIVE_VERSION}/dive_${DIVE_VERSION}_linux_amd64.deb"
sudo dpkg -i "./dive_${DIVE_VERSION}_linux_amd64.deb"
rm "./dive_${DIVE_VERSION}_linux_amd64.deb"
echo "dive v${DIVE_VERSION} installed."

# --- lazydocker ---
echo "Installing lazydocker..."
LAZYDOCKER_VER=$(curl -fsSL "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest" \
  | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
TMP=$(mktemp -d)
curl -fsSL "https://github.com/jesseduffield/lazydocker/releases/download/v${LAZYDOCKER_VER}/lazydocker_${LAZYDOCKER_VER}_Linux_x86_64.tar.gz" \
  | tar -xzf - -C "$TMP"
sudo install "$TMP/lazydocker" /usr/local/bin/lazydocker
rm -rf "$TMP"
echo "lazydocker v${LAZYDOCKER_VER} installed."

#!/bin/bash
# VM tooling
# Installs: QEMU/KVM, libvirt, quickemu (+ quickget), and adds user to kvm/libvirt groups.
set -euo pipefail

if ! command -v apt &>/dev/null; then
  echo "ERROR: apt not found — this script requires Ubuntu/Debian/Mint." >&2
  exit 1
fi

sudo apt update

# --- QEMU/KVM prerequisites ---
echo "Installing QEMU/KVM..."
sudo apt install -y qemu-system-x86 qemu-kvm libvirt-daemon-system virtinst

# --- quickemu (includes quickget; Ubuntu 22.04+ universe) ---
echo "Installing quickemu..."
sudo add-apt-repository -y universe || true
sudo apt install -y quickemu || {
  echo "quickemu not found in apt — trying GitHub release..."
  QUICKEMU_VER=$(curl -sL "https://api.github.com/repos/quickemu-project/quickemu/releases/latest" \
    | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL "https://github.com/quickemu-project/quickemu/releases/download/${QUICKEMU_VER}/quickemu" \
    -o "$TMP/quickemu"
  curl -fsSL "https://github.com/quickemu-project/quickemu/releases/download/${QUICKEMU_VER}/quickget" \
    -o "$TMP/quickget"
  sudo install "$TMP/quickemu" /usr/local/bin/quickemu
  sudo install "$TMP/quickget" /usr/local/bin/quickget
  trap - EXIT; rm -rf "$TMP"
}

# --- User group membership ---
echo "Adding ${USER} to kvm and libvirt groups..."
sudo usermod -aG kvm,libvirt "$USER"

echo ""
echo "VM tools installed: QEMU/KVM, quickemu, quickget"
echo "NOTE: log out and back in for group membership (kvm, libvirt) to take effect."

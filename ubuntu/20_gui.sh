#!/bin/bash
# GUI applications
# Installs: flatpak (+ flathub), ghostty, Obsidian, Discord, Google Chrome, Firefox
set -euo pipefail

if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  echo "No display detected — skipping GUI installs"
  exit 0
fi

if ! command -v apt &>/dev/null; then
  echo "ERROR: apt not found — this script requires Ubuntu/Debian/Mint." >&2
  exit 1
fi

# --- flatpak + flathub ---
sudo apt install -y flatpak
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# --- Flatpak apps ---
flatpak install -y flathub org.ghostty.ghostty || true
flatpak install -y flathub md.obsidian.Obsidian || true
flatpak install -y flathub com.discordapp.Discord || true

# --- Google Chrome (deb → dpkg; Google apt repo for updates) ---
if ! command -v google-chrome-stable &>/dev/null && ! command -v google-chrome &>/dev/null; then
  echo "Installing Google Chrome..."
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" \
    -o "$TMP/chrome.deb"
  sudo dpkg -i "$TMP/chrome.deb" || sudo apt -f install -y
  trap - EXIT; rm -rf "$TMP"
  echo "Google Chrome installed."
else
  echo "Google Chrome already installed, skipping."
fi

# --- Firefox ---
if ! command -v firefox &>/dev/null; then
  echo "Installing Firefox..."
  sudo apt install -y firefox || sudo apt install -y firefox-esr
  echo "Firefox installed."
else
  echo "Firefox already installed, skipping."
fi

echo ""
echo "GUI apps installed: ghostty (flatpak), Obsidian (flatpak), Discord (flatpak), Chrome, Firefox"

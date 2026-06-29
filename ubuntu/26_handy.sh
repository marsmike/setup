#!/bin/bash
# Handy — local Whisper push-to-talk dictation (cross-platform WisprFlow alt).
# Distro-aware: installs the .deb on apt systems, the .rpm on dnf systems, and
# falls back to the portable AppImage anywhere else. Version is resolved at
# runtime from GitHub releases (no hardcoded version, per repo convention).
#
# Hold a global hotkey, speak, release → text is typed at the cursor in any
# app. 100% on-device. Upstream: https://github.com/cjpais/Handy
set -uo pipefail

# Helper for authenticated GitHub API calls (avoids rate limits when gh is set up)
gh_api() {
  if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    curl -H "Authorization: token $(gh auth token)" -fsSL "https://api.github.com/$1"
  else
    curl -fsSL "https://api.github.com/$1"
  fi
}
log_error() { echo "ERROR: $1" >&2; }

if command -v handy &>/dev/null; then
  echo "  ✓ handy (already installed)"
else
  VER=$(gh_api repos/cjpais/Handy/releases/latest | grep -oP '"tag_name": "v?\K[^"]+')
  [ -z "${VER:-}" ] && { log_error "could not resolve latest Handy version"; exit 1; }
  BASE="https://github.com/cjpais/Handy/releases/download/v${VER}"
  MACH=$(uname -m)  # x86_64 | aarch64 | arm64
  TMP=$(mktemp -d)

  if command -v apt &>/dev/null; then
    # Debian/Ubuntu/Mint — .deb uses amd64/arm64 naming
    case "$MACH" in x86_64) DARCH=amd64 ;; aarch64|arm64) DARCH=arm64 ;; *) DARCH= ;; esac
    if [ -n "$DARCH" ] && curl -fsSL "${BASE}/Handy_${VER}_${DARCH}.deb" -o "$TMP/handy.deb"; then
      sudo apt install -y "$TMP/handy.deb" || sudo dpkg -i "$TMP/handy.deb" || log_error "dpkg install failed"
    else
      log_error "no .deb for arch '$MACH' — try the AppImage below"
    fi
  elif command -v dnf &>/dev/null; then
    # Fedora/RHEL — .rpm uses x86_64/aarch64 naming
    if curl -fsSL "${BASE}/Handy-${VER}-1.${MACH}.rpm" -o "$TMP/handy.rpm"; then
      sudo dnf install -y "$TMP/handy.rpm" || log_error "rpm install failed"
    else
      log_error "no .rpm for arch '$MACH' — try the AppImage below"
    fi
  else
    # Portable fallback — AppImage to ~/.local/bin (amd64/aarch64 naming)
    case "$MACH" in x86_64) AARCH=amd64 ;; aarch64|arm64) AARCH=aarch64 ;; *) AARCH= ;; esac
    if [ -n "$AARCH" ] && mkdir -p "$HOME/.local/bin" && \
       curl -fsSL "${BASE}/Handy_${VER}_${AARCH}.AppImage" -o "$HOME/.local/bin/handy"; then
      chmod +x "$HOME/.local/bin/handy"
      echo "  → installed AppImage to ~/.local/bin/handy (ensure it is on PATH)"
    else
      log_error "no AppImage for arch '$MACH'"
    fi
  fi
fi

# --- runtime deps Handy needs on Linux (soft-fail; names vary by distro) ---
# libgtk-layer-shell: overlay window. xdotool (X11) / wtype (Wayland): text input.
echo "Installing Handy runtime deps (text input + layer-shell)..."
if command -v apt &>/dev/null; then
  sudo apt install -y libgtk-layer-shell0 xdotool wtype 2>/dev/null \
    || log_error "some Handy deps failed (libgtk-layer-shell0/xdotool/wtype)"
elif command -v dnf &>/dev/null; then
  sudo dnf install -y gtk-layer-shell xdotool wtype 2>/dev/null \
    || log_error "some Handy deps failed (gtk-layer-shell/xdotool/wtype)"
fi

echo "Done. Launch Handy, grant Accessibility/input permissions, set a push-to-talk hotkey,"
echo "and pick the large-v3-turbo model for best accuracy."

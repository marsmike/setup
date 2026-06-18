#!/bin/bash
# Phase 1 — Core (macOS)
# Installs Homebrew (if missing) and baseline packages.
#
# Robust by design: each formula/cask is installed independently with
# soft-fail, so one broken or unreachable package (or tap) never aborts the
# whole run. Previously a single monolithic `brew install` under `set -e`
# meant one bad entry left everything after it — tmux included — uninstalled.
set -euo pipefail

# --- Install Homebrew if not present ---
if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Ensure brew is on PATH for the rest of this script regardless of arch
# (/opt/homebrew on Apple Silicon, /usr/local on Intel).
if ! command -v brew &>/dev/null; then
  for prefix in /opt/homebrew /usr/local; do
    [ -x "${prefix}/bin/brew" ] && eval "$(${prefix}/bin/brew shellenv)" && break
  done
fi
command -v brew &>/dev/null || { echo "ERROR: brew not found after install"; exit 1; }

# --- soft-fail install helpers (idempotent; one failure never aborts) ---
FAILED=()

brew_install() {
  # $1 = formula (may be tap-qualified, e.g. owner/tap/name)
  local f="$1" name="${1##*/}"
  if brew list --formula --versions "$name" &>/dev/null; then
    echo "  ✓ ${name} (already installed)"
    return 0
  fi
  echo "  → installing ${f} ..."
  brew install "$f" || { echo "  ✗ FAILED: ${f}"; FAILED+=("$f"); }
}

cask_install() {
  local c="$1"
  if brew list --cask --versions "$c" &>/dev/null; then
    echo "  ✓ ${c} (cask already installed)"
    return 0
  fi
  echo "  → installing cask ${c} ..."
  brew install --cask "$c" || { echo "  ✗ FAILED: cask ${c}"; FAILED+=("cask ${c}"); }
}

# --- taps required by some formulae below (tap explicitly so a tap failure
#     is isolated rather than aborting an install that references it) ---
for tap in arimxyer/tap gromgit/brewtils AlexsJones/llmfit; do
  brew tap "$tap" 2>/dev/null || { echo "  ✗ tap failed: ${tap}"; FAILED+=("tap ${tap}"); }
done

# --- baseline formulae ---
echo "Installing baseline formulae..."
FORMULAE=(
  git gh vim wget
  zoxide fzf bat jq tmux zsh btop ncdu tldr httpie rsync
  eza ripgrep fd
  lazygit
  git-delta direnv hyperfine lnav watchexec yq glow
  jless csvlens viddy
  arimxyer/tap/models
  gromgit/brewtils/taproom
  mactop
  timg
  nvm
  AlexsJones/llmfit/llmfit
  yt-dlp gemini-cli
)
for f in "${FORMULAE[@]}"; do brew_install "$f"; done

# --- casks ---
echo "Installing casks..."
for c in ghostty codex; do cask_install "$c"; done

# --- Node LTS via nvm ---
echo "Setting up nvm + Node LTS..."
mkdir -p ~/.nvm
export NVM_DIR="$HOME/.nvm"
if [ -s "$(brew --prefix nvm 2>/dev/null)/nvm.sh" ]; then
  # shellcheck source=/dev/null
  \. "$(brew --prefix nvm)/nvm.sh"
  nvm install --lts && nvm alias default 'lts/*' || echo "  ✗ nvm node install failed"
else
  echo "  ✗ nvm not installed — skipping Node setup"
fi

# --- bun ---
if ! command -v bun &>/dev/null; then
  echo "Installing bun..."
  curl -fsSL https://bun.sh/install | bash || echo "  ✗ bun install failed"
fi

# --- summary ---
echo ""
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "✅ All packages installed."
else
  echo "⚠️  Completed with ${#FAILED[@]} failure(s) — re-run to retry just these:"
  printf '   - %s\n' "${FAILED[@]}"
fi

echo ""
echo "Note: Docker Desktop must be installed manually from https://www.docker.com/products/docker-desktop/"
echo "Next: 02_shell.sh then 03_dotfiles.sh"

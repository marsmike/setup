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

# Persist brew on PATH for future login shells. Written to ~/.zprofile (NOT
# .zshrc): .zshrc is chezmoi-managed and 03_dotfiles.sh force-applies it on
# every run, which would silently wipe a manual edit there. .zprofile is
# untouched by chezmoi, so this survives indefinitely. Guarded so re-running
# this script never duplicates the block.
ZPROFILE="${HOME}/.zprofile"
BREW_MARKER="# >>> mac/01_basics.sh: brew on PATH >>>"
if ! grep -qF "$BREW_MARKER" "$ZPROFILE" 2>/dev/null; then
  {
    echo ""
    echo "$BREW_MARKER"
    echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\""
    echo "# <<< mac/01_basics.sh <<<"
  } >> "$ZPROFILE"
  echo "  ✓ Added brew shellenv to ~/.zprofile for future shells"
fi

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
  sst/tap/opencode   # upstream tap — homebrew-core lags releases
)
for f in "${FORMULAE[@]}"; do brew_install "$f"; done

# --- casks ---
echo "Installing casks..."
for c in ghostty codex handy; do cask_install "$c"; done  # handy = local Whisper push-to-talk dictation
# Model backends + Antigravity: all self-update after install.
# lm-studio serves local models on :1234; ollama-app runs the daemon on :11434
# that proxies Ollama cloud models (`ollama signin` once).
for c in antigravity lm-studio ollama-app; do cask_install "$c"; done

# --- Nerd Fonts (JetBrainsMono + Meslo — match ubuntu/01_basics.sh) ---
echo "Installing Nerd Fonts..."
for c in font-jetbrains-mono-nerd-font font-meslo-lg-nerd-font; do cask_install "$c"; done

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
export PATH="$HOME/.bun/bin:$PATH"

# --- ccstatusline (Claude Code status line — global bun packages don't
# survive a bun reinstall, so re-check every run) ---
if command -v bun &>/dev/null && ! command -v ccstatusline &>/dev/null; then
  echo "Installing ccstatusline..."
  bun add -g ccstatusline || echo "  ✗ ccstatusline install failed"
fi

# --- Claude Code (Anthropic's native installer → ~/.local/bin/claude) ---
if ! command -v claude &>/dev/null; then
  echo "Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash || echo "  ✗ Claude Code install failed"
fi

# --- Antigravity CLI (Google's installer → ~/.local/bin/agy, self-updates) ---
if [ ! -x "$HOME/.local/bin/agy" ]; then
  echo "Installing Antigravity CLI..."
  curl -fsSL https://antigravity.google/cli/install.sh | bash || echo "  ✗ agy install failed"
fi

# Pi coding agent is installed by chezmoi's run_onchange_after_install-bun-globals.sh
# (03_dotfiles.sh), next to the ~/.pi/agent config it reads.

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

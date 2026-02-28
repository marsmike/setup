#!/bin/bash
# Phase 1 — Core (every machine)
# Installs oh-my-zsh, powerlevel10k theme, and essential plugins.
# Idempotent — safe to re-run.
set -euo pipefail

ZSH_DIR="${HOME}/.oh-my-zsh"
CUSTOM="${ZSH_DIR}/custom"

# --- oh-my-zsh ---
# Check the actual framework file, not just the directory — the custom/
# subdirectory can exist before the framework is installed (e.g. from
# chezmoi dotfiles or a partial previous run), giving a false positive.
if [ -f "${ZSH_DIR}/oh-my-zsh.sh" ]; then
  echo "oh-my-zsh already installed, skipping."
else
  # If a partial/empty directory exists, back up custom and remove it so
  # the installer can clone fresh.
  if [ -d "${ZSH_DIR}" ]; then
    echo "Partial oh-my-zsh directory found — cleaning up before install..."
    [ -d "${CUSTOM}" ] && cp -r "${CUSTOM}" /tmp/omz-custom-backup
    rm -rf "${ZSH_DIR}"
  fi
  echo "Installing oh-my-zsh..."
  RUNZSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  # Restore any pre-existing custom plugins/themes
  if [ -d /tmp/omz-custom-backup ]; then
    cp -rn /tmp/omz-custom-backup/. "${CUSTOM}/"
    rm -rf /tmp/omz-custom-backup
  fi
fi

# --- powerlevel10k theme ---
P10K_DIR="${CUSTOM}/themes/powerlevel10k"
if [ -d "${P10K_DIR}" ]; then
  echo "powerlevel10k already installed, skipping."
else
  echo "Installing powerlevel10k..."
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${P10K_DIR}"
fi

# --- zsh-autosuggestions ---
AUTOSUGGEST_DIR="${CUSTOM}/plugins/zsh-autosuggestions"
if [ -d "${AUTOSUGGEST_DIR}" ]; then
  echo "zsh-autosuggestions already installed, skipping."
else
  echo "Installing zsh-autosuggestions..."
  git clone https://github.com/zsh-users/zsh-autosuggestions "${AUTOSUGGEST_DIR}"
fi

# --- zsh-syntax-highlighting ---
SYNTAX_DIR="${CUSTOM}/plugins/zsh-syntax-highlighting"
if [ -d "${SYNTAX_DIR}" ]; then
  echo "zsh-syntax-highlighting already installed, skipping."
else
  echo "Installing zsh-syntax-highlighting..."
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${SYNTAX_DIR}"
fi

# --- ensure history file exists (mcfly/atuin error if it's missing) ---
touch "${HOME}/.zsh_history"

# --- guard mcfly in .zshrc (it's optional — only run if installed) ---
# The dotfiles .zshrc has a bare eval that errors when mcfly isn't installed.
# Replace it with a guarded version so it silently skips if not present.
if [ -f "${HOME}/.zshrc" ] && grep -q '^eval "\$(mcfly init zsh)"' "${HOME}/.zshrc"; then
  echo "Guarding mcfly in .zshrc (skips silently if mcfly not installed)..."
  sed -i.bak 's|^eval "\$(mcfly init zsh)"|command -v mcfly \&>/dev/null \&\& eval "$(mcfly init zsh)"|' \
    "${HOME}/.zshrc" && rm -f "${HOME}/.zshrc.bak"
fi

# --- set zsh as default shell ---
ZSH_BIN="$(which zsh)"
if [ "${SHELL}" != "${ZSH_BIN}" ]; then
  echo "Setting zsh as default shell..."
  if sudo -n usermod -s "${ZSH_BIN}" "${USER}" 2>/dev/null; then
    echo "Default shell changed to zsh."
  else
    echo "NOTE: Could not set default shell automatically (needs sudo)."
    echo "Run manually: chsh -s ${ZSH_BIN}"
  fi
fi

echo ""
echo "============================================================"
echo "Done! Next steps:"
echo "  1. exec zsh                   (reload shell)"
echo "  2. p10k configure             (optional — config already in dotfiles)"
echo "============================================================"
echo ""
echo "Make sure your .zshrc contains:"
echo '  ZSH_THEME="powerlevel10k/powerlevel10k"'
echo '  plugins=(git zsh-autosuggestions zsh-syntax-highlighting)'

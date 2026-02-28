#!/bin/bash
# Phase 1 — Core (every machine)
# Installs oh-my-zsh, powerlevel10k theme, and essential plugins.
# Idempotent — safe to re-run.
set -euo pipefail

ZSH_DIR="${HOME}/.oh-my-zsh"
CUSTOM="${ZSH_DIR}/custom"

# --- oh-my-zsh ---
if [ -f "${ZSH_DIR}/oh-my-zsh.sh" ]; then
  echo "oh-my-zsh already installed, skipping."
else
  echo "Installing oh-my-zsh..."
  RUNZSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
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

# --- set zsh as default shell ---
ZSH_BIN="$(which zsh)"
if [ "${SHELL}" != "${ZSH_BIN}" ]; then
  echo "Setting zsh as default shell..."
  chsh -s "${ZSH_BIN}"
fi

echo ""
echo "============================================================"
echo "Done! Next steps:"
echo "  1. exec zsh          (reload shell)"
echo "  2. p10k configure    (interactive prompt setup)"
echo "  3. chezmoi add ~/.p10k.zsh && chezmoi cd && git add dot_p10k.zsh && git commit -m 'add p10k config' && git push"
echo "============================================================"
echo ""
echo "Make sure your .zshrc contains:"
echo '  ZSH_THEME="powerlevel10k/powerlevel10k"'
echo '  plugins=(git zsh-autosuggestions zsh-syntax-highlighting)'

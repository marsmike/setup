#!/bin/bash
# Phase 3 — Optional
# Installs Miniconda (default) or Anaconda.
# Note: for most Python workflows, 20_uv.sh (uv) is faster and lighter.
set -euo pipefail

# --- Configuration ---
# Set MODE to "miniconda" (recommended, lighter) or "anaconda" (full suite)
MODE="${1:-miniconda}"
ANACONDA_VERSION="Anaconda3-2024.10-1"

case "${MODE}" in
  miniconda)
    echo "Installing Miniconda (latest)..."
    curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o ~/miniconda.sh
    bash ~/miniconda.sh -b -p "${HOME}/miniconda"
    rm ~/miniconda.sh
    echo "Miniconda installed at ~/miniconda"
    echo "Run: ~/miniconda/bin/conda init zsh"
    ;;
  anaconda)
    echo "Installing Anaconda ${ANACONDA_VERSION}..."
    curl -L -O "https://repo.anaconda.com/archive/${ANACONDA_VERSION}-Linux-x86_64.sh"
    bash "./${ANACONDA_VERSION}-Linux-x86_64.sh"
    rm "./${ANACONDA_VERSION}-Linux-x86_64.sh"
    echo "Anaconda installed."
    ;;
  *)
    echo "Usage: $0 [miniconda|anaconda]" >&2
    exit 1
    ;;
esac

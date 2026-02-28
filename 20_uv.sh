#!/bin/bash
# Phase 3 — Optional
# Installs uv — extremely fast Python package and project manager by Astral.
# Modern alternative to pip/conda for most Python workflows.
set -euo pipefail

curl -LsSf https://astral.sh/uv/install.sh | sh

echo ""
echo "uv installed."
echo ""
echo "Quick reference:"
echo "  uv python install 3.12   # install a Python version"
echo "  uv pip install <pkg>      # fast pip replacement"
echo "  uv run script.py          # run with auto-managed deps"
echo "  uv venv && source .venv/bin/activate"

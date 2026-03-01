#!/bin/bash
# Phase 3 — Optional
# Installs Coder (self-hosted dev environments).
set -euo pipefail

curl -fsSL https://coder.com/install.sh | sh

echo "Coder installed. Run 'coder server' to start."

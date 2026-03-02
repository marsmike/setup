#!/bin/bash
# bootstrap/local/01_keygen.sh
# Generates an ED25519 SSH key pair on this machine (if none exists).
# Reads SETUP_SSH_KEY from repo root .env.
#
# Usage:
#   bash bootstrap/local/01_keygen.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[ -f "${REPO_ROOT}/.env" ] && set -o allexport && source "${REPO_ROOT}/.env" && set +o allexport

KEY_PATH="${SETUP_SSH_KEY:-${HOME}/.ssh/id_ed25519}"

if [ -f "${KEY_PATH}" ]; then
  echo "Key already exists at ${KEY_PATH}, skipping keygen."
  echo "Public key:"
  cat "${KEY_PATH}.pub"
  exit 0
fi

echo "Generating ED25519 key pair at ${KEY_PATH}..."
mkdir -p "$(dirname "${KEY_PATH}")"
chmod 700 "$(dirname "${KEY_PATH}")"
ssh-keygen -t ed25519 -f "${KEY_PATH}" -C "${USER}@$(hostname)"

echo ""
echo "Key generated. Public key:"
cat "${KEY_PATH}.pub"
echo ""
echo "Next: bash bootstrap/local/02_key_upload.sh"

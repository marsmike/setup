#!/bin/bash
# bootstrap/local/02_key_upload.sh
# Copies the public SSH key to the remote host (ssh-copy-id).
# Reads SETUP_USER, SETUP_HOST, SETUP_SSH_KEY from repo root .env.
#
# Usage:
#   bash bootstrap/local/02_key_upload.sh
#   bash bootstrap/local/02_key_upload.sh user@host
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[ -f "${REPO_ROOT}/.env" ] && set -o allexport && source "${REPO_ROOT}/.env" && set +o allexport

REMOTE="${1:-${SETUP_HOST:-}}"
KEY_PATH="${SETUP_SSH_KEY:-${HOME}/.ssh/id_ed25519}"

if [ -z "${REMOTE}" ]; then
  read -rp "Remote host (user@host or host): " REMOTE
fi

if [ ! -f "${KEY_PATH}.pub" ]; then
  echo "ERROR: Public key not found at ${KEY_PATH}.pub" >&2
  echo "Run: bash bootstrap/local/01_keygen.sh" >&2
  exit 1
fi

echo "Copying public key to ${REMOTE}..."
ssh-copy-id -i "${KEY_PATH}.pub" "${REMOTE}"

echo ""
echo "Done. Test with: bash bootstrap/local/03_key_test.sh"

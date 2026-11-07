#!/bin/bash
# bootstrap/local/02_key_upload.sh
# Copies the public SSH key to the account you connect with (ssh-copy-id).
# On a fresh server that account is root, because SETUP_USER does not exist
# yet. 04_adduser.sh installs the same key for SETUP_USER afterwards.
#
# Usage:
#   SSH_USER=root bash bootstrap/local/02_key_upload.sh   # fresh server
#   bash bootstrap/local/02_key_upload.sh                 # existing SETUP_USER
#   bash bootstrap/local/02_key_upload.sh user@host       # explicit target
set -euo pipefail

# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
load_setup_env

if [ -n "${1:-}" ]; then
  REMOTE="$1"
else
  require_setup_target
  REMOTE="${SSH_USER}@${HOST_ONLY}"
fi

if [ ! -f "${KEY_PATH}.pub" ]; then
  echo "ERROR: Public key not found at ${KEY_PATH}.pub" >&2
  echo "Run: bash bootstrap/local/01_keygen.sh" >&2
  exit 1
fi

echo "Copying public key to ${REMOTE}..."
ssh-copy-id -i "${KEY_PATH}.pub" "${REMOTE}"

echo ""
echo "Done. Next: SSH_USER=root bash bootstrap/server/04_adduser.sh"

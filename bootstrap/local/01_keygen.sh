#!/bin/bash
# bootstrap/local/01_keygen.sh
# Generates an ED25519 SSH key pair for one server (if none exists) and adds the
# server to ~/.ssh/config so only that key is offered to it.
#
# The key is ~/.ssh/id_ed25519_<host>, where <host> comes from SETUP_HOST.
# SETUP_SSH_KEY overrides the path.
#
# Usage:
#   bash bootstrap/local/01_keygen.sh
#   SETUP_HOST=mike@other.example.com bash bootstrap/local/01_keygen.sh
set -euo pipefail

# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
load_setup_env
require_setup_target

mkdir -p "$(dirname "${KEY_PATH}")"
chmod 700 "$(dirname "${KEY_PATH}")"

if [ -f "${KEY_PATH}" ]; then
  echo "Key already exists at ${KEY_PATH}, skipping keygen."
else
  echo "Generating ED25519 key pair at ${KEY_PATH}..."
  ssh-keygen -t ed25519 -f "${KEY_PATH}" -C "${USER}@$(hostname) for ${HOST_ONLY}"
fi

echo ""
echo "Public key:"
cat "${KEY_PATH}.pub"
echo ""
ensure_ssh_config_entry "${HOST_ONLY}"

echo ""
echo "Next: SSH_USER=root bash bootstrap/local/02_key_upload.sh"

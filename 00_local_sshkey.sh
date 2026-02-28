#!/bin/bash
# Phase 0 — Run locally (on your client machine)
# Generates an ED25519 SSH key pair (if none exists) and copies the
# public key to a remote server so you can log in without a password.
# Reads SETUP_HOST and SETUP_SSH_KEY from .env if present.
#
# Usage:
#   bash 00_local_sshkey.sh                          # uses SETUP_HOST from .env or prompts
#   bash 00_local_sshkey.sh mike@5.199.130.154
#   bash 00_local_sshkey.sh mike@5.199.130.154 ~/.ssh/id_myserver
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR}/.env" ] && set -o allexport && source "${SCRIPT_DIR}/.env" && set +o allexport

REMOTE="${1:-${SETUP_HOST:-}}"
KEY_PATH="${2:-${SETUP_SSH_KEY:-${HOME}/.ssh/id_ed25519}}"

# --- Prompt for host if not provided ---
if [ -z "${REMOTE}" ]; then
  read -rp "Remote host (user@host): " REMOTE
fi

# --- Generate key pair if it doesn't exist ---
if [ ! -f "${KEY_PATH}" ]; then
  echo "Generating ED25519 key pair at ${KEY_PATH}..."
  ssh-keygen -t ed25519 -f "${KEY_PATH}" -C "${USER}@$(hostname)"
else
  echo "Key already exists at ${KEY_PATH}, skipping keygen."
fi

# --- Copy public key to remote ---
echo "Copying public key to ${REMOTE}..."
ssh-copy-id -i "${KEY_PATH}.pub" "${REMOTE}"

echo ""
echo "Done! Test with: ssh ${REMOTE}"
echo ""
echo "Next on the server: sudo bash 00_server_sshd.sh"
echo "  (disables password auth once key login is confirmed working)"

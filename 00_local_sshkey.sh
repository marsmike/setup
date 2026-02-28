#!/bin/bash
# Phase 0 — Run locally (on your client machine)
# Generates an ED25519 SSH key pair (if none exists) and copies the
# public key to a remote server so you can log in without a password.
#
# Usage:
#   bash 00_local_sshkey.sh                          # prompts for host
#   bash 00_local_sshkey.sh mike@5.199.130.154
#   bash 00_local_sshkey.sh mike@5.199.130.154 ~/.ssh/id_myserver
set -euo pipefail

REMOTE="${1:-}"
KEY_PATH="${2:-${HOME}/.ssh/id_ed25519}"

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
echo "Done! Test with: ssh -i ${KEY_PATH} ${REMOTE}"
echo ""
echo "Next on the server: sudo bash 00_server_sshd.sh"
echo "  (disables password auth once key login is confirmed working)"

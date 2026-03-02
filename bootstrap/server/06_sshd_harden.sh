#!/bin/bash
# bootstrap/server/06_sshd_harden.sh
# Hardens sshd on the remote host: key-based auth only, no root login, no passwords.
# Invoked LOCALLY — SSHes into the server to run the commands.
#
# IMPORTANT: Run 03_key_test.sh first to confirm key auth works before calling this.
# Disabling password auth without a working key will lock you out.
#
# Reads SETUP_USER, SETUP_HOST, SSH_USER from repo root .env.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[ -f "${REPO_ROOT}/.env" ] && set -o allexport && source "${REPO_ROOT}/.env" && set +o allexport

SETUP_USER="${SETUP_USER:-}"
SETUP_HOST="${SETUP_HOST:-}"
SSH_USER="${SSH_USER:-${SETUP_USER}}"

if [ -z "${SETUP_USER}" ]; then
  echo "ERROR: SETUP_USER is not set. Add it to .env." >&2
  exit 1
fi
if [ -z "${SETUP_HOST}" ]; then
  echo "ERROR: SETUP_HOST is not set. Add it to .env." >&2
  exit 1
fi

HOST_ONLY="${SETUP_HOST#*@}"
SUDO_CMD="$( [ "${SSH_USER}" = "root" ] && echo "" || echo "sudo" )"

echo "This will disable password authentication on ${HOST_ONLY}."
echo "Ensure key auth is working first: bash bootstrap/local/03_key_test.sh"
echo ""
read -rp "Confirm key login works before disabling password auth? [y/N] " ans
[[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }

echo ""
echo "Hardening sshd on ${HOST_ONLY}..."

ssh "${SSH_USER}@${HOST_ONLY}" ${SUDO_CMD:+"${SUDO_CMD}"} bash -s <<'REMOTE'
set -euo pipefail
sed -i 's/.*PubkeyAuthentication.*/PubkeyAuthentication yes/'   /etc/ssh/sshd_config
sed -i 's/.*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/.*PermitRootLogin.*/PermitRootLogin no/'              /etc/ssh/sshd_config
sed -i 's/.*AuthorizedKeysFile.*/AuthorizedKeysFile .ssh\/authorized_keys/' /etc/ssh/sshd_config
systemctl restart sshd
echo "sshd hardened: key-only auth, no root login, no passwords."
REMOTE

echo ""
echo "Done. Bootstrap complete."
echo "  Connect: ssh ${SETUP_USER}@${HOST_ONLY}"

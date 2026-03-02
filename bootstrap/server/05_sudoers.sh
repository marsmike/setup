#!/bin/bash
# bootstrap/server/05_sudoers.sh
# Grants passwordless sudo to SETUP_USER on the remote host.
# Invoked LOCALLY — SSHes into the server to run the commands.
#
# Reads SETUP_USER, SETUP_HOST, SSH_USER from repo root .env.
#
# For a fresh server (connecting as root):
#   SSH_USER=root bash bootstrap/server/05_sudoers.sh
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

echo "Granting passwordless sudo to '${SETUP_USER}' on ${HOST_ONLY}..."

ssh "${SSH_USER}@${HOST_ONLY}" ${SUDO_CMD:+"${SUDO_CMD}"} bash -s <<REMOTE
set -euo pipefail
SUDOERS_FILE="/etc/sudoers.d/${SETUP_USER}-nopasswd"
echo "${SETUP_USER} ALL=(ALL) NOPASSWD: ALL" > "\${SUDOERS_FILE}"
chmod 440 "\${SUDOERS_FILE}"
visudo -c -f "\${SUDOERS_FILE}"
echo "Passwordless sudo enabled for '${SETUP_USER}' (\${SUDOERS_FILE})."
REMOTE

echo ""
echo "Done. Verify key auth, then: bash bootstrap/server/06_sshd_harden.sh"

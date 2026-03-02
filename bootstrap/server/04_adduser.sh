#!/bin/bash
# bootstrap/server/04_adduser.sh
# Creates SETUP_USER on the remote host and adds them to sudo + docker groups.
# Invoked LOCALLY — SSHes into the server to run the commands.
#
# Reads SETUP_USER, SETUP_HOST, SSH_USER from repo root .env.
#
# For a fresh server (SETUP_USER doesn't exist yet):
#   SSH_USER=root bash bootstrap/server/04_adduser.sh
#
# After bootstrap, default SSH_USER=$SETUP_USER works:
#   bash bootstrap/server/04_adduser.sh
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

# Strip user@ prefix from SETUP_HOST if present
HOST_ONLY="${SETUP_HOST#*@}"

if [ "${SSH_USER}" != "root" ]; then
  echo "WARNING: SSH_USER=${SSH_USER} (not root)."
  echo "  If ${SETUP_USER} doesn't exist yet on ${HOST_ONLY}, this will fail."
  echo "  For a fresh server, run: SSH_USER=root bash $0"
  echo ""
fi

SUDO_CMD="$( [ "${SSH_USER}" = "root" ] && echo "" || echo "sudo" )"

echo "Connecting as ${SSH_USER}@${HOST_ONLY} to create user '${SETUP_USER}'..."

ssh "${SSH_USER}@${HOST_ONLY}" ${SUDO_CMD:+"${SUDO_CMD}"} bash -s <<REMOTE
set -euo pipefail
if id "${SETUP_USER}" &>/dev/null; then
  echo "User '${SETUP_USER}' already exists, skipping adduser."
else
  adduser --disabled-password --gecos "" "${SETUP_USER}"
  echo "User '${SETUP_USER}' created."
fi
usermod -aG sudo "${SETUP_USER}"
getent group docker &>/dev/null && usermod -aG docker "${SETUP_USER}" || true
echo "Groups updated for '${SETUP_USER}'."
REMOTE

echo ""
echo "Done. Next: bash bootstrap/server/05_sudoers.sh"

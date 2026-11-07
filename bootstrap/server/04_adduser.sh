#!/bin/bash
# bootstrap/server/04_adduser.sh
# Creates SETUP_USER on the remote host, adds them to the sudo and docker
# groups, and installs this machine's public key for them.
# Invoked LOCALLY — SSHes into the server to run the commands.
#
# For a fresh server (SETUP_USER doesn't exist yet):
#   SSH_USER=root bash bootstrap/server/04_adduser.sh
set -euo pipefail

# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
load_setup_env
require_setup_target

if [ ! -f "${KEY_PATH}.pub" ]; then
  echo "ERROR: Public key not found at ${KEY_PATH}.pub" >&2
  echo "Run: bash bootstrap/local/01_keygen.sh" >&2
  exit 1
fi
PUBLIC_KEY="$(cat "${KEY_PATH}.pub")"

echo "Connecting as ${SSH_USER}@${HOST_ONLY} to set up user '${SETUP_USER}'..."

run_remote_root "TARGET_USER=${SETUP_USER}" "PUBLIC_KEY=${PUBLIC_KEY}" <<'REMOTE'
set -euo pipefail
if id "${TARGET_USER}" &>/dev/null; then
  echo "User '${TARGET_USER}' already exists, skipping creation."
else
  useradd -m -s /bin/bash -U "${TARGET_USER}"
  # No usable password, but not locked: key login still works.
  usermod -p '*' "${TARGET_USER}"
  echo "User '${TARGET_USER}' created."
fi
usermod -aG sudo "${TARGET_USER}"
if getent group docker &>/dev/null; then
  usermod -aG docker "${TARGET_USER}"
fi

TARGET_GROUP="$(id -gn "${TARGET_USER}")"
TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
AUTHORIZED_KEYS="${TARGET_HOME}/.ssh/authorized_keys"
install -d -m 700 -o "${TARGET_USER}" -g "${TARGET_GROUP}" "${TARGET_HOME}/.ssh"
touch "${AUTHORIZED_KEYS}"
if ! grep -qxF "${PUBLIC_KEY}" "${AUTHORIZED_KEYS}"; then
  printf '%s\n' "${PUBLIC_KEY}" >> "${AUTHORIZED_KEYS}"
fi
chown "${TARGET_USER}:${TARGET_GROUP}" "${AUTHORIZED_KEYS}"
chmod 600 "${AUTHORIZED_KEYS}"
echo "Groups and SSH key updated for '${TARGET_USER}'."
REMOTE

echo ""
echo "Done. Next: SSH_USER=root bash bootstrap/server/05_sudoers.sh"

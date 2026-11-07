#!/bin/bash
# bootstrap/server/05_sudoers.sh
# Grants passwordless sudo to SETUP_USER on the remote host. The rule is
# validated before it is installed, so a broken file can never land.
# Invoked LOCALLY — SSHes into the server to run the commands.
#
# For a fresh server (connecting as root):
#   SSH_USER=root bash bootstrap/server/05_sudoers.sh
set -euo pipefail

# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
load_setup_env
require_setup_target

echo "Granting passwordless sudo to '${SETUP_USER}' on ${HOST_ONLY}..."

run_remote_root "TARGET_USER=${SETUP_USER}" <<'REMOTE'
set -euo pipefail
SUDOERS_FILE="/etc/sudoers.d/${TARGET_USER}-nopasswd"
CANDIDATE="$(mktemp)"
trap 'rm -f "${CANDIDATE}"' EXIT
echo "${TARGET_USER} ALL=(ALL) NOPASSWD: ALL" > "${CANDIDATE}"
visudo -c -f "${CANDIDATE}"
install -m 440 -o root -g root "${CANDIDATE}" "${SUDOERS_FILE}"
echo "Passwordless sudo enabled for '${TARGET_USER}' (${SUDOERS_FILE})."
REMOTE

echo ""
echo "Done. Next: bash bootstrap/local/03_key_test.sh, then bootstrap/server/06_sshd_harden.sh"

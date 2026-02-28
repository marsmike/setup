#!/bin/bash
# Phase 0 — Server only (run as root)
# Grants passwordless sudo to the specified user.
# Reads SETUP_USER from .env if present.
#
# Usage:
#   sudo bash 00_server_sudoers.sh          # uses SETUP_USER from .env
#   sudo bash 00_server_sudoers.sh alice    # explicit override
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR}/.env" ] && set -o allexport && source "${SCRIPT_DIR}/.env" && set +o allexport

TARGET_USER="${1:-${SETUP_USER:-}}"
if [ -z "${TARGET_USER}" ]; then
  echo "ERROR: SETUP_USER is not set. Pass a username or add it to .env." >&2
  exit 1
fi
SUDOERS_FILE="/etc/sudoers.d/${TARGET_USER}-nopasswd"

echo "${TARGET_USER} ALL=(ALL) NOPASSWD: ALL" > "${SUDOERS_FILE}"
chmod 440 "${SUDOERS_FILE}"

# Validate — visudo will error and we'll abort before a broken sudoers lands
visudo -c -f "${SUDOERS_FILE}"

echo "Passwordless sudo enabled for ${TARGET_USER} (${SUDOERS_FILE})"

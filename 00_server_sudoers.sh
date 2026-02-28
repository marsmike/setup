#!/bin/bash
# Phase 0 — Server only (run as root)
# Grants passwordless sudo to the specified user (default: mike).
#
# Usage:
#   sudo bash 00_server_sudoers.sh          # defaults to mike
#   sudo bash 00_server_sudoers.sh alice    # specify user
set -euo pipefail

TARGET_USER="${1:-mike}"
SUDOERS_FILE="/etc/sudoers.d/${TARGET_USER}-nopasswd"

echo "${TARGET_USER} ALL=(ALL) NOPASSWD: ALL" > "${SUDOERS_FILE}"
chmod 440 "${SUDOERS_FILE}"

# Validate — visudo will error and we'll abort before a broken sudoers lands
visudo -c -f "${SUDOERS_FILE}"

echo "Passwordless sudo enabled for ${TARGET_USER} (${SUDOERS_FILE})"

#!/bin/bash
# Phase 0 — Server only (run as root)
# Creates the user and grants sudo + docker access.
# Reads SETUP_USER from .env if present (default: mike).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR}/.env" ] && set -o allexport && source "${SCRIPT_DIR}/.env" && set +o allexport

TARGET_USER="${SETUP_USER:-mike}"

adduser --disabled-password --gecos "" "${TARGET_USER}"
usermod -aG sudo "${TARGET_USER}"
usermod -aG docker "${TARGET_USER}"

echo "User '${TARGET_USER}' created with sudo + docker access."

#!/bin/bash
# Phase 0 — Server only (run as root)
# Creates the user and grants sudo + docker access.
# Reads SETUP_USER from .env (required).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR}/.env" ] && set -o allexport && source "${SCRIPT_DIR}/.env" && set +o allexport

TARGET_USER="${SETUP_USER:-}"
if [ -z "${TARGET_USER}" ]; then
  echo "ERROR: SETUP_USER is not set. Add it to .env (see .env.example)." >&2
  exit 1
fi

adduser --disabled-password --gecos "" "${TARGET_USER}"
usermod -aG sudo "${TARGET_USER}"
usermod -aG docker "${TARGET_USER}"

echo "User '${TARGET_USER}' created with sudo + docker access."

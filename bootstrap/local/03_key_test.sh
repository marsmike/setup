#!/bin/bash
# bootstrap/local/03_key_test.sh
# Verifies key-based SSH auth to SETUP_HOST.
# Prints the authorized key fingerprint on the remote host and pass/fail result.
# Reads SETUP_USER, SETUP_HOST, SETUP_SSH_KEY from repo root .env.
#
# Usage:
#   bash bootstrap/local/03_key_test.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[ -f "${REPO_ROOT}/.env" ] && set -o allexport && source "${REPO_ROOT}/.env" && set +o allexport

SETUP_HOST="${SETUP_HOST:-}"
SETUP_USER="${SETUP_USER:-}"
KEY_PATH="${SETUP_SSH_KEY:-${HOME}/.ssh/id_ed25519}"

if [ -z "${SETUP_HOST}" ]; then
  echo "ERROR: SETUP_HOST is not set. Add it to .env or export it." >&2
  exit 1
fi

# Extract host (strip user@ prefix if present)
HOST_ONLY="${SETUP_HOST#*@}"
CONNECT_USER="${SETUP_USER:-${SETUP_HOST%%@*}}"
[ "${CONNECT_USER}" = "${HOST_ONLY}" ] && CONNECT_USER="${USER}"

echo "Testing key auth: ${CONNECT_USER}@${HOST_ONLY} (key: ${KEY_PATH})"
echo ""

# Print authorized key fingerprints from the remote host
ssh \
  -o PasswordAuthentication=no \
  -o BatchMode=yes \
  -i "${KEY_PATH}" \
  "${CONNECT_USER}@${HOST_ONLY}" \
  "ssh-keygen -lf ~/.ssh/authorized_keys 2>/dev/null || true; exit 0" \
  && AUTH_OK=true || AUTH_OK=false

echo ""
if $AUTH_OK; then
  echo "✓ Key authentication works"
else
  echo "✗ Key authentication failed" >&2
  echo "  Check that 02_key_upload.sh completed successfully." >&2
  exit 1
fi

#!/bin/bash
# bootstrap/local/03_key_test.sh
# Verifies key-based SSH auth and prints the authorized key fingerprints.
# Tests SETUP_USER by default. SSH_USER overrides the account.
#
# Usage:
#   bash bootstrap/local/03_key_test.sh
#   SSH_USER=root bash bootstrap/local/03_key_test.sh
set -euo pipefail

# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
load_setup_env
require_setup_target

echo "Testing key auth: ${SSH_USER}@${HOST_ONLY} (key: ${KEY_PATH})"
echo ""

if setup_ssh -o PasswordAuthentication=no -o BatchMode=yes "${SSH_USER}@${HOST_ONLY}" \
  'ssh-keygen -lf ~/.ssh/authorized_keys'; then
  echo ""
  echo "✓ Key authentication works"
else
  echo ""
  echo "✗ Key authentication failed" >&2
  echo "  Check that 02_key_upload.sh or 04_adduser.sh completed successfully." >&2
  exit 1
fi

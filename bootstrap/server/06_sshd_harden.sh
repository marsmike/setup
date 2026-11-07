#!/bin/bash
# bootstrap/server/06_sshd_harden.sh
# Hardens sshd on the remote host: key-only auth, no root login, SETUP_USER only.
# Invoked LOCALLY — SSHes into the server as SETUP_USER to run the commands.
#
# The settings go in a drop-in that loads before every other file, so provider
# files such as 50-cloud-init.conf cannot override them. A timer removes the
# drop-in after 5 minutes unless a new login proves the change is safe.
#
# Usage:
#   bash bootstrap/server/06_sshd_harden.sh
set -euo pipefail

# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
load_setup_env
require_setup_target

# Root may be locked out by this script, so always work as SETUP_USER.
SSH_USER="${SETUP_USER}"
require_user_access

echo "Hardening sshd on ${HOST_ONLY}..."

run_remote_root "TARGET_USER=${SETUP_USER}" <<'REMOTE'
set -euo pipefail
DROPIN=/etc/ssh/sshd_config.d/00-hardening.conf
ROLLBACK_UNIT=setup-sshd-rollback

if ! grep -qiE '^Include /etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config; then
  echo "ERROR: /etc/ssh/sshd_config does not include sshd_config.d; nothing changed." >&2
  exit 1
fi

# The service is 'ssh' on Debian/Ubuntu and 'sshd' elsewhere.
SERVICE=sshd
systemctl cat ssh.service &>/dev/null && SERVICE=ssh

# Socket-activated sshd may not have created this yet, and sshd -t needs it.
mkdir -p /run/sshd

systemctl stop "${ROLLBACK_UNIT}.timer" 2>/dev/null || true
systemd-run --quiet --unit="${ROLLBACK_UNIT}" --on-active=300 \
  /bin/sh -c "rm -f ${DROPIN}; systemctl restart ${SERVICE}"

cat > "${DROPIN}" <<EOF
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AllowUsers ${TARGET_USER}
EOF
chmod 644 "${DROPIN}"

if ! sshd -t; then
  rm -f "${DROPIN}"
  systemctl stop "${ROLLBACK_UNIT}.timer" || true
  echo "ERROR: sshd rejected the configuration; drop-in removed." >&2
  exit 1
fi
systemctl restart "${SERVICE}"
echo "sshd restarted with ${DROPIN}; rollback armed for 5 minutes."
REMOTE

echo ""
echo "Verifying with a new login..."
EFFECTIVE="$(setup_ssh -o BatchMode=yes "${SETUP_USER}@${HOST_ONLY}" 'sudo -n sshd -T')" || {
  echo "ERROR: new login failed. Keep any open session; the change reverts within 5 minutes." >&2
  exit 1
}

for expected in \
  "permitrootlogin no" \
  "passwordauthentication no" \
  "kbdinteractiveauthentication no" \
  "pubkeyauthentication yes" \
  "allowusers ${SETUP_USER}"; do
  if ! grep -qix "${expected}" <<<"${EFFECTIVE}"; then
    echo "ERROR: effective sshd setting is not '${expected}'. The change reverts within 5 minutes." >&2
    exit 1
  fi
  echo "  ok: ${expected}"
done

setup_ssh -o BatchMode=yes "${SETUP_USER}@${HOST_ONLY}" \
  'sudo -n systemctl stop setup-sshd-rollback.timer'
echo "Rollback cancelled."

echo ""
echo "Done. Connect with: ssh ${SETUP_USER}@${HOST_ONLY}"
echo "Next: bash bootstrap/server/07_baseline.sh"

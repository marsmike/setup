#!/bin/bash
# bootstrap/server/07_baseline.sh
# Applies the server security baseline on Debian/Ubuntu: all pending updates,
# automatic security updates, a default-deny ufw firewall, and fail2ban for SSH.
# Invoked LOCALLY — SSHes into the server as SETUP_USER to run the commands.
#
# A timer disables the firewall after 5 minutes unless a new login proves it
# did not block SSH. Safe to re-run.
#
# Docker note: ports published by containers bypass ufw. Bind private services
# to localhost, for example 127.0.0.1:8080:8080.
#
# Usage:
#   bash bootstrap/server/07_baseline.sh
#   FAIL2BAN_IGNOREIP="203.0.113.7 2001:db8::1" bash bootstrap/server/07_baseline.sh
set -euo pipefail

# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
load_setup_env
require_setup_target

SSH_USER="${SETUP_USER}"
require_user_access

IGNOREIP="${FAIL2BAN_IGNOREIP:-}"
if ! [[ "${IGNOREIP}" =~ ^[0-9a-fA-F:./\ ]*$ ]]; then
  echo "ERROR: FAIL2BAN_IGNOREIP may only contain IP addresses and CIDR ranges." >&2
  exit 1
fi

echo "Applying security baseline on ${HOST_ONLY}..."

run_remote_root "IGNOREIP=${IGNOREIP}" <<'REMOTE'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
ROLLBACK_UNIT=setup-ufw-rollback
APT_OPTIONS=(-y -o DPkg::Lock::Timeout=300
  -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

echo "--- updates"
apt-get -o DPkg::Lock::Timeout=300 update
apt-get "${APT_OPTIONS[@]}" full-upgrade
apt-get "${APT_OPTIONS[@]}" install ufw fail2ban python3-systemd unattended-upgrades

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
systemctl enable --now unattended-upgrades

echo "--- fail2ban"
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 ${IGNOREIP}

[sshd]
enabled = true
backend = systemd
bantime = 1h
findtime = 10m
maxretry = 5
EOF
systemctl enable fail2ban
systemctl restart fail2ban

echo "--- firewall"
mkdir -p /run/sshd
# Capture full output first: a reader that exits early would make the writer
# die of SIGPIPE, which pipefail and set -e treat as a failure.
SSHD_CONFIG="$(sshd -T)"
SSH_PORT="$(awk '$1 == "port" { print $2; exit }' <<<"${SSHD_CONFIG}")"
if [ -z "${SSH_PORT}" ]; then
  echo "ERROR: could not determine the SSH port; firewall left unchanged." >&2
  exit 1
fi
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp"
UFW_STATUS="$(ufw status)"
if [[ "${UFW_STATUS}" != *"Status: active"* ]]; then
  systemctl stop "${ROLLBACK_UNIT}.timer" 2>/dev/null || true
  systemd-run --quiet --unit="${ROLLBACK_UNIT}" --on-active=300 /usr/sbin/ufw --force disable
  ufw --force enable
  echo "Firewall enabled; rollback armed for 5 minutes."
fi
REMOTE

echo ""
echo "Verifying with a new login..."
if ! setup_ssh -o BatchMode=yes "${SETUP_USER}@${HOST_ONLY}" 'sudo -n true'; then
  echo "ERROR: new login failed. A firewall enabled by this run turns off within 5 minutes." >&2
  exit 1
fi

setup_ssh -o BatchMode=yes "${SETUP_USER}@${HOST_ONLY}" 'sudo -n bash -s' <<'REMOTE'
set -euo pipefail
systemctl stop setup-ufw-rollback.timer 2>/dev/null || true
ufw status verbose
for attempt in 1 2 3 4 5; do
  fail2ban-client status sshd && break
  [ "${attempt}" -lt 5 ] || { echo "ERROR: fail2ban sshd jail is not running." >&2; exit 1; }
  sleep 2
done
echo "unattended-upgrades: $(systemctl is-active unattended-upgrades)"
if [ -f /var/run/reboot-required ]; then
  echo "NOTE: a reboot is required to finish applying updates."
fi
REMOTE

echo ""
echo "Done. Next, on the server: bash ubuntu/01_minimal.sh or bash ubuntu/01_basics.sh --server"

#!/bin/bash
# Bootstrap a fresh Linux host: create user, upload SSH key, harden SSH.
# Runs from your LOCAL machine (Mac, Linux, MobaXterm) — not on the host.
#
# The host must have root SSH access (password) to start.
# After this script, only key-based SSH as SETUP_USER is allowed.
#
# Usage:
#   bash linux/00_bootstrap.sh <HOST_IP>
#   bash linux/00_bootstrap.sh <HOST_IP> --root-pass 'mypassword'
#
# Secrets sourced from proxmox/.env (or repo root .env):
#   SETUP_USER, SSH_PUBLIC_KEY, PROXMOX_PASS (used as root password if --root-pass not given)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

HOST_IP="${1:-}"
if [ -z "$HOST_IP" ]; then
  echo "Usage: $0 <HOST_IP> [--root-pass 'password']" >&2
  exit 1
fi

# Parse optional --root-pass flag
ROOT_PASS_OVERRIDE=""
shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root-pass) ROOT_PASS_OVERRIDE="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# Load secrets — proxmox/.env first, fall back to repo root .env
for ENV_FILE in "${REPO_ROOT}/proxmox/.env" "${REPO_ROOT}/.env" "${SCRIPT_DIR}/.env"; do
  if [ -f "$ENV_FILE" ]; then
    set -o allexport
    source "$ENV_FILE"
    set +o allexport
    break
  fi
done

SETUP_USER="${SETUP_USER:-mike}"
ROOT_PASS="${ROOT_PASS_OVERRIDE:-${PROXMOX_PASS:-}}"

if [ -z "${SSH_PUBLIC_KEY:-}" ]; then
  echo "ERROR: SSH_PUBLIC_KEY is not set. Add it to proxmox/.env" >&2
  exit 1
fi

# Build SSH prefix
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
if [ -n "$ROOT_PASS" ] && command -v sshpass &>/dev/null; then
  SSH_AS_ROOT="sshpass -p ${ROOT_PASS} ssh $SSH_OPTS root@${HOST_IP}"
elif [ -n "$ROOT_PASS" ]; then
  echo "WARNING: password provided but sshpass is not installed." >&2
  echo "  Mac: brew install sshpass | Linux: apt install sshpass" >&2
  echo "Falling back to interactive password prompt." >&2
  SSH_AS_ROOT="ssh $SSH_OPTS root@${HOST_IP}"
else
  SSH_AS_ROOT="ssh $SSH_OPTS root@${HOST_IP}"
fi

echo "========================================"
echo "  Bootstrapping: $HOST_IP"
echo "  User to create: $SETUP_USER"
echo "========================================"

# Step 1: Create user
echo "[1/4] Creating user '$SETUP_USER'..."
$SSH_AS_ROOT "
  id $SETUP_USER 2>/dev/null && echo 'User already exists, skipping.' || \
  adduser --disabled-password --gecos '' $SETUP_USER
  usermod -aG sudo $SETUP_USER
"

# Step 2: Passwordless sudo
echo "[2/4] Configuring passwordless sudo..."
$SSH_AS_ROOT "
  echo '${SETUP_USER} ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/${SETUP_USER}-nopasswd
  chmod 440 /etc/sudoers.d/${SETUP_USER}-nopasswd
  visudo -c -f /etc/sudoers.d/${SETUP_USER}-nopasswd
"

# Step 3: Upload SSH key
echo "[3/4] Uploading SSH key..."
$SSH_AS_ROOT "
  mkdir -p /home/${SETUP_USER}/.ssh
  echo '${SSH_PUBLIC_KEY}' >> /home/${SETUP_USER}/.ssh/authorized_keys
  sort -u /home/${SETUP_USER}/.ssh/authorized_keys -o /home/${SETUP_USER}/.ssh/authorized_keys
  chmod 700 /home/${SETUP_USER}/.ssh
  chmod 600 /home/${SETUP_USER}/.ssh/authorized_keys
  chown -R ${SETUP_USER}:${SETUP_USER} /home/${SETUP_USER}/.ssh
"

# Step 4: Harden SSH
echo "[4/4] Hardening sshd (key-only, no root login, no passwords)..."
$SSH_AS_ROOT "
  sed -i 's/.*PubkeyAuthentication.*/PubkeyAuthentication yes/'   /etc/ssh/sshd_config
  sed -i 's/.*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/.*PermitRootLogin.*/PermitRootLogin no/'              /etc/ssh/sshd_config
  systemctl restart sshd
"

echo ""
echo "========================================"
echo "  Bootstrap complete!"
echo "========================================"
echo "  Connect: ssh ${SETUP_USER}@${HOST_IP}"
echo "  Root login and password auth are now disabled."

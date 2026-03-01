#!/bin/bash
# Provision a Proxmox VM from a YAML definition.
# Reads proxmox/.env for secrets.
#
# Usage:
#   ./proxmox/provision.sh proxmox/vms/ragflow.yaml
#   ./proxmox/provision.sh proxmox/vms/ragflow.yaml --dry-run
#
# Requirements on the running machine:
#   - bash, ssh, scp
#   - yq  (mikefarah): https://github.com/mikefarah/yq
#   - envsubst (gettext): brew install gettext / apt install gettext
#   - sshpass (if using password auth): brew install sshpass / apt install sshpass

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_YAML="${1:-}"
DRY_RUN="${2:-}"

# --- Validate input ---
if [ -z "$VM_YAML" ]; then
  echo "Usage: $0 <path/to/vms/vm.yaml> [--dry-run]" >&2
  exit 1
fi
if [ ! -f "$VM_YAML" ]; then
  echo "ERROR: VM file not found: $VM_YAML" >&2
  exit 1
fi

# --- Load secrets ---
ENV_FILE="${SCRIPT_DIR}/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: $ENV_FILE not found." >&2
  echo "Run: cp ${SCRIPT_DIR}/.env.example ${SCRIPT_DIR}/.env" >&2
  echo "Then fill in your secrets." >&2
  exit 1
fi
set -o allexport
source "$ENV_FILE"
set +o allexport

SETUP_USER="${SETUP_USER:-mike}"

# Validate required secrets
for var in SSH_PUBLIC_KEY USER_PASSWORD_HASH CHEZMOI_USER SETUP_USER; do
  if [ -z "${!var:-}" ]; then
    echo "ERROR: $var is not set in $ENV_FILE" >&2
    exit 1
  fi
done

# --- Parse VM YAML ---
VM_NAME=$(yq '.vm.name'  "$VM_YAML")
VM_ID=$(yq   '.vm.id'    "$VM_YAML")
NODE_NAME=$(yq '.vm.node' "$VM_YAML")
PROFILE=$(yq   '.profile' "$VM_YAML")
APP=$(yq '.app // ""' "$VM_YAML")

# Hardware: VM YAML overrides profile defaults
MEMORY=$(yq '.hardware.memory // ""' "$VM_YAML")
CORES=$(yq  '.hardware.cores  // ""' "$VM_YAML")
DISK=$(yq   '.hardware.disk   // ""' "$VM_YAML")

# Load profile defaults for any unset values
PROFILE_FILE="${SCRIPT_DIR}/profiles/${PROFILE}.yaml"
if [ ! -f "$PROFILE_FILE" ]; then
  echo "ERROR: Profile not found: $PROFILE_FILE" >&2
  exit 1
fi
[ -z "$MEMORY" ] && MEMORY=$(yq '.hardware.memory' "$PROFILE_FILE")
[ -z "$CORES"  ] && CORES=$(yq  '.hardware.cores'  "$PROFILE_FILE")
[ -z "$DISK"   ] && DISK=$(yq   '.hardware.disk'   "$PROFILE_FILE")

# Network — use nodes.yaml defaults if not specified in VM YAML
NODES_FILE="${SCRIPT_DIR}/nodes.yaml"
DEFAULT_GATEWAY=$(yq '.ip_pool.gateway'      "$NODES_FILE")
DEFAULT_NETMASK=$(yq '.ip_pool.netmask'      "$NODES_FILE")
DEFAULT_DNS=$(yq     '.ip_pool.dns'          "$NODES_FILE")
DEFAULT_DOMAIN=$(yq  '.ip_pool.searchdomain' "$NODES_FILE")

VM_IP=$(yq '.network.ip' "$VM_YAML")

# Validate required fields parsed from VM YAML
for field_name in VM_NAME VM_ID NODE_NAME PROFILE VM_IP; do
  val="${!field_name}"
  if [ -z "$val" ] || [ "$val" = "null" ]; then
    echo "ERROR: Required field missing or null in $VM_YAML: ${field_name,,} (got: '$val')" >&2
    exit 1
  fi
done

VM_GATEWAY=$(yq '.network.gateway // ""' "$VM_YAML")
VM_NETMASK=$(yq '.network.netmask // ""' "$VM_YAML")
VM_DNS=$(yq     '.network.dns     // ""' "$VM_YAML")
VM_SEARCHDOMAIN=$(yq '.network.searchdomain // ""' "$VM_YAML")

[ -z "$VM_GATEWAY" ]      && VM_GATEWAY="$DEFAULT_GATEWAY"
[ -z "$VM_NETMASK" ]      && VM_NETMASK="$DEFAULT_NETMASK"
[ -z "$VM_DNS" ]           && VM_DNS="$DEFAULT_DNS"
[ -z "$VM_SEARCHDOMAIN" ] && VM_SEARCHDOMAIN="$DEFAULT_DOMAIN"

# Resolve node IP and storage from nodes.yaml
NODE_IP=$(yq ".nodes[] | select(.name == \"${NODE_NAME}\") | .ip" "$NODES_FILE")
NODE_STORAGE=$(yq ".nodes[] | select(.name == \"${NODE_NAME}\") | .storage" "$NODES_FILE")

# Allow VM YAML to override storage
VM_STORAGE=$(yq '.hardware.storage // ""' "$VM_YAML")
[ -n "$VM_STORAGE" ] && NODE_STORAGE="$VM_STORAGE"

IMAGE_URL=$(yq '.vm.image_url // ""' "$VM_YAML")
CREATE_VM_FLAGS=()
[ -n "$IMAGE_URL" ] && CREATE_VM_FLAGS+=(--image-url "$IMAGE_URL")

if [ -z "$NODE_IP" ]; then
  echo "ERROR: Node '$NODE_NAME' not found in $NODES_FILE" >&2
  exit 1
fi

# --- Render cloud-init template ---
TPL_YAML_PATH=$(yq '.cloudinit.base_template // ""' "$VM_YAML")
[ -z "$TPL_YAML_PATH" ] && TPL_YAML_PATH=$(yq '.cloudinit.base_template // "cloudinit/base.yaml.tpl"' "$PROFILE_FILE")
TPL_FILE="${SCRIPT_DIR}/${TPL_YAML_PATH}"
if [ ! -f "$TPL_FILE" ]; then
  echo "ERROR: Cloud-init template not found: $TPL_FILE" >&2
  exit 1
fi
RENDERED_FILE="/tmp/${VM_NAME}-cloudinit.yaml"

export VM_NAME VM_SEARCHDOMAIN SSH_PUBLIC_KEY USER_PASSWORD_HASH CHEZMOI_USER SETUP_USER
# IMPORTANT: explicit variable list prevents envsubst from eating $HOME etc.
envsubst '${VM_NAME} ${VM_SEARCHDOMAIN} ${SSH_PUBLIC_KEY} ${USER_PASSWORD_HASH} ${CHEZMOI_USER} ${SETUP_USER}' \
  < "$TPL_FILE" > "$RENDERED_FILE"

# --- Summary ---
echo "========================================"
echo "  VM Provisioning Plan"
echo "========================================"
echo "  VM YAML:    $VM_YAML"
echo "  Name:       $VM_NAME (ID: $VM_ID)"
echo "  Node:       $NODE_NAME ($NODE_IP)"
echo "  Storage:    $NODE_STORAGE"
echo "  Profile:    $PROFILE"
echo "  Hardware:   ${MEMORY}MB RAM | ${CORES} cores | $DISK disk"
echo "  Network:    $VM_IP/$VM_NETMASK gw $VM_GATEWAY"
echo "========================================"

if [ "$DRY_RUN" = "--dry-run" ]; then
  echo ""
  echo "DRY RUN — no changes made. Rendered cloud-init:"
  echo "---"
  cat "$RENDERED_FILE"
  exit 0
fi

# --- SSH helper ---
# Try key-based auth first. Fall back to sshpass if PROXMOX_PASS is set.
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5"
if ssh $SSH_OPTS -o BatchMode=yes "${PROXMOX_USER:-root}@${NODE_IP}" exit 2>/dev/null; then
  SSH_PREFIX=()
elif [ -n "${PROXMOX_PASS:-}" ] && command -v sshpass &>/dev/null; then
  SSH_PREFIX=(sshpass -p "${PROXMOX_PASS}")
else
  echo "ERROR: Cannot authenticate to $NODE_IP." >&2
  echo "  Option 1: Set up SSH key auth (recommended)" >&2
  echo "  Option 2: Set PROXMOX_PASS in .env and install sshpass" >&2
  echo "            Mac: brew install sshpass" >&2
  echo "            Linux: apt install sshpass" >&2
  exit 1
fi

RUN_NODE()  { "${SSH_PREFIX[@]}" ssh  $SSH_OPTS "${PROXMOX_USER:-root}@${NODE_IP}" "$@"; }
COPY_NODE() { "${SSH_PREFIX[@]}" scp  $SSH_OPTS "$1" "${PROXMOX_USER:-root}@${NODE_IP}:$2"; }

# --- Upload cloud-init snippet ---
echo "Uploading cloud-init config to $NODE_NAME..."
RUN_NODE "mkdir -p /var/lib/vz/snippets"
COPY_NODE "$RENDERED_FILE" "/var/lib/vz/snippets/${VM_NAME}-cloudinit.yaml"

# --- Upload create_vm.sh ---
echo "Uploading create_vm.sh..."
COPY_NODE "${SCRIPT_DIR}/scripts/create_vm.sh" "/tmp/create_vm_${VM_NAME}.sh"
RUN_NODE "chmod +x /tmp/create_vm_${VM_NAME}.sh"

# --- Run creation ---
echo "Creating VM on $NODE_NAME..."
RUN_NODE "/tmp/create_vm_${VM_NAME}.sh \
  --vmid ${VM_ID} \
  --name ${VM_NAME} \
  --storage ${NODE_STORAGE} \
  --memory ${MEMORY} \
  --cores ${CORES} \
  --disk ${DISK} \
  --ip ${VM_IP} \
  --netmask ${VM_NETMASK} \
  --gateway ${VM_GATEWAY} \
  --dns ${VM_DNS} \
  --searchdomain ${VM_SEARCHDOMAIN} \
  --cloudinit /var/lib/vz/snippets/${VM_NAME}-cloudinit.yaml \
  ${CREATE_VM_FLAGS[*]:-}"

# Cleanup temp file on node
RUN_NODE "rm -f /tmp/create_vm_${VM_NAME}.sh" 2>/dev/null || true

# --- Run app post_provision steps if app is defined ---
if [ -n "$APP" ]; then
  APP_FILE="${SCRIPT_DIR}/apps/${APP}.yaml"
  if [ -f "$APP_FILE" ]; then
    POST_STEPS=$(yq '.post_provision[]' "$APP_FILE" 2>/dev/null || echo "")
    if [ -n "$POST_STEPS" ]; then
      echo "Waiting 3 min for cloud-init to complete before app setup..."
      sleep 180
      echo "Running post_provision steps for app: $APP"
      STEP_COUNT=$(yq '.post_provision | length' "$APP_FILE")
      for i in $(seq 0 $((STEP_COUNT - 1))); do
        STEP=$(yq ".post_provision[$i]" "$APP_FILE")
        echo "  Step $((i+1))/$STEP_COUNT: $STEP"
        "${SSH_PREFIX[@]}" ssh $SSH_OPTS "${SETUP_USER}@${VM_IP}" "$STEP" || \
          echo "  WARNING: step failed (app may need manual setup)"
      done
      echo "App post_provision complete."
    fi
  else
    echo "WARNING: app '$APP' defined but apps/${APP}.yaml not found — skipping post_provision"
  fi
fi

echo ""
echo "========================================"
echo "  Done! VM $VM_NAME is starting."
echo "========================================"
echo "  SSH (after ~3-5 min):  ssh ${SETUP_USER}@${VM_IP}"
echo "  Monitor:               ssh ${PROXMOX_USER:-root}@${NODE_IP} 'qm status ${VM_ID}'"
echo "  Cloud-init log:        ssh ${SETUP_USER}@${VM_IP} 'sudo tail -f /var/log/cloud-init-output.log'"

#!/bin/bash
# Non-interactive VM creation — runs on the Proxmox node.
# Uploaded and invoked by provision.sh via SSH.
#
# Usage: create_vm.sh --vmid 100 --name ragflow --ip 192.168.1.100 \
#          --netmask 24 --gateway 192.168.1.1 --dns 192.168.1.1 \
#          --searchdomain home --memory 8192 --cores 4 --disk 32G \
#          --storage nvme --cloudinit /var/lib/vz/snippets/ragflow-cloudinit.yaml \
#          [--image-url https://...]

set -euo pipefail

DEFAULT_IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMAGE_URL=""

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vmid)        VMID="$2";         shift 2 ;;
    --name)        VM_NAME="$2";      shift 2 ;;
    --storage)     STORAGE="$2";      shift 2 ;;
    --memory)      MEMORY="$2";       shift 2 ;;
    --cores)       CORES="$2";        shift 2 ;;
    --disk)        DISK="$2";         shift 2 ;;
    --ip)          VM_IP="$2";        shift 2 ;;
    --netmask)     VM_NETMASK="$2";   shift 2 ;;
    --gateway)     VM_GATEWAY="$2";   shift 2 ;;
    --dns)         VM_DNS="$2";       shift 2 ;;
    --searchdomain) VM_SEARCHDOMAIN="$2"; shift 2 ;;
    --cloudinit)   CLOUDINIT_FILE="$2"; shift 2 ;;
    --image-url)   IMAGE_URL="$2";    shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

[ -z "$IMAGE_URL" ] && IMAGE_URL="$DEFAULT_IMAGE_URL"
IMAGE_FILENAME="$(basename "$IMAGE_URL")"
IMAGE_FILE="/root/${IMAGE_FILENAME}"

# Validate required flags
for var in VMID VM_NAME STORAGE MEMORY CORES DISK VM_IP VM_NETMASK VM_GATEWAY VM_DNS VM_SEARCHDOMAIN CLOUDINIT_FILE; do
  [ -z "${!var:-}" ] && { echo "ERROR: --${var,,} is required" >&2; exit 1; }
done

echo "========================================"
echo "  Creating VM: $VM_NAME (ID: $VMID)"
echo "========================================"

# Download cloud image if not cached
if [ ! -f "$IMAGE_FILE" ]; then
  echo "Downloading base cloud image ($IMAGE_FILENAME)..."
  wget -q --show-progress "$IMAGE_URL" -O "$IMAGE_FILE"
fi

# Create a temporary copy for resize+import (preserves cached original size)
IMPORT_FILE="${IMAGE_FILE%.*}-${VMID}-import.img"
echo "Copying image for import (preserving cache)..."
cp "$IMAGE_FILE" "$IMPORT_FILE"
echo "Resizing copy to $DISK..."
qemu-img resize "$IMPORT_FILE" "$DISK"

# Destroy existing VM with same ID (idempotent)
echo "Removing existing VM $VMID if present..."
qm destroy "$VMID" 2>/dev/null || true

# Create VM
echo "Creating VM $VMID..."
qm create "$VMID" \
  --name "$VM_NAME" \
  --ostype l26 \
  --memory "$MEMORY" \
  --balloon 0 \
  --agent enabled=1,fstrim_cloned_disks=1 \
  --cpu host \
  --sockets 1 \
  --cores "$CORES" \
  --vga serial0 \
  --serial0 socket \
  --scsihw virtio-scsi-single \
  --net0 virtio,bridge=vmbr0,firewall=1

# Import disk
echo "Importing disk..."
qm set "$VMID" --scsi0 "${STORAGE}:0,import-from=${IMPORT_FILE},discard=on,ssd=1"

# Cloud-init drive
echo "Adding cloud-init drive..."
qm set "$VMID" --ide2 "${STORAGE}:cloudinit"

# Boot order
qm set "$VMID" --boot order=scsi0

# Apply cloud-init snippet
SNIPPET_NAME="$(basename "$CLOUDINIT_FILE")"
echo "Applying cloud-init: $SNIPPET_NAME"
qm set "$VMID" --cicustom "user=local:snippets/${SNIPPET_NAME}"

# Static network
echo "Configuring network: $VM_IP/$VM_NETMASK gw $VM_GATEWAY"
qm set "$VMID" --ipconfig0 "ip=${VM_IP}/${VM_NETMASK},gw=${VM_GATEWAY}"
qm set "$VMID" --nameserver "$VM_DNS"
qm set "$VMID" --searchdomain "$VM_SEARCHDOMAIN"

# Tags
qm set "$VMID" --tags "ubuntu-noble,docker,dev-env"

# Regenerate cloud-init ISO
echo "Generating cloud-init drive..."
qm cloudinit update "$VMID"

# Start VM
echo "Starting VM..."
qm start "$VMID"

# Clean up import copy
rm -f "$IMPORT_FILE"

echo ""
echo "========================================"
echo "  VM $VM_NAME ($VMID) started!"
echo "========================================"
echo "  IP:     $VM_IP"
echo "  SSH:    ssh mike@$VM_IP"
echo "  Wait ~3-5 min for cloud-init to complete."
echo "  Monitor: qm status $VMID"

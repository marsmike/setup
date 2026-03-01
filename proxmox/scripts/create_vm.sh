#!/bin/bash
# Non-interactive VM creation — runs on the Proxmox node.
# Uploaded and invoked by provision.sh via SSH.
#
# Usage: create_vm.sh --vmid 100 --name ragflow --ip 192.168.1.100 \
#          --netmask 24 --gateway 192.168.1.1 --dns 192.168.1.1 \
#          --searchdomain home --memory 8192 --cores 4 --disk 32G \
#          --storage nvme --cloudinit /var/lib/vz/snippets/ragflow-cloudinit.yaml \
#          [--image-url https://...] [--boot-iso]

set -euo pipefail

DEFAULT_IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMAGE_URL=""
BOOT_ISO=0

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
    --boot-iso)    BOOT_ISO=1;        shift 1 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

[ -z "$IMAGE_URL" ] && IMAGE_URL="$DEFAULT_IMAGE_URL"
IMAGE_FILENAME="$(basename "$IMAGE_URL")"
if [ "$BOOT_ISO" -eq 1 ]; then
  IMAGE_FILE="/var/lib/vz/template/iso/${IMAGE_FILENAME}"
else
  IMAGE_FILE="/root/${IMAGE_FILENAME}"
fi

# Validate required flags
for var in VMID VM_NAME STORAGE MEMORY CORES DISK VM_IP VM_NETMASK VM_GATEWAY VM_DNS VM_SEARCHDOMAIN CLOUDINIT_FILE; do
  [ -z "${!var:-}" ] && { echo "ERROR: --${var,,} is required" >&2; exit 1; }
done

echo "========================================"
echo "  Creating VM: $VM_NAME (ID: $VMID)"
echo "========================================"

# Download cloud image or ISO if not cached
if [ ! -f "$IMAGE_FILE" ] && [ ! -f "${IMAGE_FILE%.xz}" ]; then
  echo "Downloading image ($IMAGE_FILENAME)..."
  wget -q --show-progress "$IMAGE_URL" -O "$IMAGE_FILE"
fi

if [[ "$IMAGE_FILE" == *.xz ]]; then
  if [ -f "$IMAGE_FILE" ]; then
    echo "Extracting xz image..."
    unxz -f "$IMAGE_FILE"
  fi
  IMAGE_FILE="${IMAGE_FILE%.xz}"
  IMAGE_FILENAME="$(basename "$IMAGE_FILE")"
fi

# Destroy existing VM with same ID (idempotent)
echo "Removing existing VM $VMID if present..."
qm stop "$VMID" 2>/dev/null || true
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
  --vga vmware \
  --serial0 socket \
  --scsihw virtio-scsi-single \
  --net0 virtio,bridge=vmbr0,firewall=1

if [ "$BOOT_ISO" -eq 1 ]; then
  echo "Creating empty $DISK disk..."
  # Create an empty raw disk
  pvesm alloc "$STORAGE" "$VMID" "vm-${VMID}-disk-0.raw" "$DISK"
  qm set "$VMID" --scsi0 "${STORAGE}:${VMID}/vm-${VMID}-disk-0.raw,discard=on,ssd=1"
  
  echo "Mounting ISO as CD-ROM..."
  qm set "$VMID" --ide2 "local:iso/${IMAGE_FILENAME},media=cdrom"
  
  echo "Setting boot order to CD-ROM first..."
  qm set "$VMID" --boot order=ide2

else
  # Import disk
  IMPORT_FILE="${IMAGE_FILE%.*}-${VMID}-import.img"
  echo "Copying image for import (preserving cache)..."
  cp "$IMAGE_FILE" "$IMPORT_FILE"
  echo "Resizing copy to $DISK..."
  qemu-img resize "$IMPORT_FILE" "$DISK"

  echo "Importing disk..."
  qm set "$VMID" --scsi0 "${STORAGE}:0,import-from=${IMPORT_FILE},discard=on,ssd=1"

  # Boot order
  qm set "$VMID" --boot order=scsi0

  # Apply cloud-init or Ignition snippet
  SNIPPET_NAME="$(basename "$CLOUDINIT_FILE")"
  echo "Applying initialization configuration: $SNIPPET_NAME"
  if [[ "$SNIPPET_NAME" == *.ign ]]; then
    # Ignition for CoreOS/Flatcar
    qm set "$VMID" --args "-fw_cfg name=opt/com.coreos/config,file=/var/lib/vz/snippets/${SNIPPET_NAME}"
  else
    # Standard Cloud-Init
    echo "Adding cloud-init drive..."
    qm set "$VMID" --ide2 "${STORAGE}:cloudinit"
    qm set "$VMID" --cicustom "user=local:snippets/${SNIPPET_NAME}"

    echo "Configuring network: $VM_IP/$VM_NETMASK gw $VM_GATEWAY"
    qm set "$VMID" --ipconfig0 "ip=${VM_IP}/${VM_NETMASK},gw=${VM_GATEWAY}"
    qm set "$VMID" --nameserver "$VM_DNS"
    qm set "$VMID" --searchdomain "$VM_SEARCHDOMAIN"

    echo "Generating cloud-init drive..."
    qm cloudinit update "$VMID"
  fi
fi

# Tags
qm set "$VMID" --tags "ubuntu-noble,docker,dev-env"

# Start VM
echo "Starting VM..."
qm start "$VMID"

if [ "$BOOT_ISO" -eq 1 ]; then
  echo ""
  echo "========================================"
  echo "  VM $VM_NAME ($VMID) booted from ISO!"
  echo "========================================"
  echo "  Open the Proxmox web console to complete the GUI installation."
else
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
fi
#!/bin/bash
# Build the Ubuntu Noble cloud-init template (VM 8200) on this Proxmox node.
# Runs ON the node (uploaded by provision.sh or run manually via SSH).
#
# Usage: template.sh [<template-id>] [<storage>]
#   template.sh           # uses defaults: ID=8200, storage=nvme
#   template.sh 8200 nvme

set -euo pipefail

TEMPLATE_ID="${1:-8200}"
STORAGE="${2:-nvme}"
IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMAGE_FILE="/root/noble-server-cloudimg-amd64.img"

echo "Building Ubuntu Noble template (VM $TEMPLATE_ID) on storage: $STORAGE"

if [ ! -f "$IMAGE_FILE" ]; then
  echo "Downloading Ubuntu Noble cloud image..."
  wget -q --show-progress "$IMAGE_URL" -O "$IMAGE_FILE"
fi

echo "Resizing image to 32G..."
qemu-img resize "$IMAGE_FILE" 32G

echo "Removing existing template $TEMPLATE_ID if present..."
qm destroy "$TEMPLATE_ID" 2>/dev/null || true

echo "Creating template VM..."
qm create "$TEMPLATE_ID" \
  --name "ubuntu-24-04-cloud" \
  --ostype l26 \
  --memory 8192 \
  --balloon 0 \
  --agent enabled=1,fstrim_cloned_disks=1 \
  --cpu host \
  --sockets 1 \
  --cores 4 \
  --vga serial0 \
  --serial0 socket \
  --scsihw virtio-scsi-single \
  --net0 virtio,bridge=vmbr0,firewall=1

echo "Importing disk..."
qm set "$TEMPLATE_ID" --scsi0 "${STORAGE}:0,import-from=${IMAGE_FILE},discard=on,ssd=1"
qm set "$TEMPLATE_ID" --ide2 "${STORAGE}:cloudinit"
qm set "$TEMPLATE_ID" --boot order=scsi0
qm set "$TEMPLATE_ID" --tags "ubuntu-noble,cloudinit,template"
qm cloudinit update "$TEMPLATE_ID"

echo "Converting to template..."
qm template "$TEMPLATE_ID"

echo ""
echo "Template $TEMPLATE_ID ready on $STORAGE."
echo "Clone with: qm clone $TEMPLATE_ID <NEWID> --name <NAME> --full"

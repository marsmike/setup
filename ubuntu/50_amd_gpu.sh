#!/bin/bash
# AMD GPU setup — Vulkan drivers + amdgpu.gttsize=98304 kernel parameter
# Requires a reboot to take effect. Safe to re-run.
set -euo pipefail

# --- Vulkan drivers ---
sudo apt-get update -qq
sudo apt-get install -y \
  mesa-vulkan-drivers vulkan-tools \
  libvulkan1 libvulkan-dev

# --- Current GTT size (before change) ---
GTT_FILE=$(ls /sys/class/drm/card*/device/mem_info_gtt_total 2>/dev/null | head -1)
if [ -n "$GTT_FILE" ]; then
  GTT_BYTES=$(cat "$GTT_FILE")
  GTT_GB=$(( GTT_BYTES / 1024 / 1024 / 1024 ))
  echo "Current GTT size: ${GTT_GB} GB (${GTT_BYTES} bytes)"
else
  echo "WARNING: could not read GTT size — AMD GPU may not be detected yet"
fi

# --- Set amdgpu.gttsize in GRUB ---
GRUB_FILE=/etc/default/grub

if grep -q "amdgpu.gttsize" "$GRUB_FILE"; then
  echo "amdgpu.gttsize already present in GRUB:"
  grep "GRUB_CMDLINE_LINUX_DEFAULT" "$GRUB_FILE"
else
  # Append param inside the existing quotes
  sudo sed -i \
    's/^\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 amdgpu.gttsize=98304"/' \
    "$GRUB_FILE"
  sudo update-grub
  echo "amdgpu.gttsize=98304 added to GRUB_CMDLINE_LINUX_DEFAULT."
fi

# --- Vulkan sanity check (pre-reboot, may show limited info) ---
echo ""
echo "Vulkan device detection:"
vulkaninfo --summary 2>/dev/null \
  | grep -E "GPU id|deviceName|driverVersion" \
  || echo "(no Vulkan devices yet — expected before reboot on some systems)"

echo ""
echo "================================================================"
echo "REBOOT REQUIRED for amdgpu.gttsize to take effect."
echo ""
echo "After reboot, verify with:"
echo "  cat /sys/class/drm/card*/device/mem_info_gtt_total"
echo "  Expected: >= 103079215104 bytes (96 GB)"
echo ""
echo "Vulkan verify:"
echo "  vulkaninfo --summary | grep deviceName"
echo "================================================================"

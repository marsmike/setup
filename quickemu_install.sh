#!/bin/bash
# Utilities — Linux only
# Installs quickemu + quickget for running lightweight VMs locally.
# Requires Ubuntu/Debian with apt.
set -euo pipefail

echo "Installing quickemu dependencies..."
sudo apt-get update -qq
sudo apt-get install -y \
  qemu-system-x86 bash coreutils ovmf grep jq lsb-release \
  procps python3 genisoimage usbutils util-linux sed \
  spice-client-gtk libtss2-tcti-swtpm0 \
  wget xdg-user-dirs zsync unzip

echo "Adding quickemu PPA..."
grep -rq 'flexiondotorg/quickemu' /etc/apt/sources.list* 2>/dev/null \
  || sudo apt-add-repository -y ppa:flexiondotorg/quickemu
sudo apt-get update -qq
sudo apt-get install -y quickemu

echo ""
echo "quickemu $(quickemu --version 2>/dev/null || echo 'installed')."
echo "  Download a VM:  quickget ubuntu 24.04"
echo "  Start it:       quickemu --vm ubuntu-24.04.conf"
echo "  Test pipeline:  bash test_pipeline.sh"

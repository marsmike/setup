#!/bin/bash
# Phase 3 — Optional
# Installs restic backup tool (apt + self-update to latest).
set -euo pipefail

sudo apt update
sudo apt install -y restic
sudo restic self-update

echo "restic $(restic version) installed."

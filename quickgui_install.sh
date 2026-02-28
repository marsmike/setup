#!/bin/bash
# Utilities — Linux only
# Installs quickgui — a graphical front-end for quickemu.
# Optional: quickemu works fine without it.
set -euo pipefail

echo "Adding quickgui PPA..."
sudo add-apt-repository -y ppa:yannick-mauray/quickgui
sudo apt-get update -qq
sudo apt-get install -y quickgui

echo ""
echo "quickgui installed. Launch from your application menu or run: quickgui"

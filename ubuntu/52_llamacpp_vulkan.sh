#!/bin/bash
# Build llama.cpp from source with Vulkan GPU support.
# Binaries installed to ~/.local/bin. Idempotent — rebuilds if source changed.
set -euo pipefail

LLAMA_DIR="$HOME/llama.cpp"

# --- Build dependencies ---
sudo apt-get install -y \
  cmake ninja-build \
  libvulkan-dev glslc \
  build-essential pkg-config

# --- Clone or update ---
if [ -d "$LLAMA_DIR/.git" ]; then
  echo "Updating llama.cpp..."
  git -C "$LLAMA_DIR" pull --ff-only
else
  echo "Cloning llama.cpp..."
  git clone --depth=1 https://github.com/ggerganov/llama.cpp "$LLAMA_DIR"
fi

# --- Build ---
cd "$LLAMA_DIR"
cmake -B build \
  -DGGML_VULKAN=1 \
  -DCMAKE_BUILD_TYPE=Release \
  -G Ninja

cmake --build build --target llama-server llama-cli -j"$(nproc)"

# --- Install ---
mkdir -p ~/.local/bin
install -m 755 build/bin/llama-server ~/.local/bin/llama-server
install -m 755 build/bin/llama-cli    ~/.local/bin/llama-cli

echo "Installed:"
ls -lh ~/.local/bin/llama-server ~/.local/bin/llama-cli

# --- UFW: LAN access ---
if ! sudo ufw status | grep -q "8080"; then
  sudo ufw allow from 192.168.1.0/24 to any port 8080 comment 'llama.cpp LAN'
  echo "UFW rule added for :8080"
else
  echo "UFW rule for :8080 already exists"
fi

# --- List Vulkan devices ---
echo ""
echo "Vulkan devices visible to llama.cpp:"
AMD_VULKAN_ICD=RADV ~/.local/bin/llama-server --list-devices 2>&1 | head -20 || true

echo ""
echo "================================================================"
echo "llama.cpp server usage (benchmark / manual):"
echo ""
echo "  # Find model GGUF blobs from Ollama cache:"
echo "  ls ~/.ollama/models/blobs/"
echo ""
echo "  # Start server (GPU layers = 99 to push everything to VRAM):"
echo "  AMD_VULKAN_ICD=RADV llama-server --host 0.0.0.0 --port 8080 \\"
echo "    -m ~/.ollama/models/blobs/<sha256-hash> \\"
echo "    --n-gpu-layers 99"
echo ""
echo "  # API: http://192.168.1.13:8080"
echo "================================================================"

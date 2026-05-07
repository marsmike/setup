#!/bin/bash
# Ollama — primary LLM inference server
# Configures AMD iGPU override + LAN binding. Idempotent.
set -euo pipefail

# --- Install Ollama ---
if command -v ollama &>/dev/null; then
  echo "Ollama already installed: $(ollama --version 2>/dev/null || true)"
else
  echo "Installing Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh
fi

# --- Systemd override (AMD ROCm + LAN binding) ---
# Note: Radeon 890M is gfx1150 — Ollama 0.23+ detects it natively.
# HSA_OVERRIDE_GFX_VERSION is NOT set here; setting it to 11.0.3 (gfx1103) breaks
# ROCm discovery because Ollama's bundled rocblas has no Tensile kernels for gfx1103.
# gfx1150 kernels ARE present in the bundled rocblas library.
OVERRIDE_DIR=/etc/systemd/system/ollama.service.d
sudo mkdir -p "$OVERRIDE_DIR"

cat <<'EOF' | sudo tee "$OVERRIDE_DIR/override.conf" > /dev/null
[Service]
Environment="ROCR_VISIBLE_DEVICES=0"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF

sudo systemctl daemon-reload
sudo systemctl enable ollama
sudo systemctl restart ollama
sleep 3  # let it initialise

echo "Ollama service status:"
sudo systemctl is-active ollama

# --- UFW: LAN access ---
if ! sudo ufw status | grep -q "11434"; then
  sudo ufw allow from 192.168.1.0/24 to any port 11434 comment 'Ollama LAN'
  echo "UFW rule added for :11434"
else
  echo "UFW rule for :11434 already exists"
fi

# --- Pull models ---
# Verify exact tags at https://ollama.com/library before running.
# Tags below are current as of May 2026 — update if ollama pull fails.
for model in \
  "bge-m3" \
  "qwen3:30b-a3b-q4_K_M" \
  "gemma3:27b-it-q4_K_M"
do
  if ollama list | grep -q "^${model}"; then
    echo "Model already present: ${model}"
  else
    echo "Pulling ${model}..."
    ollama pull "$model" || echo "WARNING: pull failed for ${model} — verify tag name at ollama.com/library"
  fi
done

# --- Smoke test ---
echo ""
echo "Smoke test (gemma3:27b, 10 tokens):"
ollama run gemma3:27b-it-q4_K_M "Reply with exactly: ok" --nowordwrap 2>/dev/null || \
  echo "WARNING: smoke test failed — check model tag"

echo ""
echo "Loaded models:"
ollama ps

echo ""
echo "Ollama API:"
echo "  http://localhost:11434        (local)"
echo "  http://192.168.1.13:11434     (LAN)"
echo ""
echo "Check GPU backend:"
echo "  ollama ps  (shows 'GPU' column if ROCm active)"

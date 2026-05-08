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
Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
Environment="HSA_ENABLE_SDMA=0"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF

sudo systemctl daemon-reload
sudo systemctl enable ollama
sudo systemctl restart ollama

echo "Waiting for Ollama API to become ready..."
timeout 30 bash -c 'until curl -s http://localhost:11434/api/tags >/dev/null 2>&1; do sleep 1; done' \
  || { echo "ERROR: Ollama API did not start within 30 seconds"; sudo systemctl status ollama; exit 1; }

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
# Benchmarks (F3A, Radeon 890M, May 2026, q8_0 KV cache):
#   qwen3:30b-a3b-q4_K_M  29.7 t/s  primary, best speed/quality
#   gemma4:e4b            22.6 t/s  small multimodal (text+image+audio)
#   qwen3.6:35b           18.5 t/s  most capable, uses 34GB GPU with 256K ctx
#   phi4:14b               8.3 t/s  dense 14B, bandwidth-bound — optional
#   gemma3:27b-it-q4_K_M   4.2 t/s  dense 27B, very slow — skip
#
# Verify exact tags at https://ollama.com/library before running.
for model in \
  "bge-m3" \
  "qwen3:30b-a3b-q4_K_M" \
  "gemma4:e4b" \
  "qwen3.6:35b"
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
echo "Smoke test (qwen3:30b-a3b, 10 tokens):"
ollama run qwen3:30b-a3b-q4_K_M "/no_think Reply with exactly: ok" --nowordwrap 2>/dev/null || \
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

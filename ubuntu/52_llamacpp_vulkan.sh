#!/bin/bash
# llama.cpp Vulkan stack on F3A — thin launcher for the llamacpp/ compose stack.
#
# Replaces Ollama as RagFlow's chat/embed backend. ~4× faster prompt-eval on
# Qwen3-30B-A3B vs Ollama (verified, see memory/project_f3a_llm_stack.md).
#
# Native build of llama.cpp at ~/llama.cpp is still useful for ad-hoc benching
# (llama-bench, llama-cli) and is rebuilt on demand below — but production
# serving runs from the pinned llama-swap container.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -f "$REPO_ROOT/.env" ]; then
  echo "ERROR: $REPO_ROOT/.env missing. Copy .env.example → .env first."
  exit 1
fi

# Export LLAMACPP_* and stack-shared vars for docker compose substitution
set -a
# shellcheck disable=SC1091
source "$REPO_ROOT/.env"
set +a

# ── 1. Ensure mike is in render group (Vulkan needs /dev/dri/renderD128) ──
if ! id -nG | grep -qw render; then
  echo "Adding $USER to render group (re-login required to take effect)..."
  sudo usermod -aG render "$USER"
  echo "WARN: log out + back in (or new SSH session) so the group is picked up,"
  echo "      then re-run this script."
  exit 1
fi

# ── 2. Native llama.cpp build for benching (idempotent) ──
LLAMA_DIR="$HOME/llama.cpp"
if [ ! -d "$LLAMA_DIR/.git" ]; then
  echo "Cloning llama.cpp for native bench utilities..."
  sudo apt-get install -y cmake ninja-build libvulkan-dev glslc spirv-headers \
    build-essential pkg-config
  git clone --depth=1 https://github.com/ggerganov/llama.cpp "$LLAMA_DIR"
fi
if [ ! -x "$LLAMA_DIR/build/bin/llama-bench" ]; then
  echo "Building llama-bench / llama-cli for native bench use..."
  cmake -B "$LLAMA_DIR/build" -S "$LLAMA_DIR" \
    -DGGML_VULKAN=1 -DCMAKE_BUILD_TYPE=Release -G Ninja >/dev/null
  cmake --build "$LLAMA_DIR/build" --target llama-bench llama-cli -j"$(nproc)"
fi

# ── 3. Stage GGUFs as symlinks into Ollama's blob cache (no re-download) ──
mkdir -p "$HOME/llama-models"
stage_blob() {
  local manifest="$1" target="$2"
  local digest
  digest="$(sudo cat "$manifest" 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); [print(l['digest']) for l in d['layers'] if l['mediaType']=='application/vnd.ollama.image.model']" \
    | head -1 | tr -d :)"
  if [ -n "$digest" ] && [ ! -e "$HOME/llama-models/$target" ]; then
    ln -sf "/usr/share/ollama/.ollama/models/blobs/$digest" "$HOME/llama-models/$target"
    echo "  staged: $target  →  $digest"
  fi
}
echo "Staging GGUFs from Ollama blob cache..."
stage_blob /usr/share/ollama/.ollama/models/manifests/registry.ollama.ai/library/qwen3/30b-a3b-q4_K_M \
  qwen3-30b-a3b-q4_K_M.gguf
stage_blob /usr/share/ollama/.ollama/models/manifests/registry.ollama.ai/library/bge-m3/latest \
  bge-m3.gguf
# qwen3.6-35b — MoE successor, 23 GB. Lazy-loaded by llama-swap.
stage_blob /usr/share/ollama/.ollama/models/manifests/registry.ollama.ai/library/qwen3.6/35b \
  qwen3.6-35b.gguf

# qwen3-vl-8b — Ollama bundles the vision tower differently than llama-server expects,
# so we pull a separate GGUF + mmproj from the official HF repo. ~5.8 GB total, one-time.
fetch_hf() {
  local url="$1" target="$HOME/llama-models/$2"
  if [ ! -e "$target" ]; then
    echo "  pulling: $2 (~$(curl -sI "$url" | awk '/[Cc]ontent-[Ll]ength/{printf "%.1f GB", $2/1e9}'))"
    curl -fL --progress-bar -o "$target" "$url"
  fi
}
fetch_hf https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF/resolve/main/Qwen3VL-8B-Instruct-Q4_K_M.gguf \
  qwen3-vl-8b-q4_K_M.gguf
fetch_hf https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF/resolve/main/mmproj-Qwen3VL-8B-Instruct-Q8_0.gguf \
  qwen3-vl-8b-mmproj-q8_0.gguf

# ── 4. UFW: LAN access on :8080 ──
if command -v ufw >/dev/null 2>&1; then
  if ! sudo ufw status | grep -q " 8080.*192.168.1.0/24"; then
    sudo ufw allow from 192.168.1.0/24 to any port 8080 comment 'llama.cpp LAN'
  fi
fi

# ── 5. Bring up the compose stack ──
cd "$REPO_ROOT/llamacpp"
echo "Starting llama-swap stack (image: $(grep 'image:' docker-compose.yml | awk '{print $2}'))..."
docker compose up -d

# ── 6. Wait for health ──
echo "Waiting for llama-swap to respond on :8080 (model load is lazy)..."
for i in $(seq 1 30); do
  if curl -fsS -o /dev/null --max-time 2 http://localhost:8080/health 2>/dev/null; then
    echo "llama-swap is up."
    break
  fi
  printf '.'
  sleep 2
done
echo

docker compose ps
echo
echo "================================================================"
echo "Endpoint:    http://192.168.1.13:8080  (OpenAI-compatible /v1)"
echo "Models:      qwen3-30b-a3b-q4_K_M (chat), bge-m3 (embedding)"
echo
echo "Smoke test:"
echo "  curl -fsS http://localhost:8080/v1/embeddings \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"model\":\"bge-m3\",\"input\":\"hello\"}' | head -c 200"
echo
echo "Native bench (bare-metal, for comparison):"
echo "  AMD_VULKAN_ICD=RADV ~/llama.cpp/build/bin/llama-bench \\"
echo "    -m ~/llama-models/qwen3-30b-a3b-q4_K_M.gguf \\"
echo "    -ngl 99 -fa 1 -ctk q8_0 -ctv q8_0 -p 512 -n 128 -r 3"
echo "================================================================"

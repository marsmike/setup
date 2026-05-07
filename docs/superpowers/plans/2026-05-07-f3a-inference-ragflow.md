# F3A Inference + RagFlow Stack — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy a fully local LLM inference stack (Ollama + llama.cpp/Vulkan) and RagFlow + Open WebUI on the AceMagic F3A MiniPC at 192.168.1.13.

**Architecture:** Ollama serves as the primary OpenAI-compatible inference endpoint (LAN-wide); llama.cpp compiled with Vulkan is the benchmark/experimental engine. RagFlow and Open WebUI run as Docker services pointing at Ollama. All outbound traffic from Docker containers is blocked via UFW after.rules.

**Tech Stack:** Bash, Ubuntu 26.04, Ollama, llama.cpp (Vulkan/CMake), Docker Compose, UFW

---

## Workflow convention

Every task follows this pattern — do not deviate:
1. Write/edit files **locally** (`/Users/mike/work/setup/`)
2. `git add … && git commit -m "…" && git push`
3. On F3A: `ssh mike@192.168.1.13 'cd ~/work/setup && git pull'`
4. On F3A: run the script, capture output, verify
5. Fix locally if anything fails → push → pull → re-run (idempotent scripts)

All scripts use `set -euo pipefail`. Idempotency: guard every install with `command -v` or a directory/file check.

---

## Task 1: AMD GPU + Vulkan setup (`ubuntu/50_amd_gpu.sh`)

**Files:**
- Create: `ubuntu/50_amd_gpu.sh`

- [ ] **Step 1.1 — Write the script**

Create `ubuntu/50_amd_gpu.sh`:

```bash
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
```

- [ ] **Step 1.2 — Commit and push**

```bash
git add ubuntu/50_amd_gpu.sh
git commit -m "feat(ubuntu): add 50_amd_gpu.sh — Vulkan + amdgpu.gttsize=98304"
git push
```

- [ ] **Step 1.3 — Pull on F3A and run**

```bash
ssh mike@192.168.1.13 'cd ~/work/setup && git pull && bash ubuntu/50_amd_gpu.sh'
```

Expected: Vulkan packages installed, GRUB updated, "REBOOT REQUIRED" printed.

- [ ] **Step 1.4 — Reboot F3A**

```bash
ssh mike@192.168.1.13 'sudo reboot'
```

Wait ~30 seconds, then reconnect.

- [ ] **Step 1.5 — Verify GTT size and Vulkan**

```bash
ssh mike@192.168.1.13 '
  echo "=== GTT size ==="
  cat /sys/class/drm/card*/device/mem_info_gtt_total
  echo ""
  echo "=== Vulkan devices ==="
  vulkaninfo --summary 2>/dev/null | grep -E "GPU id|deviceName|driverVersion"
'
```

Expected GTT output: a number ≥ `103079215104` (96 GB in bytes).
Expected Vulkan: AMD Radeon 890M (or similar) listed as deviceName.

If GTT is still the old value, the kernel param didn't apply — check:
```bash
ssh mike@192.168.1.13 'cat /proc/cmdline | grep -o "amdgpu.gttsize=[^ ]*"'
```

---

## Task 2: Ollama inference engine (`ubuntu/51_ollama.sh`)

**Files:**
- Create: `ubuntu/51_ollama.sh`

- [ ] **Step 2.1 — Write the script**

Create `ubuntu/51_ollama.sh`:

```bash
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
OVERRIDE_DIR=/etc/systemd/system/ollama.service.d
sudo mkdir -p "$OVERRIDE_DIR"

cat <<'EOF' | sudo tee "$OVERRIDE_DIR/override.conf" > /dev/null
[Service]
Environment="HSA_OVERRIDE_GFX_VERSION=11.0.3"
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
```

- [ ] **Step 2.2 — Commit and push**

```bash
git add ubuntu/51_ollama.sh
git commit -m "feat(ubuntu): add 51_ollama.sh — Ollama with AMD ROCm override + LAN binding"
git push
```

- [ ] **Step 2.3 — Pull on F3A and run**

```bash
ssh mike@192.168.1.13 'cd ~/work/setup && git pull && bash ubuntu/51_ollama.sh 2>&1 | tee ~/setup-51.log'
```

Model pulls are large (bge-m3 ~1.5 GB, qwen3 ~17 GB, gemma3 ~15 GB). This takes 20–40 minutes depending on connection speed.

- [ ] **Step 2.4 — Verify Ollama and GPU detection**

```bash
ssh mike@192.168.1.13 '
  echo "=== Service status ==="
  sudo systemctl is-active ollama

  echo ""
  echo "=== Loaded models ==="
  ollama ps

  echo ""
  echo "=== API reachable from LAN ==="
  curl -s http://192.168.1.13:11434/api/tags | python3 -m json.tool | grep name

  echo ""
  echo "=== Quick generation test (t/s) ==="
  curl -s http://localhost:11434/api/generate \
    -d "{\"model\":\"gemma3:27b-it-q4_K_M\",\"prompt\":\"Count to 5.\",\"stream\":false}" \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
tps = d[\"eval_count\"] / d[\"eval_duration\"] * 1e9
print(f\"Tokens: {d[\"eval_count\"]}, Duration: {d[\"eval_duration\"]/1e9:.1f}s, Speed: {tps:.1f} t/s\")
"
'
```

Expected: service active, models listed, ≥20 t/s on gemma3 27B. Check `GPU` column in `ollama ps` — if blank, ROCm override didn't work; inference runs on CPU (still valid, just slower).

---

## Task 3: llama.cpp with Vulkan (`ubuntu/52_llamacpp_vulkan.sh`)

**Files:**
- Create: `ubuntu/52_llamacpp_vulkan.sh`

- [ ] **Step 3.1 — Write the script**

Create `ubuntu/52_llamacpp_vulkan.sh`:

```bash
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
~/.local/bin/llama-server --list-devices 2>&1 | head -20 || true

echo ""
echo "================================================================"
echo "llama.cpp server usage (benchmark / manual):"
echo ""
echo "  # Get model GGUF from Ollama's cache:"
echo "  ls ~/.ollama/models/blobs/"
echo ""
echo "  # Start server (GPU layers = 99 to push everything to VRAM):"
echo "  llama-server --host 0.0.0.0 --port 8080 \\"
echo "    -m ~/.ollama/models/blobs/<sha256-hash> \\"
echo "    --n-gpu-layers 99"
echo ""
echo "  # API: http://192.168.1.13:8080"
echo "================================================================"
```

- [ ] **Step 3.2 — Commit and push**

```bash
git add ubuntu/52_llamacpp_vulkan.sh
git commit -m "feat(ubuntu): add 52_llamacpp_vulkan.sh — llama.cpp built with GGML_VULKAN=1"
git push
```

- [ ] **Step 3.3 — Pull on F3A and run**

```bash
ssh mike@192.168.1.13 'cd ~/work/setup && git pull && bash ubuntu/52_llamacpp_vulkan.sh 2>&1 | tee ~/setup-52.log'
```

Build takes ~5–10 minutes on the HX370.

- [ ] **Step 3.4 — Verify**

```bash
ssh mike@192.168.1.13 '
  echo "=== Binary versions ==="
  ~/.local/bin/llama-server --version 2>&1 | head -3
  ~/.local/bin/llama-cli --version 2>&1 | head -3

  echo ""
  echo "=== Vulkan devices ==="
  ~/.local/bin/llama-server --list-devices 2>&1

  echo ""
  echo "=== UFW rules ==="
  sudo ufw status | grep -E "8080|11434|3000|80"
'
```

Expected: both binaries present, Radeon 890M listed as Vulkan device, UFW shows rules for all service ports.

---

## Task 4: RagFlow deployment (`ubuntu/53_ragflow.sh` + config files)

**Files:**
- Create: `ubuntu/ragflow/ragflow.env`
- Create: `ubuntu/ragflow/docker-compose.override.yml`
- Create: `ubuntu/53_ragflow.sh`

- [ ] **Step 4.1 — Write `ubuntu/ragflow/ragflow.env`**

```env
# RagFlow environment overrides
# Privacy: disable all telemetry and external AI endpoints
TELEMETRY_ENABLED=false
RAGFLOW_ANALYTICS=false
DOC_INTELLIGENCE_ENDPOINT=

# Inference backend — points to local Ollama
LLM_FACTORY=Ollama
OLLAMA_BASE_URL=http://host.docker.internal:11434
```

- [ ] **Step 4.2 — Write `ubuntu/ragflow/docker-compose.override.yml`**

```yaml
# Overrides applied on top of the upstream docker-compose.yml
# Usage: docker compose -f docker-compose.yml -f docker-compose.override.yml up -d
services:
  ragflow:
    environment:
      - TELEMETRY_ENABLED=false
      - RAGFLOW_ANALYTICS=false
      - DOC_INTELLIGENCE_ENDPOINT=
    extra_hosts:
      - "host.docker.internal:host-gateway"

  es01:
    environment:
      - ES_JAVA_OPTS=-Xms4g -Xmx8g
```

- [ ] **Step 4.3 — Write `ubuntu/53_ragflow.sh`**

```bash
#!/bin/bash
# RagFlow — RAG-based document Q&A (Docker Compose)
# Privacy hardened: telemetry disabled, Docker outbound blocked via UFW.
set -euo pipefail

RAGFLOW_DIR="$HOME/ragflow"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$RAGFLOW_DIR"
cd "$RAGFLOW_DIR"

# --- Fetch upstream compose (idempotent) ---
if [ ! -f docker-compose.yml ]; then
  echo "Downloading RagFlow docker-compose.yml..."
  curl -fsSL \
    "https://raw.githubusercontent.com/infiniflow/ragflow/main/docker/docker-compose.yml" \
    -o docker-compose.yml
else
  echo "docker-compose.yml already present — to update, delete and re-run."
fi

# --- Copy our override files ---
cp "$SCRIPT_DIR/ragflow/docker-compose.override.yml" ./docker-compose.override.yml
cp "$SCRIPT_DIR/ragflow/ragflow.env" ./.env

# --- UFW: block Docker container outbound, allow LAN + loopback ---
# Docker bypasses UFW by default; DOCKER-USER chain is the correct intercept point.
# We append to /etc/ufw/after.rules (UFW-managed) and reload.
AFTER_RULES=/etc/ufw/after.rules
MARKER="# BEGIN ragflow-outbound-block"

if grep -q "$MARKER" "$AFTER_RULES"; then
  echo "UFW Docker outbound rules already present."
else
  echo "Adding Docker outbound block to UFW after.rules..."
  cat <<'IPTABLES' | sudo tee -a "$AFTER_RULES" > /dev/null

# BEGIN ragflow-outbound-block
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A DOCKER-USER -d 192.168.1.0/24 -j ACCEPT
-A DOCKER-USER -d 127.0.0.0/8 -j ACCEPT
-A DOCKER-USER -j DROP
-A DOCKER-USER -j RETURN
COMMIT
# END ragflow-outbound-block
IPTABLES
  sudo ufw reload
  echo "UFW reloaded with Docker outbound block."
fi

# --- UFW: allow LAN access to RagFlow UI ---
if ! sudo ufw status | grep -q " 80 "; then
  sudo ufw allow from 192.168.1.0/24 to any port 80 comment 'RagFlow LAN'
fi

# --- Start RagFlow ---
echo "Starting RagFlow stack..."
docker compose \
  -f docker-compose.yml \
  -f docker-compose.override.yml \
  --env-file .env \
  up -d

echo ""
echo "Waiting for RagFlow to become healthy..."
sleep 15
docker compose ps

echo ""
echo "================================================================"
echo "RagFlow: http://192.168.1.13"
echo "First visit: create admin account."
echo ""
echo "Configure LLM backend in RagFlow UI:"
echo "  Settings → Model Providers → Add → Ollama"
echo "  Base URL: http://host.docker.internal:11434"
echo "  Models: gemma3:27b-it-q4_K_M, qwen3:30b-a3b-q4_K_M"
echo ""
echo "Configure embedding model:"
echo "  Settings → Model Providers → Add → Ollama → bge-m3"
echo "================================================================"
```

- [ ] **Step 4.4 — Commit and push**

```bash
git add ubuntu/53_ragflow.sh ubuntu/ragflow/
git commit -m "feat(ubuntu): add 53_ragflow.sh + RagFlow override config with privacy hardening"
git push
```

- [ ] **Step 4.5 — Pull on F3A and run**

```bash
ssh mike@192.168.1.13 'cd ~/work/setup && git pull && bash ubuntu/53_ragflow.sh 2>&1 | tee ~/setup-53.log'
```

Docker will pull several large images (RagFlow, Elasticsearch, MinIO). Takes 5–15 minutes.

- [ ] **Step 4.6 — Verify RagFlow**

```bash
ssh mike@192.168.1.13 '
  echo "=== Container status ==="
  docker compose -f ~/ragflow/docker-compose.yml ps

  echo ""
  echo "=== HTTP health check ==="
  curl -s -o /dev/null -w "%{http_code}" http://localhost/ || echo "not ready"

  echo ""
  echo "=== UFW status ==="
  sudo ufw status | grep -E "80|11434|8080|3000"

  echo ""
  echo "=== Outbound block test (should fail/timeout) ==="
  docker exec ragflow curl -s --connect-timeout 3 https://example.com \
    && echo "WARNING: outbound not blocked!" \
    || echo "OK: outbound blocked"
'
```

Expected: all containers Up, HTTP 200 on port 80, outbound test times out/fails.

---

## Task 5: Open WebUI (`ubuntu/54_openwebui.sh`)

**Files:**
- Create: `ubuntu/54_openwebui.sh`

- [ ] **Step 5.1 — Write the script**

Create `ubuntu/54_openwebui.sh`:

```bash
#!/bin/bash
# Open WebUI — Chat interface over Ollama
# Runs as a standalone Docker container (independent of RagFlow).
set -euo pipefail

CONTAINER_NAME=open-webui

# --- Remove old container if present (for idempotent re-run) ---
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Removing existing ${CONTAINER_NAME} container..."
  docker rm -f "$CONTAINER_NAME"
fi

# --- Start Open WebUI ---
docker run -d \
  --name "$CONTAINER_NAME" \
  --restart always \
  -p 3000:8080 \
  -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
  -e WEBUI_AUTH=true \
  -v open-webui-data:/app/backend/data \
  --add-host host.docker.internal:host-gateway \
  ghcr.io/open-webui/open-webui:main

echo "Waiting for Open WebUI to start..."
sleep 10

docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# --- UFW: LAN access ---
if ! sudo ufw status | grep -q "3000"; then
  sudo ufw allow from 192.168.1.0/24 to any port 3000 comment 'Open WebUI LAN'
  echo "UFW rule added for :3000"
fi

echo ""
echo "================================================================"
echo "Open WebUI: http://192.168.1.13:3000"
echo "First visit: create admin account."
echo "Ollama models are auto-discovered from http://host.docker.internal:11434"
echo "================================================================"
```

- [ ] **Step 5.2 — Commit and push**

```bash
git add ubuntu/54_openwebui.sh
git commit -m "feat(ubuntu): add 54_openwebui.sh — Open WebUI chat interface over Ollama"
git push
```

- [ ] **Step 5.3 — Pull on F3A and run**

```bash
ssh mike@192.168.1.13 'cd ~/work/setup && git pull && bash ubuntu/54_openwebui.sh 2>&1 | tee ~/setup-54.log'
```

- [ ] **Step 5.4 — Verify**

```bash
ssh mike@192.168.1.13 '
  echo "=== Container status ==="
  docker ps --filter name=open-webui --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

  echo ""
  echo "=== HTTP check ==="
  curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:3000

  echo ""
  echo "=== Model list via Open WebUI API ==="
  curl -s http://localhost:3000/api/models 2>/dev/null \
    | python3 -m json.tool 2>/dev/null | grep '"id"' | head -5 \
    || echo "(models only show after first login)"
'
```

Expected: container Up, HTTP 200 on port 3000.

---

## Task 6: Benchmark script (`ubuntu/benchmark_llm.sh`)

**Files:**
- Create: `ubuntu/benchmark_llm.sh`

- [ ] **Step 6.1 — Write the script**

Create `ubuntu/benchmark_llm.sh`:

```bash
#!/bin/bash
# Benchmark: Ollama vs llama.cpp (Vulkan) token-per-second comparison.
# Run AFTER 51_ollama.sh and 52_llamacpp_vulkan.sh.
# llama.cpp server must NOT be running before this script starts.
set -euo pipefail

PROMPT="Explain the water cycle in detail, covering evaporation, condensation, precipitation, and collection. Include the role of solar energy and atmospheric conditions."
MAX_TOKENS=200
OLLAMA_URL="http://localhost:11434"
LLAMACPP_PORT=8080
LLAMACPP_BIN="$HOME/.local/bin/llama-server"

RED='\033[0;31m'; GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'

# Models to test: "ollama_tag|gguf_blob_sha_prefix|display_name"
# Find GGUF blobs: ls ~/.ollama/models/blobs/ | grep -v sha256
# Each model's manifest: cat ~/.ollama/models/manifests/registry.ollama.ai/library/<model>/latest
MODELS=(
  "gemma3:27b-it-q4_K_M|Gemma3 27B Q4"
  "qwen3:30b-a3b-q4_K_M|Qwen3 30B MoE Q4"
)

declare -A RESULTS

# --- Ollama benchmark ---
echo -e "\n${BOLD}=== OLLAMA BENCHMARK ===${NC}"
for entry in "${MODELS[@]}"; do
  tag="${entry%%|*}"
  label="${entry##*|}"

  echo -n "Testing ${label}... "
  response=$(curl -s "$OLLAMA_URL/api/generate" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${tag}\",\"prompt\":\"${PROMPT}\",\"stream\":false,\"options\":{\"num_predict\":${MAX_TOKENS}}}")

  if echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if 'eval_count' in d else 1)" 2>/dev/null; then
    tps=$(echo "$response" | python3 -c "
import sys, json
d = json.load(sys.stdin)
tps = d['eval_count'] / d['eval_duration'] * 1e9
print(f'{tps:.1f}')
")
    tokens=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin)['eval_count'])")
    echo -e "${GREEN}${tps} t/s${NC} (${tokens} tokens)"
    RESULTS["ollama|${label}"]="$tps"
  else
    echo -e "${RED}FAILED${NC} — is model pulled? Run: ollama pull ${tag}"
    RESULTS["ollama|${label}"]="FAIL"
  fi
done

# --- llama.cpp benchmark ---
echo -e "\n${BOLD}=== LLAMA.CPP (VULKAN) BENCHMARK ===${NC}"
echo "Note: llama.cpp tests one model at a time. Ollama must free GPU first."
echo "Stopping Ollama to free GPU resources..."
sudo systemctl stop ollama
sleep 3

for entry in "${MODELS[@]}"; do
  tag="${entry%%|*}"
  label="${entry##*|}"

  # Find the GGUF blob for this model from Ollama's cache
  model_name="${tag%%:*}"
  model_tag="${tag##*:}"
  manifest_path="$HOME/.ollama/models/manifests/registry.ollama.ai/library/${model_name}/${model_tag}"

  if [ ! -f "$manifest_path" ]; then
    echo -e "${RED}SKIP${NC} ${label}: manifest not found at ${manifest_path}"
    RESULTS["llamacpp|${label}"]="SKIP"
    continue
  fi

  # Extract blob digest from manifest
  blob_digest=$(python3 -c "
import json, sys
with open('${manifest_path}') as f:
    m = json.load(f)
for layer in m.get('layers', []):
    if layer.get('mediaType','').endswith('.model'):
        print(layer['digest'].replace('sha256:','sha256-'))
        break
")
  gguf_path="$HOME/.ollama/models/blobs/${blob_digest}"

  if [ ! -f "$gguf_path" ]; then
    echo -e "${RED}SKIP${NC} ${label}: blob not found at ${gguf_path}"
    RESULTS["llamacpp|${label}"]="SKIP"
    continue
  fi

  echo -n "Testing ${label} (starting server)... "

  # Start llama.cpp server
  "$LLAMACPP_BIN" \
    --host 0.0.0.0 --port "$LLAMACPP_PORT" \
    -m "$gguf_path" \
    --n-gpu-layers 99 \
    --log-disable \
    > /tmp/llamacpp-bench.log 2>&1 &
  LLAMACPP_PID=$!

  # Wait for server ready
  for i in $(seq 1 30); do
    curl -s "http://localhost:${LLAMACPP_PORT}/health" &>/dev/null && break
    sleep 2
  done

  # Run generation
  start_ns=$(date +%s%N)
  response=$(curl -s "http://localhost:${LLAMACPP_PORT}/completion" \
    -H "Content-Type: application/json" \
    -d "{\"prompt\":\"${PROMPT}\",\"n_predict\":${MAX_TOKENS},\"stream\":false}")
  end_ns=$(date +%s%N)

  kill "$LLAMACPP_PID" 2>/dev/null
  wait "$LLAMACPP_PID" 2>/dev/null

  if tokens_predicted=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin)['tokens_predicted'])" 2>/dev/null); then
    elapsed_s=$(python3 -c "print(f'{($end_ns - $start_ns)/1e9:.1f}')")
    tps=$(python3 -c "print(f'{${tokens_predicted}/${elapsed_s}:.1f}')")
    echo -e "${GREEN}${tps} t/s${NC} (${tokens_predicted} tokens in ${elapsed_s}s)"
    RESULTS["llamacpp|${label}"]="$tps"
  else
    echo -e "${RED}FAILED${NC}"
    RESULTS["llamacpp|${label}"]="FAIL"
  fi

  sleep 2
done

# Restart Ollama
echo ""
echo "Restarting Ollama..."
sudo systemctl start ollama

# --- Results table ---
echo ""
echo -e "${BOLD}================================================================${NC}"
echo -e "${BOLD}RESULTS (tokens/second)${NC}"
echo -e "${BOLD}================================================================${NC}"
printf "%-32s %12s %15s\n" "Model" "Ollama" "llama.cpp"
printf "%-32s %12s %15s\n" "-----" "------" "---------"
for entry in "${MODELS[@]}"; do
  label="${entry##*|}"
  ollama_tps="${RESULTS["ollama|${label}"]:-N/A}"
  llamacpp_tps="${RESULTS["llamacpp|${label}"]:-N/A}"
  printf "%-32s %12s %15s\n" "$label" "$ollama_tps" "$llamacpp_tps"
done
echo -e "${BOLD}================================================================${NC}"
echo ""
echo "GPU utilisation during benchmark: run 'radeontop' in a separate terminal"
```

- [ ] **Step 6.2 — Commit and push**

```bash
git add ubuntu/benchmark_llm.sh
git commit -m "feat(ubuntu): add benchmark_llm.sh — Ollama vs llama.cpp t/s comparison"
git push
```

- [ ] **Step 6.3 — Pull on F3A and run (after Tasks 2 and 3 complete)**

```bash
ssh mike@192.168.1.13 'cd ~/work/setup && git pull && bash ubuntu/benchmark_llm.sh 2>&1 | tee ~/benchmark-results.log'
```

Expected: results table with t/s for both engines. Target ≥20 t/s on Qwen3 MoE.

---

## Task 7: End-to-end integration smoke test

No new files — verification only.

- [ ] **Step 7.1 — Full service check**

```bash
ssh mike@192.168.1.13 '
  echo "=== Services ==="
  sudo systemctl is-active ollama
  docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "ragflow|open-webui|es01|minio|redis|mysql"

  echo ""
  echo "=== UFW rules ==="
  sudo ufw status numbered | grep -E "80|3000|8080|11434"

  echo ""
  echo "=== GTT size (GPU VRAM cap) ==="
  cat /sys/class/drm/card*/device/mem_info_gtt_total \
    | awk "{printf \"%.0f GB\n\", \$1/1024/1024/1024}"

  echo ""
  echo "=== Ollama models ==="
  ollama list

  echo ""
  echo "=== Open WebUI ==="
  curl -s -o /dev/null -w "Open WebUI HTTP: %{http_code}\n" http://localhost:3000

  echo ""
  echo "=== RagFlow ==="
  curl -s -o /dev/null -w "RagFlow HTTP: %{http_code}\n" http://localhost/

  echo ""
  echo "=== Privacy check: Docker outbound blocked ==="
  docker exec ragflow curl -s --connect-timeout 3 https://ifconfig.me \
    && echo "WARNING: outbound NOT blocked" \
    || echo "OK: Docker outbound blocked"
'
```

- [ ] **Step 7.2 — Configure RagFlow manually in browser**

Open `http://192.168.1.13` in browser:
1. Create admin account (first visit)
2. Settings → Model Providers → Add Ollama provider:
   - Base URL: `http://host.docker.internal:11434`
3. Add models: `gemma3:27b-it-q4_K_M`, `qwen3:30b-a3b-q4_K_M`
4. Add embedding model: `bge-m3`
5. Create a knowledge base, upload a document, run a query

- [ ] **Step 7.3 — Configure Open WebUI manually in browser**

Open `http://192.168.1.13:3000`:
1. Create admin account (first visit)
2. Verify Ollama models appear in model selector
3. Send one test message — confirm response generates

- [ ] **Step 7.4 — Commit benchmark results**

```bash
scp mike@192.168.1.13:~/benchmark-results.log /Users/mike/work/setup/docs/
git add docs/benchmark-results.log
git commit -m "docs: add F3A benchmark results (Ollama vs llama.cpp Vulkan)"
git push
```

---

## Quick reference — run order on F3A

```bash
bash ubuntu/50_amd_gpu.sh && sudo reboot
# after reboot — verify GTT size, then:
bash ubuntu/51_ollama.sh        # ~30 min (model downloads)
bash ubuntu/52_llamacpp_vulkan.sh  # ~10 min (build)
bash ubuntu/53_ragflow.sh       # ~15 min (image pulls)
bash ubuntu/54_openwebui.sh     # ~5 min
bash ubuntu/benchmark_llm.sh    # ~20 min
```

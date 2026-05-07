# F3A Inference + RagFlow Stack — Design Spec

**Date:** 2026-05-07
**Hardware:** AceMagic F3A — AMD HX370 (Radeon 890M, RDNA 3.5, gfx1103), 128 GB LPDDR5X
**OS:** Ubuntu 26.04 (192.168.1.13)
**Goal:** Local LLM inference (no cloud, no telemetry) + RagFlow document Q&A, all on bare metal.

---

## Architecture

Four layers stacked on the F3A:

```
F3A (192.168.1.13)
│
├── Layer 1 — GPU / kernel
│   ├── amdgpu.gttsize=98304  (96 GB GTT cap — mapping limit, not reservation)
│   ├── Vulkan drivers: mesa-vulkan-drivers, vulkan-tools
│   └── ROCm override: HSA_OVERRIDE_GFX_VERSION=11.0.3 (injected via Ollama systemd env)
│
├── Layer 2 — Inference                    ← LAN-accessible (192.168.1.0/24)
│   ├── Ollama :11434          primary, OpenAI-compatible, systemd-managed
│   │   └── OLLAMA_HOST=0.0.0.0 — binds all interfaces
│   └── llama.cpp server :8080 benchmark + experimental, manual start only
│       └── --host 0.0.0.0 — binds all interfaces
│
├── Layer 3 — RagFlow (Docker Compose)     ← LAN-accessible :80
│   ├── ragflow-server :80
│   ├── elasticsearch (heap capped at 8 GB)
│   ├── minio, redis, mysql
│   ├── telemetry disabled — env vars + UFW after.rules outbound block
│   └── LLM backend → Ollama at host.docker.internal:11434
│
└── Layer 4 — Open WebUI (Docker)          ← LAN-accessible :3000
    ├── Chat UI for direct Ollama interaction
    ├── Persistent volume: open-webui-data
    └── Backend → Ollama at host.docker.internal:11434
```

### Why Vulkan over ROCm

The HX370 iGPU is gfx1103 (RDNA 3.5). ROCm officially supports gfx1100/1101/1102 only.
`HSA_OVERRIDE_GFX_VERSION=11.0.3` may unlock ROCm on this chip — Ollama will attempt it.
If ROCm is unstable, llama.cpp compiled with `GGML_VULKAN=1` is the reliable fallback;
Vulkan works on any GPU with a compliant driver, no ROCm needed.

### Why amdgpu.gttsize matters

AMD APU unified memory: GPU VRAM is drawn from system RAM on demand.
The GTT (Graphics Translation Table) size is a **mapping cap, not a reservation**.
Setting `amdgpu.gttsize=98304` allows the GPU to map up to 96 GB — but only consumes
that memory when models are actually loaded.

| State | GPU-mapped | Available to system |
|---|---|---|
| Idle | 0 GB | 128 GB |
| Qwen3 30B MoE Q4 (~17 GB) | ~17 GB | ~111 GB |
| All three models loaded | ~21 GB | ~107 GB |
| RagFlow stack overhead | — | −14 GB |
| **Net headroom (all running)** | | **~93 GB** |

Probing sequence: set 32 GB → reboot → verify → 64 GB → reboot → verify → 96 GB → reboot → verify.
Verification: `cat /sys/class/drm/card0/device/mem_info_gtt_total` (value in bytes).

---

## Models

| Model | Size (Q4_K_M) | Role | Notes |
|---|---|---|---|
| `bge-m3` | ~1.5 GB | Embeddings + reranking | RagFlow ingestion + retrieval |
| `qwen3:30b-a3b-q4_K_M` | ~17 GB | Primary generation | MoE: 3.6B active params/token — fast despite size |
| `gemma4` | ~2.5–15 GB | Fast generation / fallback | Exact variant TBD at pull time |

All three fit simultaneously in GPU-mapped memory. Target: ≥20 t/s on Qwen3 MoE.
Memory bandwidth (~100 GB/s LPDDR5X) is the throughput ceiling; MoE active-param efficiency helps.

---

## Script Structure

New scripts added to `ubuntu/` following the existing `NN_name.sh` numbering:

```
ubuntu/
├── 50_amd_gpu.sh           Vulkan drivers + GRUB kernel param
├── 51_ollama.sh            Ollama install, ROCm env, model pulls
├── 52_llamacpp_vulkan.sh   Build llama.cpp from source (GGML_VULKAN=1)
├── 53_ragflow.sh           RagFlow Docker Compose + privacy hardening
├── 54_openwebui.sh         Open WebUI Docker container + UFW rule
├── benchmark_llm.sh        t/s comparison: Ollama vs llama.cpp, all models
│
└── ragflow/
    ├── docker-compose.override.yml   ES heap, telemetry vars, Ollama endpoint
    └── ragflow.env                   LLM backend config, privacy flags
```

### 50_amd_gpu.sh

1. Install `mesa-vulkan-drivers vulkan-tools libvulkan1 libvulkan-dev`
2. Read current GTT: `cat /sys/class/drm/card0/device/mem_info_gtt_total`
3. Add `amdgpu.gttsize=98304` to `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`
4. `sudo update-grub`
5. Run `vulkaninfo --summary` to confirm GPU is detected pre-reboot
6. Print: reboot required, post-reboot verification command

### 51_ollama.sh

1. Install Ollama via official script
2. Write `/etc/systemd/system/ollama.service.d/override.conf`:
   ```
   [Service]
   Environment="HSA_OVERRIDE_GFX_VERSION=11.0.3"
   Environment="ROCR_VISIBLE_DEVICES=0"
   Environment="OLLAMA_FLASH_ATTENTION=1"
   Environment="OLLAMA_NUM_PARALLEL=1"
   Environment="OLLAMA_HOST=0.0.0.0:11434"
   ```
3. `systemctl daemon-reload && systemctl enable --now ollama`
4. Pull models: `ollama pull bge-m3`, `ollama pull qwen3:30b-a3b-q4_K_M`, `ollama pull gemma4`
5. Open LAN access: `sudo ufw allow from 192.168.1.0/24 to any port 11434 comment 'Ollama LAN'`
6. Smoke-test: `ollama run gemma4 "Hello" --nowordwrap`
7. Print GPU utilisation check: `ollama ps` (shows which backend is active)

### 52_llamacpp_vulkan.sh

1. Install build deps: `cmake ninja-build libvulkan-dev glslc`
2. Clone: `git clone https://github.com/ggerganov/llama.cpp ~/llama.cpp`
3. Build:
   ```bash
   cmake -B build -DGGML_VULKAN=1 -DCMAKE_BUILD_TYPE=Release
   cmake --build build -j$(nproc)
   ```
4. Install `llama-server` and `llama-cli` to `~/.local/bin`
5. Open LAN access: `sudo ufw allow from 192.168.1.0/24 to any port 8080 comment 'llama.cpp LAN'`
6. Print usage: `llama-server --host 0.0.0.0 --port 8080 -m /path/to/model.gguf`

### 53_ragflow.sh

1. `mkdir -p ~/ragflow`
2. Fetch upstream compose: `curl -fsSL https://raw.githubusercontent.com/infiniflow/ragflow/main/docker/docker-compose.yml`
3. Write `ragflow/docker-compose.override.yml` and `ragflow/ragflow.env` (see Privacy section)
4. `docker compose --env-file ragflow.env up -d`
5. Append DOCKER-USER block to `/etc/ufw/after.rules`, then `sudo ufw reload`
6. Print: RagFlow URL, admin setup instructions, Ollama config location in UI

### 54_openwebui.sh

1. Run as standalone Docker container (no Compose — keeps it independent of RagFlow):
   ```bash
   docker run -d \
     --name open-webui \
     --restart always \
     -p 3000:8080 \
     -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
     -v open-webui-data:/app/backend/data \
     --add-host host.docker.internal:host-gateway \
     ghcr.io/open-webui/open-webui:main
   ```
2. Open LAN access: `sudo ufw allow from 192.168.1.0/24 to any port 3000 comment 'Open WebUI LAN'`
3. Print: `http://192.168.1.13:3000` — first visit creates admin account

### benchmark_llm.sh

For each model (Qwen3 MoE, Gemma4):
1. Start llama.cpp server on :8080 with GGUF path
2. Run 3 identical generation requests (warm-up + 2 measured), capture t/s
3. Stop llama.cpp server
4. Run same requests through Ollama on :11434, capture t/s
5. Capture GPU utilisation via `radeontop -d -` during each run
6. Print comparison table: model × engine × t/s × GPU%

---

## RagFlow Privacy Hardening

### Layer 1 — Application env vars (`ragflow.env`)

```env
TELEMETRY_ENABLED=false
RAGFLOW_ANALYTICS=false
DOC_INTELLIGENCE_ENDPOINT=
LLM_FACTORY=Ollama
OLLAMA_BASE_URL=http://host.docker.internal:11434
```

### Layer 2 — Elasticsearch heap cap (`docker-compose.override.yml`)

```yaml
services:
  es01:
    environment:
      - ES_JAVA_OPTS=-Xms4g -Xmx8g
```

### Layer 3 — Outbound firewall (UFW)

Docker bypasses UFW's default chains by writing iptables rules directly.
The fix: append DOCKER-USER rules into `/etc/ufw/after.rules` (UFW-managed),
then reload UFW — no direct iptables commands needed.

`53_ragflow.sh` appends to `/etc/ufw/after.rules`:

```
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
```

Then applies with:
```bash
sudo ufw reload
sudo ufw status verbose
```

RagFlow reaches Ollama via `host.docker.internal:11434` (LAN-local, permitted).
All external calls from Docker containers are dropped. Rules survive reboots
because UFW manages `/etc/ufw/after.rules` natively.

---

## LAN Endpoints

All services on F3A are accessible from any machine on 192.168.1.0/24:

| Service | URL | Notes |
|---|---|---|
| RagFlow UI | `http://192.168.1.13` | Document Q&A, knowledge base |
| Open WebUI | `http://192.168.1.13:3000` | Chat UI over Ollama |
| Ollama API | `http://192.168.1.13:11434` | OpenAI-compatible (`/v1/chat/completions`, `/v1/embeddings`) |
| llama.cpp server | `http://192.168.1.13:8080` | OpenAI-compatible (benchmark / manual use only) |

UFW rules allow inbound on 11434 and 8080 from LAN only (not internet-exposed).
Outbound from Docker containers (RagFlow) is blocked except LAN + loopback.

---

## Run Order on F3A

```bash
bash ubuntu/50_amd_gpu.sh      # install Vulkan, set GRUB param
sudo reboot                     # required for amdgpu.gttsize to take effect
# verify: cat /sys/class/drm/card0/device/mem_info_gtt_total

bash ubuntu/51_ollama.sh       # install Ollama, ROCm override, pull models
bash ubuntu/52_llamacpp_vulkan.sh  # build llama.cpp with Vulkan
bash ubuntu/53_ragflow.sh      # deploy RagFlow + privacy rules
bash ubuntu/54_openwebui.sh    # deploy Open WebUI chat interface
bash ubuntu/benchmark_llm.sh   # compare t/s Ollama vs llama.cpp
```

---

## Future / Experimental (not in scope now)

- KV-cache quantisation (llama.cpp `--cache-type-k q8_0`)
- TurboQuant / EXL2 format models (exllamav2 engine)
- vLLM with ROCm if gfx1103 support improves
- Continuous batching for multi-user throughput
- Model routing: small model (Gemma4) for retrieval, large (Qwen3) for generation

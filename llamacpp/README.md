# llama.cpp Vulkan Stack (F3A)

Self-compiled (well — upstream Vulkan-built) llama.cpp behind llama-swap, on
the AMD Radeon 890M iGPU. Replaces Ollama as RagFlow's chat/embed backend,
delivering ~4× prompt-eval throughput on Qwen3-30B-A3B.

## Why this exists

Ollama's vendored llama.cpp (frozen at b7437, Dec 2025) is missing two Vulkan
PRs that materially help on gfx1150:

- Wave32 Flash Attention (PR #19625, Feb 2026)
- Graphics Queue support (PR #20551, Mar 2026)

Verified delta on F3A (clean bench, build aaf4a4d, 2026-05-08):

| test  | Ollama | llama.cpp Vulkan | speedup |
|-------|-------:|-----------------:|--------:|
| Qwen3-30B-A3B pp512 | 103 t/s | 443.83 t/s | **4.3×** |
| Qwen3-30B-A3B tg128 | 29.7 t/s | 33.87 t/s | 1.14× |
| bge-m3 prompt eval | ~1800 t/s | 2825 t/s | ~1.6× |

For a RAG workload (where prompt-eval dominates query latency), the realised
speedup is ~4×. See `~/.claude/.../memory/project_f3a_llm_stack.md`.

## Run order

```bash
# From repo root, with .env populated:
bash ubuntu/52_llamacpp_vulkan.sh
```

Stack starts in foreground until healthy; binds `:8080`, exposes the OpenAI-
compatible API. Models are loaded on first request; configured `ttl: 0` keeps
the two RagFlow-critical ones (chat + embed) resident permanently.

## What's served

| model id (in API) | type | model file | flags |
|---|---|---|---|
| `qwen3-30b-a3b-q4_K_M` | chat | `qwen3-30b-a3b-q4_K_M.gguf` | -ngl 99 -fa on -ctk q8_0 -ctv q8_0 |
| `bge-m3` | embedding | `bge-m3.gguf` | -ngl 99 --embeddings --pooling mean |

Both flag sets are the verified-fast configuration from the bench. Don't
change them without re-benching.

## Files

- `docker-compose.yml` — single `llama-swap` service, pinned to
  `ghcr.io/mostlygeek/llama-swap:vulkan-v211`. Mounts `/dev/dri/renderD128`
  with `group_add: ["990"]` for render-group access.
- `config.yaml` — llama-swap model definitions (chat + embed for now).
- `ubuntu/52_llamacpp_vulkan.sh` — thin launcher (this script).

## Smoke tests

```bash
# health
curl -fsS http://localhost:8080/health

# chat
curl -fsS http://localhost:8080/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"qwen3-30b-a3b-q4_K_M","messages":[{"role":"user","content":"ping"}]}'

# embedding
curl -fsS http://localhost:8080/v1/embeddings -H 'Content-Type: application/json' \
  -d '{"model":"bge-m3","input":"the quick brown fox"}'

# what's currently loaded
curl -fsS http://localhost:8080/upstream
```

## RagFlow integration

Register both models in RagFlow under the `OpenAI-API-Compatible` factory,
with `api_base=http://host.docker.internal:8080/v1` (RagFlow runs in Docker;
`host.docker.internal` resolves to the host bridge, where llama-swap listens).
Set `tenant.llm_id` and `tenant.embd_id` to `qwen3-30b-a3b-q4_K_M@OpenAI-API-Compatible`
and `bge-m3@OpenAI-API-Compatible` respectively.

## Vision (qwen3-vl:8b) is NOT here yet

VLM stays in Ollama for now — it ships a separate `mmproj` file that needs
llama-server's `--mmproj` flag, and Ollama already packages the pair. Migrate
once we have a working pattern. Until then, RagFlow keeps `qwen3-vl:8b@Ollama`
for `image2text`.

## Reset / debug

```bash
# Logs
docker compose logs -f llama-swap

# Restart (re-reads config.yaml)
docker compose restart

# Confirm Vulkan inside the container sees the iGPU:
docker compose exec llama-swap vulkaninfo --summary | grep -E 'deviceName'
```

## Why upstream image, not our own build?

The bench used `~/llama.cpp` build `aaf4a4d` (May 7, 2026). The
`ghcr.io/mostlygeek/llama-swap:vulkan-v211` image bundles llama.cpp from a
similar nightly date. If perf parity (within ±10% of bare-metal pp512) is
confirmed by Task #20, we stay on upstream. If not, we'll add a `Dockerfile`
that bakes our exact build.

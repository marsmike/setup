# RagFlow on F3A — Fix & Refactor Design Spec

**Date:** 2026-05-08
**Target:** F3A MiniPC (192.168.1.13), Ubuntu, single-user personal LAN deployment
**Inspiration:** `~/work/ragflow-docker` (multi-instance Bosch deployment)

## Problem

`ubuntu/53_ragflow.sh` fetches the upstream RagFlow `docker-compose.yml` at runtime, applies a thin override, and performs a fragile UFW outbound-block dance to allow first-run tiktoken downloads while keeping the container otherwise sandboxed. Recent commits show repeated chasing of upstream drift and first-run brittleness:

- `set TIKTOKEN_CACHE_DIR to persistent volume path`
- `move es01 above volumes key in override — YAML structure fix`
- `persist tiktoken cache in named volume to survive restarts`
- `allow Docker→Ollama UFW, set LLM_TIMEOUT_SECONDS=120`
- `auto-persist API key from RAGFLOW_API_KEY env var`

Every fresh deploy still requires manual UI clicking: log in, create API key, add Ollama provider, register each model.

## Goals

1. **Eliminate the UFW outbound block.** F3A is on a private LAN; the threat model doesn't justify the complexity.
2. **Auto-init users, API key, and LLM provider** on first boot, drawing from `ragflow-docker`'s `init_default_users.py` pattern.
3. **Vendor & pin** the RagFlow Docker Compose stack — stop fighting upstream drift.
4. **Read deployment defaults from `.env`** at the repo root (single source of truth).

## Non-goals

- Multi-instance support (single F3A box, single user).
- LiteLLM / OpenAI-compatible proxy paths (Ollama only).
- Langfuse observability (out of scope).
- MCP / Admin server (default-off; can be added later).
- Rerank / ASR / image2text models (Ollama factory doesn't differentiate; not used today).

## Approach

**Vendor + customize.** Copy a slimmed-down `docker-compose.yml`, `entrypoint.sh`, `init_default_user.py`, and `service_conf.yaml.template` into `setup/ragflow/`. Pin the RagFlow image to **`infiniflow/ragflow:v0.25.1`** (latest stable as of 2026-04-30). Mount the entrypoint and init script into the upstream container as volumes — no custom image build.

The bash wrapper `ubuntu/53_ragflow.sh` becomes a thin launcher: source `.env`, allow inbound port 80 from LAN via UFW, `docker compose up -d`, wait for health.

## File layout

```
setup/
├── ragflow/                          # NEW: top-level, mirrors proxmox/
│   ├── README.md                      # overview, run order, troubleshooting
│   ├── docker-compose.yml             # vendored, pinned, slim (single profile)
│   ├── entrypoint.sh                  # slimmed port from ragflow-docker
│   ├── init_default_user.py           # creates user + API key + Ollama models
│   └── service_conf.yaml.template     # ${VAR} placeholders, processed by entrypoint
├── ubuntu/
│   ├── 53_ragflow.sh                  # NEW THIN: source .env, docker compose up
│   └── ragflow/                       # DELETED — moved to top-level
├── .env.example                       # documents new RAGFLOW_* variables
└── .env                               # unchanged location, holds RAGFLOW_* vars
```

## `init_default_user.py` — auto-init behavior

Slimmed from `ragflow-docker`'s script: single user, Ollama-only, no LiteLLM, no Langfuse, no proxy logic.

**Inputs (env vars, set in `.env`):**

| Variable | Example | Purpose |
|---|---|---|
| `RAGFLOW_DEFAULT_EMAIL` | `muemike@gmail.com` | Admin user email |
| `RAGFLOW_DEFAULT_PASSWORD` | `<password>` | Admin user password |
| `RAGFLOW_DEFAULT_NICKNAME` | `Mike` | Display name |
| `RAGFLOW_API_KEY` | `ragflow-AbCd...` | Stable API token, persisted to DB on every boot |
| `OLLAMA_BASE_URL` | `http://host.docker.internal:11434` | Ollama endpoint |
| `RAGFLOW_DEFAULT_CHAT_MODEL` | `qwen3:30b-a3b-q4_K_M` | Default chat model |
| `RAGFLOW_DEFAULT_EMBEDDING_MODEL` | `bge-m3` | Default embedding model |
| `RAGFLOW_ADDITIONAL_CHAT_MODELS` | `gemma4:e4b,qwen3.6:35b` | Comma-separated extras |

**Behavior on container start:**

1. `wait_for_database()` — retry loop (40 × 3s = 2 min ceiling).
2. **If `user` table is empty (first run):**
   - Create admin user from `.env` vars (UserService + tenant + user-tenant relationship + root folder).
   - Register Ollama as LLM factory pointing at `OLLAMA_BASE_URL`.
   - Add chat models + embedding model to user's "Added Models" list.
   - Set `bge-m3` as default embedding.
3. **Always (idempotent, every boot):**
   - Ensure `RAGFLOW_API_KEY` exists in `api_token` table for the admin user. Recreate if missing. Survives `docker compose down && up`.
4. Exit clean → entrypoint continues. Failures exit non-zero → container restarts.

**Removed vs ragflow-docker version:**

- LiteLLM / OpenAI-Compatible factory path (we only use Ollama).
- Langfuse setup.
- Second hardcoded user.
- Rerank / ASR / image2text model handling.

## `entrypoint.sh` — slimmed startup

Trimmed from ragflow-docker's 239-line version with all flag parsing removed. F3A runs one webserver + one task executor.

**Steps:**

1. `set -e`, export `PYTHONPATH=/ragflow`, `LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu/`.
2. `envsubst` over `service_conf.yaml.template` → `service_conf.yaml`.
3. Run `init_default_user.py` (blocks until DB ready and user/API key exist).
4. Start `nginx` (web UI on port 80).
5. Start `ragflow_server` (API on port 9380) with restart-on-crash loop, in background.
6. Start one `task_executor` worker with restart-on-crash loop, in background.
7. `wait` on background PIDs (container stays alive, stops cleanly on signals).

**Kept:** `jemalloc` `LD_PRELOAD` (free memory win).
**Removed:** all `--workers`, `--enable-mcpserver`, `--consumer-no-beg` argument parsing; MCP server; Admin server.

## `docker-compose.yml` — vendored, slim

Single file, single profile. Services: `ragflow`, `mysql`, `redis`, `minio`, `es01`. Image pinned to `infiniflow/ragflow:v0.25.1` (full image — embeds local embedding models, `LIGHTEN=0`).

**Mounted into container:**

```yaml
volumes:
  - ./entrypoint.sh:/ragflow/entrypoint.sh
  - ./init_default_user.py:/ragflow/init_default_user.py
  - ./service_conf.yaml.template:/ragflow/conf/service_conf.yaml.template
  - ragflow-tiktoken:/root/.tiktoken
  - ragflow-logs:/ragflow/logs
extra_hosts:
  - "host.docker.internal:host-gateway"
entrypoint: ["/ragflow/entrypoint.sh"]
restart: unless-stopped
```

`service_conf.yaml.template` is vendored even though the upstream image ships its own. Owning it lets us add OAuth, Langfuse, or other config later by editing one file in this repo — no image rebuild, no override-merging.

**Dropped:**

- Profiles (`elasticsearch` / `infinity` / `opensearch` / `cpu` / `gpu`) — only ES+CPU.
- `kibana`, `sandbox` services.
- Multi-instance variable substitution (`${INSTANCE_ID}`, etc.).

**Kept:**

- `ragflow-tiktoken` named volume (saves redownload on every restart).
- ES heap cap `-Xms4g -Xmx8g`.
- Telemetry disable env vars (`TELEMETRY_ENABLED=false`, `RAGFLOW_ANALYTICS=false`, `DOC_INTELLIGENCE_ENDPOINT=`).

## New `.env` contract

Variables added to repo-root `.env`:

```bash
# RagFlow auto-init (read by init_default_user.py)
RAGFLOW_DEFAULT_EMAIL=muemike@gmail.com
RAGFLOW_DEFAULT_PASSWORD=<password>
RAGFLOW_DEFAULT_NICKNAME=Mike
RAGFLOW_API_KEY=ragflow-<random-32char>
RAGFLOW_DEFAULT_CHAT_MODEL=qwen3:30b-a3b-q4_K_M
RAGFLOW_DEFAULT_EMBEDDING_MODEL=bge-m3
RAGFLOW_ADDITIONAL_CHAT_MODELS=gemma4:e4b,qwen3.6:35b

# Existing
OLLAMA_BASE_URL=http://host.docker.internal:11434
TELEMETRY_ENABLED=false
RAGFLOW_ANALYTICS=false
```

`.env.example` updated with documented placeholders. Real `.env` stays gitignored.

## New `ubuntu/53_ragflow.sh` — thin launcher

```bash
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

[ -f "$REPO_ROOT/.env" ] && set -a && source "$REPO_ROOT/.env" && set +a

cd "$REPO_ROOT/ragflow"

if ! sudo ufw status | grep -q " 80 .*192.168.1.0/24"; then
  sudo ufw allow from 192.168.1.0/24 to any port 80 comment 'RagFlow LAN'
fi

docker compose up -d

for i in $(seq 1 60); do
  curl -fsS -o /dev/null http://localhost/ && break
  sleep 5
done

docker compose ps
echo "RagFlow: http://192.168.1.13"
echo "Admin: $RAGFLOW_DEFAULT_EMAIL"
```

~30 lines vs the current 190.

## What's removed

- **All UFW outbound block logic** — no `after.rules` editing, no Python regex strip/restore. Container talks to Ollama on `host.docker.internal` directly; tiktoken downloads on first run just work because outbound is allowed by default.
- **Upstream fetching** — no `fetch_if_missing`, no `.env.upstream` merge, no marker-based env layering.
- **Profile flags** — `--profile elasticsearch --profile cpu` baked into the compose file.

## Error handling

| Failure | Behavior |
|---|---|
| MySQL not ready | `init_default_user.py` retries 40 × 3s; container restarts via `restart: unless-stopped` if it exhausts retries |
| API key missing on restart | Idempotently recreated by init script |
| Ollama unreachable at init | Models still register (metadata only); chat fails at runtime, not deploy time |
| RagFlow upgrade breaks init | Init fails noisily with import errors → fix script → bump pin deliberately |

## Testing strategy

- **Pipeline test:** Add `--with-ragflow` flag to `ubuntu/test_pipeline.sh`. After dotfiles, run `53_ragflow.sh`, then assert:
  - `curl localhost/` → 200
  - `curl -H "Authorization: Bearer $RAGFLOW_API_KEY" localhost:9380/v1/dataset` → valid JSON
- **F3A itself:** `docker compose down -v && up` validates init runs cleanly on an empty DB.

## Risks

- **`v0.25.1` schema drift:** ragflow-docker last documented testing with v0.23.1. Internal Python module imports (`api.db.services.user_service`) may have changed. First deploy will surface any breakage; fix script and re-test. This is the deliberate cost of pinning latest.
- **Tiktoken on absolute first deploy:** Cache volume is empty → tiktoken downloads from `openaipublic.blob.core.windows.net`. With UFW outbound block removed, this is now trivial. Cache persists across restarts.

## Run order on F3A

```bash
bash ubuntu/50_amd_gpu.sh       # unchanged
sudo reboot
bash ubuntu/51_ollama.sh        # unchanged
bash ubuntu/52_llamacpp_vulkan.sh  # unchanged
bash ubuntu/53_ragflow.sh       # NEW thin launcher
bash ubuntu/54_openwebui.sh     # unchanged
```

For an existing deploy: `cd ~/ragflow && docker compose down -v` to wipe the old stack, then run the new `53_ragflow.sh`. The `-v` discards old volumes (DB, MinIO, ES) — a clean slate is required since the user/API-key init logic only triggers on an empty user table.

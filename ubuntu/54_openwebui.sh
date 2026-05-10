#!/bin/bash
# Open WebUI — Chat interface over llama-swap (primary) and Ollama (backup).
# Runs as a standalone Docker container (independent of RagFlow).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV_FILE="${HOME}/.env"
[ ! -f "$ENV_FILE" ] && ENV_FILE="$REPO_ROOT/.env"  # repo-side fallback
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$ENV_FILE"
  set +a
fi

CONTAINER_NAME=open-webui

# --- Remove old container if present (for idempotent re-run) ---
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Removing existing ${CONTAINER_NAME} container..."
  docker rm -f "$CONTAINER_NAME"
fi

# --- Start Open WebUI ---
# Two backends: llama-swap (PRIMARY, OpenAI-compatible at :8080) and Ollama
# (backup at :11434). Open WebUI lists models from BOTH endpoints and labels
# them by source. With Ollama service stopped on the host the Ollama
# discovery just times out silently — set ENABLE_OLLAMA_API=False to skip.
#
# HF_HUB_OFFLINE + TRANSFORMERS_OFFLINE: skip HuggingFace network calls at startup.
# Pre-register the RagFlow MCP servers as external tools. Open WebUI parses
# this JSON on startup; PersistentConfig then keeps it in the DB.
#   - Primary uses RAGFLOW_API_KEY (Mike's tenant) at port 9382.
#   - Each entry in RAGFLOW_MCP_EXTRA_INSTANCES (comma-separated
#     "name:port:apikey") becomes an additional MCP tool labelled by name.
RAGFLOW_MCP_HOST="${RAGFLOW_MCP_HOST:-http://host.docker.internal}"
TOOL_SERVERS_JSON=$(python3 - <<EOF
import json, os
servers = []
key = os.environ.get('RAGFLOW_API_KEY', '').strip()
host = os.environ.get('RAGFLOW_MCP_HOST', 'http://host.docker.internal').strip()
if key:
    servers.append({
        'url': f'{host}:9382',
        'path': '/mcp/',
        'type': 'mcp',
        'auth_type': 'bearer',
        'key': key,
        'config': {'enable': True, 'name': 'RagFlow MCP (Mike)'},
    })
extras = os.environ.get('RAGFLOW_MCP_EXTRA_INSTANCES', '').strip()
for entry in [e.strip() for e in extras.split(',') if e.strip()]:
    parts = entry.split(':', 2)
    if len(parts) == 3:
        name, port, k = parts
        servers.append({
            'url': f'{host}:{port}',
            'path': '/mcp/',
            'type': 'mcp',
            'auth_type': 'bearer',
            'key': k,
            'config': {'enable': True, 'name': f'RagFlow MCP ({name})'},
        })
print(json.dumps(servers))
EOF
)

docker run -d \
  --name "$CONTAINER_NAME" \
  --restart always \
  -p 3000:8080 \
  -e OPENAI_API_BASE_URL="http://host.docker.internal:8080/v1" \
  -e OPENAI_API_KEY="dummy" \
  -e ENABLE_OLLAMA_API=False \
  -e WEBUI_AUTH=true \
  -e HF_HUB_OFFLINE=1 \
  -e TRANSFORMERS_OFFLINE=1 \
  -e TOOL_SERVER_CONNECTIONS="$TOOL_SERVERS_JSON" \
  -v open-webui-data:/app/backend/data \
  --add-host host.docker.internal:host-gateway \
  ghcr.io/open-webui/open-webui:main

echo "Waiting for Open WebUI to start..."
timeout 60 bash -c 'until curl -s http://localhost:3000 >/dev/null 2>&1; do sleep 2; done' \
  || echo "WARNING: Open WebUI did not respond within 60 seconds — may still be starting"

docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# --- UFW: LAN access ---
if ! sudo ufw status | grep -q "3000.*192.168.1.0/24"; then
  sudo ufw allow from 192.168.1.0/24 to any port 3000 comment 'Open WebUI LAN'
  echo "UFW rule added for :3000"
fi

echo ""
echo "================================================================"
echo "Open WebUI: http://192.168.1.13:3000"
echo "Backend:    llama-swap @ http://host.docker.internal:8080/v1"
echo "Models:     qwen3-30b-a3b-q4_K_M (chat), bge-m3 (embed), qwen3-vl-8b (vision)"
echo "First visit: create admin account."
echo "================================================================"

#!/bin/bash
# RagFlow on F3A — thin launcher.
# Loads .env from repo root, opens UFW for inbound port 80 from LAN,
# runs docker compose against ragflow/ stack, waits for healthy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -f "$REPO_ROOT/.env" ]; then
  echo "ERROR: $REPO_ROOT/.env missing. Copy .env.example → .env and fill in RAGFLOW_* vars."
  exit 1
fi

# Export RAGFLOW_* and stack-secret vars so docker compose substitutes them
set -a
# shellcheck disable=SC1091
source "$REPO_ROOT/.env"
set +a

cd "$REPO_ROOT/ragflow"

# Inbound from LAN only — RagFlow UI on port 80
if command -v ufw >/dev/null 2>&1; then
  if ! sudo ufw status | grep -q " 80 .*192.168.1.0/24"; then
    sudo ufw allow from 192.168.1.0/24 to any port 80 comment 'RagFlow LAN'
  fi
fi

echo "Starting RagFlow stack (image: $(grep -E 'image: infiniflow/ragflow' docker-compose.yml | awk '{print $2}'))..."
docker compose up -d

echo "Waiting for RagFlow UI to respond (up to 10 min — first run pulls image, downloads tiktoken)..."
for i in $(seq 1 60); do
  if curl -fsS -o /dev/null http://localhost/ 2>/dev/null; then
    echo "RagFlow is up."
    break
  fi
  printf '.'
  sleep 10
done
echo

docker compose ps
echo
echo "================================================================"
echo "RagFlow:        http://192.168.1.13"
echo "Admin email:    ${RAGFLOW_DEFAULT_EMAIL:-<not set>}"
echo "API key:        ${RAGFLOW_API_KEY:+set in .env, persisted to DB}"
echo
echo "Models registered (if Ollama is reachable from container):"
echo "  chat:       ${RAGFLOW_DEFAULT_CHAT_MODEL:-<not set>}"
echo "  embedding:  ${RAGFLOW_DEFAULT_EMBEDDING_MODEL:-<not set>}"
echo "  additional: ${RAGFLOW_ADDITIONAL_CHAT_MODELS:-<none>}"
echo "================================================================"

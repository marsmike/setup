#!/bin/bash
# RagFlow on F3A — thin launcher.
# Loads .env from $HOME/.env (canonical) with repo-root fallback for back-compat.
# Opens UFW for inbound ports 80, 9382, 9383 from LAN. Runs docker compose
# against ragflow/ stack, waits for healthy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV_FILE="${HOME}/.env"
[ ! -f "$ENV_FILE" ] && ENV_FILE="$REPO_ROOT/.env"  # repo-side fallback
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: no .env at \$HOME/.env or \$REPO_ROOT/.env. Copy .env.example → ~/.env and fill in vars."
  exit 1
fi

# Export all vars so docker compose can interpolate them
set -a
# shellcheck disable=SC1091
source "$ENV_FILE"
set +a

cd "$REPO_ROOT/ragflow"

# Inbound from LAN only — RagFlow UI on port 80, MCP server on 9382
if command -v ufw >/dev/null 2>&1; then
  if ! sudo ufw status | grep -q " 80 .*192.168.1.0/24"; then
    sudo ufw allow from 192.168.1.0/24 to any port 80 comment 'RagFlow LAN'
  fi
  if ! sudo ufw status | grep -q " 9382.*192.168.1.0/24"; then
    sudo ufw allow from 192.168.1.0/24 to any port 9382 comment 'RagFlow MCP LAN'
  fi
  if ! sudo ufw status | grep -q " 9383.*192.168.1.0/24"; then
    sudo ufw allow from 192.168.1.0/24 to any port 9383 comment 'RagFlow MCP extra LAN'
  fi
fi

# One-time cleanup: remove the old DOCKER-USER outbound block from earlier
# versions of this script (private LAN, no longer needed). Idempotent.
if sudo grep -q "ragflow-outbound-block" /etc/ufw/after.rules 2>/dev/null; then
  echo "Removing legacy ragflow outbound block from /etc/ufw/after.rules..."
  sudo python3 -c "
import re
p = '/etc/ufw/after.rules'
t = open(p).read()
open(p, 'w').write(re.sub(r'\n*# BEGIN ragflow-outbound-block.*?# END ragflow-outbound-block\n*', '\n', t, flags=re.DOTALL))
"
  sudo ufw reload >/dev/null
  # ufw reload doesn't flush a live DOCKER-USER chain — do it explicitly.
  sudo iptables -F DOCKER-USER 2>/dev/null || true
  sudo iptables -A DOCKER-USER -j RETURN 2>/dev/null || true
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

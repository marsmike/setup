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

# --- Enable UFW if inactive (SSH must be allowed first) ---
if sudo ufw status | grep -q "Status: inactive"; then
  echo "Enabling UFW (allowing SSH first to avoid lockout)..."
  sudo ufw allow from 192.168.1.0/24 to any port 22 comment 'SSH LAN'
  sudo ufw --force enable
  echo "UFW enabled."
fi

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
if ! sudo ufw status | grep -q " 80 .*192.168.1.0/24"; then
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
echo "Waiting for RagFlow to become healthy (up to 2 min)..."
for i in $(seq 1 24); do
  if curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null | grep -q "200\|301\|302"; then
    echo "RagFlow is up!"
    break
  fi
  echo -n "."
  sleep 5
done
echo ""

docker compose -f docker-compose.yml ps

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

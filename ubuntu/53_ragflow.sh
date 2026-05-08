#!/bin/bash
# RagFlow — RAG-based document Q&A (Docker Compose)
# Privacy hardened: telemetry disabled, Docker outbound blocked via UFW.
set -euo pipefail

RAGFLOW_DIR="$HOME/ragflow"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAGFLOW_RAW="https://raw.githubusercontent.com/infiniflow/ragflow/main/docker"

mkdir -p "$RAGFLOW_DIR"
cd "$RAGFLOW_DIR"

# --- Fetch upstream compose files (idempotent) ---
fetch_if_missing() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "Downloading $file..."
    curl -fsSL "$RAGFLOW_RAW/$file" -o "$file"
  else
    echo "$file already present — to update, delete and re-run."
  fi
}

fetch_if_missing docker-compose.yml
fetch_if_missing docker-compose-base.yml
fetch_if_missing service_conf.yaml.template
fetch_if_missing entrypoint.sh
fetch_if_missing init.sql

# Make entrypoint executable
chmod +x entrypoint.sh 2>/dev/null || true

# --- Build .env: start from upstream defaults, then overlay our settings ---
if [ ! -f .env ]; then
  echo "Fetching upstream .env defaults..."
  curl -fsSL "$RAGFLOW_RAW/.env" -o .env.upstream
  cp .env.upstream .env
else
  echo ".env already present — preserving existing config."
fi

# Apply our privacy overrides on top (idempotent)
if ! grep -q "# === Privacy overrides from 53_ragflow.sh ===" .env; then
  echo "" >> .env
  echo "# === Privacy overrides from 53_ragflow.sh ===" >> .env
  grep -v "^#" "$SCRIPT_DIR/ragflow/ragflow.env" | grep -v "^$" >> .env
fi

# --- Copy our docker-compose override ---
cp "$SCRIPT_DIR/ragflow/docker-compose.override.yml" ./docker-compose.override.yml

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

if sudo grep -q "$MARKER" "$AFTER_RULES" 2>/dev/null; then
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
-A DOCKER-USER -d 172.16.0.0/12 -j ACCEPT
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

# --- Start RagFlow (CPU profile + elasticsearch) ---
# On first run, RagFlow downloads tiktoken data (openaipublic.blob.core.windows.net).
# Temporarily remove the DOCKER-USER outbound block from after.rules so the download
# can succeed, then restore it once the service is healthy.
# We use UFW (ufw reload) to apply/remove the rules — no direct iptables commands.

AFTER_RULES=/etc/ufw/after.rules
MARKER_BEGIN="# BEGIN ragflow-outbound-block"
MARKER_END="# END ragflow-outbound-block"

# Remove outbound block temporarily (strip between markers + blank line before)
echo "Temporarily removing Docker outbound block for first-run initialisation..."
sudo python3 - "$AFTER_RULES" <<'PYEOF'
import sys, re
path = sys.argv[1]
text = open(path).read()
# Remove blank line + block between markers (inclusive)
cleaned = re.sub(r'\n# BEGIN ragflow-outbound-block.*?# END ragflow-outbound-block\n',
                 '', text, flags=re.DOTALL)
open(path, 'w').write(cleaned)
PYEOF
sudo ufw reload

echo "Starting RagFlow stack..."
docker compose \
  -f docker-compose.yml \
  -f docker-compose.override.yml \
  --env-file .env \
  --profile elasticsearch \
  --profile cpu \
  up -d

echo ""
echo "Waiting for RagFlow to become healthy (up to 10 min — first run downloads tiktoken data)..."
RAGFLOW_UP=false
for i in $(seq 1 60); do
  if curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null | grep -q "200\|301\|302"; then
    RAGFLOW_UP=true
    echo "RagFlow is up!"
    break
  fi
  echo -n "."
  sleep 10
done
echo ""

# Restore the DOCKER-USER outbound block via UFW
echo "Restoring Docker outbound block..."
cat <<'IPTABLES' | sudo tee -a "$AFTER_RULES" > /dev/null

# BEGIN ragflow-outbound-block
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A DOCKER-USER -d 192.168.1.0/24 -j ACCEPT
-A DOCKER-USER -d 127.0.0.0/8 -j ACCEPT
-A DOCKER-USER -d 172.16.0.0/12 -j ACCEPT
-A DOCKER-USER -j DROP
-A DOCKER-USER -j RETURN
COMMIT
# END ragflow-outbound-block
IPTABLES
sudo ufw reload
echo "Docker outbound block restored."

if [ "$RAGFLOW_UP" = false ]; then
  echo "WARNING: RagFlow did not respond within timeout. Check: docker logs ragflow-ragflow-cpu-1"
fi
echo ""

docker compose -f docker-compose.yml --profile elasticsearch --profile cpu ps

echo ""
echo "================================================================"
echo "RagFlow: http://192.168.1.13"
echo "First visit: create admin account."
echo ""
echo "Configure LLM backend in RagFlow UI:"
echo "  Settings → Model Providers → Add → Ollama"
echo "  Base URL: http://host.docker.internal:11434"
echo "  Models: qwen3:30b-a3b-q4_K_M, qwen3.6:35b, gemma4:e4b"
echo ""
echo "Configure embedding model:"
echo "  Settings → Model Providers → Add → Ollama → bge-m3"
echo "================================================================"

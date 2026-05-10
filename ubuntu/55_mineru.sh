#!/bin/bash
# MinerU API server on F3A — thin launcher.
# Builds the CPU-only image from mineru/Dockerfile and starts the service
# alongside the RagFlow stack.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV_FILE="${HOME}/.env"
[ ! -f "$ENV_FILE" ] && ENV_FILE="$REPO_ROOT/.env"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$ENV_FILE"
  set +a
fi

IMAGE_TAG="${MINERU_IMAGE:-mineru-cpu:3.1.11}"

echo "=== Building $IMAGE_TAG (first run pulls torch CPU + 3-5 GB pipeline models) ==="
docker build -t "$IMAGE_TAG" "$REPO_ROOT/mineru/"

echo
echo "=== Starting mineru-api service via the ragflow compose stack ==="
cd "$REPO_ROOT/ragflow"
docker compose up -d mineru-api

echo
echo "=== Waiting for /openapi.json (model load can take ~60s after start) ==="
for i in $(seq 1 60); do
  if curl -fsS -o /dev/null --max-time 3 "http://localhost:${MINERU_PORT:-8100}/openapi.json" 2>/dev/null; then
    echo "  mineru-api is up."
    break
  fi
  printf '.'
  sleep 5
done
echo

docker compose ps mineru-api
echo
echo "================================================================"
echo "MinerU API:  http://192.168.1.13:${MINERU_PORT:-8100}"
echo "Internal:    http://mineru-api:8000  (set MINERU_APISERVER to this)"
echo
echo "Smoke test:"
echo "  curl -s -X POST http://localhost:${MINERU_PORT:-8100}/file_parse \\"
echo "    -F 'files=@<your.pdf>;type=application/pdf' \\"
echo "    -F 'backend=pipeline' -F 'parse_method=auto' \\"
echo "    -F 'return_md=true' -F 'response_format_zip=true' -o /tmp/out.zip"
echo "================================================================"

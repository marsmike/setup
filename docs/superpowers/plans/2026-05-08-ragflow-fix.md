# RagFlow Fix & Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fragile UFW-dance + upstream-fetch RagFlow setup with a vendored, pinned, auto-initialised stack at `setup/ragflow/`, drawing on the architecture of `~/work/ragflow-docker`.

**Architecture:** Top-level `setup/ragflow/` directory holds a self-contained Docker Compose stack pinned to `infiniflow/ragflow:v0.25.1`. A custom `entrypoint.sh` runs `init_default_user.py` after server start to auto-create one admin user, persist a stable API key, and register Ollama as the LLM provider with `bge-m3` + `qwen3:30b-a3b-q4_K_M` + `gemma4:e4b`. `ubuntu/53_ragflow.sh` becomes a ~30-line launcher that sources `.env` and runs `docker compose up -d`. Drops the UFW outbound block entirely (private LAN, no telemetry-firewall needed).

**Tech Stack:** Docker Compose, Python 3 (RagFlow internal `api.db.services.*`), bash, MySQL 8, Elasticsearch 8, MinIO, Redis (Valkey).

**Spec:** `docs/superpowers/specs/2026-05-08-ragflow-fix-design.md`

**Reference:** `~/work/ragflow-docker/` (multi-instance Bosch deployment — single source of truth for entrypoint + init script patterns).

---

## File Structure

Files this plan creates or modifies:

| File | Action | Purpose |
|---|---|---|
| `ragflow/README.md` | create | Overview, run order, troubleshooting |
| `ragflow/docker-compose.yml` | create | Self-contained, pinned RagFlow + ES + MySQL + MinIO + Redis |
| `ragflow/entrypoint.sh` | create | Slim startup: envsubst conf, start nginx + server + executor + init |
| `ragflow/init_default_user.py` | create | Auto-create admin user, API key, Ollama factory + 3 models |
| `ragflow/service_conf.yaml.template` | create | Vendored config template processed by entrypoint |
| `ragflow/init.sql` | create | MySQL DB initialiser (verbatim from upstream) |
| `.env.example` | modify | Document new RAGFLOW_* variables |
| `ubuntu/53_ragflow.sh` | rewrite | Thin launcher (~30 lines) |
| `ubuntu/ragflow/` | delete | Moved to top-level |
| `CLAUDE.md` | modify | Reference new ragflow/ location |

---

## Task 1: Scaffold `ragflow/` directory + README

**Files:**
- Create: `ragflow/README.md`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p /Users/mike/work/setup/ragflow
```

- [ ] **Step 2: Write `ragflow/README.md`**

```markdown
# RagFlow Stack (F3A)

Self-contained Docker Compose stack for RagFlow, pinned to a known image
version and auto-initialised on first boot. Intended for single-machine,
single-user deployment on a private LAN (the F3A MiniPC).

## Run order

```bash
# From repo root, with .env populated (see .env.example):
bash ubuntu/53_ragflow.sh
```

## What the stack does on first boot

1. MySQL, MinIO, Redis, Elasticsearch start (named volumes for persistence).
2. RagFlow image starts with our mounted `entrypoint.sh`:
   - Renders `service_conf.yaml` from the template via env-var substitution.
   - Starts nginx + ragflow_server + one task_executor.
   - After 60s (server up + DB schema created), runs `init_default_user.py`:
     - Creates admin user from `RAGFLOW_DEFAULT_EMAIL` / `RAGFLOW_DEFAULT_PASSWORD`.
     - Persists `RAGFLOW_API_KEY` to the `api_token` table (idempotent).
     - Registers Ollama factory at `OLLAMA_BASE_URL`.
     - Adds `RAGFLOW_DEFAULT_CHAT_MODEL`, `RAGFLOW_DEFAULT_EMBEDDING_MODEL`,
       and `RAGFLOW_ADDITIONAL_CHAT_MODELS` to the user's model list.

## Files

- `docker-compose.yml` — vendored, pinned (`infiniflow/ragflow:v0.25.1`).
- `entrypoint.sh` — slim startup, mounted into the container.
- `init_default_user.py` — auto-init logic, mounted into the container.
- `service_conf.yaml.template` — bash-style ${VAR} placeholders.
- `init.sql` — MySQL bootstrap.

## Reset

To wipe state and re-run init from scratch:

```bash
cd ~/work/setup/ragflow
docker compose down -v
bash ../ubuntu/53_ragflow.sh
```

## Troubleshooting

Logs:

```bash
docker compose logs -f ragflow
docker compose logs -f mysql
```

Init script failures show in `ragflow` logs. The init script is idempotent —
on schema drift after a RagFlow version bump, fix the script and bump the
image pin in `docker-compose.yml` deliberately.
```

- [ ] **Step 3: Verify file written**

```bash
ls -la /Users/mike/work/setup/ragflow/README.md
```

Expected: file exists, ~1.5 KB.

- [ ] **Step 4: Commit**

```bash
cd /Users/mike/work/setup
git add ragflow/README.md
git commit -m "feat(ragflow): scaffold top-level ragflow/ directory with README"
```

---

## Task 2: Write `ragflow/docker-compose.yml` (vendored, pinned, slim)

**Files:**
- Create: `ragflow/docker-compose.yml`

- [ ] **Step 1: Write the file**

```yaml
# Self-contained RagFlow stack — pinned to v0.25.1.
# Drops profiles, extra services, and multi-instance machinery from upstream.

services:
  ragflow:
    image: infiniflow/ragflow:v0.25.1
    container_name: ragflow-server
    depends_on:
      mysql:
        condition: service_healthy
      es01:
        condition: service_started
      minio:
        condition: service_started
      redis:
        condition: service_started
    entrypoint: ["/ragflow/entrypoint.sh"]
    ports:
      - "${SVR_HTTP_PORT:-9380}:9380"
      - "80:80"
    env_file: ../.env
    environment:
      - TZ=${TIMEZONE:-Europe/Berlin}
      - TELEMETRY_ENABLED=false
      - RAGFLOW_ANALYTICS=false
      - DOC_INTELLIGENCE_ENDPOINT=
      - LLM_TIMEOUT_SECONDS=120
      - TIKTOKEN_CACHE_DIR=/root/.tiktoken
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - ./entrypoint.sh:/ragflow/entrypoint.sh
      - ./init_default_user.py:/ragflow/init_default_user.py
      - ./service_conf.yaml.template:/ragflow/conf/service_conf.yaml.template
      - ragflow-logs:/ragflow/logs
      - ragflow-tiktoken:/root/.tiktoken
    networks:
      - ragflow
    restart: unless-stopped

  mysql:
    image: mysql:8.0.39
    container_name: ragflow-mysql
    env_file: ../.env
    environment:
      - MYSQL_ROOT_PASSWORD=${MYSQL_PASSWORD:-infini_rag_flow}
      - TZ=${TIMEZONE:-Europe/Berlin}
    command: >
      --max_connections=1000
      --character-set-server=utf8mb4
      --collation-server=utf8mb4_unicode_ci
      --default-authentication-plugin=mysql_native_password
      --tls_version=TLSv1.2,TLSv1.3
      --init-file=/data/application/init.sql
      --binlog_expire_logs_seconds=604800
    ports:
      - "${MYSQL_PORT:-5455}:3306"
    volumes:
      - mysql_data:/var/lib/mysql
      - ./init.sql:/data/application/init.sql
    networks:
      - ragflow
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-uroot", "-p${MYSQL_PASSWORD:-infini_rag_flow}"]
      interval: 10s
      timeout: 10s
      retries: 30
    restart: unless-stopped

  es01:
    image: elasticsearch:8.11.3
    container_name: ragflow-es01
    env_file: ../.env
    environment:
      - node.name=es01
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD:-infini_rag_flow}
      - bootstrap.memory_lock=false
      - discovery.type=single-node
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=false
      - xpack.security.transport.ssl.enabled=false
      - cluster.routing.allocation.disk.watermark.low=5gb
      - cluster.routing.allocation.disk.watermark.high=3gb
      - cluster.routing.allocation.disk.watermark.flood_stage=2gb
      - ES_JAVA_OPTS=-Xms4g -Xmx8g
      - TZ=${TIMEZONE:-Europe/Berlin}
    ports:
      - "${ES_PORT:-1200}:9200"
    volumes:
      - esdata:/usr/share/elasticsearch/data
    ulimits:
      memlock:
        soft: -1
        hard: -1
    networks:
      - ragflow
    restart: unless-stopped

  minio:
    image: quay.io/minio/minio:RELEASE.2025-06-13T11-33-47Z
    container_name: ragflow-minio
    command: server --console-address ":9001" /data
    env_file: ../.env
    environment:
      - MINIO_ROOT_USER=${MINIO_USER:-rag_flow}
      - MINIO_ROOT_PASSWORD=${MINIO_PASSWORD:-infini_rag_flow}
      - TZ=${TIMEZONE:-Europe/Berlin}
    ports:
      - "${MINIO_PORT:-9000}:9000"
      - "${MINIO_CONSOLE_PORT:-9001}:9001"
    volumes:
      - minio_data:/data
    networks:
      - ragflow
    restart: unless-stopped

  redis:
    image: valkey/valkey:8
    container_name: ragflow-redis
    command: valkey-server --requirepass ${REDIS_PASSWORD:-infini_rag_flow} --maxmemory 128mb --maxmemory-policy allkeys-lru
    env_file: ../.env
    ports:
      - "${REDIS_PORT:-6379}:6379"
    volumes:
      - redis_data:/data
    networks:
      - ragflow
    restart: unless-stopped

volumes:
  mysql_data:
  esdata:
  minio_data:
  redis_data:
  ragflow-logs:
  ragflow-tiktoken:

networks:
  ragflow:
    driver: bridge
```

- [ ] **Step 2: Validate compose syntax**

```bash
cd /Users/mike/work/setup/ragflow
docker compose config --quiet 2>&1
```

Expected: no output (valid). The command will warn about missing `.env` since env_file points to `../.env` — that's fine; if `.env` doesn't yet have `MYSQL_PASSWORD` etc., compose substitutes the defaults.

If the user has not yet copied `.env.example` to `.env`, run:
```bash
[ -f /Users/mike/work/setup/.env ] || echo "WARN: .env missing — defaults will be used"
```

- [ ] **Step 3: Commit**

```bash
cd /Users/mike/work/setup
git add ragflow/docker-compose.yml
git commit -m "feat(ragflow): vendor pinned docker-compose.yml (v0.25.1)"
```

---

## Task 3: Write `ragflow/service_conf.yaml.template`

**Files:**
- Create: `ragflow/service_conf.yaml.template`

This is a slim version of upstream — drops Langfuse, OAuth, OSS, Postgres sections. Add them later if needed.

- [ ] **Step 1: Write the file**

```yaml
ragflow:
  host: ${RAGFLOW_HOST:-0.0.0.0}
  http_port: 9380
admin:
  host: ${RAGFLOW_HOST:-0.0.0.0}
  http_port: 9381
mysql:
  name: '${MYSQL_DBNAME:-rag_flow}'
  user: '${MYSQL_USER:-root}'
  password: '${MYSQL_PASSWORD:-infini_rag_flow}'
  host: '${MYSQL_HOST:-mysql}'
  port: 3306
  max_connections: 900
  stale_timeout: 300
  max_allowed_packet: ${MYSQL_MAX_PACKET:-1073741824}
minio:
  user: '${MINIO_USER:-rag_flow}'
  password: '${MINIO_PASSWORD:-infini_rag_flow}'
  host: '${MINIO_HOST:-minio}:9000'
es:
  hosts: 'http://${ES_HOST:-es01}:9200'
  username: '${ES_USER:-elastic}'
  password: '${ELASTIC_PASSWORD:-infini_rag_flow}'
redis:
  db: 1
  password: '${REDIS_PASSWORD:-infini_rag_flow}'
  host: '${REDIS_HOST:-redis}:6379'
```

- [ ] **Step 2: Verify file written**

```bash
ls -la /Users/mike/work/setup/ragflow/service_conf.yaml.template
```

Expected: file exists, ~700 bytes.

- [ ] **Step 3: Commit**

```bash
cd /Users/mike/work/setup
git add ragflow/service_conf.yaml.template
git commit -m "feat(ragflow): vendor slim service_conf.yaml.template"
```

---

## Task 4: Write `ragflow/init.sql`

**Files:**
- Create: `ragflow/init.sql`

Verbatim from upstream — needed by MySQL `--init-file`.

- [ ] **Step 1: Write the file**

```sql
CREATE DATABASE IF NOT EXISTS rag_flow;
```

- [ ] **Step 2: Commit**

```bash
cd /Users/mike/work/setup
git add ragflow/init.sql
git commit -m "feat(ragflow): vendor init.sql for MySQL bootstrap"
```

---

## Task 5: Write `ragflow/entrypoint.sh`

**Files:**
- Create: `ragflow/entrypoint.sh`

Slimmed from `~/work/ragflow-docker/entrypoint.sh`. No flag parsing, no MCP/admin, single executor.

- [ ] **Step 1: Write the file**

```bash
#!/usr/bin/env bash
# Slim entrypoint for RagFlow on F3A — single-instance, single-executor.
# Mounted into the upstream image as /ragflow/entrypoint.sh via docker-compose.

set -e

# -----------------------------------------------------------------------------
# Render service_conf.yaml from template (bash-style ${VAR:-default} expansion)
# -----------------------------------------------------------------------------
CONF_DIR="/ragflow/conf"
TEMPLATE_FILE="${CONF_DIR}/service_conf.yaml.template"
CONF_FILE="${CONF_DIR}/service_conf.yaml"

rm -f "${CONF_FILE}"
while IFS= read -r line || [[ -n "$line" ]]; do
    eval "echo \"$line\"" >> "${CONF_FILE}"
done < "${TEMPLATE_FILE}"

export LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu/"
export PYTHONPATH="/ragflow/"
PY=python3

# -----------------------------------------------------------------------------
# Background init: wait for server to bring up DB schema, then create user etc.
# -----------------------------------------------------------------------------
function init_default_user() {
    echo "[entrypoint] waiting 60s for ragflow_server to initialise DB schema..."
    sleep 60
    if [ -f "/ragflow/init_default_user.py" ]; then
        echo "[entrypoint] running init_default_user.py..."
        cd /ragflow && PYTHONPATH="/ragflow/" "$PY" /ragflow/init_default_user.py \
            || echo "[entrypoint] WARNING: init_default_user.py exited non-zero — continuing"
    fi
}

function task_exe() {
    local consumer_id="$1"
    local host_id="$2"
    JEMALLOC_PATH="$(pkg-config --variable=libdir jemalloc)/libjemalloc.so"
    while true; do
        LD_PRELOAD="$JEMALLOC_PATH" "$PY" rag/svr/task_executor.py "${host_id}_${consumer_id}"
    done
}

# -----------------------------------------------------------------------------
# Start nginx, ragflow_server, init (background), one task executor
# -----------------------------------------------------------------------------
HOST_ID="$(hostname)"
[ ${#HOST_ID} -gt 32 ] && HOST_ID="$(echo -n "$HOST_ID" | md5sum | cut -d ' ' -f 1)"

echo "[entrypoint] starting nginx..."
/usr/sbin/nginx

echo "[entrypoint] starting ragflow_server (with restart loop)..."
init_default_user &
while true; do
    "$PY" api/ragflow_server.py
done &

echo "[entrypoint] starting one task_executor on host '${HOST_ID}'..."
task_exe 0 "${HOST_ID}" &

wait
```

- [ ] **Step 2: Make executable**

```bash
chmod +x /Users/mike/work/setup/ragflow/entrypoint.sh
```

- [ ] **Step 3: Validate bash syntax**

```bash
bash -n /Users/mike/work/setup/ragflow/entrypoint.sh
```

Expected: no output (valid). Exits non-zero on syntax errors.

- [ ] **Step 4: Commit**

```bash
cd /Users/mike/work/setup
git add ragflow/entrypoint.sh
git commit -m "feat(ragflow): slim entrypoint — single user, single executor, no MCP"
```

---

## Task 6: Write `ragflow/init_default_user.py`

**Files:**
- Create: `ragflow/init_default_user.py`

Slimmed port of `~/work/ragflow-docker/init_default_user.py`. Single user. Ollama-only. API-key persistence is idempotent.

- [ ] **Step 1: Write the file**

```python
#!/usr/bin/env python3
"""
Initialise RagFlow on first boot:
- Create one admin user from RAGFLOW_DEFAULT_EMAIL / RAGFLOW_DEFAULT_PASSWORD.
- Register Ollama as LLM factory + add chat/embedding models from env vars.
- Persist a stable API key from RAGFLOW_API_KEY (idempotent every boot).

Imports RagFlow internals (api.db.services.*) — runs INSIDE the container.
"""
import os
import sys
import logging
import time
import uuid
import base64

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)
sys.path.insert(0, '/ragflow')


def get_uuid():
    return uuid.uuid1().hex


def wait_for_database(max_retries=40, retry_delay=3):
    """Block until MySQL is up AND ragflow_server has created the schema."""
    try:
        from api.db.db_models import DB
    except ImportError:
        logger.error("Cannot import DB module — PYTHONPATH wrong?")
        return False

    logger.info(f"Waiting for database (max {max_retries} attempts, {retry_delay}s apart)...")
    for attempt in range(max_retries):
        try:
            with DB.connection_context():
                DB.execute_sql('SELECT COUNT(*) FROM user')
            logger.info("Database ready.")
            return True
        except Exception as e:
            logger.warning(f"DB not ready ({attempt + 1}/{max_retries}): {e}")
            time.sleep(retry_delay)
    logger.error("Database never became ready.")
    return False


def add_ollama_models(tenant_id):
    """Register Ollama factory entries in tenant_llm for this tenant."""
    try:
        from api.db.services.tenant_llm_service import TenantLLMService
    except ImportError as e:
        logger.error(f"Cannot import TenantLLMService: {e}")
        return False

    ollama_base = os.environ.get('OLLAMA_BASE_URL', 'http://host.docker.internal:11434').strip()
    chat_model = os.environ.get('RAGFLOW_DEFAULT_CHAT_MODEL', '').strip()
    embedding_model = os.environ.get('RAGFLOW_DEFAULT_EMBEDDING_MODEL', '').strip()
    additional = os.environ.get('RAGFLOW_ADDITIONAL_CHAT_MODELS', '').strip()

    models = []

    if chat_model:
        models.append({
            "tenant_id": tenant_id,
            "llm_factory": "Ollama",
            "model_type": "chat",
            "llm_name": chat_model,
            "api_key": "",
            "api_base": ollama_base,
            "max_tokens": 0,
            "used_tokens": 0,
        })
        logger.info(f"  + chat: {chat_model} (Ollama)")

    if additional:
        for name in [m.strip() for m in additional.split(',') if m.strip()]:
            models.append({
                "tenant_id": tenant_id,
                "llm_factory": "Ollama",
                "model_type": "chat",
                "llm_name": name,
                "api_key": "",
                "api_base": ollama_base,
                "max_tokens": 0,
                "used_tokens": 0,
            })
            logger.info(f"  + chat: {name} (Ollama)")

    if embedding_model:
        # max_tokens=8192 is critical — 0 truncates input to empty string
        # (see ragflow-docker CLAUDE.md "Critical fix" note).
        models.append({
            "tenant_id": tenant_id,
            "llm_factory": "Ollama",
            "model_type": "embedding",
            "llm_name": embedding_model,
            "api_key": "",
            "api_base": ollama_base,
            "max_tokens": 8192,
            "used_tokens": 0,
        })
        logger.info(f"  + embedding: {embedding_model} (Ollama, max_tokens=8192)")

    if not models:
        logger.info("No Ollama models configured via env — skipping.")
        return True

    try:
        if not TenantLLMService.insert_many(models):
            raise Exception("TenantLLMService.insert_many() returned False")
        logger.info(f"Registered {len(models)} Ollama model(s) for tenant {tenant_id}")
        return True
    except Exception as e:
        logger.error(f"Failed to register Ollama models: {e}")
        return False


def create_api_key(tenant_id):
    """Persist RAGFLOW_API_KEY to api_token table. Idempotent."""
    api_key = os.environ.get('RAGFLOW_API_KEY', '').strip()
    if not api_key:
        logger.info("RAGFLOW_API_KEY not set — skipping API key creation.")
        return True

    try:
        from api.db.services.api_service import APITokenService
        from api.db.db_models import DB
    except ImportError as e:
        logger.warning(f"Cannot import APITokenService: {e}")
        return True

    try:
        with DB.connection_context():
            existing = APITokenService.query(tenant_id=tenant_id, token=api_key)
            if existing:
                logger.info(f"API key already in DB for tenant {tenant_id} — leaving alone.")
                return True

        if not APITokenService.save(
            tenant_id=tenant_id,
            token=api_key,
            dialog_id=None,
            source="none",
            beta=None,
        ):
            raise Exception("APITokenService.save() returned False")
        logger.info(f"Persisted API key for tenant {tenant_id}.")
        return True
    except Exception as e:
        logger.error(f"Failed to create API key: {e}")
        return False


def create_default_user():
    """Create one admin user if none exist; ensure API key always exists."""
    try:
        from api.db.services.user_service import (
            UserService, TenantService, UserTenantService,
        )
        from api.db.services.file_service import FileService
        from api.db import UserTenantRole, FileType
        from api import settings
    except ImportError as e:
        logger.error(f"Cannot import RagFlow modules: {e}")
        return False

    email = os.environ.get('RAGFLOW_DEFAULT_EMAIL', '').strip()
    password = os.environ.get('RAGFLOW_DEFAULT_PASSWORD', '').strip()
    nickname = os.environ.get('RAGFLOW_DEFAULT_NICKNAME', 'Admin').strip()

    if not email or not password:
        logger.error("RAGFLOW_DEFAULT_EMAIL or RAGFLOW_DEFAULT_PASSWORD not set in .env")
        return False

    try:
        users = UserService.get_all_users()
    except Exception as e:
        logger.error(f"Cannot read users table: {e}")
        return False

    if users:
        logger.info(f"Found {len(users)} existing user(s) — skipping creation.")
        # Idempotent re-check of API key on every boot
        first = users[0]
        return create_api_key(first.id)

    logger.info(f"No users found. Creating admin user {email}...")
    user_id = get_uuid()
    pw_b64 = base64.b64encode(password.encode()).decode()

    chat_model = os.environ.get('RAGFLOW_DEFAULT_CHAT_MODEL', '').strip()
    embedding_model = os.environ.get('RAGFLOW_DEFAULT_EMBEDDING_MODEL', '').strip()

    user = {
        "id": user_id,
        "email": email,
        "nickname": nickname,
        "password": pw_b64,
        "status": 1,
        "is_superuser": True,
        "login_channel": "password",
    }
    tenant = {
        "id": user_id,
        "name": f"{nickname}'s Kingdom",
        # tenant.llm_id format: "model_name@factory_name"
        "llm_id": f"{chat_model}@Ollama" if chat_model else "",
        "embd_id": f"{embedding_model}@Ollama" if embedding_model else "",
        "asr_id": "",
        "img2txt_id": "",
        "rerank_id": "",
        "parser_ids": getattr(settings, 'PARSERS', '') or
            "naive:General,qa:Q&A,resume:Resume,manual:Manual,table:Table,"
            "paper:Paper,book:Book,laws:Laws,presentation:Presentation,"
            "picture:Picture,one:One,audio:Audio,email:Email,tag:Tag",
    }
    user_tenant = {
        "tenant_id": user_id,
        "user_id": user_id,
        "invited_by": user_id,
        "role": UserTenantRole.OWNER,
    }
    file_id = get_uuid()
    root_folder = {
        "id": file_id,
        "parent_id": file_id,
        "tenant_id": user_id,
        "created_by": user_id,
        "name": "/",
        "type": FileType.FOLDER.value,
        "size": 0,
        "location": "",
    }

    try:
        if not UserService.save(**user):
            raise Exception("UserService.save() returned False")
        if not TenantService.insert(**tenant):
            raise Exception("TenantService.insert() failed")
        if not UserTenantService.insert(**user_tenant):
            raise Exception("UserTenantService.insert() failed")
        if not FileService.insert(root_folder):
            raise Exception("FileService.insert() failed")
        logger.info(f"Created user {email}")
    except Exception as e:
        logger.error(f"User creation failed: {e}", exc_info=True)
        return False

    if not add_ollama_models(user_id):
        logger.warning("Ollama model registration failed — user can add via UI.")
    if not create_api_key(user_id):
        logger.warning("API key creation failed — user can create via UI.")

    logger.warning(f"Admin user is {email} — change password via UI at first login if desired.")
    return True


def main():
    logger.info("=" * 60)
    logger.info("RagFlow auto-init")
    logger.info("=" * 60)
    if not wait_for_database():
        sys.exit(1)
    if create_default_user():
        sys.exit(0)
    sys.exit(1)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Validate Python syntax**

```bash
python3 -m py_compile /Users/mike/work/setup/ragflow/init_default_user.py
```

Expected: no output (valid). Exits non-zero on syntax errors.

- [ ] **Step 3: Commit**

```bash
cd /Users/mike/work/setup
git add ragflow/init_default_user.py
git commit -m "feat(ragflow): port init_default_user.py for Ollama single-user"
```

---

## Task 7: Update `.env.example` with new RAGFLOW_* vars

**Files:**
- Modify: `.env.example`

Add the new auto-init variables. Replace the existing placeholder block at the bottom.

- [ ] **Step 1: Edit the file**

Replace this block at the end of `.env.example`:

```
# RagFlow — generated after first login to http://192.168.1.13 → Settings → API
# Used by other services to authenticate RagFlow API calls.
# RAGFLOW_API_KEY=ragflow-...
```

…with this:

```
# ── RagFlow ───────────────────────────────────────────────────────────────────
#
# All variables below are read by ragflow/init_default_user.py inside the
# container on first boot. Re-running with a different email creates no new
# user (init only fires when the user table is empty); to start over:
#   cd ragflow && docker compose down -v && cd .. && bash ubuntu/53_ragflow.sh
#
# Admin login auto-created on first boot
RAGFLOW_DEFAULT_EMAIL=
RAGFLOW_DEFAULT_PASSWORD=
RAGFLOW_DEFAULT_NICKNAME=Mike

# Stable API key — idempotently persisted to DB on every boot.
# Generate any random string (the value is what RagFlow stores; format optional):
#   echo "ragflow-$(openssl rand -hex 16)"
RAGFLOW_API_KEY=

# Ollama models registered on first boot (must already be pulled on the host).
OLLAMA_BASE_URL=http://host.docker.internal:11434
RAGFLOW_DEFAULT_CHAT_MODEL=qwen3:30b-a3b-q4_K_M
RAGFLOW_DEFAULT_EMBEDDING_MODEL=bge-m3
RAGFLOW_ADDITIONAL_CHAT_MODELS=gemma4:e4b,qwen3.6:35b

# Stack secrets — change before deploying. Defaults match upstream RagFlow.
MYSQL_PASSWORD=infini_rag_flow
ELASTIC_PASSWORD=infini_rag_flow
MINIO_USER=rag_flow
MINIO_PASSWORD=infini_rag_flow
REDIS_PASSWORD=infini_rag_flow
TIMEZONE=Europe/Berlin
```

Use the Edit tool to replace exactly:

**old_string:**
```
# RagFlow — generated after first login to http://192.168.1.13 → Settings → API
# Used by other services to authenticate RagFlow API calls.
# RAGFLOW_API_KEY=ragflow-...
```

**new_string:**
```
# ── RagFlow ───────────────────────────────────────────────────────────────────
#
# All variables below are read by ragflow/init_default_user.py inside the
# container on first boot. Re-running with a different email creates no new
# user (init only fires when the user table is empty); to start over:
#   cd ragflow && docker compose down -v && cd .. && bash ubuntu/53_ragflow.sh
#
# Admin login auto-created on first boot
RAGFLOW_DEFAULT_EMAIL=
RAGFLOW_DEFAULT_PASSWORD=
RAGFLOW_DEFAULT_NICKNAME=Mike

# Stable API key — idempotently persisted to DB on every boot.
# Generate any random string (the value is what RagFlow stores; format optional):
#   echo "ragflow-$(openssl rand -hex 16)"
RAGFLOW_API_KEY=

# Ollama models registered on first boot (must already be pulled on the host).
OLLAMA_BASE_URL=http://host.docker.internal:11434
RAGFLOW_DEFAULT_CHAT_MODEL=qwen3:30b-a3b-q4_K_M
RAGFLOW_DEFAULT_EMBEDDING_MODEL=bge-m3
RAGFLOW_ADDITIONAL_CHAT_MODELS=gemma4:e4b,qwen3.6:35b

# Stack secrets — change before deploying. Defaults match upstream RagFlow.
MYSQL_PASSWORD=infini_rag_flow
ELASTIC_PASSWORD=infini_rag_flow
MINIO_USER=rag_flow
MINIO_PASSWORD=infini_rag_flow
REDIS_PASSWORD=infini_rag_flow
TIMEZONE=Europe/Berlin
```

- [ ] **Step 2: Verify**

```bash
grep -c "RAGFLOW_DEFAULT_EMAIL\|RAGFLOW_DEFAULT_CHAT_MODEL\|MYSQL_PASSWORD" /Users/mike/work/setup/.env.example
```

Expected: 3.

- [ ] **Step 3: Commit**

```bash
cd /Users/mike/work/setup
git add .env.example
git commit -m "docs(env): document RAGFLOW_* auto-init vars in .env.example"
```

---

## Task 8: Replace `ubuntu/53_ragflow.sh` with thin launcher

**Files:**
- Rewrite: `ubuntu/53_ragflow.sh`

Old script is ~190 lines with UFW dance. New one is ~35 lines.

- [ ] **Step 1: Overwrite the file**

```bash
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
```

- [ ] **Step 2: Validate bash syntax**

```bash
bash -n /Users/mike/work/setup/ubuntu/53_ragflow.sh
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
cd /Users/mike/work/setup
git add ubuntu/53_ragflow.sh
git commit -m "refactor(ragflow): rewrite 53_ragflow.sh as thin launcher (no UFW dance)"
```

---

## Task 9: Delete old `ubuntu/ragflow/` subdirectory

**Files:**
- Delete: `ubuntu/ragflow/docker-compose.override.yml`
- Delete: `ubuntu/ragflow/ragflow.env`
- Delete: `ubuntu/ragflow/` (the directory)

- [ ] **Step 1: Remove the files**

```bash
cd /Users/mike/work/setup
git rm -r ubuntu/ragflow/
```

- [ ] **Step 2: Verify**

```bash
ls /Users/mike/work/setup/ubuntu/ragflow 2>&1
```

Expected: `ls: cannot access … No such file or directory`.

- [ ] **Step 3: Commit**

```bash
cd /Users/mike/work/setup
git commit -m "refactor(ragflow): remove ubuntu/ragflow/ — moved to top-level"
```

---

## Task 10: Update `CLAUDE.md` to reference new layout

**Files:**
- Modify: `CLAUDE.md`

The current CLAUDE.md mentions `ubuntu/ragflow` indirectly. Add a short paragraph about the new top-level `ragflow/`.

- [ ] **Step 1: Read the current CLAUDE.md**

```bash
cat /Users/mike/work/setup/CLAUDE.md | head -100
```

- [ ] **Step 2: Insert a new section before "## Proxmox"**

Use the Edit tool to insert this block immediately before the line `## Proxmox`:

**old_string:**
```
## Proxmox
```

**new_string:**
```
## RagFlow

Self-contained stack lives at `ragflow/` (top-level, mirrors `proxmox/`):
pinned `infiniflow/ragflow:v0.25.1` Docker image, custom entrypoint, and
a Python init script that auto-creates one admin user, persists a stable
`RAGFLOW_API_KEY`, and registers Ollama as the LLM provider on first boot.

- Run from F3A: `bash ubuntu/53_ragflow.sh` (thin launcher).
- Variables read from repo-root `.env` (see `.env.example` for the full list).
- Reset state: `cd ragflow && docker compose down -v`.
- Inspired by `~/work/ragflow-docker` (multi-instance Bosch deployment) but
  trimmed for single-user, Ollama-only, private-LAN deployment. No UFW
  outbound block — F3A is on a private LAN.

## Proxmox
```

- [ ] **Step 3: Commit**

```bash
cd /Users/mike/work/setup
git add CLAUDE.md
git commit -m "docs(claude.md): document new ragflow/ top-level layout"
```

---

## Task 11: Local validation — `docker compose config`

**Files:**
- (no file changes — validation only)

- [ ] **Step 1: Run config validation**

```bash
cd /Users/mike/work/setup/ragflow
docker compose config --quiet
echo "exit code: $?"
```

Expected: exit code 0, possibly with warnings about substitution defaults if `.env` is incomplete. Substitution warnings are OK.

- [ ] **Step 2: List the resolved services**

```bash
docker compose config --services
```

Expected output (any order):
```
ragflow
mysql
es01
minio
redis
```

- [ ] **Step 3: Verify image pin**

```bash
docker compose config | grep -E "^\s+image:" | sort
```

Expected to include:
```
    image: infiniflow/ragflow:v0.25.1
    image: mysql:8.0.39
    image: elasticsearch:8.11.3
    image: quay.io/minio/minio:RELEASE.2025-06-13T11-33-47Z
    image: valkey/valkey:8
```

If any check fails: review the offending file, fix, repeat.

- [ ] **Step 4: No commit needed (validation only)**

---

## Task 12: F3A smoke test — deploy from clean slate

**Files:**
- (no file changes — deployment test)

This task runs on the F3A itself (192.168.1.13). Local execution from the Mac requires SSH; the engineer should run the steps over SSH or have the user run them.

- [ ] **Step 1: SSH to F3A and pull the latest setup repo**

From the Mac:
```bash
ssh mike@192.168.1.13 'cd ~/work/setup && git pull'
```

If `~/work/setup` doesn't exist on F3A:
```bash
ssh mike@192.168.1.13 'git clone <repo-url> ~/work/setup'
```

- [ ] **Step 2: Sync `.env` from Mac to F3A (excluding GH_TOKEN if needed)**

The `.env` file on F3A must have `RAGFLOW_DEFAULT_EMAIL`, `RAGFLOW_DEFAULT_PASSWORD`, `RAGFLOW_API_KEY` set. Either edit on F3A or scp from Mac:

```bash
# Option A: edit on F3A
ssh mike@192.168.1.13
nano ~/work/setup/.env  # add RAGFLOW_* vars per .env.example

# Option B: scp from Mac (if happy with Mac contents)
scp /Users/mike/work/setup/.env mike@192.168.1.13:~/work/setup/.env
```

- [ ] **Step 3: Wipe any prior RagFlow state**

```bash
ssh mike@192.168.1.13 'cd ~/work/setup/ragflow 2>/dev/null && docker compose down -v 2>/dev/null; cd ~/ragflow 2>/dev/null && docker compose down -v 2>/dev/null; true'
```

This drops volumes from both the new and old stack locations — clean slate.

- [ ] **Step 4: Run the new launcher**

```bash
ssh mike@192.168.1.13 'cd ~/work/setup && bash ubuntu/53_ragflow.sh'
```

Watch the output. Expected timeline:
- Image pull: 5–15 min on first run (large image).
- "RagFlow is up." within ~3 min after pull completes.
- Stack ps shows 5 containers all `Up` or `Up (healthy)`.

- [ ] **Step 5: Verify init worked**

```bash
ssh mike@192.168.1.13 'docker logs ragflow-server 2>&1 | grep -E "init_default_user|admin user|API key|Ollama model" | tail -30'
```

Expected to see lines like:
```
[entrypoint] running init_default_user.py...
... Created user muemike@gmail.com
... Registered 4 Ollama model(s) for tenant ...
... Persisted API key for tenant ...
```

- [ ] **Step 6: Verify HTTP UI**

```bash
curl -fsS -o /dev/null -w '%{http_code}\n' http://192.168.1.13/
```

Expected: `200` or `301`/`302`.

- [ ] **Step 7: Verify API key is valid**

Get the dataset list using the persisted API key:
```bash
ssh mike@192.168.1.13 'source ~/work/setup/.env && curl -fsS -H "Authorization: Bearer $RAGFLOW_API_KEY" http://localhost:9380/api/v1/datasets'
```

Expected: JSON like `{"code":0,"data":[]}` or similar — meaning the token is recognised. A 401 means the API key didn't get persisted; check init logs.

- [ ] **Step 8: Verify models in UI**

Open `http://192.168.1.13/` in a browser. Log in with `RAGFLOW_DEFAULT_EMAIL` / `RAGFLOW_DEFAULT_PASSWORD`. Go to Settings → Model Providers. Expected: Ollama listed as a configured provider; bge-m3, qwen3:30b-a3b-q4_K_M, gemma4:e4b, qwen3.6:35b in the model list.

If models are missing: `RAGFLOW_DEFAULT_CHAT_MODEL` etc. were not in `.env` at first boot. Reset (Step 3) and retry.

- [ ] **Step 9: Verify idempotent restart**

```bash
ssh mike@192.168.1.13 'cd ~/work/setup/ragflow && docker compose restart ragflow && sleep 90 && docker logs ragflow-server 2>&1 | grep -E "API key already in DB|Found .* existing user" | tail -5'
```

Expected: log lines confirming user creation was skipped and API key was found in DB. The init script's idempotency is real.

- [ ] **Step 10: No commit — this is verification, not code**

If any of steps 5–9 fail, file the failure as a follow-up task in this session and decide:
- Schema drift in v0.25.1 (likely): inspect failing import, adjust `init_default_user.py`, bump pin if needed.
- Ollama not reachable from container: verify `host.docker.internal` resolves inside the container with `docker exec ragflow-server getent hosts host.docker.internal`.
- Server not up after 60s: increase the sleep in `entrypoint.sh:init_default_user`.

---

## Self-review

After implementing all tasks, run this final check:

- [ ] **Spec coverage:** every section of `docs/superpowers/specs/2026-05-08-ragflow-fix-design.md` has a matching task above. Verified — section list:
  - File layout → Tasks 1, 8, 9
  - init_default_user.py behavior → Task 6
  - entrypoint.sh behavior → Task 5
  - docker-compose.yml → Tasks 2, 3, 4
  - .env contract → Task 7
  - new ubuntu/53_ragflow.sh → Task 8
  - what's removed → Tasks 8, 9
  - error handling → covered by init script retry loop in Task 6
  - testing strategy → Task 11 (local) + Task 12 (F3A smoke)
- [ ] **Placeholder scan:** no TBD, TODO, "fill in", "similar to" anywhere in this plan. Code blocks are complete.
- [ ] **Type consistency:**
  - `RAGFLOW_API_KEY` (not `RAGFLOW_MCP_API_KEY`) used everywhere.
  - `tenant_id == user_id` invariant matches ragflow-docker.
  - `max_tokens=8192` for embedding models (per CLAUDE.md fix).
  - `llm_factory="Ollama"` (case-sensitive native factory name in RagFlow).

---

## Out of scope (explicitly)

These were considered and deliberately excluded:

- Multi-instance support.
- Langfuse observability hooks.
- MCP server / Admin server.
- LiteLLM / OpenAI-compatible proxy paths.
- Rerank / ASR / image2text models.
- `--with-ragflow` flag for `ubuntu/test_pipeline.sh` — separate plan if/when needed (would require Docker-in-Docker host networking quirks for Ollama integration).
- nginx config customisation — using the upstream image's defaults (mounted nginx config files in ragflow-docker were for proxy/HTTPS in the multi-instance deployment).

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

# v0.25.1+ ships nginx variants (ragflow.conf.{python,golang,hybrid}) and the
# upstream entrypoint copies one to ragflow.conf at startup. Default: python.
NGINX_CONF_DIR="/etc/nginx/conf.d"
if [ -f "${NGINX_CONF_DIR}/ragflow.conf.python" ] && [ ! -f "${NGINX_CONF_DIR}/ragflow.conf" ]; then
    cp -f "${NGINX_CONF_DIR}/ragflow.conf.python" "${NGINX_CONF_DIR}/ragflow.conf"
    echo "[entrypoint] applied nginx config: ragflow.conf.python"
fi

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

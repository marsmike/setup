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

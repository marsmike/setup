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


def _desired_ollama_models():
    """Build the list of (model_type, llm_name, max_tokens) tuples from env."""
    chat_model = os.environ.get('RAGFLOW_DEFAULT_CHAT_MODEL', '').strip()
    embedding_model = os.environ.get('RAGFLOW_DEFAULT_EMBEDDING_MODEL', '').strip()
    vision_model = os.environ.get('RAGFLOW_DEFAULT_VISION_MODEL', '').strip()
    additional = os.environ.get('RAGFLOW_ADDITIONAL_CHAT_MODELS', '').strip()

    desired = []
    if chat_model:
        desired.append(("chat", chat_model, 0))
    if additional:
        for name in [m.strip() for m in additional.split(',') if m.strip()]:
            desired.append(("chat", name, 0))
    if embedding_model:
        # max_tokens=8192 is critical — 0 truncates input to empty string.
        desired.append(("embedding", embedding_model, 8192))
    if vision_model:
        desired.append(("image2text", vision_model, 0))
    return desired


def ensure_ollama_models(tenant_id):
    """Per-model idempotent: only insert Ollama models that aren't already registered.
    Safe to call on every boot — picks up new models added to env over time."""
    try:
        from api.db.services.tenant_llm_service import TenantLLMService
    except ImportError as e:
        logger.error(f"Cannot import TenantLLMService: {e}")
        return False

    desired = _desired_ollama_models()
    if not desired:
        logger.info("No Ollama models configured via env — skipping.")
        return True

    try:
        existing = TenantLLMService.query(tenant_id=tenant_id, llm_factory="Ollama")
        existing_names = {row.llm_name for row in existing}
    except Exception as e:
        logger.warning(f"Could not query existing Ollama models: {e}")
        existing_names = set()

    ollama_base = os.environ.get('OLLAMA_BASE_URL', 'http://host.docker.internal:11434').strip()
    to_insert = []
    for model_type, llm_name, max_tokens in desired:
        if llm_name in existing_names:
            continue
        to_insert.append({
            "tenant_id": tenant_id,
            "llm_factory": "Ollama",
            "model_type": model_type,
            "llm_name": llm_name,
            "api_key": "",
            "api_base": ollama_base,
            "max_tokens": max_tokens,
            "used_tokens": 0,
            "status": "1",
        })
        logger.info(f"  + {model_type}: {llm_name} (Ollama, max_tokens={max_tokens})")

    if not to_insert:
        logger.info(f"Tenant {tenant_id} already has all desired Ollama models ({len(existing_names)} present) — skipping.")
        return True

    try:
        if not TenantLLMService.insert_many(to_insert):
            raise Exception("TenantLLMService.insert_many() returned False")
        logger.info(f"Registered {len(to_insert)} new Ollama model(s) for tenant {tenant_id}")
        return True
    except Exception as e:
        logger.error(f"Failed to register Ollama models: {e}")
        return False


def _desired_llamacpp_models():
    """Build (model_type, llm_name, max_tokens) tuples for our llama-swap stack."""
    chat_model = os.environ.get('LLAMACPP_CHAT_MODEL', '').strip()
    embedding_model = os.environ.get('LLAMACPP_EMBEDDING_MODEL', '').strip()
    desired = []
    if chat_model:
        # 32k context matches llama-swap config; max_tokens here is the per-call cap.
        desired.append(("chat", chat_model, 32768))
    if embedding_model:
        desired.append(("embedding", embedding_model, 8192))
    return desired


def ensure_llamacpp_models(tenant_id):
    """Register llama-swap models under the OpenAI-API-Compatible factory.
    Per-model idempotent."""
    try:
        from api.db.services.tenant_llm_service import TenantLLMService
    except ImportError as e:
        logger.error(f"Cannot import TenantLLMService: {e}")
        return False

    desired = _desired_llamacpp_models()
    if not desired:
        logger.info("No llama-swap models configured (LLAMACPP_* unset) — skipping.")
        return True

    try:
        existing = TenantLLMService.query(tenant_id=tenant_id, llm_factory="OpenAI-API-Compatible")
        existing_names = {row.llm_name for row in existing}
    except Exception as e:
        logger.warning(f"Could not query existing OpenAI-API-Compatible models: {e}")
        existing_names = set()

    base = os.environ.get('LLAMACPP_BASE_URL', 'http://host.docker.internal:8080/v1').strip()
    to_insert = []
    for model_type, llm_name, max_tokens in desired:
        if llm_name in existing_names:
            continue
        to_insert.append({
            "tenant_id": tenant_id,
            "llm_factory": "OpenAI-API-Compatible",
            "model_type": model_type,
            "llm_name": llm_name,
            # api_key is required by RagFlow's validator even though llama-swap doesn't check it.
            "api_key": "dummy",
            "api_base": base,
            "max_tokens": max_tokens,
            "used_tokens": 0,
            "status": "1",
        })
        logger.info(f"  + {model_type}: {llm_name} (OpenAI-API-Compatible @ {base})")

    if not to_insert:
        logger.info(f"Tenant {tenant_id} already has all llama-swap models — skipping.")
        return True

    try:
        if not TenantLLMService.insert_many(to_insert):
            raise Exception("TenantLLMService.insert_many() returned False")
        logger.info(f"Registered {len(to_insert)} llama-swap model(s) for tenant {tenant_id}")
        return True
    except Exception as e:
        logger.error(f"Failed to register llama-swap models: {e}")
        return False


def _primary_model_ids():
    """Resolve the primary tenant.{llm,embd,img2txt}_id values.
    llama-swap (OpenAI-API-Compatible) takes precedence over Ollama; VLM stays on
    Ollama until mmproj migration."""
    llama_chat = os.environ.get('LLAMACPP_CHAT_MODEL', '').strip()
    llama_embed = os.environ.get('LLAMACPP_EMBEDDING_MODEL', '').strip()
    ollama_chat = os.environ.get('RAGFLOW_DEFAULT_CHAT_MODEL', '').strip()
    ollama_embed = os.environ.get('RAGFLOW_DEFAULT_EMBEDDING_MODEL', '').strip()
    ollama_vlm = os.environ.get('RAGFLOW_DEFAULT_VISION_MODEL', '').strip()

    llm_id = (f"{llama_chat}@OpenAI-API-Compatible" if llama_chat
              else (f"{ollama_chat}@Ollama" if ollama_chat else ""))
    embd_id = (f"{llama_embed}@OpenAI-API-Compatible" if llama_embed
               else (f"{ollama_embed}@Ollama" if ollama_embed else ""))
    img2txt_id = f"{ollama_vlm}@Ollama" if ollama_vlm else ""
    return llm_id, embd_id, img2txt_id


def ensure_tenant_default_models(tenant_id):
    """Set tenant.{llm,embd,img2txt}_id to the resolved primary, only if empty.
    Idempotent: doesn't overwrite manual UI changes."""
    try:
        from api.db.services.user_service import TenantService
    except ImportError as e:
        logger.warning(f"Cannot import TenantService: {e}")
        return False

    llm_id, embd_id, img2txt_id = _primary_model_ids()

    try:
        rows = TenantService.query(id=tenant_id)
        if not rows:
            return False
        t = rows[0]
        updates = {}
        if llm_id and not (t.llm_id or '').strip():
            updates['llm_id'] = llm_id
        if embd_id and not (t.embd_id or '').strip():
            updates['embd_id'] = embd_id
        if img2txt_id and not (t.img2txt_id or '').strip():
            updates['img2txt_id'] = img2txt_id
        if not updates:
            return True
        for k, v in updates.items():
            setattr(t, k, v)
            logger.info(f"  ~ tenant.{k} = {v}")
        t.save()
        return True
    except Exception as e:
        logger.error(f"Failed to update tenant default models: {e}")
        return False


def ensure_user_access_token(user_id):
    """Ensure user.access_token is non-empty. Required for api_token-based auth
    (api/apps/__init__.py:_load_user falls back to api_token but rejects users
    whose access_token is empty)."""
    try:
        from api.db.services.user_service import UserService
    except ImportError as e:
        logger.warning(f"Cannot import UserService: {e}")
        return False
    try:
        users = UserService.query(id=user_id)
        if not users:
            logger.warning(f"User {user_id} not found — cannot set access_token.")
            return False
        u = users[0]
        if u.access_token and u.access_token.strip():
            return True
        u.access_token = get_uuid()
        u.save()
        logger.info(f"Set access_token on user {user_id} to enable api_token auth.")
        return True
    except Exception as e:
        logger.error(f"Failed to set user.access_token: {e}")
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
        first = users[0]
        # Idempotent re-checks on every boot
        ensure_ollama_models(first.id)
        ensure_llamacpp_models(first.id)
        ensure_tenant_default_models(first.id)
        ensure_user_access_token(first.id)
        return create_api_key(first.id)

    logger.info(f"No users found. Creating admin user {email}...")
    user_id = get_uuid()
    pw_b64 = base64.b64encode(password.encode()).decode()

    llm_id, embd_id, img2txt_id = _primary_model_ids()

    user = {
        "id": user_id,
        "email": email,
        "nickname": nickname,
        "password": pw_b64,
        # access_token must be non-empty for the api_token fallback auth path
        # to succeed (api/apps/__init__.py:_load_user). Value can be any 32+ string.
        "access_token": get_uuid(),
        "status": 1,
        "is_superuser": True,
        "login_channel": "password",
    }
    tenant = {
        "id": user_id,
        "name": f"{nickname}'s Kingdom",
        # tenant.<x>_id format: "model_name@factory_name"
        "llm_id": llm_id,
        "embd_id": embd_id,
        "asr_id": "",
        "img2txt_id": img2txt_id,
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

    if not ensure_ollama_models(user_id):
        logger.warning("Ollama model registration failed — user can add via UI.")
    if not ensure_llamacpp_models(user_id):
        logger.warning("llama-swap model registration failed — user can add via UI.")
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

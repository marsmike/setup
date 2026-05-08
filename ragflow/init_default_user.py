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


def ensure_ollama_models(tenant_id):
    """Add Ollama models only if none are registered yet for this tenant.
    Idempotent: safe to call on every boot."""
    try:
        from api.db.services.tenant_llm_service import TenantLLMService
    except ImportError as e:
        logger.error(f"Cannot import TenantLLMService: {e}")
        return False

    try:
        existing = TenantLLMService.query(tenant_id=tenant_id, llm_factory="Ollama")
        if existing:
            logger.info(f"Tenant {tenant_id} already has {len(existing)} Ollama model(s) — skipping.")
            return True
    except Exception as e:
        logger.warning(f"Could not check existing Ollama models: {e}")

    return add_ollama_models(tenant_id)


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
            "status": "1",
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
                "status": "1",
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
            "status": "1",
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
        first = users[0]
        # Idempotent re-checks on every boot
        ensure_ollama_models(first.id)
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

    if not ensure_ollama_models(user_id):
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

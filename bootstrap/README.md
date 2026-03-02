# bootstrap/

One-time onboarding scripts for a new server. Run these **before** the platform scripts
(`ubuntu/`, `mac/`, `fedora/`), which handle software setup for an already-accessible host.

---

## Overview

| Script | Actor | What it does |
|--------|-------|--------------|
| `local/01_keygen.sh` | local | Generate ED25519 key pair (skips if exists) |
| `local/02_key_upload.sh` | local | `ssh-copy-id` key → `SETUP_USER@SETUP_HOST` |
| `local/03_key_test.sh` | local | Verify key auth; print remote fingerprint |
| `server/04_adduser.sh` | local→remote | Create `SETUP_USER`, add to sudo + docker groups |
| `server/05_sudoers.sh` | local→remote | Grant passwordless sudo to `SETUP_USER` |
| `server/06_sshd_harden.sh` | local→remote | Disable password auth (asks confirmation) |

All server scripts run **locally** and SSH into the remote host.

---

## Prerequisites

1. Copy and fill in the repo root `.env`:

```bash
cp .env.example .env
# Edit .env — set SETUP_USER, SETUP_HOST, SETUP_SSH_KEY at minimum
```

2. The remote host must have SSH accessible (password or key).

---

## Run order

### Step 1 — Local: generate and upload key

```bash
bash bootstrap/local/01_keygen.sh    # generate key (skips if exists)
bash bootstrap/local/02_key_upload.sh # upload to server (prompts for password)
bash bootstrap/local/03_key_test.sh   # verify + print fingerprint
```

### Step 2 — Server: create user and harden

For a **fresh server** (only `root` exists), override `SSH_USER`:

```bash
SSH_USER=root bash bootstrap/server/04_adduser.sh  # create SETUP_USER
SSH_USER=root bash bootstrap/server/05_sudoers.sh  # passwordless sudo
```

Once `SETUP_USER` can log in with a key, the default (`SSH_USER=$SETUP_USER`) works:

```bash
bash bootstrap/server/06_sshd_harden.sh  # disable password auth (asks confirmation)
```

### SSH_USER override

`SSH_USER` controls who you SSH as when running server scripts:

- Default: `SSH_USER=$SETUP_USER` — assumes user already exists and key is uploaded.
- Override: `SSH_USER=root` — use for fresh servers where `SETUP_USER` doesn't exist yet.

Set in `.env` or inline: `SSH_USER=root bash bootstrap/server/04_adduser.sh`

---

## After bootstrap

The server is ready for the platform setup scripts:

```bash
bash ubuntu/01_basics.sh
bash ubuntu/02_shell.sh
bash ubuntu/03_dotfiles.sh
# ...
```

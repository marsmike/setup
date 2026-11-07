# bootstrap/

One-time onboarding scripts for a new server. Run these **before** the platform scripts
(`ubuntu/`, `mac/`, `fedora/`), which handle software setup for an already-accessible host.

All scripts run **locally** and SSH into the remote host. They read `~/.env`, and
values set inline on the command line take priority.

---

## Overview

| Script | What it does |
|--------|--------------|
| `local/01_keygen.sh` | Generate this server's ED25519 key and add it to `~/.ssh/config` |
| `local/02_key_upload.sh` | `ssh-copy-id` the key to `SSH_USER@host` |
| `local/03_key_test.sh` | Verify key auth and print authorized fingerprints |
| `server/04_adduser.sh` | Create `SETUP_USER`, add sudo + docker groups, install the key |
| `server/05_sudoers.sh` | Grant passwordless sudo to `SETUP_USER` |
| `server/06_sshd_harden.sh` | Key-only SSH, no root login, only `SETUP_USER` may log in |
| `server/07_baseline.sh` | All updates, automatic security updates, ufw, fail2ban (Debian/Ubuntu) |

---

## Prerequisites

Set at least `SETUP_USER` and `SETUP_HOST` in `~/.env`. The remote host must accept
SSH as root, by password or key.

## One key per server

Every server gets its own key at `~/.ssh/id_ed25519_<host>`, named from `SETUP_HOST`,
so a compromised server exposes nothing about your other hosts. `01_keygen.sh` also
adds the host to `~/.ssh/config` with `IdentitiesOnly yes` and `ForwardAgent no`.
`SETUP_SSH_KEY` overrides the path. To onboard another server, set its host inline:

```bash
SETUP_HOST=mike@other.example.com bash bootstrap/local/01_keygen.sh
```

Use a host name rather than an IP in `SETUP_HOST`, so the key name stays meaningful.

---

## Run order for a fresh server

Only `root` exists at first, so the early steps connect as root:

```bash
bash bootstrap/local/01_keygen.sh
SSH_USER=root bash bootstrap/local/02_key_upload.sh
SSH_USER=root bash bootstrap/server/04_adduser.sh
SSH_USER=root bash bootstrap/server/05_sudoers.sh
```

Confirm your user can log in, then secure the server. These steps always connect
as `SETUP_USER` and stop if it has no working key login with sudo:

```bash
bash bootstrap/local/03_key_test.sh
bash bootstrap/server/06_sshd_harden.sh
bash bootstrap/server/07_baseline.sh
```

---

## Lockout protection

**`06_sshd_harden.sh`** writes `/etc/ssh/sshd_config.d/00-hardening.conf`. It loads
before every other file, so provider files such as `50-cloud-init.conf` can't
override it. The script then checks the effective settings with `sshd -T` over a
new login. If that fails, a timer removes the file after 5 minutes.

**`07_baseline.sh`** allows the SSH port before enabling ufw, then tests a new login.
If that fails, a timer disables the firewall after 5 minutes.

Keep an existing session open until each script finishes.

---

## fail2ban

Five failed logins within 10 minutes ban the source IP for an hour. Failed key
attempts count, including tries with the wrong user. Exempt stable addresses with:

```bash
FAIL2BAN_IGNOREIP="203.0.113.7 2001:db8::1" bash bootstrap/server/07_baseline.sh
```

To lift a ban from an address that can still log in:

```bash
sudo fail2ban-client set sshd unbanip <ip>
```

---

## After bootstrap

The server is ready for the platform setup scripts. On the server as your user,
choose `01_minimal.sh` or `01_basics.sh --server`:

```bash
bash ubuntu/01_minimal.sh
bash ubuntu/02_shell.sh
bash ubuntu/03_dotfiles.sh
```

# Quick Start

## One-time setup: `~/.env`

All scripts read config from a single file at `$HOME/.env` (canonical).
The repo-root `.env` is a symlink to it.

```bash
cp .env.example ~/.env
chmod 600 ~/.env
ln -sf ~/.env .env          # at the repo root, for docker-compose env_file
```

Edit `~/.env` and fill in `SETUP_USER`, `SETUP_HOST`, `RAGFLOW_API_KEY`,
`LLAMACPP_*`, etc. — see `.env.example` for the full list.

Don't create per-subdir `.env` files — everything sources from `~/.env`.

---

## New Linux server

From your **local machine**:

```bash
bash bootstrap/local/01_keygen.sh
SSH_USER=root bash bootstrap/local/02_key_upload.sh
SSH_USER=root bash bootstrap/server/04_adduser.sh
SSH_USER=root bash bootstrap/server/05_sudoers.sh
bash bootstrap/local/03_key_test.sh
bash bootstrap/server/06_sshd_harden.sh
bash bootstrap/server/07_baseline.sh
```

Then **on the server** as your user:

```bash
git clone https://github.com/marsmike/setup.git ~/Developer/setup
cd ~/Developer/setup

bash ubuntu/01_minimal.sh           # Claude Code, herdr, tmux
# or
bash ubuntu/01_basics.sh --server   # everything except ollama and fonts

bash ubuntu/02_shell.sh
bash ubuntu/03_dotfiles.sh
exec zsh
```

---

## Ubuntu desktop or MiniPC

```bash
bash ubuntu/01_basics.sh
bash ubuntu/02_shell.sh
bash ubuntu/03_dotfiles.sh
exec zsh
```

Optional add-ons:

```bash
bash ubuntu/10_containers.sh  # ctop, dive, lazydocker, k9s, kubectl, helm, k3d, kind, minikube
bash ubuntu/20_gui.sh         # flatpak, ghostty, Obsidian, Discord, WezTerm, Chrome, Firefox
```

---

## macOS

```bash
bash mac/01_basics.sh
bash mac/02_shell.sh
bash mac/03_dotfiles.sh
exec zsh && p10k configure
```

---

## Proxmox VM

Provision a VM from any machine (Mac, Linux, MobaXterm). Credentials come from
the `PROXMOX_*` keys in `~/.env`.

```bash
./proxmox/provision.sh --dry-run proxmox/vms/ragflow.yaml
./proxmox/provision.sh proxmox/vms/ragflow.yaml
```

See [proxmox/README.md](proxmox/README.md) for full documentation.

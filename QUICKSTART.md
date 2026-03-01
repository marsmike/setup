# Quick Start

## macOS

```bash
bash mac/01_basics.sh         # Homebrew + all baseline tools
bash linux/02_dotfiles.sh     # chezmoi dotfiles + tmux plugins
bash linux/03_shell.sh        # zsh + powerlevel10k + plugins
exec zsh && p10k configure
```

Optional add-ons:

```bash
bash tools/10_claude.sh       # Claude Code CLI
bash tools/10_ai_tools.sh     # Gemini CLI, GH Copilot, Pi
bash tools/10_llm_tools.sh    # llm, aider, ttok, strip-tags, files-to-prompt
bash tools/20_atuin.sh        # shell history sync
bash tools/20_uv.sh           # Python manager
```

---

## New Linux Server — automated

Run from your **local machine** (handles everything in one step):

```bash
bash linux/00_bootstrap.sh <HOST_IP>
# or with password: bash linux/00_bootstrap.sh <HOST_IP> --root-pass 'password'
```

Then SSH in as your user and continue:

```bash
bash linux/01_basics.sh
bash linux/02_dotfiles.sh
bash linux/03_shell.sh
exec zsh && p10k configure
```

---

## New Linux Server — manual

Run as **root** on the fresh server:

```bash
bash linux/00_adduser.sh      # create user + sudo/docker groups
bash linux/00_sudoers.sh      # passwordless sudo
```

From your **local machine** — copy your SSH key while password auth is still on:

```bash
bash mac/00_sshkey.sh user@<host>
```

Back on server as **root**, after confirming the key works:

```bash
bash linux/00_sshd.sh         # key-only auth, disable password login
```

Then SSH in as your user and continue:

```bash
bash linux/01_basics.sh
bash linux/02_dotfiles.sh
bash linux/03_shell.sh
exec zsh && p10k configure
```

---

## Linux Dev Machine

```bash
bash linux/01_basics.sh       # apt baseline + nvm + yq + glow + watchexec
bash linux/02_dotfiles.sh     # chezmoi dotfiles + tmux plugins
bash linux/03_shell.sh        # zsh + powerlevel10k + plugins
exec zsh && p10k configure
```

Optional add-ons:

```bash
bash tools/10_claude.sh       # Claude Code CLI
bash tools/10_ai_tools.sh     # Gemini CLI, GH Copilot, Pi
bash tools/10_llm_tools.sh    # llm, aider, ttok, strip-tags, files-to-prompt
bash linux/10_neovim.sh       # Neovim AppImage
bash tools/10_kubectl.sh      # kubectl
bash tools/10_helm.sh         # Helm 3
bash tools/10_k3d.sh          # k3d (k3s in Docker)
bash linux/11_docker_tools.sh # ctop, dive, lazydocker
bash tools/20_atuin.sh        # shell history sync
bash tools/20_uv.sh           # Python manager
bash linux/20_restic.sh       # encrypted backups
bash tools/20_fonts.sh        # JetBrainsMono + Meslo Nerd Fonts
```

---

## Proxmox VM

Provision a VM from any machine (Mac, Linux, MobaXterm):

```bash
cp proxmox/.env.example proxmox/.env   # first time: fill in credentials
./proxmox/provision.sh --dry-run proxmox/vms/ragflow.yaml
./proxmox/provision.sh proxmox/vms/ragflow.yaml
```

See [proxmox/README.md](proxmox/README.md) for full documentation.

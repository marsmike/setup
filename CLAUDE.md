# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Personal machine setup scripts for macOS, Linux servers, and Proxmox VMs. Scripts are numbered by phase so you know what to run and in what order.

## Configuration

All scripts source `.env` from the repo root (or `proxmox/.env` / `linux/.env` as fallbacks). Required variables:

```bash
cp .env.example .env
# SETUP_USER, SETUP_HOST, DOTFILES_REPO, GH_TOKEN, SSH_PUBLIC_KEY
```

## Two Ubuntu Script Collections

There are two overlapping Ubuntu script sets — understand which to use:

- **`linux/`** — modular, run each script separately. Suitable for servers where you want step control. `00_bootstrap.sh` runs from your local machine over SSH.
- **`ubuntu/`** — newer, consolidated Ubuntu setup for desktop/MiniPC. `01_basics.sh` here is a superset (combines packages + most optional tools in one pass). Has a test pipeline.

For a fresh server: use `linux/`. For a new desktop/MiniPC: use `ubuntu/`.

## Running the Pipeline

### New Linux server (automated, from local machine)
```bash
bash linux/00_bootstrap.sh <HOST_IP>                    # or --root-pass 'password'
# Then SSH in as your user:
bash linux/01_basics.sh && bash linux/02_dotfiles.sh && bash linux/03_shell.sh
exec zsh && p10k configure
```

### New Ubuntu desktop/MiniPC (on the machine itself)
```bash
bash ubuntu/01_basics.sh      # packages + Docker + most optional tools
bash ubuntu/02_shell.sh       # oh-my-zsh + powerlevel10k + plugins
bash ubuntu/03_dotfiles.sh    # chezmoi dotfiles + tpm
exec zsh
```

### macOS
```bash
bash mac/01_basics.sh && bash linux/02_dotfiles.sh && bash linux/03_shell.sh
exec zsh && p10k configure
```

### Optional tool scripts (both platforms)
```bash
bash ubuntu/10_containers.sh  # ctop, dive, lazydocker, k9s, kubectl, helm, k3d, kind, minikube
bash ubuntu/20_gui.sh         # flatpak, ghostty, Obsidian, Discord, WezTerm, Chrome, Firefox
bash tools/10_claude_agents.sh --start  # persistent Claude tmux sessions (backup copy — see below)
```

## Testing

Test the ubuntu pipeline in an isolated environment:

```bash
# Auto-detect backend (Docker preferred; quickemu if /dev/kvm available)
bash ubuntu/test_pipeline.sh

# Force Docker
bash ubuntu/test_pipeline.sh --backend docker

# Include dotfiles phase (requires GH_TOKEN in .env)
bash ubuntu/test_pipeline.sh --with-dotfiles

# Leave container running to inspect
bash ubuntu/test_pipeline.sh --keep

# Destroy previous environment first
bash ubuntu/test_pipeline.sh --clean
```

Logs are written to `~/.pipeline-test/logs/`.

## Architecture Patterns

**Version resolution**: All tool versions are resolved at runtime via the GitHub API — no hardcoded versions. The `gh_api()` helper in `ubuntu/01_basics.sh` uses `gh auth token` when available to avoid rate limits.

**Idempotency**: Every tool install is guarded with `command -v <tool> &>/dev/null || install`. Scripts are safe to re-run; `02_shell.sh` explicitly skips already-installed components.

**Error handling**: `set -euo pipefail` at the top, but optional/external downloads use soft-fail (`log_error` function + continue) so one failed download doesn't abort the whole script.

**Install locations**: User-level tools go to `~/.local/bin`; system tools requiring sudo go to `/usr/local/bin`.

**Ubuntu quirks handled by scripts**:
- `bat` is installed as `batcat` → symlinked to `~/.local/bin/bat`
- `libfuse2` renamed to `libfuse2t64` in Ubuntu 22.10+ (auto-detected)
- Ghostty terminfo installed in `02_shell.sh` to prevent SSH character repeat bugs

**`tools/10_claude_agents.sh`** is a backup copy. The canonical version lives at `~/work/agentic-toolkit-private/scripts/agents.sh`. Edits here are not picked up by the nightly cron. It manages a `claude` tmux session with windows: `ozzie` (WhatsApp bot), `top` (crowd dashboard), `kora` (remote-control agent).

## llama.cpp Vulkan stack

Self-contained stack lives at `llamacpp/` (top-level, mirrors `ragflow/`):
single `llama-swap` container that fronts per-model `llama-server` processes
on the AMD Radeon 890M iGPU via Vulkan/RADV. Replaces Ollama as RagFlow's
chat/embed backend (~4× faster prompt-eval on Qwen3-30B-A3B; verified bench
in memory `project_f3a_llm_stack.md`).

- Run: `bash ubuntu/52_llamacpp_vulkan.sh` (thin launcher; also builds the
  native `~/llama.cpp` for ad-hoc benching).
- Endpoint: `http://192.168.1.13:8080` (OpenAI-compatible /v1).
- Models in container: `qwen3-30b-a3b-q4_K_M` (chat), `bge-m3` (embedding).
- VLM (`qwen3-vl:8b`) stays on Ollama for now — its `mmproj` packaging in
  llama-server needs a separate migration step.
- Ollama remains as a backup chat/embed provider; do not decommission until
  the llama.cpp stack has run RagFlow's full RTCU dataset end-to-end.

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

```bash
cp proxmox/.env.example proxmox/.env
./proxmox/provision.sh --dry-run proxmox/vms/<name>.yaml
./proxmox/provision.sh proxmox/vms/<name>.yaml
```

See `proxmox/README.md` for full documentation.

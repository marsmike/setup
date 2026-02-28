# setup

Personal machine setup scripts for Linux servers and macOS. Scripts are
numbered by phase so you always know what to run and in what order.

---

## Quick Start

### First: set up `.env`

```bash
cp .env.example .env
# fill in SETUP_USER, SETUP_HOST, DOTFILES_REPO, GH_TOKEN
```

`.env` is sourced automatically by all scripts — no more hardcoded usernames or tokens.

---

### New Linux Server

Run as **root** on the fresh server:

```bash
bash 00_server_adduser.sh   # create user (SETUP_USER) + add to sudo & docker groups
bash 00_server_sudoers.sh   # passwordless sudo for user
```

From your **local machine** — copy your SSH key over while password auth is still on:

```bash
bash 00_local_sshkey.sh user@<host>
```

Back on the server as **root** — lock down SSH once the key is confirmed working:

```bash
bash 00_server_sshd.sh      # key-only auth, no root login, restart sshd
```

Then SSH in as your user and continue with Phase 1:

```bash
bash 01_basics_linux.sh
bash 02_dotfiles.sh
bash 03_shell.sh
exec zsh && p10k configure
```

---

### Linux Dev Machine (existing server / VM)

```bash
bash 01_basics_linux.sh     # baseline apt packages
bash 02_dotfiles.sh         # chezmoi dotfiles + tmux plugins
bash 03_shell.sh            # oh-my-zsh + powerlevel10k + plugins
exec zsh && p10k configure
```

---

### macOS

```bash
bash 01_basics_macos.sh     # Homebrew + baseline packages
bash 02_dotfiles.sh         # chezmoi dotfiles + tmux plugins
bash 03_shell.sh            # oh-my-zsh + powerlevel10k + plugins
exec zsh && p10k configure
```

---

## Script Reference

| Script | What it does | Linux | macOS |
|--------|-------------|:-----:|:-----:|
| **Phase 0 — Server bootstrap** | | | |
| `00_local_sshkey.sh` | Generate ED25519 key pair + copy to server | — | ✓ |
| `00_server_adduser.sh` | Create user (`SETUP_USER`), sudo + docker groups | ✓ | — |
| `00_server_sudoers.sh` | Passwordless sudo for user | ✓ | — |
| `00_server_sshd.sh` | Key-only auth, disable password + root login | ✓ | — |
| **Phase 1 — Core** | | | |
| `01_basics_linux.sh` | apt baseline: git, zsh, eza, ripgrep, fd, node… | ✓ | — |
| `01_basics_macos.sh` | Homebrew + same baseline via brew | — | ✓ |
| `02_dotfiles.sh` | chezmoi dotfiles (`DOTFILES_REPO`) + tpm | ✓ | ✓ |
| `03_shell.sh` | oh-my-zsh, powerlevel10k, autosuggestions, syntax-hl | ✓ | ✓ |
| **Phase 2 — Dev tools** | | | |
| `10_neovim.sh` | Neovim AppImage → `~/.local/bin/nvim` | ✓ | — |
| `10_lazygit.sh` | lazygit (latest GitHub release) | ✓ | — |
| `10_kubectl.sh` | kubectl (latest stable) | ✓ | — |
| `10_helm.sh` | Helm 3 (official installer) | ✓ | — |
| `10_k3d.sh` | k3d — k3s in Docker | ✓ | — |
| `10_claude.sh` | Claude Code CLI (native installer) | ✓ | ✓ |
| `10_ai_tools.sh` | Gemini CLI, GH Copilot CLI, Pi | ✓ | ✓ |
| `10_llm_tools.sh` | llm, files-to-prompt, ttok, strip-tags, aider | ✓ | ✓ |
| `11_docker_tools.sh` | ctop, dive, lazydocker | ✓ | — |
| **Phase 3 — Optional / Specialized** | | | |
| `20_atuin.sh` | atuin shell history (replaces mcfly) | ✓ | ✓ |
| `20_uv.sh` | uv — fast Python package + project manager | ✓ | ✓ |
| `20_conda.sh` | Miniconda (default) or Anaconda | ✓ | — |
| `20_kind.sh` | kind — Kubernetes IN Docker (latest) | ✓ | — |
| `20_minikube.sh` | minikube — local Kubernetes cluster | ✓ | — |
| `20_coder.sh` | Coder — self-hosted dev environments | ✓ | — |
| `20_teleport.sh` | Teleport v17 — zero-trust access | ✓ | — |
| `20_restic.sh` | restic — fast, encrypted backups | ✓ | — |
| `20_fonts.sh` | Nerd Fonts: JetBrainsMono + Meslo | ✓ | — |
| **Utilities** | | | |
| `yabs.sh` | Server benchmark (Yet Another Bench Script) | ✓ | — |
| `mx-keys-fix.sh` | Logitech MX Keys Fn-key fix (Linux desktop) | ✓ | — |
| `quickemu_install.sh` | quickemu + quickget — run lightweight VMs | ✓ | — |
| `quickgui_install.sh` | quickgui — GUI front-end for quickemu (optional) | ✓ | — |
| `test_pipeline.sh` | Spin up a fresh Ubuntu 24.04 VM and test the Linux pipeline | ✓ | — |

---

## Phase 0 — Server Bootstrap

### `00_local_sshkey.sh` — SSH key setup *(run locally)*

Generates an ED25519 key pair (if one doesn't already exist at the given path)
and copies the public key to a remote server using `ssh-copy-id`. Run this
**before** `00_server_sshd.sh` locks out password auth.

```bash
bash 00_local_sshkey.sh                                   # uses SETUP_HOST from .env or prompts
bash 00_local_sshkey.sh user@1.2.3.4                      # specify host
bash 00_local_sshkey.sh user@1.2.3.4 ~/.ssh/id_myserver   # custom key path
```

Default key path: `~/.ssh/id_ed25519`

---

### `00_server_adduser.sh` — Create user *(run as root)*

Creates the user (`SETUP_USER` from `.env`) and adds them to the `sudo` and `docker` groups.

```bash
bash 00_server_adduser.sh
```

---

### `00_server_sudoers.sh` — Passwordless sudo *(run as root)*

Writes `/etc/sudoers.d/<user>-nopasswd` granting `NOPASSWD: ALL` to the
specified user, then validates it with `visudo -c` before saving so a broken
sudoers file can never land.

```bash
sudo bash 00_server_sudoers.sh           # defaults to SETUP_USER
sudo bash 00_server_sudoers.sh alice     # explicit override
```

---

### `00_server_sshd.sh` — Harden SSH *(run as root)*

Edits `/etc/ssh/sshd_config` to enforce key-based authentication and restarts
sshd. **Run this only after your SSH key is working** — it disables password
login, locking you out if the key isn't in place.

```bash
bash 00_server_sshd.sh
```

Changes applied:
- `PubkeyAuthentication yes`
- `PasswordAuthentication no`
- `PermitRootLogin no`
- `AuthorizedKeysFile .ssh/authorized_keys`

---

## Phase 1 — Core

### `01_basics_linux.sh` — Baseline packages (Linux)

Adds the `universe` repo and installs a comprehensive set of apt packages.
Run this first on any Linux machine.

```bash
bash 01_basics_linux.sh
```

| Group | Tools |
|-------|-------|
| Core | `git` `gh` `vim` `wget` `curl` `build-essential` |
| Shell | `zsh` `tmux` `fzf` `zoxide` |
| Files | `eza` `bat` `fd-find` `ripgrep` `ranger` |
| Monitor | `btop` `htop` `ncdu` `powertop` `hyperfine` |
| Data | `jq` `yq` `glow` `lnav` `csvlens` `ack` `tldr` |
| Dev workflow | `git-delta` `direnv` `watchexec` `python3` `docker-compose` |
| Network | `httpie` `rsync` `dnsutils` |
| AI / LLM | `models` |
| Runtime | Node.js LTS (via nvm) `libfuse2` |

---

### `01_basics_macos.sh` — Baseline packages (macOS)

Installs Homebrew if not present, then installs an equivalent set of tools.

```bash
bash 01_basics_macos.sh
```

| Group | Tools |
|-------|-------|
| Core | `git` `gh` `vim` `wget` |
| Shell | `zsh` `tmux` `fzf` `zoxide` |
| Files | `eza` `bat` `fd` `ripgrep` `lazygit` |
| Monitor | `btop` `ncdu` `hyperfine` `mactop` `viddy` |
| Data | `jq` `yq` `glow` `lnav` `csvlens` `jless` `tldr` |
| Dev workflow | `git-delta` `direnv` `watchexec` |
| Network | `httpie` `rsync` |
| AI / LLM | `models` `llmfit` |
| Terminal extras | `taproom` `timg` |
| Runtime | Node.js LTS (via nvm) |

> **Note:** Docker Desktop must be installed manually from docker.com.

---

### `02_dotfiles.sh` — Dotfiles + tmux plugins

Installs [chezmoi](https://chezmoi.io) to `~/.local/bin/chezmoi` and applies
the dotfiles repo (`DOTFILES_REPO` from `.env`). Also
bootstraps [tpm](https://github.com/tmux-plugins/tpm) (Tmux Plugin Manager).

```bash
bash 02_dotfiles.sh
```

After running, open tmux and press `prefix+I` to install tmux plugins.

---

### `03_shell.sh` — Shell setup (oh-my-zsh + powerlevel10k)

Idempotent — safe to re-run. Skips any component already installed.

```bash
bash 03_shell.sh
```

Installs:
- **oh-my-zsh** — with `RUNZSH=no KEEP_ZSHRC=yes` (won't overwrite your `.zshrc`)
- **powerlevel10k** — cloned into `~/.oh-my-zsh/custom/themes/`
- **zsh-autosuggestions** — fish-style inline completions
- **zsh-syntax-highlighting** — command highlighting as you type
- Sets zsh as default shell via `usermod` (falls back with instructions if sudo unavailable)

After running:

```bash
exec zsh           # reload shell
p10k configure     # optional — config already applied from dotfiles
```

Make sure your `.zshrc` contains:
```zsh
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
```

---

## Phase 2 — Dev Tools

### `10_neovim.sh` — Neovim

Downloads the latest Neovim AppImage and installs it to `~/.local/bin/nvim`.
`libfuse2` (required for AppImage) is already included in `01_basics_linux.sh`.

```bash
bash 10_neovim.sh
```

---

### `10_lazygit.sh` — lazygit

Downloads the latest release from GitHub and installs to `/usr/local/bin`.

```bash
bash 10_lazygit.sh
```

---

### `10_kubectl.sh` — kubectl

Downloads the latest stable kubectl binary from the official Kubernetes CDN.

```bash
bash 10_kubectl.sh
```

---

### `10_helm.sh` — Helm 3

Runs the official Helm installer script.

```bash
bash 10_helm.sh
```

---

### `10_k3d.sh` — k3d

Installs [k3d](https://k3d.io) (k3s in Docker) via the official installer script.

```bash
bash 10_k3d.sh
```

---

### `10_claude.sh` — Claude Code

Installs [Claude Code](https://claude.ai/code) using the native installer.

```bash
bash 10_claude.sh
```

After installing, run `claude` to get started.

---

### `10_ai_tools.sh` — AI coding assistants

Installs Gemini CLI, GitHub Copilot CLI, and Pi. Requires `nodejs` + `npm`
and `gh` (both included in the Phase 1 basics scripts).

```bash
bash 10_ai_tools.sh
```

| Tool | Command | Source |
|------|---------|--------|
| Gemini CLI | `gemini` | Google — `@google/gemini-cli` |
| GitHub Copilot CLI | `gh copilot` | `gh extension install github/gh-copilot` |
| Pi coding agent | `pi` | badlogic — `@mariozechner/pi-coding-agent` |

---

### `10_llm_tools.sh` — LLM CLI utilities

Installs Simon Willison's LLM stack and aider via `uv tool install`.
Bootstraps `uv` automatically if not present.

```bash
bash 10_llm_tools.sh
```

| Tool | Command | What it does |
|------|---------|-------------|
| [llm](https://llm.datasette.io) | `llm` | Run prompts against any model; log history |
| [files-to-prompt](https://github.com/simonw/files-to-prompt) | `files-to-prompt` | Concat a codebase into a single prompt |
| [ttok](https://github.com/simonw/ttok) | `ttok` | Count tokens before making API calls |
| [strip-tags](https://github.com/simonw/strip-tags) | `strip-tags` | Strip HTML to clean text for LLM input |
| [aider](https://aider.chat) | `aider` | AI pair programmer, git-native |

> `llmfit` and `timg` are installed via brew in `01_basics_macos.sh`.

---

### `11_docker_tools.sh` — Docker utilities

Installs three Docker companion tools. All versions resolved at runtime via
the GitHub API — no hardcoded versions.

```bash
bash 11_docker_tools.sh
```

| Tool | What it does |
|------|-------------|
| [ctop](https://github.com/bcicen/ctop) | `top`-like interface for containers |
| [dive](https://github.com/wagoodman/dive) | Explore image layers and wasted space |
| [lazydocker](https://github.com/jesseduffield/lazydocker) | TUI for Docker management |

---

## Phase 3 — Optional / Specialized

### `20_atuin.sh` — atuin shell history

Replaces `mcfly` with [atuin](https://atuin.sh) — shell history with full-text
search, statistics, and optional cross-machine sync.

```bash
bash 20_atuin.sh
```

After installing:
```bash
atuin import auto          # migrate existing shell history
```

Add to `.zshrc` (replacing any mcfly eval):
```zsh
eval "$(atuin init zsh)"
```

Optional sync across machines:
```bash
atuin register   # create account
atuin login      # on other machines
atuin sync
```

---

### `20_uv.sh` — uv Python manager

Installs [uv](https://docs.astral.sh/uv/) by Astral — an extremely fast Python
package and project manager. Handles Python version management, virtual envs,
and package installation. Replaces pip/pyenv/conda for most workflows.

```bash
bash 20_uv.sh
```

Quick reference:
```bash
uv python install 3.12      # install a Python version
uv venv && source .venv/bin/activate
uv pip install <package>    # fast pip replacement
uv run script.py            # run with auto-managed deps
```

---

### `20_conda.sh` — Conda (Miniconda / Anaconda)

Installs Miniconda (default, recommended) or full Anaconda. Prefer `20_uv.sh`
for most Python workflows — use conda only when you need the conda ecosystem.

```bash
bash 20_conda.sh              # Miniconda (default)
bash 20_conda.sh miniconda    # explicit
bash 20_conda.sh anaconda     # full Anaconda suite (Anaconda3-2024.10-1)
```

After Miniconda:
```bash
~/miniconda/bin/conda init zsh
exec zsh
```

---

### `20_kind.sh` — kind

Installs [kind](https://kind.sigs.k8s.io) (Kubernetes IN Docker). Version
resolved at runtime from the GitHub API.

```bash
bash 20_kind.sh
```

ARM64 variant is included as a commented-out line in the script.

---

### `20_minikube.sh` — minikube

Installs the latest [minikube](https://minikube.sigs.k8s.io) for running a
local Kubernetes cluster.

```bash
bash 20_minikube.sh
```

---

### `20_coder.sh` — Coder

Installs [Coder](https://coder.com) for self-hosted cloud development
environments using the official installer.

```bash
bash 20_coder.sh
```

After installing: `coder server` to start, then open `http://localhost:3000`.

---

### `20_teleport.sh` — Teleport

Installs [Teleport](https://goteleport.com) using the official installer.
Defaults to v17; pass a version argument to override.

```bash
bash 20_teleport.sh        # installs v17
bash 20_teleport.sh 16     # specific major version
```

---

### `20_restic.sh` — restic

Installs [restic](https://restic.net) via apt, then runs `restic self-update`
to ensure the latest version regardless of what's in the apt repo.

```bash
bash 20_restic.sh
```

---

### `20_fonts.sh` — Nerd Fonts

Downloads and installs **JetBrainsMono** and **Meslo** Nerd Fonts to
`~/.local/share/fonts`, then rebuilds the font cache. Version resolved at
runtime from the GitHub API.

```bash
bash 20_fonts.sh
```

> **Note:** If you use `02_dotfiles.sh`, the chezmoi dotfiles already manage
> MesloLGS NF fonts — you may only need JetBrainsMono.

Set your terminal font to `JetBrainsMono Nerd Font` or `MesloLGS NF` after running.

---

## Utilities

### `yabs.sh` — Server benchmark

Runs [YABS](https://github.com/masonr/yet-another-bench-script): disk, network,
and CPU benchmarks. Useful for evaluating a new VPS.

```bash
bash yabs.sh
```

---

### `mx-keys-fix.sh` — Logitech MX Keys Fn-key fix

Fixes the Fn-key behaviour on Logitech MX Keys under Linux so F1–F12 work
without holding Fn. Linux desktop only.

```bash
bash mx-keys-fix.sh
```

---

## Config Snippets

| File | Purpose |
|------|---------|
| `60-vxlan.cfg` | VXLAN network configuration snippet |
| `docker-grub.txt` | GRUB cmdline settings for Docker (cgroup, memory) |

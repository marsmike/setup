# setup

Machine setup scripts for Linux servers and macOS.

---

## Quick Start

### New Linux Server (as root)
```bash
bash 00_server_adduser.sh   # create mike user
bash 00_server_sshd.sh      # harden sshd (key-only, no root)
# then SSH in as mike and continue below
```

### Linux Dev Machine / Server (as mike)
```bash
bash 01_basics_linux.sh     # baseline packages
bash 02_dotfiles.sh         # chezmoi dotfiles
bash 03_shell.sh            # oh-my-zsh + p10k + plugins
exec zsh && p10k configure
```

### macOS
```bash
bash 01_basics_macos.sh     # Homebrew + baseline packages
bash 02_dotfiles.sh         # chezmoi dotfiles
bash 03_shell.sh            # oh-my-zsh + p10k + plugins
exec zsh && p10k configure
```

---

## Script Reference

| Script | What it does | Linux | macOS |
|--------|-------------|-------|-------|
| **Phase 0 — Server only (run as root)** | | | |
| `00_server_adduser.sh` | Create `mike` user, add to sudo + docker | ✓ | — |
| `00_server_sshd.sh` | Harden sshd: key-only auth, no root login | ✓ | — |
| **Phase 1 — Core (run first, every machine)** | | | |
| `01_basics_linux.sh` | apt packages: git, zsh, eza, ripgrep, fd, node… | ✓ | — |
| `01_basics_macos.sh` | Homebrew + same baseline via brew | — | ✓ |
| `02_dotfiles.sh` | chezmoi → marsmike dotfiles + tpm | ✓ | ✓ |
| `03_shell.sh` | oh-my-zsh, powerlevel10k, autosuggestions, syntax-hl | ✓ | ✓ |
| **Phase 2 — Dev tools (most dev machines)** | | | |
| `10_neovim.sh` | Neovim AppImage → `~/.local/bin/nvim` | ✓ | — |
| `10_lazygit.sh` | lazygit (latest) | ✓ | — |
| `10_kubectl.sh` | kubectl (latest stable) | ✓ | — |
| `10_helm.sh` | Helm 3 | ✓ | — |
| `10_k3d.sh` | k3d (k3s in Docker) | ✓ | — |
| `10_ai_tools.sh` | Claude Code, Gemini CLI, GH Copilot CLI, Pi | ✓ | ✓ |
| `11_docker_tools.sh` | ctop, dive, lazydocker | ✓ | — |
| **Phase 3 — Optional / Specialized** | | | |
| `20_atuin.sh` | atuin shell history (replaces mcfly) | ✓ | ✓ |
| `20_uv.sh` | uv Python manager (fast pip/conda alternative) | ✓ | ✓ |
| `20_conda.sh` | Miniconda or Anaconda (`bash 20_conda.sh [miniconda\|anaconda]`) | ✓ | — |
| `20_kind.sh` | kind (Kubernetes in Docker, latest) | ✓ | — |
| `20_minikube.sh` | minikube | ✓ | — |
| `20_coder.sh` | Coder self-hosted dev environments | ✓ | — |
| `20_teleport.sh` | Teleport v17 | ✓ | — |
| `20_restic.sh` | restic backup tool | ✓ | — |
| `20_fonts.sh` | Nerd Fonts: JetBrainsMono + Meslo | ✓ | — |
| **Utilities** | | | |
| `yabs.sh` | Server benchmark | ✓ | — |
| `mx-keys-fix.sh` | Logitech MX Keys fix (Linux desktop) | ✓ | — |

---

## Post-install: p10k + dotfiles

After running `03_shell.sh`:

```bash
exec zsh               # reload shell with oh-my-zsh
p10k configure         # interactive prompt wizard
```

Save the generated config back to your dotfiles:
```bash
chezmoi add ~/.p10k.zsh
chezmoi cd
git add dot_p10k.zsh
git commit -m "add p10k config"
git push
```

Your `.zshrc` should have:
```zsh
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
```

---

## Notes

### chezmoi dotfiles
`02_dotfiles.sh` uses `chezmoi init --apply marsmike` which pulls from
[github.com/marsmike/dotfiles](https://github.com/marsmike/dotfiles).
chezmoi is installed to `~/.local/bin/chezmoi` (no fragile `mv ./bin/` dance).

### atuin vs mcfly
`20_atuin.sh` installs [atuin](https://atuin.sh) — a modern replacement for mcfly
with optional cross-machine sync. After install:
```bash
atuin import auto           # migrate existing history
# in .zshrc: eval "$(atuin init zsh)"
```

### uv vs conda
[uv](https://docs.astral.sh/uv/) (`20_uv.sh`) handles most Python workflows
faster and with less overhead than conda. Use `20_conda.sh` only when you
specifically need the conda ecosystem.

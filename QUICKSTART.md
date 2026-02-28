# Quick Start

## macOS

```bash
bash 01_basics_macos.sh     # Homebrew + all baseline tools
bash 02_dotfiles.sh         # chezmoi dotfiles + tmux plugins
bash 03_shell.sh            # zsh + powerlevel10k + plugins
exec zsh && p10k configure
```

Optional add-ons:

```bash
bash 10_claude.sh           # Claude Code CLI
bash 10_ai_tools.sh         # Gemini CLI, GH Copilot, Pi
bash 10_llm_tools.sh        # llm, aider, ttok, strip-tags, files-to-prompt
bash 20_atuin.sh            # shell history sync
bash 20_uv.sh               # Python manager
```

---

## New Linux Server

Run as **root** on the fresh server:

```bash
bash 00_server_adduser.sh   # create user + sudo/docker groups
bash 00_server_sudoers.sh   # passwordless sudo
```

From your **local machine** — copy your SSH key while password auth is still on:

```bash
bash 00_local_sshkey.sh user@<host>
```

Back on server as **root**, after confirming the key works:

```bash
bash 00_server_sshd.sh      # key-only auth, disable password login
```

Then SSH in as your user and continue:

```bash
bash 01_basics_linux.sh
bash 02_dotfiles.sh
bash 03_shell.sh
exec zsh && p10k configure
```

---

## Linux Dev Machine

```bash
bash 01_basics_linux.sh     # apt baseline + nvm + yq + glow + watchexec
bash 02_dotfiles.sh         # chezmoi dotfiles + tmux plugins
bash 03_shell.sh            # zsh + powerlevel10k + plugins
exec zsh && p10k configure
```

Optional add-ons:

```bash
bash 10_claude.sh           # Claude Code CLI
bash 10_ai_tools.sh         # Gemini CLI, GH Copilot, Pi
bash 10_llm_tools.sh        # llm, aider, ttok, strip-tags, files-to-prompt
bash 10_neovim.sh           # Neovim AppImage
bash 10_kubectl.sh          # kubectl
bash 10_helm.sh             # Helm 3
bash 10_k3d.sh              # k3d (k3s in Docker)
bash 11_docker_tools.sh     # ctop, dive, lazydocker
bash 20_atuin.sh            # shell history sync
bash 20_uv.sh               # Python manager
bash 20_restic.sh           # encrypted backups
bash 20_fonts.sh            # JetBrainsMono + Meslo Nerd Fonts
```

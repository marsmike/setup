# tmux Guide

Your config lives at `~/.config/tmux/tmux.conf` (and `tmux.keybinds.conf`), managed via chezmoi.

---

## Core Concept: Prefix Key

**Your prefix is `Ctrl+A`** (not the default `Ctrl+B`).

Most tmux commands: press `Ctrl+A`, release, then press the next key.
The most frequent actions (pane/window navigation) need **no prefix at all**.

### Mental Model

```
Server
└── Session (e.g. "work", "personal")
    ├── Window 1  (like a browser tab, shown in status bar)
    │   ├── Pane A
    │   └── Pane B
    └── Window 2
        └── Pane A
```

- **Session**: a named workspace. Survives terminal close. You detach/attach.
- **Window**: full-screen "tab" within a session, shown in the top status bar.
- **Pane**: a split within a window.

---

## Navigation (no prefix — fastest actions)

These work instantly, no prefix key needed:

| Key | Action |
|-----|--------|
| `Alt+h` | focus pane left |
| `Alt+j` | focus pane down |
| `Alt+k` | focus pane up |
| `Alt+l` | focus pane right |
| `Alt+H` (Alt+Shift+H) | previous window |
| `Alt+L` (Alt+Shift+L) | next window |

> **Note:** Requires Ghostty's `macos-option-as-alt = left` (already set).
> No conflicts with Magnet (`Ctrl+Option`), WhisprFlow (`Fn`), ScreenFloat (`Cmd+Shift`), or Nextcloud.

---

## Sessions

| Key | Action |
|-----|--------|
| `prefix + o` | **SessionX** — fuzzy session switcher with preview (your main session tool) |
| `prefix + S` | choose session from list |
| `prefix + d` | detach from current session (session keeps running) |
| `tmux new -s name` | create named session from shell |
| `tmux attach -t name` | attach to existing session |
| `tmux ls` | list sessions |

**SessionX** (`prefix + o`) is the power tool: fuzzy search, zoxide integration, preview pane. It searches `~/dotfiles` as the base path. Use this instead of remembering session names.

### Auto-save & Restore (tmux-continuum + tmux-resurrect)

Your sessions are **automatically saved every 15 minutes** and **restored on tmux start**.
- `prefix + Ctrl+S` — manually save
- `prefix + Ctrl+R` — manually restore
- Neovim sessions are also restored (`@resurrect-strategy-nvim 'session'`)

---

## Windows

Windows are indexed starting at **1** (not 0). They auto-renumber when closed.
Status bar is at the **top**.

| Key | Action |
|-----|--------|
| `Alt+H` / `Alt+L` | previous / next window **(no prefix)** |
| `prefix + c` | new window (opens in current path) |
| `prefix + a` | last window (toggle between two recent) |
| `prefix + w` | list all windows |
| `prefix + r` | rename current window |

---

## Panes (Splits)

### Creating Splits (visual mnemonics)

| Key | Action |
|-----|--------|
| `prefix + -` | split **horizontally** (top/bottom) — `-` looks like a horizontal line |
| `prefix + \` | split **vertically** (side by side) — `\` looks like a vertical line |

Both open in the current working directory.

### Moving Between Panes

| Key | Action |
|-----|--------|
| `Alt+h/j/k/l` | move focus between panes **(no prefix, vim-style)** |

### Managing Panes

| Key | Action |
|-----|--------|
| `prefix + z` | zoom/unzoom current pane (fullscreen toggle) |
| `prefix + x` | kill current pane |
| `prefix + X` | swap pane with next |
| `prefix + P` | toggle pane border status bar |
| `prefix + *` | **synchronize panes** — type in all panes simultaneously |

### Resize Panes

Hold `prefix` then tap repeatedly (the `-r` flag allows repeat without re-pressing prefix):

| Key | Action |
|-----|--------|
| `prefix + H` | resize left (5 cols) |
| `prefix + J` | resize down (5 rows) |
| `prefix + K` | resize up (5 rows) |
| `prefix + L` | resize right (5 cols) |

---

## Copy Mode (vi-style)

| Key | Action |
|-----|--------|
| `prefix + [` | enter copy mode (scroll/search buffer) |
| `v` | begin selection (in copy mode) |
| `y` | yank selection to clipboard (tmux-yank) |
| `q` or `Esc` | exit copy mode |
| `/` | search forward in buffer |
| `?` | search backward |

---

## Global Keybindings (no prefix needed)

| Key | Action |
|-----|--------|
| `Alt+h/j/k/l` | navigate panes |
| `Alt+H` / `Alt+L` | prev/next window |
| `Ctrl+N` | open **nvim popup** → `:ObsidianNew` (new note) |
| `Ctrl+Q` | open **nvim popup** → `:ObsidianSearch` (search notes, 90%×85% popup) |

---

## Other Prefix Commands

| Key | Action |
|-----|--------|
| `prefix + R` | reload tmux config |
| `prefix + :` | open tmux command prompt |

---

## URL Picker (tmux-fzf-url)

`prefix + u` — opens fzf picker showing all URLs visible in the current pane. Select one to open in browser. History limit: 2000.

---

## Fuzzy Finder (tmux-fzf)

`prefix + F` — opens tmux-fzf menu for fuzzy-finding windows, sessions, panes, commands.

---

## Thumbs (tmux-thumbs)

`prefix + Space` — activates thumbs mode: overlays hint characters on text patterns (URLs, file paths, git hashes, IPs, etc.). Press the hint letter to copy that text to clipboard. Faster than copy mode for grabbing specific strings.

---

## Status Bar

Status bar is at the **top**. Layout (Catppuccin theme):

```
[session name]   win1  WIN2  win3   ...   [directory]  [meetings]  [HH:MM]
```

- **Left**: current session name
- **Middle**: windows (current window highlighted)
- **Right**: current directory basename | next calendar meeting | clock
- Window shows `()` suffix when zoomed

### Meetings Widget

The status bar shows your **next calendar meeting** (via `icalBuddy`, macOS only).
- Shows meeting title + time when within 10 minutes
- Shows a popup alert 10 seconds before
- Skips solo events (< 2 attendees)

---

## Installed Plugins

| Plugin | Purpose |
|--------|---------|
| `tmux-plugins/tpm` | Plugin manager — `prefix + I` install, `prefix + U` update, `prefix + Alt+U` remove |
| `tmux-plugins/tmux-sensible` | Sane defaults (faster key repeat, larger history, etc.) |
| `tmux-plugins/tmux-yank` | Clipboard integration for copy mode |
| `tmux-plugins/tmux-resurrect` | Manual save/restore sessions (`prefix + Ctrl+S/R`) |
| `tmux-plugins/tmux-continuum` | Auto-saves every 15min, auto-restores on start |
| `fcsonline/tmux-thumbs` | Hint-based text picker (`prefix + Space`) |
| `sainnhe/tmux-fzf` | Fuzzy finder for tmux objects (`prefix + F`) |
| `wfxr/tmux-fzf-url` | URL picker from pane content (`prefix + u`) |
| `omerxx/catppuccin-tmux` | Catppuccin theme (forked, includes meetings script) |
| `omerxx/tmux-sessionx` | Session manager with fzf preview (`prefix + o`) |

### Managing Plugins

```
prefix + I        install new plugins (after adding to config)
prefix + U        update all plugins
prefix + Alt+U    remove plugins not in config
```

---

## Quick Reference Card

```
NO PREFIX (instant)        WINDOWS (prefix+key)       SPLITS (prefix+key)
Alt+hjkl  move panes       c  new window              -  split ─ (horizontal)
Alt+H     prev window       a  last window             \  split │ (vertical)
Alt+L     next window       r  rename
                            w  list                   PANES (prefix+key)
SESSIONS (prefix+key)                                 x  kill pane
o  SessionX              RESIZE (prefix, repeatable)   z  zoom toggle
S  list sessions         H/J/K/L  resize 5 cols/rows   X  swap pane
d  detach                                              *  sync all

COPY MODE                GLOBAL (no prefix)
prefix+[  enter          Ctrl+N  Obsidian new note
v         select         Ctrl+Q  Obsidian search
y         yank
q         quit           MISC (prefix+key)
                         R  reload config
                         u  pick URL
                         Space  thumbs (hint copy)
                         F  tmux-fzf menu
```

---

## Tips

- **SSH + sessions**: `tmux new -s project` on the remote host. Detach with `prefix+d`. Reconnect with `tmux attach -t project`. Sessions survive network drops.
- **Sync panes** (`prefix + *`): useful for running the same command on multiple servers at once.
- **Zoom** (`prefix + z`): temporarily fullscreen a pane. Press again to restore splits.
- **ObsidianNew** (`Ctrl+N`): works from anywhere — opens a floating nvim window to take a quick note without leaving your current context.
- **Alt key**: Uses Left Option via Ghostty's `macos-option-as-alt = left`. Right Option still types special characters (é, ü, etc.).

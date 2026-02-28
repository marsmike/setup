# Neovim Guide

Your config lives at `~/.config/nvim/init.lua`, managed via chezmoi.
Based on **kickstart.nvim** — a minimal, readable single-file config (not a distribution).

---

## Core Concepts

### Leader Key

**`<Space>`** is your leader key. Most custom bindings start with it.

In the key tables below, `<leader>` means press `Space` first (in normal mode).

### Modes

| Mode | How to enter | Indicator |
|------|-------------|-----------|
| Normal | `Esc` | (default, for navigation) |
| Insert | `i`, `a`, `o`, etc. | `-- INSERT --` |
| Visual | `v` (char), `V` (line), `Ctrl+V` (block) | `-- VISUAL --` |
| Command | `:` | `:` prompt |
| Terminal | `:term` then `i` | `-- TERMINAL --` |

---

## Essential Navigation

### Movement

| Key | Action |
|-----|--------|
| `h/j/k/l` | left / down / up / right |
| `w/b` | next/prev word |
| `gg` / `G` | top / bottom of file |
| `{` / `}` | prev / next blank line (paragraph) |
| `Ctrl+d` / `Ctrl+u` | half-page down / up |
| `%` | jump to matching bracket |
| `f{char}` | jump to next occurrence of char on line |
| `*` | search for word under cursor |
| `n` / `N` | next / prev search result |
| `Esc` | clear search highlights |

### Splits (Windows)

| Key | Action |
|-----|--------|
| `Ctrl+h` | move to left split |
| `Ctrl+j` | move to lower split |
| `Ctrl+k` | move to upper split |
| `Ctrl+l` | move to right split |
| `:sp` | horizontal split |
| `:vsp` | vertical split |

New splits open to the right and below (configured).

---

## Telescope (Fuzzy Finder)

Your primary tool for navigating everything. Activated with `<leader>s*`.

| Key | Action |
|-----|--------|
| `<leader>sf` | **search files** (find_files) |
| `<leader>sg` | **live grep** — search content across project |
| `<leader>sw` | grep the word under cursor |
| `<leader>s/` | live grep in currently open files only |
| `<leader>/` | fuzzy search inside current buffer |
| `<leader><leader>` | list open buffers |
| `<leader>s.` | recent files |
| `<leader>sr` | resume last telescope search |
| `<leader>sh` | search help tags |
| `<leader>sk` | search keymaps |
| `<leader>ss` | search/select telescope pickers |
| `<leader>sd` | search LSP diagnostics |
| `<leader>sn` | search nvim config files |

### Inside Telescope

| Key | Action |
|-----|--------|
| Type | filter results |
| `Ctrl+j/k` or arrows | navigate results |
| `Enter` | open selected |
| `Ctrl+x` | open in horizontal split |
| `Ctrl+v` | open in vertical split |
| `Ctrl+t` | open in new tab |
| `Esc` or `Ctrl+c` | close |
| `?` (normal mode) | show all telescope keymaps |
| `Ctrl+/` (insert mode) | show all telescope keymaps |

---

## LSP (Language Server Protocol)

LSP gives you IDE features: go-to-definition, find references, rename, etc.
These activate automatically when a supported language file is open.

### LSP Navigation

| Key | Action |
|-----|--------|
| `gd` | **go to definition** |
| `gD` | go to declaration |
| `gr` | **find all references** |
| `gI` | go to implementation |
| `Ctrl+T` | jump back (after gd/gr) |
| `K` | show hover documentation |
| `<leader>D` | type definition |

### LSP Actions

| Key | Action |
|-----|--------|
| `<leader>rn` | **rename** symbol (renames across all files) |
| `<leader>ca` | **code action** (fixes, imports, refactors) |
| `<leader>ds` | document symbols (all functions/vars in file) |
| `<leader>ws` | workspace symbols (across project) |

### Diagnostics (Errors/Warnings)

| Key | Action |
|-----|--------|
| `[d` | go to previous diagnostic |
| `]d` | go to next diagnostic |
| `<leader>e` | show diagnostic detail (floating window) |
| `<leader>q` | send diagnostics to quickfix list |

### Mason (LSP Installer)

`:Mason` — opens the LSP/tool installer UI. Install language servers here.
Currently auto-installed: `lua_ls` (Lua), `stylua` (Lua formatter).

To add more servers, edit the `servers` table in `init.lua` and run `:Mason`.

---

## Autocompletion (nvim-cmp)

Completions appear automatically. Navigate and accept:

| Key | Action |
|-----|--------|
| `Ctrl+n` | next completion item |
| `Ctrl+p` | previous completion item |
| `Ctrl+y` | **accept** selected completion |
| `Ctrl+Space` | manually trigger completion |
| `Ctrl+l` | jump forward in snippet placeholder |
| `Ctrl+h` | jump backward in snippet placeholder |

Sources: LSP → snippets (LuaSnip) → file paths.

---

## Editing

### Comments (Comment.nvim)

| Key | Action |
|-----|--------|
| `gcc` | toggle line comment |
| `gc` + motion | comment a motion (e.g. `gc5j` = comment 5 lines down) |
| `gc` in visual | comment selected lines |

### Surround (mini.surround)

| Key | Action |
|-----|--------|
| `saiw)` | **s**urround **a**dd **i**nner **w**ord with `()` |
| `saiw"` | surround word with `""` |
| `sd'` | **s**urround **d**elete `'` quotes |
| `sr)"` | **s**urround **r**eplace `)` with `"` |

### Text Objects (mini.ai) — Enhanced

Use with operators like `v` (visual), `y` (yank), `d` (delete), `c` (change):

| Object | Selects |
|--------|---------|
| `i)` / `a)` | inside/around parentheses |
| `i"` / `a"` | inside/around double quotes |
| `i'` / `a'` | inside/around single quotes |
| `it` / `at` | inside/around HTML tag |
| `in'` | inside **n**ext quotes (looks forward) |

Examples: `va)` = visually select around parens, `ci"` = change inside quotes.

### Format on Save

Files are **auto-formatted on save** via conform.nvim.
- Lua files: formatted with `stylua`
- Other formatters: add to `formatters_by_ft` in init.lua

---

## Git (gitsigns)

Signs appear in the gutter (left column) automatically for modified files:

| Sign | Meaning |
|------|---------|
| `+` | added line |
| `~` | changed line |
| `_` | deleted line |
| `‾` | top of deleted block |

No keybindings configured beyond the defaults — use `:Gitsigns` for commands, or LazyGit.

### LazyGit (lazygit.nvim)

Full-featured terminal git UI, launched from inside nvim:

| Command | Action |
|---------|--------|
| `:LazyGit` | open LazyGit in floating window |
| `:LazyGitCurrentFile` | open LazyGit focused on current file |
| `:LazyGitFilter` | filter commits |

Inside LazyGit: `?` shows all keybindings.

---

## Treesitter

Provides intelligent syntax highlighting, indentation, and code structure understanding for: `bash`, `c`, `html`, `lua`, `markdown`, `vim`, `vimdoc` (pre-installed). Others auto-install when you open a file.

No direct keybindings — works transparently in the background.

---

## TODO Comments (todo-comments.nvim)

Highlights special comment keywords automatically:

```lua
-- TODO: something to do
-- FIXME: broken thing
-- NOTE: important note
-- HACK: workaround
-- WARN: be careful
```

Use `<leader>sg` (live grep) and search for `TODO` to find all of them across the project.

---

## Keybinding Discovery

**which-key** shows a popup when you pause mid-sequence:

1. Press `<leader>` (Space) and wait ~300ms → popup shows all `<leader>` bindings
2. Press `<leader>s` and wait → shows all search bindings
3. Press `g` and wait → shows all `g*` bindings

This means you don't need to memorize everything — just start the sequence and wait.

---

## Installed Plugins

| Plugin | Purpose |
|--------|---------|
| `lazy.nvim` | Plugin manager (`:Lazy` to manage) |
| `tpope/vim-sleuth` | Auto-detect indent settings per file |
| `numToStr/Comment.nvim` | `gc` commenting |
| `lewis6991/gitsigns.nvim` | Git gutter signs |
| `folke/which-key.nvim` | Keybinding popup hints |
| `nvim-telescope/telescope.nvim` | Fuzzy finder (+ fzf-native, ui-select) |
| `neovim/nvim-lspconfig` | LSP client configuration |
| `williamboman/mason.nvim` | LSP/tool installer (`:Mason`) |
| `williamboman/mason-lspconfig.nvim` | Bridge mason ↔ lspconfig |
| `WhoIsSethDaniel/mason-tool-installer.nvim` | Auto-install tools |
| `j-hui/fidget.nvim` | LSP progress indicator (bottom right) |
| `stevearc/conform.nvim` | Auto-format on save |
| `hrsh7th/nvim-cmp` | Autocompletion engine |
| `L3MON4D3/LuaSnip` | Snippet engine |
| `hrsh7th/cmp-nvim-lsp` | LSP completion source |
| `hrsh7th/cmp-path` | File path completion source |
| `folke/tokyonight.nvim` | Colorscheme (tokyonight-night) |
| `folke/todo-comments.nvim` | Highlight TODO/FIXME/NOTE etc. |
| `echasnovski/mini.nvim` | mini.ai + mini.surround + mini.statusline |
| `nvim-treesitter/nvim-treesitter` | Syntax highlighting & code intelligence |
| `kdheepak/lazygit.nvim` | LazyGit UI (`:LazyGit`) |

### Available but Not Enabled

These exist in the config as commented-out lines — uncomment to activate:

- `kickstart.plugins.debug` — DAP debugger (F1-F5 keybindings, supports Go via delve)
- `kickstart.plugins.indent_line` — visual indent guides
- `custom.plugins` — your own plugins directory (`lua/custom/plugins/`)

---

## Plugin Management

`:Lazy` — opens the plugin manager UI.

| Command | Action |
|---------|--------|
| `:Lazy` | open manager |
| `:Lazy update` | update all plugins |
| `:Lazy sync` | install + update + clean |
| `:Lazy clean` | remove unused plugins |
| `?` inside :Lazy | show help |

Lock file at `~/.config/nvim/lazy-lock.json` — pins exact plugin versions.

---

## Settings Summary

| Setting | Value | Effect |
|---------|-------|--------|
| `number` | true | line numbers |
| `mouse` | 'a' | mouse in all modes |
| `clipboard` | 'unnamedplus' | system clipboard sync |
| `undofile` | true | persistent undo across sessions |
| `ignorecase` + `smartcase` | true | smart case search |
| `updatetime` | 250ms | faster CursorHold (LSP highlights) |
| `timeoutlen` | 300ms | which-key popup delay |
| `scrolloff` | 10 | keep 10 lines above/below cursor |
| `inccommand` | 'split' | live preview of `:s/` substitutions |
| `cursorline` | true | highlight current line |
| `signcolumn` | 'yes' | always show gutter (no layout shift) |
| colorscheme | tokyonight-night | dark theme |

---

## Quick Reference Card

```
NAVIGATE              TELESCOPE             LSP
hjkl    move          <leader>sf  files     gd   definition
gg/G    top/bot       <leader>sg  grep      gr   references
Ctrl+d/u half page    <leader>/   in file   K    hover docs
Ctrl+hjkl splits      <leader><>  buffers   <leader>rn rename
                                            <leader>ca action

EDIT                  DIAGNOSTICS           GIT
gcc     comment line  [d/]d   prev/next     :LazyGit
gc+mot  comment       <leader>e float        gitsigns in gutter
saiw)   surround add  <leader>q quickfix
sd'     surround del
sr)"    surround repl COMPLETION
                      Ctrl+n/p  navigate
WHICH-KEY             Ctrl+y    accept
<Space> then wait     Ctrl+l/h  snippet jump
```

---

## Tips

- **`:checkhealth`** — diagnose issues (LSP, treesitter, missing tools)
- **`:Tutor`** — built-in interactive vim tutorial (30 min, worth doing once)
- **`<leader>sn`** — quickly open your nvim config files to edit them
- **`:help {topic}`** — nvim's built-in help is excellent; use `<leader>sh` to search it
- The `-- NOTE:` / `-- TODO:` comments in `init.lua` are intentional teaching aids from kickstart — you can delete them once you're comfortable
- Obsidian notes (new/search) are accessible from **tmux** via `Ctrl+N` / `Ctrl+Q` — you don't need to be in nvim first

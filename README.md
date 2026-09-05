# Neovim config

Personal [LazyVim](https://github.com/LazyVim/LazyVim)-based Neovim configuration.

One repository, one remote, multiple **profiles**. Each profile is a git branch checked
out as its own [worktree](#how-profiles-work) at a path Neovim recognises via the
`NVIM_APPNAME` environment variable. Profiles share history and a remote; they diverge
only where they need to.

| Profile | Branch | Config path | Purpose |
|---------|--------|-------------|---------|
| main    | `main` | `~/.config/nvim`      | Full general-purpose setup |
| rust    | `rust` | `~/.config/nvim-rust` | Rust development. `main` + Rust LSP/DAP/treesitter, plus `rustaceanvim` tuning |

Remote: `https://github.com/skylar-smith/lazyvim`

---

## How profiles work

Neovim derives every path it uses from one environment variable, `NVIM_APPNAME`
(default: `nvim`):

| | default | `NVIM_APPNAME=nvim-rust` |
|---|---|---|
| config | `~/.config/nvim` | `~/.config/nvim-rust` |
| plugins / data | `~/.local/share/nvim` | `~/.local/share/nvim-rust` |
| state (logs, shada) | `~/.local/state/nvim` | `~/.local/state/nvim-rust` |
| cache | `~/.cache/nvim` | `~/.cache/nvim-rust` |

So `NVIM_APPNAME=nvim-rust nvim` is a fully separate Neovim: its own plugin set, its own
`lazy-lock.json`, its own Mason packages and LSP logs. The main config never loads.

The two config directories are **git worktrees of this one repo**:

```
~/.config/nvim/        worktree on branch main
~/.config/nvim-rust/   worktree on branch rust
        both share -> ~/.config/nvim/.git  (one object store, one remote)
```

A worktree is a second working directory backed by the same repository. Commits, staging
and stashes are independent per worktree; `fetch` / `push` and history are shared. A
branch may be checked out in at most one worktree at a time.

---

## Bootstrap on a fresh machine

### 1. Prerequisites (install manually)

```sh
# macOS
brew install neovim git ripgrep fd fzf gcc

# Rust profile: toolchain + the components Neovim needs
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup component add rust-analyzer rust-src clippy

# 99 plugin backend (model is set in lua/plugins/99.lua)
brew install opencode ollama
ollama pull qwen3-coder
```

- Neovim >= 0.11.
- A C compiler is required — `nvim-treesitter` builds parsers from source.

### 2. Run the bootstrap script

```sh
git clone https://github.com/skylar-smith/lazyvim.git ~/.config/nvim
~/.config/nvim/bootstrap.sh
```

`bootstrap.sh` is idempotent. It:

1. Checks prerequisites (hard-fails on `git` / `nvim` / C compiler; warns on missing
   `rg` / `fd` / `fzf` and missing rustup components).
2. Clones the repo to `~/.config/nvim` if not already present.
3. Adds the `rust` worktree at `~/.config/nvim-rust` (tracking `origin/rust`).
4. Runs `Lazy! restore` for both profiles — installs every plugin at the exact commit
   pinned in that branch's `lazy-lock.json`.
5. Force-loads Mason and treesitter headless and installs `codelldb`, `stylua`, `shfmt`,
   `shellcheck` and the Rust/TOML/Lua/etc. parsers.
6. Prints a `checkhealth` error/warning summary.

If the Mason/treesitter step looks incomplete, just open a `.rs` file in the rust
profile and wait ~1 minute — LazyVim finishes the install on filetype.

### 3. Verify

```sh
NVIM_APPNAME=nvim-rust nvim --headless "+checkhealth" +qa 2>&1 | grep -iE 'error|warning'
```

Open a real cargo project in the rust profile and run `:LspInfo` — `rust-analyzer`
should attach, rooted at the nearest `Cargo.toml`.

---

## Daily use

```sh
nvim                           # main profile
NVIM_APPNAME=nvim-rust nvim     # rust profile
```

Suggested shell alias:

```sh
alias nvr='NVIM_APPNAME=nvim-rust nvim'
```

Pick-a-profile launcher:

```sh
nvims() {
  local c; c=$(ls ~/.config | grep '^nvim' | fzf) || return
  NVIM_APPNAME="$c" nvim "$@"
}
```

Check which profile a running Neovim is: `:echo stdpath('config')`.

You cannot hot-swap profiles. `NVIM_APPNAME` is bound at startup — quit and relaunch to
change. Different terminals can run different profiles simultaneously with no conflict.

---

## Layout

```
init.lua                     -> require("config.lazy")
lua/config/
  lazy.lua                   bootstraps lazy.nvim + LazyVim, imports lua/plugins/
  options.lua keymaps.lua autocmds.lua
lua/plugins/
  99.lua                     ThePrimeagen/99 AI assistant (both profiles)
  rust.lua                   rustaceanvim tuning (rust profile only)
  example.lua                inert LazyVim sample
lazyvim.json                 which LazyVim "extras" are enabled
lazy-lock.json               pinned plugin commits (per branch)
bootstrap.sh                 fresh-machine setup
propagate.sh                 merge a shared main change into every other profile
```

### What the `rust` branch adds over `main`

- `lazyvim.json` extras: `lang.rust`, `lang.toml`, `dap.core` (on top of the shared
  `editor.fzf`). These pull in `rustaceanvim`, `crates.nvim`, `nvim-dap` + UI, the
  Rust/TOML treesitter parsers and the `codelldb` Mason package.
- `lua/plugins/rust.lua` — overrides merged onto `rustaceanvim` / `crates.nvim`:
  clippy on save (`check.command = "clippy"`), `cargo.buildScripts`, `procMacro.enable`,
  `target/` excluded from analysis. Bevy is macro- and feature-heavy, so these matter.

`rustaceanvim` manages `rust-analyzer` itself — do **not** also configure it via
`lspconfig` or `mason-lspconfig`.

### 99 plugin

`lua/plugins/99.lua` loads project context from `AGENTS.md`, `AGENT.md` and `CLAUDE.md`,
searched from the edited file's directory up to the current working directory. Missing
files are skipped silently. Backend and model are set in that file
(`ollama/qwen3-coder`); requires `opencode` (or `claude`) plus a running `ollama`.

Keymaps: `<leader>9v` (visual request), `<leader>9x` (cancel all), `<leader>9s`
(search), `<leader>9m` / `<leader>9p` (pick model / provider).

---

## Updating

### Update plugins (one profile)

```sh
cd ~/.config/nvim          # or ~/.config/nvim-rust
nvim   # then :Lazy sync
git add lazy-lock.json && git commit -m "bump plugins"
```

`:Lazy sync` updates to latest allowed and rewrites `lazy-lock.json`.
`:Lazy restore` reinstalls exactly what the lockfile names — use it to roll back or to
match another machine.

### Toggle LazyVim extras

`:LazyExtras` — the UI writes `lazyvim.json`. Commit the change.

### Propagate a shared change from `main` into every other profile

After committing a shared change (a new plugin under `lua/plugins/`, a
`lazyvim.json` extra) on `main`:

```sh
cd ~/.config/nvim
./propagate.sh
```

`propagate.sh` loops **every** worktree except `main` (today just `rust`, plus any
profile you add later). For each it merges `main`, auto-resolves the
`lazy-lock.json` conflict, runs `:Lazy! install` in that profile, and commits the
finished merge. Any conflict outside `lazy-lock.json` aborts that profile's merge
and stops the script — resolve that branch by hand. It does not push, and a new
Mason/treesitter dependency still has to be added to `bootstrap.sh` yourself.

For a version bump or a plugin removal (which `:Lazy! install` will not pick up),
or a single fix, do it by hand instead:

```sh
cd ~/.config/nvim-rust
git merge main            # or: git cherry-pick <sha>
nvim   # :Lazy sync / :Lazy clean as needed, then commit lazy-lock.json
```

Commits on `main` do **not** reach other branches automatically — branches are
independent pointers.

### Push

```sh
cd ~/.config/nvim
git push origin main rust        # first push of rust: add -u
```

One remote. A single `push` can send every branch.

---

## Add a new profile

Example: a `go` profile.

```sh
cd ~/.config/nvim
git branch go main
git worktree add ~/.config/nvim-go go

cd ~/.config/nvim-go
# enable Go extras via :LazyExtras, add lua/plugins/go.lua as needed
nvim --headless "+Lazy! sync" +qa
git add -A && git commit -m "go profile"
git push -u origin go
```

Then `NVIM_APPNAME=nvim-go nvim`. Update `bootstrap.sh` to add the worktree and its
Mason/treesitter step.

### Remove a profile

```sh
git worktree remove ~/.config/nvim-go
git branch -D go                         # optional
rm -rf ~/.local/{share,state,cache}/nvim-go
```

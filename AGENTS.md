# Agent guide — Neovim config

Read `README.md` first for the full picture. This file is the short version plus the
rules an automated change must not break.

## What this repo is

One LazyVim-based Neovim config. **Multiple profiles, one repo.** Each profile is a git
branch checked out as its own worktree at a path Neovim finds via `NVIM_APPNAME`:

| Profile | Branch | Worktree path | Data path |
|---------|--------|---------------|-----------|
| main | `main` | `~/.config/nvim` | `~/.local/share/nvim`, `~/.local/state/nvim` |
| rust | `rust` | `~/.config/nvim-rust` | `~/.local/share/nvim-rust`, `~/.local/state/nvim-rust` |

`rust` is `main` plus Rust tooling. Remote: `github.com/skylar-smith/lazyvim`.

## Rules

1. **Know which worktree you are in.** `git -C <dir> branch --show-current`. Edits in
   `~/.config/nvim` land on `main`; edits in `~/.config/nvim-rust` land on `rust`.
2. **Shared/general changes go on `main`, then merge into `rust`:**
   ```sh
   cd ~/.config/nvim      && <edit> && git commit
   cd ~/.config/nvim-rust && git merge main --no-edit
   ```
   Only Rust-specific changes are committed directly on `rust` (e.g. `lua/plugins/rust.lua`,
   Rust entries in `lazyvim.json`).

   For a shared **plugin add**, `./propagate.sh` (run from the `main` worktree,
   after committing) does this merge for every non-`main` worktree: merge,
   auto-resolve the `lazy-lock.json` conflict, `:Lazy! install`, commit. It
   aborts on any other conflict. It does not push, and does not handle version
   bumps / removals — merge those by hand.
3. **Never `git checkout <other-branch>` inside a worktree.** A branch is checked out in
   at most one worktree. Switching branches here corrupts the setup. Use the other
   worktree instead.
4. **Do not delete or move `~/.config/nvim/.git`** — it is the shared object store for
   both worktrees.
5. **Commit `lazy-lock.json`** whenever a plugin set changes (`:Lazy sync` / `restore`
   rewrites it). It is per-branch and is what `bootstrap.sh` restores.
6. **Do not configure `rust-analyzer` via `lspconfig` or `mason-lspconfig`.**
   `rustaceanvim` owns it. Rust LSP settings go under
   `opts.server.default_settings["rust-analyzer"]` in `lua/plugins/rust.lua`.
7. **Plugin specs**: one file per concern under `lua/plugins/`, each returns a spec
   table. A second spec for an existing plugin deep-merges its `opts` — prefer
   overriding over replacing. Match the existing file style (`stylua.toml`).
8. **LazyVim extras** are toggled through `lazyvim.json` (normally `:LazyExtras`).
   Editing that file by hand is fine; commit it.
9. Keep `bootstrap.sh` in sync when you add a profile or a Mason/treesitter dependency.

## Testing a change

```sh
# syntax / load check for the profile you touched
NVIM_APPNAME=nvim-rust nvim --headless "+checkhealth" +qa 2>&1 | grep -iE 'error|warning'

# plugin resolves and loads
NVIM_APPNAME=nvim-rust nvim --headless \
  -c "lua require('lazy').load({plugins={'<plugin-name>'}})" \
  -c "lua print(pcall(require,'<module>'))" -c "qa"

# LSP actually attaches (run from inside a real cargo project)
NVIM_APPNAME=nvim-rust nvim --headless <file>.rs \
  -c "lua vim.wait(15000, function() return #vim.lsp.get_clients({name='rust-analyzer'})>0 end)" \
  -c "lua for _,c in ipairs(vim.lsp.get_clients()) do print(c.name) end" -c "qa"
```

Headless gotcha: Mason and `nvim-treesitter` (main branch) install **asynchronously**
and are killed when headless nvim exits. Force-load the plugin, start the install, then
`-c "sleep <n>"` before `qa`. See `bootstrap.sh` for the working incantation.

## codecompanion (AI assistant in-editor)

`lua/plugins/ai.lua`. Chat adapter: `ollama` (HTTP, model `qwen3-coder`) — needs `ollama`
running, no `opencode`. `acp.claude_code` adapter available for Claude Code, using
`CLAUDE_CODE_OAUTH_TOKEN` env var. Unrelated to how you (an external agent) edit the
repo — it is a feature of the running editor.

## Do not

- Add a language server, formatter or linter without checking whether a LazyVim extra
  already provides it (`:LazyExtras`, or the `lazyvim.plugins.extras.*` tree).
- Bump Neovim-version assumptions below 0.11.
- Push without being asked. `git push origin main rust` sends everything.

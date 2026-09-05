#!/usr/bin/env bash
# Bootstrap this Neovim config on a fresh machine.
#
#   main branch  -> ~/.config/nvim        (full setup)
#   rust branch  -> ~/.config/nvim-rust   (Rust profile, via NVIM_APPNAME)
#
# Prereqs (install yourself, this script only checks):
#   neovim >= 0.11, git, a C compiler (treesitter builds parsers from source),
#   ripgrep, fd, fzf. For the Rust profile also: rustup with the rust-analyzer,
#   rust-src and clippy components. For the 99 plugin: opencode + ollama with the
#   model named in lua/plugins/99.lua.
set -euo pipefail

REPO="https://github.com/skylar-smith/lazyvim.git"
MAIN_DIR="$HOME/.config/nvim"
RUST_DIR="$HOME/.config/nvim-rust"

say() { printf '\033[1;36m>> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*"; }
die() {
  printf '\033[1;31mxx %s\033[0m\n' "$*" >&2
  exit 1
}

# --- prereq checks -----------------------------------------------------------
need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }
need git
need nvim
need lazygit
command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 || command -v clang >/dev/null 2>&1 ||
  die "no C compiler (cc/gcc/clang) - nvim-treesitter needs one"

for t in rg fd fzf; do
  command -v "$t" >/dev/null 2>&1 || warn "optional tool not found: $t (some pickers degrade)"
done

nvim_ver=$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
say "neovim $nvim_ver"

# Rust profile prereqs - warn only, do not block
if command -v rustup >/dev/null 2>&1; then
  installed=$(rustup component list --installed 2>/dev/null || true)
  for c in rust-analyzer rust-src clippy; do
    echo "$installed" | grep -q "^$c" || warn "rustup component missing: $c   (rustup component add $c)"
  done
else
  warn "rustup not found - Rust profile LSP/debug will not work until you install it"
fi

# --- clone + worktree ------------------------------------------------------
if [ -d "$MAIN_DIR/.git" ] || git -C "$MAIN_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  say "config already present at $MAIN_DIR - skipping clone"
else
  [ -e "$MAIN_DIR" ] && die "$MAIN_DIR exists but is not a git repo - move it aside first"
  say "cloning $REPO -> $MAIN_DIR"
  git clone "$REPO" "$MAIN_DIR"
fi

git -C "$MAIN_DIR" fetch --all --prune

if git -C "$MAIN_DIR" worktree list | grep -q "$RUST_DIR"; then
  say "rust worktree already present"
else
  [ -e "$RUST_DIR" ] && die "$RUST_DIR exists but is not the rust worktree - move it aside first"
  say "adding rust worktree -> $RUST_DIR"
  # track origin/rust if the local branch does not exist yet
  if git -C "$MAIN_DIR" show-ref --verify --quiet refs/heads/rust; then
    git -C "$MAIN_DIR" worktree add "$RUST_DIR" rust
  else
    git -C "$MAIN_DIR" worktree add "$RUST_DIR" -b rust --track origin/rust
  fi
fi

# --- plugins: install at locked commits ----------------------------------
for app in nvim nvim-rust; do
  say "$app: restoring plugins from lazy-lock.json"
  NVIM_APPNAME="$app" nvim --headless "+Lazy! restore" +qa
done

# --- mason tools + treesitter parsers (headless: force load, then wait) ---
say "nvim-rust: installing mason tools + treesitter parsers"
NVIM_APPNAME=nvim-rust nvim --headless \
  -c "lua require('lazy').load({plugins={'mason.nvim','nvim-treesitter'}})" \
  -c "lua local r=require('mason-registry'); r.refresh(function() for _,p in ipairs({'codelldb','stylua','shfmt','shellcheck'}) do local k=r.get_package(p); if not k:is_installed() then k:install() end end end)" \
  -c "lua require('nvim-treesitter').install({'rust','toml','ron','lua','bash','markdown','markdown_inline','json','yaml','vim','query'})" \
  -c "sleep 75" -c "qa" || warn "mason/treesitter step exited non-zero - open a .rs file in nvim-rust to finish"

# --- verify --------------------------------------------------------------
say "health summary (nvim-rust):"
NVIM_APPNAME=nvim-rust nvim --headless "+checkhealth" +qa 2>&1 |
  grep -iE '\b(ERROR|WARNING)\b' | head -20 || true

cat <<EOF

$(say "done")
  main profile : nvim
  rust profile : NVIM_APPNAME=nvim-rust nvim   (alias suggestion: nvr)

Next: open a real cargo project in the rust profile, run :LspInfo, confirm
rust-analyzer attaches. If mason/treesitter looked incomplete above, just open
a .rs file and wait ~1 min - LazyVim finishes the install on filetype.
EOF

#!/usr/bin/env bash
# Propagate an already-committed `main` change into every other profile worktree.
#
# Use this after you have added a shared plugin / extra on `main` and committed
# it. For each other worktree (rust, and any future profile) this script:
#   1. merges `main` into that branch
#   2. auto-resolves a lazy-lock.json conflict (the only conflict it will touch)
#   3. installs the newly-merged plugin specs headless (:Lazy! install)
#   4. commits the finished merge + updated lazy-lock.json
#   5. prints a checkhealth error/warning summary
#
# Scope / limitations:
#   - Handles the ADD-A-PLUGIN case. A version bump or plugin removal on `main`
#     is not reflected by `:Lazy! install` - run `:Lazy sync` / `:Lazy clean` in
#     the target worktree by hand for those.
#   - Only lazy-lock.json conflicts are auto-resolved. Any other conflict aborts
#     that profile's merge untouched and the script stops.
#   - Assumes each worktree dir basename is its NVIM_APPNAME (nvim, nvim-rust,
#     nvim-go, ...).
#   - Does not push. Run `git push origin --all` yourself when ready.
#   - A new Mason tool / treesitter parser still has to be added to bootstrap.sh
#     by hand.
set -euo pipefail

say()  { printf '\033[1;36m>> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mxx %s\033[0m\n' "$*" >&2; exit 1; }

command -v nvim >/dev/null 2>&1 || die "missing required tool: nvim"

# --- locate the main worktree (this script lives at its root) ----------------
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MAIN_DIR="$SCRIPT_DIR"
git -C "$MAIN_DIR" rev-parse --git-dir >/dev/null 2>&1 || die "$MAIN_DIR is not a git repo"

main_branch=$(git -C "$MAIN_DIR" symbolic-ref --short HEAD 2>/dev/null || true)
[ "$main_branch" = "main" ] || die "$MAIN_DIR is on '$main_branch', expected 'main' - run this from the main worktree"

# Uncommitted work in the main worktree does not affect the merge (only committed
# `main` is merged), but it will not be propagated - warn so it is not a surprise.
[ -z "$(git -C "$MAIN_DIR" status --porcelain)" ] \
  || warn "main worktree has uncommitted changes - only committed 'main' is propagated"

# --- enumerate target worktrees --------------------------------------------
targets=()  # "dir<TAB>branch"
dir="" branch=""
while IFS= read -r line; do
  case "$line" in
    "worktree "*) dir=${line#worktree } ; branch="" ;;
    "branch "*)   branch=${line#branch refs/heads/} ;;
    "detached")   branch="" ;;
    "")           # end of a record
      if [ -n "$dir" ] && [ "$dir" != "$MAIN_DIR" ] && [ -n "$branch" ]; then
        targets+=("$dir	$branch")
      fi
      dir="" branch=""
      ;;
  esac
done < <(git -C "$MAIN_DIR" worktree list --porcelain; printf '\n')

[ ${#targets[@]} -gt 0 ] || die "no other profile worktrees found - nothing to propagate"

# --- preflight -------------------------------------------------------------
for t in "${targets[@]}"; do
  d=${t%%	*}
  [ -d "$d" ] || die "worktree path missing: $d"
  [ -z "$(git -C "$d" status --porcelain)" ] || die "worktree has uncommitted changes: $d - clean it first"
done

say "propagating $(git -C "$MAIN_DIR" rev-parse --short main) (main) into: $(for t in "${targets[@]}"; do printf '%s ' "${t##*	}"; done)"

# --- per target ----------------------------------------------------------
summary=()
for t in "${targets[@]}"; do
  d=${t%%	*}
  b=${t##*	}
  app=$(basename "$d")

  say "$b ($app): merging main"
  if ! git -C "$d" merge main --no-edit; then
    unmerged=$(git -C "$d" diff --name-only --diff-filter=U)
    if [ "$unmerged" = "lazy-lock.json" ]; then
      say "$b: auto-resolving lazy-lock.json conflict"
      git -C "$d" show main:lazy-lock.json > "$d/lazy-lock.json"
      git -C "$d" add lazy-lock.json
    else
      git -C "$d" merge --abort
      die "$b: merge conflict in files other than lazy-lock.json:
$unmerged
resolve this branch by hand (cd $d && git merge main), then re-run."
    fi
  fi

  say "$b: installing merged plugin specs (:Lazy! install)"
  NVIM_APPNAME="$app" nvim --headless \
    -c "lua require('lazy').load({plugins={'lazy.nvim'}})" \
    -c "Lazy! install" \
    -c "sleep 20" -c "qa" \
    || warn "$b: :Lazy! install exited non-zero - open $app and run :Lazy install"

  git -C "$d" add lazy-lock.json
  if git -C "$d" rev-parse -q --verify MERGE_HEAD >/dev/null; then
    git -C "$d" commit --no-edit
  elif ! git -C "$d" diff --cached --quiet; then
    git -C "$d" commit -m "propagate: merge main + lazy-lock.json"
  fi

  say "$b: health summary"
  NVIM_APPNAME="$app" nvim --headless "+checkhealth" +qa 2>&1 \
    | grep -iE '\b(ERROR|WARNING)\b' | head -20 || true

  summary+=("$b	$(git -C "$d" rev-parse --short HEAD)")
done

# --- done --------------------------------------------------------------
say "done"
for s in "${summary[@]}"; do
  printf '  %-10s -> %s\n' "${s%%	*}" "${s##*	}"
done
cat <<EOF

Next:
  - review the merge commits in each worktree
  - git push origin --all   (from any worktree; sends every branch)
  - if this change added a Mason tool or treesitter parser, add it to bootstrap.sh
EOF

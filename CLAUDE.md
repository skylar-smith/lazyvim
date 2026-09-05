@AGENTS.md

Claude Code specific:

- This directory is a git worktree on branch `main`. `~/.config/nvim-rust` is a second
  worktree of the same repo on branch `rust`. Check `git branch --show-current` before
  committing so a change lands where you intend.
- Never run `git checkout <branch>` here — it breaks the worktree layout. Edit the other
  worktree directory instead.
- General changes: commit on `main`, then `cd ~/.config/nvim-rust && git merge main`.
- Do not push unless asked.

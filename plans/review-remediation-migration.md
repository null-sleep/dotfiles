# Migration steps: pulling the review-remediation changes on another machine

One-time steps after `git pull` on a machine that was set up before the
`dotfiles-review-remediation` series (24 commits; the plan doc has since
landed and been removed from `plans/` — see `git log --grep=review-remediation`
for the commit sequence). Files moved/added/deleted in that series need
restowing and agent reloads; everything else flows through the existing
symlinks with no action.

## Every machine

1. **If the pull errors on `zsh/.stow-local-ignore`** ("untracked working
   tree file would be overwritten by merge") — this machine created it
   locally per the old README instructions. Delete the local copy and
   re-pull; the file is now tracked with the same content:

   ```bash
   rm zsh/.stow-local-ignore && git pull
   ```

2. **Restow nvim** — cleans the dangling symlink left by the deleted
   `nvim/.config/nvim/README.md` and links the new `.stylua.toml`:

   ```bash
   cd ~/src/dotfiles && stow -R nvim
   ```

3. **`brew bundle`** — picks up the newly-required `elixir` (fixes the
   Mason `elixirls` install failure on every nvim launch) and `ruff`.

4. **First nvim launch:**
   - The orphan-plugin warning fires for `cursortab.nvim` — run the
     suggested `:lua vim.pack.del({'cursortab.nvim'})` once.
   - If spell check warns about a missing `.spl` (now untracked/gitignored),
     any `zg` regenerates it, or run
     `:mkspell! ~/.config/nvim/spell/en.utf-8.add`.

## Only on the yknotify machine (work laptop)

5. **Restow yknotify** — removes the old `~/yknotify.sh` and
   `~/Library/LaunchAgents/com.user.yknotify.plist` symlinks (their repo
   targets no longer exist, so they're dangling) and links the new layout
   (`~/.local/bin/yknotify-watch`, `com.dhruv.yknotify.plist`):

   ```bash
   cd ~/src/dotfiles && stow -R --no-folding yknotify
   ```

6. **Load the new agent** — the setup script boots out the legacy
   `com.user.yknotify` label itself, then bootstraps `com.dhruv.yknotify`.
   This is the machine where the old agent was respawn-looping against a
   hardcoded `/Users/dhruvjauhar` path, so this step is the actual fix
   landing:

   ```bash
   bash yknotify/setup-yknotify.sh
   ```

7. **Manually merge `~/.zshrc_work.zsh`** — the work machine's real file is
   a local copy, not a symlink, so the template improvements do NOT arrive
   via pull. Port these from `zsh/.zshrc_work.zsh` (or replace the local
   file with the template plus any local extras):
   - `bga` alias uses `$HOME`, not a hardcoded user path
   - colima/yknotify checks gated behind a once-per-boot `/tmp` stamp
   - `yknotify_check` looks for the `com.dhruv.yknotify` label and suggests
     `setup-yknotify.sh` instead of `launchctl load`

## No action needed

- Keymap changes (`<leader>T*` terminals, `sd` picker), picker enhancements,
  theme/claude-nvim/statusline script fixes, and all doc updates — flow
  through existing symlinks.
- Statusline scratch state — old `/tmp/claude-ctx-*` files are abandoned;
  `~/.cache/claude-statusline/` self-creates. The monthly cost log
  (`~/.claude/cost-log/`) is untouched.
- theme-follow agent — unchanged.
- iTerm2 — the folder-sync flow was never enabled anywhere; the tracked
  state export is the mechanism (see README → iTerm2).

Delete this file once every machine has migrated.

# Zed: settings.json churn from model and mode picks

Status: decided (2026-11-14), nothing built. Accept the drift and commit it
when it shows up. The git clean filter (option 3) is documented here in case
the churn starts to hurt. Zed 1.28.1, omp 18.20.2.

## Problem

Zed writes `zed/.config/zed/settings.json` through the stow symlink whenever
you pick a model or mode, so `git status` is rarely clean:

- `agent.default_model`: written when you pick a model in Zed's own agent.
- `agent_servers.omp.default_config_options` (`model`, `mode`): written when
  you pick a model, thinking level or mode in an omp thread.

`settings.json` already comments both blocks as expected drift, and
`docs/omp.md` (omp in Zed) says the same.

## What writes the block

Read from Zed `main` (`crates/agent_servers/src/custom.rs`,
`crates/agent_ui/src/config_options.rs`, `mode_selector.rs`), not run:

- `set_default_config_option` inserts `default_config_options[config_id]`.
  Its caller in `config_options.rs` runs after the agent accepts a change from
  a config selector. `mode_selector.rs` calls `set_default_mode` the same way.
- No startup or session-open path writes it. Opening Zed or a thread should
  not recreate a deleted block.
- `connect()` reads the block and hands it to the agent as session defaults.
  Without it, omp starts on `modelRoles.default` in `~/.omp/agent/config.yml`.

## Options

1. **Commit the drift when it shows up (chosen).** Usually a one-line diff, and
   safe across machines and `git pull`. Cost: an occasional
   `chore(zed): ...` commit.
2. **Delete the `default_config_options` block and leave it deleted.** Churn
   drops to the times you override the model in the picker. Cost: omp threads
   open on omp's own default instead of the model Zed remembered. Pair it with
   `omp config set modelRoles.default ...` so that default is the one you want.
   Zed will write the block back on the next deliberate pick, and that diff
   can then be discarded.
3. **Git clean filter that pins the Zed-owned blocks.** Not chosen; see below.
4. **`git update-index --skip-worktree`.** Rejected. It breaks `git pull` and
   `git stash` as soon as upstream touches the file, which already happened
   once.
5. **Copy the file instead of symlinking it.** Rejected. It stops the churn but
   also stops the rest of the settings from syncing.

## Option 3 in detail: git clean filter

Git sees fixed values for the Zed-owned blocks while the file on disk keeps
whatever Zed wrote.

- `.gitattributes`: `zed/.config/zed/settings.json filter=zedpin`.
- `.git/config`: `filter.zedpin.clean = <script>`. Git pipes the working-tree
  file through the script on `git status`, `git diff`, `git add` and
  `git commit`.
- The script rewrites `agent.default_model` and
  `agent_servers.omp.default_config_options` to canonical values and prints
  the result. The working file and the stow symlink are untouched.
- Any other edit to the file passes through unchanged and shows in the diff.

Why it was not chosen:

- **The filter config is not in the repo.** `.git/config` is not cloned, so
  every machine needs a setup step (a script plus a README entry). Without it
  git silently skips the filter and you are back to today's behavior.
- **`settings.json` is JSONC.** Comments and trailing commas rule out `jq`, so
  the script is a sed or regex edit that breaks if Zed changes how it formats
  those blocks.
- **No useful smudge side.** A smudge filter only sees the committed blob, not
  what Zed last wrote. After a `git pull`, `git stash pop` or
  `git checkout -- file` that touches the file, git writes the canonical
  values over Zed's and your model pick resets.
- **Committed values only change by editing the script.** `git add` always
  stores the canonical values, so a deliberate model change cannot be
  committed through git.
- **Confusing to debug.** The disk file and the git copy differ with nothing
  in the diff to say why.

## Revival trigger

Reconsider option 2 if the drift commits become noise in `git log`. Reconsider
option 3 only if option 2 is not enough and a per-machine setup step is
acceptable.

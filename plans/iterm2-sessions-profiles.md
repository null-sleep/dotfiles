# Plan: Leverage iTerm2 Profiles & Sessions

## Context

Today the `iterm2/` stow package only carries color presets
(`iterm2/*.itermcolors`) plus a single opaque snapshot,
`iterm2/iTerm2 State.itermexport`, synced via **Settings → General →
Preferences → "Load preferences from a custom folder or URL"** pointed at
`~/src/dotfiles/iterm2` (documented in README → [iTerm2](#iterm2)). That
snapshot is a gzip'd tarball of `~/Library/Application Support/iTerm2/`
**and** iTerm2's `UserDefaults.plist` — inspecting it shows it bundles the
one existing profile (`New Bookmarks` key, currently just `"Default"`) inside
a 51-key preferences blob, alongside unrelated app state: an (empty) AI chat
history DB (`chatdb.sqlite`), saved-window-state SQLite files, Python runtime
metadata, and log files. It's binary, opaque to `git diff`, and gets
regenerated wholesale on every export (see `chore(iterm2): update state
export with Job Name title toggle`).

There are currently:
- **1 profile** ("Default"), with separate light/dark color sets already
  configured per README → [Unified theme switching](#unified-theme-switching).
- **0 saved Window Arrangements.**
- **0 Dynamic Profiles, 0 Automatic Profile Switching rules, 0 Triggers.**
- A shell/nvim title-sync mechanism already in place
  (`zsh/.zshrc_config.zsh` `title()`/`_auto_title`, `nvim/.config/nvim/lua/titling.lua`)
  that Profile-level Title/Badge settings interact with.
- `rcmd` (README → rcmd) already owns system-wide app/window switching,
  which overlaps with iTerm2's own Hotkey Window feature — noted below so we
  don't duplicate it.

## Goal

Explain what iTerm2 Profiles and Sessions actually offer, then propose a
concrete, incremental way to manage the useful parts of that
(Profiles, mainly) through this dotfiles repo the same way `rcmd` and
`kitty` are — as diffable, versioned config — instead of relying solely on
the opaque full-state export.

---

## Feature explainer

### Profiles

A **Profile** is a named bundle of session defaults: colors, font, terminal
type, working directory, startup command, keyboard shortcuts, triggers, smart
selection rules, semantic history behavior, badge text, and tags. Every new
tab/window/split launches from a profile (usually `Default`, but any profile
can be bound to a specific hotkey, menu item, or `iterm2 -p` invocation).

- **Dynamic Profiles** — the actual mechanism for versioning profiles.
  iTerm2 watches `~/Library/Application Support/iTerm2/DynamicProfiles/*.json`
  and hot-reloads any file placed there — no restart needed. Each profile in
  the JSON is a `{"Profiles": [{...}]}` object with a required unique `Guid`
  and can inherit from another profile via `"Dynamic Profile Parent Name"`.
  This is the git-friendly alternative to profiles buried in the opaque
  `UserDefaults.plist`: plain JSON, diffable, stowable exactly like
  `kitty.conf` or `rcmd`'s `config.yaml`. **This is the main opportunity
  here** — right now the one profile that exists is *not* managed this way.
- **Automatic Profile Switching (APS)** — rules (hostname / username / path,
  with `*` wildcards, e.g. `prod-*.internal:/var/www`) that auto-switch a
  session's profile when its context matches — e.g. a red-tinted profile the
  instant you `ssh` into a production host, so you never run a destructive
  command in the wrong window by mistake. Requires iTerm2 Shell Integration
  installed on every host you want it to recognize.
- **Badges** — a semi-transparent text overlay on the session showing live
  variables (`\(user.name)`, `\(session.hostname)`, job name, path). This is
  the same knob the recent `Job Name title toggle` state-export commit
  touched — worth formalizing as a Dynamic Profile field instead of leaving
  it inside the opaque snapshot.
- **Triggers** — regex-matched against terminal output, firing an action:
  highlight text, ring a bell, run a coprocess, capture a value into a named
  mark, or auto-switch profile. E.g. highlight `FAIL`/`Error` red in CI logs,
  or bell only when a specific long-running build's "done" line appears.
- **Smart Selection / Semantic History** — quad-click selects by
  regex-defined "kind" (file path, `namespace::symbol`, URL, etc.);
  Cmd-click on a recognized string (e.g. a `file.go:42` stack-trace line) can
  open it directly — e.g. in Neovide/nvim, similar to the existing `<Space>o`
  Typora handoff. Configurable per-profile under **Advanced**.
- **Hotkey Window** — a profile-scoped, global-hotkey drop-down terminal
  (Quake-style). **Skip / low priority** — `rcmd` already covers system-wide
  fast app access, and stacking a second hotkey-driven terminal on top would
  just compete with it for the same use case.

### Sessions

- **Window Arrangements** — a saved snapshot of open windows, tabs, split
  panes, their profiles, and working directories. Save with `⌘⇧S`, restore
  with `⌘⇧R`, or set **Preferences → General → Startup → "Open saved window
  arrangement"** to auto-restore on launch. Good for a fixed daily layout
  (e.g. one window split into a shell pane + a log-tail pane), the same idea
  as the toggleterm-based bottom terminal panel already does inside nvim
  (`terminal.lua`), but at the OS-terminal-window level instead.
- **tmux Integration mode** (`tmux -CC`) — iTerm2 attaches to a real tmux
  session but renders its windows/panes as *native* iTerm2 tabs/splits
  (mouse drag-to-resize, real scrollback, etc.) while tmux still owns
  persistence across quits/crashes/reattaches from another machine.
  **Conflicts with the existing `zellij` setup** (README → Zellij) — this
  repo already standardized on zellij as the multiplexer. Do not add tmux
  -CC on top; it would be a second, redundant persistence layer. Skip unless
  zellij is ever replaced.
- **Native window/session restore** — separate from Arrangements, iTerm2 can
  restore exactly what was open at quit (regular macOS-style state
  restoration), independent of tmux/zellij.
- **Broadcast Input** — type into multiple panes/sessions simultaneously.
  Useful for driving several parallel SSH sessions (e.g. running the same
  command against a small fleet) but not something to wire into dotfiles —
  it's a manual, per-use toggle (**Session → Broadcast Input**), not
  persisted state.

---

## Proposed changes

1. **Migrate the `Default` profile to a Dynamic Profile.**
   In iTerm2: select the profile → **Other Actions → Copy Profile as JSON**.
   Paste into `iterm2/Library/Application Support/iTerm2/DynamicProfiles/default.json`,
   wrapped as `{"Profiles": [...]}`, and hand-add a stable `"Guid"` if one
   isn't already present. Stow it the same way `macos/` links
   `Library/LaunchAgents/*.plist` — `stow --no-folding iterm2` (folding would
   otherwise try to symlink the whole `Application Support/iTerm2/` tree).
   **Verify first** whether "Copy Profile as JSON" round-trips the
   3.4 "separate colors for light/dark mode" keys cleanly — if it does, this
   subsumes the manual `.itermcolors` import steps in README → [Unified
   theme switching](#one-time-iterm2-setup-single-profile-follows-macos) for
   *new* machines; if it doesn't, keep both (Dynamic Profile for
   everything else, manual color-preset import as documented today).
2. **Add 1–2 purpose-specific profiles**, only if there's an actual use —
   e.g. an `ssh` profile with a distinct badge/border color, paired with an
   Automatic Profile Switching rule for the hosts you actually SSH into
   regularly (needs Shell Integration on those hosts). Skip this if you
   don't SSH out often enough to justify it.
3. **Leave Hotkey Window and tmux -CC out of scope** (see reasoning above —
   both duplicate existing tools: rcmd and zellij respectively).
4. **Optional: one Window Arrangement** for a recurring daily layout, saved
   via `⌘⇧S`, only if there's a layout you reopen by hand often enough to be
   worth automating.
5. **Re-scope or retire `iTerm2 State.itermexport`.** Once the profile lives
   in a Dynamic Profile JSON and colors are handled as today, audit what's
   left in the full-state export that's actually needed — the AI chat DB,
   secure-user-defaults, and SQLite window-restoration files are
   machine/session state, not config, and don't belong in a version-controlled
   dotfiles repo. This is a **discussion point, not a decision** — don't
   delete the export without confirming nothing else in this repo/workflow
   depends on it round-tripping the full `UserDefaults.plist` (e.g. keyboard
   shortcuts, global key map, arrangement definitions once step 4 exists).

## Open questions

- Do you actually want per-host Automatic Profile Switching, or is a single
  profile with light/dark colors enough? (Step 2 is skippable.)
- Any recurring multi-pane layout worth a saved Arrangement, or is
  zellij inside a single iTerm2 window already covering that need?
- OK to stop syncing the full `iTerm2 State.itermexport` blob once Dynamic
  Profiles cover the profile itself, and pare the custom-folder sync down to
  just what iTerm2 actually needs from a custom preferences folder (colors +
  the `com.googlecode.iterm2.plist` it already writes there)?

## Verification

1. After adding the Dynamic Profile JSON: relaunch iTerm2 (or wait a few
   seconds — Dynamic Profiles hot-reload), confirm the profile appears in
   **Settings → Profiles** with the same name/Guid, and that light/dark
   colors still flip correctly with `theme dark` / `theme light` / macOS
   Appearance changes (regression check against the existing
   [Unified theme switching](#unified-theme-switching) setup).
2. `git diff iterm2/` should show a readable, line-level diff the next time
   a profile setting changes — the actual test that this is more
   git-friendly than the old opaque export.
3. If Automatic Profile Switching rules are added: SSH into a matching host
   and confirm the profile (colors/badge) switches automatically; SSH into a
   non-matching host and confirm it doesn't.

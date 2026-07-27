# Plan: zmx — persistent terminal sessions for nvim (and Ghostty)

**Status:** background + motivation captured 2026-07-26 — **no implementation
plan yet, deliberately.** Nothing installed; zmx is not in the Brewfile.
**Intent:** the "why" and the goalposts for adopting zmx, so the eventual spec
starts from a settled problem statement instead of re-deriving it. Read this
before designing the nvim integration.

---

## 1. What zmx is

[neurosnap/zmx](https://github.com/neurosnap/zmx) — "session attach/detach for
the terminal." Zig, MIT, ~1.9k stars, created 2025-10-10, v0.7.0 released
2026-07-23, actively developed. By Eric Bower (neurosnap), sponsored by
pico.sh. Docs at [zmx.sh](https://zmx.sh); the manifesto is his essay
[You might not need tmux](https://bower.sh/you-might-not-need-tmux).

**The thesis.** Most people run tmux for exactly one of its features — the
shell survives when the client goes away — and pay for it with a second
terminal layer that degrades the one they already chose: native scrollback,
mouse, colours, and a whole prefix-key language on top. zmx unbundles
persistence from multiplexing and ships only the former. From the README, in
caps: *"This project does **NOT** provide windows, tabs, or splits."* Ghostty
keeps owning tabs/splits; nvim keeps owning its own windows.

**How it works.**

```
client ──unix socket──> daemon ──> PTY (your shell)
                          │
                          └──────> ghostty-vt   (screen + scrollback state)
```

One daemon per session, one socket per session (under `/tmp/zmx`; `zmx version`
prints the socket and log dirs). The daemon tees PTY output to both the
attached client and `ghostty-vt` — **Ghostty's own VT engine, extracted as
`libghostty-vt`**. `ghostty-vt` is not in the input path; it is a passive
mirror that accumulates screen + scrollback so it can *re-hydrate* whatever
client attaches next. Per-session daemons mean a wedged or busy session can't
take the others down.

**Command surface** (`zmx help` for the full list):

| Command | Purpose |
|---|---|
| `zmx attach <name> [cmd...]` | Attach, creating the session if needed — the core verb |
| `zmx history <name> [--vt\|--html]` | Print a session's scrollback as text |
| `zmx run <name> [-d] <cmd...>` | Send a command without attaching |
| `zmx send` / `zmx print` | Raw input to the PTY / inject text into the display |
| `zmx tail <name>` | Follow a session's output |
| `zmx list [--short\|--where k=v]` | List sessions; sessions carry `k=v` labels |
| `zmx kill <name> [--force]` | Kill a session and its clients |

Install is `brew install neurosnap/tap/zmx` (zsh completions come with the
formula). Detach is closing the window, `zmx detach`, or `ctrl+\`. There is no
in-session prompt indicator by design — zmx exports `$ZMX_SESSION` and expects
the prompt to surface it.

## 2. Motivation — three losses, one root cause

<a id="nvim-terminal-buffers-cannot-be-restored"></a>
### 2.1 nvim: terminal buffers can't be restored

`lua/session.lua` removes `terminal` from `sessionoptions`, and the comment
there states the reason: restoring a terminal only re-spawns a fresh shell — no
scrollback, no in-session history — so there is nothing to gain and one thing
to lose (a restored sidekick CLI buffer falls out of sidekick's runtime
registry). That is a correct workaround for a limitation, not a preference.

The limitation is upstream and total: nvim cannot serialize terminal buffer
*contents* at all. `:mksession` records the command to re-spawn, nothing more.
The fix is a [GSoC 2026 proposal](https://github.com/neovim/neovim/discussions/39640)
(per-terminal UUIDs, VTerm scrollback + screen cells dumped as ANSI msgpack
under `stdpath('state')/term/`, a new `:termrestore`, ShaDa integration) —
proposal stage, maintainer asked for tracking issues, nothing merged, not in
nightly. toggleterm's "persist" is intra-process only: it survives toggles, not
`:qa`. And `lua/terminal.lua`'s pre-warm exists precisely because every launch
starts cold.

### 2.2 nvim: sidekick CLI sessions die with nvim

Already documented as a known non-persistence in `GUIDE.md`'s "what is not
persisted" list: *"Sidekick CLI sessions — die with nvim; surviving would need
the tmux/zellij backend left off in `ai.lua`."* Quitting nvim kills the Claude
Code session in it, along with everything that conversation had loaded. This is
the same problem as 2.1 wearing a different hat, and arguably the more painful
half.

Relevant trap when this gets designed: per `GUIDE.md` → "Sidekick's session
backends shell out on every lookup", sidekick's tmux/zellij backends register
on `executable(name) == 1` *alone* — not on `cli.mux.enabled` — and each adds a
~20ms `ps` scan to every `State.get()`, which is why tmux was kept off this
machine. zmx is not a sidekick backend today, so merely installing it costs
nothing there; anything that *makes* it one inherits that whole problem.

### 2.3 Ghostty: layout restores, contents don't

`window-save-state = always` is already adopted here (see
[ghostty-followups.md](ghostty-followups.md) §2.4) and restores window/tab/split
*layout* — deliberately not processes. Contents come back as fresh shells. The
request to fix that is
[#1847](https://github.com/ghostty-org/ghostty/issues/1847), open since
2024-06-08, 21 comments, heavily upvoted, no assignee, no milestone. In two
years the only maintainer comment on the thread is moderation (asking people to
stay on-topic and be respectful, with a warning about locking); no maintainer
has engaged with the design.

The stance that explains the stall is jcollie (MEMBER) in
[discussion #12055](https://github.com/ghostty-org/ghostty/discussions/12055),
2026-04-02: Linux waits for GTK's native session-management API (targeted at
GTK 4.24), because *"the only reason that macOS got session management support
is that macOS already had native platform support for session management. We do
not want to be writing our own session management system."* Ghostty implements
what the platform hands it — and no platform hands you terminal *contents*.
That is why the geometry half shipped and the scrollback half hasn't, and why
waiting is not a strategy. A community PR that did implement it for GTK,
scrollback included ([#12962](https://github.com/ghostty-org/ghostty/pull/12962),
2026-06-08), was auto-closed 19 seconds after opening by the vouch bot —
unvouched author, never reviewed on merit.

### 2.4 The root cause is the same in all three

Every one of these is one fact: **the PTY is owned by the client, so the
shell's state dies with the client.** It isn't an nvim bug or a Ghostty gap —
it's where the process lives. Move PTY ownership out of the client and all
three losses stop, without either project changing. That is exactly the
inversion zmx implements, and (satisfyingly) it does it with Ghostty's own VT
engine — solving #1847 out-of-process with the code from in-process.

## 3. Goal

**Primary — nvim terminals survive nvim.** `<C-/>` after restarting nvim lands
back in the same live shell, with its scrollback, in the right project. Same
for a *crash*, not only a clean `:qa`. Concretely: the thing
[session.lua](../nvim/.config/nvim/lua/session.lua)'s comment says is
impossible becomes possible for real, rather than nvim faking it by re-spawning.

**Secondary — Claude sessions survive nvim.** Remove line 2.2 from GUIDE.md's
not-persisted list: quitting nvim detaches from a Claude Code session instead of
killing it.

**Tertiary — Ghostty gets its contents back.** The clean division of labour is
the one both projects' constraints already imply: **Ghostty keeps owning
geometry** (`window-save-state`, platform-native, already working) and **zmx
owns contents.** Neither has to grow into the other's job. Prior art to study
rather than reinvent: [cad0p/ghostty-zmx](https://github.com/cad0p/ghostty-zmx)
(zmx-wrapped sessions + AppleScript layout restore, posted to #1847 on
2026-06-15) and [nicosuave/gmx](https://github.com/nicosuave/gmx).

**Accepted constraint — reboot ends every session (decided 2026-07-26).** zmx
persists a *process*, not a file: state lives in the per-session daemon's memory
behind a socket under `/tmp/zmx`, so a reboot takes all of it. That is fine and
in scope — every loss in §2 is *client* death (nvim quits, nvim crashes, Ghostty
updates), not machine death, and those are the ones worth fixing. Consequences
worth stating so this isn't re-opened as a bug:

- No on-disk serialization is wanted. Do **not** add a `zmx history`-dump-at-
  shutdown step (the ghostty-zmx author's mitigation) or reach for zellij's
  `serialize_pane_viewport` to close this gap — it's a decision, not a defect.
- Post-reboot, the first attach per session name creates a fresh shell. Session
  naming must therefore be *derivable* (from cwd/git root — see §5), never
  stored, so nothing has to be reconciled after a reboot.
- Still worth checking once, for behaviour rather than as a blocker: whether
  dead daemons leave stale sockets in `/tmp/zmx` that confuse the next `zmx
  attach`, or whether macOS's boot-time `/tmp` sweep handles it.

**Explicit non-goals.**

- **Not adopting a multiplexer.** No panes, splits, tabs, or prefix keys from
  zmx. If a design step starts wanting those, it has drifted — nvim and Ghostty
  already own that layer, which is the entire manifesto.
- **Not changing the terminal UX.** `<C-\>` floats and the `<C-/>` bottom panel
  keep behaving as they do; persistence is meant to be invisible until a
  restart, at which point the shell is simply still there.
- **Not patching Ghostty**, and not waiting on #1847 or the nvim GSoC work.
- **Not a scrollback-archive feature.** The goal is resuming live work, not
  building a searchable history corpus (`zmx history` may fall out of it for
  free; that's a bonus, not the target).

## 4. What success looks like

Observable outcomes, deliberately implementation-free:

1. `:qa`, relaunch nvim, `<C-/>` → the same shell, same scrollback, same cwd;
   a half-typed command is still sitting at the prompt.
2. `kill -9` the nvim process → same result. This is the one that distinguishes
   real persistence from a save-on-exit hook.
3. Two projects open in two nvim instances → two independent sessions, neither
   able to see the other's shell.
4. Ghostty quits and reopens (or auto-updates) → layout from Ghostty, contents
   from zmx.
5. Nothing regresses: no measurable startup cost, no `State.get` slowdown (2.2),
   no stray daemons accumulating for throwaway directories.

<a id="open-questions-not-answers"></a>
## 5. Open questions — to answer at spec time, not now

Reboot survival was one of these and is now settled — see §3's accepted
constraint. What's left:

- **`ctrl+\` collides with `open_mapping`** in `lua/terminal.lua`. Inside a
  toggleterm buffer nvim's terminal-mode map wins, so zmx's detach chord is
  simply unreachable there — harmless, but note that hiding the float does *not*
  detach the client, and decide whether detach needs a reachable binding at all.
- **Session naming and identity.** Keyed on cwd, git root, or cwd+branch?
  `persistence.nvim` is configured `branch = true`, so sessions are per
  directory *and* branch — a zmx naming scheme that ignores branch would
  silently diverge from the nvim session it's paired with.
- **Lifecycle and reaping.** `session.lua` refuses to save sessions for temp
  directories and `cleanup.lua` sweeps existing ones; zmx daemons need an
  equivalent story or `/tmp/zmx` becomes a graveyard. `zmx list --where k=v`
  labels look like the intended hook.
- **Double VT.** With nvim as the client, a zmx session's output is rendered by
  `ghostty-vt` (mirror) *and* nvim's vterm (display) — two independent
  interpretations of the same stream. Worth understanding before trusting
  `zmx history` output to match what the buffer showed.
- **Does the pre-warm still make sense?** `terminal.lua`'s 2000ms deferred
  `spawn()` exists to hide shell startup. Attaching to an already-running
  daemon may make it redundant, or may just move the cost.
- **Prompt indicator.** `$ZMX_SESSION` wants a segment in
  `zsh/.config/starship.toml` (Starship is the prompt here, per the Brewfile);
  zmx's README has a Starship `env_var` snippet to crib.
- **Relationship to zellij.** Present in this repo as a stow package but
  **commented out in the Brewfile** and not installed — currently unused,
  config-only. Its one edge over zmx was on-disk serialization, which §3 just
  declared out of scope, so it has no remaining claim on this problem: keep or
  drop the package on its own merits (multiplexing for remote/SSH work), not as
  a persistence fallback.
- **Ghostty launch shape.** Wrapping every shell in zmx vs. opt-in per
  window/tab — and how session identity survives a Ghostty layout restore that
  restores geometry with no memory of which zmx session belonged in which split.
  This is the part ghostty-zmx solves with AppleScript; expect it to be the
  hardest piece.
- **Docs and packaging obligations.** New tool → Brewfile entry, a `## ` Part 2
  section in root `README.md`, and a `## Contents` entry (repo `CLAUDE.md`
  rule). GUIDE.md's not-persisted list needs editing if 2.2 lands. Whether zmx
  needs a stow package at all is unclear — no config file is documented.

<a id="rejected-decided-against"></a>
## 6. Rejected / decided against

- **tmux or zellij as the host for nvim's terminals.** Would work, but drags in
  the whole multiplexer layer the manifesto rejects: a status bar rendering
  inside the float, Ctrl-chord collisions with `<C-\>`/`<C-/>`, nesting when
  nvim itself runs inside one. tmux additionally re-triggers the sidekick
  `State.get` scan (2.2), which is why it isn't installed here. zellij's one
  differentiator, reboot-surviving serialized scrollback, is explicitly out of
  scope per §3.
- **DIY: dump terminal buffers to logfiles on exit.** Considered and dropped.
  Hooking `PersistenceSavePre` to write `nvim_buf_get_lines` output under
  `stdpath('state')` yields plain text with no highlights, no live process, no
  re-attach — a transcript, not a session. `zmx history` is a strictly better
  version of the same idea, and free.
- **Patching Ghostty** (applying #12962 or similar to a release build) —
  unvouched, unreviewed, macOS-irrelevant (it's the GTK apprt), and it forks the
  terminal to get a feature a wrapper provides without forking anything.
- **Waiting for upstream**, either nvim's GSoC terminal restore or Ghostty
  #1847. Both are years-scale at best, and Ghostty's is arguably never-by-design
  given §2.3's stance.
- **Screenshotting panes at logout** (suggested on #1847) — not a serious
  option; recorded only so it isn't re-proposed.

## 7. Sources

- [neurosnap/zmx](https://github.com/neurosnap/zmx) · [zmx.sh](https://zmx.sh) ·
  [You might not need tmux](https://bower.sh/you-might-not-need-tmux) ·
  [zmx design writeup](https://bower.sh/zmx-session-persistence)
- [neovim/neovim#39640](https://github.com/neovim/neovim/discussions/39640) —
  GSoC 2026 work plan: restore `:terminal` buffers after restart
- [ghostty-org/ghostty#1847](https://github.com/ghostty-org/ghostty/issues/1847)
  — include scrollback history in state restoration
- [ghostty-org/ghostty#12055](https://github.com/ghostty-org/ghostty/discussions/12055)
  — `window-save-state` on Linux/GTK, and the no-own-session-management stance
- [ghostty-org/ghostty#12962](https://github.com/ghostty-org/ghostty/pull/12962)
  — the auto-closed GTK session + scrollback restore PR
- [cad0p/ghostty-zmx](https://github.com/cad0p/ghostty-zmx) ·
  [nicosuave/gmx](https://github.com/nicosuave/gmx) — Ghostty + zmx prior art

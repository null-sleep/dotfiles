# pi — a practical guide

How to actually use [pi](https://pi.dev) and the seven extensions this repo
installs. Install/setup steps live in README's `## pi` section; this is the
"what can it do and how do I drive it" reference. Everything here was checked
against the installed extension READMEs (all under
`~/.pi/agent/npm/node_modules/@narumitw/`) and this machine's config: pi on
OpenRouter, servers for Go/Rust/Lua on PATH, statusline seeded with
defaults + cost.

## Contents

- [The mental model](#mental-model)
- [Core pi in five minutes](#core)
- [Managing extensions](#managing)
- [pi-plan-mode — plan before touching code](#plan-mode)
- [pi-subagents — delegate work](#subagents)
- [pi-btw — side questions](#btw)
- [pi-lsp — targeted diagnostics](#lsp)
- [pi-statusline — the footer](#statusline)
- [pi-github-pr — ambient PR status](#github-pr)
- [pi-usage — OpenRouter spend](#usage)
- [Terminal setup](#terminal-setup)
- [Gotchas cheat-sheet](#gotchas)
- [Command quick-reference](#commands)

---

<a id="mental-model"></a>
## The mental model

1. **pi core is deliberately minimal.** No plan mode, no subagents, no fancy
   footer — those are all extensions. What core gives you: a TUI, a model
   picker, tools (`read`, `edit`, `write`, `bash`, `grep`, …), sessions.
2. **Extensions add two kinds of things:** slash **commands** you invoke
   (`/plan`, `/btw`, `/usage`, `/lsp`, `/statusline`, `/subagents`) and
   **tools** the *model* invokes (`lsp_diagnostics`, `subagent`, …). For the
   tool kind, you drive them by asking — "run diagnostics on the files you
   changed", "delegate the research to a scout".
3. **Each extension owns one config file**, `~/.pi/agent/pi-<name>.json` —
   optional, created on first settings save, machine-local (their settings
   UIs rewrite via rename, which is why none are stowed). Edits generally
   apply after `/reload` or a new session; pi-btw reads its file every
   invocation.
4. **Extension state shows up in the footer.** pi-statusline renders the
   other extensions' status entries (PR state, usage, plan state, subagent
   activity) below the main powerline — the footer is the shared dashboard.

<a id="core"></a>
## Core pi in five minutes

```bash
pi                    # interactive TUI in the current directory
pi -p "prompt"        # one-shot non-interactive run, prints the answer
pi --list-models      # sanity check — empty output means the key isn't resolving
```

Inside the TUI:

- `Ctrl+L` or `/model` — switch model.
- `Shift+Tab` — cycle thinking level (`off` → `minimal` → `low` → `medium` →
  `high` → `xhigh` → `max`, clamped to what the model supports).
- `Ctrl+O` — expand a collapsed tool-call row to its full details.
- `/settings` — pi's own settings (model, theme, keybindings).
- `/trust` — per-project trust; several extensions gate features on it
  (project agents, project LSP config).
- `/login openrouter` — OAuth flow, if ever preferred over the
  `OPENROUTER_API_KEY` env var this setup uses.

pi ships its full docs locally:
`ls "$(npm prefix -g)/lib/node_modules/@earendil-works/pi-coding-agent/docs"`.

<a id="managing"></a>
## Managing extensions

Extensions are npm packages registered in `~/.pi/agent/settings.json`'s
`packages` array and installed under `~/.pi/agent/npm/`. This repo's set is
installed by `pi/setup-extensions.sh` (idempotent; skips what's present).

```bash
pi list                        # what's installed
pi update --extensions         # update all (entries are unpinned by design)
pi install npm:@scope/pkg      # add one (plain npm install does NOT register it)
pi remove npm:@scope/pkg       # remove one
pi -e npm:@scope/pkg           # try one for a single session without installing
/reload                        # (in the TUI) reload extensions after config edits
```

If an update ever breaks one — pi-lsp has renamed config files/keys between
minor versions before — pin just that entry:
`pi install npm:@narumitw/pi-lsp@<last-good>`.

---

<a id="plan-mode"></a>
## pi-plan-mode — plan before touching code

Codex-style read-only collaboration: explore, ask, produce an
implementation-ready plan — with *enforced* read-only tools, not a polite
prompt. `edit`/`write` are blocked and `bash` runs through a fail-closed
parser that accepts inspection commands (plus `npm test`-style checks) and
rejects redirects, substitutions, background jobs, installs, and mutating
git. Extension tools are disabled during planning by default.

```text
/plan                 # state-aware menu (start, choose tools, settings, help)
/plan start           # enter plan mode directly
/plan <prompt>        # enter plan mode AND submit <prompt> as the first message
pi --plan             # start a whole session in plan mode
```

The flow: the agent explores, asks structured questions via
`plan_mode_question` (1–3 questions with options — answer or pick Other),
and finishes by calling `plan_mode_complete` with the full Markdown plan.
If a turn ends without a plan, plan mode just stays active; `/plan finalize`
explicitly asks it to finish. Then a menu offers:

- **Implement here** — restores full tools, implements in this session with
  the planning conversation as context (`/plan implement` is the direct route).
- **Start fresh and implement** — new session carrying *only* the approved
  plan, no planning chatter. The planning session survives as the parent —
  resume it to hand off again if the attempt is abandoned.
- **Export plan…** / `/plan export [path]` — write it to Markdown
  (default `PLAN.md`, never overwrites) and exit plan mode.
- **Save for later** / `/plan save` — park one plan in the session, outside
  model context; `plan saved` shows in the footer until implemented/cleared.

`/plan show` displays the stored plan any time; `/plan exit` discards it.
The footer tracks the lifecycle: `plan active` → `plan ready` → (`plan
saved`) → `plan implementing`.

Worth configuring in `~/.pi/agent/pi-plan-mode.json`: `safeSubcommands`
widens the read-only bash policy with reviewed validators — `git diff`,
`git show`, `git blame`, and `gh pr view`/`pr list`/`issue view`/`issue
list` (gh paths require `--json`). `status`/`log`/`rev-parse` etc. are
already built in. To use extension tools while planning (e.g. read-only
`lsp_diagnostics` or `subagent_consult`), opt in per-workflow via **Choose
tools, then start…** (`/plan tools`) — tools lock once planning starts.

<a id="subagents"></a>
## pi-subagents — delegate work

Child `pi` processes as focused workers, with four built-in agents:

| Agent | Purpose | Tools |
|---|---|---|
| `scout` | Read-only reconnaissance | read, grep, find, ls, bash |
| `planner` | Grounded implementation plans | read, grep, find, ls |
| `reviewer` | Independent review (recommends checks, doesn't run them) | read, grep, find, ls, bash |
| `worker` | General implementation | pi default tools |

These are **model-invoked tools** — you use them by asking pi to delegate:
"spawn a reviewer over my current diff", "send two scouts in parallel, one
over src and one over tests, then merge the findings". The delegation shapes:

- `subagent` — **blocking**: single task, parallel fan-out, fan-out + an
  aggregator that merges results, or a chain where each step gets
  `{previous}`. The main agent waits; use it when the answer is needed
  before it can continue. Max 8 tasks per call, but at most 4 children run
  concurrently; 10-minute default timeout per child.
- `subagent_spawn` + `subagent_send` / `subagent_manage` /
  `subagent_mailbox` — **detached**: returns an `agentId` immediately, the
  completion arrives as a message on a later turn. For broad research/review
  the current response doesn't depend on. Reusable — follow-ups keep the
  child's history.
- `subagent_consult` — one synchronous **read-only** child (tools forced to
  read/grep/find/ls), for reconnaissance that must not write.
- `subagent_inspect` — metadata only: list agents, runs, models, diagnose.

`/subagents` opens the manager: current delegation workflow (all methods /
async-only / blocking-only / disabled), running and retained agents, and
settings (`~/.pi/agent/pi-subagents.json`). While subagents run, the footer
shows their activity.

Custom agents are markdown with YAML frontmatter in `~/.pi/agent/agents/*.md`
(`name`, `description`, `tools`, optional `model` / `thinkingLevel`, body =
system prompt); project-local ones go in `.pi/agents/` and require project
trust + confirmation. `/reload` after adding one.

Two safety facts: subagents are **not sandboxes** — same OS user, same
filesystem; and concurrent write-capable agents in one cwd are rejected by
default (ask for `workspaceMode: "worktree"` for a disposable git worktree
when real isolation is needed; requires a clean repo).

<a id="btw"></a>
## pi-btw — side questions

Quick questions mid-task without polluting the main conversation — the side
thread sees your conversation but never joins it.

```text
/btw what does this borrow-checker error actually mean?
/btw is this API name idiomatic?
/btw                  # empty side thread (menu: start thread / settings)
```

The answer opens in a scrollable ephemeral view; keep typing follow-up
questions in the same thread (they share context). `Shift+Tab` cycles the
side thread's thinking level independently of the main session. `Ctrl+C`
cancels/leaves; closing discards everything by default.

The one way anything crosses back: after an answer, `Ctrl+R` opens a
bring-to-main picker — latest Q&A, everything from a chosen question on, an
exact line/character range, or the whole thread — and loads it into the main
**editor as an editable draft**. It is never auto-sent, and replacing an
existing draft asks twice.

Uses the session's current model (this setup pins nothing); to pin an
independent side-question model later, set
`~/.pi/agent/pi-btw.json` → `{ "model": "openrouter/<model-id>" }`.

<a id="lsp"></a>
## pi-lsp — targeted diagnostics

Gives the model two tools — `lsp_diagnostics` (structured diagnostics with
exact ranges) and `lsp_fix` (server source actions like `source.fixAll` /
`source.organizeImports`, preview by default, `write: true` to apply) — plus
`/lsp` for you, which lists the catalog and whether each server binary is on
PATH.

It **installs nothing** and runs no daemons: servers start per tool call and
shut down after. On this machine the default catalog finds `gopls`,
`rust-analyzer`, and `lua-language-server`; other languages are silently
skipped (not an error).

Basic use is prompting: "check lsp diagnostics on the files you just
edited", "run lsp_fix to organize imports in main.go". Know its place —
per its own README, it's for *targeted* mid-edit feedback when a full
lint/typecheck is slow; the repo's authoritative check commands still decide
done-ness.

To cover more languages, create `~/.pi/agent/pi-lsp.json` pointing at
binaries (e.g. mason's under `~/.local/share/nvim/mason/bin/`) — but a
custom config **replaces** the entire default catalog, so it must also
re-list gopls/rust-analyzer/lua-language-server.

<a id="statusline"></a>
## pi-statusline — the footer

Replaces pi's footer with a responsive powerline. Seeded here with
`model thinking context turn cost`, deliberately shaped after this setup's
Claude Code status line so the two read alike — the setup script writes
segments only, so the palette stays pi-statusline's own tokyo-night default:

```text
░▒▓ 🤖 sonnet-5 🧠 med 🪟 ctx 2.4%/272k 🔁 #36 💸 $0.42
```

Claude's line is `model · effort · ctx% · #msgs · sparkline` with a
right-flushed `5h/7d` rate-limit cluster. `thinking` maps to its effort flag
and `turn` to its message count; there's no sparkline segment, and `cost`
stands in for the rate limits, which mean nothing on pay-per-token
OpenRouter. `cwd`, `branch`, and `time` are left out for the same reason
Claude's line omits them — Ghostty's tab title and nvim's statusline already
carry them.

Reading it:

- **context** — `used%/window`; turns warning-colored at 70%, error at 90%
  (the same thresholds the Claude line uses). `?/272k` right after a
  compaction is normal.
- **turn** — the session's turn count, pi's analog of Claude's `#36`.
- **cost** — per-session model spend, totalled the same way as pi's native
  footer (includes subagent/consultation usage).
- Narrow terminal? Low-priority segments drop instead of clipping —
  `context` and `model` survive longest, `turn` goes first.

Two segments worth knowing about if you re-add them: **branch** carries
counters (`⇡` ahead, `⇣` behind, `+` staged, `~` modified/deleted, `?`
untracked, `!` conflicts; clean shows none), and **tools** takes no space
when idle but shows `💭 thinking` / `⚙ <tool>` with parallel counts while the
agent works.

`/statusline` opens the menu: **Appearance** (7 previewable palettes),
**Information** (minimal / balanced / detailed segment sets), **Advanced**
(reorder segments, line breaks, raw JSON editor), **Status** (effective
config + diagnostics). Every save is immediate and lands in
`~/.pi/agent/pi-statusline.json`. Full segment list:
`brand provider model thinking cwd branch tools context tokens cache cost time turn`.

Other extensions' entries (PR, usage, plan state, subagents) render on a
second line below the powerline with their own icons. If glyphs look broken,
the terminal font needs Powerline symbols — not an issue with this repo's
Ghostty setup.

<a id="github-pr"></a>
## pi-github-pr — ambient PR status

Zero commands, zero config: when the current branch has a GitHub PR, a
compact entry appears under the footer and refreshes every 60 s, after each
agent turn, and on branch change.

```text
PR #123: checks passing, approved, 7 comments
PR #123: checks failing (2), changes requested, 3 comments
PR #123: no checks, draft, no comments
```

The trailing count is comments + reviews combined. It deliberately never
fetches comment *bodies* — for the actual discussion, `gh pr view --comments`
or the web. No PR → no entry; `PR gh missing` / `PR gh auth` mean the `gh`
CLI needs installing or `gh auth login` (already done on this machine).

<a id="usage"></a>
## pi-usage — OpenRouter spend

`/usage` opens an interactive menu showing spend for the provider pi is
*currently* using — here, OpenRouter:

```text
Usage today:           $1.23
Usage this week:       $8.40
Usage this month:      $25.50
All-time usage:        $138.02
```

Menu actions: refresh, view another configured provider, view all. There are
intentionally no CLI-style arguments (`/usage --all` doesn't exist). A
compact footer entry (`openrouter $25.50 used`, or `$74.50 left` if the key
has a spend cap) refreshes every 5 minutes.

Semantics to remember: this is **per-API-key spend** from OpenRouter's
documented key endpoint — not the account-wide credit balance (that needs a
separate management key). It reuses pi's resolved credential; nothing to
configure.

---

<a id="terminal-setup"></a>
## Terminal setup

pi reads `Shift+Enter` (newline instead of submit) and `Option+Backspace`
(delete word) as distinct keys via the kitty keyboard protocol, so what you get
depends on the emulator. Upstream reference:
[pi.dev/docs/latest/terminal-setup](https://pi.dev/docs/latest/terminal-setup).

- **Ghostty** (the daily driver) — configured. `alt+backspace=text:\x1b\x7f` is
  bound and the old `shift+enter=text:\n` mapping is gone, since it swallowed
  the chord before pi could see it. Details in README's `## Ghostty` section.
- **Terminal.app** — nothing to configure. pi turns on enhanced key reporting
  itself, and where Terminal.app still sends a plain Return for `Shift+Enter`,
  pi falls back to reading the macOS modifier state directly. That fallback
  needs pi running on the same Mac as the terminal — **over SSH it can't see
  your keyboard**, so Shift+Enter degrades to submit. Use Ghostty for remote
  work.
- **JetBrains (RustRover/GoLand/IDEA) embedded terminal** — JediTerm can't
  distinguish `Shift+Enter` from `Enter` at all; there is no fix, so switch to
  Ghostty when you need multi-line input. What *is* fixed: `.zshrc_config.zsh`
  exports `PI_HARDWARE_CURSOR=1` when `$TERMINAL_EMULATOR` is
  `JetBrains-JediTerm`, so pi's caret stays visible (pi hides the hardware
  cursor by default, which reads as a missing cursor in JediTerm).
- **VS Code / Cursor integrated terminal** — not configured here, and not
  needed for VS Code 1.109.5+, which enables the kitty protocol by default.
  Cursor tracks an older VS Code base, so `Shift+Enter` submits instead of
  inserting a newline there — for pi, Claude Code, and opencode alike. Easiest
  fix is to run Claude Code's `/terminal-setup` once inside that terminal: it
  writes the binding below into Cursor's `keybindings.json` (leaving any
  existing binding alone) and flips `terminal.integrated.gpuAcceleration` to
  `"off"`. Or add it by hand to
  `~/Library/Application Support/Cursor/User/keybindings.json` (swap `Cursor`
  for `Code` on stock VS Code):

  ```json
  {
    "key": "shift+enter",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[13;2u" },
    "when": "terminalFocus"
  }
  ```

Claude Code and opencode want the same three things from Ghostty and are
covered by the same config: Option-as-Meta on (their `Option+P` / `Alt+B` /
`Alt+F` chords), no `shift+enter` override, and `Option+Backspace` reaching the
app. Neither needs anything pi doesn't.

<a id="gotchas"></a>
## Gotchas cheat-sheet

- `npm install` of an extension does **nothing** for pi — only `pi install`
  registers it in `settings.json`'s `packages`.
- Plan mode's read-only bash rejects unknown commands *fail-closed* — a
  blocked command means "not on the reviewed list", not "dangerous". Widen
  via `safeSubcommands`, not by fighting it.
- Plan mode disables extension tools by default — the agent can't consult
  subagents or run `lsp_diagnostics` while planning unless opted in via
  `/plan tools` before starting.
- `/plan export` never overwrites an existing file; pick a new path.
- pi-btw's side thread is discarded on close unless `Ctrl+R` brought
  something to the main editor first.
- A custom `pi-lsp.json` replaces the whole default server catalog — list
  every server, including the ones that already worked.
- Subagents and consultations bill like normal turns; their usage is
  included in the footer's `cost`.
- Extension config edits usually need `/reload` (pi-btw is the exception —
  read per invocation).
- Don't install `pi-starship` alongside pi-statusline — both own the footer.

<a id="commands"></a>
## Command quick-reference

| Command | Extension | What it does |
|---|---|---|
| `/plan`, `/plan <prompt>` | pi-plan-mode | Start/manage read-only planning |
| `/plan export [path]` | pi-plan-mode | Write the plan to Markdown |
| `/subagents` | pi-subagents | Delegation workflow + agent manager |
| `/btw [question]` | pi-btw | Ephemeral side thread |
| `/lsp` | pi-lsp | Show servers and PATH availability |
| `/statusline` | pi-statusline | Footer appearance/segments/settings |
| `/usage` | pi-usage | Provider spend menu |
| `/reload` | pi core | Reload extensions and their configs |
| `pi list` | pi core | Installed extension packages |
| `pi update --extensions` | pi core | Update all unpinned extensions |

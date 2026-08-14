# omp — a practical guide

How to actually use [omp](https://github.com/can1357/oh-my-pi) (Oh My Pi),
can1357's batteries-included fork of pi that trades pi's minimal core for one
fat binary with everything built in. Install/setup steps live in README's
`## omp` section; this is the "what can it do and how do I drive it"
reference. Everything here was checked against omp 17.2.15 (brew,
`can1357/tap`), its docs, and the repo-seeded config: OpenRouter Sonnet as
the seeded default model role (fill-in — a hand-picked model survives
re-runs), medium thinking, and the repo-owned theme/status-line/web-search
policy forced by `omp/setup-settings.sh`.

## Contents

- [The mental model](#mental-model)
- [Core omp in five minutes](#core)
- [Plan mode](#plan-mode)
- [Subagents — task, Agent Hub, advisor](#subagents)
- [Code intelligence — lsp, debug, hashline](#code-intel)
- [GitHub as a filesystem](#github)
- [MCP servers](#mcp)
- [Status line and theme](#statusline-theme)
- [Providers and model roles](#models)
- [Local memory and autolearn](#memory)
- [Magic keywords and session controls](#keywords)
- [nvim bridge](#nvim-bridge)
- [Gotchas cheat-sheet](#gotchas)
- [Command quick-reference](#commands)

---

<a id="mental-model"></a>
## The mental model

1. **omp is pi's inverse.** Everything this repo bolts onto pi as an
   extension — plan mode, subagents, LSP, a status line, PR state, usage —
   ships built in, alongside things pi doesn't have at all (DAP debugging,
   `pr://` URLs, memory backends, voice). 31 built-in tools; the model drives
   most of them, you drive the slash commands.
2. **One config store, one CLI.** Settings live in `~/.omp/agent/config.yml`
   (YAML, machine-local — omp writes to it, so it's seeded by
   `omp/setup-settings.sh` rather than stowed). `omp config list` shows every
   key with its current value; `get`/`set`/`reset` edit them; `/settings` is
   the same store with a menu. No per-feature JSON files to hunt down.
3. **Discovery providers read other agents' config.** omp scans `.omp`, then
   `.claude`, `.codex`, and `.gemini` (user and project level) for context
   files, skills, slash commands, agents, and settings. Practical upshot on
   this machine: `CLAUDE.md` files, `~/.claude` skills and commands all apply
   inside omp too — instructions written for Claude Code steer omp.
4. **`PI_*` is a shared namespace.** omp honors most `PI_*` env vars (it *is*
   pi under the hood), plus `OMP_*` ones. That makes existing terminal fixes
   free (see [Gotchas](#gotchas)) — and makes globally exporting pi-config
   vars dangerous, since both agents would obey.

<a id="core"></a>
## Core omp in five minutes

```bash
omp                    # interactive TUI in the current directory
omp -p "prompt"        # one-shot non-interactive run, prints the answer
omp -c                 # continue the previous session
omp -r                 # resume via picker (or -r <id-prefix>)
omp models             # available models by provider; `omp models refresh` re-fetches
omp config list        # every setting and its current value
omp completions zsh    # shell completion script (bash/zsh/fish)
```

Inside the TUI:

- `/model` — switch model. `Ctrl+P` / `Shift+Ctrl+P` — cycle the `cycleOrder`
  roles (`smol` → `default` → `slow`). `Alt+P` — temporary pick for this
  session; `Alt+M` — open the selector and assign roles.
- `Shift+Tab` — cycle thinking level (`minimal` … `max`; this setup seeds
  `defaultThinkingLevel: medium`).
- `Ctrl+O` — expand a tool-call row; `Ctrl+T` — toggle thinking blocks.
- `/settings` — the settings menu; `/hotkeys` — all active keybindings
  (remaps live in `~/.omp/agent/keybindings.yml`).
- `/login` — OAuth/key selector; `/login anthropic` jumps to one provider.
- `/usage` — provider usage and limits.

Tool approval defaults to `yolo` (auto-approve everything). `--approval-mode
always-ask|write|yolo` overrides per session; `tools.approvalMode` persists it.

omp's full docs ship in the repo:
[github.com/can1357/oh-my-pi/tree/master/docs](https://github.com/can1357/oh-my-pi/tree/master/docs)
(`settings.md` and `docs/tools/` are the ones worth bookmarking).

<a id="plan-mode"></a>
## Plan mode

Built in — no extension. `/plan` (or `Alt+Shift+P`) toggles it; `/plan
<prompt>` enters and submits in one step; `plan.defaultOnStartup: true` makes
every session start planning.

The flow: the agent explores, drafts the plan incrementally in
`local://<slug>-plan.md` (a session artifact, never the working tree), asks
preference questions via the `ask` tool (2–4 options plus a recommended
default), and submits by writing the slug to the internal `xd://propose`
device — approval happens only through the review UI that opens then
(`/plan-review` reopens it). Approving offers execution options and restores
write access. If `modelRoles.plan` is set, entering plan mode switches to
that model and switching back happens on exit.

`--plan-yolo` runs the whole ceremony headless: forced plan mode at start,
auto-approve on the first proposal, then implement on `--plan-yolo-into`
(default: the `smol` role).

**How enforcement differs from pi-plan-mode.** omp hard-guards `write`/`edit`
— they can only touch session-local artifacts while planning
(`plan-mode-guard`), and subagents spawned during planning get a read-only
toolset (`read`, `grep`, `glob`, `web_search`). But `bash` stays fully
enabled and is only *instructed* to be read-only by the system prompt —
there is no fail-closed command parser like pi-plan-mode's. With this
machine's `yolo` approval default, a confused model could run a mutating
command mid-plan; treat omp's plan mode as "working tree protected from the
edit tools", not a sandbox.

<a id="subagents"></a>
## Subagents — task, Agent Hub, advisor

**`task`** is the delegation tool — you use it by asking ("fan three scouts
out over src, tests, and docs, then merge"). One call takes shared `context`
plus a `tasks[]` batch; each item picks an agent type and can demand **typed
results** via a JSON `outputSchema` (validated, returned as structured data,
not prose). With `async.enabled` (default on), spawns return immediately and
results self-deliver into the conversation; `agent://<id>` holds a child's
full output, `history://<id>` its transcript.

Bundled agents: `scout` (read-only recon), `designer`, `reviewer`,
`security-reviewer`, `librarian`, `task` (general), `sonic` (fast/cheap).
Custom ones are markdown + frontmatter in `.omp/agents/` (project) or
`~/.omp/agent/agents/` (user). Note `.claude/agents` is deliberately *not*
read here (its frontmatter schema differs), even though Claude skills and
commands are discovered.

**Worktree-style isolation** is built in but off by default:
`task.isolation.mode` (`auto`, `apfs`, `reflink`, …) gives an `isolated`
flag per task — the child runs in a snapshot workspace and comes back as a
patch or a `omp/task/<id>` branch (`task.isolation.merge`). Isolated agents
are torn down after merging, not revivable.

**Agent Hub** (`Alt+A`) is the human-facing side: a live roster of every
subagent with status, cost, tokens, and current tool; `Enter` focuses one to
read its transcript and steer it by typing; `r` revives a parked agent, `x`
kills, `t` toggles tree view, double-tap `←` returns to the main session.
Finished agents idle, then park after a TTL — messaging them (Hub or the
model's `hub` tool) revives them with history intact. `/jobs` is the quick
async-job snapshot.

**Advisor**: set `modelRoles.advisor`, then `/advisor on` (or `--advisor`) —
a second model passively reviews each completed turn and injects notes,
interrupting only for concerns/blockers. Its transcripts show up in the Hub
as read-only rows.

<a id="code-intel"></a>
## Code intelligence — lsp, debug, hashline

- **`lsp`** — one tool, many actions: `diagnostics` (file, glob, or `"*"`),
  `definition`, `references`, `hover`, `symbols`, `rename`, `code_actions`,
  and raw requests. Servers are auto-detected from binaries on PATH (gopls,
  rust-analyzer, lua-language-server et al. from the nvim setup are found —
  no separate catalog to maintain, unlike pi-lsp). `--no-lsp` disables LSP
  tools, formatting, and diagnostics for a session.
- **`debug`** — a full DAP driver: launch/attach, source/data/instruction
  breakpoints, step in/over/out, evaluate, stack/scopes/variables, even
  memory reads. Adapters resolve like LSP servers do. Ask for it: "debug
  this test and break on the panic".
- **Hashline edits** — omp's `read`/`grep` output is line-anchored with a
  4-hex snapshot tag; `edit` consumes `[path#TAG]` patches (`PUT`/`CUT`
  against the tagged snapshot's line numbers). A stale tag is rejected and
  forces a re-read — structurally impossible to edit a file the model hasn't
  seen current. `write` creates or wholly replaces files.
- **`ast_edit` / `ast_grep`** — tree-sitter structural editing and search,
  for rename-shaped and pattern-shaped changes where line edits are clumsy.

<a id="github"></a>
## GitHub as a filesystem

The `read` tool resolves GitHub URLs like paths, via `gh` plus a shared
cache:

```text
pr://123                    # PR view (?comments=0 to skip discussion)
pr://123/diff               # changed-file list; /diff/2 one file; /diff/all everything
pr://owner/repo/123         # long form for other repos
pr://?state=open&author=me  # live PR list; issue:// works the same way
issue://456                 # issue view
```

Merge conflicts get the same treatment: `read <path>:conflicts` registers
the marker blocks, then `conflict://<N>` reads one and `/ours`, `/theirs`,
`/base`, `/both` select a side — no fragile string-matching on `<<<<<<<`.

The **`github` tool** (PR create/checkout/push, issue/code/commit search,
`run_watch` for live Actions runs) is **off by default** — flip
`github.enabled` in `/settings` → Tools if wanted. The `pr://`/`issue://`
reads work without it; both need `gh` authenticated (already done here).

<a id="mcp"></a>
## MCP servers

omp's own MCP config is `~/.omp/agent/mcp.json` — machine-local (omp writes
it, and there's a `.lock` sibling), so like `config.yml` it is **not stowed**.
Shape is Claude's, plus two cross-source override lists:

```json
{
  "mcpServers": { "slack": { "type": "http", "url": "https://mcp.slack.com/mcp" } },
  "disabledServers": ["github:github"]
}
```

`disabledServers` is the highest-precedence denylist and is keyed
`<source>:<name>` — it hides a same-named server from *any* discovered
source. `enabledServers` force-enables one whose source set `enabled: false`,
but can't override the denylist. `/mcp` lists everything with its status and
source file; there is no `omp mcp` CLI subcommand.

omp also inherits MCP servers from other harnesses' configs, which is why
most entries here come from Claude Code without being configured twice. At
**user** scope it reads `~/.claude.json` and `~/.claude/mcp.json`, plus
Codex, Gemini, Cursor, Windsurf, OpenCode, and installed Claude marketplace
plugins.

**The dotfile-vs-plain-name trap** (this bit us): the dot-prefixed
`.mcp.json` spelling is **project-scope only** — `.claude/.mcp.json` is read
relative to the *project* dir. A server parked at `~/.claude/.mcp.json` is
therefore treated as project config for `~/.claude/` and never loads in a
normal cwd, even though `~/.claude/mcp.json` (no dot) would. Claude Code's
own Slack server lives at exactly that path, so it was invisible to omp until
it was copied into `~/.omp/agent/mcp.json`. If a server shows up in Claude
Code but not in omp's `/mcp`, check the spelling before assuming an auth
problem.

HTTP servers using OAuth are discovered but stay disconnected until
authenticated once per harness — omp does not share Claude Code's OAuth
grant. Run `/mcp` in an interactive session and authenticate there; a
headless `omp -p` run can't complete the browser callback, so a server that
works interactively can still look absent from a piped probe.

<a id="statusline-theme"></a>
## Status line and theme

`setup-settings.sh` forces the repo-owned look, matching the Claude Code /
pi footer philosophy — plain, one line, no powerline chrome:

```yaml
statusLine:
  preset: custom
  separator: none
  transparent: true
  leftSegments: [model, context_pct, cache_hit, turn_count]
  rightSegments: [cost]
  segmentOptions:
    model: { showThinkingLevel: true }
```

Unlike pi, the footer isn't replaced by a stowed TypeScript port — it's
omp's native status line configured through settings, plus one
extension-registered segment (`turn_count`, below). Changing the look means
editing `setup-settings.sh` (the forced block) and re-running it.

The thinking level rides the `model` segment (` · ◑ med`). omp defaults it
on, so `showThinkingLevel` is pinned only to keep the forced block owning
the look; `statusLine.compactThinkingLevel: true` folds it into a glyph on
the model name instead of a suffix.

The segment registry has no extension API, but it isn't sealed: the package
root exports the live `SEGMENTS` record, segment ids are looked up in it at
render time, and the settings schema checks the segment arrays only as a
bare `array` — no id enum. The stowed
`turn-count.ts` extension registers a `turn_count` segment there and
`setup-settings.sh` appends the id to `leftSegments`, so `#N` (assistant
messages on the active branch — resume/branch/tree stay accurate) plus
Claude Code's context-growth bars render *inside* the native status line.
Bars: per-turn prompt-size deltas (input + cache read/write; shrinks clamp
to zero), last 15, scaled to the window max, drawn with `▁▂▃▄▅▆▇█` — same
algorithm as `claude/.claude/statusline-command.sh`. Without the extension
the unknown id renders invisible, and if the `SEGMENTS` export ever
disappears the extension falls back to the `ctx.ui.setStatus` hook-status
row. (`setFooter`, pi's whole-footer escape hatch, is still a no-op.)

Two gaps against pi's `claude-footer.ts` are accepted, not chased. **Context
colors are baked constants** (error ≥90%, purple ≥70%, warning ≥50%, plus
500k/270k/150k absolute-token floors) rather than Claude's two-tier 70/90.
And `cache_hit`/`cost` render `59.43%`/`$0.00` where the Claude footer shows
`CH59%`/`$0.003`.

Themes: omp keeps a **dark slot and a light slot** (`theme.dark:
dark-dracula`, `theme.light: light-catppuccin`, both built-ins) and picks
live using the terminal's reported background (OSC 11), re-evaluating when
the terminal appearance changes. That's why the repo's `theme` script has no
omp step — Ghostty flips its background, omp follows by itself. Custom
themes would go in `~/.omp/agent/themes/*.json`, but note built-in names
always win a name collision with a custom file.

**The `$HOME` quirks (two, related)**: omp refuses to *run* in `$HOME` —
launched there without `--allow-home` it silently switches its working
directory to a temp dir. And when it *does* read config with cwd `$HOME`
(`omp config get`, or an `--allow-home` session), the claude discovery
provider treats `~/.claude` as the *project* config dir, so
`~/.claude/settings.json`'s `"theme": "custom:active"` (Claude Code's theme
slot) shadows `theme.dark`. The auto-chdir means normal sessions never hit
the shadow — dark-dracula applies. Left unworked around deliberately; see
`plans/omp-integration.md`.

<a id="models"></a>
## Providers and model roles

omp routes everything through **model roles** — ten built-ins: `default`,
`smol`, `slow`, `vision`, `plan`, `designer`, `commit`, `tiny`, `task`,
`advisor`. Unset roles fall back to `default`/the active model, so this
setup configures exactly one:

```yaml
modelRoles:
  default: openrouter/anthropic/claude-sonnet-5
```

Role values accept a thinking suffix (`slow:
anthropic/claude-opus-4-5:high`). `cycleOrder` (default `[smol, default,
slow]`) decides what `Ctrl+P` cycles through. Roles feed features
automatically: `plan` for plan mode, `task` for subagents, `tiny`/`smol` for
titles and background classification, `commit` for `omp commit`.

**Reading OpenRouter GPT-5.6 names.** The picker exposes OpenRouter's full
catalog, so one base tier may appear four times. The axes are independent:

| Selector shape | What changes | Use in omp |
|---|---|---|
| `gpt-5.6-sol` | Synchronous request, default `standard` reasoning mode | Normal interactive work |
| `gpt-5.6-sol-pro` | Same Sol model with `reasoning.mode: pro` | Hard tasks where quality matters more than latency and token use |
| `gpt-5.6-sol:batch` | Standard reasoning through asynchronous batch processing | Offline bulk jobs, not a live session |
| `gpt-5.6-sol-pro:batch` | Pro reasoning through asynchronous batch processing | Offline bulk jobs needing Pro mode |

`pro` does not select a separately trained model. It makes the same model do
more work; per-token rates may match Standard, but a completed task can cost
more because hidden reasoning tokens are billed as output. Thinking effort
(`low` … `max`) remains a separate control inside either mode. `:batch` is a
delivery/pricing variant: results are asynchronous with a 24-hour completion
window and are typically 50% cheaper. Its presence in `/model` does **not**
make it suitable for an interactive omp role; do not assign a `:batch` entry
to `default`, `plan`, `task`, or another live role.

The tier word is different: `Sol` (flagship), `Terra` (balanced), and `Luna`
(fastest/cheapest) are distinct GPT-5.6 capability/cost tiers. For an
interactive coding session, start with the plain tier; choose `-pro` only for
a difficult task. Sources: [OpenAI reasoning
modes](https://developers.openai.com/api/docs/guides/reasoning#reasoning-mode),
[OpenRouter Sol Pro](https://openrouter.ai/openai/gpt-5.6-sol-pro), and the
[OpenRouter Batch API](https://openrouter.ai/docs/batch-quickstart).

**Using a Claude subscription instead of (or beside) OpenRouter**: run
`/login anthropic` — a browser OAuth flow; a Team/Enterprise seat and a
personal plan on one email count as two accounts and rotate automatically.
Then point roles at direct models (`omp config set modelRoles
'{"default":"anthropic/claude-sonnet-4-5"}'` or via `Alt+M`). Credential
resolution prefers stored OAuth over env keys, so after login `anthropic/*`
ids bill the subscription while `openrouter/*` ids keep hitting the API key
— you choose per role.

**Spend accounting**: `OPENROUTER_API_KEY` is shared with pi, so
OpenRouter's per-key spend (pi's `/usage`, the dashboard) mixes both agents.
omp's own `/usage` and the status-line `cost` segment are per-session and
unaffected.

<a id="memory"></a>
## Local memory and autolearn

`omp/setup-settings.sh` pins `memory.backend` to `local`. This enables the
automatic project-summary pipeline: eligible persisted primary sessions are
model-extracted, then consolidated into `MEMORY.md`, `memory_summary.md`, and
generated skills. Subagents and `--no-session` runs are excluded. Existing
sessions become eligible after the default 12-hour idle period; `/memory
enqueue` marks work that the next startup picks up.

Automatic consolidation and explicit lessons are separate paths. The local
backend decides retrospectively what to preserve from session history;
`autolearn.enabled` instead exposes the `learn` tool so the agent can record a
specific, verified lesson deliberately:

```yaml
autolearn:
  enabled: true
  autoContinue: false
  minToolCalls: 5
```

With the local backend, `learn` writes newest-first, deduplicated,
secret-redacted lessons to `memory://root/learned.md`. Consolidation does not
overwrite that file. A lesson is available for injection starting with the
next session, not immediately; lessons and the generated summary share the
startup injection token budget. The store keeps at most 100 lessons, with
2,000 characters of lesson content and 400 characters of optional context per
entry.

### Adding knowledge deliberately

Enable explicit lesson capture without automatic extra turns:

```bash
omp config set autolearn.enabled true
omp config set autolearn.autoContinue false
```

Then ask the agent directly: `Use learn to remember this project lesson: …`.
The agent calls `learn`; the lesson appears in
`memory://root/learned.md` and enters prompt context in the next session.

Merely stating a conclusion in a persisted session takes the automatic path:
`/memory enqueue` schedules later extraction, but does not store that sentence
directly. Consolidation may retain, rephrase, or omit it. Use `learn` when the
specific verified lesson matters.

| Information | Best location |
|---|---|
| Mandatory standing rule | `CLAUDE.md`, another discovered context file, or repository tooling |
| Durable lesson from experience | `learn` / `memory://root/learned.md` |
| General history and prior decisions | Automatic local consolidation |
| Temporary task state | Current conversation or resumed session |

The local backend has no Mnemopi-style `retain`, `recall`, or `memory_edit`;
`learn` is its supported explicit-write path.

The name **autolearn** overstates the default behavior. `enabled: true` makes
the tool and post-work capture nudge available, but `autoContinue: false`
does not spend an extra model turn when the agent stops—the passive reminder
rides the next turn. `autoContinue: true` performs that capture turn
automatically and costs additional tokens.

Use `learn` for verified debugging lessons, recurring workflow corrections,
and non-obvious project constraints. Put hard, standing rules in repository
instructions or documentation instead: memory is heuristic context and must
be checked against current files. Inspect it with `/memory view`,
`read memory://root/MEMORY.md`, and `read memory://root/learned.md`.
`/memory clear` deletes the active project's local memory data and artifacts.

<a id="keywords"></a>
## Magic keywords and session controls

Three **prose-only trigger words** inject hidden per-turn instructions (and
get a gradient highlight in the editor):

- `ultrathink` — careful multi-step reasoning; with auto-thinking it also
  selects the model's highest supported effort for that turn.
- `orchestrate` — the multi-agent contract: scope, delegate independent work
  in parallel, verify each phase.
- `workflowz` — deterministic multi-subagent pipelines via the `eval`
  kernel's `agent()`/`parallel()`/`pipeline()` helpers.

Matching is deliberate: exact lowercase, standalone prose only —
`orchestrated`, `orchestrate()`, code spans, and fenced blocks don't
trigger. Configure under `/settings` → Interaction, or `magicKeywords.enabled`
/ `.ultrathink` / `.orchestrate` / `.workflow` (note: the workflowz switch is
named `workflow`). The gradient stays even when injection is disabled.

Session controls worth knowing:

- `/vibe [prompt]` — director mode: the main session's tools shrink to
  `read` + `todo` + worker controls, and it delegates everything to
  persistent `fast` (sonic) / `good` (task) worker sessions, verifying their
  claims by reading touched files. Run `/vibe` again to exit (kills all
  workers). Mutually exclusive with plan/goal mode.
- `/btw <question>` — built-in ephemeral side question that sees the current
  session context without joining it; the exchange can be branched into its
  own session afterward.
- `/fresh` — resets *provider* stream state without touching the local
  transcript; the fix for a wedged provider session, not a "new chat"
  (that's `/new`; `/clear` empties context in place; `/compact` compacts;
  `/handoff` carries context to a new session).
- `/tree` and `/branch` — sessions are trees, not lines: navigate to any
  earlier point and continue from there; abandoned paths get summarized.

<a id="nvim-bridge"></a>
## nvim bridge

`~/.omp/agent/extensions/nvim-notify.ts` (stowed, alongside
`turn-count.ts`) is the sidekick attention bridge (running `»` / done `●`
marks in nvim's agent view). It's a port of the pi extension with two
omp-specific remaps: omp has
no `agent_settled` event, so it listens on `agent_end` gated by
`!willContinue && ctx.isIdle() && !ctx.hasPendingMessages()`, and `ctx.hasUI`
replaces pi's subagent env-var guard (omp task children run in-process).
No `@narumitw` packages are installed for omp — everything they backport to
pi is native here.

<a id="gotchas"></a>
## Gotchas cheat-sheet

- **Never export `PI_CODING_AGENT_DIR` or `PI_CONFIG_DIR` globally** — pi
  *and* omp both obey them; a global export silently relocates one agent's
  config into the other's. Use `omp --profile <name>` for isolation instead.
- The shared `PI_*` namespace also helps: the `.zshrc_config.zsh` JediTerm
  export of `PI_HARDWARE_CURSOR=1` fixes omp's cursor too, for free.
- omp won't run in `$HOME`: it silently auto-switches to a temp dir unless
  `--allow-home` is passed — surprising when a sidekick nvim session's cwd
  is `~` (relative file mentions resolve against the temp dir). Config reads
  from `$HOME` also shadow `theme.dark` (see
  [Status line and theme](#statusline-theme)).
- `web_search` is repo-pinned to `perplexity` → `public` with the
  `anthropic` OAuth backend excluded, even as a fallback
  (`setup-settings.sh`).
- `memory.backend` is repo-pinned to `local`. It consolidates persisted
  sessions into project-scoped summaries; inspect the active injection with
  `/memory view` and the full artifact with `read memory://root/MEMORY.md`.
- Built-in theme names beat same-name custom files in
  `~/.omp/agent/themes/` — a custom `dark-dracula.json` would be silently
  ignored.
- Plan mode's read-only promise covers `write`/`edit` (hard guard) but not
  `bash` (prompt-level only) — see [Plan mode](#plan-mode).
- `CLAUDE.md` files and `~/.claude` skills/commands steer omp too, via
  discovery providers. Instructions written "for Claude" are really "for
  every agent on this machine" now.
- The `github` tool is disabled by default (`github.enabled: false`);
  `pr://`/`issue://` reads work regardless.
- OpenRouter per-key spend mixes pi and omp — the shared key means neither
  agent's provider-side number is "just this tool".
- `config.yml` is deliberately not stowed — omp writes settings changes and
  migrations into it. Repo-owned defaults live in `omp/setup-settings.sh`;
  re-run it after machine setup, don't hand-copy YAML.
- A user-level MCP server must be at `~/.claude/mcp.json` (no dot) or
  `~/.omp/agent/mcp.json`. The `.mcp.json` spelling is project-scope only, so
  `~/.claude/.mcp.json` is silently skipped — see [MCP servers](#mcp).
- Approval defaults to `yolo`. If that's ever uncomfortable for a session,
  `omp --approval-mode write` prompts before anything `exec`-tier.

<a id="commands"></a>
## Command quick-reference

| Command | What it does |
|---|---|
| `/plan [prompt]`, `Alt+Shift+P` | Toggle plan mode |
| `/plan-review` | Reopen the plan approval UI |
| `/vibe [prompt]` | Toggle director/worker mode |
| `/btw <question>` | Ephemeral side question |
| `/model`, `Ctrl+P`, `Alt+M` | Switch / cycle / assign role models |
| `/login [provider]` | OAuth or API-key sign-in |
| `/usage` | Provider usage and limits |
| `/advisor on\|off` | Toggle the reviewing second model |
| `/jobs` | Async background-job snapshot |
| `/tree`, `/branch` | Navigate / fork the session tree |
| `/fresh` | Reset provider stream state (transcript untouched) |
| `/compact`, `/clear`, `/new`, `/handoff` | Context lifecycle |
| `/hotkeys` | Show active keybindings |
| `Alt+A` | Agent Hub (subagent roster) |
| `omp config list\|get\|set` | Settings from the shell |
| `omp models [refresh]` | Model catalog |
| `omp commit` | Generate a commit message |

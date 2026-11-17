# omp — a practical guide

How to actually use [omp](https://github.com/can1357/oh-my-pi) (Oh My Pi),
can1357's batteries-included fork of pi that trades pi's minimal core for one
fat binary with everything built in. Install/setup steps live in README's
`## omp` section; this is the "what can it do and how do I drive it"
reference. The guide was originally checked against omp 18.1.8; the setup
and search settings below were updated for 18.18.6 and 18.20.0. The repo
seeds OpenRouter and OpenAI Codex model-role presets, medium fallback thinking,
and the repo-owned theme/status-line/web-search policy through
`omp/setup-settings.sh`.

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
- [Zed — ACP thread or terminal](#zed-acp)
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

- `/model` — switch model through the full menu.
- `Ctrl+P` / `Shift+Ctrl+P` — cycle the configured presets forward/backward.
- `Alt+O` — open a fuzzy-searchable picker containing only those cycle
  presets; selection applies both the model and its configured thinking level.
- `Alt+P` — temporarily pick any available model for the current session.
- `Alt+M` — open the selector and assign models to roles.
- `Shift+Tab` — cycle thinking level (`minimal` … `max`; this setup seeds
  `defaultThinkingLevel: medium`).
- `Ctrl+O` — expand a tool-call row; `Ctrl+T` — show or hide thinking blocks.
- `/settings` — the settings menu; `/hotkeys` — all active keybindings
  (remaps live in `~/.omp/agent/keybindings.yml`).
- `/login` — OAuth/key selector; `/login anthropic` jumps to one provider.
- `/usage` — provider usage and limits.

The zsh `ompf` alias starts a new Luna/medium session with OpenAI priority
serving: `omp --model @luna --service-tier priority`. Inside an existing
session, `/fast` toggles the same service tier independently of the model role;
turn it off before switching to Terra or Sol unless they should also use the
more expensive priority tier.

Tool approval defaults to `yolo` (auto-approve everything). `--approval-mode
always-ask|write|yolo` overrides per session; `tools.approvalMode` persists it.

Reasoning summaries start hidden (`hideThinkingBlock: true`) but remain available
through `Ctrl+T`. `omitThinking` stays disabled: providers that honor it do not
return a summary to reveal.

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
write access.

**Which model plans** depends on where omp runs (probed on 18.20.2; evidence
in [`plans/omp-plan-mode-models.md`](../plans/omp-plan-mode-models.md)):

- **Terminal:** entering plan mode switches to `modelRoles.plan` (here
  OpenRouter Opus 5.5 at high) and exiting switches back. Override it for
  one launch with `omp --plan <id>` (or `PI_PLAN_MODEL`). An agent can't pick
  the planning model per call the way it picks a subagent model.
- **Zed (ACP):** plan mode ignores `modelRoles.plan` and keeps the thread's
  model and thinking. Switch to Plan, then pick the planning model and
  thinking in Zed's selectors, per thread, from the scoped list. Leaving Plan
  keeps that model (switch back by hand to implement on another). A model
  change can reset thinking: `high` dropped to `medium` on OpenRouter GPT-6.1
  Sol, GPT-6.1 Terra and GPT-6 Luna, and held on Claude (OpenRouter and
  subscription) and Codex GPT-5.6 Terra (probed 2026-11-16), so check thinking
  after picking the model.
- **Headless:** in testing, `--plan-yolo` planned on the default model, not
  the `plan` role, and `-p "/plan …"` never entered plan mode.

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

**Per-call model**: the setup forces `task.perCallModel: on`, which adds an
optional `model` to each task item, so "spawn a scout on opus" works like
Claude Code's subagent model choice. The selector must be an exact
`provider/model-id[:level]` the config already routes to — not a `@role`
alias — and an unmatched one fails rather than substituting. It conflicts
with an agent's `task.agentModelOverrides` entry or a `^model:level` prompt
tag. `task.perCallModelAllow` is derived from `cycleOrder` plus the
`*-sub` roles: each role's model as a canonical `provider/model-id` with no
`:level`, so those models are selectable per call at any thinking level (for
example `openrouter/anthropic/claude-opus-5.5:low` or `:xhigh`). The `*-sub`
roles (`sonnet-sub`, `opus-sub`, `haiku-sub`, `fable-sub`) are the direct
Anthropic subscription models, kept out of `cycleOrder`; plain "sonnet" or
"opus" means the OpenRouter one, so say "the sonnet sub model" for the
subscription one. Anthropic's catalog ids use dashes
(`anthropic/claude-sonnet-5-5`). Models reachable only through other roles
(`oa-*`, `glm-*`, `cheap-l`) still route normally; they just can't be picked
per call.

**Worktree-style isolation** is built in but off by default. Enable
`task.isolation.enabled` to allow an `isolated` flag per task; choose the
backend with `isolation.backend` (`auto`, `apfs`, `reflink`, …). The child
runs in a snapshot workspace and comes back as a patch or a `omp/task/<id>`
branch (`task.isolation.merge`). Isolated agents are torn down after merging,
not revivable.

**Agent Hub** (`Alt+A`) is the human-facing side: a live roster of every
subagent with status, cost, tokens, and current tool; `Enter` focuses one to
read its transcript and steer it by typing; `r` revives a parked agent, `x`
kills, `t` toggles tree view, double-tap `←` returns to the main session.
Finished agents idle, then park after a TTL — messaging them (Hub or the
model's `write agent://<id>`) revives them with history intact. `/jobs` is the quick
async-job snapshot.

**Advisor**: this setup assigns `openrouter/deepseek/deepseek-v4.1-flash-1017:high` to
`modelRoles.advisor` but leaves `advisor.enabled` false. Opt in with
`/advisor on` (or `--advisor`) when a second model passively reviewing each
completed turn is worth the added usage. It injects notes, interrupts only
for concerns/blockers, and appears in the Hub as a read-only row.

<a id="code-intel"></a>
## Code intelligence — lsp, debug, hashline

- **`lsp`** — one tool, many actions: `diagnostics` (file, glob, or `"*"`),
  `definition`, `references`, `hover`, `symbols`, `rename`, `code_actions`,
  and raw requests. OMP enables a server only when its root marker is in the
  launch directory; Go therefore needs `go.mod`, `go.work`, or `go.sum` there.
  `omp/setup-settings.sh` records the resolved `gopls` executable in the
  machine-local `~/.omp/agent/lsp.json`, avoiding dependence on the launching
  terminal or GUI process's `PATH`. Start a new OMP session after changing it.
  `--no-lsp` disables LSP tools, formatting, and diagnostics for a session.
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
  compactThinkingLevel: true
  contextLine: percentage
  leftSegments: [model, context_pct, cache_hit, turn_count]
  rightSegments: [cwd_name, cost]
  segmentOptions:
    model: { showThinkingLevel: true }
```

Unlike pi, the footer isn't replaced by a stowed TypeScript port — it's
omp's native status line configured through settings, plus extension-registered
segments (`turn_count` and `cwd_name`, below) and a narrow wrapper around the
native `cost` segment. Changing the layout still means editing
`setup-settings.sh` (the forced block) and re-running it.

The thinking level replaces the usual model badge as a single glyph before
the model name. Both `showThinkingLevel: true` and
`compactThinkingLevel: true` are pinned so that concise marker survives omp
version/default changes; setting the latter to `false` adds the verbose
` · <level>` suffix instead.

The context gauge uses `percentage`: its colored fill shows context use without
the speculative-compaction and auto-compaction divider markers.

The segment registry has no extension API, but it isn't sealed: the package
root exports the live `SEGMENTS` record and segment ids are looked up there at
render time. OMP 18.2 warns about unknown ids while loading and its `config set`
command rejects them, so `setup-settings.sh` writes only the two segment arrays
with the system Ruby YAML parser, under OMP's config-file lock and with an
atomic rename. The stowed `turn-count.ts` extension registers a `turn_count`
segment there, so `#N` (assistant messages on the active branch —
resume/branch/tree stay accurate) plus Claude Code's context-growth bars
(`▁▂▃▄▅▆▇█`, same algorithm as `claude/.claude/statusline-command.sh`) render
*inside* the native status line. Without the extension the unknown id renders
invisible; if the `SEGMENTS` export ever disappears the extension falls back
to the `ctx.ui.setStatus` hook-status row. (`setFooter`, pi's whole-footer
escape hatch, is still a no-op.) Full audit and caveats:
[plans/omp-fork-customization.md](../plans/omp-fork-customization.md).

The stowed `cwd-name.ts` registers `cwd_name` the same way, on the right
side: the launch folder's basename, or just the worktree basename when omp
recognizes a linked worktree. A shell-launched omp therefore stays identifiable
without spending status-line width on the project prefix. When omp runs inside
an nvim sidekick terminal (`$NVIM` inherited) the factory skips registration —
nvim already shows the project — and the configured id renders invisible.

The stowed `openrouter-session-cost.ts` wraps the native `cost` renderer only
while the primary session's active model uses OpenRouter. Its session-owned
aggregate includes every unique OpenRouter assistant response in the primary
transcript (including abandoned branches), default/named advisor transcripts,
top-level and nested subagent transcripts, and advisors owned by those
subagents. OpenRouter generation metadata remains authoritative: BYOK
generations use `upstream_inference_cost`; other generations use `total_cost`.
OMP's catalog estimate is never substituted.

Each resolved response is stored as a hidden `openrouter-session-cost/v2` entry
with root-session, source, full-agent-id, and advisor-slug attribution. Response
id is the accounting identity, so duplicate transcript observations count once;
a durable v2 attribution wins on resume, otherwise a primary observation wins
before the auxiliary tree's stable path/line order. Existing v1 entries still
restore primary-response costs but are not rewritten solely for migration. A
resumed session therefore paints its saved aggregate before filesystem or
network reconciliation.

The display is `$2.87` while settled. `$2.87 + …` means the primary agent is
responding, the initial auxiliary scan is running, or a discovered generation
is awaiting metadata. Advisor/subagent calls have no primary extension event,
so they cannot be marked in flight before their finalized assistant line reaches
the JSONL; the incremental scanner checks about once per second during activity
and once per five seconds while quiescent. It reads only newly completed lines,
resets safely after truncation/replacement, ignores unrelated JSONL and symlink
escapes, and follows only OMP's file-to-same-stem companion directories.
It re-reads the session and artifact paths before every pass, so `/move`
preserves the aggregate and continues reconciliation from the relocated tree.

`$2.87 + ?` takes precedence after an exhausted metadata lookup or when an owned
transcript is unreadable or has a malformed complete record. A trailing partial
line is merely retried. Generation lookups retain the five-second timeout,
bounded retries, and four-request concurrency; session switch/shutdown cancels
both lookup and scan work.

Primary and top-level advisor requests resolve credentials through the primary
session id. Child responses and child advisors use that child transcript's
session id, preserving OMP's inherited credential affinity. OMP does not persist
an advisor's random provider-facing session id, so an installation with multiple
OpenRouter accounts cannot prove which account billed an advisor request; a
failed lookup remains `+ ?` instead of probing arbitrary credentials. This
repo's single configured OpenRouter key is unaffected.

Subscription and other non-OpenRouter models, plus focused subagent views,
delegate to the native renderer unchanged — including its `S0.66`-style
subscription-equivalent spend. Returning to the primary OpenRouter view shows
the same aggregate. Title/internal `completeSimple()` calls remain excluded, as
does per-turn subagent attribution because child transcripts do not persist the
spawning `parentToolCallId`. If the mutable segment export disappears, the same
OpenRouter value falls back to the hook-status row instead of breaking startup.

One gap against pi's `claude-footer.ts` is accepted, not chased. **Context
colors are baked constants** (error ≥90%, purple ≥70%, warning ≥50%, plus
500k/270k/150k absolute-token floors) rather than Claude's two-tier 70/90.
And `cache_hit` renders `59.43%` where the Claude footer shows `CH59%`.

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

omp routes everything through **model roles**. The default is OpenRouter Terra
at high thinking; built-in roles feed features such as plan mode, subagents,
background work, and `omp commit`. The cycle presets are roles named after
their models (`sonnet`, `luna`, `haiku`, `sol`, …); `smol` and `tiny` alias
`@haiku` and `slow` aliases `@sol` so background work keeps a cheap or strong
model. This setup exposes switchable cycle presets through model roles:

```yaml
cycleOrder:
  - default
  - sonnet
  - carbon
  - opus
  - sol
  - luna
  - haiku
  - auto-code
  - dseek
  - kimi
  - astra
  - fable
modelRoles:
  default: openrouter/openai/gpt-6.1-terra:high
  luna: openrouter/openai/gpt-6-luna:xhigh
  haiku: openrouter/anthropic/claude-haiku-5.5:medium
  terra: openrouter/openai/gpt-6.1-terra:high
  sol: openrouter/openai/gpt-6.2-sol@azure:xhigh
  smol: "@haiku"
  tiny: "@haiku"
  slow: "@sol"
  auto-code: openrouter/openrouter/auto-code
  dseek: openrouter/deepseek/deepseek-v4.1-flash-1017:max
  kimi: openrouter/moonshotai/kimi-k3.1-pro:high
  carbon: openrouter/google/gemini-4-carbon:high
  sonnet: openrouter/anthropic/claude-sonnet-5.5:high
  opus: openrouter/anthropic/claude-opus-5.5:high
  cheap-l: openrouter/z-ai/glm-5.3:max
  astra: openrouter/openai/gpt-6.2-astra:xhigh
  fable: anthropic/claude-fable-5-2:high  # subscription; OpenRouter Fable is ZDR-blocked
```

Existing role assignments survive setup re-runs; only missing role and tag keys
are seeded. The first run on a machine without a `luna` role migrates the old
`smol`/`slow` selectors to `luna`/`sol` and copies the old `default` to `terra`.
`terra` stays a role but is not in the cycle, since `default` selects the same
model. `setup-settings.sh` pins `cycleOrder` to the sequence above.
`Ctrl+P` cycles it; `Alt+O` opens the extension's fuzzy picker over the same
effective configuration and applies the selected role's model and thinking
suffix.

Beyond the cycle, `DEFAULT_ROLES` also seeds `*-sub` roles (`sonnet-sub`,
`opus-sub`, `haiku-sub`, `fable-sub`) for the direct Anthropic subscription
models. They are not in `cycleOrder`; they exist so a per-call subagent can
use "the sonnet sub model" (see [Subagents](#subagents)). `fable` and
`fable-sub` are the same model: OpenRouter's Fable is excluded by the
account's Zero Data Retention setting (kept on), so the cycle role uses the
subscription and `fable-sub` keeps the "X sub" name predictable. Fable on the
subscription draws on its own weekly cap; in the main session it falls back to
OpenRouter Opus 5.5 (see the fallback chains below), but per-call spawns have
no automatic fallback. The live config
can drift from the seeded defaults because seeding is fill-in-only; the
procedure for a model-update round is the `omp-models-sync` skill
(`agents/.agents/skills/omp-models-sync/SKILL.md`).

The `auto-code` preset uses [OpenRouter Auto Code](https://openrouter.ai/docs/guides/routing/routers/auto-code)
with a repo-owned hard allowlist: GPT-6 Luna, GPT-6.1 Terra, GPT-6.2 Sol,
Claude Sonnet 5.5, Claude Opus 5.5, and Gemini 4 Carbon. `setup-auto-code.sh`
merges the model override into machine-local `models.yml`, including a 1,000,000
token context window and a 32,768 token output limit. It uses Chat Completions:
OMP's OpenRouter Responses path did not enforce the request-body allowlist.
The seeded empty fallback chain keeps retry recovery on the router instead of
switching to an unrestricted model; an existing custom chain is preserved.

The allowlist uses exact OpenRouter model IDs, not role names, so update
`setup-auto-code.sh` when changing the pool. Role thinking suffixes and `@azure`
provider pins are not inherited; OpenRouter picks the model, effort, and provider.
There is no fixed task-cost cap, and an unavailable pool can fail a request.

The Carbon preset uses OpenRouter and `high` thinking, which the model
supports. Carbon is geared toward difficult, long-running tasks and can spend
more tokens per task than cheaper presets. Check current OpenRouter pricing
before long runs.

The GLM selectors also get model-specific automatic fallback chains, and the
subscription Fable model falls back to OpenRouter Opus 5.5 when its weekly cap
is hit or the login fails. All are seeded fill-in-only so later hand edits
survive setup re-runs:

```yaml
retry:
  fallbackChains:
    anthropic/claude-fable-5-2:
      - openrouter/anthropic/claude-opus-5.5:high
    openrouter/z-ai/glm-5.3:
      - openrouter/deepseek/deepseek-v4.1-flash-1017:max
      - openrouter/moonshotai/kimi-k3.1-pro:high
      - openai-codex/gpt-6.1-terra:high
    openrouter/z-ai/glm-5.3-flash:
      - openrouter/deepseek/deepseek-v4.1-flash-1017:max
      - openrouter/moonshotai/kimi-k3.1-pro:high
      - openai-codex/gpt-6-luna:high
```

`retry.modelFallback` is on by default. Model-selector keys apply whenever
that exact model is the active model of the main session or a role-routed
subagent, regardless of which role selected it (so the Fable key covers
`fable` and `fable-sub` there; per-call spawns get no automatic fallback). The first two GLM alternatives
preserve the OpenRouter path while moving off Z.AI; the final OpenAI Codex
entry also escapes an OpenRouter-wide limit, but Codex is a low-priority,
occasionally unavailable subscription, so that step may be skipped. The default
`cooldown-expiry` revert policy returns to the primary after its suppression
window ends. Unavailable providers or models are skipped.

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

`~/.omp/agent/extensions/nvim-notify.ts` (stowed, alongside `turn-count.ts`,
`cycle-model-picker.ts`, and `cwd-name.ts`) is the sidekick attention
bridge (running `»` / done `●` marks in nvim's agent view). It's a port of
the pi extension with two omp-specific remaps: omp has no `agent_settled`
event, so it listens on `agent_end` gated by
`!willContinue && ctx.isIdle() && !ctx.hasPendingMessages()`, and `ctx.hasUI`
replaces pi's subagent env-var guard (omp task children run in-process).
No `@narumitw` packages are installed for omp — everything they backport to
pi is native here.

<a id="zed-acp"></a>
## Zed — ACP thread or terminal

`omp acp` is a stdio ACP server built into the omp binary, wired as a
`custom` entry in `agent_servers` in the stowed Zed `settings.json` (the
registry `pi-acp` drives `pi`, not omp). Both modes share `~/.omp` auth,
config, model roles, and skills; they differ in UI and in which stowed
extensions run. Zed's generic comparison is in
[`docs/zed.md`](zed.md#agent-panel).

What the adapter forwards (probed on 18.4.12):

- File reads/writes go through Zed (`fs/*`) with diff content, shell runs in
  Zed terminals, and Zed's review loop and follow work — unlike Claude Agent,
  whose edits reportedly bypass review (not verified;
  [`docs/zed.md` → Agent edits](zed.md#diff-review-agents)). Approvals would
  arrive as permission cards, but ACP mode only skips bash approval when
  yolo is set *explicitly* — the built-in `tools.approvalMode` default
  doesn't count — so the Zed entry passes `--approval-mode yolo` (probed on
  18.20.0: without it, every bash call raised a card).
- Session modes Default / Plan (Zed's mode selector, `shift-tab`), plus
  model and thinking selectors. `default_config_options.model` is what Zed
  writes when you pick a model; it's expected drift — commit it or leave it
  uncommitted, but never discard it (that silently resets your pick).
  Plan mode here keeps the thread's model instead of switching to
  `modelRoles.plan`, so the selectors choose the planning model and thinking
  per thread (see [Plan mode](#plan-mode)). Stock omp's plan-approval card
  shows only the first 12 plan lines as plain text; the stowed
  `zed-plan-in-chat.ts` extension, enabled by the Zed entry's
  `OMP_ZED_PLAN_IN_CHAT=1`, posts the whole plan to the chat as markdown
  first and shortens the card to the question (verified with a scripted ACP
  client on 18.20.2; see
  [`plans/zed-omp-plan-approval-preview.md`](../plans/zed-omp-plan-approval-preview.md)).
- ~70 slash commands, skills as `skill:*`; images, embedded context, HTTP/SSE
  MCP servers; session list/load/fork/resume.
- No version lag: the adapter ships in the same binary as the CLI.
- Claude subscription in Zed's review loop: `omp login` (or `/login`) with
  Anthropic OAuth, then pick an `anthropic/…` model in the thread. The
  Claude ACP agent needs an API key for that; check `omp usage` if those
  models vanish (the refresh token expires). `omp/setup-model-labels.sh`
  suffixes them ` (sub)` so they differ from the identically named
  `openrouter/anthropic/…` entries.
- The same instructions and subagent setup as the terminal (probed on
  18.20.2 with a fresh `omp acp` using the Zed entry's flags): the global
  `~/.omp/agent/AGENTS.md`, the `RULES.md` sticky rule, the task tool's
  per-call `model` field, and the approved-model listing with role names
  (including the `*-sub` roles) all reach the thread. See
  [Subagents](#subagents).

ACP-specific catches:

- **After changing `AGENTS.md`, `RULES.md` or global `config.yml`, reload the
  agent in Zed (or restart Zed), not just open a new thread.** Zed keeps one
  `omp acp` process across threads. A thread started after a reload had the
  new global files (2026-11); whether a new thread in an older process picks
  them up was not confirmed, so reload to be sure.
- The Zed model scope (`~/.omp/agent/zed-models.yml`) skips the `oa-*` Codex
  roles on purpose: their ids also matched an OpenRouter and a Codex
  "GPT-5.6 Terra" that sat next to the intended GPT-6.1 Terra, and a plan ran
  on the wrong one. The roles still work in the terminal and for subagents. To
  get them back in Zed (for example with a Codex subscription), remove the
  `oa-` filter in `omp/setup-zed-models.sh` and re-run
  `omp/setup-settings.sh`.
- Unverified: whether fallback chains honour the `zed-models.yml`
  `enabledModels` scope. Several GLM chain entries (DeepSeek `v4-pro`, the
  Qwen models) match no pattern there; if chains respect the scope, a GLM
  fallback in Zed would skip to the Codex step.

What you lose in an ACP thread:

- The extensions: `nvim-notify` needs `$NVIM`, and `turn-count` and
  `cycle-model-picker` (`Alt+O`) only act when `ctx.hasUI`. The exception
  is `zed-plan-in-chat`, which only acts in ACP threads.
- omp's TUI: status line, theme, keybindings (Ctrl+P cycling), and launch
  flags such as `--goal` and `--profile`.

Rule of thumb: the terminal (sidekick in nvim, or a Zed Terminal Thread) is
the default, since the setup above lives there; an ACP thread for
review-heavy edits in a project open in Zed. One catch: a Terminal Thread
comes back as an empty shell after a Zed restart, so resume the omp session
with `omp -c` / `omp -r` (see
[`docs/zed.md`](zed.md#terminal-thread-restore)); ACP threads restore from
Thread History, subject to the adapter's session support.

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
- `web_search` uses the repo-pinned `modelRoles.web` and
  `retry.fallbackChains.web`: Perplexity, Public Web, then the non-hosted
  default engines. Hosted search is omitted to avoid an Anthropic fallback.
  OMP may prepend xAI for X-only queries; 18.20.0 also prepends Hacker News for
  HN-only queries.
  The old `providers.webSearchOrder`/`webSearchExclude` settings were migrated
  upstream to the web role and fallback chain (`setup-settings.sh`).
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

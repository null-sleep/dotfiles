# omp: subagent plan critique inside the Plan Review modal

**Status:** shipped (kept for: host-prototype invariants, 18.18 vs 18.22 option-shape contract, rejected alternatives, and post-upgrade upkeep) — 2026-11-19
**Intent:** documents how `omp/.omp/agent/extensions/plan-critique.ts` adds **Critique plan (subagent)** to omp's TUI `Plan Review` modal, why each design choice was made over its alternatives, and what to check after `brew upgrade omp`.

---

## Goal and UX

When omp proposes a plan (`write` to `xd://propose`, or `/plan-review`), the fullscreen `Plan Review` modal opens with a `continue with ◂ default | sonnet | carbon | opus | sol … ▸` model slider and the `Plan mode - next step` action list:

- `(0. Refine plan)` — shown at the top on 18.22+ only when inline annotations or section deletions exist
- `1. Approve and execute`
- `2. Approve and compact context`
- `3. Approve and keep context (~207k / 1m)`
- **`4. Critique plan (subagent)`** ← added by `plan-critique.ts` right below `Approve and keep context`
- `5. Save` (or `Refine plan` + `Save and quit` on 18.18.x)

Workflow:

- Arrow `←`/`→` on `continue with` to pick any cycle role (e.g. `opus`, `sol`, `sonnet`).
- Press `Enter` on **`Critique plan (subagent)`**:
  1. The modal closes as a plan refinement (plan mode stays active; session history and any inline plan edits stay intact).
  2. The planning agent spawns **one** read-only `task` subagent pinned to that slider role's exact `provider/model-id[@upstream][:level]` selector (`modelRoles[role]`) to verify the plan file against the live codebase.
  3. Once the subagent finishes, the planner writes a **Critique TL;DR (`<role>`)** (verdict + 3–5 bullets of what the critique flagged and what was changed or rejected) to `out://` so it stays visible in the chat transcript.
  4. The planner updates `local://<slug>-plan.md` (folding in any inline annotations you added in `Plan Review` before clicking Critique) and writes to `xd://propose`, reopening `Plan Review` automatically.
- Pressing `Enter` on any **Approve** row still exits plan mode and executes on the selected `continue with` slider role as usual.

---

## Research findings: omp's Plan Review & Plan Mode internals

Checked against omp **18.22.2** (`/opt/homebrew/bin/omp`) and **18.18.6** (`~/.local/bin/omp`):

### 1. Public `ExtensionAPI` vs. `InteractiveMode.prototype.showPlanReview`

| Capability | Public `ExtensionAPI` (`omp://extensions.md`) | Host prototype (`InteractiveMode.prototype.showPlanReview`) |
|---|---|---|
| Observe review open + read `planFilePath`, `title`, `tiers` | `yes` (`plan_review_requested` event) | `yes` (paired with `plan_review_requested`) |
| Add a row to `Plan mode - next step` | `no` — `resolvePlanReview` only accepts fixed ids (`execute`, `compact`, `keep`, `refine`, `save`) | `yes` — `options` array passed to `PlanReviewOverlay` is built right before `showPlanReview` |
| Read the `continue with` slider's highlighted role | `no` — slider `index` and `onChange(idx)` live in a local closure inside `handlePlanApproval`; `tiers` only lists available roles | `yes` — `extra.slider.onChange` can be wrapped in `showPlanReview` |
| Intercept keys while `PlanReviewOverlay` is open | `no` — `PlanReviewOverlay` captures terminal input until `Esc` | `yes` — native arrow/Enter/mouse selection works on the injected row |

Like `turn-count.ts` (`SEGMENTS` registry mutation) and `zed-plan-in-chat.ts` (`AgentSideConnection` / `AcpAgent` prototype wrappers), extensions loaded by omp receive the **host's live in-process module instances**, making `@oh-my-pi/pi-coding-agent/modes/interactive-mode` patchable without a fork.

### 2. What the three stock Approve options actually do (`InteractiveMode.#En`)

All three exit plan mode, restore write/edit tools, autosave the plan, switch to the `continue with` model (`executionModel`), and send the approved plan prompt:

| Choice | `preserveContext` | `compactBeforeExecute` | What happens to the planning conversation |
|---|---|---|---|
| `Approve and execute` | `false` | `false` | Runs `handleClearCommand()` first — wipes the session history, copies session artifacts + `local://<slug>-plan.md` into the fresh session, and starts clean (~5k–15k prompt tokens) |
| `Approve and compact context` | `true` | `true` | Runs LLM compaction with internal guidance preserving details needed for `planFilePath`, then executes with summary + plan |
| `Approve and keep context` | `true` | `false` | Keeps the entire planning transcript verbatim (~200k+ tokens); disabled automatically once context exceeds omp's fullness threshold |

**Default recommendation:** `Approve and execute`. omp's `plan-mode-active.md` prompt enforces self-contained plans, and switching models on `continue with` (e.g. Opus → Terra) invalidates prompt cache anyway. Keep context only when the plan relies on raw tool output from planning **and** stays on the same model/provider so the prefix hits cache.

### 3. `showPlanReview` signature change between 18.18.6 and 18.22.2

Between 18.18.6 and 18.22.2, `InteractiveMode.handlePlanApproval` changed how it calls `this.showPlanReview(planContent, "Plan mode - next step", options, callbacks, { slider })`:

- **18.18.6:** `options` is `string[]` (`["Approve and execute", "Approve and compact context", "Approve and keep context (~207k / 1m)", "Refine plan", "Save and quit"]`), `callbacks.disabledIndices` holds numeric indices (index `2` when `keep` is disabled), and `showPlanReview` resolves with the chosen **label string** (`"Refine plan"`).
- **18.22.2:** `options` is `ObjectChoice[]` (`{ id, label, detail?, meta?, disabled? }`) containing only `execute`, `compact`, and `keep`. `Refine plan` is passed separately as `callbacks.refine` (shown in the TUI only when annotations or section deletions exist) and `Save` is synthesized from `callbacks.onSave`. `showPlanReview` resolves with the chosen **choice id** (`"refine"`).

`injectCritiqueOption` branches on `typeof options[0] === "string"` so both shapes work:
- On `string[]`, it splices `"Critique plan (subagent)"` after `"Approve and keep context…"` and increments any `disabledIndices >= insertAt`.
- On `ObjectChoice[]`, it splices `{ id: "critique", label: "Critique plan (subagent)", detail: "…" }` after `id === "keep"`. Notice `PlanReviewOverlay.#A()` renders `[refine (if annotations), ...options, save]`, so `Critique plan (subagent)` always appears even when `Refine plan` is hidden.

### 4. Why `out://` works for the TL;DR inside Plan Mode

omp's `plan-mode-active.md` forbids plain-text assistant replies (`Turn ends ONLY: 1. ask … OR 2. write slug to xd://propose`), and `plan-mode-guard.ts` blocks ordinary file writes outside `local://`. However, `WriteTool.execute` explicitly exempts internal URLs whose write spec has `scope === "reply"` (`out-protocol.ts` sets `scope: "reply"` on `out://`):

- `const isExempt = writeSpec?.scope === "coordination" || writeSpec?.scope === "reply"` → skips `plan-mode-guard`.
- `out://` renders a standalone assistant Markdown block in the TUI transcript (`reply-write.ts`) without ending the turn, allowing the planner to post **Critique TL;DR (`<role>`)** to the chat, then edit `local://<slug>-plan.md` and write `xd://propose` in the same refinement turn.
- Note: `out://` rejects calls from `taskDepth > 0` ("Subagents cannot reply to the user through out://"), so the **parent** planning agent writes the `out://` TL;DR after reading the subagent's output.

---

## Key design decisions & rejected alternatives

<a id="decisions-and-rejected-alternatives"></a>

### 1. Delegate through native `"refine"` + `task` instead of calling `runStructuredSubagent` directly

- **Chosen:** When `showPlanReview` resolves with `critique`, populate `callbacks.onFeedbackChange(critiquePrompt)` and return `"refine"` (`"Refine plan"` on 18.18.x). `handlePlanApproval` then dispatches a normal refinement turn to the planner, which spawns one `task` subagent, posts the `out://` TL;DR, updates the plan, and re-proposes via `xd://propose`.
- **Rejected:** Importing `runStructuredSubagent` from `@oh-my-pi/pi-coding-agent/task/structured-subagent` inside the extension, running the subagent while the UI waits, and then feeding its raw text into `"refine"`.
  - Why rejected: `runStructuredSubagent` takes an internal `ToolSession` (~35 methods/getters constructed inside `sdk.ts`), bypasses Agent Hub (`Alt+A`) / TUI tool-call progress unless manually wired to `asyncJobManager`, and would still need a planner turn afterward to edit `local://<slug>-plan.md` and re-open `Plan Review`. Letting the planner call `task` uses omp's battle-tested plan-mode subagent sandbox (`GH()` in `structured-subagent.ts` automatically restricts tools to `read`, `grep`, `glob`, `web_search`, `ast_grep` and prepends `plan-mode-subagent.md`) and shows live progress in the TUI and Agent Hub.

### 2. Omit `agent` (use default `task`) instead of `agent: "reviewer"`

- **Chosen:** Instruct the planner to spawn default `task` (omitting `agent`) with `model: "<exact-selector>"`.
- **Rejected:** Spawning `agent: "reviewer"`.
  - Why rejected:
    1. Bundled `reviewer` defines a rigid JTD `output` schema (`overall_correctness: "correct" | "incorrect"`, `findings[].file_path`, `line_start`, `line_end`) built for **code diffs**, which fights architectural/prose plan critique and omits a natural TL;DR structure.
    2. In `structured-subagent.ts` (`zH`), passing a `perCallModel` throws a preflight error if `task.agentModelOverrides[agentName]` is ever set (`Per-call model conflicts with task.agentModelOverrides for agent "reviewer"`). Default `task` avoids both traps while still getting clamped to read-only tools by plan mode.

### 3. Resolve exact `provider/model-id[@upstream][:level]` from `getRoleModelCycle`

- **Chosen:** Resolve the slider role through `session.getRoleModelCycle(cycleOrder)` + `formatModelStringWithRouting(entry.model)` + `:thinkingLevel` (falling back to `settings.getModelRole(role)` and `plan_review_requested`'s `tiers`).
- **Why:** `task`'s per-call model validator (`hj` / `zH` in `structured-subagent.ts`) rejects `@role` aliases, patterns, and comma lists, and requires `@upstream` routing pins (`@azure` on `sol` / `luna`) to match `formatModelStringWithRouting`. Using `getRoleModelCycle` guarantees the exact string (`openrouter/openai/gpt-6.2-sol@azure:xhigh`, `anthropic/claude-fable-5-2:high`, etc.) and preserves the role's configured thinking level. Every role on the `continue with` slider comes from `cycleOrder`, which `omp/setup-settings.sh` already seeds into `task.perCallModelAllow`.

### 4. Populate `onFeedbackChange` instead of calling `ctx.resolvePlanReview` on pick

- **Chosen:** Inside `showPlanReview`'s `.then(...)`, call `wrappedCallbacks.onFeedbackChange(feedback)` (preserving any inline annotations the user already made in `latestFeedback`) and return `"refine"`. Also normalize `"critique"` → `"refine"` in `wrappedCallbacks.onClose` so `plan_review_resolved` listeners see a valid choice id.
- **Rejected:** Calling `ctx.resolvePlanReview(reviewId, "refine", { feedback })` after the user presses Enter on `Critique plan (subagent)`.
  - Why rejected: Pressing Enter in `PlanReviewOverlay` sets `#u = true` (committed) before resolving `showPlanReview`. Calling `resolvePlanReview` afterward invokes `overlay.selectOption("refine")`, which immediately returns `false` because `if (this.#u) return false`. Writing to `onFeedbackChange` sets `handlePlanApproval`'s local feedback variable `ee` directly before `if (we === "refine")` reads it on the next microtask.

### 5. Public-API-only `/plan-critique` command (not chosen as primary UI)

- A pure `ExtensionAPI` slash command / shortcut cannot add a row to `PlanReviewOverlay` or read keyboard input while the overlay holds focus (requiring `Esc` → command → separate model picker). Inline menu injection + slider reuse matches the native `Plan Review` flow with zero extra dialogs.

---

## Upkeep & known fragility

<a id="upkeep"></a>

`omp/.omp/agent/extensions/plan-critique.ts` depends on these unblessed host details (also listed under `Known fragility` in [`plans/README.md`](README.md)):

1. `@oh-my-pi/pi-coding-agent/modes/interactive-mode` remains importable from extensions and exports `InteractiveMode` with `prototype.showPlanReview`, alongside optional `@oh-my-pi/pi-coding-agent/config/registry` (`lookup("cycleOrder")`) and `@oh-my-pi/pi-coding-agent/config/model-resolver` (`formatModelStringWithRouting`).
2. `handlePlanApproval` passes `"Plan mode - next step"` as the prompt title, `{ slider }` in the 5th argument, and `onFeedbackChange` / `onClose` in the 4th argument, and treats a `"refine"` (or `"Refine plan"`) return value as a refinement submission using the latest `onFeedbackChange` text.

Fallback: if `InteractiveMode.prototype.showPlanReview` moves or fails to import, `loadHost()` returns `undefined` and `Plan Review` degrades cleanly to stock omp behavior (and if `registry` or `model-resolver` moves, `resolveCritiqueSelector` falls back to `settings.getModelRole(role)` and `plan_review_requested` `tiers`).

### Verification after `brew upgrade omp`

Run the zero-LLM smoke suite (takes ~12s; exercises unit helpers plus real PTY `PlanReviewOverlay` sessions for both Critique and Approve):

```bash
bun omp/tests/plan-critique-smoke.ts
```

 Also check `which -a omp`: if an older `~/.local/bin/omp` shadows `/opt/homebrew/bin/omp`, either remove `~/.local/bin/omp` or keep `plan-critique-smoke.ts` passing against both.

---

## Cross-references

- Extension: `omp/.omp/agent/extensions/plan-critique.ts` (linked via `stow --no-folding omp` into `~/.omp/agent/extensions/plan-critique.ts`).
- Smoke test: `omp/tests/plan-critique-smoke.ts`.
- Related plans:
  - [`omp-plan-mode-models.md`](omp-plan-mode-models.md) — how omp selects the planning model vs. post-approval execution model.
  - [`zed-omp-plan-approval-preview.md`](zed-omp-plan-approval-preview.md) — companion ACP extension (`zed-plan-in-chat.ts`) for plan review in Zed threads (where TUI overlays do not run).
  - [`omp-fork-customization.md`](omp-fork-customization.md) — background on omp's shared in-process module graph for extensions.

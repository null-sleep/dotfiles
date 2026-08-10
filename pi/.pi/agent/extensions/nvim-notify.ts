import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawn } from "node:child_process";

/**
 * pi → nvim agent-view attention bridge (Phase 3 of
 * plans/sidekick-agent-view.md). When pi runs inside an nvim sidekick
 * terminal, $NVIM and $SIDEKICK_SESSION are inherited and the shared hook
 * script (~/.claude/hooks/sidekick-notify.sh) does the RPC. pi has no
 * permission/question events, so this covers running (`»`) and done (`●`)
 * only — the urgent (`!`) tier stays Claude/opencode-exclusive.
 */

const SCRIPT = `${process.env.HOME}/.claude/hooks/sidekick-notify.sh`;

export default function nvimNotify(pi: ExtensionAPI) {
  // No-op outside sidekick (same guard as the script), and inside pi-subagents
  // children: those are full pi processes inheriting this env, whose events
  // would mis-attribute a mid-turn ring to the parent's row.
  if (!process.env.NVIM || !process.env.SIDEKICK_SESSION) return;
  if (process.env.PI_SUBAGENT_DEPTH) return;

  // Fire-and-forget; a notification must never block or fail a turn.
  const notify = (category: string, payload: unknown) => {
    try {
      const child = spawn("bash", [SCRIPT, category], {
        stdio: ["pipe", "ignore", "ignore"],
        detached: true,
      });
      child.on("error", () => {});
      child.stdin.on("error", () => {});
      child.stdin.end(JSON.stringify(payload));
      child.unref();
    } catch {}
  };

  pi.on("before_agent_start", () => notify("prompt-submit", { type: "before_agent_start" }));
  // agent_settled = run finished with no retry/compaction/continuation
  // pending; isIdle() filters the settle that precedes a queued follow-up.
  pi.on("agent_settled", (_event, ctx) => {
    if (ctx.isIdle()) notify("turn-complete", { type: "agent_settled" });
  });
  // Covers /clear-style replacement too (reasons: quit/reload/new/resume) —
  // parity with Claude's SessionEnd bookkeeping.
  pi.on("session_shutdown", (event) => notify("session-end", { type: "session_shutdown", reason: event.reason }));
}

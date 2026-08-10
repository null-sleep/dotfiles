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
  // No-op outside sidekick (same guard as the script); inside pi-subagents
  // children (full pi processes inheriting this env, whose events would
  // mis-attribute a mid-turn ring to the parent's row); and inside a claude
  // session's tool subprocess (same mis-attribution, claude's marker).
  // Other cross-agent nestings have no marker to key on; accepted, see the
  // plan's accepted-risk list.
  if (!process.env.NVIM || !process.env.SIDEKICK_SESSION) return;
  if (process.env.PI_SUBAGENT_DEPTH) return;
  if (process.env.CLAUDE_CODE_EXECPATH) return;

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
  // agent_settled already fires after retries/compaction/queued continuations
  // drain, with the run flag cleared first — so isIdle() is currently always
  // true here. Kept as a defensive no-op against that ordering changing.
  pi.on("agent_settled", (_event, ctx) => {
    if (ctx.isIdle()) notify("turn-complete", { type: "agent_settled" });
  });
  // Only reasons that end the conversation map to session-end (parity with
  // Claude's SessionEnd on /clear + resume). "reload" (extension/settings
  // reload, same conversation continues) and "fork" (session-tree fork)
  // must NOT clear a live ring mid-turn or an unseen `●`.
  pi.on("session_shutdown", (event) => {
    if (event.reason === "reload" || event.reason === "fork") return;
    notify("session-end", { type: "session_shutdown", reason: event.reason });
  });
}

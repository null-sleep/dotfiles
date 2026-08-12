import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { spawn } from "node:child_process";

/**
 * omp → nvim agent-view attention bridge (port of the pi extension; see
 * plans/sidekick-agent-view.md Phase 3). When omp runs inside an nvim
 * sidekick terminal, $NVIM and $SIDEKICK_SESSION are inherited and the shared
 * hook script (~/.claude/hooks/sidekick-notify.sh) does the RPC. Covers
 * running (`»`) and done (`●`) only — urgent (`!`) stays Claude/opencode.
 */

const SCRIPT = `${process.env.HOME}/.claude/hooks/sidekick-notify.sh`;

export default function nvimNotify(pi: ExtensionAPI) {
  // No-op outside sidekick (same guard as the script) and inside a claude
  // session's tool subprocess (events would mis-attribute to the parent's
  // row). Unlike pi there is no subagent env marker: omp task subagents run
  // in-process with their own extension runner — ctx.hasUI (false there, and
  // in print/RPC mode) is the per-event guard instead.
  if (!process.env.NVIM || !process.env.SIDEKICK_SESSION) return;
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

  pi.on("before_agent_start", (_event, ctx) => {
    if (ctx.hasUI) notify("prompt-submit", { type: "before_agent_start" });
  });
  // omp has no agent_settled; agent_end + willContinue/pending guards
  // approximate it (skip auto-retries and queued continuations). No isIdle()
  // here: omp emits agent_end to extensions while the prompt is still in
  // flight (isStreaming true), so that guard would eat the notification.
  pi.on("agent_end", (event, ctx) => {
    if (event.willContinue) return;
    if (ctx.hasUI && !ctx.hasPendingMessages())
      notify("turn-complete", { type: "agent_end" });
  });
  // No reason field to filter (unlike pi): omp emits session_shutdown only on
  // real dispose — reload/switch keep the extension runner alive.
  pi.on("session_shutdown", (_event, ctx) => {
    if (ctx.hasUI) notify("session-end", { type: "session_shutdown" });
  });
}

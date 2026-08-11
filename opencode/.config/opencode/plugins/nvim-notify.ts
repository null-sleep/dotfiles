// opencode → nvim agent-view attention bridge (Phase 3 of
// plans/sidekick-agent-view.md). Runs in-process in the opencode server,
// which sidekick spawned inside an nvim terminal job, so $NVIM and
// $SIDEKICK_SESSION are inherited and the shared Claude hook script
// (~/.claude/hooks/sidekick-notify.sh) does the RPC. Categories map onto
// the agent_events state machine: prompt-submit / turn-complete /
// needs-permission / needs-input / session-end.
import type { Plugin } from "@opencode-ai/plugin";
import { spawn } from "node:child_process";

const SCRIPT = `${process.env.HOME}/.claude/hooks/sidekick-notify.sh`;

export const NvimNotify: Plugin = async ({ client }) => {
  // Same guards as the hook script: no-op outside a sidekick-managed nvim,
  // and no-op when this opencode was spawned from a claude session's tool
  // subprocess (which inherits the sidekick env — events here would
  // mis-attribute to the claude row). Other cross-agent nestings have no
  // marker to key on; accepted, see the plan's accepted-risk list.
  if (!process.env.NVIM || !process.env.SIDEKICK_SESSION) return {};
  if (process.env.CLAUDE_CODE_EXECPATH) return {};

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

  // Subagent (task-tool) child sessions emit the same idle/deleted events as
  // the session the user prompted; forwarding theirs would ring `●` mid-turn.
  // parentID discriminates. Fail-open — an SDK hiccup degrades to a stray
  // ring, not a silently dead feature — but only a definitive answer is
  // cached: the client resolves errors as {data: undefined} rather than
  // throwing, and caching that as "main" would poison the filter for the
  // process lifetime (retry on the next event instead).
  const topLevel = new Map<string, boolean>();
  const isMain = async (id?: string) => {
    if (!id) return true;
    let main = topLevel.get(id);
    if (main === undefined) {
      try {
        const res = await client.session.get({ path: { id } });
        if (res.data) {
          main = !res.data.parentID;
          topLevel.set(id, main);
        }
      } catch {}
    }
    return main ?? true;
  };

  // session.idle is deprecated in favor of session.status{type:"idle"}; both
  // can fire for the same turn end — collapse them.
  const lastIdle = new Map<string, number>();
  const idle = async (id: string | undefined, payload: unknown) => {
    if (!(await isMain(id))) return;
    const now = Date.now();
    if (now - (lastIdle.get(id ?? "") ?? 0) < 2000) return;
    lastIdle.set(id ?? "", now);
    notify("turn-complete", payload);
  };

  return {
    "chat.message": async (input, output) => {
      const id = input.sessionID ?? output.message?.sessionID;
      if (await isMain(id)) notify("prompt-submit", { sessionID: id });
    },
    // The live bus publishes the v2 vocabulary (permission.asked /
    // question.asked, payload under `data`); the published v1 plugin types
    // still carry permission.updated with payload under `properties`
    // (verified against the 1.18.10 binary: zero "permission.updated"
    // strings). Normalize both shapes and answer to both names.
    event: async ({ event }) => {
      const ev = event as { type: string; properties?: any; data?: any };
      const p = ev.properties ?? ev.data ?? {};
      const id: string | undefined = p.sessionID ?? p.info?.id;
      switch (ev.type) {
        case "session.idle":
          await idle(id, event);
          break;
        case "session.status":
          if (p.status?.type === "idle") await idle(id, event);
          break;
        // Urgent is never subagent-filtered: a child session's ask still
        // blocks this terminal's turn.
        case "permission.asked":
        case "permission.updated": // pre-v2 name
          notify("needs-permission", event);
          break;
        case "question.asked":
          notify("needs-input", event);
          break;
        case "session.deleted":
          if (!p.info?.parentID) notify("session-end", event);
          if (id) {
            topLevel.delete(id);
            lastIdle.delete(id);
          }
          break;
      }
    },
  };
};

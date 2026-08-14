import * as host from "@oh-my-pi/pi-coding-agent";
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";

const STATUS_KEY = "turn-count";
const SEGMENT_ID = "turn_count";
const BAR_GLYPHS = "▁▂▃▄▅▆▇█";
const MAX_BARS = 15;

type UsageLike = { input?: number; cacheRead?: number; cacheWrite?: number };
type AssistantLike = {
  role?: string;
  timestamp?: unknown;
  responseId?: unknown;
  usage?: UsageLike;
};
type SegmentLike = {
  id: string;
  render(ctx: unknown): { content: string; visible: boolean };
};

/**
 * Turn count plus per-turn prompt sizes (input + cache read/write) on the
 * active branch. Consecutive equal sizes collapse into one sample, mirroring
 * the Claude Code statusline's growth history.
 *
 * `pending` is the message carried on a message_end/turn_end event: the core
 * emits those to extensions *before* persisting the message to the session,
 * so the branch alone is one turn stale at rest. Merge it unless the branch
 * already ends with it (matched by identity, then responseId + timestamp).
 */
function branchStats(ctx: ExtensionContext, pending?: AssistantLike) {
  let count = 0;
  const sizes: number[] = [];
  let last: AssistantLike | undefined;
  const take = (msg: AssistantLike) => {
    count++;
    const size =
      (msg.usage?.input ?? 0) + (msg.usage?.cacheRead ?? 0) + (msg.usage?.cacheWrite ?? 0);
    if (size > 0 && size !== sizes[sizes.length - 1]) sizes.push(size);
  };
  for (const entry of ctx.sessionManager.getBranch()) {
    if (entry.type !== "message" || entry.message.role !== "assistant") continue;
    take(entry.message as AssistantLike);
    last = entry.message as AssistantLike;
  }
  if (pending?.role === "assistant") {
    const persisted =
      last === pending ||
      (last !== undefined &&
        last.responseId === pending.responseId &&
        last.timestamp === pending.timestamp);
    if (!persisted) take(pending);
  }
  return { count, sizes };
}

/**
 * Context-growth sparkline, same shape as the Claude Code statusline bars:
 * deltas between consecutive prompt sizes (shrinks clamp to zero), last 15,
 * scaled to the window max. Empty until two samples produce a nonzero delta.
 */
function sparkline(sizes: readonly number[]): string {
  const deltas: number[] = [];
  for (let i = 1; i < sizes.length; i++) deltas.push(Math.max(0, sizes[i] - sizes[i - 1]));
  const recent = deltas.slice(-MAX_BARS);
  const max = Math.max(0, ...recent);
  if (max === 0) return "";
  return recent.map((d) => BAR_GLYPHS[Math.min(7, Math.floor((d / max) * 7))]).join("");
}

/**
 * Show the active branch's assistant-turn count and context-growth bars in
 * the native status line. The segment registry has no extension API, but the
 * package root exports the live `SEGMENTS` record and `renderSegment` looks
 * segments up by id at render time — so registering a `turn_count` entry here
 * makes the id usable in `statusLine.leftSegments` (verified in-process on
 * the installed 17.x binary: a patched segment renders in the editor's top
 * border). The settings schema validates the segment arrays only as a bare
 * `array` (no id enum), and unknown ids render invisible, so a plain omp
 * without this extension ignores the id instead of erroring. If the export
 * disappears or the record is frozen, fall back to the hook-status row via
 * `ctx.ui.setStatus`.
 *
 * Counting persisted assistant messages makes resume, branch, and tree
 * navigation accurate.
 */
export default function turnCount(pi: ExtensionAPI) {
  let activeSession: ExtensionContext["sessionManager"] | undefined;
  let current = { turns: 0, bars: "" };

  // `theme` is a reassigned module `var` (the OSC-11 auto-switcher swaps the
  // whole object), so resolve it per render — a captured snapshot would keep
  // stale colors after a light/dark flip. Call `fg` as a method: it reads
  // private fields and an unbound reference throws.
  const liveTheme = () => (host as { theme?: { fg(color: string, text: string): string } }).theme;
  const registry = (host as { SEGMENTS?: Record<string, SegmentLike> }).SEGMENTS;
  let inline = false;
  if (registry) {
    // A throw here (frozen record) would otherwise kill the whole extension;
    // a throw inside render() would escape the TUI render loop unhandled.
    try {
      registry[SEGMENT_ID] = {
        id: SEGMENT_ID,
        render: () => {
          try {
            if (current.turns === 0) return { content: "", visible: false };
            const text = current.bars ? `#${current.turns} ${current.bars}` : `#${current.turns}`;
            return { content: liveTheme()?.fg("dim", text) ?? text, visible: true };
          } catch {
            return { content: "", visible: false };
          }
        },
      };
      inline = !!registry[SEGMENT_ID];
    } catch {
      // fall through to the hook-status row
    }
  }

  const show = (
    ctx: ExtensionContext,
    opts: { pending?: AssistantLike; extraTurns?: number } = {},
  ) => {
    if (!ctx.hasUI) return;
    activeSession = ctx.sessionManager;
    const { count, sizes } = branchStats(ctx, opts.pending);
    current = { turns: count + (opts.extraTurns ?? 0), bars: sparkline(sizes) };
    if (inline) {
      // Segment state alone doesn't repaint; a no-op status clear does
      // (setHookStatus always calls requestRender).
      ctx.ui.setStatus(STATUS_KEY, undefined);
      return;
    }
    const text = current.bars ? `#${current.turns} ${current.bars}` : `#${current.turns}`;
    ctx.ui.setStatus(STATUS_KEY, current.turns === 0 ? undefined : ctx.ui.theme.fg("dim", text));
  };

  pi.on("session_start", (_event, ctx) => show(ctx));
  pi.on("session_switch", (_event, ctx) => show(ctx));
  pi.on("session_branch", (_event, ctx) => show(ctx));
  pi.on("session_tree", (_event, ctx) => show(ctx));

  pi.on("turn_start", (_event, ctx) => {
    // The upcoming assistant message is not in the branch yet; preview it.
    if (ctx.sessionManager === activeSession) show(ctx, { extraTurns: 1 });
  });
  // Bars grow mid-turn as each assistant message (tool round-trip) completes.
  pi.on("message_end", (event, ctx) => {
    if (ctx.sessionManager === activeSession)
      show(ctx, { pending: event.message as AssistantLike });
  });
  pi.on("turn_end", (event, ctx) => {
    if (ctx.sessionManager === activeSession)
      show(ctx, { pending: event.message as AssistantLike });
  });

  pi.on("session_shutdown", (_event, ctx) => {
    if (ctx.sessionManager !== activeSession) return;
    activeSession = undefined;
    current = { turns: 0, bars: "" };
    if (ctx.hasUI) ctx.ui.setStatus(STATUS_KEY, undefined);
  });
}

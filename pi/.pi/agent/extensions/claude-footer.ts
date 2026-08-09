import type { AssistantMessage } from "@earendil-works/pi-ai";
import type {
  ExtensionAPI,
  ExtensionContext,
  SessionEntry,
} from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

/**
 * Minimal Pi footer shaped after this repo's Claude Code status line:
 *
 *   gpt-5.6-sol-pro  med  ctx:2%  CH59%  #1                    $0.065
 *
 * No powerline blocks, lead glyph, emoji, provider-spend row, cwd, or branch.
 * Ghostty's title and nvim already show location; /usage owns provider spend.
 */

const HIDDEN_STATUS_KEYS = new Set(["usage", "statusline"]);
const DROP_ORDER = ["cache", "turn", "thinking", "cost", "model"] as const;
type SegmentName = "model" | "thinking" | "context" | "cache" | "turn" | "cost";

type Segment = {
  name: SegmentName;
  text: string;
  styled: string;
};

type UsageLike = {
  input?: number;
  cacheRead?: number;
  cacheWrite?: number;
  cost?: { total?: number };
};

function usageFromEntry(entry: SessionEntry): UsageLike | undefined {
  if (entry.type === "message" && entry.message.role === "assistant") {
    return (entry.message as AssistantMessage).usage;
  }
  if (entry.type === "message" && entry.message.role === "toolResult") return entry.message.usage;
  if (entry.type === "compaction" || entry.type === "branch_summary") return entry.usage;
  return undefined;
}

function summarizeUsage(entries: readonly SessionEntry[]) {
  let cost = 0;
  let latestCacheHitRate: number | undefined;

  for (const entry of entries) {
    const usage = usageFromEntry(entry);
    if (!usage) continue;
    cost += usage.cost?.total ?? 0;

    if (entry.type === "message" && entry.message.role === "assistant") {
      const input = usage.input ?? 0;
      const read = usage.cacheRead ?? 0;
      const write = usage.cacheWrite ?? 0;
      const prompt = input + read + write;
      latestCacheHitRate = prompt > 0 ? (read / prompt) * 100 : undefined;
    }
  }

  return { cost, latestCacheHitRate };
}

function shortenModel(id: string): string {
  const withoutProvider = id.includes("/") ? id.slice(id.lastIndexOf("/") + 1) : id;
  return withoutProvider
    .replace(/^claude-/, "")
    .replace(/-(20\d{6})$/, "")
    .replace(/-(latest|preview)$/, "");
}

function thinkingLabel(level: string): string {
  switch (level) {
    case "minimal": return "min";
    case "medium": return "med";
    case "high": return "hi";
    case "xhigh": return "xhi";
    default: return level;
  }
}

function contextColor(percent: number | null | undefined): "dim" | "warning" | "error" {
  if (percent !== null && percent !== undefined && percent >= 90) return "error";
  if (percent !== null && percent !== undefined && percent >= 70) return "warning";
  return "dim";
}

function cacheColor(rate: number): "dim" | "warning" | "error" {
  if (rate >= 80) return "dim";
  if (rate >= 50) return "warning";
  return "error";
}

function renderMainLine(
  width: number,
  ctx: ExtensionContext,
  theme: ExtensionContext["ui"]["theme"],
  turnCount: number,
): string {
  const usage = summarizeUsage(ctx.sessionManager.getEntries());
  const context = ctx.getContextUsage();
  const percent = context?.percent;
  const percentText = percent === null || percent === undefined ? "?" : String(Math.round(percent));
  const model = shortenModel(ctx.model?.id ?? "no-model");
  const thinking = thinkingLabel(ctx.thinkingLevel);

  const left: Segment[] = [
    { name: "model", text: model, styled: theme.fg("accent", model) },
  ];
  if (thinking !== "off") {
    left.push({ name: "thinking", text: thinking, styled: theme.fg("dim", thinking) });
  }

  const contextText = `ctx:${percentText}%`;
  left.push({
    name: "context",
    text: contextText,
    styled: theme.fg(contextColor(percent), contextText),
  });

  if (usage.latestCacheHitRate !== undefined) {
    const rounded = Math.round(usage.latestCacheHitRate);
    const cacheText = `CH${rounded}%`;
    left.push({
      name: "cache",
      text: cacheText,
      styled: theme.fg(cacheColor(rounded), cacheText),
    });
  }

  const turnText = `#${turnCount}`;
  left.push({ name: "turn", text: turnText, styled: theme.fg("dim", turnText) });

  const costText = `$${usage.cost.toFixed(usage.cost >= 1 ? 2 : 3)}`;
  const cost: Segment = { name: "cost", text: costText, styled: theme.fg("dim", costText) };

  const keptLeft = [...left];
  let showCost = true;
  const totalWidth = () => {
    const leftWidth = visibleWidth(keptLeft.map((segment) => segment.text).join("  "));
    return leftWidth + (showCost && keptLeft.length > 0 ? 2 : 0) + (showCost ? visibleWidth(cost.text) : 0);
  };
  for (const name of DROP_ORDER) {
    if (totalWidth() <= width) break;
    if (name === "cost") {
      showCost = false;
      continue;
    }
    const index = keptLeft.findIndex((segment) => segment.name === name);
    if (index !== -1) keptLeft.splice(index, 1);
  }

  const renderedLeft = keptLeft.map((segment) => segment.styled).join("  ");
  const leftWidth = visibleWidth(keptLeft.map((segment) => segment.text).join("  "));
  if (!showCost) return truncateToWidth(renderedLeft, width, "");
  if (keptLeft.length === 0) {
    return truncateToWidth(`${" ".repeat(Math.max(0, width - visibleWidth(cost.text)))}${cost.styled}`, width, "");
  }

  const gap = " ".repeat(Math.max(2, width - leftWidth - visibleWidth(cost.text)));
  return truncateToWidth(`${renderedLeft}${gap}${cost.styled}`, width, "");
}

function renderStatuses(
  width: number,
  statuses: ReadonlyMap<string, string>,
  theme: ExtensionContext["ui"]["theme"],
): string | undefined {
  const visible = [...statuses.entries()]
    .filter(([key]) => !HIDDEN_STATUS_KEYS.has(key))
    .map(([, value]) => value.replace(/[\r\n\t]+/g, " ").trim())
    .filter(Boolean);
  if (visible.length === 0) return undefined;
  return truncateToWidth(theme.fg("dim", visible.join("  ")), width, theme.fg("dim", "…"));
}

export default function claudeFooter(pi: ExtensionAPI) {
  let activeSession: ExtensionContext["sessionManager"] | undefined;
  let requestRender: (() => void) | undefined;
  let turnCount = 0;

  const refresh = () => requestRender?.();

  const install = (ctx: ExtensionContext) => {
    activeSession = ctx.sessionManager;
    ctx.ui.setFooter((tui, theme, footerData) => {
      requestRender = () => tui.requestRender();
      const unsubscribe = footerData.onBranchChange(refresh);
      return {
        dispose() {
          unsubscribe();
          requestRender = undefined;
        },
        invalidate() {},
        render(width: number): string[] {
          const lines = [renderMainLine(width, ctx, theme, turnCount)];
          const statuses = renderStatuses(width, footerData.getExtensionStatuses(), theme);
          if (statuses) lines.push(statuses);
          return lines;
        },
      };
    });
  };

  pi.on("session_start", (_event, ctx) => {
    turnCount = 0;
    install(ctx);
  });
  pi.on("session_tree", (_event, ctx) => install(ctx));
  pi.on("session_shutdown", (_event, ctx) => {
    if (ctx.sessionManager !== activeSession) return;
    activeSession = undefined;
    requestRender = undefined;
    ctx.ui.setFooter(undefined);
  });
  pi.on("turn_start", (_event, ctx) => {
    if (ctx.sessionManager !== activeSession) return;
    turnCount += 1;
    refresh();
  });
  pi.on("turn_end", refresh);
  pi.on("message_end", refresh);
  pi.on("model_select", refresh);
  pi.on("thinking_level_select", refresh);
}

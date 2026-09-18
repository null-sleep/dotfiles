import * as host from "@oh-my-pi/pi-coding-agent";
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";

const STATUS_KEY = "openrouter-session-cost";
const CUSTOM_TYPE = "openrouter-session-cost/v1";
const MAX_CONCURRENCY = 4;
const REQUEST_TIMEOUT_MS = 5_000;
const RETRY_DELAYS_MS = [0, 250, 500, 1_000, 1_500, 2_000, 3_000] as const;
const ORIGINAL_SEGMENT = Symbol.for("dotfiles.openrouter-session-cost.original");

type CostRecord = {
  responseId: string;
  isByok: boolean;
  totalCost: number | null;
  upstreamInferenceCost: number | null;
  effectiveCost: number;
  fetchedAt: number;
};

type RenderedSegment = { content: string; visible: boolean };
type SegmentContextLike = {
  focusedAgentId?: string;
  session?: { state?: { model?: { provider?: string } } };
};
type SegmentLike = {
  id: string;
  render(ctx: unknown): RenderedSegment;
  [ORIGINAL_SEGMENT]?: SegmentLike;
};

type SessionState = {
  readonly manager: ExtensionContext["sessionManager"];
  readonly sessionId: string;
  ctx: ExtensionContext;
  readonly abort: AbortController;
  readonly records: Map<string, Readonly<CostRecord>>;
  readonly persisted: Set<string>;
  readonly pending: Set<string>;
  readonly failed: Set<string>;
  readonly warned: Set<string>;
  readonly queue: string[];
  total: number;
  activeRequests: number;
  responding: boolean;
  apiKeyPromise?: Promise<string | undefined>;
};

type LookupResult =
  | { kind: "resolved"; record: Readonly<CostRecord> }
  | { kind: "failed"; reason: string }
  | { kind: "cancelled" };

const recordCache = new Map<string, Readonly<CostRecord>>();
function effectiveCost(
  isByok: boolean,
  totalCost: number | null,
  upstreamInferenceCost: number | null,
): number | undefined {
  return (isByok ? upstreamInferenceCost : totalCost) ?? undefined;
}

function openRouterResponseId(entry: unknown): string | undefined {
  if (
    entry === null ||
    typeof entry !== "object" ||
    Array.isArray(entry) ||
    !("type" in entry) ||
    entry.type !== "message" ||
    !("message" in entry)
  ) {
    return undefined;
  }
  const message = entry.message;
  if (
    message === null ||
    typeof message !== "object" ||
    Array.isArray(message) ||
    !("role" in message) ||
    message.role !== "assistant" ||
    !("provider" in message) ||
    message.provider !== "openrouter" ||
    !("responseId" in message)
  ) {
    return undefined;
  }
  const { responseId } = message;
  return typeof responseId === "string" && responseId.length > 0 ? responseId : undefined;
}

function storeRecord(state: SessionState, record: Readonly<CostRecord>): void {
  const previous = state.records.get(record.responseId);
  state.records.set(record.responseId, record);
  state.total += record.effectiveCost - (previous?.effectiveCost ?? 0);
}

function displayText(state: SessionState): string {
  const base = `$${state.total.toFixed(2)}`;
  if (state.responding || state.pending.size > 0) return `${base} + …`;
  if (state.failed.size > 0) return `${base} + ?`;
  return base;
}

export default function openRouterSessionCost(pi: ExtensionAPI) {
  let activeState: SessionState | undefined;

  const finiteCostSchema = pi.zod
    .number()
    .nonnegative()
    .refine(Number.isFinite, "cost must be finite");
  const storedRecordSchema = pi.zod.object({
    responseId: pi.zod.string().min(1),
    isByok: pi.zod.boolean(),
    totalCost: finiteCostSchema.nullable(),
    upstreamInferenceCost: finiteCostSchema.nullable(),
    effectiveCost: finiteCostSchema,
    fetchedAt: finiteCostSchema,
  });
  const generationSchema = pi.zod
    .object({
      data: pi.zod
        .object({
          is_byok: pi.zod.boolean().optional(),
          total_cost: finiteCostSchema.nullable().optional(),
          upstream_inference_cost: finiteCostSchema.nullable().optional(),
        })
        .passthrough(),
    })
    .passthrough();

  const parseStoredRecord = (value: unknown): Readonly<CostRecord> | undefined => {
    const parsed = storedRecordSchema.safeParse(value);
    if (!parsed.success) return undefined;
    const candidate = parsed.data;
    const computed = effectiveCost(
      candidate.isByok,
      candidate.totalCost,
      candidate.upstreamInferenceCost,
    );
    if (computed === undefined || candidate.effectiveCost !== computed) return undefined;
    return Object.freeze({ ...candidate });
  };

  const parseGeneration = (
    responseId: string,
    payload: unknown,
  ): Readonly<CostRecord> | undefined => {
    const parsed = generationSchema.safeParse(payload);
    if (!parsed.success) return undefined;
    const generation = parsed.data.data;
    const isByok = generation.is_byok === true;
    const totalCost = generation.total_cost ?? null;
    const upstreamInferenceCost = generation.upstream_inference_cost ?? null;
    const computed = effectiveCost(isByok, totalCost, upstreamInferenceCost);
    if (computed === undefined) return undefined;
    return Object.freeze({
      responseId,
      isByok,
      totalCost,
      upstreamInferenceCost,
      effectiveCost: computed,
      fetchedAt: Date.now(),
    });
  };

  // Keep the dynamic wrapper marker out of OMP's closed StatusLineSegment type;
  // runtime lookup still uses this live mutable record.
  const runtimeExports = host as typeof host & {
    theme?: { fg(color: string, text: string): string };
    SEGMENTS?: unknown;
  };
  const segmentRegistry: unknown = runtimeExports.SEGMENTS;
  const registry = segmentRegistry as Record<string, SegmentLike> | undefined;
  const registered = registry?.cost;
  const original = registered?.[ORIGINAL_SEGMENT] ?? registered;
  let inline = false;

  const renderOriginal = (ctx: unknown): RenderedSegment => {
    try {
      return original?.render(ctx) ?? { content: "", visible: false };
    } catch {
      return { content: "", visible: false };
    }
  };

  if (registry && original) {
    try {
      const wrapped: SegmentLike = {
        id: "cost",
        [ORIGINAL_SEGMENT]: original,
        render: (ctx) => {
          try {
            const segmentCtx = ctx as SegmentContextLike;
            if (
              segmentCtx.focusedAgentId ||
              segmentCtx.session?.state?.model?.provider !== "openrouter" ||
              !activeState
            ) {
              return renderOriginal(ctx);
            }
            const text = displayText(activeState);
            return {
              content: runtimeExports.theme?.fg("statusLineCost", text) ?? text,
              visible: true,
            };
          } catch {
            return renderOriginal(ctx);
          }
        },
      };
      registry.cost = wrapped;
      inline = registry.cost === wrapped;
    } catch {
      // A frozen or removed registry falls back to the hook-status row.
    }
  }

  const repaint = (state: SessionState) => {
    if (activeState !== state || !state.ctx.hasUI) return;
    if (inline) {
      // A clear for an absent key does not invalidate OMP's segment cache.
      // Toggle an empty (non-rendering) hook status so async fetch completion
      // repaints the wrapped cost segment after the agent becomes idle.
      state.ctx.ui.setStatus(STATUS_KEY, "");
      state.ctx.ui.setStatus(STATUS_KEY, undefined);
      return;
    }
    if (state.ctx.model?.provider !== "openrouter") {
      state.ctx.ui.setStatus(STATUS_KEY, undefined);
      return;
    }
    const text = displayText(state);
    state.ctx.ui.setStatus(STATUS_KEY, state.ctx.ui.theme.fg("statusLineCost", text));
  };

  const warnOnce = (state: SessionState, reason: string, responseId?: string) => {
    if (state.warned.has(reason)) return;
    state.warned.add(reason);
    pi.logger.warn("OpenRouter session cost lookup failed", { reason, responseId });
  };

  const persist = (state: SessionState, record: Readonly<CostRecord>) => {
    if (state.persisted.has(record.responseId)) return;
    const responseStillExists = state.manager
      .getEntries()
      .some((entry) => openRouterResponseId(entry) === record.responseId);
    if (activeState !== state || !responseStillExists) return;
    try {
      pi.appendEntry(CUSTOM_TYPE, record);
      state.persisted.add(record.responseId);
    } catch (error) {
      warnOnce(state, "failed to persist generation cost", record.responseId);
      pi.logger.debug("OpenRouter session cost persistence error", {
        error: error instanceof Error ? error.message : String(error),
      });
    }
  };

  const lookup = async (state: SessionState, responseId: string): Promise<LookupResult> => {
    let key: string | undefined;
    try {
      state.apiKeyPromise ??= state.ctx.modelRegistry.getApiKeyForProvider(
        "openrouter",
        state.sessionId,
        { signal: state.abort.signal },
      );
      key = await state.apiKeyPromise;
    } catch (error) {
      if (state.abort.signal.aborted) return { kind: "cancelled" };
      return {
        kind: "failed",
        reason: `credential lookup failed: ${error instanceof Error ? error.message : String(error)}`,
      };
    }
    if (state.abort.signal.aborted) return { kind: "cancelled" };
    if (!key) return { kind: "failed", reason: "OpenRouter API key unavailable" };

    let lastFailure = "generation metadata unavailable";
    for (const delayMs of RETRY_DELAYS_MS) {
      if (delayMs > 0) await Bun.sleep(delayMs);
      if (state.abort.signal.aborted) return { kind: "cancelled" };
      try {
        const signal = AbortSignal.any([
          state.abort.signal,
          AbortSignal.timeout(REQUEST_TIMEOUT_MS),
        ]);
        const response = await fetch(
          `https://openrouter.ai/api/v1/generation?id=${encodeURIComponent(responseId)}`,
          { headers: { Authorization: `Bearer ${key}` }, signal },
        );
        if (response.ok) {
          const record = parseGeneration(responseId, await response.json());
          return record
            ? { kind: "resolved", record }
            : { kind: "failed", reason: "invalid generation metadata" };
        }
        lastFailure = `HTTP ${response.status}`;
        if (response.status !== 404 && response.status !== 429 && response.status < 500) {
          return { kind: "failed", reason: lastFailure };
        }
      } catch (error) {
        if (state.abort.signal.aborted) return { kind: "cancelled" };
        lastFailure = error instanceof Error ? error.message : String(error);
      }
    }
    return { kind: "failed", reason: lastFailure };
  };

  const pump = (state: SessionState) => {
    while (
      activeState === state &&
      state.activeRequests < MAX_CONCURRENCY &&
      state.queue.length > 0
    ) {
      const responseId = state.queue.shift();
      if (!responseId) continue;
      state.activeRequests++;
      void lookup(state, responseId)
        .then((result) => {
          if (activeState !== state || result.kind === "cancelled") return;
          if (result.kind === "resolved") {
            recordCache.set(responseId, result.record);
            storeRecord(state, result.record);
            state.failed.delete(responseId);
            persist(state, result.record);
          } else {
            state.failed.add(responseId);
            warnOnce(state, result.reason, responseId);
          }
        })
        .catch((error) => {
          if (activeState !== state || state.abort.signal.aborted) return;
          state.failed.add(responseId);
          warnOnce(state, error instanceof Error ? error.message : String(error), responseId);
        })
        .finally(() => {
          state.activeRequests--;
          state.pending.delete(responseId);
          if (activeState !== state) return;
          repaint(state);
          pump(state);
        });
    }
  };

  const enqueue = (state: SessionState, responseId: string) => {
    const cached = recordCache.get(responseId);
    if (cached) {
      storeRecord(state, cached);
      persist(state, cached);
      return;
    }
    if (
      state.records.has(responseId) ||
      state.pending.has(responseId) ||
      state.failed.has(responseId)
    ) {
      return;
    }
    state.pending.add(responseId);
    state.queue.push(responseId);
    pump(state);
  };

  const reconcile = (state: SessionState, retryFailures: boolean) => {
    const entries = state.manager.getEntries();
    const responseIds = new Set<string>();
    for (const entry of entries) {
      const responseId = openRouterResponseId(entry);
      if (responseId) responseIds.add(responseId);
    }

    // Session cost is intentionally session-wide, including abandoned branches.
    state.persisted.clear();
    state.records.clear();
    state.total = 0;
    if (retryFailures) {
      state.failed.clear();
      state.warned.clear();
      state.apiKeyPromise = undefined;
    }

    for (const entry of entries) {
      if (entry.type !== "custom" || entry.customType !== CUSTOM_TYPE) continue;
      const record = parseStoredRecord(entry.data);
      if (
        !record ||
        !responseIds.has(record.responseId) ||
        state.persisted.has(record.responseId)
      ) {
        continue;
      }
      state.persisted.add(record.responseId);
      storeRecord(state, record);
      recordCache.set(record.responseId, record);
    }

    for (const responseId of responseIds) enqueue(state, responseId);
    repaint(state);
  };

  const activate = (ctx: ExtensionContext) => {
    if (!ctx.hasUI) return;
    activeState?.abort.abort();
    const state: SessionState = {
      manager: ctx.sessionManager,
      sessionId: ctx.sessionManager.getSessionId(),
      ctx,
      abort: new AbortController(),
      records: new Map(),
      persisted: new Set(),
      pending: new Set(),
      failed: new Set(),
      warned: new Set(),
      queue: [],
      total: 0,
      activeRequests: 0,
      responding: false,
    };
    activeState = state;
    reconcile(state, true);
  };

  const reconcileActive = (ctx: ExtensionContext) => {
    if (!ctx.hasUI) return;
    if (!activeState || activeState.manager !== ctx.sessionManager) {
      activate(ctx);
      return;
    }
    activeState.ctx = ctx;
    reconcile(activeState, true);
  };

  pi.on("session_start", (_event, ctx) => activate(ctx));
  pi.on("session_switch", (_event, ctx) => activate(ctx));
  pi.on("session_branch", (_event, ctx) => activate(ctx));
  pi.on("session_tree", (_event, ctx) => reconcileActive(ctx));

  pi.on("agent_start", (_event, ctx) => {
    const state = activeState;
    if (!state || state.manager !== ctx.sessionManager) return;
    state.ctx = ctx;
    state.responding = true;
    repaint(state);
  });

  pi.on("message_end", (event, ctx) => {
    const state = activeState;
    if (!state || state.manager !== ctx.sessionManager) return;
    state.ctx = ctx;
    const responseId = openRouterResponseId({ type: "message", message: event.message });
    if (!responseId) return;
    enqueue(state, responseId);
    repaint(state);
  });

  pi.on("agent_end", (event, ctx) => {
    const state = activeState;
    if (!state || state.manager !== ctx.sessionManager) return;
    state.ctx = ctx;
    state.responding = event.willContinue === true;
    repaint(state);
  });

  pi.on("session_shutdown", (_event, ctx) => {
    const state = activeState;
    if (!state || state.manager !== ctx.sessionManager) return;
    state.abort.abort();
    activeState = undefined;
    if (ctx.hasUI) ctx.ui.setStatus(STATUS_KEY, undefined);
  });
}

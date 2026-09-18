import { constants as fsConstants } from "node:fs";
import type { Dirent, Stats } from "node:fs";
import { lstat, open, readdir, realpath } from "node:fs/promises";
import type { FileHandle } from "node:fs/promises";
import { basename, isAbsolute, join, relative, resolve, sep } from "node:path";
import * as host from "@oh-my-pi/pi-coding-agent";
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";

const STATUS_KEY = "openrouter-session-cost";
const CUSTOM_TYPE_V1 = "openrouter-session-cost/v1";
const CUSTOM_TYPE_V2 = "openrouter-session-cost/v2";
const JSONL_SUFFIX = ".jsonl";
const ADVISOR_TRANSCRIPT = "__advisor.jsonl";
const ADVISOR_PREFIX = "__advisor.";
const MAX_CONCURRENCY = 4;
const REQUEST_TIMEOUT_MS = 5_000;
const RETRY_DELAYS_MS = [0, 250, 500, 1_000, 1_500, 2_000, 3_000] as const;
const ACTIVE_SCAN_INTERVAL_MS = 1_000;
const QUIET_SCAN_INTERVAL_MS = 5_000;
const RECENT_ACTIVITY_MS = 5_000;
const READ_BUFFER_BYTES = 64 * 1024;
const HEADER_READ_BYTES = 64 * 1024;
const OPEN_READ_FLAGS = fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0);
const ORIGINAL_SEGMENT = Symbol.for("dotfiles.openrouter-session-cost.original");

type CostRecord = {
  responseId: string;
  isByok: boolean;
  totalCost: number | null;
  upstreamInferenceCost: number | null;
  effectiveCost: number;
  fetchedAt: number;
};

type CostAttribution = {
  ownerSessionId: string;
  source: "primary" | "advisor" | "subagent";
  agentId: string | null;
  advisorSlug: string | null;
};

type StoredCostRecordV2 = CostRecord & CostAttribution;

type Observation = {
  attribution: Readonly<CostAttribution>;
  credentialSessionId: string;
  kind: "persisted" | "primary" | "auxiliary";
  orderKey: string;
};

type QueueItem = {
  responseId: string;
  observation: Readonly<Observation>;
};

type TranscriptCursor = {
  dev: number;
  ino: number;
  offset: number;
  descriptorKey: string;
  tainted: boolean;
};

type TranscriptHeader = {
  dev: number;
  ino: number;
  sessionId: string;
  parentSession?: string;
};

type TranscriptOwner = {
  agentId: string | null;
  credentialSessionId: string;
  sessionFile: string;
};

type TranscriptCandidate = {
  file: string;
  stats: Stats;
  attribution: Readonly<CostAttribution>;
  credentialSessionId: string;
  orderKey: string;
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
  sessionFile?: string;
  artifactsDir: string | null;
  ctx: ExtensionContext;
  readonly abort: AbortController;
  readonly records: Map<string, Readonly<CostRecord>>;
  readonly observations: Map<string, Readonly<Observation>>;
  readonly persisted: Set<string>;
  readonly pending: Set<string>;
  readonly failed: Set<string>;
  readonly scanFailures: Map<string, string>;
  readonly warned: Set<string>;
  readonly queue: QueueItem[];
  readonly apiKeyPromises: Map<string, Promise<string | undefined>>;
  readonly cursors: Map<string, TranscriptCursor>;
  readonly transcriptHeaders: Map<string, TranscriptHeader>;
  total: number;
  activeRequests: number;
  responding: boolean;
  initialScanPending: boolean;
  scanRunning: boolean;
  scanRequested: boolean;
  scanTimer?: Timer;
  recentActivityUntil: number;
};

type LookupResult =
  | { kind: "resolved"; record: Readonly<CostRecord> }
  | { kind: "failed"; reason: string }
  | { kind: "cancelled" };

type HeaderResult =
  | { kind: "valid"; header: TranscriptHeader }
  | { kind: "pending" }
  | { kind: "unrelated" }
  | { kind: "malformed" };

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

function isValidAttribution(attribution: Readonly<CostAttribution>): boolean {
  if (attribution.ownerSessionId.length === 0) return false;
  if (attribution.source === "primary") {
    return attribution.agentId === null && attribution.advisorSlug === null;
  }
  if (attribution.source === "subagent") {
    return (
      typeof attribution.agentId === "string" &&
      attribution.agentId.length > 0 &&
      attribution.advisorSlug === null
    );
  }
  return (
    (attribution.agentId === null || attribution.agentId.length > 0) &&
    typeof attribution.advisorSlug === "string"
  );
}

function sameAttribution(
  left: Readonly<CostAttribution>,
  right: Readonly<CostAttribution>,
): boolean {
  return (
    left.ownerSessionId === right.ownerSessionId &&
    left.source === right.source &&
    left.agentId === right.agentId &&
    left.advisorSlug === right.advisorSlug
  );
}

function sameObservation(left: Readonly<Observation>, right: Readonly<Observation>): boolean {
  return (
    sameAttribution(left.attribution, right.attribution) &&
    left.credentialSessionId === right.credentialSessionId &&
    left.kind === right.kind &&
    left.orderKey === right.orderKey
  );
}

function storeRecord(state: SessionState, record: Readonly<CostRecord>): void {
  const previous = state.records.get(record.responseId);
  state.records.set(record.responseId, record);
  state.total += record.effectiveCost - (previous?.effectiveCost ?? 0);
}

function displayText(state: SessionState): string {
  const base = `$${state.total.toFixed(2)}`;
  if (state.failed.size > 0 || state.scanFailures.size > 0) return `${base} + ?`;
  if (state.responding || state.initialScanPending || state.pending.size > 0) {
    return `${base} + …`;
  }
  return base;
}

function errorCode(error: unknown): string | undefined {
  if (error === null || typeof error !== "object" || !("code" in error)) return undefined;
  return typeof error.code === "string" ? error.code : undefined;
}

function isMissingPath(error: unknown): boolean {
  const code = errorCode(error);
  return code === "ENOENT" || code === "ENOTDIR";
}

function pathIsWithin(root: string, candidate: string): boolean {
  const child = relative(root, candidate);
  return (
    child === "" ||
    (child !== ".." && !child.startsWith(`..${sep}`) && !isAbsolute(child))
  );
}

function advisorSlug(name: string): string | undefined {
  if (name === ADVISOR_TRANSCRIPT) return "";
  if (name.startsWith(ADVISOR_PREFIX) && name.endsWith(JSONL_SUFFIX)) {
    return name.slice(ADVISOR_PREFIX.length, -JSONL_SUFFIX.length);
  }
  return undefined;
}

function parseJsonLine(line: Buffer): unknown {
  const body =
    line.length > 0 && line[line.length - 1] === 13
      ? line.subarray(0, line.length - 1)
      : line;
  return JSON.parse(body.toString("utf8"));
}

export default function openRouterSessionCost(pi: ExtensionAPI) {
  let activeState: SessionState | undefined;

  const finiteCostSchema = pi.zod
    .number()
    .nonnegative()
    .refine(Number.isFinite, "cost must be finite");
  const storedRecordFields = {
    responseId: pi.zod.string().min(1),
    isByok: pi.zod.boolean(),
    totalCost: finiteCostSchema.nullable(),
    upstreamInferenceCost: finiteCostSchema.nullable(),
    effectiveCost: finiteCostSchema,
    fetchedAt: finiteCostSchema,
  };
  const storedRecordSchema = pi.zod.object(storedRecordFields);
  const storedRecordV2Schema = pi.zod.object({
    ...storedRecordFields,
    ownerSessionId: pi.zod.string().min(1),
    source: pi.zod.string().min(1),
    agentId: pi.zod.string().min(1).nullable(),
    advisorSlug: pi.zod.string().nullable(),
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

  const parseStoredRecordV2 = (value: unknown): Readonly<StoredCostRecordV2> | undefined => {
    const parsed = storedRecordV2Schema.safeParse(value);
    if (!parsed.success) return undefined;
    const candidate = parsed.data;
    const computed = effectiveCost(
      candidate.isByok,
      candidate.totalCost,
      candidate.upstreamInferenceCost,
    );
    const source = candidate.source;
    if (source !== "primary" && source !== "advisor" && source !== "subagent") {
      return undefined;
    }
    const attribution: CostAttribution = {
      ownerSessionId: candidate.ownerSessionId,
      source,
      agentId: candidate.agentId,
      advisorSlug: candidate.advisorSlug,
    };
    if (
      computed === undefined ||
      candidate.effectiveCost !== computed ||
      !isValidAttribution(attribution)
    ) {
      return undefined;
    }
    return Object.freeze({ ...candidate, source });
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
  let inline = false;
  let original: SegmentLike | undefined;
  let rendererInstalled = false;

  const renderOriginal = (ctx: unknown): RenderedSegment => {
    try {
      return original?.render(ctx) ?? { content: "", visible: false };
    } catch {
      return { content: "", visible: false };
    }
  };

  const ensureRenderer = () => {
    if (rendererInstalled) return;
    rendererInstalled = true;
    const registry = runtimeExports.SEGMENTS as Record<string, SegmentLike> | undefined;
    const registered = registry?.cost;
    original = registered?.[ORIGINAL_SEGMENT] ?? registered;
    if (!registry || !original) return;
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
  };

  const repaint = (state: SessionState) => {
    if (activeState !== state || !state.ctx.hasUI) return;
    if (inline) {
      // A clear for an absent key does not invalidate OMP's segment cache.
      // Toggle an empty (non-rendering) hook status so async work repaints the
      // wrapped cost segment after the agent becomes idle.
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

  const warnOnce = (
    state: SessionState,
    key: string,
    reason: string,
    responseId?: string,
  ) => {
    if (state.warned.has(key)) return;
    state.warned.add(key);
    pi.logger.warn("OpenRouter session cost incomplete", { reason, responseId });
  };

  const setScanFailure = (state: SessionState, file: string, reason: string) => {
    state.scanFailures.set(file, reason);
    warnOnce(
      state,
      `scan:${file}:${reason}`,
      `transcript ${basename(file)}: ${reason}`,
    );
  };

  const clearScanFailure = (state: SessionState, file: string) => {
    state.scanFailures.delete(file);
  };

  const observe = (
    state: SessionState,
    responseId: string,
    candidate: Readonly<Observation>,
  ): Readonly<Observation> => {
    const current = state.observations.get(responseId);
    if (!current) {
      state.observations.set(responseId, candidate);
      return candidate;
    }
    if (sameAttribution(current.attribution, candidate.attribution)) {
      if (
        current.kind !== "persisted" &&
        (candidate.kind === "persisted" ||
          (candidate.kind === "primary" && current.kind === "auxiliary") ||
          (candidate.kind === current.kind && candidate.orderKey < current.orderKey))
      ) {
        state.observations.set(responseId, candidate);
        state.failed.delete(responseId);
        return candidate;
      }
      return current;
    }

    warnOnce(
      state,
      `attribution:${responseId}`,
      "conflicting response attribution; counting once",
      responseId,
    );
    if (current.kind === "persisted") return current;
    if (
      candidate.kind === "persisted" ||
      (candidate.kind === "primary" && current.kind === "auxiliary") ||
      (candidate.kind === current.kind && candidate.orderKey < current.orderKey)
    ) {
      state.observations.set(responseId, candidate);
      state.failed.delete(responseId);
      return candidate;
    }
    return current;
  };

  const persist = (
    state: SessionState,
    record: Readonly<CostRecord>,
    expected?: Readonly<Observation>,
  ) => {
    if (state.persisted.has(record.responseId)) return;
    const observation = state.observations.get(record.responseId);
    if (
      activeState !== state ||
      !observation ||
      (expected && !sameObservation(observation, expected)) ||
      observation.attribution.ownerSessionId !== state.sessionId ||
      !isValidAttribution(observation.attribution)
    ) {
      return;
    }
    const stored: StoredCostRecordV2 = {
      ...record,
      ...observation.attribution,
    };
    try {
      pi.appendEntry(CUSTOM_TYPE_V2, stored);
      state.persisted.add(record.responseId);
      state.observations.set(
        record.responseId,
        Object.freeze({ ...observation, kind: "persisted" }),
      );
    } catch (error) {
      warnOnce(
        state,
        `persist:${record.responseId}`,
        "failed to persist generation cost",
        record.responseId,
      );
      pi.logger.debug("OpenRouter session cost persistence error", {
        error: error instanceof Error ? error.message : String(error),
      });
    }
  };

  const lookup = async (state: SessionState, item: QueueItem): Promise<LookupResult> => {
    let key: string | undefined;
    try {
      let keyPromise = state.apiKeyPromises.get(item.observation.credentialSessionId);
      if (!keyPromise) {
        keyPromise = state.ctx.modelRegistry.getApiKeyForProvider(
          "openrouter",
          item.observation.credentialSessionId,
          { signal: state.abort.signal },
        );
        state.apiKeyPromises.set(item.observation.credentialSessionId, keyPromise);
      }
      key = await keyPromise;
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
          `https://openrouter.ai/api/v1/generation?id=${encodeURIComponent(item.responseId)}`,
          { headers: { Authorization: `Bearer ${key}` }, signal },
        );
        if (response.ok) {
          const record = parseGeneration(item.responseId, await response.json());
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
      const item = state.queue.shift();
      if (!item) continue;
      const current = state.observations.get(item.responseId);
      if (!current || !sameObservation(current, item.observation)) {
        state.pending.delete(item.responseId);
        if (current && !state.records.has(item.responseId) && !state.failed.has(item.responseId)) {
          state.pending.add(item.responseId);
          state.queue.push({ responseId: item.responseId, observation: current });
        }
        continue;
      }
      state.activeRequests++;
      void lookup(state, item)
        .then((result) => {
          if (activeState !== state || result.kind === "cancelled") return;
          const latest = state.observations.get(item.responseId);
          if (!latest || !sameObservation(latest, item.observation)) {
            if (result.kind === "resolved") recordCache.set(item.responseId, result.record);
            return;
          }
          if (result.kind === "resolved") {
            recordCache.set(item.responseId, result.record);
            storeRecord(state, result.record);
            state.failed.delete(item.responseId);
            persist(state, result.record, item.observation);
          } else {
            state.failed.add(item.responseId);
            warnOnce(
              state,
              `lookup:${item.responseId}:${result.reason}`,
              result.reason,
              item.responseId,
            );
          }
        })
        .catch((error) => {
          if (activeState !== state || state.abort.signal.aborted) return;
          const latest = state.observations.get(item.responseId);
          if (!latest || !sameObservation(latest, item.observation)) return;
          const reason = error instanceof Error ? error.message : String(error);
          state.failed.add(item.responseId);
          warnOnce(state, `lookup:${item.responseId}:${reason}`, reason, item.responseId);
        })
        .finally(() => {
          state.activeRequests--;
          state.pending.delete(item.responseId);
          if (activeState !== state) return;
          const latest = state.observations.get(item.responseId);
          if (
            latest &&
            !sameObservation(latest, item.observation) &&
            !state.records.has(item.responseId)
          ) {
            enqueue(state, item.responseId);
          }
          try {
            repaint(state);
          } finally {
            pump(state);
          }
        })
        .catch((error) => {
          try {
            pi.logger.warn("OpenRouter session cost worker failed", {
              responseId: item.responseId,
              error: error instanceof Error ? error.message : String(error),
            });
          } catch {
            // A detached worker must not leak a second failure to the process.
          }
        });
    }
  };

  const enqueue = (state: SessionState, responseId: string) => {
    const observation = state.observations.get(responseId);
    if (!observation) return;
    const existing = state.records.get(responseId);
    if (existing) {
      persist(state, existing, observation);
      return;
    }
    const cached = recordCache.get(responseId);
    if (cached) {
      storeRecord(state, cached);
      state.failed.delete(responseId);
      persist(state, cached, observation);
      return;
    }
    if (state.pending.has(responseId) || state.failed.has(responseId)) return;
    state.pending.add(responseId);
    state.queue.push({ responseId, observation });
    pump(state);
  };

  const reconcilePrimary = (state: SessionState, retryFailures: boolean) => {
    const entries = state.manager.getEntries();
    const primaryResponseIds = new Set<string>();
    for (const entry of entries) {
      const responseId = openRouterResponseId(entry);
      if (responseId) primaryResponseIds.add(responseId);
    }

    if (retryFailures) {
      state.failed.clear();
      state.apiKeyPromises.clear();
    }

    // V2 attribution is durable proof and wins over any legacy primary record.
    for (const entry of entries) {
      if (entry.type !== "custom" || entry.customType !== CUSTOM_TYPE_V2) continue;
      const stored = parseStoredRecordV2(entry.data);
      if (
        !stored ||
        stored.ownerSessionId !== state.sessionId ||
        state.persisted.has(stored.responseId)
      ) {
        continue;
      }
      const attribution: Readonly<CostAttribution> = Object.freeze({
        ownerSessionId: stored.ownerSessionId,
        source: stored.source,
        agentId: stored.agentId,
        advisorSlug: stored.advisorSlug,
      });
      const observation: Readonly<Observation> = Object.freeze({
        attribution,
        credentialSessionId: state.sessionId,
        kind: "persisted",
        orderKey: `0:persisted:${stored.responseId}`,
      });
      const record: Readonly<CostRecord> = Object.freeze({
        responseId: stored.responseId,
        isByok: stored.isByok,
        totalCost: stored.totalCost,
        upstreamInferenceCost: stored.upstreamInferenceCost,
        effectiveCost: stored.effectiveCost,
        fetchedAt: stored.fetchedAt,
      });
      observe(state, stored.responseId, observation);
      state.persisted.add(stored.responseId);
      storeRecord(state, record);
      recordCache.set(stored.responseId, record);
    }

    // V1 records are accepted only for response ids still present in primary entries.
    for (const entry of entries) {
      if (entry.type !== "custom" || entry.customType !== CUSTOM_TYPE_V1) continue;
      const stored = parseStoredRecord(entry.data);
      if (
        !stored ||
        !primaryResponseIds.has(stored.responseId) ||
        state.persisted.has(stored.responseId)
      ) {
        continue;
      }
      const observation: Readonly<Observation> = Object.freeze({
        attribution: Object.freeze({
          ownerSessionId: state.sessionId,
          source: "primary",
          agentId: null,
          advisorSlug: null,
        }),
        credentialSessionId: state.sessionId,
        kind: "persisted",
        orderKey: `0:legacy:${stored.responseId}`,
      });
      observe(state, stored.responseId, observation);
      state.persisted.add(stored.responseId);
      storeRecord(state, stored);
      recordCache.set(stored.responseId, stored);
    }

    for (const responseId of primaryResponseIds) {
      const observation: Readonly<Observation> = Object.freeze({
        attribution: Object.freeze({
          ownerSessionId: state.sessionId,
          source: "primary",
          agentId: null,
          advisorSlug: null,
        }),
        credentialSessionId: state.sessionId,
        kind: "primary",
        orderKey: "1:primary",
      });
      observe(state, responseId, observation);
    }
    for (const responseId of state.observations.keys()) enqueue(state, responseId);
    repaint(state);
  };

  const safeFileStats = async (
    state: SessionState,
    rootRealPath: string,
    file: string,
    reportFailure: boolean,
  ): Promise<Stats | undefined> => {
    try {
      const stats = await lstat(file);
      if (stats.isSymbolicLink() || !stats.isFile()) return undefined;
      const resolved = await realpath(file);
      if (!pathIsWithin(rootRealPath, resolved)) return undefined;
      return stats;
    } catch (error) {
      if (!isMissingPath(error) && reportFailure) {
        setScanFailure(state, file, errorCode(error) ?? "stat failed");
      }
      return undefined;
    }
  };

  const safeDirectory = async (
    state: SessionState,
    rootRealPath: string,
    directory: string,
  ): Promise<string | undefined> => {
    try {
      const stats = await lstat(directory);
      if (stats.isSymbolicLink() || !stats.isDirectory()) return undefined;
      const resolved = await realpath(directory);
      if (!pathIsWithin(rootRealPath, resolved)) return undefined;
      return resolved;
    } catch (error) {
      if (!isMissingPath(error)) {
        setScanFailure(state, directory, errorCode(error) ?? "directory stat failed");
      }
      return undefined;
    }
  };

  const inspectTranscriptHeader = async (
    state: SessionState,
    file: string,
    stats: Stats,
  ): Promise<HeaderResult> => {
    const cursor = state.cursors.get(file);
    if (cursor && stats.size < cursor.offset) {
      state.cursors.delete(file);
      state.transcriptHeaders.delete(file);
    }
    const cached = state.transcriptHeaders.get(file);
    if (cached && cached.dev === stats.dev && cached.ino === stats.ino) {
      return { kind: "valid", header: cached };
    }

    let handle: FileHandle | undefined;
    try {
      handle = await open(file, OPEN_READ_FLAGS);
      const openedStats = await handle.stat();
      if (
        !openedStats.isFile() ||
        openedStats.dev !== stats.dev ||
        openedStats.ino !== stats.ino
      ) {
        return { kind: "pending" };
      }
      const maxBytes = Math.min(openedStats.size, HEADER_READ_BYTES);
      if (maxBytes === 0) return { kind: "pending" };
      const buffer = Buffer.allocUnsafe(maxBytes);
      const { bytesRead } = await handle.read(buffer, 0, maxBytes, 0);
      const prefix = buffer.subarray(0, bytesRead);
      const firstEnd = prefix.indexOf(10);
      if (firstEnd < 0) {
        return openedStats.size >= HEADER_READ_BYTES
          ? { kind: "malformed" }
          : { kind: "pending" };
      }

      let header: unknown;
      let titlePrefixed = false;
      try {
        const first = parseJsonLine(prefix.subarray(0, firstEnd));
        if (
          first !== null &&
          typeof first === "object" &&
          !Array.isArray(first) &&
          "type" in first &&
          first.type === "title"
        ) {
          titlePrefixed = true;
          const secondEnd = prefix.indexOf(10, firstEnd + 1);
          if (secondEnd < 0) {
            return openedStats.size >= HEADER_READ_BYTES
              ? { kind: "malformed" }
              : { kind: "pending" };
          }
          header = parseJsonLine(prefix.subarray(firstEnd + 1, secondEnd));
        } else {
          header = first;
        }
      } catch {
        return { kind: "malformed" };
      }

      if (
        header === null ||
        typeof header !== "object" ||
        Array.isArray(header) ||
        !("type" in header) ||
        header.type !== "session"
      ) {
        return { kind: titlePrefixed ? "malformed" : "unrelated" };
      }
      if (
        !("id" in header) ||
        typeof header.id !== "string" ||
        header.id.length === 0
      ) {
        return { kind: "malformed" };
      }
      const parsed: TranscriptHeader = {
        dev: openedStats.dev,
        ino: openedStats.ino,
        sessionId: header.id,
      };
      if (
        "parentSession" in header &&
        typeof header.parentSession === "string" &&
        header.parentSession.length > 0
      ) {
        parsed.parentSession = header.parentSession;
      }
      state.transcriptHeaders.set(file, parsed);
      return { kind: "valid", header: parsed };
    } catch (error) {
      if (isMissingPath(error) || errorCode(error) === "ELOOP") return { kind: "pending" };
      setScanFailure(state, file, errorCode(error) ?? "header read failed");
      return { kind: "pending" };
    } finally {
      await handle?.close().catch(() => {});
    }
  };

  const collectTranscripts = async (
    state: SessionState,
    rootRealPath: string,
    directory: string,
    owner: TranscriptOwner,
    candidates: TranscriptCandidate[],
    seen: Set<string>,
  ): Promise<void> => {
    if (activeState !== state || state.abort.signal.aborted) return;
    seen.add(directory);
    let entries: Dirent[];
    try {
      entries = await readdir(directory, { withFileTypes: true });
      clearScanFailure(state, directory);
    } catch (error) {
      if (!isMissingPath(error)) {
        setScanFailure(state, directory, errorCode(error) ?? "directory read failed");
      }
      return;
    }

    entries.sort((left, right) => left.name.localeCompare(right.name));
    let entriesSinceYield = 0;
    for (const entry of entries) {
      if (activeState !== state || state.abort.signal.aborted) return;
      if (++entriesSinceYield >= 16) {
        entriesSinceYield = 0;
        await Bun.sleep(0);
      }
      if (!entry.isFile() || !entry.name.endsWith(JSONL_SUFFIX)) continue;
      const file = join(directory, entry.name);
      const slug = advisorSlug(entry.name);
      const reservedAdvisor =
        entry.name === ADVISOR_TRANSCRIPT ||
        (entry.name.startsWith(ADVISOR_PREFIX) && entry.name.endsWith(JSONL_SUFFIX));
      const known = reservedAdvisor || state.transcriptHeaders.has(file);
      seen.add(file);
      const stats = await safeFileStats(state, rootRealPath, file, known);
      if (!stats) continue;
      const headerResult = await inspectTranscriptHeader(state, file, stats);
      if (headerResult.kind === "pending") continue;
      if (headerResult.kind === "malformed") {
        setScanFailure(state, file, "malformed transcript header");
        continue;
      }
      if (headerResult.kind === "unrelated") {
        if (reservedAdvisor || known) {
          setScanFailure(state, file, "invalid transcript header");
        } else {
          clearScanFailure(state, file);
        }
        continue;
      }

      const orderKey = relative(state.artifactsDir ?? rootRealPath, resolve(file));
      if (reservedAdvisor && slug !== undefined) {
        candidates.push({
          file,
          stats,
          attribution: Object.freeze({
            ownerSessionId: state.sessionId,
            source: "advisor",
            agentId: owner.agentId,
            advisorSlug: slug,
          }),
          credentialSessionId: owner.credentialSessionId,
          orderKey,
        });
        continue;
      }

      const agentId = entry.name.slice(0, -JSONL_SUFFIX.length);
      if (agentId.length === 0) continue;
      if (
        headerResult.header.parentSession &&
        resolve(headerResult.header.parentSession) !== resolve(owner.sessionFile)
      ) {
        warnOnce(
          state,
          `parent:${file}`,
          `transcript ${basename(file)}: parent session mismatch`,
        );
      }
      candidates.push({
        file,
        stats,
        attribution: Object.freeze({
          ownerSessionId: state.sessionId,
          source: "subagent",
          agentId,
          advisorSlug: null,
        }),
        credentialSessionId: headerResult.header.sessionId,
        orderKey,
      });

      const companion = file.slice(0, -JSONL_SUFFIX.length);
      seen.add(companion);
      const companionRealPath = await safeDirectory(state, rootRealPath, companion);
      if (!companionRealPath) continue;
      await collectTranscripts(
        state,
        rootRealPath,
        companion,
        {
          agentId,
          credentialSessionId: headerResult.header.sessionId,
          sessionFile: file,
        },
        candidates,
        seen,
      );
    }
  };

  const scanTranscript = async (
    state: SessionState,
    candidate: TranscriptCandidate,
  ): Promise<void> => {
    const { attribution } = candidate;
    const key = [
      attribution.source,
      attribution.agentId ?? "",
      attribution.advisorSlug ?? "<none>",
      candidate.credentialSessionId,
    ].join("\0");
    let cursor = state.cursors.get(candidate.file);
    let reset =
      !cursor ||
      cursor.dev !== candidate.stats.dev ||
      cursor.ino !== candidate.stats.ino ||
      candidate.stats.size < cursor.offset ||
      cursor.descriptorKey !== key;
    if (reset) {
      cursor = {
        dev: candidate.stats.dev,
        ino: candidate.stats.ino,
        offset: 0,
        descriptorKey: key,
        tainted: false,
      };
      state.cursors.set(candidate.file, cursor);
    }

    let handle: FileHandle | undefined;
    let lastCompleteOffset = cursor.offset;
    try {
      handle = await open(candidate.file, OPEN_READ_FLAGS);
      const openedStats = await handle.stat();
      if (
        !openedStats.isFile() ||
        openedStats.dev !== candidate.stats.dev ||
        openedStats.ino !== candidate.stats.ino
      ) {
        return;
      }
      if (openedStats.size < cursor.offset) {
        reset = true;
        cursor.offset = 0;
        cursor.tainted = false;
        lastCompleteOffset = 0;
      }
      const snapshotSize = openedStats.size;
      if (cursor.offset >= snapshotSize) {
        if (!cursor.tainted) clearScanFailure(state, candidate.file);
        return;
      }

      const buffer = Buffer.allocUnsafe(READ_BUFFER_BYTES);
      const lineParts: Buffer[] = [];
      let linePartsLength = 0;
      let lineStartOffset = cursor.offset;
      let position = cursor.offset;
      let malformed = false;

      while (position < snapshotSize) {
        if (activeState !== state || state.abort.signal.aborted) {
          cursor.offset = lastCompleteOffset;
          return;
        }
        const requested = Math.min(buffer.length, snapshotSize - position);
        const { bytesRead } = await handle.read(buffer, 0, requested, position);
        if (bytesRead === 0) break;
        const chunkStart = position;
        let start = 0;
        while (start < bytesRead) {
          const newline = buffer.indexOf(10, start);
          if (newline < 0 || newline >= bytesRead) {
            const remainder = buffer.subarray(start, bytesRead);
            if (remainder.length > 0) {
              const copy = Buffer.from(remainder);
              lineParts.push(copy);
              linePartsLength += copy.length;
            }
            break;
          }

          const segment = buffer.subarray(start, newline);
          let line: Buffer;
          if (lineParts.length === 0) {
            line = segment;
          } else {
            if (segment.length > 0) {
              const copy = Buffer.from(segment);
              lineParts.push(copy);
              linePartsLength += copy.length;
            }
            line = Buffer.concat(lineParts, linePartsLength);
          }
          const completeOffset = chunkStart + newline + 1;
          try {
            const entry = parseJsonLine(line);
            const responseId = openRouterResponseId(entry);
            if (responseId) {
              const observation: Readonly<Observation> = Object.freeze({
                attribution: candidate.attribution,
                credentialSessionId: candidate.credentialSessionId,
                kind: "auxiliary",
                orderKey: `${candidate.orderKey}:${lineStartOffset
                  .toString()
                  .padStart(16, "0")}`,
              });
              observe(state, responseId, observation);
              enqueue(state, responseId);
            }
          } catch {
            malformed = true;
            cursor.tainted = true;
          }
          lineParts.length = 0;
          linePartsLength = 0;
          lineStartOffset = completeOffset;
          lastCompleteOffset = completeOffset;
          start = newline + 1;
        }
        position += bytesRead;
      }

      cursor.offset = lastCompleteOffset;
      if (malformed || cursor.tainted) {
        setScanFailure(state, candidate.file, "malformed complete JSONL record");
      } else {
        clearScanFailure(state, candidate.file);
      }
      if (reset && !malformed) cursor.tainted = false;
    } catch (error) {
      cursor.offset = lastCompleteOffset;
      if (!isMissingPath(error) && errorCode(error) !== "ELOOP") {
        setScanFailure(state, candidate.file, errorCode(error) ?? "read failed");
      }
    } finally {
      await handle?.close().catch(() => {});
    }
  };

  const refreshTranscriptRoots = (state: SessionState): boolean => {
    const sessionFile = state.manager.getSessionFile() ?? undefined;
    const artifactsDir = state.manager.getArtifactsDir();
    if (state.sessionFile === sessionFile && state.artifactsDir === artifactsDir) {
      return false;
    }
    state.sessionFile = sessionFile;
    state.artifactsDir = artifactsDir;
    state.cursors.clear();
    state.transcriptHeaders.clear();
    state.scanFailures.clear();
    state.initialScanPending = Boolean(sessionFile?.endsWith(JSONL_SUFFIX) && artifactsDir);
    return true;
  };

  const scanAuxiliaryTranscripts = async (state: SessionState): Promise<void> => {
    if (refreshTranscriptRoots(state)) repaint(state);
    const root = state.artifactsDir;
    const sessionFile = state.sessionFile;
    if (!root || !sessionFile?.endsWith(JSONL_SUFFIX)) return;

    let rootRealPath: string;
    try {
      const rootStats = await lstat(root);
      if (rootStats.isSymbolicLink() || !rootStats.isDirectory()) {
        setScanFailure(state, root, "invalid transcript root");
        return;
      }
      rootRealPath = await realpath(root);
      clearScanFailure(state, root);
    } catch (error) {
      if (isMissingPath(error)) {
        if (refreshTranscriptRoots(state)) {
          state.scanRequested = true;
          repaint(state);
        } else {
          state.cursors.clear();
          state.transcriptHeaders.clear();
          state.scanFailures.clear();
        }
        return;
      }
      setScanFailure(state, root, errorCode(error) ?? "transcript root unavailable");
      return;
    }

    const candidates: TranscriptCandidate[] = [];
    const seen = new Set<string>();
    await collectTranscripts(
      state,
      rootRealPath,
      root,
      {
        agentId: null,
        credentialSessionId: state.sessionId,
        sessionFile,
      },
      candidates,
      seen,
    );
    if (activeState !== state || state.abort.signal.aborted) return;
    candidates.sort((left, right) => left.orderKey.localeCompare(right.orderKey));
    for (const candidate of candidates) {
      if (activeState !== state || state.abort.signal.aborted) return;
      await scanTranscript(state, candidate);
    }

    for (const file of state.cursors.keys()) {
      if (!seen.has(file)) state.cursors.delete(file);
    }
    for (const file of state.transcriptHeaders.keys()) {
      if (!seen.has(file)) state.transcriptHeaders.delete(file);
    }
    for (const file of state.scanFailures.keys()) {
      if (file !== root && !seen.has(file)) state.scanFailures.delete(file);
    }
    if (refreshTranscriptRoots(state)) {
      state.scanRequested = true;
      repaint(state);
    }
  };

  const hasRunningAuxiliaryJob = (state: SessionState): boolean => {
    try {
      return (
        state.ctx
          .getAsyncJobSnapshot()
          ?.running.some(
            (job) =>
              typeof job.agentId === "string" &&
              job.agentId.length > 0 &&
              (job.type === "task" || job.type === "eval"),
          ) === true
      );
    } catch {
      return false;
    }
  };

  const nextScanDelay = (state: SessionState): number => {
    const active =
      state.responding ||
      state.initialScanPending ||
      state.pending.size > 0 ||
      Date.now() < state.recentActivityUntil ||
      hasRunningAuxiliaryJob(state);
    return active ? ACTIVE_SCAN_INTERVAL_MS : QUIET_SCAN_INTERVAL_MS;
  };

  const armScan = (state: SessionState, delayMs: number) => {
    if (activeState !== state || state.abort.signal.aborted) return;
    if (state.scanTimer !== undefined) {
      state.ctx.clearTimer(state.scanTimer);
      state.scanTimer = undefined;
    }
    state.scanTimer = state.ctx.setTimeout(async () => {
      state.scanTimer = undefined;
      if (activeState !== state || state.abort.signal.aborted || state.scanRunning) return;
      state.scanRunning = true;
      state.scanRequested = false;
      try {
        await scanAuxiliaryTranscripts(state);
      } catch (error) {
        if (activeState !== state || state.abort.signal.aborted) return;
        const root = state.artifactsDir ?? state.sessionFile ?? "transcripts";
        setScanFailure(state, root, errorCode(error) ?? "reconciliation failed");
      } finally {
        if (activeState === state) {
          state.scanRunning = false;
          const rerun = state.scanRequested;
          state.scanRequested = false;
          state.initialScanPending = rerun && state.initialScanPending;
          try {
            repaint(state);
          } finally {
            armScan(state, rerun ? 0 : nextScanDelay(state));
          }
        }
      }
    }, delayMs);
  };

  const requestScan = (state: SessionState, immediate: boolean) => {
    if (activeState !== state || state.abort.signal.aborted) return;
    state.scanRequested = true;
    if (state.scanRunning) return;
    armScan(state, immediate ? 0 : nextScanDelay(state));
  };

  const markActivity = (state: SessionState) => {
    state.recentActivityUntil = Date.now() + RECENT_ACTIVITY_MS;
  };

  const stopState = (state: SessionState) => {
    if (state.scanTimer !== undefined) {
      state.ctx.clearTimer(state.scanTimer);
      state.scanTimer = undefined;
    }
    state.abort.abort();
  };

  const activate = (ctx: ExtensionContext) => {
    if (!ctx.hasUI) return;
    ensureRenderer();
    if (activeState) stopState(activeState);
    const sessionFile = ctx.sessionManager.getSessionFile() ?? undefined;
    const artifactsDir = ctx.sessionManager.getArtifactsDir();
    const state: SessionState = {
      manager: ctx.sessionManager,
      sessionId: ctx.sessionManager.getSessionId(),
      sessionFile,
      artifactsDir,
      ctx,
      abort: new AbortController(),
      records: new Map(),
      observations: new Map(),
      persisted: new Set(),
      pending: new Set(),
      failed: new Set(),
      scanFailures: new Map(),
      warned: new Set(),
      queue: [],
      apiKeyPromises: new Map(),
      cursors: new Map(),
      transcriptHeaders: new Map(),
      total: 0,
      activeRequests: 0,
      responding: false,
      initialScanPending: Boolean(sessionFile?.endsWith(JSONL_SUFFIX) && artifactsDir),
      scanRunning: false,
      scanRequested: false,
      recentActivityUntil: Date.now() + RECENT_ACTIVITY_MS,
    };
    activeState = state;
    reconcilePrimary(state, true);
    if (state.initialScanPending) requestScan(state, true);
  };

  const reconcileActive = (ctx: ExtensionContext) => {
    if (!ctx.hasUI) return;
    if (!activeState || activeState.manager !== ctx.sessionManager) {
      activate(ctx);
      return;
    }
    activeState.ctx = ctx;
    reconcilePrimary(activeState, true);
    markActivity(activeState);
    requestScan(activeState, true);
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
    markActivity(state);
    requestScan(state, false);
    repaint(state);
  });

  pi.on("message_end", (event, ctx) => {
    const state = activeState;
    if (!state || state.manager !== ctx.sessionManager) return;
    state.ctx = ctx;
    const responseId = openRouterResponseId({ type: "message", message: event.message });
    if (responseId) {
      const observation: Readonly<Observation> = Object.freeze({
        attribution: Object.freeze({
          ownerSessionId: state.sessionId,
          source: "primary",
          agentId: null,
          advisorSlug: null,
        }),
        credentialSessionId: state.sessionId,
        kind: "primary",
        orderKey: "1:primary",
      });
      observe(state, responseId, observation);
      enqueue(state, responseId);
    }
    markActivity(state);
    repaint(state);
  });

  pi.on("agent_end", (event, ctx) => {
    const state = activeState;
    if (!state || state.manager !== ctx.sessionManager) return;
    state.ctx = ctx;
    state.responding = event.willContinue === true;
    markActivity(state);
    requestScan(state, true);
    repaint(state);
  });

  pi.on("session_shutdown", (_event, ctx) => {
    const state = activeState;
    if (!state || state.manager !== ctx.sessionManager) return;
    stopState(state);
    activeState = undefined;
    if (ctx.hasUI) ctx.ui.setStatus(STATUS_KEY, undefined);
  });
}

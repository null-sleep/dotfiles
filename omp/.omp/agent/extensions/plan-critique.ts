import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";

/**
 * TUI Plan Review: add "Critique plan (subagent)" right under
 * "Approve and keep context" in "Plan mode - next step".
 *
 * Reuses the native `continue with ◂ default | sonnet | … ▸` slider directly:
 * arrowing to a role on the slider and pressing Enter on "Critique plan
 * (subagent)" spawns a read-only subagent on that exact role's model + thinking
 * level (`modelRoles[role]`) to critique the plan against the codebase, posts a
 * concise TL;DR via `out://`, updates the plan with valid findings, and
 * re-proposes via `xd://propose` so the updated Plan Review reopens.
 *
 * Choosing any Approve option continues to execute on the slider role as usual.
 *
 * Works across omp 18.18.x (string options) and 18.22+ (`{ id, label }` options)
 * by wrapping `InteractiveMode.prototype.showPlanReview` (the same live
 * host-prototype mechanism `zed-plan-in-chat.ts` and `turn-count.ts` use) and
 * pairing it with the public `plan_review_requested` / `plan_review_resolved` API.
 * Design, rejected alternatives, and upkeep: plans/omp-plan-critique.md.
 */

const PATCHED = Symbol.for("omp-plan-critique");
const PENDING_KEY = Symbol.for("omp-plan-critique.pending");
const CRITIQUE_ID = "critique";
const CRITIQUE_LABEL = "Critique plan (subagent)";
const CRITIQUE_DETAIL = "Critique on the slider model, revise, and reopen review";
const PROMPT_TITLE = "Plan mode - next step";

type SliderSegment = { label: string; detail?: string };
type SliderConfig = {
  caption?: string;
  index: number;
  segments: SliderSegment[];
  onChange?: (index: number) => void;
};
type ObjectChoice = {
  id: string;
  label: string;
  detail?: string;
  meta?: string;
  disabled?: string;
};
type ReviewOptionsArg = string[] | ObjectChoice[];
type ShowPlanReviewCallbacks = {
  disabledIndices?: number[];
  onFeedbackChange?: (feedback: string) => void;
  onClose?: (choice: string | undefined) => void;
  [key: string]: unknown;
};
type ShowPlanReviewExtra = {
  slider?: SliderConfig;
  [key: string]: unknown;
};
type ShowPlanReviewFn = (
  this: InteractiveModeLike,
  planContent: string,
  title: string,
  options: ReviewOptionsArg,
  callbacks?: ShowPlanReviewCallbacks,
  extra?: ShowPlanReviewExtra,
) => Promise<string | undefined>;

type CycleEntry = {
  role: string;
  model: {
    provider: string;
    id: string;
    name?: string;
    compat?: Record<string, unknown>;
  };
  thinkingLevel?: string;
  explicitThinkingLevel?: boolean;
};
type RoleCycle = { models: CycleEntry[]; currentIndex: number };
type SessionLike = {
  settings?: { getModelRole?: (role: string) => string | undefined };
  sessionManager?: { getSessionId?: () => string };
  getRoleModelCycle?: (order?: readonly string[]) => RoleCycle | undefined;
};
type InteractiveModeLike = {
  session?: SessionLike;
  sessionManager?: { getSessionId?: () => string };
  resolvePlanReview?: (
    reviewId: string,
    choice: string,
    input?: { feedback?: string; role?: string },
  ) => boolean;
  showPlanReview: ShowPlanReviewFn;
};

type TierInfo = {
  role: string;
  provider: string;
  model: string;
  thinkingLevel?: string;
};
type PendingReview = {
  reviewId: string;
  sessionId: string;
  title: string;
  planFilePath: string;
  tiers?: TierInfo[];
  ctx?: ExtensionContext;
};

type Host = {
  InteractiveMode: { prototype: InteractiveModeLike };
  cycleOrderLookup?: { get(scope: unknown): readonly string[] };
  formatModelWithRouting?: (model: CycleEntry["model"]) => string;
};

function hasShowPlanReview(value: unknown): value is Host["InteractiveMode"] {
  if ((typeof value !== "function" && typeof value !== "object") || value === null) return false;
  const proto: unknown = Reflect.get(value, "prototype");
  return (
    typeof proto === "object" &&
    proto !== null &&
    typeof Reflect.get(proto, "showPlanReview") === "function"
  );
}

function isCycleOrderLookup(value: unknown): value is NonNullable<Host["cycleOrderLookup"]> {
  return typeof value === "object" && value !== null && typeof Reflect.get(value, "get") === "function";
}

async function loadHost(): Promise<Host | undefined> {
  try {
    const [im, registry, resolver] = await Promise.all([
      import("@oh-my-pi/pi-coding-agent/modes/interactive-mode"),
      import("@oh-my-pi/pi-coding-agent/config/registry").catch(() => undefined),
      import("@oh-my-pi/pi-coding-agent/config/model-resolver").catch(() => undefined),
    ]);
    const InteractiveMode: unknown =
      typeof im === "object" && im !== null ? Reflect.get(im, "InteractiveMode") : undefined;
    if (!hasShowPlanReview(InteractiveMode)) {
      return undefined;
    }
    const rawLookup: unknown =
      typeof registry === "object" && registry !== null ? Reflect.get(registry, "lookup") : undefined;
    const candidateLookup: unknown =
      typeof rawLookup === "function" ? rawLookup("cycleOrder") : undefined;
    const formatModelWithRouting: unknown =
      typeof resolver === "object" && resolver !== null
        ? Reflect.get(resolver, "formatModelStringWithRouting")
        : undefined;
    return {
      InteractiveMode,
      cycleOrderLookup: isCycleOrderLookup(candidateLookup) ? candidateLookup : undefined,
      formatModelWithRouting:
        typeof formatModelWithRouting === "function"
          ? (model => {
              const formatted: unknown = formatModelWithRouting(model);
              return typeof formatted === "string"
                ? formatted
                : `${model.provider}/${model.id}${upstreamSuffix(model)}`;
            })
          : undefined,
    };
  } catch {
    return undefined;
  }
}

function upstreamSuffix(model: CycleEntry["model"]): string {
  const compat = model.compat;
  if (!compat || typeof compat !== "object") return "";
  for (const key of ["openRouterRouting", "vercelGatewayRouting"]) {
    const routing = compat[key];
    if (typeof routing !== "object" || routing === null || !("only" in routing)) continue;
    const only = routing.only;
    if (Array.isArray(only) && only.length === 1 && typeof only[0] === "string" && only[0]) {
      return `@${only[0]}`;
    }
  }
  return "";
}

/**
 * Resolve the exact `provider/model-id[@upstream][:level]` selector that `task`'s
 * `perCallModel` validator expects for a slider role.
 *
 * Preference order:
 * 1. Live `getRoleModelCycle` entry (includes upstream routing + resolved thinking).
 * 2. Configured `settings.getModelRole(role)` when it is already a direct selector
 *    (not a `@role` alias or comma fallback list).
 * 3. `plan_review_requested` event `tiers` entry.
 */
export function resolveCritiqueSelector(
  role: string | undefined,
  host: Pick<Host, "cycleOrderLookup" | "formatModelWithRouting">,
  session: SessionLike | undefined,
  tiers: readonly TierInfo[] | undefined,
): { role: string; selector?: string; displayLabel: string } {
  const effectiveRole = role || "default";

  let order: readonly string[] | undefined;
  if (session?.settings && host.cycleOrderLookup) {
    try {
      order = host.cycleOrderLookup.get(session.settings);
    } catch {
      order = undefined;
    }
  }
  let cycle: RoleCycle | undefined;
  try {
    cycle = session?.getRoleModelCycle?.(order);
  } catch {
    cycle = undefined;
  }
  const cycleEntry = cycle?.models.find(entry => entry.role === effectiveRole);
  if (cycleEntry) {
    const base = host.formatModelWithRouting
      ? host.formatModelWithRouting(cycleEntry.model)
      : `${cycleEntry.model.provider}/${cycleEntry.model.id}${upstreamSuffix(cycleEntry.model)}`;
    const level =
      cycleEntry.explicitThinkingLevel && cycleEntry.thinkingLevel
        ? `:${cycleEntry.thinkingLevel}`
        : "";
    const detail = cycleEntry.model.name || cycleEntry.model.id;
    return {
      role: effectiveRole,
      selector: `${base}${level}`,
      displayLabel: `${effectiveRole} (${detail}${level})`,
    };
  }

  const rawRole = session?.settings?.getModelRole?.(effectiveRole)?.trim();
  if (rawRole && !rawRole.startsWith("@") && !rawRole.includes(",") && rawRole.includes("/")) {
    return {
      role: effectiveRole,
      selector: rawRole,
      displayLabel: `${effectiveRole} (${rawRole})`,
    };
  }

  const tier = tiers?.find(entry => entry.role === effectiveRole);
  if (tier) {
    const level = tier.thinkingLevel ? `:${tier.thinkingLevel}` : "";
    return {
      role: effectiveRole,
      selector: `${tier.provider}/${tier.model}${level}`,
      displayLabel: `${effectiveRole} (${tier.provider}/${tier.model}${level})`,
    };
  }

  return {
    role: effectiveRole,
    selector: undefined,
    displayLabel: effectiveRole,
  };
}

function isStringOptionArray(options: ReviewOptionsArg): options is string[] {
  return options.length > 0 && typeof options[0] === "string";
}

export function injectCritiqueOption(
  options: ReviewOptionsArg,
  callbacks?: ShowPlanReviewCallbacks,
): { options: ReviewOptionsArg; callbacks?: ShowPlanReviewCallbacks } {
  if (options.length === 0) return { options, callbacks };

  if (isStringOptionArray(options)) {
    if (options.includes(CRITIQUE_LABEL)) return { options, callbacks };
    const keepIdx = options.findIndex(label => label.startsWith("Approve and keep context"));
    // No "keep" row: land before the trailing "Save and quit", not after it.
    const insertAt = keepIdx >= 0 ? keepIdx + 1 : Math.max(options.length - 1, 0);
    const nextOptions = [
      ...options.slice(0, insertAt),
      CRITIQUE_LABEL,
      ...options.slice(insertAt),
    ];
    const shiftedDisabled = callbacks?.disabledIndices?.map(idx => (idx >= insertAt ? idx + 1 : idx));
    return {
      options: nextOptions,
      callbacks: shiftedDisabled ? { ...callbacks, disabledIndices: shiftedDisabled } : callbacks,
    };
  }

  if (options.some(choice => choice.id === CRITIQUE_ID)) return { options, callbacks };
  const critiqueChoice: ObjectChoice = {
    id: CRITIQUE_ID,
    label: CRITIQUE_LABEL,
    detail: CRITIQUE_DETAIL,
  };
  const keepIdx = options.findIndex(choice => choice.id === "keep");
  const insertAt = keepIdx >= 0 ? keepIdx + 1 : options.length;
  return {
    options: [
      ...options.slice(0, insertAt),
      critiqueChoice,
      ...options.slice(insertAt),
    ],
    callbacks,
  };
}

export function buildCritiqueFeedback(params: {
  planFilePath: string;
  title: string;
  role: string;
  selector?: string;
  displayLabel: string;
  operatorFeedback?: string;
}): string {
  const modelClause = params.selector
    ? `with \`model: "${params.selector}"\` (selected via the \`continue with\` slider role \`${params.displayLabel}\`; omit \`agent\` so default \`task\` runs read-only under plan mode without conflicting with any agent-specific model override)`
    : `using default \`task\` (selected slider role \`${params.role}\`)`;

  const lines = [
    `Critique the current plan before finalizing it:`,
    ``,
    `1. Spawn ONE \`task\` subagent ${modelClause} to rigorously critique the plan at \`${params.planFilePath}\` ("${params.title}") against the live codebase. Instruct the subagent to read the plan file and verify referenced files, symbols, control flow, edge cases, failure modes, and verification steps, then return:`,
    `   - **Verdict**: ready vs. needs changes`,
    `   - **TL;DR**: 3-5 concise bullets summarizing what it found`,
    `   - **Actionable findings**: concrete bugs, wrong file/symbol/API assumptions, missing edge cases, ordering hazards, or verification gaps (with exact file/symbol evidence; skip nitpicks and out-of-scope expansion)`,
    `2. Incorporate every valid critique finding into \`${params.planFilePath}\` (leave sound parts alone; if the critique found zero real issues, keep the plan unchanged).`,
    `3. Write a short **Critique TL;DR (${params.role})** Markdown summary (the verdict + 3-5 bullets of what the critique said and what you changed or rejected) to \`out://\` via \`write\` so it stays visible in the chat transcript.`,
    `4. Re-propose the plan by writing its title/slug to \`xd://propose\` via \`write\` so Plan Review reopens.`,
  ];

  const extra = params.operatorFeedback?.trim();
  if (extra) {
    lines.push(``, `Also address these inline annotations/notes from my review:`, ``, extra);
  }
  return lines.join("\n");
}

const sharedGlobals = globalThis as {
  [PATCHED]?: boolean;
  [PENDING_KEY]?: Map<string, PendingReview>;
};
const pendingBySession = (sharedGlobals[PENDING_KEY] ??= new Map<string, PendingReview>());

export default async function planCritique(pi: ExtensionAPI) {
  pi.on("plan_review_requested", (event, ctx) => {
    pendingBySession.set(event.sessionId, {
      reviewId: event.reviewId,
      sessionId: event.sessionId,
      title: event.title,
      planFilePath: event.planFilePath,
      tiers: event.tiers,
      ctx,
    });
  });

  pi.on("plan_review_resolved", event => {
    const current = pendingBySession.get(event.sessionId);
    if (current?.reviewId === event.reviewId) {
      pendingBySession.delete(event.sessionId);
    }
  });

  if (sharedGlobals[PATCHED]) return;

  const host = await loadHost();
  if (!host) return;
  if (sharedGlobals[PATCHED]) return;
  sharedGlobals[PATCHED] = true;

  const proto = host.InteractiveMode.prototype;
  const originalShowPlanReview = proto.showPlanReview;

  proto.showPlanReview = function (
    this: InteractiveModeLike,
    planContent: string,
    title: string,
    options: ReviewOptionsArg,
    callbacks?: ShowPlanReviewCallbacks,
    extra?: ShowPlanReviewExtra,
  ) {
    if (title !== PROMPT_TITLE || !Array.isArray(options) || options.length === 0) {
      return originalShowPlanReview.call(this, planContent, title, options, callbacks, extra);
    }

    const isStringMode = typeof options[0] === "string";
    const slider = extra?.slider;
    let sliderIdx = slider?.index ?? 0;
    let latestFeedback = "";

    const wrappedSlider: SliderConfig | undefined = slider
      ? {
          ...slider,
          onChange: (idx: number) => {
            sliderIdx = idx;
            slider.onChange?.(idx);
          },
        }
      : undefined;

    const refineChoice = isStringMode ? "Refine plan" : "refine";
    const wrappedCallbacks: ShowPlanReviewCallbacks = {
      ...callbacks,
      onFeedbackChange: (feedback: string) => {
        latestFeedback = feedback;
        callbacks?.onFeedbackChange?.(feedback);
      },
      onClose: callbacks?.onClose
        ? (choice: string | undefined) => {
            const pickedCritique = isStringMode ? choice === CRITIQUE_LABEL : choice === CRITIQUE_ID;
            callbacks.onClose?.(pickedCritique ? refineChoice : choice);
          }
        : undefined,
    };

    const injected = injectCritiqueOption(options, wrappedCallbacks);
    const wrappedExtra = wrappedSlider ? { ...extra, slider: wrappedSlider } : extra;

    const sessionId =
      this.sessionManager?.getSessionId?.() ?? this.session?.sessionManager?.getSessionId?.();

    const resultPromise = originalShowPlanReview.call(
      this,
      planContent,
      title,
      injected.options,
      injected.callbacks,
      wrappedExtra,
    );

    return resultPromise.then(picked => {
      const pickedCritique = isStringMode ? picked === CRITIQUE_LABEL : picked === CRITIQUE_ID;
      if (!pickedCritique) return picked;

      const pending = sessionId ? pendingBySession.get(sessionId) : undefined;
      const role = slider?.segments?.[sliderIdx]?.label ?? "default";
      const resolved = resolveCritiqueSelector(role, host, this.session, pending?.tiers);
      const feedback = buildCritiqueFeedback({
        planFilePath: pending?.planFilePath ?? "the active plan file",
        title: pending?.title ?? "current plan",
        role: resolved.role,
        selector: resolved.selector,
        displayLabel: resolved.displayLabel,
        operatorFeedback: latestFeedback,
      });

      // Populate the local feedback buffer that handlePlanApproval reads when
      // `showPlanReview` resolves with `"refine"` / `"Refine plan"`.
      wrappedCallbacks.onFeedbackChange?.(feedback);
      return refineChoice;
    });
  };
}

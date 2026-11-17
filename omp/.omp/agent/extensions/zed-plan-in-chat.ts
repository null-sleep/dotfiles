import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

/**
 * Zed: post the whole plan to the chat before omp's plan-approval card.
 *
 * omp's ACP plan approval (`#requestAcpPlanApprovalChoice` in
 * modes/acp/acp-agent.ts) is a form elicitation whose message carries only a
 * 12-line plain-text preview, so in Zed you approve a plan you can't read.
 * This wraps three host prototypes (extensions get the host's live module
 * instances, the mechanism turn-count.ts relies on):
 *
 * - `AgentSession.prototype.setPlanProposalHandler`: before omp's handler runs,
 *   resolve the plan exactly as omp will (`resolveApprovedPlan`, read-only) and
 *   stash it under the exact approval message omp is about to build.
 * - `AgentSideConnection.prototype.unstable_createElicitation`: on an exact
 *   stash hit, send the full plan as an `agent_message_chunk` (Zed renders it
 *   as markdown), then forward the elicitation with the preview replaced by a
 *   pointer to the chat. An unchanged re-proposal in the same turn isn't
 *   posted again.
 * - `AcpAgent.prototype.prompt`: resets that same-turn dedupe.
 *
 * omp still owns the decision: the elicitation's schema and options are never
 * touched and the wrapper never answers it. Any miss or failure forwards the
 * original params, so the worst case is the stock 12-line card.
 *
 * Opt-in via OMP_ZED_PLAN_IN_CHAT=1, set only in Zed's `agent_servers.omp.env`;
 * the variable is deleted after reading so child omp processes start stock.
 * Design and verification: plans/zed-omp-plan-approval-preview.md.
 */

const ENV_FLAG = "OMP_ZED_PLAN_IN_CHAT";
const PATCHED = Symbol.for("zed-plan-in-chat");
// Mirrors the preview rule in omp's #requestAcpPlanApprovalChoice.
const PREVIEW_LINES = 12;

type LocalProtocolOptions = { getArtifactsDir(): string; getSessionId(): string };
type PlanFileOptions = { localProtocolOptions: LocalProtocolOptions; cwd: string };
type SessionLike = {
  sessionManager: { getArtifactsDir(): string; getSessionId(): string; getCwd(): string };
  getPlanModeState(): { enabled?: boolean; planFilePath: string } | undefined;
};
type PlanProposalHandler = (title: string) => Promise<unknown>;
type ElicitationParams = { sessionId: string; message?: unknown };
type ConnectionLike = { sessionUpdate(params: unknown): Promise<void> };
type Stashed = { title: string; planContent: string; absPath: string };

type Host = {
  AgentSideConnection: { prototype: ConnectionLike & { unstable_createElicitation(params: ElicitationParams): Promise<unknown> } };
  AgentSession: { prototype: { setPlanProposalHandler(handler: PlanProposalHandler | null): void } };
  AcpAgent: { prototype: { prompt(params: { sessionId?: unknown }): Promise<unknown> } };
  resolveApprovedPlan(input: {
    suppliedTitle?: unknown;
    statePlanFilePath: string;
    readPlan(url: string): Promise<string | null>;
    listPlanFiles?(): Promise<string[]>;
  }): Promise<{ planFilePath: string; planContent: string; title: string }>;
  readPlanFile(url: string, options: PlanFileOptions): Promise<string | null>;
  listPlanFiles(options: { localProtocolOptions: LocalProtocolOptions }): Promise<string[]>;
  resolvePlanFilePath(url: string, options: PlanFileOptions): string;
};

async function loadHost(): Promise<Host | undefined> {
  try {
    const [acp, session, acpAgent, approved, files] = await Promise.all([
      import("@oh-my-pi/pi-utils/acp"),
      import("@oh-my-pi/pi-coding-agent/session/agent-session"),
      import("@oh-my-pi/pi-coding-agent/modes/acp/acp-agent"),
      import("@oh-my-pi/pi-coding-agent/plan-mode/approved-plan"),
      import("@oh-my-pi/pi-coding-agent/plan-mode/plan-files"),
    ]);
    const host = {
      AgentSideConnection: acp.AgentSideConnection,
      AgentSession: session.AgentSession,
      AcpAgent: acpAgent.AcpAgent,
      resolveApprovedPlan: approved.resolveApprovedPlan,
      readPlanFile: files.readPlanFile,
      listPlanFiles: files.listPlanFiles,
      resolvePlanFilePath: files.resolvePlanFilePath,
    } as Partial<Host>;
    const ok =
      typeof host.AgentSideConnection?.prototype?.unstable_createElicitation === "function" &&
      typeof host.AgentSideConnection.prototype.sessionUpdate === "function" &&
      typeof host.AgentSession?.prototype?.setPlanProposalHandler === "function" &&
      typeof host.AcpAgent?.prototype?.prompt === "function" &&
      typeof host.resolveApprovedPlan === "function" &&
      typeof host.readPlanFile === "function" &&
      typeof host.listPlanFiles === "function" &&
      typeof host.resolvePlanFilePath === "function";
    return ok ? (host as Host) : undefined;
  } catch {
    return undefined;
  }
}

/** The exact message omp's #requestAcpPlanApprovalChoice sends for this plan. */
function approvalMessage(title: string, planContent: string): string {
  const lines = planContent.split("\n");
  const preview = lines.slice(0, PREVIEW_LINES).join("\n");
  const ellipsis = lines.length > PREVIEW_LINES ? "\n…" : "";
  return `Approve plan "${title}" and start implementation?\n\n${preview}${ellipsis}`;
}

export default async function zedPlanInChat(_pi: ExtensionAPI) {
  const globals = globalThis as { [PATCHED]?: boolean };
  // Extensions load per ACP session; the patches are process-wide, so later
  // loads (after the flag was consumed below) have nothing to do.
  if (globals[PATCHED]) return;
  if (process.env[ENV_FLAG] !== "1") return;
  delete process.env[ENV_FLAG];

  const host = await loadHost();
  if (!host) {
    // stderr is safe under ACP (stdout carries the protocol); Zed keeps it in its agent log.
    console.error("zed-plan-in-chat: omp host API not found; plan approval stays stock");
    return;
  }
  if (globals[PATCHED]) return;
  globals[PATCHED] = true;

  // Keyed by the exact approval message; overwritten on re-proposal, deleted on use.
  const stash = new Map<string, Stashed>();
  // Last plan text posted per ACP session. After Refine, plan mode keeps nudging
  // the model to call a tool, so it often re-proposes an unchanged plan within
  // the same turn; skip reposting an identical copy right under the previous one.
  // Cleared at every session/prompt: a thread reload (session/load replays
  // history without the live-only chunk) is always followed by a new prompt.
  const lastPosted = new Map<string, string>();

  const agentProto = host.AcpAgent.prototype;
  const originalPrompt = agentProto.prompt;
  agentProto.prompt = function (this: unknown, params: { sessionId?: unknown }) {
    if (typeof params?.sessionId === "string") lastPosted.delete(params.sessionId);
    return originalPrompt.call(this, params);
  };

  async function remember(session: SessionLike, title: string): Promise<void> {
    const state = session.getPlanModeState();
    if (!state?.enabled) return;
    const manager = session.sessionManager;
    const options: PlanFileOptions = {
      localProtocolOptions: {
        getArtifactsDir: () => manager.getArtifactsDir(),
        getSessionId: () => manager.getSessionId(),
      },
      cwd: manager.getCwd(),
    };
    // Same inputs as omp's #handleAcpPlanProposal; resolveApprovedPlan only reads.
    const plan = await host!.resolveApprovedPlan({
      suppliedTitle: title,
      statePlanFilePath: state.planFilePath,
      readPlan: url => host!.readPlanFile(url, options),
      listPlanFiles: () => host!.listPlanFiles({ localProtocolOptions: options.localProtocolOptions }),
    });
    stash.set(approvalMessage(plan.title, plan.planContent), {
      title: plan.title,
      planContent: plan.planContent,
      absPath: host!.resolvePlanFilePath(plan.planFilePath, options),
    });
  }

  const sessionProto = host.AgentSession.prototype;
  const originalSetHandler = sessionProto.setPlanProposalHandler;
  sessionProto.setPlanProposalHandler = function (this: SessionLike, handler: PlanProposalHandler | null) {
    const wrapped: PlanProposalHandler | null = handler
      ? async title => {
          await remember(this, title).catch(() => {});
          return handler(title);
        }
      : handler;
    return originalSetHandler.call(this, wrapped);
  };

  const connectionProto = host.AgentSideConnection.prototype;
  const originalElicit = connectionProto.unstable_createElicitation;
  connectionProto.unstable_createElicitation = async function (this: ConnectionLike, params: ElicitationParams) {
    const key = typeof params?.message === "string" ? params.message : undefined;
    const hit = key === undefined ? undefined : stash.get(key);
    if (!hit) return originalElicit.call(this, params);
    stash.delete(key!);
    const text = `${hit.planContent.trimEnd()}\n\n---\n\nPlan file: \`${hit.absPath}\``;
    const unchanged = lastPosted.get(params.sessionId) === text;
    if (!unchanged) {
      try {
        await this.sessionUpdate({
          sessionId: params.sessionId,
          update: {
            sessionUpdate: "agent_message_chunk",
            messageId: crypto.randomUUID(),
            content: { type: "text", text },
          },
        });
      } catch {
        return originalElicit.call(this, params);
      }
      lastPosted.set(params.sessionId, text);
    }
    const pointer = unchanged ? "The plan is unchanged from the copy above." : "The full plan is in the chat above.";
    return originalElicit.call(this, {
      ...params,
      message: `Approve plan "${hit.title}" and start implementation? ${pointer}`,
    });
  };
}

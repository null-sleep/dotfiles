// End-to-end check for omp/.omp/agent/extensions/zed-plan-in-chat.ts: drives
// `omp acp` with the Zed entry's flags through one plan proposal, like Zed.
// Needs the omp package stowed; makes a few cheap model calls (~10 s each).
// Rerun both variants after `brew upgrade omp`:
//   bun omp/tests/zed-plan-in-chat-smoke.ts with     # extension on: full plan in chat, short card
//   bun omp/tests/zed-plan-in-chat-smoke.ts without  # env unset: stock 12-line card
// Optional third arg: substring of the model to use (default "haiku").
// DUMP=<n> prints every recorded event from index n.
// STRICT=1 fails a SKIP (the model never re-proposed, so dedupe went untested).
// On any failure, the tail of omp's stderr is printed.
type Obj = Record<string, unknown>;
type Msg = { jsonrpc: "2.0"; id?: number | string; method?: string; params?: Obj; result?: Obj; error?: unknown };

const isObj = (v: unknown): v is Obj => typeof v === "object" && v !== null;
function at(v: unknown, ...path: string[]): unknown {
  let cur = v;
  for (const key of path) cur = isObj(cur) ? cur[key] : undefined;
  return cur;
}
const str = (v: unknown): string => (typeof v === "string" ? v : "");

const variant = process.argv[2] ?? "with";
const modelHint = process.argv[3] ?? "haiku";
const workdir = `/tmp/zed-plan-in-chat-smoke/${variant}`;
await Bun.$`rm -rf ${workdir} && mkdir -p ${workdir}`;

const env: Record<string, string | undefined> = { ...process.env };
if (variant === "with") env.OMP_ZED_PLAN_IN_CHAT = "1";
else delete env.OMP_ZED_PLAN_IN_CHAT;

const proc = Bun.spawn(
  ["/opt/homebrew/bin/omp", "acp", "--approval-mode", "yolo", "--config", `${process.env.HOME}/.omp/agent/zed-models.yml`],
  { stdin: "pipe", stdout: "pipe", stderr: "pipe", env, cwd: workdir },
);
// Drained continuously so a chatty omp can't block on a full pipe.
let stderrText = "";
void (async () => {
  const decoder = new TextDecoder();
  for await (const chunk of proc.stderr) stderrText = (stderrText + decoder.decode(chunk)).slice(-8000);
})();
// Any hang (omp exiting mid-handshake, a lost response) fails instead of blocking.
setTimeout(() => {
  console.log("FAIL overall timeout");
  proc.kill();
  process.exit(2);
}, 300_000).unref();

const events: { kind: string; data: Obj }[] = [];
const pending = new Map<number, (m: Msg) => void>();
let nextId = 1;
let elicitations = 0;
// Phase 1: first prompt (refine, then dismiss re-proposals). Phase 2 ("with" only):
// a second prompt, where the same plan must be posted again (dedupe resets per turn).
let phase = 1;
let phaseElicitations = 0;
let phase2Start = -1;

function send(m: Msg): void {
  proc.stdin.write(`${JSON.stringify(m)}\n`);
}
function request(method: string, params: Obj): Promise<Msg> {
  const id = nextId++;
  const { promise, resolve } = Promise.withResolvers<Msg>();
  pending.set(id, resolve);
  send({ jsonrpc: "2.0", id, method, params });
  return promise;
}

void (async () => {
  const decoder = new TextDecoder();
  let buf = "";
  for await (const chunk of proc.stdout) {
    buf += decoder.decode(chunk);
    for (let nl = buf.indexOf("\n"); nl >= 0; nl = buf.indexOf("\n")) {
      const line = buf.slice(0, nl).trim();
      buf = buf.slice(nl + 1);
      if (!line) continue;
      let m: Msg;
      try {
        m = JSON.parse(line) as Msg;
      } catch {
        console.log(`non-JSON stdout line: ${line.slice(0, 200)}`);
        continue;
      }
      const params = m.params ?? {};
      if (m.method === "session/update") {
        const update = isObj(params.update) ? params.update : {};
        events.push({ kind: `update:${str(update.sessionUpdate)}`, data: update });
      } else if (m.method === "elicitation/create" && m.id !== undefined) {
        elicitations++;
        phaseElicitations++;
        events.push({ kind: "elicitation", data: params });
        const refine = phase === 1 && phaseElicitations === 1;
        const result = refine ? { action: "accept", content: { value: "Refine plan" } } : { action: "cancel" };
        send({ jsonrpc: "2.0", id: m.id, result });
        // Plan mode re-prompts after a refine; stop phase 1 after three proposals, phase 2 after one.
        if ((phase === 1 && phaseElicitations === 3) || phase === 2) {
          send({ jsonrpc: "2.0", method: "session/cancel", params: { sessionId: params.sessionId } });
        }
      } else if (m.method && m.id !== undefined) {
        events.push({ kind: `request:${m.method}`, data: params });
        send({ jsonrpc: "2.0", id: m.id, error: { code: -32601, message: "not supported by smoke client" } });
      } else if (m.id !== undefined) {
        const resolve = pending.get(Number(m.id));
        pending.delete(Number(m.id));
        resolve?.(m);
      }
    }
  }
})();

function must(m: Msg, what: string): Obj {
  if (m.error) throw new Error(`${what}: ${JSON.stringify(m.error)}`);
  return m.result ?? {};
}

must(
  await request("initialize", {
    protocolVersion: 1,
    clientCapabilities: { elicitation: { form: {} } },
    clientInfo: { name: "zed", version: "smoke" },
  }),
  "initialize",
);
const created = must(await request("session/new", { cwd: workdir, mcpServers: [] }), "session/new");
const sessionId = str(created.sessionId);
const configOptions = Array.isArray(created.configOptions) ? created.configOptions : [];
const modelOption = configOptions.find(o => at(o, "id") === "model");
const rawOptions = at(modelOption, "options");
const flat = (Array.isArray(rawOptions) ? rawOptions : []).flatMap(o => {
  const nested = at(o, "options");
  return Array.isArray(nested) ? nested : [o];
});
const cheap = flat.find(o => str(at(o, "value")).toLowerCase().includes(modelHint));
if (cheap) must(await request("session/set_config_option", { sessionId, configId: "model", value: at(cheap, "value") }), "set model");
console.log(`model: ${str(at(cheap, "value")) || str(at(modelOption, "currentValue"))}`);
must(await request("session/set_mode", { sessionId, modeId: "plan" }), "set_mode");

const prompt = [
  "This is an automated test of plan approval. Do not read or explore any files.",
  "Immediately write a plan file whose content is a '# Dummy plan' heading followed by exactly 40 lines",
  "'Step 1: do thing 1' through 'Step 40: do thing 40', then propose it for approval with the title dummy.",
  "If refinement is requested, propose the identical plan again without changing the file.",
].join(" ");
const done = await Promise.race([
  request("session/prompt", { sessionId, prompt: [{ type: "text", text: prompt }] }),
  Bun.sleep(240_000).then((): Msg => ({ jsonrpc: "2.0", error: "timeout" })),
]);
if (variant === "with") {
  phase = 2;
  phaseElicitations = 0;
  phase2Start = events.length;
  const again = "Propose the same plan for approval again now, without changing the file.";
  await Promise.race([request("session/prompt", { sessionId, prompt: [{ type: "text", text: again }] }), Bun.sleep(120_000)]);
}
proc.kill();
if (process.env.DUMP) {
  for (const [i, e] of events.entries()) {
    if (i >= Number(process.env.DUMP)) console.log(i, e.kind, JSON.stringify(e.data).slice(0, 220));
  }
}

const elicitIdx = events.findIndex(e => e.kind === "elicitation");
const elicitMessage = str(events[elicitIdx]?.data.message);
const chunkText = (e: { data: Obj }) => str(at(e.data, "content", "text"));
const planChunkIdx = events.findIndex(
  e => e.kind === "update:agent_message_chunk" && chunkText(e).includes("Step 40: do thing 40") && chunkText(e).includes("Plan file:"),
);
const modeToDefault = events.some(e => e.kind === "update:current_mode_update" && e.data.currentModeId === "default");
console.log(
  JSON.stringify(
    {
      variant,
      stopReason: at(done.result, "stopReason") ?? done.error,
      elicitations,
      elicitMessage,
      planChunkIdx,
      elicitIdx,
      planChunkMessageId: events[planChunkIdx]?.data.messageId,
      modeToDefault,
    },
    null,
    2,
  ),
);
if (planChunkIdx >= 0) {
  const text = chunkText(events[planChunkIdx]);
  console.log(`--- plan chunk ---\n${text.slice(0, 120)}\n...\n${text.slice(-160)}`);
}

/** Each re-proposal must either repost a changed plan or show the "unchanged" card with no new copy. */
function dedupeCheck(): boolean | "skip" {
  let prompts = 0;
  let lastChunk: string | undefined;
  let chunkSincePrompt: string | undefined;
  for (const e of phase2Start >= 0 ? events.slice(0, phase2Start) : events) {
    if (e.kind === "update:agent_message_chunk" && chunkText(e).includes("Plan file:")) {
      chunkSincePrompt = chunkText(e);
    } else if (e.kind === "elicitation" && str(e.data.message).startsWith("Approve plan")) {
      prompts++;
      const unchangedCard = str(e.data.message).endsWith("The plan is unchanged from the copy above.");
      const ok = unchangedCard
        ? chunkSincePrompt === undefined
        : chunkSincePrompt !== undefined && chunkSincePrompt !== lastChunk;
      if (prompts > 1 && !ok) return false;
      if (chunkSincePrompt !== undefined) lastChunk = chunkSincePrompt;
      chunkSincePrompt = undefined;
    }
  }
  return prompts < 2 ? "skip" : true;
}

/** In phase 2 the first plan card must follow a fresh plan chunk, not the "unchanged" pointer. */
function nextTurnReposted(): boolean {
  const later = events.slice(phase2Start);
  const card = later.findIndex(e => e.kind === "elicitation" && str(e.data.message).startsWith("Approve plan"));
  if (card < 0) return false;
  const posted = later.slice(0, card).some(e => e.kind === "update:agent_message_chunk" && chunkText(e).includes("Plan file:"));
  return posted && str(later[card].data.message).endsWith("The full plan is in the chat above.");
}

const checks: [string, boolean | "skip"][] =
  variant === "with"
    ? [
        ["elicitation happened", elicitIdx >= 0],
        ["full plan chunk sent", planChunkIdx >= 0],
        ["plan chunk before elicitation", planChunkIdx >= 0 && planChunkIdx < elicitIdx],
        ["card has no plan body", !elicitMessage.includes("Step 1:") && elicitMessage.includes("full plan is in the chat above")],
        ["stayed in plan mode", !modeToDefault],
        // "skip" when the model never re-proposed, so the dedupe branch didn't run.
        ["re-proposals not reposted", dedupeCheck()],
        ["next turn posts the plan again", nextTurnReposted()],
      ]
    : [
        ["elicitation happened", elicitIdx >= 0],
        ["no plan chunk", planChunkIdx < 0],
        ["stock 12-line preview", elicitMessage.includes("Step 1:") && elicitMessage.endsWith("\n…")],
        ["stayed in plan mode", !modeToDefault],
      ];
const strict = process.env.STRICT === "1";
for (const [name, ok] of checks) console.log(`${ok === "skip" ? (strict ? "FAIL (skip)" : "SKIP") : ok ? "PASS" : "FAIL"} ${name}`);
const passed = checks.every(([, ok]) => ok === true || (ok === "skip" && !strict));
if (!passed && stderrText.trim()) console.log(`--- omp stderr (tail) ---\n${stderrText.slice(-2000)}`);
process.exit(passed ? 0 : 1);

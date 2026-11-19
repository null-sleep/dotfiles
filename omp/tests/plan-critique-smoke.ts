// End-to-end + unit smoke check for omp/.omp/agent/extensions/plan-critique.ts.
// Runs pure unit checks in Bun AND drives real TUI PlanReviewOverlay sessions
// in a PTY on installed omp binaries (stopping at `before_agent_start` so zero
// paid LLM calls are made).
//
// Rerun after `brew upgrade omp`:
//   bun omp/tests/plan-critique-smoke.ts
import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { mkdir, rm } from "node:fs/promises";
import {
  buildCritiqueFeedback,
  injectCritiqueOption,
  resolveCritiqueSelector,
} from "../.omp/agent/extensions/plan-critique";

// 1. 18.22+ object options: inserts right after "keep"
{
  const input = [
    { id: "execute", label: "Approve and execute", detail: "Start fresh" },
    { id: "compact", label: "Approve and compact context" },
    { id: "keep", label: "Approve and keep context", meta: "~207k / 1m" },
  ];
  const { options } = injectCritiqueOption(input);
  assert.equal(options.length, 4);
  assert.deepEqual(
    options.map(item => (typeof item === "string" ? item : item.id)),
    ["execute", "compact", "keep", "critique"],
  );
  assert.equal(injectCritiqueOption(options).options.length, 4);
}

// 2. 18.18.x string options: inserts right after "Approve and keep context..." and shifts disabledIndices
{
  const input = [
    "Approve and execute",
    "Approve and compact context",
    "Approve and keep context (~207k / 1m)",
    "Refine plan",
    "Save and quit",
  ];
  const { options, callbacks } = injectCritiqueOption(input, { disabledIndices: [2, 4] });
  assert.deepEqual(options, [
    "Approve and execute",
    "Approve and compact context",
    "Approve and keep context (~207k / 1m)",
    "Critique plan (subagent)",
    "Refine plan",
    "Save and quit",
  ]);
  assert.deepEqual(callbacks?.disabledIndices, [2, 5]);
}

// 3. Selector resolution preserves @upstream routing and thinking level from slider role
{
  const resolved = resolveCritiqueSelector(
    "sol",
    { cycleOrderLookup: { get: () => ["default", "sol", "opus"] } },
    {
      settings: {},
      getRoleModelCycle: () => ({
        currentIndex: 0,
        models: [
          {
            role: "default",
            model: { provider: "openrouter", id: "openai/gpt-6.1-terra", name: "GPT-6.1 Terra" },
            thinkingLevel: "high",
            explicitThinkingLevel: true,
          },
          {
            role: "sol",
            model: {
              provider: "openrouter",
              id: "openai/gpt-6.2-sol",
              name: "GPT-6.2 Sol",
              compat: { openRouterRouting: { only: ["azure"] } },
            },
            thinkingLevel: "xhigh",
            explicitThinkingLevel: true,
          },
        ],
      }),
    },
    undefined,
  );
  assert.equal(resolved.role, "sol");
  assert.equal(resolved.selector, "openrouter/openai/gpt-6.2-sol@azure:xhigh");
  assert.equal(resolved.displayLabel, "sol (GPT-6.2 Sol:xhigh)");

  const prompt = buildCritiqueFeedback({
    planFilePath: "local://ping-alert-plan.md",
    title: "ping-alert",
    role: resolved.role,
    selector: resolved.selector,
    displayLabel: resolved.displayLabel,
    operatorFeedback: "Refinement feedback on the plan:\n\n## Approach\n- Check metric cardinality",
  });
  assert.ok(prompt.includes('model: "openrouter/openai/gpt-6.2-sol@azure:xhigh"'));
  assert.ok(prompt.includes("local://ping-alert-plan.md"));
  assert.ok(prompt.includes("out://"));
  assert.ok(prompt.includes("xd://propose"));
  assert.ok(prompt.includes("Check metric cardinality"));
}

// 4. Real PTY TUI verification against installed omp binary(ies)
const workdir = `/tmp/plan-critique-smoke-${process.pid}`;
await rm(workdir, { recursive: true, force: true });
await mkdir(workdir, { recursive: true });

const extPath = new URL("../.omp/agent/extensions/plan-critique.ts", import.meta.url).pathname;
const driverExt = `${workdir}/driver.ts`;
const pyRunner = `${workdir}/run_pty.py`;

await Bun.write(
  driverExt,
  `import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { resolvePlanFilePath } from "@oh-my-pi/pi-coding-agent/plan-mode/plan-files";
import { mkdir } from "node:fs/promises";
import { dirname } from "node:path";

export default function (pi: ExtensionAPI) {
  pi.on("session_start", (_event, ctx) => {
    void (async () => {
      for (let attempt = 0; attempt < 40; attempt++) {
        const res = await ctx.sessionModes?.set({ mode: "plan", action: "enter" });
        if (res?.ok) break;
        await Bun.sleep(50);
      }
      const planPath = resolvePlanFilePath("local://demo-plan.md", {
        cwd: ctx.cwd,
        localProtocolOptions: {
          getArtifactsDir: () => ctx.sessionManager.getArtifactsDir(),
          getSessionId: () => ctx.sessionManager.getSessionId(),
        },
      });
      await mkdir(dirname(planPath), { recursive: true });
      await Bun.write(
        planPath,
        "# Demo Plan\\n\\n## Context\\nTest context\\n\\n## Approach\\n1. Step one\\n2. Step two\\n",
      );
      for (let attempt = 0; attempt < 40; attempt++) {
        if (await ctx.openPlanReview()) break;
        await Bun.sleep(50);
      }
    })();
  });

  pi.on("before_agent_start", async (event, ctx) => {
    const outPath = process.env.PLAN_CRITIQUE_RESULT_FILE;
    if (outPath) {
      const current = ctx.models.current();
      await Bun.write(
        outPath,
        JSON.stringify({
          prompt: event.prompt,
          modelMatch: event.prompt.match(/model: "([^"]+)"/)?.[1] ?? null,
          roleMatch: event.prompt.match(/Critique TL;DR \\(([^)]+)\\)/)?.[1] ?? null,
          hasOut: event.prompt.includes("out://"),
          hasPropose: event.prompt.includes("xd://propose"),
          activeModel: current ? current.provider + "/" + current.id : null,
          thinking: pi.getThinkingLevel(),
          planStatus: ctx.sessionModes?.getState().plan.status ?? null,
        }),
      );
    }
    process.exit(0);
  });
}
`,
);

await Bun.write(
  pyRunner,
  `import fcntl, os, pty, re, select, struct, sys, termios, time

omp_bin, mode, out_file = sys.argv[1], sys.argv[2], sys.argv[3]
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"
    os.environ["PLAN_CRITIQUE_RESULT_FILE"] = out_file
    os.execvp(omp_bin, [
        omp_bin,
        "--no-session",
        "--no-extensions",
        "-e", ${JSON.stringify(extPath)},
        "-e", ${JSON.stringify(driverExt)},
    ])

try:
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
    buf = b""
    replied = False

    def plain_screen():
        return re.sub(
            r"\\x1b\\[[0-9;?]*[A-Za-z]|\\x1b\\][^\\x07\\x1b]*(?:\\x07|\\x1b\\\\)",
            "",
            buf.decode("utf-8", "replace"),
        )

    def pump(secs, stop_when=None):
        global buf, replied
        end = time.time() + secs
        while time.time() < end:
            if stop_when and stop_when():
                return True
            r, _, _ = select.select([fd], [], [], 0.05)
            if r:
                try:
                    chunk = os.read(fd, 65536)
                    if not chunk:
                        break
                    buf += chunk
                    if not replied and (b"\\x1b]11;?" in buf or b"\\x1b[6n" in buf or b"\\x1b[c" in buf):
                        replied = True
                        os.write(fd, b"\\x1b]11;rgb:1e1e/1e1e/2e2e\\x07\\x1b[1;1R\\x1b[?62;c")
                except OSError:
                    break
        return bool(stop_when and stop_when())

    found_row = pump(8.0, lambda: "Critique plan (subagent)" in plain_screen())
    print("HAS_CRITIQUE_ROW:" + ("1" if found_row else "0"))

    # Move slider right 1 step from default (index 0) -> second cycle role
    os.write(fd, b"\\x1b[C")
    pump(0.2)

    if mode == "critique":
        # Down 3 rows: execute (0) -> compact (1) -> keep (2) -> Critique plan (subagent) (3)
        os.write(fd, b"\\x1b[B\\x1b[B\\x1b[B")
        pump(0.2)

    os.write(fd, b"\\r")
    pump(4.0, lambda: os.path.exists(out_file))
finally:
    try:
        os.kill(pid, 9)
    except OSError:
        pass
`,
);

async function runPtyScenario(ompBin: string, mode: "critique" | "approve") {
  const resultFile = `${workdir}/result-${mode}.json`;
  await rm(resultFile, { force: true });
  const proc = Bun.spawn(["python3", pyRunner, ompBin, mode, resultFile], {
    cwd: workdir,
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  await proc.exited;
  assert.ok(
    stdout.includes("HAS_CRITIQUE_ROW:1"),
    `Expected Critique plan (subagent) row in ${ompBin}:\n${stdout}\n${stderr}`,
  );
  assert.ok(
    existsSync(resultFile),
    `Expected before_agent_start capture for ${ompBin} (${mode}):\n${stdout}\n${stderr}`,
  );
  const data: unknown = await Bun.file(resultFile).json();
  assert.ok(typeof data === "object" && data !== null);
  return data;
}

try {
  const bins = ["/opt/homebrew/bin/omp", `${process.env.HOME}/.local/bin/omp`].filter(bin =>
    existsSync(bin),
  );
  for (const bin of bins) {
    const rolesProc = Bun.spawn([bin, "config", "get", "modelRoles", "--json"], {
      stdout: "pipe",
      stderr: "ignore",
    });
    const rolesJson: unknown = JSON.parse(await new Response(rolesProc.stdout).text());
    await rolesProc.exited;
    const configuredRoles: unknown =
      typeof rolesJson === "object" && rolesJson !== null
        ? Reflect.get(rolesJson, "value")
        : undefined;

    const critiqueData = await runPtyScenario(bin, "critique");
    assert.equal(Reflect.get(critiqueData, "planStatus"), "active");
    assert.equal(Reflect.get(critiqueData, "hasOut"), true);
    assert.equal(Reflect.get(critiqueData, "hasPropose"), true);
    const roleMatch = Reflect.get(critiqueData, "roleMatch");
    const modelMatch = Reflect.get(critiqueData, "modelMatch");
    assert.ok(typeof roleMatch === "string" && roleMatch !== "default");
    assert.ok(typeof modelMatch === "string" && modelMatch.includes("/"));
    const expectedRoleSelector =
      typeof configuredRoles === "object" && configuredRoles !== null
        ? Reflect.get(configuredRoles, roleMatch)
        : undefined;
    if (typeof expectedRoleSelector === "string" && !expectedRoleSelector.startsWith("@")) {
      assert.equal(modelMatch, expectedRoleSelector);
    }
    console.log(`PASS PTY critique (${bin}) -> role=${roleMatch} model=${modelMatch}`);
  }

  if (existsSync("/opt/homebrew/bin/omp")) {
    const approveData = await runPtyScenario("/opt/homebrew/bin/omp", "approve");
    assert.equal(Reflect.get(approveData, "planStatus"), "inactive");
    console.log(
      `PASS PTY approve (/opt/homebrew/bin/omp) -> activeModel=${String(Reflect.get(approveData, "activeModel"))}:${String(Reflect.get(approveData, "thinking"))}`,
    );
  }
} finally {
  await rm(workdir, { recursive: true, force: true });
}

console.log("PASS all plan-critique smoke checks");

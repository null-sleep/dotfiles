import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

type ConfigResponse<T> = { value: T };
type PresetThinkingLevel = "off" | "minimal" | "low" | "medium" | "high" | "xhigh" | "max";

const SHORTCUT = "alt+o";
const THINKING_SUFFIX = /:(off|minimal|low|medium|high|xhigh|max)$/;

async function readConfig<T>(pi: ExtensionAPI, cwd: string, key: string): Promise<T> {
  const result = await pi.exec("omp", ["config", "get", key, "--json"], {
    cwd,
    timeout: 5_000,
  });
  if (result.code !== 0) {
    throw new Error(result.stderr.trim() || `omp config get ${key} failed`);
  }
  return (JSON.parse(result.stdout) as ConfigResponse<T>).value;
}

export default function cycleModelPicker(pi: ExtensionAPI) {
  pi.registerShortcut(SHORTCUT, {
    description: "Fuzzy-pick a configured cycle model preset",
    handler: async ctx => {
      if (!ctx.hasUI) return;

      try {
        const [cycleOrder, modelRoles] = await Promise.all([
          readConfig<string[]>(pi, ctx.cwd, "cycleOrder"),
          readConfig<Record<string, string>>(pi, ctx.cwd, "modelRoles"),
        ]);

        const presets = cycleOrder.flatMap(role => {
          const selector = modelRoles[role];
          if (!selector) return [];
          const thinking = selector.match(THINKING_SUFFIX)?.[1] as PresetThinkingLevel | undefined;
          return [{
            role,
            selector,
            thinking,
            model: ctx.models.resolve(`@${role}`),
          }];
        });
        if (presets.length === 0) {
          ctx.ui.notify("No configured cycle model presets", "warning");
          return;
        }

        const current = ctx.models.current();
        const currentThinking = pi.getThinkingLevel();
        const initialIndex = Math.max(
          0,
          presets.findIndex(preset =>
            preset.model?.provider === current?.provider &&
            preset.model?.id === current?.id &&
            (!preset.thinking || preset.thinking === currentThinking),
          ),
        );
        const selected = await ctx.ui.select(
          "Cycle model presets",
          presets.map(preset => ({
            label: preset.role,
            description: preset.model
              ? `${preset.model.provider}/${preset.model.id}${preset.thinking ? ` · ${preset.thinking}` : ""}`
              : `${preset.selector} · unavailable`,
          })),
          {
            initialIndex,
            helpText: "type to filter  up/down navigate  enter select  esc cancel",
          },
        );
        if (!selected) return;

        const preset = presets.find(candidate => candidate.role === selected);
        if (!preset?.model) {
          ctx.ui.notify(`Preset ${selected} is unavailable`, "warning");
          return;
        }
        if (!(await pi.setModel(preset.model))) {
          ctx.ui.notify(`Could not switch to ${selected}`, "error");
          return;
        }
        if (preset.thinking) pi.setThinkingLevel(preset.thinking);
        ctx.ui.notify(`Switched to ${selected}`, "info");
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        ctx.ui.notify(`Cycle preset picker failed: ${message}`, "error");
      }
    },
  });
}

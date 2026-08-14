import * as host from "@oh-my-pi/pi-coding-agent";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import * as path from "node:path";

const SEGMENT_ID = "cwd_name";

type SegmentLike = { id: string; render(ctx: unknown): { content: string; visible: boolean } };
type CtxLike = { worktree?: { projectName?: string; worktreeName?: string } };

/**
 * Launch-folder segment for the native status line, so a shell-launched omp
 * shows which project it's in: the basename of the working directory, or
 * `project/worktree` when the segment context identifies a linked git
 * worktree. Registered through the live `SEGMENTS` record like
 * turn-count.ts (which documents the mechanism and the theme/render
 * caveats followed here). Inside an nvim sidekick terminal ($NVIM
 * inherited) nvim already shows the project, so skip registration — the
 * configured id then renders invisible.
 */
export default function cwdName(_pi: ExtensionAPI) {
  if (process.env.NVIM) return;
  const registry = (host as { SEGMENTS?: Record<string, SegmentLike> }).SEGMENTS;
  if (!registry) return;
  const liveTheme = () => (host as { theme?: { fg(color: string, text: string): string } }).theme;
  try {
    registry[SEGMENT_ID] = {
      id: SEGMENT_ID,
      render: (ctx) => {
        try {
          const wt = (ctx as CtxLike | undefined)?.worktree;
          const name =
            wt?.projectName && wt.worktreeName
              ? `${wt.projectName}/${wt.worktreeName}`
              : path.basename(process.cwd());
          if (!name) return { content: "", visible: false };
          return { content: liveTheme()?.fg("dim", name) ?? name, visible: true };
        } catch {
          return { content: "", visible: false };
        }
      },
    };
  } catch {
    // frozen registry — nothing to show; the configured id renders invisible
  }
}

-- omp (oh-my-pi, a pi fork) has no upstream sidekick preset — sidekick
-- resolves sk/cli/<tool>.lua from the runtimepath, so this config-local spec
-- integrates it exactly like pi's bundled one. Mirrors sk/cli/pi.lua.
---@type sidekick.cli.Config
return {
  cmd = { "omp" },
  is_proc = "\\<omp\\>",
  url = "https://github.com/can1357/oh-my-pi",
  resume = { "--resume" },
  continue = { "--continue" },
  native_scroll = false,
}

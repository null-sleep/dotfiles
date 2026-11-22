-- omp (oh-my-pi) has no upstream sidekick preset — sidekick resolves
-- sk/cli/<tool>.lua from the runtimepath, so this config-local spec
-- integrates it like a bundled one.
---@type sidekick.cli.Config
return {
  cmd = { "omp" },
  is_proc = "\\<omp\\>",
  url = "https://github.com/can1357/oh-my-pi",
  resume = { "--resume" },
  continue = { "--continue" },
  native_scroll = false,
}

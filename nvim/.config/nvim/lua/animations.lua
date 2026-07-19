-- Terminal-only animation (smear-cursor + cinnamon). Neovide animates
-- natively (see neovide.lua) — running these on top would double-animate.
if vim.g.neovide then return end

-- Not expressible as config below:
-- - :SmearCursorToggle toggles the smear at runtime.
-- - `vim.b.cinnamon_disable = true` disables cinnamon per buffer (could hook
--   a FileType autocmd over require('buffers').special_filetypes if panels
--   ever animate weirdly).
-- - cinnamon's docs have a flash.nvim integration recipe — relevant for the
--   flash eval queued in plans/nvim-backlog.md. Wrapping gd the same way
--   won't work here: it goes through the snacks picker, which moves the
--   cursor after the wrapped function returns.

vim.cmd.packadd('smear-cursor.nvim')
require('smear_cursor').setup({
  -- Smoother sub-cell smear glyphs (Symbols for Legacy Computing). Rare in
  -- fonts, but Ghostty renders the block natively — font never consulted.
  legacy_computing_symbols_support = true,
  -- Same, for the insert-mode vertical-bar smear.
  -- legacy_computing_symbols_support_vertical_bars = false,

  -- Defaults to the Cursor highlight; hex color if a theme looks off,
  -- 'none' to match the text color at the target.
  -- cursor_color = nil,

  -- Trail dynamics (defaults shown). Upstream's "faster smear" preset:
  -- 0.8 / 0.6 / 0.95 / 0.5. Lower damping (~0.65) = elastic overshoot.
  -- stiffness = 0.6,
  -- trailing_stiffness = 0.45,
  -- damping = 0.85,
  -- distance_stop_animating = 0.1,

  -- Frame time in ms (17 ≈ 60 fps); lower if choppy.
  -- time_interval = 17,
})

vim.cmd.packadd('cinnamon.nvim')
require('cinnamon').setup({
  -- 'basic' animates existing motions only (table in GUIDE.md "Animations").
  -- 'extra' is left off — it also remaps gg/G, 0/^/$, the z family, and
  -- counted h/j/k/l: a bigger behavior change than "add animation".
  keymaps = { basic = true },

  options = {
    -- 'cursor' (default) steps through intermediate lines; 'window' only
    -- animates off-screen jumps — the switch if on-screen n/{/} feels slow.
    -- mode = 'cursor',

    -- Animation duration cap (ms); lower (~250-500) for snappier long
    -- jumps. `line = <n>` skips animation entirely past n lines.
    -- max_delta = { time = 1000, line = false },
  },
})

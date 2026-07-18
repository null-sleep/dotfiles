vim.cmd.packadd('toggleterm.nvim')

local utils = require('utils')

require('toggleterm').setup({
  direction = 'horizontal',
  float_opts = {
    border = 'curved',
    -- Functions, not fixed numbers, so the float tracks window resizing. Only
    -- the go-run/clippy-fix floats use these (gotargets.lua, rust.lua); the
    -- bottom terminals are always horizontal.
    width = function()
      return math.floor(vim.o.columns * 0.85)
    end,
    height = function()
      return math.floor(vim.o.lines * 0.85)
    end,
  },
  shade_terminals = false, -- float border already provides visual separation
  start_in_insert = true,
  close_on_exit = true,
  -- Always reopen in terminal mode (with start_in_insert) rather than restoring
  -- the mode a terminal was hidden in, so toggling back never strands you in
  -- normal mode on old scrollback instead of a live prompt.
  persist_mode = false,
  size = function()
    return math.floor(vim.o.lines * 0.3)
  end,
})

-- The bottom terminal <C-/> targets: the last one opened, cycled, or focused.
-- Starts at 1 (the pre-warmed shell). A count on <C-/> overrides and re-pins it.
local last_term_id = 1

-- Close the current bottom terminal and open the next/previous one (wraps).
-- Filtered to ids < 100 so the cycle never sweeps in the go-run (id 101) or
-- clippy-fix (id 102) floats — those aren't hidden and belong to their own
-- toggles, not this rotation.
local function cycle_term(direction)
  local terminal = require('toggleterm.terminal')
  local terms = vim.tbl_filter(function(t) return t.id < 100 end, terminal.get_all())
  if #terms <= 1 then return end
  local current_id = vim.b.toggle_number
  local current_idx = 1
  for i, t in ipairs(terms) do
    if t.id == current_id then current_idx = i end
  end
  local next_idx = ((current_idx - 1 + direction) % #terms) + 1
  terms[current_idx]:close()
  terms[next_idx]:open()
  last_term_id = terms[next_idx].id
end

local function toggle_term()
  local id = vim.v.count > 0 and vim.v.count or last_term_id
  last_term_id = id
  vim.cmd(id .. 'ToggleTerm')
end
-- <C-/> and <C-_> are bound identically: Neovim receives <C-_> for this physical
-- chord in terminal mode, <C-/> from normal mode / the GUI.
for _, lhs in ipairs({ '<C-/>', '<C-_>' }) do
  vim.keymap.set({ 'n', 'i', 't' }, lhs, toggle_term,
    { desc = 'Terminal: toggle bottom (last-used, or #N with a count)' })
end

-- Re-pin last_term_id whenever a bottom terminal is (re-)focused directly (<C-w>
-- nav, mouse click), not just via toggle/cycle. Clamped to the 1-99 pool so
-- focusing a go-run/clippy-fix float (ids 101/102, also filetype toggleterm)
-- can't hijack the last-used target and make a bare <C-/> reopen a transient
-- float instead of your last shell.
vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter' }, {
  group = vim.api.nvim_create_augroup('UserTermFocus', { clear = true }),
  pattern = '*',
  desc = 'Terminal: track last-focused bottom terminal for <C-/>',
  callback = function()
    if vim.bo.filetype ~= 'toggleterm' then return end
    local n = vim.b.toggle_number
    if n and n < 100 then last_term_id = n end
  end,
})

-- Terminal-mode keymaps — only for toggleterm buffers (not sidekick CLI).
vim.api.nvim_create_autocmd('TermOpen', {
  group = vim.api.nvim_create_augroup('UserTermKeymaps', { clear = true }),
  desc = 'Terminal keymaps: Esc, split navigation, terminal cycling/switching',
  callback = function()
    -- Skip sidekick CLI buffers — sidekick manages its own keymaps.
    if vim.bo.filetype == 'sidekick_terminal' then return end
    local opts = { buffer = 0 }
    utils.term_nav_keymaps(0, { esc = true }) -- <Esc>/jj/jk exit, <C-h/j/k/l> nav

    -- <M-]>/<M-[>/<M-n>/<M-l> deliberately mirror the sidekick CLI's own
    -- session keys (ai.lua:313-336) for muscle-memory symmetry, though each
    -- is buffer-local to its own terminal kind so neither clashes.
    vim.keymap.set('t', '<M-]>', function() cycle_term(1) end, opts)
    vim.keymap.set('n', '<M-]>', function() cycle_term(1) end, opts)
    vim.keymap.set('t', '<M-[>', function() cycle_term(-1) end, opts)
    vim.keymap.set('n', '<M-[>', function() cycle_term(-1) end, opts)

    local function new_term()
      local used = {}
      for _, t in ipairs(require('toggleterm.terminal').get_all(true)) do used[t.id] = true end
      local n = 1
      -- Capped at 99: an exhausted 1-99 pool must not climb into the
      -- go-run/clippy floats' ids (101/102).
      while used[n] and n < 99 do n = n + 1 end
      last_term_id = n
      vim.cmd(n .. 'ToggleTerm')
    end
    vim.keymap.set('t', '<M-n>', new_term, opts)
    vim.keymap.set('n', '<M-n>', new_term, opts)

    vim.keymap.set('t', '<M-l>', '<cmd>TermSelect<CR>', opts)
    vim.keymap.set('n', '<M-l>', '<cmd>TermSelect<CR>', opts)

    -- Shift+Enter: send a linefeed so the running program inserts a newline.
    -- CLIs treat \r (<CR>) as "submit" and \n as "newline". Needs a terminal
    -- that transmits Shift+Enter distinctly (iTerm2 requires CSI u enabled).
    vim.keymap.set('t', '<S-CR>', function()
      vim.fn.chansend(vim.b.terminal_job_id, '\n')
    end, opts)
  end,
})

-- Pre-warm: spawn the shell into a hidden buffer so the first <C-/> opens an
-- already-running terminal instead of paying ~50-200ms of shell startup.
-- Terminal:spawn() runs termopen without opening a window (no flicker). Bare
-- :ToggleTerm toggles the lowest-id terminal, so id=1 is what <C-/> attaches to.
-- Fired at 2000ms, before ai.lua's claude pre-warm (3000ms), so the two spawns
-- don't collide on a <leader>qs restore. spawn() isn't idempotent — the get(1)
-- guard covers a <C-/> during the 2s wait (which pays one cold spawn).
vim.defer_fn(function()
  if not utils.has_ui() then return end -- headless: skip so spawned shells don't keep nvim alive
  if not require('toggleterm.terminal').get(1, true) then
    require('toggleterm.terminal').Terminal:new({ id = 1 }):spawn()
  end
end, 2000)

vim.cmd.packadd('toggleterm.nvim')

require('toggleterm').setup({
  -- <C-\> toggles the terminal from normal, insert, or terminal mode.
  -- Prefix with a count to open a specific terminal instance: 2<C-\>, 3<C-\>, etc.
  open_mapping = [[<c-\>]],
  direction = 'float',
  float_opts = {
    border = 'curved',
    -- Functions instead of fixed numbers so the float adapts to window resizing.
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
  -- persist_mode = true (default): remembers whether you were in insert or normal
  -- mode when you hid the terminal, and restores that mode on re-open.
  --
  -- persist_size = true (default): remembers split dimensions across hides.
  -- Only relevant if you use direction = 'horizontal' or 'vertical'.
  --
  -- autochdir = false (default): set to true to make the terminal cwd follow
  -- the current buffer's directory — useful for multi-project Neovim sessions.
  --
  -- size: ignored for float direction, but used by <leader>th and <leader>tv
  -- which override direction per-invocation. Function form lets us vary by direction.
  size = function(term)
    if term.direction == 'horizontal' then return math.floor(vim.o.lines * 0.3) end
    if term.direction == 'vertical'   then return math.floor(vim.o.columns * 0.4) end
  end,
})

-- Cycle through open toggleterm instances. Closes the current terminal and
-- opens the next/previous one (wraps around). Reads vim.b.toggle_number
-- (set by toggleterm on each terminal buffer) to find the current position
-- in the sorted terminal list.
local function cycle_term(direction)
  local terminal = require('toggleterm.terminal')
  local terms = terminal.get_all(true) -- sorted by id
  if #terms <= 1 then return end
  local current_id = vim.b.toggle_number
  local current_idx = 1
  for i, t in ipairs(terms) do
    if t.id == current_id then current_idx = i end
  end
  local next_idx = ((current_idx - 1 + direction) % #terms) + 1
  terms[current_idx]:close()
  terms[next_idx]:open()
end

-- Terminal-mode keymaps — only for toggleterm buffers (not sidekick CLI).
-- NOTE: <C-[> was previously used for cycle-previous, but <C-[> is the same
-- keycode as <Esc> — the binding shadowed Esc and caused cycling instead of
-- exiting terminal mode. Removed; use <C-]> for next and <S-C-]> or
-- <leader>tt + count for previous.
vim.api.nvim_create_autocmd('TermOpen', {
  desc = 'Terminal keymaps: Esc, split navigation, terminal cycling',
  callback = function()
    -- Skip sidekick CLI buffers — sidekick manages its own keymaps.
    if vim.bo.filetype == 'sidekick_terminal' then return end
    local opts = { buffer = 0 }
    vim.keymap.set('t', '<Esc>',  [[<C-\><C-n>]], opts)
    vim.keymap.set('t', 'jj',     [[<C-\><C-n>]], opts)
    vim.keymap.set('t', '<C-h>',  [[<Cmd>wincmd h<CR>]], opts)
    vim.keymap.set('t', '<C-j>',  [[<Cmd>wincmd j<CR>]], opts)
    vim.keymap.set('t', '<C-k>',  [[<Cmd>wincmd k<CR>]], opts)
    vim.keymap.set('t', '<C-l>',  [[<Cmd>wincmd l<CR>]], opts)
    vim.keymap.set('t', '<C-]>', function() cycle_term(1)  end, opts)
    vim.keymap.set('n', '<C-]>', function() cycle_term(1)  end, opts) -- overrides built-in tag jump; harmless here since this is buffer-local to toggleterm
    -- Prevent Shift+Enter from closing the terminal — send a plain newline instead.
    vim.keymap.set('t', '<S-CR>', '<CR>', opts)
  end,
})

vim.keymap.set('n', '<leader>tt', '<cmd>ToggleTerm<CR>', { desc = 'Toggle: Terminal (float)' })
vim.keymap.set('n', '<leader>th', '<cmd>ToggleTerm direction=horizontal<CR>', { desc = 'Toggle: Terminal (horizontal split)' })
vim.keymap.set('n', '<leader>tv', '<cmd>ToggleTerm direction=vertical<CR>',   { desc = 'Toggle: Terminal (vertical split)' })

-- Pre-warm: spawn the shell into a hidden buffer so the first <C-\> /
-- <leader>tt opens an already-running terminal instead of paying ~50–200ms
-- of shell startup. Toggleterm's Terminal:spawn() creates the buffer and
-- runs termopen without opening a window — no flicker, no monkey-patching
-- (unlike the sidekick pre-warm in ai.lua, where start() always opens a
-- visible window). :ToggleTerm with no args toggles the lowest-id terminal,
-- so spawning id=1 here is what <C-\> attaches to on first press.
vim.defer_fn(function()
  local Terminal = require('toggleterm.terminal').Terminal
  Terminal:new({ id = 1 }):spawn()
end, 100)

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
  -- size = 15 (not set): ignored for float direction. Set this if you switch to
  -- horizontal/vertical splits to control the split height/width.
})

-- Terminal-mode keymaps (buffer-local, set when any terminal opens).
-- NOTE: <Esc> exits terminal mode in all terminal buffers. If you add
-- lazygit or other TUI integrations, guard this with a filetype check:
--   if vim.bo[args.buf].filetype == 'toggleterm' then ... end
vim.api.nvim_create_autocmd('TermOpen', {
  desc = 'Terminal keymaps: Esc and split navigation',
  callback = function()
    local opts = { buffer = 0 }
    vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], opts)
    vim.keymap.set('t', '<C-h>', [[<Cmd>wincmd h<CR>]], opts)
    vim.keymap.set('t', '<C-j>', [[<Cmd>wincmd j<CR>]], opts)
    vim.keymap.set('t', '<C-k>', [[<Cmd>wincmd k<CR>]], opts)
    vim.keymap.set('t', '<C-l>', [[<Cmd>wincmd l<CR>]], opts)
  end,
})

vim.keymap.set('n', '<leader>tt', '<cmd>ToggleTerm<CR>', { desc = 'Toggle: Terminal' })

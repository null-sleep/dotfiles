vim.cmd.packadd('lualine.nvim')

-- Round powerline caps (Nerd Font) for the statusline's outer edges only —
-- see the mode/location components below. `left` bulges right (trailing
-- edge), `right` bulges left (leading edge).
local round_left = ''
local round_right = ''

require('lualine').setup({
  options = {
    -- 'auto' reads the active colorscheme's highlight groups — no manual
    -- theme changes needed when switching themes in themes.lua.
    theme = 'auto',

    -- Flat: no separators between sections/components.
    section_separators    = { left = '', right = '' },
    component_separators  = { left = '', right = '' },

    -- Single global statusline at the bottom (nvim 0.7+).
    -- Set to false for per-window statuslines.
    globalstatus = true,

    -- Filetypes where lualine is hidden entirely.
    disabled_filetypes = {
      statusline = { 'alpha', 'dashboard', 'starter' },
    },
  },

  sections = {
    lualine_a = {
      -- Rounds the statusline's outer-left edge.
      { 'mode', separator = { left = round_right } },
    },
    lualine_b = {
      {
        'filename',
        path = 1,  -- relative path
        fmt = function(name, ctx)
          -- Clean up raw terminal buffer names:
          --   toggleterm: "t//path/49473:/bin/zsh;#toggleterm#1" → "Terminal #1"
          --   sidekick:   "term://path//PID:/opt/homebrew/bin/claude:6" → "Claude CLI"
          if vim.bo.filetype == 'toggleterm' then
            local nr = vim.b.toggle_number or 1
            return 'Terminal #' .. nr
          end
          local bufname = vim.api.nvim_buf_get_name(0)
          -- [%w-] not %w: cursor-agent has a hyphen. Explicit display names,
          -- not a title-case rule — that would render "Cursor-agent CLI".
          local cli = bufname:match('/bin/([%w-]+)$') or bufname:match('/bin/([%w-]+):')
          local known_clis = { claude = 'Claude', copilot = 'Copilot',
                               gemini = 'Gemini', ['cursor-agent'] = 'Cursor',
                               opencode = 'Opencode', pi = 'Pi' }
          if cli and known_clis[cli] and bufname:match('^term://') then
            return known_clis[cli] .. ' CLI'
          end
          return name
        end,
      },
    },
    lualine_c = {
      -- Always show the git branch. This used to be Neovide-only: in a terminal
      -- the branch was left off because iTerm2's status bar already showed it,
      -- so lualine saved the real estate. Under Ghostty (no status bar) the
      -- terminal needs it here too, so the gate is gone.
      'branch',
      'diff',
      'diagnostics',
    },
    lualine_x = {
      'lsp_status',
    },
    lualine_y = { 'searchcount', 'progress' },
    lualine_z = {
      -- Rounds the statusline's outer-right edge.
      { 'location', separator = { right = round_left } },
    },
  },

  inactive_sections = {
    lualine_c = { { 'filename', path = 1 } },
    lualine_x = { 'location' },
  },

  -- Auto-hide statusline in these plugin windows and show a minimal one instead.
  extensions = { 'quickfix', 'mason' },
})

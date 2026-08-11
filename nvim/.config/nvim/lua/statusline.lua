vim.cmd.packadd('lualine.nvim')

-- Round powerline caps (Nerd Font) for the statusline's outer edges only —
-- see the mode/location components below. `left` bulges right (trailing
-- edge), `right` bulges left (leading edge).
local round_left = ''
local round_right = ''

-- Agent attention badge (agent_events registry): names the top unread session
-- — '! <label>' for the most recent urgent one (needs permission/input), else
-- '● <label>' for the most recent unread, ' +N' for the rest. Identity, not a
-- count: the question here is "is this worth interrupting for", and
-- <leader>aj routes regardless of what the badge says. Empty at zero and
-- inside the view tab (the sidebar says it better there). Returns text + the
-- Agentview* highlight group; purely reactive reads, no timers.
local BADGE_CELLS = 12  -- M.rename caps nothing; the statusline is finite

local function fit(s)
  if vim.fn.strdisplaywidth(s) <= BADGE_CELLS then return s end
  local n = vim.fn.strchars(s)
  while n > 1 do
    n = n - 1
    local cut = vim.fn.strcharpart(s, 0, n)
    if vim.fn.strdisplaywidth(cut) <= BADGE_CELLS - 1 then return cut .. '…' end
  end
  return '…'
end

local function agent_badge()
  local ev = package.loaded['agent_events']
  if not ev or vim.t.agentview then return '', nil end
  local unread = ev.unread_sessions()          -- most recent first
  if #unread == 0 then return '', nil end
  local top, group, glyph = unread[1], 'AgentviewUnread', '● '
  for _, name in ipairs(unread) do
    if ev.status(name) == 'urgent' then
      top, group, glyph = name, 'AgentviewUrgent', '! '
      break
    end
  end
  local ai = package.loaded['ai']
  local text = glyph .. fit(ai and ai.display(top) or top)
  if #unread > 1 then text = text .. ' +' .. (#unread - 1) end
  return text, group
end

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
      {
        function() return (agent_badge()) end,
        color = function()
          local _, group = agent_badge()
          if not group then return nil end
          -- lualine wants a color table; resolve the linked group's fg so
          -- the badge follows the active theme like everything else.
          local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
          return hl.fg and { fg = ('#%06x'):format(hl.fg) } or nil
        end,
      },
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

-- lualine repaints on its own cadence — refresh immediately on registry
-- transitions so the badge appears/clears the moment an agent rings.
vim.api.nvim_create_autocmd('User', {
  group = vim.api.nvim_create_augroup('UserStatuslineAgentBadge', { clear = true }),
  pattern = 'AgentSessionEvent',
  desc = 'Statusline: refresh agent unread badge',
  callback = function() require('lualine').refresh({ place = { 'statusline' } }) end,
})

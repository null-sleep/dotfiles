-- pcall: on first launch vim.pack is still downloading the plugin in the
-- background, so packadd/require will fail. Silently skip — next restart
-- picks it up once the clone finishes.
local ok = pcall(vim.cmd.packadd, 'sidekick.nvim')
if not ok then return end

-- Set by the pre-warm flow below; captured here so the cleanup step can
-- restore the instance's open_win without walking sidekick's session tables.
local prewarm_term ---@type any?

require('sidekick').setup({
  cli = {
    -- Use telescope for cli.select() (tool list) and cli.prompt() (prompt library)
    -- so the sidekick UI matches the rest of the config.
    picker = 'telescope',
    win = {
      layout = 'right',  -- CLI opens as a right split; switch to 'float' if preferred
      -- global scrolloff=10 pins terminal view to bottom; 0 lets it scroll freely
      wo = { scrolloff = 0 },
      -- Extra in-window keymaps. Sidekick owns the keymaps inside CLI buffers via
      -- this `keys` table (merged over its defaults: q / <C-q> / <C-.> already
      -- hide, <C-z> blurs, <C-b>/<C-f> pick buffers/files, etc.). Add bindings
      -- here rather than in a FileType autocmd so they live with the rest of the
      -- CLI config and use sidekick's own actions. <C-\> mirrors toggleterm's
      -- float toggle: from inside the open window "hide" tucks Claude away with
      -- its session intact (same as <leader>aa).
      keys = {
        toggle_bslash = { [[<c-\>]], 'hide', mode = 'nt', desc = 'hide Claude (toggleterm-style)' },
      },
      -- Pre-warm hook: while __sidekick_prewarm is set, swap this instance's
      -- open_win for one that creates a hidden float instead of a visible
      -- split. See the pre-warm block at the bottom of this file.
      config = function(term)
        if _G.__sidekick_prewarm then
          prewarm_term = term
          term.open_win = function(self)
            if self:is_open() or not self.buf then return end
            self.win = vim.api.nvim_open_win(self.buf, false, {
              relative = 'editor', row = 0, col = 0,
              width = 80, height = math.max(20, vim.o.lines),
              style = 'minimal', hide = true, focusable = false,
            })
            vim.w[self.win].sidekick_cli = self.tool
            vim.w[self.win].sidekick_session_id = self.id
            self:wo()
          end
        end
      end,
    },
    -- mux: leave disabled. Enable with backend = 'tmux' or 'zellij' if you want
    -- sessions to persist across nvim restarts.
  },
  nes = {
    -- defaults are good: enabled = true, debounce = 100, diff.inline = 'words'
  },
})

-- Add `jj` to exit terminal mode in sidekick CLI buffers. terminal.lua's
-- generic TermOpen autocmd skips sidekick_terminal so sidekick can own its
-- own keymaps; this restores just `jj` without touching <Esc> (which the
-- CLI needs to forward to Claude for interrupts).
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'sidekick_terminal',
  desc = 'Sidekick CLI: keymaps for terminal and normal mode',
  callback = function(args)
    vim.keymap.set('t', 'jj', [[<C-\><C-n>]], { buffer = args.buf })

    -- In normal mode, forward keys to Claude's job channel so its TUI scrolls.
    local function send_to_claude(seq)
      return function()
        local session_id = vim.w[vim.api.nvim_get_current_win()].sidekick_session_id
        local Terminal = require('sidekick.cli.terminal')
        local term = session_id and Terminal.get(session_id)
        if term and term.job then
          vim.api.nvim_chan_send(term.job, seq)
        end
      end
    end
    vim.keymap.set('n', '<C-u>', send_to_claude('\27[5~'), { buffer = args.buf })
    vim.keymap.set('n', '<C-d>', send_to_claude('\27[6~'), { buffer = args.buf })
  end,
})

-- Pre-warm strategy: the first <leader>aa freezes the editor for ~1–2s while
-- claude boots, so we pay that cost during nvim startup instead. Sidekick's
-- start() always opens a visible window, but `nvim_open_win` accepts
-- `hide = true` for floats (Neovim 0.10+) and `jobstart{ term = true }` only
-- needs the buffer to be shown in *some* current window — visibility doesn't
-- matter. So we use sidekick's per-instance `win.config` callback (above) to
-- swap in a hidden-float open_win, run cli.show, then close the hidden float
-- (cli.hide leaves the job alive) and restore the default — no flicker, no
-- cold-start freeze.
--
-- The global flag bridges cli.show's two `vim.schedule_wrap` hops so the
-- override is still in place when win.config eventually runs. If claude is
-- missing the pcall + nil guards make this a no-op rather than a wedged
-- editor. Gated on a `.git` ancestor (using vim.fs.root so it works for git
-- worktrees, where .git is a file rather than a directory) so we don't spawn
-- claude when nvim opens a single file outside a project.
if vim.fs.root(0, '.git') and #vim.api.nvim_list_uis() > 0 then -- skip claude pre-warm when headless: the spawned CLI job would keep nvim alive
  vim.defer_fn(function()
    local cli = require('sidekick.cli')
    _G.__sidekick_prewarm = true
    pcall(cli.show, { name = 'claude', focus = false })
    vim.defer_fn(function()
      _G.__sidekick_prewarm = nil
      if prewarm_term then
        prewarm_term.open_win = nil
        prewarm_term = nil
      end
      pcall(cli.hide, { name = 'claude' })
    end, 300)
  end, 100)
end

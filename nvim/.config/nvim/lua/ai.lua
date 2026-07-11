-- pcall: on first launch vim.pack is still downloading the plugin in the
-- background, so packadd/require will fail. Silently skip — next restart
-- picks it up once the clone finishes.
local ok = pcall(vim.cmd.packadd, 'sidekick.nvim')
if not ok then return end

local utils = require('utils')

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
      -- In-window CLI keymaps (merged over sidekick's defaults).
      -- <C-\> is intentionally NOT bound here so it falls through to the global
      -- toggleterm mapping, allowing toggleterm floats to be opened from sidekick.
      -- Use <leader>aa to hide sidekick.
      keys = {},
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

-- Promote the sidekick CLI to a full-height edge column on every show.
-- Without this, opening sidekick while the bottom panel (or any non-editor
-- window) has focus splits *that* window — the CLI ends up as a short column
-- inside the panel row instead of spanning the editor's full height. `wincmd
-- L` mirrors nvim-tree's reposition trick and lets Neovim reflow everything
-- else around the new column. SidekickCliAttach fires on every show path
-- (cli.show / cli.toggle / cli.focus), so this covers both user triggers and
-- internal re-shows (e.g. cli.send to a hidden CLI).
-- clear = true so a re-source doesn't register duplicate handlers (the
-- config's standard re-source guard, see configs.lua).
local augroup = vim.api.nvim_create_augroup('UserSidekick', { clear = true })

vim.api.nvim_create_autocmd('User', {
  group = augroup,
  pattern = 'SidekickCliAttach',
  desc = 'Sidekick CLI: promote to full-height edge column',
  callback = function(args)
    -- During pre-warm the CLI lives in a deliberately hidden float. Promoting
    -- it (wincmd L) converts that float into a *visible* split — which the
    -- pre-warm's Guard 2 then mistakes for a user-opened CLI and leaves on
    -- screen instead of hiding. The hidden float needs no promotion, so skip
    -- it while pre-warming.
    if _G.__sidekick_prewarm then return end
    local layout = require('sidekick.config').cli.win.layout
    local side = layout == 'right' and 'right' or layout == 'left' and 'left' or nil
    if not side then return end -- float / top / bottom layouts don't need promoting
    local term = require('sidekick.cli.terminal').get(args.data.id)
    if term then utils.promote_to_full_height(term.win, side) end
  end,
})

-- Terminal-nav keymaps for sidekick CLI buffers. terminal.lua's generic
-- TermOpen autocmd skips sidekick_terminal so sidekick can own its own
-- keymaps; this restores the shared nav set WITHOUT <Esc> (esc = false —
-- the CLI needs Esc forwarded to Claude for interrupts).
vim.api.nvim_create_autocmd('FileType', {
  group = augroup,
  pattern = 'sidekick_terminal',
  desc = 'Sidekick CLI: keymaps for terminal and normal mode',
  callback = function(args)
    utils.term_nav_keymaps(args.buf, { esc = false })

    -- <C-\> opens the toggleterm float from the sidekick CLI. Needed because
    -- toggleterm's terminal-mode toggle is buffer-local to its own terminals, so
    -- in this (sidekick) terminal there's otherwise no <C-\> mapping at all. The
    -- normal-mode global toggleterm mapping already handles <count><C-\>; from
    -- terminal mode a count isn't possible (digits go to Claude), so it opens the
    -- default float. v:count1 still lets a normal-mode count flow through here.
    vim.keymap.set({ 't', 'n' }, [[<C-\>]], function()
      vim.cmd(vim.v.count1 .. 'ToggleTerm')
    end, { buffer = args.buf, desc = 'Open toggleterm float' })

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
local PREWARM_DELAY = 3000 -- ms; see PersistenceLoadPre/Post below for why not a fixed defer_fn

-- Guard 1 + the show/hide dance, factored out so the timer and the
-- persistence reschedule below share it.
local function do_prewarm()
  -- Headless skip (the PersistenceLoadPost reschedule path isn't otherwise
  -- has_ui-gated, unlike the initial trigger below): don't spawn claude with
  -- no UI to warm for.
  if not utils.has_ui() then return end
  -- Project skip: only the initial trigger below is `.git`-gated, but the
  -- PersistenceLoadPost reschedule path lands here too -- re-check at fire time
  -- (evaluated against the restored buffers) so we don't spawn claude for a
  -- session/dir outside a project.
  if not vim.fs.root(0, '.git') then return end
  -- Guard 1: a *claude* CLI already exists (user opened it during the wait, or
  -- a restore surfaced one) -> don't double-spawn. Match the claude tool
  -- specifically via sidekick's live terminal registry, NOT the
  -- `sidekick_terminal` filetype -- other tools (codex/aider via <leader>as)
  -- share that filetype and must not suppress the claude pre-warm.
  for _, t in ipairs(require('sidekick.cli.terminal').sessions()) do
    if t.tool and t.tool.name == 'claude' and t:buf_valid() then
      return
    end
  end
  local cli = require('sidekick.cli')
  _G.__sidekick_prewarm = true
  pcall(cli.show, { name = 'claude', focus = false })
  vim.defer_fn(function()
    _G.__sidekick_prewarm = nil
    if prewarm_term then
      prewarm_term.open_win = nil
      prewarm_term = nil
    end
    -- Guard 2: if a *visible* claude CLI appeared during the show->hide window
    -- (user hit <leader>aa), skip the hide so we don't yank it away. Match the
    -- claude tool specifically (registry, not filetype) so a visible *other*
    -- tool doesn't suppress our hide. Our own pre-warm float stays hidden
    -- (hide=true; promotion is skipped while pre-warming), so it's excluded.
    for _, t in ipairs(require('sidekick.cli.terminal').sessions()) do
      if t.tool and t.tool.name == 'claude' and t:win_valid()
         and not vim.api.nvim_win_get_config(t.win).hide then
        return
      end
    end
    pcall(cli.hide, { name = 'claude' })
  end, 300)
end

-- Re-schedulable one-shot timer so PersistenceLoadPre/Post (below) can push
-- the spawn past a <leader>qs restore. Follows configs.lua's `_G`
-- stop-before-create re-source guard, and additionally closes its own handle
-- once it fires (repeat = 0, one-shot) so it doesn't leak until the next
-- re-source.
local function schedule_prewarm()
  if _G._sidekick_prewarm_timer then
    _G._sidekick_prewarm_timer:stop()
    _G._sidekick_prewarm_timer:close()
  end
  _G._sidekick_prewarm_timer = assert(vim.uv.new_timer())
  _G._sidekick_prewarm_timer:start(PREWARM_DELAY, 0, vim.schedule_wrap(function()
    if _G._sidekick_prewarm_timer then
      _G._sidekick_prewarm_timer:close()
      _G._sidekick_prewarm_timer = nil
    end
    do_prewarm()
  end))
end

-- persistence.nvim fires these around <leader>qs restore (verified in
-- persistence.nvim source: LoadPre/:source session/LoadPost). Pre: stop the
-- timer so claude doesn't spawn mid-restore, competing with rust-analyzer/
-- LSP/treesitter for the main thread. Post: reschedule so it fires
-- PREWARM_DELAY *after* restore completes instead of racing it.
vim.api.nvim_create_autocmd('User', {
  group = augroup,
  pattern = 'PersistenceLoadPre',
  desc = 'Sidekick pre-warm: pause claude spawn during session restore',
  callback = function()
    if _G._sidekick_prewarm_timer then
      _G._sidekick_prewarm_timer:stop()
      _G._sidekick_prewarm_timer:close()
      _G._sidekick_prewarm_timer = nil
    end
  end,
})
vim.api.nvim_create_autocmd('User', {
  group = augroup,
  pattern = 'PersistenceLoadPost',
  desc = 'Sidekick pre-warm: reschedule claude spawn after restore completes',
  callback = schedule_prewarm,
})

if vim.fs.root(0, '.git') and utils.has_ui() then -- skip pre-warm when headless (see above)
  schedule_prewarm()
end

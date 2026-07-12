-- snacks.nvim setup: the picker module (fuzzy finder), plus the scratch and
-- indent modules whose options used to live in scratch.lua. There must be
-- exactly one require('snacks').setup() call, so this file owns it;
-- scratch.lua keeps only the scratch keymaps.
--
-- Picker migration background: plans/telescope-vs-snacks-picker.md (repo
-- root). During the migration telescope and snacks coexist; telescope is
-- removed in the final step.
vim.cmd.packadd('snacks.nvim')

-- After selecting a result, scroll so the cursor lands ~20% from the top.
-- CURSOR_TOP_RATIO: 0.0 = top of window, 0.5 = center (zz), 1.0 = bottom
local CURSOR_TOP_RATIO = 0.20

-- Global <CR> confirm: snacks' default jump + the scroll adjustment above.
-- Two snacks-internals constraints shape this (see snacks picker actions.lua):
--  * <C-s>/<C-v> splits are implemented *through* confirm ({ action =
--    'confirm', cmd = 'split' }) — `action` must be forwarded to jump() or
--    every split key silently degrades to an in-place edit. Side effect:
--    splits get the same 20%-scroll, which telescope's <CR>-only version
--    didn't do.
--  * jump() is async while the input is in insert mode (stopinsert +
--    vim.schedule + early return, then a final `norm! zzzv` that re-centers),
--    so a naive "jump then scroll" scrolls before the file is open and then
--    gets clobbered. Mirror the same stopinsert-and-reschedule dance here so
--    jump() runs synchronously (in normal mode) before the winrestview.
local function confirm_and_scroll(picker, item, action)
  if vim.fn.mode():sub(1, 1) == 'i' then
    vim.cmd.stopinsert()
    vim.schedule(function() confirm_and_scroll(picker, item, action) end)
    return
  end
  require('snacks.picker.actions').jump(picker, item, action)
  local offset = math.floor(vim.api.nvim_win_get_height(0) * CURSOR_TOP_RATIO)
  vim.fn.winrestview({ topline = math.max(1, vim.fn.line('.') - offset) })
end

-- Send the picker's current item (or multi-selection) to the active sidekick
-- CLI session as space-separated path:line refs (the sidekick README's <a-a>
-- integration, bound to <M-a> here to match the rest of this config).
-- util.path() returns nil for non-file items (help tags, keymaps, ...), so
-- those are skipped and the action no-ops gracefully on them.
local function send_to_sidekick(picker)
  local items = picker:selected({ fallback = true })
  local refs = {}
  for _, item in ipairs(items) do
    local path = Snacks.picker.util.path(item)
    if path then
      refs[#refs + 1] = item.pos and (path .. ':' .. item.pos[1]) or path
    end
  end
  picker:close()
  if #refs > 0 then
    require('ai').send({ msg = table.concat(refs, ' ') })
  end
end

require('snacks').setup({
  picker = {
    -- telescope-ui-select still owns vim.ui.select while the two pickers
    -- coexist; flipped to true when telescope is removed.
    ui_select = false,
    layout = {
      -- Flex parity with the old telescope config: preview on the right when
      -- wide, below when narrow, flipping at 160 columns.
      preset = function()
        return vim.o.columns >= 160 and 'default' or 'vertical'
      end,
    },
    matcher = {
      -- Boost results by recency+frequency of use (files/recent/buffers/...).
      -- Persisted store is created on first use under stdpath('data');
      -- sqlite via the system libsqlite3, with a plain-file fallback.
      frecency = true,
    },
    actions = {
      confirm = confirm_and_scroll,
      send_to_sidekick = send_to_sidekick,
    },
    win = {
      input = {
        keys = {
          -- One-press close from insert mode (telescope muscle memory).
          -- 'cancel', not 'close': cancel re-pins focus to the window the
          -- picker was launched from before closing.
          ['<Esc>'] = { 'cancel', mode = { 'n', 'i' } },
          ['<M-a>'] = { 'send_to_sidekick', mode = { 'i', 'n' } },
          -- <C-h> aliases the default `?` help popup (shows this picker's
          -- live keymaps); shadows the global "move to left split" <C-h>
          -- only while the picker input is focused.
          ['<C-h>'] = { 'toggle_help_input', mode = { 'i', 'n' } },
        },
      },
      list = {
        keys = {
          ['<M-a>'] = 'send_to_sidekick',
        },
      },
    },
    sources = {
      -- Include hidden files/dirs (e.g. .github/) in results. .git/ is
      -- excluded by the finders' defaults; node_modules needs the explicit
      -- exclude (it's only skipped by default when gitignored).
      files = { hidden = true, exclude = { 'node_modules' } },
      grep = { hidden = true, exclude = { 'node_modules' } },
    },
  },
  scratch = {
    win = {
      width = 100,
      height = 30,
      border = 'rounded',  -- match toggleterm's curved float style (nvim_open_win vocabulary differs)
    },
  },
  -- Indent guides off by default; toggle on with <leader>tg. `enabled = false`
  -- survives snacks' auto-enable (setup only forces enabled=true when it's nil),
  -- so the module never activates on BufReadPost and Snacks.indent.enabled stays
  -- false until the first toggle. char/scope/animate are still registered here,
  -- so enable() picks them up when it fires.
  indent = {
    enabled  = false,
    indent   = { char = '▏' },
    scope    = { char = '▏' },
    animate  = { enabled = false },
  },
})

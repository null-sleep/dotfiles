-- pickers/aibuffers.lua — multi-select picker: which open buffers to send to
-- the AI CLI as `@relpath` mentions.
--
-- USAGE
--   require('pickers.aibuffers').open()        (bound to <leader>ab)
--   <Tab> toggle a row, <c-a> select/deselect all (snacks defaults), <CR> send
--
-- WHY
--   The old <leader>ab sent sidekick's `{buffers}` template var, which lists
--   EVERY open buffer wholesale — no way to exclude a scratch/unrelated file
--   from the send. This picker lets you choose which buffers go, using
--   ai_context.lua's `M.ref` for the same `@relpath` mention shape the other
--   send bindings use (file-only: no line numbers).
--
--   All rows start preselected, so bare <CR> (nothing toggled) reproduces the
--   old "send everything" behavior — <Tab>/<c-a> narrow it down from there.
--   Preselecting requires `picker:find({ on_done = ... })`: on_done fires
--   once the async matcher has actually populated the list (immediately if
--   it's already done), which matters because `list:select_all()` on an
--   empty/not-yet-populated list is a no-op. This is snacks' public hook —
--   do NOT reach into picker.matcher.task (private).
--
--   Deliberately no <M-N> quick-pick column and no <C-d> kill action, unlike
--   pickers/buffer.lua and pickers/gitstatus.lua: pickers/common.lua's
--   quick_pick_actions() does view(i) + confirm, and confirm here reads the
--   whole multi-selection — with every row preselected, <M-3> would send ALL
--   buffers, not just row 3. So this picker doesn't use
--   indexed_select/quick_pick_actions at all.

local ai_context = require('ai_context')

local M = {}

function M.open()
  local items = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if ai_context.is_file(b) then
      local name = vim.api.nvim_buf_get_name(b)
      items[#items + 1] = { buf = b, file = name, text = name }
    end
  end

  if #items == 0 then
    vim.notify('No file buffers to send', vim.log.levels.INFO)
    return
  end

  local picker = Snacks.picker.pick({
    source = 'ai_buffers',
    title = 'Send buffers to AI (<Tab> toggle, <C-a> all)',
    finder = function() return items end,
    format = 'filename',
    layout = { preset = 'select' },
    confirm = function(picker)
      local sel = picker:selected({ fallback = true })
      picker:close()
      local refs = {}
      for _, item in ipairs(sel) do
        refs[#refs + 1] = ai_context.ref(item.file, vim.fn.getcwd())
      end
      if #refs > 0 then
        require('ai').send({ msg = table.concat(refs, ' ') })
      end
    end,
  })

  -- Preselect every row once the finder's async matcher has actually
  -- populated the list — see header comment.
  picker:find({ on_done = function()
    if not picker.closed then picker.list:select_all() end
  end })
end

return M

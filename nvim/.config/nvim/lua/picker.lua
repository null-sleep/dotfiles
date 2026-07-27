-- snacks.nvim setup: the picker module (fuzzy finder) plus the scratch and
-- indent module options. There must be exactly one require('snacks').setup()
-- call, so this file owns it; scratch.lua keeps only the scratch keymaps.
-- Picker background and decision record: plans/telescope-vs-snacks-picker.md.
vim.cmd.packadd('snacks.nvim')

-- Global picker layout: preview right when wide, below when narrow; flips at
-- 160 columns, per picker open. Deliberately a *function*: snacks replaces
-- (rather than deep-merges) function layouts, so pickers that pin their own
-- layout (select popups, symbols) can't inherit stray keys from here.
local function pick_layout()
  return {
    preset = vim.o.columns >= 160 and 'default' or 'vertical',
    -- 0.9 over the presets' 0.8, matching the old telescope look. Every scroll
    -- tick past the list edge re-renders all visible rows *and* forces a
    -- full-window redraw flush, so per-tick cost is linear in height — but the
    -- Lua half of that is only ~0.9ms/tick here (measured), so it isn't why
    -- scrolling feels sluggish, and 0.8 didn't help when tried. Suspect is the
    -- forced flush; see plans/telescope-vs-snacks-picker.md §7.
    layout = { height = 0.9 },
  }
end

-- After selecting a result, scroll so the cursor lands ~20% from the top.
-- CURSOR_TOP_RATIO: 0.0 = top of window, 0.5 = center (zz), 1.0 = bottom
local CURSOR_TOP_RATIO = 0.20

-- Global <CR> confirm: snacks' default jump + the scroll adjustment above.
-- Two snacks-internals constraints (see snacks picker actions.lua):
--  * <C-s>/<C-v> splits run *through* confirm ({ action = 'confirm', cmd =
--    'split' }) — `action` must be forwarded to jump() or every split key
--    silently degrades to an in-place edit.
--  * jump() is async while the input is in insert mode (stopinsert +
--    vim.schedule + early return, ending in `norm! zzzv`), so a naive "jump
--    then scroll" runs before the file is open and then gets clobbered.
--    Mirror the same stopinsert-and-reschedule dance so jump() runs
--    synchronously before the winrestview.
local function confirm_and_scroll(picker, item, action)
  if vim.fn.mode():sub(1, 1) == 'i' then
    vim.cmd.stopinsert()
    vim.schedule(function() confirm_and_scroll(picker, item, action) end)
    return
  end
  -- pcall: a stale item position (e.g. a mark past EOF of a shrunk file)
  -- makes jump's nvim_win_set_cursor throw — degrade to a warning instead
  -- of a stack trace. The buffer is usually open at that point, just not
  -- at the intended line.
  local ok, err = pcall(require('snacks.picker.actions').jump, picker, item, action)
  if not ok then
    vim.notify('picker jump: ' .. tostring(err), vim.log.levels.WARN)
    return
  end
  local offset = math.floor(vim.api.nvim_win_get_height(0) * CURSOR_TOP_RATIO)
  vim.fn.winrestview({ topline = math.max(1, vim.fn.line('.') - offset) })
end

-- Line number for a positioned row, nil otherwise. pos can carry lnum 0 (e.g.
-- file-only quickfix entries) — treat that as unpositioned, like upstream's
-- `item.pos[1] > 0` guard, so yanks/sends don't emit a bogus `:0`.
local function item_lnum(item)
  local lnum = item and item.pos and item.pos[1]
  return lnum and lnum > 0 and lnum or nil
end

-- Send the picker's current item (or multi-selection) to the active sidekick
-- CLI as space-separated `@path`/`@path#L<n>` mentions (ai_context.lua — the
-- same shape as the <leader>a* sends). Bound to <C-CR>: Ctrl+Enter = send,
-- joining the picker's Enter family (<CR> open, <S-CR> pick-window).
-- util.path() returns nil for non-file items (help tags, keymaps, ...), so
-- those are skipped and the action no-ops gracefully on them.
local function send_to_sidekick(picker)
  local items = picker:selected({ fallback = true })
  local refs = {}
  for _, item in ipairs(items) do
    local path = Snacks.picker.util.path(item)
    if path then
      -- nil lnum (e.g. plain file items) → ref() emits a bare `@path`.
      refs[#refs + 1] = require('ai_context').ref(path, picker:cwd(), item_lnum(item))
    end
  end
  picker:close()
  if #refs > 0 then
    require('ai').send({ msg = table.concat(refs, ' ') })
  end
end

-- Yank the item's path to the '+' register (clipboard is unset in configs.lua,
-- so the unnamed register snacks' stock yank uses wouldn't reach the system
-- clipboard). copy_path is cwd-relative, copy_path_full absolute; both append
-- `:<line>` on positioned rows (grep/LSP/symbols). util.path() normalizes the
-- source's mixed relative/absolute output; ':p' / relpath then force the form.
local function yank_path(picker, item, full)
  local path = Snacks.picker.util.path(item)
  if not path and item and item.buf then
    path = vim.api.nvim_buf_get_name(item.buf)
  end
  if not path or path == '' then
    vim.notify('No path for this item', vim.log.levels.WARN)
    return
  end
  local abs = vim.fn.fnamemodify(path, ':p')
  local out = full and abs or (vim.fs.relpath(picker:cwd(), abs) or abs)
  local lnum = item_lnum(item)
  if lnum then out = out .. ':' .. lnum end
  picker:close()
  vim.fn.setreg('+', out)
  vim.notify('Copied: ' .. out)
end
local function copy_path(picker, item) yank_path(picker, item, false) end
local function copy_path_full(picker, item) yank_path(picker, item, true) end

-- Copy the item's GitHub permalink (HEAD-pinned, #L<line> on positioned rows) —
-- the picker twin of the `yu` buffer yank, reusing yank.lua's URL builder.
local function copy_github_url(picker, item)
  local path = Snacks.picker.util.path(item)
  if not path and item and item.buf then
    path = vim.api.nvim_buf_get_name(item.buf)
  end
  if not path or path == '' then
    vim.notify('No path for this item', vim.log.levels.WARN)
    return
  end
  local url, err = require('yank').github_url_for(vim.fn.fnamemodify(path, ':p'),
    item_lnum(item))
  if not url then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end
  picker:close()
  vim.fn.setreg('+', url)
  vim.notify('Copied: ' .. url)
end

require('snacks').setup({
  picker = {
    -- snacks owns vim.ui.select (consumers: nvim-tree confirmations,
    -- rustaceanvim runnables, sidekick's prompt library).
    ui_select = true,
    layout = pick_layout,
    -- Left-truncate long paths so the identifying tail survives
    -- (`…/orderbuilderutil/order.go` vs stock center `packages/…/order.go`).
    -- Stock snacks expands the path to the full list width, so on a wide
    -- pane almost nothing truncates — the format.filename wrap after setup
    -- caps display width (PATH_MAX / PATH_MAX_BY_SOURCE). Full path for the
    -- selected row lives in the preview border. GUIDE.md "Path display".
    formatters = {
      file = { truncate = 'left' },
    },
    -- Live mode is easy to lose track of, and it silently changes what the
    -- prompt *means* (the tool's regex vs the fuzzy matcher — see GUIDE.md
    -- "Whose grammar is it?"). Stock snacks signals it with a bare 󰐰 in the
    -- title, which reads as decoration; spell it out instead. The title
    -- re-renders on every <c-g> (toggle_live -> input:set -> update_titles),
    -- and the icon is empty in fuzzy mode, so presence/absence is the signal.
    icons = { ui = { live = '󰐰 LIVE ' } },
    matcher = {
      -- Boost results by recency+frequency of use (files/recent/buffers/...).
      -- Persisted store is created on first use under stdpath('data');
      -- sqlite via the system libsqlite3, with a plain-file fallback.
      frecency = true,
    },
    -- Surface the frecency-adjusted score as a prefix column in every
    -- picker's list (list.lua only reads this when scores is truthy, so it's
    -- free otherwise) — makes the ranking above legible/tunable instead of
    -- a black box. Off by default (didn't like the look of the column); flip
    -- to true to debug frecency ranking again.
    debug = {
      scores = false,
    },
    actions = {
      confirm = confirm_and_scroll,
      send_to_sidekick = send_to_sidekick,
      copy_path = copy_path,
      copy_path_full = copy_path_full,
      copy_github_url = copy_github_url,
    },
    win = {
      input = {
        keys = {
          -- One-press close from insert mode. 'cancel', not 'close': cancel
          -- re-pins focus to the launch window before closing.
          ['<Esc>'] = { 'cancel', mode = { 'n', 'i' } },
          ['<C-CR>'] = { 'send_to_sidekick', mode = { 'i', 'n' } },
          -- <C-h> aliases the default `?` help popup (shows this picker's
          -- live keymaps); shadows the global "move to left split" <C-h>
          -- only while the picker input is focused.
          ['<C-h>'] = { 'toggle_help_input', mode = { 'i', 'n' } },
          -- Shadows the global <C-y> (scroll up one line) only while the
          -- picker input is focused — same trade as <C-h> above.
          ['<C-y>'] = { 'copy_path', mode = { 'i', 'n' } },
          -- <C-S-Y> yanks the absolute path (same shadow trade). The undo
          -- source reclaims it for yank_removed per-source (GUIDE "Undo history").
          ['<C-S-Y>'] = { 'copy_path_full', mode = { 'i', 'n' } },
          -- Send results to the location list (snacks built-in loclist), the
          -- window-local twin of the default <C-q> qflist. Shadows the global
          -- <C-l> move-to-right-split while the input is focused (as <C-h> does).
          ['<C-l>'] = { 'loclist', mode = { 'i', 'n' } },
          -- <C-S-U> yanks the item's GitHub permalink (u = url) — the picker twin
          -- of the `yu` buffer yank, in the <C-y>/<C-S-Y> Ctrl-yank family.
          ['<C-S-U>'] = { 'copy_github_url', mode = { 'i', 'n' } },
        },
      },
      list = {
        keys = {
          ['<C-CR>'] = 'send_to_sidekick',
          ['<C-y>'] = 'copy_path',
          ['<C-S-Y>'] = 'copy_path_full',
          ['<C-l>'] = 'loclist',
          ['<C-S-U>'] = 'copy_github_url',
        },
      },
    },
    sources = {
      -- Undo history (<leader>uu). Stock format lays the tree gutter out
      -- left-aligned and then pads the seq column by `8 - gutter_width -
      -- #seq`, which goes NEGATIVE once a branch nests deep enough — align()
      -- returns the text unpadded in that case, so a nested row's whole line
      -- shifts right and stops lining up with its siblings.
      --
      -- Same columns, but the gutter gets a fixed-width right-aligned field:
      -- glyphs still grow leftward with depth (so nesting reads), while every
      -- seq/time/count lands on the same column regardless of depth.
      undo = {
        -- Stock preview is the "fancy" diff renderer, which spends the first
        -- ~6 lines on a boxed filename plus a boxed file-type icon before any
        -- content. Both are dead weight here: an undo picker only ever diffs
        -- the current buffer, so the filename is a constant. The trade is
        -- losing the dual line-number columns and in-hunk syntax
        -- highlighting — diff colors only. (There's no way to keep fancy and
        -- drop just the header: its parser needs the `diff --git`/`---`/`+++`
        -- lines to find the block, and removing them mangles the layout.)
        previewers = { diff = { style = 'syntax' } },
        preview = function(ctx)
          if ctx.item.resolve then ctx.item:resolve() end
          -- Drop the git header the finder templates on — with `syntax` it
          -- would render as three literal lines of noise naming a file you
          -- already know.
          if ctx.item.diff then
            ctx.item.diff = ctx.item.diff:gsub('^diff %-%-git[^\n]*\n%-%-%-[^\n]*\n%+%+%+[^\n]*\n', '', 1)
          end
          local ret = Snacks.picker.preview.diff(ctx)
          -- The filename moves to the preview window's border instead: one
          -- line of chrome rather than six, and it survives the header strip
          -- above. Set AFTER the previewer runs — preview:reset() clears the
          -- title on every item change.
          if ctx.item.file then
            -- ':.' is cwd-relative and leaves a file outside the project as a
            -- full absolute path, which would overflow the border — fall back
            -- to '~' for those.
            local name = vim.fn.fnamemodify(ctx.item.file, ':.')
            if name:sub(1, 1) == '/' then
              name = vim.fn.fnamemodify(ctx.item.file, ':~')
            end
            ctx.preview:set_title(name)
          end
          return ret
        end,
        format = function(item, picker)
          local a = Snacks.picker.util.align
          local entry = item.item
          local GUTTER_W, SEQ_W = 6, 3
          local ret = {}
          ret[#ret + 1] = { a('', 2), item.current and 'SnacksPickerUndoCurrent' or nil }

          local gutter = ''
          for _, chunk in ipairs(Snacks.picker.format.tree(item, picker)) do
            gutter = gutter .. chunk[1]
          end
          local gw = vim.api.nvim_strwidth(gutter)
          if gw > GUTTER_W then
            -- Deeper than the column: keep the innermost glyphs, drop the
            -- outer verticals — the near-siblings are what you're reading.
            gutter, gw = vim.fn.strcharpart(gutter, gw - GUTTER_W), GUTTER_W
          end
          ret[#ret + 1] = { (' '):rep(GUTTER_W - gw) .. gutter, 'SnacksPickerTree' }

          ret[#ret + 1] = { ' ' }
          ret[#ret + 1] = { a(tostring(entry.seq), SEQ_W, { align = 'right' }), 'SnacksPickerIdx' }
          ret[#ret + 1] = { '  ' }
          ret[#ret + 1] = { a(Snacks.picker.util.reltime(entry.time), 15), 'SnacksPickerTime' }
          ret[#ret + 1] = { ' ' }
          local function num(v, prefix)
            v = v or 0
            return a(v > 0 and prefix .. v or '', 4)
          end
          ret[#ret + 1] = { num(item.added, '+'), 'SnacksPickerUndoAdded' }
          ret[#ret + 1] = { ' ' }
          ret[#ret + 1] = { num(item.removed, '-'), 'SnacksPickerUndoRemoved' }
          if entry.save then
            ret[#ret + 1] = { ' ' }
            ret[#ret + 1] = { a(picker.opts.icons.undo.saved, 2), 'SnacksPickerUndoSaved' }
          end
          return ret
        end,
      },
      -- Include hidden files/dirs (e.g. .github/) in results. .git/ is
      -- excluded by the finders' defaults; node_modules needs the explicit
      -- exclude (it's only skipped by default when gitignored).
      --
      -- The `live` toggle is a *chip that shows when live is off* — snacks'
      -- toggle loop renders a flag when `opts[name] == value`, so `value =
      -- false` inverts it. It advertises "this picker can go live, <c-g>"
      -- exactly where that's true and currently isn't, and vanishes when the
      -- 󰐰 LIVE title marker takes over. Per-source, not global: every
      -- fixed-list picker also has `live = false`, and a chip there would
      -- promise a <c-g> that only warns. GUIDE.md → "Whose grammar is it?"
      files = {
        hidden = true,
        exclude = { 'node_modules' },
        -- `live = false` is load-bearing, not documentation: the files source
        -- leaves it *unset*, and the toggle loop compares `opts.live == false`
        -- — nil ~= false, so the chip would never render without this.
        live = false,
        toggles = { live = { icon = '󰐰 <c-g>', value = false } },
      },
      grep = {
        hidden = true,
        exclude = { 'node_modules' },
        toggles = { live = { icon = '󰐰 <c-g>', value = false } },
      },
      -- lines (<leader>sb, <leader>s/): the source's own layout (bottom ivy
      -- strip previewing in the main window) beats the global one; the same
      -- function replaces it wholesale, `preview = "main"` included.
      lines = {
        layout = pick_layout,
        -- Match grep's empty state: nothing until a query is typed (an
        -- empty fuzzy pattern matches every line — the document you're
        -- already in, twice). The finder produces the emptiness; the
        -- transform re-runs it when the prompt flips empty <-> non-empty
        -- (transform fires on every input change, true = re-run finder).
        show_empty = true,  -- don't auto-close on opening with 0 items
        -- Line numbers get grep's file-name group instead of LineNr, which
        -- fades into the background. ret[1] is the number column.
        format = function(item, picker)
          local ret = Snacks.picker.format.lines(item, picker)
          ret[1][2] = 'SnacksPickerFile'
          return ret
        end,
        finder = function(opts, ctx)
          if ctx.filter.pattern == '' then return {} end
          return require('snacks.picker.source.lines').lines(opts, ctx)
        end,
        filter = {
          transform = function(picker, filter)
            local prev = picker.finder.filter
            return (not prev or prev.pattern == '') ~= (filter.pattern == '')
          end,
        },
      },
    },
  },
  scratch = {
    win = {
      width = 100,
      height = 30,
      border = 'rounded',  -- match toggleterm's curved float style (nvim_open_win vocabulary differs)
    },
  },
  -- Large-file protection. Defaults: >1.5MB, or an *average* line length >1000
  -- (the minified case — a 1-line 2MB .js trips this despite being one line).
  -- The mechanism is a filetype *rename* to 'bigfile', not a feature switch:
  -- everything ft-keyed (LSP, treesitter, nvim-lint, conform, aerial,
  -- render-markdown) then simply never matches. Subsystems that are NOT
  -- ft-keyed — gitsigns, satellite, auto-save — still run; see
  -- GUIDE.md "Big files get a filetype rename, not a per-feature guard" and
  -- plans/large-file-protection.md for what that leaves open.
  bigfile = { enabled = true },
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

-- Cap stock file-path display width. Snacks' filename formatter expands to
-- the list pane's full width (math.max(available, min_width)), so left-
-- truncate alone barely fires on a wide picker — monorepo paths fill the
-- row. Clamp the resolve()'d max_width so deep paths still truncate.
-- Files (`<leader>sf`) gets a wider cap: its rows are path-only, so a tight
-- global cap leaves half the list empty; grep/LSP keep the tighter default
-- to leave room for the snippet. Preview border still shows the full path
-- (wrap below). GUIDE.md "Path display".
local PATH_MAX = 40
local PATH_MAX_BY_SOURCE = { files = 60 }
do
  local filename = Snacks.picker.format.filename
  Snacks.picker.format.filename = function(item, picker)
    local ret = filename(item, picker)
    local cap = PATH_MAX_BY_SOURCE[picker.opts.source] or PATH_MAX
    for _, chunk in ipairs(ret) do
      if chunk.resolve then
        local orig = chunk.resolve
        chunk.resolve = function(max_width)
          return orig(math.min(max_width, cap))
        end
      end
    end
    return ret
  end
end

-- Stock file preview puts only the basename in the preview border. Wrap it so
-- the selected row shows the full cwd-relative path there (list rows stay
-- left-truncated — see formatters.file above). Wrap the module function rather
-- than a global `preview`/`on_change`: on_change runs *before* preview:show()
-- so a title set there gets overwritten, and a top-level preview fn would
-- fight sources that pin their own (diff, man, undo). GUIDE.md "Path display".
do
  local file_preview = Snacks.picker.preview.file
  Snacks.picker.preview.file = function(ctx)
    local ret = file_preview(ctx)
    -- An item-pinned title (stock: preview_title or title) outranks the path,
    -- same precedence the stock previewer gives it over the basename.
    if ctx.item.preview_title or ctx.item.title then
      return ret
    end
    local path = Snacks.picker.util.path(ctx.item)
    if path then
      -- ':.' / relpath is cwd-relative; files outside the project stay absolute
      -- and would overflow the border — fall back to '~' for those (same as
      -- the undo source's preview title).
      local name = vim.fs.relpath(ctx.picker:cwd(), path) or path
      if name:sub(1, 1) == '/' then
        name = vim.fn.fnamemodify(path, ':~')
      end
      ctx.preview:set_title(name)
    end
    return ret
  end
end

-- <leader>tp: start/stop the snacks instrumentation profiler; stopping opens a
-- picker over the trace. Lives here because it needs the `Snacks` global that
-- this file's setup() creates. Standing tool, but the reason it exists is the
-- picker scroll-perf hunt in plans/telescope-vs-snacks-picker.md §7 — run it
-- there with `Snacks.profiler.scratch()` to set `filter_fn = { default = true }`,
-- otherwise the default filter hides every `_`-prefixed function, which is most
-- of the list-render hot path. A profiled *run* leaves the wrapped modules in
-- place until restart, so quit nvim before timing anything for real.
-- Explicit desc: snacks would generate "Toggle Profiler", and the <leader>sk
-- picker derives a keymap's tag from the text before the first ':' — no colon,
-- no tag. Matches the 'Group: Action' format every other keymap here uses.
Snacks.toggle.profiler():map('<leader>tp', { desc = 'Toggle: Profiler' })

-- Sticky scope header ("context") — pins the header lines of the enclosing
-- scopes (function / class / if / loop signatures) to the top of the window as
-- you scroll into a block, so the context you're inside never scrolls off. Same
-- idea as VS Code's "sticky scroll". Driven by the core vim.treesitter API, so
-- it's independent of our `main`-branch nvim-treesitter (no reliance on the
-- removed module system).
vim.cmd.packadd('nvim-treesitter-context')

require('treesitter-context').setup({
  max_lines           = 3,        -- cap the sticky header at 3 lines; deeper nesting is trimmed
  multiline_threshold = 1,        -- collapse a multi-line signature down to a single header line
  mode                = 'cursor', -- track the scope the *cursor* is in, not the window topline
  trim_scope          = 'outer',  -- over max_lines, drop the outermost (least-relevant) contexts
  separator           = nil,      -- no drawn separator line; rely on the TreesitterContext hl group
})

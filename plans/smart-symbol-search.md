# Smart Symbol Search

## Problem
`<leader>ss` (workspace symbols) only works when the current buffer has an LSP
attached. Opening a non-code file (e.g. markdown, README) means you lose access
to project symbol search even though gopls or other LSPs are still running.

## Goal
Make `<leader>ss` work regardless of the current buffer by querying all active
LSP clients in the session — not just the one attached to the current buffer.

## Approach
Replace `builtin.lsp_dynamic_workspace_symbols` with a custom function that:
1. Checks if the current buffer has an LSP client with workspace symbol support — if so, use it (current behavior).
2. If not, find all running LSP clients in the session that support workspace symbols.
3. Query all of them and merge results into a single Telescope picker.

## Files to modify
- `lua/keymaps.lua` — replace the `<leader>ss` keymap with the custom function

## Open questions
- Should results from multiple LSPs be deduplicated or labeled by server name?
- Should there be a preference order (e.g. gopls first, then others)?

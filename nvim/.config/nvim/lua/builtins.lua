-- builtins.lua — Common built-in normal mode commands not covered by which-key presets.
--
-- Which-key presets (operators, motions, text objects, z/g/window/nav) cover
-- ~160 entries but miss fundamental editing commands. Neovim has no API to
-- enumerate built-in commands (they're hardcoded in C, not keymaps).
--
-- Descriptions sourced from :help normal-index ($VIMRUNTIME/doc/index.txt).
-- To verify or update: run `:help normal-index` and compare.
--
-- The `group` field mirrors which-key group labels and is included in the
-- search text so e.g. typing "scroll" finds all scrolling commands.

return {
  { lhs = 'u',      group = 'Undo/Redo',           desc = 'Undo changes' },
  { lhs = 'U',      group = 'Undo/Redo',           desc = 'Undo all latest changes on one line' },
  { lhs = '<C-r>',  group = 'Undo/Redo',           desc = 'Redo changes which were undone with u' },

  { lhs = 'p',      group = 'Put',                 desc = 'Put text after cursor' },
  { lhs = 'P',      group = 'Put',                 desc = 'Put text before cursor' },

  { lhs = 'x',      group = 'Delete/Substitute',   desc = 'Delete N characters under and after cursor' },
  { lhs = 'X',      group = 'Delete/Substitute',   desc = 'Delete N characters before cursor' },
  { lhs = 's',      group = 'Delete/Substitute',   desc = 'Substitute N characters and start insert' },
  { lhs = 'S',      group = 'Delete/Substitute',   desc = 'Substitute N lines and start insert (cc)' },

  { lhs = 'J',      group = 'Line operations',     desc = 'Join N lines' },
  { lhs = 'dd',     group = 'Line operations',     desc = 'Delete N lines' },
  { lhs = 'cc',     group = 'Line operations',     desc = 'Delete N lines and start insert' },
  { lhs = 'yy',     group = 'Line operations',     desc = 'Yank N lines' },
  { lhs = '>>',     group = 'Line operations',     desc = 'Shift N lines one shiftwidth right' },
  { lhs = '<<',     group = 'Line operations',     desc = 'Shift N lines one shiftwidth left' },
  { lhs = '==',     group = 'Line operations',     desc = 'Filter N lines through indent' },
  { lhs = '!!',     group = 'Line operations',     desc = 'Filter N lines through external command' },

  { lhs = 'i',      group = 'Insert',              desc = 'Insert text before cursor' },
  { lhs = 'I',      group = 'Insert',              desc = 'Insert text before first non-blank on line' },
  { lhs = 'a',      group = 'Insert',              desc = 'Append text after cursor' },
  { lhs = 'A',      group = 'Insert',              desc = 'Append text at end of line' },
  { lhs = 'o',      group = 'Insert',              desc = 'Open new line below and insert' },
  { lhs = 'O',      group = 'Insert',              desc = 'Open new line above and insert' },
  { lhs = 'R',      group = 'Insert',              desc = 'Enter replace mode' },

  { lhs = '.',      group = 'Repeat/Macro',        desc = 'Repeat last change' },
  { lhs = 'q',      group = 'Repeat/Macro',        desc = 'Record/stop recording into register' },
  { lhs = '@',      group = 'Repeat/Macro',        desc = 'Execute register contents' },
  { lhs = '@@',     group = 'Repeat/Macro',        desc = 'Repeat previous @{register}' },
  { lhs = 'Q',      group = 'Repeat/Macro',        desc = 'Replay last recorded register' },

  { lhs = 'n',      group = 'Search',              desc = 'Repeat last search forward' },
  { lhs = 'N',      group = 'Search',              desc = 'Repeat last search backward' },
  { lhs = '*',      group = 'Search',              desc = 'Search forward for word under cursor' },
  { lhs = '#',      group = 'Search',              desc = 'Search backward for word under cursor' },
  { lhs = '&',      group = 'Search',              desc = 'Repeat last :s substitution' },

  { lhs = 'm',      group = 'Marks',               desc = 'Set mark at cursor position' },

  { lhs = '<C-d>',  group = 'Scrolling',           desc = 'Scroll down N lines (default: half screen)' },
  { lhs = '<C-u>',  group = 'Scrolling',           desc = 'Scroll up N lines (default: half screen)' },
  { lhs = '<C-f>',  group = 'Scrolling',           desc = 'Scroll N screens forward' },
  { lhs = '<C-b>',  group = 'Scrolling',           desc = 'Scroll N screens backward' },
  { lhs = '<C-e>',  group = 'Scrolling',           desc = 'Scroll window N lines downward' },
  { lhs = '<C-y>',  group = 'Scrolling',           desc = 'Scroll window N lines upward' },

  { lhs = '<C-o>',  group = 'Jump list/Tags',      desc = 'Go to N older entry in jump list' },
  { lhs = '<C-i>',  group = 'Jump list/Tags',      desc = 'Go to N newer entry in jump list (same as Tab)' },
  { lhs = '<C-t>',  group = 'Jump list/Tags',      desc = 'Jump to N older tag in tag list' },
  { lhs = '<C-]>',  group = 'Jump list/Tags',      desc = 'Jump to tag under cursor' },

  { lhs = 'K',      group = 'Help',                desc = 'Look up keyword under cursor' },
  { lhs = 'D',      group = 'Operator shortcuts',  desc = 'Delete to end of line (synonym for d$)' },
  { lhs = 'C',      group = 'Operator shortcuts',  desc = 'Change to end of line (synonym for c$)' },
  { lhs = 'Y',      group = 'Operator shortcuts',  desc = 'Yank N lines (mapped to y$ by default)' },
  { lhs = '<C-a>',  group = 'Increment/Decrement', desc = 'Add N to number at/after cursor' },
  { lhs = '<C-x>',  group = 'Increment/Decrement', desc = 'Subtract N from number at/after cursor' },

  { lhs = '<C-g>',  group = 'Display',             desc = 'Display current file name and position' },
  { lhs = '<C-l>',  group = 'Display',             desc = 'Redraw screen' },

  { lhs = '<C-v>',  group = 'Visual',              desc = 'Start blockwise visual mode' },

  { lhs = '+',      group = 'Line navigation',     desc = 'Cursor to first non-blank N lines lower' },
  { lhs = '-',      group = 'Line navigation',     desc = 'Cursor to first non-blank N lines higher' },
  { lhs = '_',      group = 'Line navigation',     desc = 'Cursor to first non-blank N-1 lines lower' },
  { lhs = '|',      group = 'Line navigation',     desc = 'Cursor to column N' },

  { lhs = '(',      group = 'Sentence/Paragraph',  desc = 'Cursor N sentences backward' },
  { lhs = ')',      group = 'Sentence/Paragraph',  desc = 'Cursor N sentences forward' },

  { lhs = 'do',     group = 'Diff',                desc = 'Diff obtain (same as :diffget)' },
  { lhs = 'dp',     group = 'Diff',                desc = 'Diff put (same as :diffput)' },

  { lhs = ':',      group = 'Command-line',        desc = 'Start entering an Ex command' },
  { lhs = 'q:',     group = 'Command-line',        desc = 'Edit Ex command-line in command-line window' },
  { lhs = 'q/',     group = 'Command-line',        desc = 'Edit search forward in command-line window' },
  { lhs = 'q?',     group = 'Command-line',        desc = 'Edit search backward in command-line window' },
  { lhs = '@:',     group = 'Command-line',        desc = 'Repeat previous Ex command N times' },

  { lhs = '<C-^>',  group = 'Buffer',              desc = 'Edit alternate file' },
  { lhs = '<C-c>',  group = 'Process',             desc = 'Interrupt current command' },
  { lhs = '<C-z>',  group = 'Process',             desc = 'Suspend program' },

  { lhs = 'ZZ',     group = 'Save/Quit',           desc = 'Write if changed and close window' },
  { lhs = 'ZQ',     group = 'Save/Quit',           desc = 'Close window without writing' },

  { lhs = 'gJ',     group = 'Go to',               desc = 'Join lines without inserting space' },
  { lhs = 'gd',     group = 'Go to',               desc = 'Go to local definition of word under cursor' },
  { lhs = 'gD',     group = 'Go to',               desc = 'Go to global definition of word under cursor' },
  { lhs = 'ga',     group = 'Go to',               desc = 'Print ascii value of character under cursor' },
  { lhs = 'g&',     group = 'Go to',               desc = 'Repeat last :s on all lines' },
  { lhs = 'gq',     group = 'Go to',               desc = 'Format text with motion' },

  { lhs = 'gc',     group = 'Comment',             desc = 'Toggle comment with motion (e.g. gcip, gc3j)' },
  { lhs = 'gcc',    group = 'Comment',             desc = 'Toggle comment on current line' },

  { lhs = 'dw',     group = 'Delete combos',       desc = 'Delete to next word boundary' },
  { lhs = 'diw',    group = 'Delete combos',       desc = 'Delete inner word' },
  { lhs = 'daw',    group = 'Delete combos',       desc = 'Delete a word (including surrounding space)' },
  { lhs = 'di"',    group = 'Delete combos',       desc = 'Delete inside double quotes' },
  { lhs = "di'",    group = 'Delete combos',       desc = 'Delete inside single quotes' },
  { lhs = 'di(',    group = 'Delete combos',       desc = 'Delete inside parentheses' },
  { lhs = 'da(',    group = 'Delete combos',       desc = 'Delete around parentheses' },
  { lhs = 'di{',    group = 'Delete combos',       desc = 'Delete inside curly braces' },
  { lhs = 'dip',    group = 'Delete combos',       desc = 'Delete inner paragraph' },

  { lhs = 'cw',     group = 'Change combos',       desc = 'Change to next word boundary' },
  { lhs = 'ciw',    group = 'Change combos',       desc = 'Change inner word' },
  { lhs = 'caw',    group = 'Change combos',       desc = 'Change a word (including surrounding space)' },
  { lhs = 'ci"',    group = 'Change combos',       desc = 'Change inside double quotes' },
  { lhs = "ci'",    group = 'Change combos',       desc = 'Change inside single quotes' },
  { lhs = 'ci(',    group = 'Change combos',       desc = 'Change inside parentheses' },
  { lhs = 'ca(',    group = 'Change combos',       desc = 'Change around parentheses' },
  { lhs = 'ci{',    group = 'Change combos',       desc = 'Change inside curly braces' },
  { lhs = 'cip',    group = 'Change combos',       desc = 'Change inner paragraph' },

  { lhs = 'yw',     group = 'Yank combos',         desc = 'Yank to next word boundary' },
  { lhs = 'yiw',    group = 'Yank combos',         desc = 'Yank inner word' },
  { lhs = 'yaw',    group = 'Yank combos',         desc = 'Yank a word (including surrounding space)' },
  { lhs = 'yip',    group = 'Yank combos',         desc = 'Yank inner paragraph' },

  { lhs = ':vs',        group = 'Split/Window',        desc = 'Split window vertically (type filename or Enter for same file)' },
  { lhs = ':q<CR>',    group = 'Split/Window',        desc = 'Quit current window/split' },
  { lhs = ':only<CR>', group = 'Split/Window',        desc = 'Close all windows except current' },
}

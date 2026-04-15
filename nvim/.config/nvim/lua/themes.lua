local gh = require('utils').gh

local M = {}

-- Active theme — change this to switch colorscheme
M.active = 'catppuccin'

-- Plugin sources — all registered with vim.pack, only the active one is used at runtime
M.sources = {
  { src = gh('catppuccin/nvim'),                    name = 'catppuccin' },
  { src = gh('folke/tokyonight.nvim') },
  { src = gh('ellisonleao/gruvbox.nvim') },
  { src = gh('rose-pine/neovim'),                   name = 'rose-pine' },
  { src = gh('rebelot/kanagawa.nvim') },
  { src = gh('Mofiqul/dracula.nvim') },
  { src = gh('projekt0n/github-nvim-theme'),         name = 'github-nvim-theme' },
  { src = gh('zenbones-theme/zenbones.nvim') },
  { src = gh('maxmx03/solarized.nvim') },
  -- high contrast
  { src = gh('nyoom-engineering/oxocarbon.nvim') },
  { src = gh('miikanissi/modus-themes.nvim') },
  { src = gh('dasupradyumna/midnight.nvim') },
  { src = gh('navarasu/onedark.nvim') },
  { src = gh('Mofiqul/vscode.nvim') },
  { src = gh('neanias/everforest-nvim') },
  { src = gh('AlexvZyl/nordic.nvim') },
}

-- Available variants per theme — informational, not used programmatically.
-- Set M.active to any variant name directly (e.g. 'catppuccin-latte').
M.variants = {
  catppuccin = {
    'catppuccin',          -- alias for mocha (default)
    'catppuccin-latte',    -- light; warm creamy whites with pastel accents
    'catppuccin-frappe',   -- dark, low contrast; muted cool grays with soft pastels
    'catppuccin-macchiato',-- dark, medium contrast; deeper grays, more vivid accents
    'catppuccin-mocha',    -- dark, high contrast; richest darks with vibrant pastel accents
  },
  tokyonight = {
    'tokyonight',          -- dark (default)
    'tokyonight-night',    -- darkest
    'tokyonight-storm',    -- slightly lighter dark
    'tokyonight-moon',     -- blue-tinted dark
    'tokyonight-day',      -- light
  },
  ['rose-pine'] = {
    'rose-pine',           -- dark (default)
    'rose-pine-moon',      -- dark, muted
    'rose-pine-dawn',      -- light
  },
  kanagawa = {
    'kanagawa',            -- dark (default)
    'kanagawa-wave',       -- original dark
    'kanagawa-dragon',     -- darker
    'kanagawa-lotus',      -- light
  },
  ['github-nvim-theme'] = {
    -- dark
    'github_dark',
    'github_dark_default',
    'github_dark_dimmed',
    'github_dark_high_contrast',
    'github_dark_colorblind',
    'github_dark_tritanopia',
    -- light
    'github_light',
    'github_light_default',
    'github_light_high_contrast',
    'github_light_colorblind',
  },
  zenbones = {
    'zenbones',      -- warm earth tones; low saturation, highlights via contrast + font variation
    'zenwritten',    -- fully desaturated/grayscale; zero hue, maximum readability
    'neobones',      -- cool blue-black bg, neon green accents; high contrast, inspired by neovim.io
    'vimbones',      -- warm cream light theme; earthy muted tones (rose, sage, burnt orange), inspired by vim.org
    'rosebones',     -- warm dark purple bg, rosy pinks and mauves; romantic aesthetic, inspired by Rosé Pine
    'forestbones',   -- cool dark bg, forest greens and earth tones; nature-inspired, inspired by Everforest
    'nordbones',     -- cool arctic blues and cyans on gray-blue bg; minimal, inspired by Nord
    'tokyobones',    -- vivid blues, pinks and teals on very dark blue bg; modern, inspired by Tokyo Night
    'seoulbones',    -- soft pastel pinks, teals and greens on medium gray; gentle contrast, inspired by Seoul256
    'duckbones',     -- bright oranges, cyans and purples on very dark bg; high contrast, inspired by Spaceduck
    'zenburned',     -- warm beige fg on medium-dark gray bg; muted earth tones, comfortable, inspired by Zenburn
    'kanagawabones', -- warm gold/pale yellow fg on dark purple-gray bg; muted with purple undertones, inspired by Kanagawa
  },
  solarized = {
    'solarized',           -- uses background=light/dark to switch
  },
  dracula = {
    'dracula',
    'dracula-soft',
  },
  gruvbox = {
    'gruvbox',             -- uses background=light/dark to switch
  },
  -- high contrast
  oxocarbon = {
    'oxocarbon',           -- uses background=light/dark to switch; pitch black bg (dark), bright white (light); electric cyan/purple accents; IBM Carbon design language
  },
  ['modus-themes'] = {
    -- dark
    'modus_vivendi',           -- dark default; WCAG AAA contrast (7:1 minimum); neutral bg, high legibility
    'modus_vivendi_tinted',    -- dark with subtle warm tint on bg
    'modus_vivendi_deuteranopia', -- dark, red-green colorblind safe
    'modus_vivendi_tritanopia',   -- dark, blue-yellow colorblind safe
    -- light
    'modus_operandi',          -- light default; WCAG AAA contrast; clean white bg, maximum legibility
    'modus_operandi_tinted',   -- light with subtle warm tint on bg
    'modus_operandi_deuteranopia', -- light, red-green colorblind safe
    'modus_operandi_tritanopia',   -- light, blue-yellow colorblind safe
  },
  midnight = {
    'midnight',            -- single dark variant; very dark blue-black bg; desaturated cool palette, warmer syntax accents; GUI only
  },
  onedark = {
    'onedark',             -- dark default; cool-toned, balanced saturation; Atom One Dark palette
    -- variants set via setup() style option, not separate colorscheme names
    -- 'darker': deeper blacks, higher contrast
    -- 'cool':   cooler blue undertones
    -- 'deep':   dark navy bg with vivid accents
    -- 'warm':   warm gray bg, reduced blue
    -- 'warmer': even warmer, amber tones
    -- 'light':  light bg, muted warm palette
  },
  vscode = {
    'vscode',              -- uses background=light/dark to switch; exact VS Code Dark+/Light+ palette; cool-toned dark, muted saturation
  },
  everforest = {
    'everforest',          -- uses background=light/dark + setup() background option (hard/medium/soft) to control contrast; natural greens and earthy tones; warm, moderate saturation
  },
  nordic = {
    'nordic',              -- single variant; warmer deeper Nord with Aurora accents; reduced blue saturation; cool with vibrant highlights
  },
}

-- Background hint per variant — plugins.lua sets vim.opt.background automatically.
-- Only needed for themes that use background=light/dark instead of separate names.
-- Themes with distinct variant names (catppuccin-latte, tokyonight-day, etc.) don't
-- need entries here — their name is unambiguous.
M.background = {
  -- gruvbox
  gruvbox            = 'dark',
  -- solarized
  solarized          = 'dark',
  -- oxocarbon
  oxocarbon          = 'dark',
  -- vscode
  vscode             = 'dark',
  -- everforest (hard/medium/soft set in M.setup)
  everforest         = 'dark',
  -- modus — explicit variant names already encode light/dark, but list here for clarity
  modus_vivendi               = 'dark',
  modus_vivendi_tinted        = 'dark',
  modus_vivendi_deuteranopia  = 'dark',
  modus_vivendi_tritanopia    = 'dark',
  modus_operandi              = 'light',
  modus_operandi_tinted       = 'light',
  modus_operandi_deuteranopia = 'light',
  modus_operandi_tritanopia   = 'light',
}

-- Maps every variant name back to its plugin name, so plugins.lua can find
-- the right setup() entry even when M.active is set to a variant.
M.plugin = {}
for plugin, variants in pairs(M.variants) do
  for _, variant in ipairs(variants) do
    M.plugin[variant] = plugin
  end
end

-- Per-theme setup() calls — run before colorscheme is applied.
-- Keyed by plugin name (not variant), so they fire regardless of which variant is active.
M.setup = {
  dracula = function()
    require('dracula').setup({
      italic_comment = true,
    })
  end,
  ['github-nvim-theme'] = function()
    require('github-theme').setup()
  end,
  -- onedark requires both setup() and load() — style selects the variant
  onedark = function()
    require('onedark').setup({
      style = 'dark',  -- dark | darker | cool | deep | warm | warmer | light
      code_style = {
        comments = 'italic',
      },
    })
    require('onedark').load()
  end,
  -- everforest contrast is controlled here rather than via colorscheme name
  everforest = function()
    require('everforest').setup({
      background = 'hard',  -- hard | medium | soft
    })
  end,
  -- modus-themes: style controls which base variant loads when using 'auto'
  ['modus-themes'] = function()
    require('modus-themes').setup({
      style = 'auto',  -- auto (follows background), modus_operandi, modus_vivendi
      styles = {
        comments = { italic = true },
      },
    })
  end,
}

-- Highlight overrides — applied after colorscheme so they always win.
-- Two levels:
--   M.overrides.global  — applied for every theme
--   M.overrides[theme]  — applied only when that plugin is active (keyed by plugin name)
--
-- Each entry is a table of { GroupName = { attr = value, ... } }.
-- See :help nvim_set_hl for all valid attributes.
-- Examples: { fg = '#ff0000' }, { bold = true }, { link = 'Comment' }
--
-- Tip: to find the highlight group name for anything on screen,
-- position the cursor on it and run :Inspect
M.overrides = {
  global = {
    -- Examples (uncomment to use):
    -- Comment    = { italic = true },
    -- LineNr     = { fg = '#888888' },
  },

  catppuccin = {
    -- Examples:
    -- Normal     = { bg = 'NONE' },  -- transparent background
  },

  tokyonight = {},
  ['rose-pine'] = {},
  kanagawa = {},
  dracula = {},
  gruvbox = {},
  solarized = {},
  zenbones = {},
  ['github-nvim-theme'] = {},
  -- high contrast
  oxocarbon = {},
  ['modus-themes'] = {},
  midnight = {},
  onedark = {},
  vscode = {},
  everforest = {},
  nordic = {},
}

return M

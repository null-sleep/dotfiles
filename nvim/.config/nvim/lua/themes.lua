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
}

return M

-- themes.lua — all theme configuration lives here.
--
-- SWITCHING THEMES
--   Change M.active to any colorscheme name or variant name:
--     M.active = 'catppuccin'          -- default dark
--     M.active = 'catppuccin-latte'    -- light variant
--     M.active = 'tokyonight-day'      -- light variant
--   For themes that use background=light/dark (gruvbox, solarized, etc.),
--   add a background entry in the theme's `background` field.
--
-- CUSTOMISING A THEME
--   Edit the theme's `setup` function or `overrides` table.
--   Tip: position cursor on any UI element and run :Inspect to find its highlight group name.
--
-- ADDING A NEW THEME
--   Add one entry to M.themes with at minimum `src`. All other fields are optional.

local gh = require('utils').gh

local M = {}

-- The active colorscheme. Set to any variant name from the variants list below.
M.active = 'catppuccin'

-- Global highlight overrides — applied for every theme, after colorscheme.
-- Format: { HighlightGroup = { fg = '#hex', bg = '#hex', bold = true, ... } }
-- See :help nvim_set_hl for all attributes.
M.global_overrides = {
  -- Comment = { italic = true },
  -- LineNr  = { fg = '#888888' },
}

-- Per-theme configuration. Each entry has:
--   src        (required) GitHub repo path
--   name       (optional) explicit pack name, only needed when repo slug differs from plugin name
--   variants   (optional) list of all colorscheme names this plugin provides, with descriptions
--   background (optional) map of variant name → 'light'|'dark', for themes that switch via
--              vim.opt.background rather than distinct colorscheme names
--   setup      (optional) function called before colorscheme is applied
--   overrides  (optional) highlight group overrides applied only when this theme is active
M.themes = {

  --------------------------------------------------------------------------
  -- General / popular
  --------------------------------------------------------------------------

  catppuccin = {
    src  = gh('catppuccin/nvim'),
    name = 'catppuccin',
    variants = {
      'catppuccin',          -- alias for mocha (default)
      'catppuccin-latte',    -- light; warm creamy whites with pastel accents
      'catppuccin-frappe',   -- dark, low contrast; muted cool grays with soft pastels
      'catppuccin-macchiato',-- dark, medium contrast; deeper grays, more vivid accents
      'catppuccin-mocha',    -- dark, high contrast; richest darks with vibrant pastel accents
    },
    overrides = {
      -- Normal = { bg = 'NONE' },  -- transparent background
    },
  },

  tokyonight = {
    src = gh('folke/tokyonight.nvim'),
    variants = {
      'tokyonight',          -- dark (default)
      'tokyonight-night',    -- darkest
      'tokyonight-storm',    -- slightly lighter dark
      'tokyonight-moon',     -- blue-tinted dark
      'tokyonight-day',      -- light
    },
  },

  gruvbox = {
    src = gh('ellisonleao/gruvbox.nvim'),
    variants = {
      'gruvbox',             -- warm amber/orange palette; uses background=light/dark to switch
    },
    background = { gruvbox = 'dark' },
  },

  ['rose-pine'] = {
    src  = gh('rose-pine/neovim'),
    name = 'rose-pine',
    variants = {
      'rose-pine',           -- dark (default); warm muted purples and pinks
      'rose-pine-moon',      -- dark, more muted and desaturated
      'rose-pine-dawn',      -- light; warm rose-tinted whites
    },
  },

  kanagawa = {
    src = gh('rebelot/kanagawa.nvim'),
    variants = {
      'kanagawa',            -- dark (default)
      'kanagawa-wave',       -- original dark; deep ink blue bg, warm gold/red accents
      'kanagawa-dragon',     -- darker; even deeper bg, higher contrast
      'kanagawa-lotus',      -- light; soft warm whites, muted ink tones
    },
  },

  dracula = {
    src = gh('Mofiqul/dracula.nvim'),
    variants = {
      'dracula',             -- classic dark; vivid purples, pinks and greens on near-black bg
      'dracula-soft',        -- same palette, slightly softened contrast
    },
    setup = function()
      require('dracula').setup({
        italic_comment = true,
      })
    end,
  },

  --------------------------------------------------------------------------
  -- Light-friendly / minimal
  --------------------------------------------------------------------------

  solarized = {
    src = gh('maxmx03/solarized.nvim'),
    variants = {
      'solarized',           -- classic warm palette; uses background=light/dark to switch
    },
    background = { solarized = 'dark' },
  },

  ['github-nvim-theme'] = {
    src  = gh('projekt0n/github-nvim-theme'),
    name = 'github-nvim-theme',
    variants = {
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
    setup = function()
      require('github-theme').setup()
    end,
  },

  zenbones = {
    src = gh('zenbones-theme/zenbones.nvim'),
    variants = {
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
  },

  --------------------------------------------------------------------------
  -- High contrast
  --------------------------------------------------------------------------

  oxocarbon = {
    src = gh('nyoom-engineering/oxocarbon.nvim'),
    variants = {
      'oxocarbon',           -- IBM Carbon design; pitch black bg (dark) or bright white (light); electric cyan/purple accents
    },
    background = { oxocarbon = 'dark' },
  },

  ['modus-themes'] = {
    src  = gh('miikanissi/modus-themes.nvim'),
    variants = {
      -- dark — WCAG AAA contrast (7:1 minimum)
      'modus_vivendi',               -- neutral dark bg; maximum legibility
      'modus_vivendi_tinted',        -- dark with subtle warm tint on bg
      'modus_vivendi_deuteranopia',  -- dark, red-green colorblind safe
      'modus_vivendi_tritanopia',    -- dark, blue-yellow colorblind safe
      -- light — WCAG AAA contrast
      'modus_operandi',              -- clean white bg; maximum legibility
      'modus_operandi_tinted',       -- light with subtle warm tint on bg
      'modus_operandi_deuteranopia', -- light, red-green colorblind safe
      'modus_operandi_tritanopia',   -- light, blue-yellow colorblind safe
    },
    background = {
      modus_vivendi               = 'dark',
      modus_vivendi_tinted        = 'dark',
      modus_vivendi_deuteranopia  = 'dark',
      modus_vivendi_tritanopia    = 'dark',
      modus_operandi              = 'light',
      modus_operandi_tinted       = 'light',
      modus_operandi_deuteranopia = 'light',
      modus_operandi_tritanopia   = 'light',
    },
    setup = function()
      require('modus-themes').setup({
        style  = 'auto',  -- auto (follows background) | modus_operandi | modus_vivendi
        styles = { comments = { italic = true } },
        on_colors     = function(_) end,
        on_highlights = function(_, _) end,
      })
    end,
  },

  midnight = {
    src = gh('dasupradyumna/midnight.nvim'),
    variants = {
      'midnight',            -- single dark variant; very dark blue-black bg; desaturated cool palette, warmer syntax accents; GUI only
    },
  },

  onedark = {
    src = gh('navarasu/onedark.nvim'),
    variants = {
      'onedark',             -- Atom One Dark palette; cool-toned, balanced saturation
      -- variants are set via setup() style option, not separate colorscheme names:
      -- 'darker': deeper blacks, higher contrast
      -- 'cool':   cooler blue undertones
      -- 'deep':   dark navy bg with vivid accents
      -- 'warm':   warm gray bg, reduced blue
      -- 'warmer': even warmer, amber tones
      -- 'light':  light bg, muted warm palette
    },
    -- onedark requires both setup() AND load() — style selects the variant
    setup = function()
      require('onedark').setup({
        style      = 'dark',  -- dark | darker | cool | deep | warm | warmer | light
        code_style = { comments = 'italic' },
      })
      require('onedark').load()
    end,
  },

  vscode = {
    src = gh('Mofiqul/vscode.nvim'),
    variants = {
      'vscode',              -- exact VS Code Dark+/Light+ palette; cool-toned dark, muted saturation; uses background=light/dark to switch
    },
    background = { vscode = 'dark' },
  },

  everforest = {
    src = gh('neanias/everforest-nvim'),
    variants = {
      'everforest',          -- natural greens and earthy tones; warm, moderate saturation; uses background=light/dark + setup() background (hard|medium|soft) for contrast
    },
    background = { everforest = 'dark' },
    -- contrast level is controlled here — hard | medium | soft
    setup = function()
      require('everforest').setup({
        background = 'hard',
      })
    end,
  },

  nordic = {
    src = gh('AlexvZyl/nordic.nvim'),
    variants = {
      'nordic',              -- warmer deeper Nord; Aurora accents over muted bg; reduced blue saturation; cool with vibrant highlights
    },
  },

}

--------------------------------------------------------------------------
-- Derived lookup tables — computed from M.themes, do not edit directly
--------------------------------------------------------------------------

-- vim.pack.add source list
M.sources = {}
for _, t in pairs(M.themes) do
  local entry = { src = t.src }
  if t.name then entry.name = t.name end
  M.sources[#M.sources + 1] = entry
end

-- variant name → plugin key  (e.g. 'catppuccin-latte' → 'catppuccin')
M.plugin = {}
for key, t in pairs(M.themes) do
  if t.variants then
    for _, variant in ipairs(t.variants) do
      M.plugin[variant] = key
    end
  end
end

-- variant name → 'light'|'dark'  (only for background-switching themes)
M.background = {}
for _, t in pairs(M.themes) do
  if t.background then
    for variant, bg in pairs(t.background) do
      M.background[variant] = bg
    end
  end
end

return M

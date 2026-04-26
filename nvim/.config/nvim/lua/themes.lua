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

-- Persistence: read saved theme from state file, fall back to default.
local state_file = vim.fn.stdpath('data') .. '/theme.txt'
local default_theme = 'catppuccin'

local function read_saved_theme()
  local ok, lines = pcall(vim.fn.readfile, state_file)
  if ok and lines[1] and lines[1] ~= '' then return lines[1] end
  return default_theme
end

M.active = read_saved_theme()

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
--   variants   (optional) list of all colorscheme names this plugin provides, with descriptions.
--              For themes that only register one colorscheme name but support light/dark via
--              vim.opt.background, add virtual variant names (e.g. 'gruvbox-light') and map
--              them to the real colorscheme name in the `colorscheme` table below.
--   colorscheme (optional) map of virtual variant name → real colorscheme name, for variants
--              that don't correspond to a registered colorscheme (e.g. 'gruvbox-light' → 'gruvbox')
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
      'gruvbox',             -- warm amber/orange palette; dark
      'gruvbox-light',       -- warm amber/orange palette; light
    },
    colorscheme = { ['gruvbox-light'] = 'gruvbox' },
    background  = { gruvbox = 'dark', ['gruvbox-light'] = 'light' },
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

  nightfox = {
    src = gh('EdenEast/nightfox.nvim'),
    variants = {
      'nightfox',            -- dark; cool blue-purple palette
      'dayfox',              -- light; warm soft tones
      'dawnfox',             -- light; rosy warm palette
      'duskfox',             -- dark; muted purple twilight tones
      'nordfox',             -- dark; Nord-inspired arctic blues
      'terafox',             -- dark; earthy greens and warm tones
      'carbonfox',           -- dark; neutral carbon grays with vivid accents
    },
  },

  cyberdream = {
    src = gh('scottmckendry/cyberdream.nvim'),
    variants = {
      'cyberdream',          -- dark; neon accents on dark bg
      'cyberdream-light',    -- light variant
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
      'solarized',           -- classic warm palette; dark
      'solarized-light',     -- classic warm palette; light
    },
    colorscheme = { ['solarized-light'] = 'solarized' },
    background  = { solarized = 'dark', ['solarized-light'] = 'light' },
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
    -- Use pre-baked VimScript highlights instead of the lush.nvim dynamic path,
    -- which would require lush as an extra dependency.
    setup = function() vim.g.bones_compat = 1 end,
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
      'oxocarbon',           -- IBM Carbon design; pitch black bg, electric cyan/purple accents
      'oxocarbon-light',     -- IBM Carbon design; bright white bg, electric cyan/purple accents
    },
    colorscheme = { ['oxocarbon-light'] = 'oxocarbon' },
    background  = { oxocarbon = 'dark', ['oxocarbon-light'] = 'light' },
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
    -- onedark style is configured via setup(); M.apply() handles colorscheme.
    setup = function()
      require('onedark').setup({
        style      = 'dark',  -- dark | darker | cool | deep | warm | warmer | light
        code_style = { comments = 'italic' },
      })
    end,
  },

  vscode = {
    src = gh('Mofiqul/vscode.nvim'),
    variants = {
      'vscode',              -- exact VS Code Dark+ palette; cool-toned, muted saturation
      'vscode-light',        -- exact VS Code Light+ palette
    },
    colorscheme = { ['vscode-light'] = 'vscode' },
    background  = { vscode = 'dark', ['vscode-light'] = 'light' },
  },

  everforest = {
    src = gh('neanias/everforest-nvim'),
    variants = {
      'everforest',          -- natural greens and earthy tones; dark, hard contrast
      'everforest-light',    -- natural greens and earthy tones; light, hard contrast
    },
    colorscheme = { ['everforest-light'] = 'everforest' },
    background  = { everforest = 'dark', ['everforest-light'] = 'light' },
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

-- virtual variant name → real colorscheme name  (e.g. 'gruvbox-light' → 'gruvbox')
-- For themes that use vim.opt.background to switch light/dark but only register
-- one colorscheme name. Variants not in this table use their own name directly.
M.colorscheme = {}
for _, t in pairs(M.themes) do
  if t.colorscheme then
    for variant, cs in pairs(t.colorscheme) do
      M.colorscheme[variant] = cs
    end
  end
end

--------------------------------------------------------------------------
-- Operations
--------------------------------------------------------------------------

--- Apply a theme variant: packadd → background → setup → colorscheme → overrides.
---
--- Designed to be called repeatedly during live preview (theme-picker scrolling).
--- Verified safe because:
---   packadd:  re-sources plugin/ scripts each call, but none of our current
---             themes have problematic plugin/ scripts (github-nvim-theme
---             registers commands idempotently; all others have no plugin/ dir).
---             When adding a new theme: if it has a plugin/ dir with side effects
---             (autocommands, global state) that accumulate on repeated source,
---             it will misbehave during live preview. Check with :packadd + :scriptnames.
---   setup():  all five current setup functions (dracula, github-nvim-theme,
---             modus-themes, onedark, everforest) use replace/overwrite patterns —
---             no accumulating autocommands, no growing global state.
---             When adding a new theme with a setup(): verify it is idempotent
---             (no additive autocommands, no append-only state). If not, the
---             picker will degrade for that theme (flicker, leaked state, slowdown).
---   Note:     some themes (onedark) call setup() internally from their
---             colors/<name>.lua file, so setup() may run twice per apply. This is
---             harmless — all our themes' setup functions are idempotent.
---   colorscheme: pcall-wrapped so a broken theme during preview shows a warning
---             instead of crashing Neovim.
function M.apply(variant)
  local plugin_key = M.plugin[variant] or variant
  local theme = M.themes[plugin_key]
  if not theme then return end

  -- packadd takes the pack directory name, which is theme.name when the repo
  -- slug differs from the plugin name (e.g. catppuccin/nvim → name='catppuccin').
  vim.cmd.packadd(theme.name or plugin_key)

  -- Explicit background reset: prevents a previous theme's background='light'
  -- from leaking into themes that don't specify one.
  -- Note: changing background can fire a ColorScheme event for the *current*
  -- colorscheme if the value actually changes (e.g. light→dark). This is
  -- harmless — the vim.cmd.colorscheme() call below immediately overwrites it.
  vim.opt.background = M.background[variant] or 'dark'

  if theme.setup then pcall(theme.setup) end

  -- Resolve virtual variant names (e.g. 'gruvbox-light' → 'gruvbox') for themes
  -- that use vim.opt.background to switch but only register one colorscheme name.
  local cs = M.colorscheme[variant] or variant
  local ok, err = pcall(vim.cmd.colorscheme, cs)
  if not ok then
    vim.notify('theme-picker: ' .. err, vim.log.levels.WARN)
    return
  end

  -- Overrides must run after colorscheme so they aren't clobbered.
  for group, attrs in pairs(M.global_overrides) do
    vim.api.nvim_set_hl(0, group, attrs)
  end
  if theme.overrides then
    for group, attrs in pairs(theme.overrides) do
      vim.api.nvim_set_hl(0, group, attrs)
    end
  end
end

--- Persist a variant name to the state file so it survives restarts.
--- stdpath('data') (typically ~/.local/share/nvim/) always exists — no mkdir needed.
--- To reset to the default theme, delete the state file.
function M.save(variant)
  vim.fn.writefile({ variant }, state_file)
  M.active = variant
end

--- Sorted list of all variant names (deterministic alphabetical order).
--- pairs() over M.themes is non-deterministic, so we collect and sort.
function M.all_variants()
  local list = {}
  for _, t in pairs(M.themes) do
    if t.variants then
      for _, v in ipairs(t.variants) do
        list[#list + 1] = v
      end
    end
  end
  table.sort(list)
  return list
end

return M

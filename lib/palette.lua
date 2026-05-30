-- Semantic color names mapped onto the engine's 16-slot palette, plus a
-- string->slot resolver so JSON content can name colors (e.g. "RED").
-- `gfx` is a global the engine installs before this module is required.

local P = {}

-- Lookup for data-driven color names (data/*.json store colors as strings).
P.by_name = {
  BLACK      = gfx.COLOR_BLACK,
  DARK_BLUE  = gfx.COLOR_DARK_BLUE,
  DARK_PURPLE = gfx.COLOR_DARK_PURPLE,
  DARK_GREEN = gfx.COLOR_DARK_GREEN,
  BROWN      = gfx.COLOR_BROWN,
  DARK_GRAY  = gfx.COLOR_DARK_GRAY,
  LIGHT_GRAY = gfx.COLOR_LIGHT_GRAY,
  WHITE      = gfx.COLOR_WHITE,
  RED        = gfx.COLOR_RED,
  ORANGE     = gfx.COLOR_ORANGE,
  YELLOW     = gfx.COLOR_YELLOW,
  GREEN      = gfx.COLOR_GREEN,
  BLUE       = gfx.COLOR_BLUE,
  INDIGO     = gfx.COLOR_INDIGO,
  PINK       = gfx.COLOR_PINK,
  PEACH      = gfx.COLOR_PEACH,
}

-- Returns a gfx.COLOR_* slot for a name; magenta-ish PINK if unknown.
function P.resolve(name)
  return P.by_name[name] or gfx.COLOR_PINK
end

-- Semantic roles used by the UI / rendering.
P.BG         = gfx.COLOR_DARK_BLUE
P.FIELD_BG   = gfx.COLOR_DARK_BLUE
P.PATH       = gfx.COLOR_DARK_GRAY
P.PATH_EDGE  = gfx.COLOR_INDIGO
P.CORE       = gfx.COLOR_GREEN
P.SPAWN      = gfx.COLOR_RED
P.TEXT       = gfx.COLOR_WHITE
P.TEXT_DIM   = gfx.COLOR_LIGHT_GRAY
P.MONEY      = gfx.COLOR_YELLOW
P.LIVES      = gfx.COLOR_RED
P.GOOD       = gfx.COLOR_GREEN
P.BAD        = gfx.COLOR_RED
P.RANGE      = gfx.COLOR_INDIGO
P.GHOST_OK   = gfx.COLOR_GREEN
P.GHOST_BAD  = gfx.COLOR_RED
P.HUD_BG     = gfx.COLOR_BLACK
P.HUD_PANEL  = gfx.COLOR_DARK_PURPLE
P.HUD_SEL    = gfx.COLOR_YELLOW

return P

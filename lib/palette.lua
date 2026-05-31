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
P.PATH_CORE  = gfx.COLOR_BLUE    -- bright neon centre-line of the lane
P.PULSE      = gfx.COLOR_PEACH   -- energy packets travelling the route
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

-- High-contrast accessibility mode (V2-M9). The semantic roles are direct fields,
-- so a toggle just rewrites them: capture the normal set once, define brighter
-- overrides for the readability-critical roles (a pure-black field so neon enemies
-- pop, white/gray route tubes, crisp text/danger), and fall back to the normal
-- value for any role without an override -- so set_contrast(true) resolves EVERY
-- semantic color. set_contrast(false) restores the normal set exactly.
P.SEMANTIC = {
  "BG", "FIELD_BG", "PATH", "PATH_EDGE", "PATH_CORE", "PULSE", "CORE", "SPAWN",
  "TEXT", "TEXT_DIM", "MONEY", "LIVES", "GOOD", "BAD", "RANGE", "GHOST_OK",
  "GHOST_BAD", "HUD_BG", "HUD_PANEL", "HUD_SEL",
}

local NORMAL = {}
for i = 1, #P.SEMANTIC do NORMAL[P.SEMANTIC[i]] = P[P.SEMANTIC[i]] end

local HIGH = {
  BG = gfx.COLOR_BLACK, FIELD_BG = gfx.COLOR_BLACK,
  PATH = gfx.COLOR_LIGHT_GRAY, PATH_EDGE = gfx.COLOR_WHITE, PATH_CORE = gfx.COLOR_WHITE,
  PULSE = gfx.COLOR_YELLOW, CORE = gfx.COLOR_GREEN, SPAWN = gfx.COLOR_RED,
  TEXT = gfx.COLOR_WHITE, TEXT_DIM = gfx.COLOR_LIGHT_GRAY,
  RANGE = gfx.COLOR_WHITE, HUD_PANEL = gfx.COLOR_DARK_GRAY,
}

function P.set_contrast(on)
  for i = 1, #P.SEMANTIC do
    local k = P.SEMANTIC[i]
    P[k] = (on and HIGH[k]) or NORMAL[k]
  end
end

return P

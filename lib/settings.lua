-- Player settings (V2-M9): volumes + accessibility/comfort toggles, persisted as
-- part of the meta save (so they survive restart + ride the meta version migration
-- -- backfill adds any missing key). The model lives here; the systems read live
-- values via settings.value(id), which is SAFE before State/State.settings exist
-- (falls back to the default), so headless tests and a fresh boot behave at the
-- documented defaults -- i.e. identical to pre-M9 behaviour. Persistence is the
-- caller's job (meta.save), like lib/mastery; this module never requires meta.

local M = {}

-- Order is the display order on the menu Options tab. Every setting is a boolean
-- comfort/accessibility toggle. Player-facing music/SFX volume is the engine's
-- built-in pause-menu control (Usagi scales every sfx/music call by it), so the
-- game keeps no volume of its own -- a second multiplier would just compound it.
M.DEFS = {
  { id = "crt",            name = "CRT Filter",     default = true },
  { id = "shake",          name = "Screen Shake",   default = true },
  { id = "high_contrast",  name = "High Contrast",  default = false },
  { id = "damage_numbers", name = "Damage Numbers", default = true },
}

local DEFAULTS = {}
for i = 1, #M.DEFS do DEFAULTS[M.DEFS[i].id] = M.DEFS[i].default end

-- A fresh settings table at the defaults.
function M.defaults()
  local t = {}
  for k, v in pairs(DEFAULTS) do t[k] = v end
  return t
end

-- Backfill a (possibly old / partial) settings table with any missing default --
-- the settings half of the save migration.
function M.fill(s)
  s = s or {}
  for k, v in pairs(DEFAULTS) do
    if s[k] == nil then s[k] = v end
  end
  return s
end

-- The live value of a setting: State.settings if present, else the default. Safe
-- to call from any system at any time (incl. before _init / in headless tests).
function M.value(id)
  local s = State and State.settings
  if s and s[id] ~= nil then return s[id] end
  return DEFAULTS[id]
end

-- Flip a boolean setting on a settings table; returns the new value. Every
-- setting is a boolean toggle, so this is the one control action -- the menu
-- Options tab and the pause-menu items both flip through it.
function M.toggle(s, id)
  s[id] = not s[id]
  return s[id]
end

return M

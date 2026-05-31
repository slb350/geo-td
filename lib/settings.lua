-- Player settings (V2-M9): volumes + accessibility/comfort toggles, persisted as
-- part of the meta save (so they survive restart + ride the meta version migration
-- -- backfill adds any missing key). The model lives here; the systems read live
-- values via settings.value(id), which is SAFE before State/State.settings exist
-- (falls back to the default), so headless tests and a fresh boot behave at the
-- documented defaults -- i.e. identical to pre-M9 behaviour. Persistence is the
-- caller's job (meta.save), like lib/mastery; this module never requires meta.

local M = {}

-- Order is the display order on the menu Options tab. kind drives the control:
-- a "toggle" flips bool; a "volume" cycles through VOL_STEPS.
M.DEFS = {
  { id = "music_vol",      name = "Music",          kind = "volume", default = 0.48 },
  { id = "sfx_vol",        name = "SFX",            kind = "volume", default = 1.0 },
  { id = "crt",            name = "CRT Filter",     kind = "toggle", default = true },
  { id = "shake",          name = "Screen Shake",   kind = "toggle", default = true },
  { id = "high_contrast",  name = "High Contrast",  kind = "toggle", default = false },
  { id = "damage_numbers", name = "Damage Numbers", kind = "toggle", default = true },
}

local DEFAULTS = {}
for i = 1, #M.DEFS do DEFAULTS[M.DEFS[i].id] = M.DEFS[i].default end
M.DEFAULTS = DEFAULTS

M.VOL_STEPS = { 0, 0.25, 0.5, 0.75, 1.0 }

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

-- Flip a boolean setting on a settings table; returns the new value.
function M.toggle(s, id)
  s[id] = not s[id]
  return s[id]
end

-- Step a volume to the next VOL_STEPS rung above the current value, wrapping to the
-- lowest. Returns the new value.
function M.cycle_volume(s, id)
  local cur = s[id] or 0
  for i = 1, #M.VOL_STEPS do
    if M.VOL_STEPS[i] > cur + 1e-6 then s[id] = M.VOL_STEPS[i]; return s[id] end
  end
  s[id] = M.VOL_STEPS[1]
  return s[id]
end

-- Apply the control action for a DEF row (toggle or volume cycle) to a settings
-- table; returns the new value. Shared by the menu Options tab + the pause menu.
function M.apply(s, def)
  if def.kind == "volume" then return M.cycle_volume(s, def.id) end
  return M.toggle(s, def.id)
end

return M

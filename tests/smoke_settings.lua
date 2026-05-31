-- Settings cases (V2-M9): the model (defaults / fill-migration / live value with
-- safe fallback / toggle / volume cycle), the meta save integration (settings in
-- default + backfilled onto an old save), the high-contrast palette (resolves every
-- semantic color, restores), the fx comfort gates (screen shake + damage numbers),
-- and the menu Options tab (layout fit + toggle-on-click persists). Run by smoke.lua
-- via M.run(check, near) AFTER smoke_core installs the scene globals.

local harness  = require("tests.harness")
local settings = require("lib.settings")
local meta     = require("lib.meta")
local pal      = require("lib.palette")
local fx       = require("lib.fx")
local menu_s   = require("scenes.menu")

local M = {}

function M.run(check, near)
  -- ------------------------------------------------------------------- model
  local d = settings.defaults()
  check(near(d.music_vol, 0.48) and near(d.sfx_vol, 1.0) and d.crt == true
    and d.shake == true and d.high_contrast == false and d.damage_numbers == true,
    "defaults carry every setting at its documented value")

  -- fill is the migration: add only the missing keys, keep existing values
  local partial = settings.fill({ music_vol = 0.2 })
  check(near(partial.music_vol, 0.2), "fill keeps an existing value")
  check(partial.crt == true and partial.damage_numbers == true, "fill backfills missing keys")
  local n = 0; for _ in pairs(settings.fill({})) do n = n + 1 end
  check(n == #settings.DEFS, "fill produces every setting")

  -- value: live State.settings wins; absent falls back to the default
  local saved = State.settings
  State.settings = { music_vol = 0.75 }
  check(near(settings.value("music_vol"), 0.75), "value reads the live setting")
  check(settings.value("crt") == true, "value falls back to default for a missing key")
  State.settings = nil
  check(near(settings.value("music_vol"), 0.48) and settings.value("shake") == true,
    "value is safe with no State.settings (returns defaults)")
  State.settings = saved

  -- toggle + volume cycle
  local s = settings.defaults()
  check(settings.toggle(s, "crt") == false and s.crt == false, "toggle flips a bool")
  s.music_vol = 0.5
  check(near(settings.cycle_volume(s, "music_vol"), 0.75), "cycle_volume steps up")
  s.music_vol = 1.0
  check(near(settings.cycle_volume(s, "music_vol"), 0), "cycle_volume wraps to the bottom")

  -- ------------------------------------------------------ meta save integration
  check(meta.default().settings ~= nil, "meta.default carries settings")
  local v1 = { version = 1, currency = 5, unlocks = {}, map_unlocked = {}, map_best = {} }
  meta.save(v1)
  local up = meta.load()
  check(type(up.settings) == "table" and up.settings.crt == true,
    "loading an old save backfills settings")
  meta.save({ version = 2, settings = { music_vol = 0.25 } })
  local pm = meta.load()
  check(near(pm.settings.music_vol, 0.25) and pm.settings.shake == true,
    "a partial settings save is filled, existing value kept")

  -- --------------------------------------------------- high-contrast palette
  pal.set_contrast(true)
  local all_resolved = true
  for i = 1, #pal.SEMANTIC do if pal[pal.SEMANTIC[i]] == nil then all_resolved = false end end
  check(all_resolved, "high contrast resolves every semantic color")
  check(pal.BG == gfx.COLOR_BLACK, "high contrast overrides the field background")
  pal.set_contrast(false)
  check(pal.BG == gfx.COLOR_DARK_BLUE, "set_contrast(false) restores the normal palette")

  -- -------------------------------------------------------- fx comfort gates
  -- damage numbers: gate suppresses the floating number (observed via draw calls)
  local function drew_number()
    fx.clear(); fx.number(40, 40, "+5"); harness.reset_gfx(); fx.draw()
    local calls = harness.gfx_calls()
    for i = 1, #calls do if calls[i].fn == "text_ex" then return true end end
    return false
  end
  State.settings = settings.defaults()
  check(drew_number(), "damage numbers on: the number draws")
  State.settings.damage_numbers = false
  check(not drew_number(), "damage numbers off: the number is suppressed")

  -- screen shake: the gate suppresses effect.screen_shake
  local shook
  local real_shake = effect.screen_shake
  effect.screen_shake = function() shook = true end
  State.settings.shake = true; shook = false; fx.shake(0.1, 2)
  check(shook, "screen shake on: fx.shake shakes")
  State.settings.shake = false; shook = false; fx.shake(0.1, 2)
  check(not shook, "screen shake off: fx.shake is silent")
  effect.screen_shake = real_shake
  State.settings = saved
  fx.clear()

  -- ----------------------------------------------------------- menu Options tab
  State.meta = meta.default(); State.settings = State.meta.settings
  State.ui.menu_tab = "options"
  local rows = menu_s.tab_rows("options")
  check(#rows == #settings.DEFS, "the options tab lays out one row per setting")
  check(rows[#rows].y + rows[#rows].h <= 94 + 150, "every options row stays inside the panel")
  -- click the CRT row (a toggle): it flips, updates State.crt, and persists
  local crt_row
  for i = 1, #rows do if rows[i].id == "crt" then crt_row = rows[i] end end
  local before = State.settings.crt
  input._clicks.left, input._clicks.mx, input._clicks.my = true, crt_row.x + 4, crt_row.y + 4
  menu_s.update(1 / 60)
  input._clicks.left = false
  check(State.settings.crt == (not before), "clicking the CRT row toggles the setting")
  check(State.crt == State.settings.crt, "the CRT flag tracks the setting")
  check(meta.load().settings.crt == State.settings.crt, "the toggle persists to the save")
  menu_s.draw(1 / 60)                     -- the options panel renders without error
  State.meta = meta.default(); State.settings = nil; State.ui.menu_tab = "shop"
  pal.set_contrast(false)                 -- leave the palette normal for later suites
end

return M

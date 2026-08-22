-- Settings cases (V2-M9): the model (defaults / fill-migration / live value with
-- safe fallback / toggle), the meta save integration (settings in
-- default + backfilled onto an old save), the high-contrast palette (resolves every
-- semantic color, restores), the fx comfort gates (screen shake + damage numbers),
-- and the menu Options tab (layout fit + toggle-on-click persists). Run by smoke.lua
-- via M.run(check, near) AFTER smoke_core installs the scene globals.

local harness = require("tests.harness")
local settings = require("lib.settings")
local meta = require("lib.meta")
local pal = require("lib.palette")
local fx = require("lib.fx")
local ring = require("lib.ring")
local run_mod = require("lib.run")
local menu_s = require("scenes.menu")

local M = {}

function M.run(check, near)
  -- ------------------------------------------------------------------- model
  local d = settings.defaults()
  check(
    d.crt == true and d.shake == true and d.high_contrast == false and d.damage_numbers == true,
    "defaults carry every setting at its documented value"
  )

  -- fill is the migration: add only the missing keys, keep existing values
  local partial = settings.fill({ shake = false })
  check(partial.shake == false, "fill keeps an existing value")
  check(partial.crt == true and partial.damage_numbers == true, "fill backfills missing keys")
  local n = 0
  for _ in pairs(settings.fill({})) do
    n = n + 1
  end
  check(n == #settings.DEFS, "fill produces every setting")

  -- value: live State.settings wins; absent falls back to the default
  local saved = State.settings
  State.settings = { shake = false }
  check(settings.value("shake") == false, "value reads the live setting")
  check(settings.value("crt") == true, "value falls back to default for a missing key")
  State.settings = nil
  check(
    settings.value("crt") == true and settings.value("shake") == true,
    "value is safe with no State.settings (returns defaults)"
  )
  State.settings = saved

  -- toggle
  local s = settings.defaults()
  check(settings.toggle(s, "crt") == false and s.crt == false, "toggle flips a bool")

  -- ------------------------------------------------------ meta save integration
  check(meta.default().settings ~= nil, "meta.default carries settings")
  local v1 = { version = 1, currency = 5, unlocks = {}, map_unlocked = {}, map_best = {} }
  meta.save(v1)
  local up = meta.load()
  check(type(up.settings) == "table" and up.settings.crt == true, "loading an old save backfills settings")
  meta.save({ version = 2, settings = { crt = false } })
  local pm = meta.load()
  check(
    pm.settings.crt == false and pm.settings.shake == true,
    "a partial settings save is filled, existing value kept"
  )

  -- --------------------------------------------------- high-contrast palette
  pal.set_contrast(true)
  local all_resolved = true
  for i = 1, #pal.SEMANTIC do
    if pal[pal.SEMANTIC[i]] == nil then all_resolved = false end
  end
  check(all_resolved, "high contrast resolves every semantic color")
  check(pal.BG == gfx.COLOR_BLACK, "high contrast overrides the field background")
  pal.set_contrast(false)
  check(pal.BG == gfx.COLOR_DARK_BLUE, "set_contrast(false) restores the normal palette")

  -- -------------------------------------------------------- fx comfort gates
  -- damage numbers: gate suppresses the floating number (observed via draw calls)
  local function drew_number()
    fx.clear()
    fx.number(40, 40, "+5")
    harness.reset_gfx()
    fx.draw()
    local calls = harness.gfx_calls()
    for i = 1, #calls do
      if calls[i].fn == "text_ex" then return true end
    end
    return false
  end
  State.settings = settings.defaults()
  check(drew_number(), "damage numbers on: the number draws")
  State.settings.damage_numbers = false
  check(not drew_number(), "damage numbers off: the number is suppressed")

  -- screen shake: the gate suppresses effect.screen_shake
  local shook
  local real_shake = effect.screen_shake
  effect.screen_shake = function()
    shook = true
  end
  State.settings.shake = true
  shook = false
  fx.shake(0.1, 2)
  check(shook, "screen shake on: fx.shake shakes")
  State.settings.shake = false
  shook = false
  fx.shake(0.1, 2)
  check(not shook, "screen shake off: fx.shake is silent")
  effect.screen_shake = real_shake
  State.settings = saved
  fx.clear()

  -- ----------------------------------------------------------- menu Options tab
  State.meta = meta.default()
  State.settings = State.meta.settings
  State.ui.menu_tab = "options"
  local rows = menu_s.tab_rows("options")
  check(#rows == #settings.DEFS, "the options tab lays out one row per setting")
  check(rows[#rows].y + rows[#rows].h <= 94 + 150, "every options row stays inside the panel")
  -- click the CRT row (a toggle): it flips, updates State.crt, and persists
  local crt_row
  for i = 1, #rows do
    if rows[i].id == "crt" then crt_row = rows[i] end
  end
  local before = State.settings.crt
  input._clicks.left, input._clicks.mx, input._clicks.my = true, crt_row.x + 4, crt_row.y + 4
  menu_s.update(1 / 60)
  input._clicks.left = false
  check(State.settings.crt == not before, "clicking the CRT row toggles the setting")
  check(State.crt == State.settings.crt, "the CRT flag tracks the setting")
  check(meta.load().settings.crt == State.settings.crt, "the toggle persists to the save")
  menu_s.draw(1 / 60) -- the options panel renders without error
  State.meta = meta.default()
  State.settings = nil
  State.ui.menu_tab = "shop"
  pal.set_contrast(false) -- leave the palette normal for later suites

  -- ------------------------------------------------- alpha fades (engine 1.2.0)
  -- Every gfx primitive takes an optional trailing alpha now, so effects that
  -- expire can fade instead of popping out. Previously only text_ex could.
  fx.clear()
  fx.burst(50, 50, gfx.COLOR_ORANGE, 4)
  local function particle_alpha()
    harness.reset_gfx()
    fx.draw()
    for _, c in ipairs(harness.gfx_calls()) do
      if c.fn == "circ_fill" then return c.args[5] end
    end
  end
  local a0 = particle_alpha()
  check(a0 ~= nil, "particles draw with an alpha argument")
  check(a0 and a0 > 0.9, "a fresh particle draws at full opacity, got " .. tostring(a0))
  fx.update(0.15)
  local a1 = particle_alpha()
  check(a1 and a1 < a0, "a particle fades as its life runs down (" .. tostring(a0) .. " -> " .. tostring(a1) .. ")")
  fx.update(0.15)
  local a2 = particle_alpha()
  check(a2 == nil or a2 < a1, "the fade keeps decreasing toward expiry")
  fx.clear()

  -- splash rings: the comment always claimed "a fading ring"; now it really fades
  local rr = run_mod.new(meta.default(), 7, "serpentine")
  ring.spawn(rr, 40, 40, { radius = 20, ticks = 4, dmg = 1 })
  local function ring_alpha()
    harness.reset_gfx()
    ring.draw(rr)
    for _, c in ipairs(harness.gfx_calls()) do
      if c.fn == "circ" then return c.args[5] end
    end
  end
  local r0 = ring_alpha()
  check(r0 ~= nil, "splash rings draw with an alpha argument")
  rr.rings[1].ticks = 1
  local r1 = ring_alpha()
  check(r1 and r0 and r1 < r0, "a splash ring fades as it spends its ticks")
end

return M

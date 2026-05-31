-- Shared fixtures for the split smoke suites (smoke_report, smoke_cards). The
-- engine-stub harness must already be installed (modules read JSON at require
-- time), which smoke.lua guarantees by requiring tests.harness first.

local C       = require("lib.const")
local enemy   = require("lib.enemy")
local proj    = require("lib.projectile")
local tower   = require("lib.tower")
local run_mod = require("lib.run")
local path    = require("lib.path")

local M = {}

-- A fresh serpentine run with money to spare (the common test starting point).
function M.fresh(meta, seed)
  local r = run_mod.new(meta, seed or 1, "serpentine")
  r.money = 99999
  return r
end

-- Is a point inside the play field (left of the HUD)? Used by the path/variant
-- in-bounds checks in the layout suites.
function M.in_field(x, y)
  return x >= 0 and x < C.FIELD_W and y >= 0 and y < C.FIELD_H
end

-- A stationary, durable, no-armor ground target so damage math is not muddied
-- by death, movement, armor, or shields. Big default hp so direct/chain hits
-- never cap out; pass hp_scale to override.
function M.dummy(r, x, y, hp_scale)
  local e = enemy.spawn(r, "hulk", hp_scale or 50, 1, 10)
  e.x, e.y = x, y
  e.armor, e.shield, e.shield_max = 0, 0, 0
  return e
end

-- Advance projectiles to impact. enemy.update is intentionally NOT called, so
-- targets stay put and the shot lands.
function M.settle(r)
  for _ = 1, 400 do
    if r.projectiles.n == 0 then break end
    proj.update(r, 1 / 60)
  end
end

-- Fire one shot from tower t (zero its cooldown) and settle every projectile.
function M.fire_and_settle(r, t)
  t.cooldown = 0
  tower.update(r, 1 / 60)
  M.settle(r)
end

-- ----------------------------------------------------------- build-plan helpers
-- A lib/sim build plan is an array of actions, each carrying the `wave` whose
-- build phase applies it plus one of place/upgrade/module/sell/powerup. These
-- helpers generate the recurring shapes (a uniform tower cordon) so the sim and
-- balance suites and the baseline tool don't hand-roll the same grid each time.

-- A uniform off-path tower grid for `path_obj`: one `kind` tower (default pellet)
-- every `step` px (default 26) that clears the path by PLACE_MARGIN + TOWER_R, all
-- applied in wave `wave` (default 1). Step > 2*TOWER_R guarantees no overlaps, so
-- with enough money every cell places -- the "uniform cordon" used to rank map
-- difficulty empirically. opts: kind, step, wave, margin.
function M.grid_cordon(path_obj, opts)
  opts = opts or {}
  local kind   = opts.kind or "pellet"
  local step   = opts.step or 26
  local wv     = opts.wave or 1
  local margin = opts.margin or (C.PLACE_MARGIN + C.TOWER_R)
  local plan = {}
  for gx = 16, C.FIELD_W - 16, step do
    for gy = 16, C.FIELD_H - 16, step do
      if path.dist_to(path_obj, gx, gy) >= margin then
        plan[#plan + 1] = { wave = wv, place = { kind = kind, x = gx, y = gy } }
      end
    end
  end
  return plan
end

-- grid_cordon for a map by name (builds a scratch run just to read its path).
function M.map_cordon(meta, map, opts)
  local r = run_mod.new(meta, (opts and opts.seed) or 1, map)
  return M.grid_cordon(r.path, opts)
end

return M

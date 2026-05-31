-- Shared fixtures for the split smoke suites (smoke_report, smoke_cards). The
-- engine-stub harness must already be installed (modules read JSON at require
-- time), which smoke.lua guarantees by requiring tests.harness first.

local C       = require("lib.const")
local enemy   = require("lib.enemy")
local proj    = require("lib.projectile")
local tower   = require("lib.tower")
local run_mod = require("lib.run")

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

return M

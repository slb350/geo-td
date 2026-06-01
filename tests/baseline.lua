-- Balance baseline table (V2-M0). Runs a uniform max cordon through standard mode
-- for waves 1-WAVES on every map and prints the per-map metrics the roadmap wants
-- a baseline to record: final wave, leaks, boss seconds, peak enemies/projectiles,
-- tower-damage distribution, gross money spent, and route refunds. Deterministic
-- (fixed seed + fixed cordon), so it doubles as the source of truth for the
-- regression thresholds asserted in tests/smoke_balance.lua.
--
--     luajit tests/baseline.lua
--
-- Not part of the smoke suite (it is a reporting tool, not an assertion suite).

package.path = "./?.lua;" .. package.path
require("tests.harness") -- installs the fake engine globals

local sim = require("lib.sim")
local maps = require("lib.maps")
local meta = require("lib.meta")
local helpers = require("tests.helpers")

local SEED, WAVES, STEP = 1234, 30, 30

local m = meta.default()

print(("baseline | standard | waves 1-%d | uniform pellet cordon step %d | seed %d"):format(WAVES, STEP, SEED))
print(
  ("%-11s %4s %4s %5s %5s %5s %7s %6s  %s"):format(
    "map",
    "wave",
    "surv",
    "leak",
    "pkEn",
    "pkPj",
    "spend",
    "rfund",
    "top damage"
  )
)

for _, name in ipairs(maps.ORDER) do
  local plan = helpers.map_cordon(m, name, { step = STEP })
  local r = sim.run({
    seed = SEED,
    map = name,
    mode = "standard",
    waves = WAVES,
    money = 99999,
    meta = m,
    plan = plan,
    affixes = false, -- affix-free baseline (M5)
  })
  local top = r.tower_damage.list[1]
  print(
    ("%-11s %4d %4s %5d %5d %5d %7d %6d  %s"):format(
      name,
      r.final_wave,
      r.survived and "yes" or "NO",
      r.leaks,
      r.peak_enemies,
      r.peak_proj,
      r.money_spent,
      r.route_refunds,
      top and (top.kind .. " " .. math.floor(top.damage)) or "-"
    )
  )

  -- boss seconds-to-clear, in wave order
  local bw = {}
  for w in pairs(r.boss_seconds) do
    bw[#bw + 1] = w
  end
  table.sort(bw)
  local parts = {}
  for i = 1, #bw do
    parts[i] = ("w%d=%.1fs"):format(bw[i], r.boss_seconds[bw[i]])
  end
  print("            bosses: " .. (#parts > 0 and table.concat(parts, "  ") or "-"))
end

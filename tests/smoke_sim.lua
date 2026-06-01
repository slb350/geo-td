-- lib/sim driver cases (V2-M0). Verifies the headless balance-lab driver is
-- deterministic, reports the metrics the roadmap asks for, surfaces (not hides)
-- rejected plan actions, and honors the run mode -- so tests/smoke_balance and
-- any balance investigation can trust its numbers. Run by smoke.lua via
-- M.run(check, near).

local sim = require("lib.sim")
local helpers = require("tests.helpers")
local meta = require("lib.meta")
local run_mod = require("lib.run")

local M = {}

function M.run(check, near)
  local m = meta.default()
  -- a uniform serpentine cordon, applied wave 1 with money to burn, so coverage
  -- (not affordability) is what is being measured
  local plan = helpers.map_cordon(m, "serpentine", { step = 34 })
  local function cordon(extra)
    local o = {
      seed = 4242,
      map = "serpentine",
      mode = "standard",
      waves = 6,
      money = 99999,
      meta = m,
      plan = plan,
    }
    if extra then
      for k, v in pairs(extra) do
        o[k] = v
      end
    end
    return o
  end

  -- determinism: identical (seed, map, mode, plan) -> identical metrics
  local a = sim.run(cordon())
  local b = sim.run(cordon())
  check(a.survived == b.survived and a.final_wave == b.final_wave, "sim is deterministic (survival + final wave)")
  check(a.leaks == b.leaks and a.kills == b.kills and a.score == b.score, "sim is deterministic (leaks/kills/score)")
  check(
    a.total_frames == b.total_frames and a.peak_enemies == b.peak_enemies and a.peak_proj == b.peak_proj,
    "sim is deterministic (frames + peaks)"
  )
  check(near(a.tower_damage.total, b.tower_damage.total), "sim is deterministic (tower damage total)")
  local same_records = (#a.records == #b.records)
  for i = 1, #a.records do
    if a.records[i].frames ~= b.records[i].frames or a.records[i].money_after ~= b.records[i].money_after then
      same_records = false
    end
  end
  check(same_records, "sim is deterministic (per-wave frames + money)")

  -- the metrics the roadmap requires are populated
  check(a.peak_enemies > 0, "sim reports a peak enemy count")
  check(a.peak_proj > 0, "sim reports a peak projectile count")
  check(a.total_frames > 0, "sim reports total simulated frames")
  check(a.money_curve[1] ~= nil and a.money_curve[6] ~= nil, "sim reports a per-wave money curve")
  check(a.tower_damage.total > 0 and #a.tower_damage.list > 0, "sim reports a tower-damage distribution")

  -- a cordon clears the wave-5 boss (Prism) and the boss wave is timed
  check(a.bosses_killed >= 1, "cordon clears the wave-5 boss")
  check(a.boss_seconds[5] ~= nil and a.boss_seconds[5] > 0, "boss wave records seconds-to-clear")

  -- a known-bad (empty) plan leaks out before wave 5
  local bad = sim.run({ seed = 1, map = "serpentine", mode = "standard", waves = 20, plan = {} })
  check(not bad.survived, "an empty plan does not survive")
  check(bad.final_wave <= 5, "an empty plan dies before wave 5")
  check(bad.leaks > 0, "an empty plan leaks enemies to the core")

  -- rejected plan actions are recorded, never silently dropped
  local err = sim.run({
    seed = 1,
    map = "serpentine",
    waves = 1,
    money = 99999,
    plan = {
      { wave = 1, place = { kind = "pellet", x = 150, y = 56 } }, -- on the path
      { wave = 1, upgrade = { tower = 9, id = "dmg" } }, -- no such tower
    },
  })
  check(#err.errors >= 2, "sim records rejected plan actions (on-path place + bad upgrade)")

  -- the run mode is honored: Boss Rush makes every wave (incl. wave 1) a boss
  local br = sim.run({
    seed = 7,
    map = "serpentine",
    mode = "boss_rush",
    waves = 1,
    money = 99999,
    plan = helpers.map_cordon(m, "serpentine", { step = 30 }),
  })
  check(br.boss_seconds[1] ~= nil, "boss_rush mode makes wave 1 a boss wave")

  -- a build plan actually changes the outcome vs the empty plan (towers matter)
  check(a.kills > bad.kills, "a cordon kills more than an empty plan")

  -- plan tower references are by STABLE id, so a sell that compacts run.towers
  -- can't silently shift a later upgrade onto the wrong tower (regression guard).
  local id_run = sim.run({
    seed = 1,
    map = "serpentine",
    waves = 2,
    money = 99999,
    plan = {
      { wave = 1, place = { kind = "pellet", x = 200, y = 150 } }, -- id 1
      { wave = 1, place = { kind = "pellet", x = 110, y = 95 } }, -- id 2
      { wave = 1, place = { kind = "pellet", x = 300, y = 40 } }, -- id 3
      { wave = 2, sell = { tower = 1 } }, -- selling id 1 compacts the array
      { wave = 2, upgrade = { tower = 2, id = "dmg" } }, -- must hit id 2, not the shifted id 3
    },
  })
  local t2, t3 = sim.tower_by_id(id_run.run, 2), sim.tower_by_id(id_run.run, 3)
  check(#id_run.errors == 0, "sim: sell-then-upgrade-by-id plan runs without errors")
  check(t2 and (t2.upgrades.dmg or 0) == 1, "sim: upgrade by stable id hits the intended tower after a sell")
  check(t3 and (t3.upgrades.dmg or 0) == 0, "sim: the array-shifted neighbor is NOT mis-upgraded")

  -- building during a wave: a `frame`-stamped action is combat-timed and re-applies
  -- mid-combat (not in a build phase). A frame-5 place adds a tower during wave 1.
  check(run_mod.is_combat_timed({ frame = 5, place = {} }), "a frame-stamped action is combat-timed")
  check(not run_mod.is_combat_timed({ place = {} }), "a frameless build action is not combat-timed")
  local base = sim.run({
    seed = 5,
    map = "serpentine",
    waves = 2,
    money = 99999,
    plan = { { wave = 1, place = { kind = "pellet", x = 200, y = 150 } } },
  })
  local mid = sim.run({
    seed = 5,
    map = "serpentine",
    waves = 2,
    money = 99999,
    plan = {
      { wave = 1, place = { kind = "pellet", x = 200, y = 150 } }, -- build phase
      { wave = 1, frame = 5, place = { kind = "pellet", x = 110, y = 95 } }, -- mid-combat
    },
  })
  check(#mid.errors == 0, "sim: a frame-stamped mid-wave place applies without error")
  check(#mid.run.towers == #base.run.towers + 1, "sim: the mid-wave placement adds a tower during combat")
end

return M

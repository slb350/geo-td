-- Replay / verification metadata (V2-M9): a deterministic snapshot of a run that
-- is enough to RECREATE it (seed + map + mode + the recorded build plan) and to
-- VERIFY its summary by replaying that plan through the headless sim. Given the
-- same run + report it returns identical metadata, so it doubles as a bug-report
-- artifact and a local "did this seed + build really reach wave N" check. No online
-- dependency.
--
-- The plan (run.log) is the player's build-action stream -- placements, sells,
-- upgrades, module sockets, and draft picks -- the SAME shape lib/sim replays.
-- M.verify re-runs it and is EXACT for runs whose decisions were all build-phase
-- actions + draft picks. A run that leaned on interactive route swaps, signed
-- contracts, or active abilities (orbital / discharge / call-early) is not fully
-- reproducible by the headless driver, so reproduced=false is expected and honest
-- there (the recorded contract_ids / affix_ids still document what happened).

local share = require("lib.share")
local sim   = require("lib.sim")

local M = {}
M.VERSION = 1

-- Build the snapshot from a run + its report (lib/report.build). Reads ids from the
-- run (path_name/mode.id/seed) for the share code and display stats from the report.
function M.snapshot(run, report)
  return {
    version    = M.VERSION,
    seed       = run.seed,
    map        = run.path_name,        -- map id (drives the share code)
    map_name   = report.map,           -- display name
    mode       = run.mode.id,          -- mode id
    mode_name  = report.mode,          -- display name, or nil for standard
    share      = share.encode({ seed = run.seed, map = run.path_name, mode = run.mode.id }),
    wave       = report.wave,
    bosses     = report.bosses_killed,
    final_boss = report.final_boss,
    kills      = report.kills,
    score      = report.score,
    contracts  = report.contracts,
    affixes    = report.affixes,
    arena_kills = report.arena_kills,
    -- the replayable build plan + the decision ids (what happened, not just counts)
    plan        = run.log,
    contract_ids = run.contract_history,
    affix_ids    = run.affix_history,
  }
end

-- Replay a snapshot's plan through the headless sim and report whether it
-- reproduces the recorded final wave. Deterministic (same snapshot -> same result).
-- See the module header for the exactness caveat (build-only runs reproduce; runs
-- that used interactive route/contract/ability events are not fully reproducible).
function M.verify(snap)
  local res = sim.run({
    seed = snap.seed, map = snap.map, mode = snap.mode,
    waves = snap.wave, plan = snap.plan,
  })
  return {
    reproduced    = res.final_wave == snap.wave,
    expected_wave = snap.wave,
    actual_wave   = res.final_wave,
    survived      = res.survived,
  }
end

-- A compact human-readable block (a bug report / brag artifact).
function M.format(snap)
  local lines = {
    "share " .. snap.share,
    "seed " .. snap.seed .. "   map " .. snap.map .. "   mode " .. snap.mode,
    "wave " .. snap.wave .. "   bosses " .. snap.bosses .. "   score " .. snap.score,
    "contracts " .. snap.contracts .. "   affixes " .. snap.affixes
      .. "   arena " .. snap.arena_kills,
  }
  return table.concat(lines, "\n")
end

return M

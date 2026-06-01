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
local sim = require("lib.sim")
local report = require("lib.report")

local M = {}
M.VERSION = 1

local SUMMARY_KEYS = {
  "wave",
  "bosses_killed",
  "kills",
  "leaked",
  "money_spent",
  "score",
  "contracts",
  "affixes",
  "arena_kills",
  "final_boss",
}

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do
    out[k] = copy(x)
  end
  return out
end

local function summary(report_row)
  local out = {}
  for i = 1, #SUMMARY_KEYS do
    local k = SUMMARY_KEYS[i]
    out[k] = report_row[k]
  end
  return out
end

-- Build the snapshot from a run + its report (lib/report.build). Reads ids from the
-- run (path_name/mode.id/seed) for the share code and display stats from the report.
function M.snapshot(run, run_report)
  local sum = summary(run_report)
  return {
    version = M.VERSION,
    seed = run.seed,
    map = run.path_name, -- map id (drives the share code)
    map_name = run_report.map, -- display name
    mode = run.mode.id, -- mode id
    mode_name = run_report.mode, -- display name, or nil for standard
    share = share.encode({ seed = run.seed, map = run.path_name, mode = run.mode.id }),
    wave = run_report.wave,
    bosses = run_report.bosses_killed,
    final_boss = run_report.final_boss,
    kills = run_report.kills,
    score = run_report.score,
    contracts = run_report.contracts,
    affixes = run_report.affixes,
    arena_kills = run_report.arena_kills,
    summary = sum,
    -- the replayable build plan + the decision ids (what happened, not just counts)
    plan = copy(run.log or {}),
    contract_ids = copy(run.contract_history or {}),
    affix_ids = copy(run.affix_history or {}),
  }
end

local function expected_summary(snap)
  if snap.summary then return snap.summary end
  return { wave = snap.wave }
end

local function compare_summary(exp, got)
  local mismatches = {}
  local ok = true
  for k, v in pairs(exp) do
    if got[k] ~= v then
      ok = false
      mismatches[k] = { expected = v, actual = got[k] }
    end
  end
  return ok, mismatches
end

-- Replay a snapshot's plan through the headless sim and report whether it
-- reproduces the recorded run summary. Deterministic (same snapshot -> same result).
function M.verify(snap)
  local res = sim.run({
    seed = snap.seed,
    map = snap.map,
    mode = snap.mode,
    waves = snap.wave,
    plan = snap.plan,
  })
  local actual = summary(report.build(res.run))
  local exp = expected_summary(snap)
  local summary_ok, mismatches = compare_summary(exp, actual)
  local no_errors = #res.errors == 0
  return {
    reproduced = summary_ok and no_errors,
    summary_matches = summary_ok,
    expected_wave = snap.wave,
    actual_wave = res.final_wave,
    survived = res.survived,
    expected = exp,
    actual = actual,
    mismatches = mismatches,
    errors = res.errors,
  }
end

-- A compact human-readable block (a bug report / brag artifact).
function M.format(snap)
  local lines = {
    "share " .. snap.share,
    "seed " .. snap.seed .. "   map " .. snap.map .. "   mode " .. snap.mode,
    "wave " .. snap.wave .. "   bosses " .. snap.bosses .. "   score " .. snap.score,
    "contracts " .. snap.contracts .. "   affixes " .. snap.affixes .. "   arena " .. snap.arena_kills,
  }
  return table.concat(lines, "\n")
end

return M

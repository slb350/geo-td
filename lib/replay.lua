-- Replay / verification metadata (V2-M9): a deterministic snapshot of a run that
-- is enough to RECREATE it (seed + map + mode, as a share code) and to VERIFY its
-- summary (wave/bosses/score/contracts/affixes). Pure -- given the same run +
-- report it returns identical metadata -- so it doubles as a bug-report artifact
-- and a local "did this seed really reach wave N" check. No online dependency.

local share = require("lib.share")

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

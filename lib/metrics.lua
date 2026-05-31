-- Balance-lab metrics (V2-M0): pure helpers that turn a finished run and the
-- per-wave samples collected by lib/sim into structured, comparable numbers.
-- No engine/gfx/run mutation -- every function reads its inputs and returns a
-- fresh table, so the balance suite can assert on them deterministically and a
-- baseline tool can print them.

local C = require("lib.const")

local M = {}

-- The game's fixed combat step. scenes/game.lua's accumulator and lib/sim both
-- advance combat at exactly this dt (one source: C.SIM_DT), so frame counts
-- convert to wall-clock seconds the way the real game feels them, and balance
-- numbers match real play.
M.DT = C.SIM_DT

-- Seconds of simulated combat for a frame count.
function M.seconds(frames)
  return frames * M.DT
end

-- Applied-damage distribution across a run's towers, summed by kind (several
-- towers of one kind merge), sorted by damage desc then kind for a stable order.
-- Returns { list = { { kind, damage }, ... }, total = <number> }. Reads the same
-- run.tower_stats the M1 run report does, so the two never disagree on totals.
function M.tower_damage(run)
  local by_kind, total = {}, 0
  local stats = run.tower_stats or {}
  for _, s in pairs(stats) do
    local dmg = s.damage or 0
    if dmg > 0 then
      by_kind[s.kind] = (by_kind[s.kind] or 0) + dmg
      total = total + dmg
    end
  end
  local list = {}
  for kind, dmg in pairs(by_kind) do
    list[#list + 1] = { kind = kind, damage = dmg }
  end
  table.sort(list, function(a, b)
    if a.damage ~= b.damage then return a.damage > b.damage end
    return a.kind < b.kind
  end)
  return { list = list, total = total }
end

-- Reduce the sim's per-wave records into run-level rollups. Each record is
--   { wave, frames, peak_enemies, peak_proj, leaks, money_after, boss }
-- (boss = true on a boss wave). Returns peak enemy/projectile high-water marks,
-- the total simulated frames, a wave -> end-of-wave-money curve, and a
-- boss-wave -> seconds-to-clear map.
function M.rollup(records)
  local out = {
    peak_enemies = 0,
    peak_proj = 0,
    total_frames = 0,
    money_curve = {},
    boss_seconds = {},
  }
  for i = 1, #records do
    local r = records[i]
    if r.peak_enemies > out.peak_enemies then out.peak_enemies = r.peak_enemies end
    if r.peak_proj > out.peak_proj then out.peak_proj = r.peak_proj end
    out.total_frames = out.total_frames + r.frames
    out.money_curve[r.wave] = r.money_after
    if r.boss then out.boss_seconds[r.wave] = M.seconds(r.frames) end
  end
  return out
end

return M

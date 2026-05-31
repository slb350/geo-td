-- Run report: aggregates a finished run into a flat, string-keyed stats table
-- for the gameover panel. Pure (no engine/gfx calls), so it is unit-testable
-- headlessly and reusable later (e.g. challenge-mode result screens). The raw
-- counters it reads are instrumented across lib/* during a run:
--   run.kills / run.score / run.bosses_killed  -- enemy.kill / boss.kill
--   run.leaked                                 -- enemy.update / boss.update
--   run.money_spent                            -- tower.place / run.orbital_strike
--   run.tower_stats = { [id] = {kind, damage} } -- projectile applied-damage credit

local powerup = require("lib.powerup")

local M = {}

-- Most-frequent powerup key; ties break to the earliest acquired. Returns nil
-- for an empty/absent list.
local function favorite_powerup(list)
  if not list or #list == 0 then return nil end
  local count, first = {}, {}
  for i = 1, #list do
    local k = list[i]
    count[k] = (count[k] or 0) + 1
    if first[k] == nil then first[k] = i end
  end
  local best, best_n, best_first
  for i = 1, #list do
    local k = list[i]
    local n = count[k]
    if best == nil or n > best_n or (n == best_n and first[k] < best_first) then
      best, best_n, best_first = k, n, first[k]
    end
  end
  return best
end

-- Highest applied-damage tower across run.tower_stats. Survives sells because
-- the stat lives on the run keyed by tower id, not on the tower table. Returns
-- nil when no tower has dealt damage.
local function top_tower(stats)
  if not stats then return nil end
  local best_kind, best_dmg
  for _, s in pairs(stats) do
    if best_dmg == nil or s.damage > best_dmg then
      best_kind, best_dmg = s.kind, s.damage
    end
  end
  if not best_kind or best_dmg <= 0 then return nil end
  return { kind = best_kind, damage = best_dmg }
end

function M.build(run)
  local fav = favorite_powerup(run.powerups)
  return {
    seed          = run.seed,        -- for replay/share metadata (M9)
    map           = run.map_name,
    wave          = run.final_wave or run.wave_index,
    bosses_killed = run.bosses_killed or 0,
    kills         = run.kills or 0,
    leaked        = run.leaked or 0,
    money_spent   = run.money_spent or 0,
    score         = run.score or 0,
    top_tower     = top_tower(run.tower_stats),
    favorite      = fav,
    favorite_name = fav and powerup.DEFS[fav] and powerup.DEFS[fav].name or nil,
    -- challenge mode name, or nil for a standard run (so default runs show nothing)
    mode          = (run.mode and run.mode.id ~= "standard") and run.mode.name or nil,
    -- M3 economy: contracts signed + bank shards earned (nil/0 when unused)
    contracts     = run.contract_history and #run.contract_history or 0,
    bank_shards   = run.bank_shards or 0,
    -- M5: number of affix-bearing waves survived
    affixes       = run.affix_history and #run.affix_history or 0,
    -- M6: boss-arena objects destroyed + whether the final boss was reached
    arena_kills   = run.arena_kills or 0,
    final_boss    = run.final_boss_reached or false,
  }
end

return M

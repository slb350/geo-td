-- Persistent meta-progression: currency, unlocks, records. Serialized via
-- usagi.save/load (JSON, namespaced by game_id). Kept strictly string-keyed
-- so it satisfies the save serializer's shape rules.

local C    = require("lib.const")
local maps = require("lib.maps")

local M = {}
local SAVE_VERSION = 1

function M.default()
  return {
    version = SAVE_VERSION,
    currency = 0,
    best_wave = 0,
    total_runs = 0,
    unlocks = { tower_rail = false, tower_flak = false, start_bonus = false },
    map_unlocked = { [maps.first] = true },  -- easiest map open from the start
    map_best = {},                           -- per-map best wave reached
  }
end

function M.load()
  local data = usagi.load()
  if type(data) ~= "table" or data.version ~= SAVE_VERSION then
    return M.default()
  end
  data.unlocks = data.unlocks or {}
  if data.unlocks.tower_rail == nil then data.unlocks.tower_rail = false end
  if data.unlocks.tower_flak == nil then data.unlocks.tower_flak = false end
  if data.unlocks.start_bonus == nil then data.unlocks.start_bonus = false end
  data.map_unlocked = data.map_unlocked or {}
  data.map_unlocked[maps.first] = true       -- first map is always available
  data.map_best = data.map_best or {}
  return data
end

function M.is_map_unlocked(meta, name)
  return meta.map_unlocked[name] == true
end

function M.save(meta)
  usagi.save(meta)
end

-- Purchasable permanent unlocks.
M.SHOP = {
  { id = "tower_rail",  name = "Rail Tower",   desc = "Long-range anti-air sniper", cost = 16 },
  { id = "tower_flak",  name = "Flak Cannon",  desc = "Anti-air: shreds flyers",    cost = 14 },
  { id = "start_bonus", name = "Head Start",   desc = "+50 money, +5 lives",        cost = 18 },
}

function M.can_buy(meta, id)
  for i = 1, #M.SHOP do
    local it = M.SHOP[i]
    if it.id == id then
      return meta.currency >= it.cost and not meta.unlocks[id]
    end
  end
  return false
end

function M.buy(meta, id)
  for i = 1, #M.SHOP do
    local it = M.SHOP[i]
    if it.id == id and meta.currency >= it.cost and not meta.unlocks[id] then
      meta.currency = meta.currency - it.cost
      meta.unlocks[id] = true
      M.save(meta)
      return true
    end
  end
  return false
end

-- Award currency for a finished run, update records, and (when a map was
-- played) record its best wave and unlock the next harder map on a wave >=
-- UNLOCK_WAVE finish. Persists. Returns: award, newly_unlocked_map_or_nil.
function M.finish_run(meta, wave_reached, bosses_killed, map_name, bank_shards)
  local award = wave_reached * C.META_PER_WAVE + (bosses_killed or 0) * 8
    + (bank_shards or 0) * C.BANK_SHARD_VALUE
  meta.currency = meta.currency + award
  meta.total_runs = meta.total_runs + 1
  if wave_reached > meta.best_wave then meta.best_wave = wave_reached end

  local newly_unlocked
  if map_name then
    if wave_reached > (meta.map_best[map_name] or 0) then
      meta.map_best[map_name] = wave_reached
    end
    if wave_reached >= maps.UNLOCK_WAVE then
      local nxt = maps.next(map_name)
      if nxt and not meta.map_unlocked[nxt] then
        meta.map_unlocked[nxt] = true
        newly_unlocked = nxt
      end
    end
  end

  M.save(meta)
  return award, newly_unlocked
end

return M

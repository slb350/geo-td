-- Persistent meta-progression: currency, unlocks, records. Serialized via
-- usagi.save/load (JSON, namespaced by game_id). Kept strictly string-keyed
-- so it satisfies the save serializer's shape rules.

local C = require("lib.const")

local M = {}
local SAVE_VERSION = 1

function M.default()
  return {
    version = SAVE_VERSION,
    currency = 0,
    best_wave = 0,
    total_runs = 0,
    unlocks = { tower_rail = false, start_bonus = false },
  }
end

function M.load()
  local data = usagi.load()
  if type(data) ~= "table" or data.version ~= SAVE_VERSION then
    return M.default()
  end
  data.unlocks = data.unlocks or {}
  if data.unlocks.tower_rail == nil then data.unlocks.tower_rail = false end
  if data.unlocks.start_bonus == nil then data.unlocks.start_bonus = false end
  return data
end

function M.save(meta)
  usagi.save(meta)
end

-- Purchasable permanent unlocks.
M.SHOP = {
  { id = "tower_rail",  name = "Rail Tower", desc = "Long-range anti-air sniper", cost = 16 },
  { id = "start_bonus", name = "Head Start", desc = "+50 money, +5 lives",        cost = 18 },
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

-- Award currency for a finished run, update records, persist. Returns award.
function M.finish_run(meta, wave_reached, bosses_killed)
  local award = wave_reached * C.META_PER_WAVE + (bosses_killed or 0) * 8
  meta.currency = meta.currency + award
  meta.total_runs = meta.total_runs + 1
  if wave_reached > meta.best_wave then meta.best_wave = wave_reached end
  M.save(meta)
  return award
end

return M

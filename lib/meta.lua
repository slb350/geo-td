-- Persistent meta-progression: currency, unlocks, records. Serialized via
-- usagi.save/load (JSON, namespaced by game_id). Kept strictly string-keyed
-- so it satisfies the save serializer's shape rules.

local C = require("lib.const")
local maps = require("lib.maps")
local settings = require("lib.settings")

local M = {}
local SAVE_VERSION = 2

function M.default()
  return {
    version = SAVE_VERSION,
    currency = 0,
    best_wave = 0,
    total_runs = 0,
    unlocks = { tower_rail = false, tower_flak = false, start_bonus = false },
    map_unlocked = { [maps.first] = true }, -- easiest map open from the start
    map_best = {}, -- per-map best wave reached
    -- V2-M7 meta progression:
    bank_shards = 0, -- premium currency earned from wave contracts
    mastery = {}, -- [node id] = true (permanent run buffs)
    badges = {}, -- [badge id] = true (achievements)
    contract_board = {}, -- active meta-contract ids (the 3-goal board)
    completed_contracts = {}, -- [meta-contract id] = true (done at least once)
    daily = {}, -- { day = <n>, done = bool, best = wave }
    settings = settings.defaults(), -- V2-M9 comfort/accessibility toggles
  }
end

-- Ensure every field exists on a loaded save (covers a v1->v2 migration and any
-- partially-written v2 save). Never drops existing currency/unlocks/records.
local function backfill(data)
  -- core fields (present since v1, but guard a truncated/hand-edited v2 save so a
  -- missing one can't crash finish_run's arithmetic or the menu's concatenation)
  data.currency = data.currency or 0
  data.best_wave = data.best_wave or 0
  data.total_runs = data.total_runs or 0
  data.unlocks = data.unlocks or {}
  if data.unlocks.tower_rail == nil then data.unlocks.tower_rail = false end
  if data.unlocks.tower_flak == nil then data.unlocks.tower_flak = false end
  if data.unlocks.start_bonus == nil then data.unlocks.start_bonus = false end
  data.map_unlocked = data.map_unlocked or {}
  data.map_unlocked[maps.first] = true -- first map is always available
  data.map_best = data.map_best or {}
  data.bank_shards = data.bank_shards or 0
  data.mastery = data.mastery or {}
  data.badges = data.badges or {}
  data.contract_board = data.contract_board or {}
  data.completed_contracts = data.completed_contracts or {}
  data.daily = data.daily or {}
  data.settings = settings.fill(data.settings) -- add any missing setting (M9 migration)
  return data
end

function M.load()
  local data = usagi.load()
  if type(data) ~= "table" then return M.default() end
  if data.version == 1 then
    data.version = SAVE_VERSION -- migrate v1 -> v2 (fields added by backfill)
  elseif data.version ~= SAVE_VERSION then
    return M.default() -- unknown/future version: safe default
  end
  return backfill(data)
end

function M.is_map_unlocked(meta, name)
  return meta.map_unlocked[name] == true
end

function M.save(meta)
  usagi.save(meta)
end

-- Purchasable permanent unlocks.
M.SHOP = {
  { id = "tower_rail", name = "Rail Tower", desc = "Long-range anti-air sniper", cost = 16 },
  { id = "tower_flak", name = "Flak Cannon", desc = "Anti-air: shreds flyers", cost = 14 },
  { id = "start_bonus", name = "Head Start", desc = "+50 money, +5 lives", cost = 18 },
}

function M.can_buy(meta, id)
  for i = 1, #M.SHOP do
    local it = M.SHOP[i]
    if it.id == id then return meta.currency >= it.cost and not meta.unlocks[id] end
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
  meta.currency = meta.currency + award
  meta.bank_shards = (meta.bank_shards or 0) + (bank_shards or 0) -- premium currency (M7)
  meta.total_runs = meta.total_runs + 1
  if wave_reached > meta.best_wave then meta.best_wave = wave_reached end

  local newly_unlocked
  if map_name then
    if wave_reached > (meta.map_best[map_name] or 0) then meta.map_best[map_name] = wave_reached end
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

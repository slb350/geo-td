-- In-run upgrade drafts with Common / Uncommon / Rare rarities. Each draft card
-- is { key, rarity }; rarity scales the effect magnitude and gates a few strong
-- kinds (crit/interest are uncommon+, bastion is rare-only). Defs in
-- data/powerups.json. `apply` folds the scaled effect into run.mods / run.lives.

local pal = require("lib.palette")

local DEFS = usagi.read_json("powerups.json")

local M = {}
M.DEFS = DEFS

-- index 1..3 = Common / Uncommon / Rare
M.RARITY = {
  { name = "Common",   mult = 1.0, weight = 62, color = "LIGHT_GRAY" },
  { name = "Uncommon", mult = 1.7, weight = 30, color = "GREEN" },
  { name = "Rare",     mult = 2.6, weight = 8,  color = "BLUE" },
}

M.KEYS = {}
for k in pairs(DEFS) do M.KEYS[#M.KEYS + 1] = k end
table.sort(M.KEYS)

local function roll_rarity(rng)
  local total = 0
  for i = 1, #M.RARITY do total = total + M.RARITY[i].weight end
  local x = rng:range(0, total)
  local acc = 0
  for i = 1, #M.RARITY do
    acc = acc + M.RARITY[i].weight
    if x < acc then return i end
  end
  return 1
end

-- Draft n distinct cards. Each card = { key = <string>, rarity = 1..3 }. With
-- `chaos` (the Draft Chaos mode), each card's rarity is bumped one tier (capped
-- at Rare), so the whole draft skews powerful.
function M.draft(rng, n, chaos)
  local out, used, attempts = {}, {}, 0
  while #out < n and attempts < 200 do
    attempts = attempts + 1
    local ri = roll_rarity(rng)
    if chaos then ri = math.min(#M.RARITY, ri + 1) end
    local pool = {}
    for i = 1, #M.KEYS do
      local k = M.KEYS[i]
      if (DEFS[k].min_rarity or 1) <= ri and not used[k] then
        pool[#pool + 1] = k
      end
    end
    if #pool > 0 then
      local key = pool[rng:int(1, #pool)]
      used[key] = true
      out[#out + 1] = { key = key, rarity = ri }
    end
  end
  return out
end

function M.color(card)
  return pal.resolve(M.RARITY[card.rarity].color)
end

function M.rarity_name(card)
  return M.RARITY[card.rarity].name
end

-- Human-readable effect for a card, magnitude scaled by rarity.
function M.describe(card)
  local d = DEFS[card.key]
  local v = d.value * M.RARITY[card.rarity].mult
  local k = d.kind
  if k == "add_lives" then
    return ("+%d lives"):format(math.floor(v + 0.5))
  elseif k == "life_per_wave" then
    return ("+%d life / wave"):format(math.floor(v + 0.5))
  elseif k == "cost_mult" then
    return ("-%d%% tower cost"):format(math.floor(v * 100 + 0.5))
  elseif k == "crit_chance" then
    return ("+%d%% crit"):format(math.floor(v * 100 + 0.5))
  elseif k == "interest" then
    return ("+%d%% interest / wave"):format(math.floor(v * 100 + 0.5))
  elseif k == "pierce" then
    return "shots pierce +1 enemy"
  elseif k == "ricochet" then
    return "shots ricochet +1"
  elseif k == "ring" then
    return "splash leaves a dmg ring"
  elseif k == "flyer_burst" then
    return "flyers burst on death"
  elseif k == "brittle" then
    return ("+%d%% dmg to slowed"):format(math.floor(v * 100 + 0.5))
  else
    return ("+%d%% %s"):format(math.floor(v * 100 + 0.5), d.desc)
  end
end

function M.apply(run, card)
  local d = DEFS[card.key]
  if not d then return end
  local v = d.value * M.RARITY[card.rarity].mult
  local mods = run.mods
  local k = d.kind
  if k == "dmg_mult" then
    mods.dmg_mult = mods.dmg_mult + v
  elseif k == "rate_mult" then
    mods.rate_mult = mods.rate_mult + v
  elseif k == "range_mult" then
    mods.range_mult = mods.range_mult + v
  elseif k == "proj_mult" then
    mods.proj_mult = mods.proj_mult + v
  elseif k == "bounty_mult" then
    mods.bounty_mult = mods.bounty_mult + v
  elseif k == "splash_mult" then
    mods.splash_mult = mods.splash_mult + v
  elseif k == "crit_chance" then
    mods.crit_chance = math.min(0.9, mods.crit_chance + v)
  elseif k == "interest" then
    mods.interest = mods.interest + v
  elseif k == "cost_mult" then
    mods.cost_mult = math.max(0.4, mods.cost_mult - v)
  elseif k == "add_lives" then
    run.lives = run.lives + math.floor(v + 0.5)
  elseif k == "life_per_wave" then
    mods.life_per_wave = mods.life_per_wave + math.floor(v + 0.5)
  -- behavior cards (M2): pierce/ricochet are flat +1 extra-hit unlocks (gated by
  -- min_rarity, magnitude not rarity-scaled); brittle/ring/flyer_burst scale.
  elseif k == "pierce" then
    mods.pierce = mods.pierce + 1
  elseif k == "ricochet" then
    mods.ricochet = mods.ricochet + 1
  elseif k == "brittle" then
    mods.brittle = mods.brittle + v
  elseif k == "ring" then
    mods.ring = mods.ring + v
  elseif k == "flyer_burst" then
    mods.flyer_burst = mods.flyer_burst + v
  end
  run.powerups[#run.powerups + 1] = card.key
end

return M

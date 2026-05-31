-- Mastery tracks (V2-M7): a compact tree of permanent run buffs bought with meta
-- progression. Two costs gate a node: `cost` in bank currency (the plentiful
-- run-award currency, giving it a long-term sink past the three shop unlocks) and
-- an optional `shards` premium cost (bank shards earned from wave/meta contracts).
-- A purchase only flips meta.mastery[id] = true; persistence is the caller's job
-- (kept pure so this module depends on nothing but its data, like lib/modes).
--
-- Effects are DERIVED, applied once at run.new via M.apply: additive into the run's
-- starting money/lives and run.mods (interest/dmg/crit/bounty). meta.default()'s
-- mastery is empty, so a default run -- and every balance fixture -- is byte-identical.

local DEFS = usagi.read_json("mastery.json")

local M = {}
M.DEFS = DEFS

-- Stable display/iteration order, grouped by track (Builder / Arsenal / Survival).
M.ORDER = {
  "builder_economy", "builder_interest",
  "arsenal_caliber", "arsenal_precision",
  "survival_bulwark", "survival_salvage",
}

function M.owned(meta, id)
  return meta.mastery and meta.mastery[id] == true
end

-- Can this node be bought? Rejects an unknown id, an already-owned node, missing
-- bank currency, or (for a premium node) missing bank shards.
function M.can_buy(meta, id)
  local d = DEFS[id]
  if not d or M.owned(meta, id) then return false end
  if (meta.currency or 0) < d.cost then return false end
  if d.shards and (meta.bank_shards or 0) < d.shards then return false end
  return true
end

-- Deduct both costs and mark the node owned. Pure: the caller persists (meta.save).
function M.buy(meta, id)
  if not M.can_buy(meta, id) then return false end
  local d = DEFS[id]
  meta.currency = meta.currency - d.cost
  if d.shards then meta.bank_shards = meta.bank_shards - d.shards end
  meta.mastery = meta.mastery or {}
  meta.mastery[id] = true
  return true
end

-- Fold every owned node's effect into a fresh run. Additive + commutative, so the
-- pairs() iteration order is irrelevant. Called from run.new after run.mods exists
-- and after the challenge-mode lives override (a mode that FIXES lives -- e.g. One
-- Life -- ignores the Bulwark life bonus so the mode invariant holds).
function M.apply(run, meta)
  local owned = meta.mastery
  if not owned then return end
  for id, on in pairs(owned) do
    local d = on and DEFS[id]
    if d then
      local e = d.effect
      local k = e.kind
      if k == "money" then run.money = run.money + e.value
      elseif k == "lives" then
        if not run.mode.lives then run.lives = run.lives + e.value end
      elseif k == "interest" then run.mods.interest = run.mods.interest + e.value
      elseif k == "dmg" then run.mods.dmg_mult = run.mods.dmg_mult + e.value
      elseif k == "crit" then run.mods.crit_chance = run.mods.crit_chance + e.value
      elseif k == "bounty" then run.mods.bounty_mult = run.mods.bounty_mult + e.value
      end
    end
  end
end

return M

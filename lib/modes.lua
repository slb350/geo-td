-- Challenge modes (M6): rule-variant runs defined as small config deltas. A
-- mode is chosen on the select screen and stored on the run (run.mode); the
-- relevant systems read its flags at a few decision points (run.new lives,
-- run.can_orbital, wave boss/scaling/pool, tower.available). The default
-- "standard" mode carries no deltas, so every default-mode code path and test
-- behaves exactly as before -- modes never leak into a normal run.

local M = {}

M.DEFAULT = "standard"

-- Each mode is a flat table of deltas/flags read by the systems above.
M.LIST = {
  { id = "standard", name = "Standard", desc = "The classic climb." },
  { id = "one_life", name = "One Life", desc = "Start with a single life.", lives = 1 },
  { id = "no_orbital", name = "No Orbital", desc = "No panic button -- towers only.", no_orbital = true },
  { id = "no_rail", name = "No Rail", desc = "The Rail sniper is disabled.", no_rail = true },
  { id = "boss_rush", name = "Boss Rush", desc = "Every wave is a boss.", boss_rush = true },
  { id = "flyer_swarm", name = "Flyer Swarm", desc = "The skies are thick with flyers.", flyer_bias = true },
  { id = "hardcore", name = "Hardcore", desc = "Difficulty tiers spike harder.", hardcore = true },
  { id = "draft_chaos", name = "Draft Chaos", desc = "Upgrade drafts skew to high rarity.", draft_chaos = true },
}

M.ORDER = {}
local BY_ID = {}
for i = 1, #M.LIST do
  M.ORDER[i] = M.LIST[i].id
  BY_ID[M.LIST[i].id] = M.LIST[i]
end

-- The mode table for an id (falls back to standard for nil/unknown).
function M.get(id)
  return BY_ID[id] or BY_ID[M.DEFAULT]
end

-- Next mode id in the cycle (for the select-screen picker).
function M.next(id)
  for i = 1, #M.ORDER do
    if M.ORDER[i] == id then return M.ORDER[i % #M.ORDER + 1] end
  end
  return M.ORDER[1]
end

return M

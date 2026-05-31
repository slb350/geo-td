-- Targeting eligibility, shared by tower acquisition and the projectile chain so
-- a chained shot (pierce/ricochet) obeys the same air/ground rule as the tower
-- that fired it. A leaf module (no requires) so both tower.lua and
-- projectile.lua can use it without a require cycle.

local M = {}

-- Can a tower (def.targets: "all" / "air" / "ground") hit this entity? Keyed off
-- the entity's `fly` flag (bosses are ground).
function M.can_hit(def, e)
  local t = def.targets or "ground"
  if e.fly then return t == "all" or t == "air" end
  return t == "all" or t == "ground"
end

return M

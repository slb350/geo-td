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

-- Is this enemy visible to acquisition? False for stealthed (aura veil / affix
-- cloak) and untargetable arena objects (Specter anchors). Shared by tower
-- acquisition AND the projectile pierce/ricochet chain so they can't drift -- a
-- chained shot skips exactly what the firing tower would.
function M.targetable(e)
  return not e.aura_stealth and not e.affix_stealth and not (e.arena and e.arena.untargetable)
end

return M

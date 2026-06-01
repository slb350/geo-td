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
--
-- An untargetable arena object (a Specter phase anchor) is never a valid target
-- and is never uncloaked by detection -- its protection outranks both. The single
-- predicate, shared by targetable() AND tower.reveal so the rule sits in one place.
function M.arena_untargetable(e)
  return e.arena ~= nil and e.arena.untargetable == true
end

-- `e.revealed` (set each frame by tower.reveal for a detector's anti-veil pass)
-- overrides stealth, so a Pellet uncloaks a veiled pack for every tower. It does
-- NOT override arena untargetability: a Specter phase anchor stays protected even
-- if a detector's radius covers it (the reveal pass never marks anchors anyway).
function M.targetable(e)
  if M.arena_untargetable(e) then return false end
  if e.revealed then return true end
  return not e.aura_stealth and not e.affix_stealth
end

return M

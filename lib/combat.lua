-- Shared damage + regeneration mechanics for any entity with optional shield /
-- armor / regen fields (enemies and bosses both use these). Keeps the
-- shield→armor→hp resolution and the regen tick in one place so the two callers
-- can't drift apart. Each entity sets its own `shield_hit_delay`.

local M = {}

-- Apply `dmg` through the shield pool, then armor, then hp. Returns true if the
-- entity's hp dropped to 0 (caller handles death/fx/split).
function M.apply_damage(ent, dmg)
  local remaining = dmg
  if ent.shield and ent.shield > 0 then
    local absorbed = math.min(ent.shield, remaining)
    ent.shield = ent.shield - absorbed
    remaining = remaining - absorbed
    ent.shield_hit_t = ent.shield_hit_delay or 0.5
  end
  if remaining > 0 then
    local real = remaining - (ent.armor or 0)
    if real < 1 then real = 1 end
    ent.hp = ent.hp - real
  end
  return ent.hp <= 0
end

-- Tick hp regen and shield regen. Shield regen pauses for `shield_hit_delay`
-- seconds after the pool last took a hit.
function M.tick_regen(ent, dt)
  if ent.regen and ent.regen > 0 and ent.hp < ent.maxhp then
    ent.hp = math.min(ent.maxhp, ent.hp + ent.regen * dt)
  end
  if ent.shield_max and ent.shield_max > 0 then
    if ent.shield_hit_t and ent.shield_hit_t > 0 then
      ent.shield_hit_t = ent.shield_hit_t - dt
    elseif ent.shield < ent.shield_max then
      ent.shield = math.min(ent.shield_max, ent.shield + ent.shield_regen * dt)
    end
  end
end

return M

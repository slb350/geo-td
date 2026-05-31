-- Enemy formation auras (M4): some enemies buff their neighbors, creating
-- "kill the buffer" target puzzles. Buffs are DERIVED -- recomputed from scratch
-- every tick (aura.update, called at the top of enemy.update) and never mutate
-- base stats, so a buff vanishes the moment its emitter dies or the target
-- leaves the radius. Consumers read the e.aura_* fields:
--   aura_speed   (mult, strongest wins) -- enemy.update movement
--   aura_armor   (additive)             -- combat.apply_damage
--   aura_regen   (additive)             -- combat.tick_regen
--   aura_shield  (pool, strongest wins) -- combat.apply_damage (absorbed first;
--                                          refreshed each tick = a maintained ward)
--   aura_stealth (flag)                 -- tower.acquire skips stealthed enemies
-- An emitter never buffs itself, so a stealth veil hides its pack while staying
-- targetable. Data: an enemy def's `aura = { kind, radius, value }`.

local M = {}

-- Reset one enemy's derived aura fields to their no-buff defaults.
function M.reset(e)
  e.aura_speed = 1
  e.aura_armor = 0
  e.aura_regen = 0
  e.aura_shield = 0
  e.aura_stealth = false
end

local function apply(o, kind, value)
  if kind == "speed" then o.aura_speed = math.max(o.aura_speed, value)
  elseif kind == "armor" then o.aura_armor = o.aura_armor + value
  elseif kind == "regen" then o.aura_regen = o.aura_regen + value
  elseif kind == "shield" then o.aura_shield = math.max(o.aura_shield, value)
  elseif kind == "stealth" then o.aura_stealth = true end
end

-- One O(n * emitters) pass: reset every enemy, then each living emitter buffs the
-- enemies within its radius (never itself).
function M.update(run)
  local list = run.enemies
  local n = list.n
  for i = 1, n do M.reset(list[i]) end
  for i = 1, n do
    local em = list[i]
    local a = em.def.aura
    if a and not em.dead then
      local r2 = a.radius * a.radius
      for j = 1, n do
        if j ~= i then
          local o = list[j]
          if not o.dead then
            local dx, dy = o.x - em.x, o.y - em.y
            if dx * dx + dy * dy <= r2 then apply(o, a.kind, a.value) end
          end
        end
      end
    end
  end
end

function M.draw(run)
  local list = run.enemies
  for i = 1, list.n do
    local em = list[i]
    local a = em.def.aura
    if a and not em.dead then
      -- faint buff-zone ring (dim; the CRT bloom lifts it off the field)
      gfx.circ(em.x, em.y, a.radius, gfx.COLOR_DARK_PURPLE)
    end
  end
end

return M

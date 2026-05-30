-- Projectiles: pooled, homing shots. Nothing references a projectile, so the
-- pool recycles tables freely. Each homes onto its target enemy; if that
-- enemy dies or leaks before impact the shot whiffs and expires. On impact it
-- applies direct damage, optional splash (area) damage, and optional slow.

local enemy = require("lib.enemy")
local boss  = require("lib.boss")
local fx    = require("lib.fx")

local M = {}

-- opts: damage, speed, radius, color, splash_radius?, slow_factor?, slow_time?
function M.spawn(run, x, y, target, opts)
  local list = run.projectiles
  list.n = list.n + 1
  local p = list[list.n]
  if not p then p = {}; list[list.n] = p end
  p.x, p.y = x, y
  p.target = target
  p.damage = opts.damage
  p.speed = opts.speed
  p.radius = opts.radius or 2
  p.color = opts.color
  p.splash = opts.splash_radius or 0
  p.slow_factor = opts.slow_factor
  p.slow_time = opts.slow_time
  p.life = 2.0
  p.dead = false
  return p
end

local function resolve_hit(run, p)
  local t = p.target
  if t.is_boss then
    boss.hurt(run, p.damage)
  else
    enemy.damage(run, t, p.damage)
    if p.slow_factor then
      enemy.slow(t, p.slow_factor, p.slow_time)
    end
  end
  fx.hit_sfx()
  if p.splash > 0 then
    local r2 = p.splash * p.splash
    local list = run.enemies
    for i = 1, list.n do
      local e = list[i]
      if e ~= t and not e.dead then
        local dx, dy = e.x - p.x, e.y - p.y
        if dx * dx + dy * dy <= r2 then
          enemy.damage(run, e, p.damage)
          if p.slow_factor then enemy.slow(e, p.slow_factor, p.slow_time) end
        end
      end
    end
  end
end

function M.update(run, dt)
  local list = run.projectiles
  local i = 1
  while i <= list.n do
    local p = list[i]
    local t = p.target
    p.life = p.life - dt
    if p.life <= 0 or not t or t.dead or t.leaked then
      p.dead = true
    else
      local dx, dy = t.x - p.x, t.y - p.y
      local dist = math.sqrt(dx * dx + dy * dy)
      local step = p.speed * dt
      local reach = p.radius + (t.size or 0)
      if dist <= reach or dist <= step then
        resolve_hit(run, p)
        p.dead = true
      else
        p.x = p.x + (dx / dist) * step
        p.y = p.y + (dy / dist) * step
      end
    end
    if p.dead then
      list[i] = list[list.n]; list[list.n] = p; list.n = list.n - 1
    else
      i = i + 1
    end
  end
end

function M.draw(run)
  local list = run.projectiles
  for i = 1, list.n do
    local p = list[i]
    gfx.circ_fill(p.x, p.y, p.radius, p.color)
  end
end

return M

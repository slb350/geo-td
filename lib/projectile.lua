-- Projectiles: pooled, homing shots. Nothing references a projectile, so the
-- pool recycles tables freely. Each homes onto its target enemy; if that enemy
-- dies or leaks before impact the shot whiffs and expires. On impact it applies
-- direct damage, optional splash (area) damage, and optional slow.
-- Behavior cards (M2) let a shot "chain" to extra targets (pierce/ricochet),
-- deal extra damage to slowed targets (brittle), and leave a splash ring.

local enemy   = require("lib.enemy")
local boss    = require("lib.boss")
local fx      = require("lib.fx")
local C       = require("lib.const")
local run_lib = require("lib.run")
local ring    = require("lib.ring")

local M = {}

-- opts: damage, speed, radius, color, splash_radius?, slow_factor?, slow_time?,
-- tower? (the firing tower, for damage attribution). Pooled tables MUST reset
-- every field each spawn -- including the chain/hit-set state below.
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
  p.tower = opts.tower
  p.tower_id = opts.tower and opts.tower.id or nil
  -- chain: pierce hops to a target ahead of the shot, ricochet to any nearest.
  -- The firing tower passes the effective counts (global cards + its module
  -- socket); pierce wins if both are present. `hits` is a reused set so a
  -- chained shot never re-hits the same enemy.
  local pierce = opts.pierce or 0
  local ricochet = opts.ricochet or 0
  if pierce > 0 then
    p.chain, p.chain_ahead = pierce, true
  elseif ricochet > 0 then
    p.chain, p.chain_ahead = ricochet, false
  else
    p.chain, p.chain_ahead = 0, false
  end
  if p.hits then for k in pairs(p.hits) do p.hits[k] = nil end else p.hits = {} end
  p.hx, p.hy = 0, 0   -- last travel heading (for pierce "ahead" target selection)
  p.life = 2.0
  p.dead = false
  return p
end

-- Nearest enemy this shot has not hit yet, within chain range. Pierce mode only
-- considers enemies ahead of the shot's heading (forward hemisphere).
local function next_chain_target(run, p)
  local r2 = C.CHAIN_RANGE * C.CHAIN_RANGE
  local list = run.enemies
  local best, best_d2
  for i = 1, list.n do
    local e = list[i]
    if not e.dead and not p.hits[e] then
      local dx, dy = e.x - p.x, e.y - p.y
      local d2 = dx * dx + dy * dy
      if d2 <= r2 and ((not p.chain_ahead) or (dx * p.hx + dy * p.hy) > 0) then
        if not best_d2 or d2 < best_d2 then best, best_d2 = e, d2 end
      end
    end
  end
  return best
end

-- Resolve an impact. Returns true if the projectile should die, false if it
-- chained to a fresh target and stays alive.
local function resolve_hit(run, p)
  local t = p.target
  if t.is_boss then
    local _, applied = boss.hurt(run, p.damage)
    run_lib.credit_damage(run, p.tower_id, applied)
  else
    local _, applied = enemy.damage(run, t, p.damage)
    run_lib.credit_damage(run, p.tower_id, applied)
    if p.slow_factor then enemy.slow(t, p.slow_factor, p.slow_time) end
    p.hits[t] = true
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
          local _, applied = enemy.damage(run, e, p.damage)
          run_lib.credit_damage(run, p.tower_id, applied)
          if p.slow_factor then enemy.slow(e, p.slow_factor, p.slow_time) end
        end
      end
    end
    if run.mods.ring > 0 then
      ring.spawn(run, p.x, p.y, {
        radius = p.splash,
        damage = p.damage * run.mods.ring,
        tower_id = p.tower_id,
      })
    end
  end

  -- chain to another target (the boss is never a chain target)
  if p.chain > 0 and not t.is_boss then
    local nt = next_chain_target(run, p)
    if nt then
      p.target = nt
      p.chain = p.chain - 1
      p.life = math.max(p.life, 0.5)
      return false
    end
  end
  return true
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
      if dist > 0 then p.hx, p.hy = dx / dist, dy / dist end
      if dist <= reach or dist <= step then
        p.dead = resolve_hit(run, p)
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

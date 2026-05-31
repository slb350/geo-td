-- Enemies: spawn, advance along the path, take damage (shield -> armor -> hp),
-- regenerate, die (bounty + split), and leak (cost a life). Enemy tables are
-- allocated fresh and dropped on removal (projectiles hold references to them;
-- pooling would alias a recycled table onto a stale projectile target).

local pal    = require("lib.palette")
local path   = require("lib.path")
local fx     = require("lib.fx")
local shape  = require("lib.shape")
local combat = require("lib.combat")

local DEFS = usagi.read_json("enemies.json")

local M = {}
M.DEFS = DEFS

function M.spawn(run, kind, hp_scale, speed_scale, start_d)
  local def = DEFS[kind]
  if not def then return nil end
  local list = run.enemies
  list.n = list.n + 1
  local e = {}
  list[list.n] = e
  e.kind = kind
  e.def = def
  e.maxhp = def.hp * (hp_scale or 1)
  e.hp = e.maxhp
  e.base_speed = def.speed * (speed_scale or 1)
  e.d = start_d or 0
  e.slow_t = 0
  e.slow_factor = 1
  e.size = def.size
  e.armor = def.armor or 0
  e.regen = def.regen or 0
  e.shield_max = def.shield or 0
  e.shield = e.shield_max
  e.shield_regen = def.shield_regen or 0
  e.shield_hit_t = 0
  e.shield_hit_delay = 0.5
  e.color = pal.resolve(def.color)
  e.shape = def.shape
  e.spin = def.spin or 0
  e.phase = (list.n % 8) * 0.8
  e.bounty = def.bounty
  e.dead = false
  e.leaked = false
  e.fly = def.fly == true
  e.trail = def.trail == true
  if e.fly then
    -- flyers beeline straight from spawn to core, ignoring the path
    local nodes = run.path.nodes
    local sp, cp = nodes[1], nodes[#nodes]
    local dx, dy = cp[1] - sp[1], cp[2] - sp[2]
    local len = math.sqrt(dx * dx + dy * dy)
    e.sx, e.sy = sp[1], sp[2]
    e.fly_ux, e.fly_uy = dx / len, dy / len
    e.fly_total = len
    e.x, e.y = sp[1] + e.fly_ux * e.d, sp[2] + e.fly_uy * e.d
  else
    e.x, e.y = path.point_at(run.path, e.d)
  end
  return e
end

-- Damage order: shield pool first, then armor-reduced hp (shared with bosses).
function M.damage(run, e, dmg)
  if e.dead then return end
  if combat.apply_damage(e, dmg) then
    M.kill(run, e)
  end
end

function M.kill(run, e)
  if e.dead then return end
  e.dead = true
  local reward = math.floor(e.bounty * (run.mods.bounty_mult or 1))
  run.money = run.money + reward
  run.score = run.score + e.bounty
  run.kills = run.kills + 1
  fx.burst(e.x, e.y, e.color, 8)
  fx.number(e.x - 4, e.y - e.size - 6, "+" .. reward, gfx.COLOR_YELLOW)
  fx.kill_sfx()
  local split = e.def.split
  if split then
    for k = 1, split.count do
      M.spawn(run, split.type, run.hp_scale, run.speed_scale, math.max(0, e.d - k * 3))
    end
  end
end

-- Strongest slow wins; refresh duration.
function M.slow(e, factor, time)
  if factor < e.slow_factor then e.slow_factor = factor end
  if time > e.slow_t then e.slow_t = time end
end

function M.update(run, dt)
  local list = run.enemies
  local total = run.path.total_len
  local i = 1
  while i <= list.n do
    local e = list[i]
    if e.slow_t > 0 then
      e.slow_t = e.slow_t - dt
      if e.slow_t <= 0 then e.slow_factor = 1 end
    end
    combat.tick_regen(e, dt)
    if not e.dead then
      e.d = e.d + e.base_speed * e.slow_factor * dt
      if e.fly then
        if e.d >= e.fly_total then e.leaked = true end
        e.x, e.y = e.sx + e.fly_ux * e.d, e.sy + e.fly_uy * e.d
      else
        if e.d >= total then e.leaked = true end
        e.x, e.y = path.point_at(run.path, e.d)
      end
    end
    if e.dead or e.leaked then
      if e.leaked then
        run.lives = run.lives - 1
        fx.life_lost()
      end
      list[i] = list[list.n]
      list[list.n] = nil
      list.n = list.n - 1
    else
      i = i + 1
    end
  end
end

function M.draw(run)
  local list = run.enemies
  local t = usagi.elapsed
  for i = 1, list.n do
    local e = list[i]
    local s = e.size
    local rot = e.spin > 0 and (t * e.spin + e.phase) or 0
    -- flyers cast a ground shadow and bob above their travel line
    local by = e.y
    if e.fly then
      gfx.circ_fill(e.x, e.y + 1, s * 0.8, gfx.COLOR_BLACK)
      by = e.y - 5 - math.sin(t * 5 + e.phase) * 1.5
    end
    -- motion trail for fast movers: a couple of shrinking ghosts behind
    if e.trail then
      for k = 1, 2 do
        local td = e.d - k * (s + 1)
        if td > 0 then
          local gx, gy
          if e.fly then gx, gy = e.sx + e.fly_ux * td, e.sy + e.fly_uy * td - 5
          else gx, gy = path.point_at(run.path, td) end
          shape.fill(e.shape, gx, gy, s - k, gfx.COLOR_DARK_GRAY, rot)
        end
      end
    end
    shape.fill(e.shape, e.x, by, s, e.color, rot)
    -- inner counter-rotating facet: a glowing cut-gem core (catches the bloom)
    if s >= 4 then
      shape.fill(e.shape, e.x, by, s * 0.4, gfx.COLOR_WHITE, -rot * 1.5)
    else
      gfx.circ_fill(e.x, by, math.max(1, s * 0.4), gfx.COLOR_WHITE)
    end
    -- armor: outline ring
    if e.armor > 0 then
      shape.line(e.shape, e.x, by, s + 1, gfx.COLOR_LIGHT_GRAY, rot)
    end
    -- shield: outer ring whose thickness tracks the remaining pool
    if e.shield_max > 0 and e.shield > 0 then
      local th = 1 + math.floor((e.shield / e.shield_max) * 2)
      gfx.circ_ex(e.x, by, s + 3, th, gfx.COLOR_LIGHT_GRAY)
    end
    -- regen: soft pulsing ring
    if e.regen > 0 then
      gfx.circ(e.x, by, s + 2 + math.sin(t * 6 + e.phase) * 1.5, gfx.COLOR_GREEN)
    end
    -- slow: blue ring
    if e.slow_factor < 1 then
      gfx.circ(e.x, by, s + 2, gfx.COLOR_BLUE)
    end
    -- hp bar (only when wounded)
    if e.hp < e.maxhp then
      local w = s * 2
      gfx.rect_fill(e.x - s, by - s - 4, w, 2, gfx.COLOR_DARK_GRAY)
      gfx.rect_fill(e.x - s, by - s - 4, w * (e.hp / e.maxhp), 2, gfx.COLOR_GREEN)
    end
  end
end

return M

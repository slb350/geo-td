-- Boss: a tanky path-walker driven by optional data mechanics so each boss
-- plays differently -- shield pool, armor, regen, tower-disabling shockwaves,
-- continuous or phase-2 adds, invulnerability windows, and on-death splits.
-- Towers target it via tower.acquire; projectiles route damage here (the
-- target carries is_boss = true). Bosses cycle by wave (M.for_wave).

local C      = require("lib.const")
local pal    = require("lib.palette")
local path   = require("lib.path")
local enemy  = require("lib.enemy")
local fx     = require("lib.fx")
local shape  = require("lib.shape")
local combat = require("lib.combat")

local DEFS = usagi.read_json("bosses.json")

local M = {}
M.DEFS = DEFS
M.ROTATION = { "prism", "bulwark", "hydra", "specter" }

-- Which boss spawns on (boss) wave n.
function M.for_wave(n)
  local idx = math.floor(n / C.BOSS_EVERY)
  return M.ROTATION[((idx - 1) % #M.ROTATION) + 1]
end

function M.spawn(run, kind, hp_scale)
  local def = DEFS[kind] or DEFS.prism
  local hp = def.hp * (hp_scale or 1)
  local b = {
    is_boss = true, def = def, kind = kind,
    maxhp = hp, hp = hp,
    d = 0, base_speed = def.speed, size = def.size,
    color = pal.resolve(def.color), shape = def.shape or "tri",
    armor = def.armor or 0, regen = def.regen or 0,
    shield_max = def.shield or 0, shield = def.shield or 0,
    shield_regen = def.shield_regen or 0, shield_hit_t = 0, shield_hit_delay = 0.6,
    phase = 1, angle = 0,
    shock_t = def.shockwave_every or 0,
    spawn_t = def.spawn_every or 0,
    invuln_t = 0, invuln_cd = def.invuln_every or 0,
    dead = false, leaked = false,
  }
  b.x, b.y = path.point_at(run.path, 0)
  run.boss = b
  fx.boss_sfx()
  return b
end

function M.hurt(run, dmg)
  local b = run.boss
  if not b or b.dead then return end
  if b.invuln_t > 0 then return end -- phased out; immune
  local killed = combat.apply_damage(b, dmg)
  fx.boss_hit()
  if b.phase == 1 and b.def.phase2_at and b.hp <= b.maxhp * b.def.phase2_at then
    b.phase = 2
  end
  if killed then M.kill(run) end
end

function M.kill(run)
  local b = run.boss
  if not b or b.dead then return end
  b.dead = true
  run.bosses_killed = run.bosses_killed + 1
  local reward = math.floor(b.def.bounty * (run.mods.bounty_mult or 1))
  run.money = run.money + reward
  run.score = run.score + b.def.bounty
  fx.boss_death()
  fx.burst(b.x, b.y, b.color, 30)
  fx.number(b.x - 8, b.y - b.size - 8, "+" .. reward, gfx.COLOR_YELLOW)
  local split = b.def.on_death_split
  if split then
    local hp_scale = run.hp_scale * (split.hp_mult or C.BOSS_SPLIT_HP_MULT)
    for k = 1, split.count do
      enemy.spawn(run, split.type, hp_scale, run.speed_scale, math.max(0, b.d - k * 4))
    end
  end
end

local function emit_add(run, b)
  enemy.spawn(run, b.def.spawn_type, run.hp_scale * C.BOSS_ADD_HP_MULT, run.speed_scale, 0)
end

function M.update(run, dt)
  local b = run.boss
  if not b or b.dead then return end
  b.angle = b.angle + dt * 1.5

  combat.tick_regen(b, dt)
  -- invulnerability windows
  if b.def.invuln_every then
    if b.invuln_t > 0 then
      b.invuln_t = b.invuln_t - dt
    else
      b.invuln_cd = b.invuln_cd - dt
      if b.invuln_cd <= 0 then
        b.invuln_t = b.def.invuln_time
        b.invuln_cd = b.def.invuln_every + b.def.invuln_time
      end
    end
  end

  -- movement
  local total = run.path.total_len
  local spd = b.base_speed * (b.phase == 2 and b.def.phase2_speed_mult or 1)
  b.d = b.d + spd * dt
  if b.d >= total then
    b.leaked = true
    b.dead = true
    run.lives = run.lives - 5
    fx.life_lost()
    return
  end
  b.x, b.y = path.point_at(run.path, b.d)

  -- shockwave: disable towers in radius
  if b.def.shockwave_every then
    b.shock_t = b.shock_t - dt
    if b.shock_t <= 0 then
      b.shock_t = b.def.shockwave_every
      local r2 = b.def.shockwave_radius * b.def.shockwave_radius
      local towers = run.towers
      for i = 1, #towers do
        local tw = towers[i]
        local dx, dy = tw.x - b.x, tw.y - b.y
        if dx * dx + dy * dy <= r2 then tw.disabled_t = b.def.shockwave_disable end
      end
      fx.burst(b.x, b.y, gfx.COLOR_PINK, 16)
      effect.screen_shake(0.2, 3)
    end
  end

  -- adds (continuous or phase-2 only)
  if b.def.spawn_every then
    local active = b.def.spawn_phase == "always" or (b.def.spawn_phase == "phase2" and b.phase == 2)
    if active then
      b.spawn_t = b.spawn_t - dt
      if b.spawn_t <= 0 then
        b.spawn_t = b.def.spawn_every
        emit_add(run, b)
      end
    end
  end
end

function M.draw(run)
  local b = run.boss
  if not b or b.dead then return end
  local r = b.size
  local invuln = b.invuln_t > 0
  -- flicker the body while phased out
  local show = not (invuln and (math.floor(usagi.elapsed * 12) % 2 == 0))
  if show then
    shape.fill(b.shape, b.x, b.y, r, b.color, b.angle)
    shape.fill(b.shape, b.x, b.y, r * 0.5, gfx.COLOR_WHITE, -b.angle * 1.5)
  end
  -- shield ring
  if b.shield_max > 0 and b.shield > 0 then
    local th = 1 + math.floor((b.shield / b.shield_max) * 3)
    gfx.circ_ex(b.x, b.y, r + 4, th, gfx.COLOR_LIGHT_GRAY)
  end
  -- invuln / phase rings
  if invuln then
    gfx.circ(b.x, b.y, r + 6, gfx.COLOR_WHITE)
  elseif b.phase == 2 then
    gfx.circ(b.x, b.y, r + 3, gfx.COLOR_RED)
  else
    gfx.circ(b.x, b.y, r + 3, gfx.COLOR_WHITE)
  end
  -- hp bar (+ shield bar)
  local w = r * 3
  local x0, y0 = b.x - w * 0.5, b.y - r - 10
  gfx.rect_fill(x0, y0, w, 3, gfx.COLOR_DARK_GRAY)
  gfx.rect_fill(x0, y0, w * (b.hp / b.maxhp), 3, gfx.COLOR_RED)
  if b.shield_max > 0 and b.shield > 0 then
    gfx.rect_fill(x0, y0 - 3, w * (b.shield / b.shield_max), 2, gfx.COLOR_LIGHT_GRAY)
  end
end

return M

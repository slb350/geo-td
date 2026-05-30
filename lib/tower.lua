-- Towers: placement validity, target acquisition by policy, cooldown firing
-- into the projectile pool, temporary disable (boss shockwave), aiming + muzzle
-- flash, and geometric rendering (square = Pellet, diamond = Splash, hex = Frost).

local C     = require("lib.const")
local pal   = require("lib.palette")
local path  = require("lib.path")
local proj  = require("lib.projectile")
local fx    = require("lib.fx")
local shape = require("lib.shape")

local DEFS = usagi.read_json("towers.json")

local M = {}
M.DEFS = DEFS

-- Stable display order for the build palette.
M.ORDER = { "pellet", "splash", "frost", "rail" }

-- Can this tower hit the given enemy, given air/ground targeting?
local function can_hit(def, e)
  local t = def.targets or "ground"
  if e.fly then
    return t == "all" or t == "air"
  end
  return t == "all" or t == "ground"
end

function M.cost(run, kind)
  local def = DEFS[kind]
  return math.max(1, math.floor(def.cost * run.mods.cost_mult))
end

function M.available(meta, kind)
  local def = DEFS[kind]
  if def.locked then
    return meta.unlocks[def.unlock] == true
  end
  return true
end

function M.can_place(run, x, y, kind)
  if x < 0 or x >= C.HUD_X or y < 0 or y >= C.GAME_H then
    return false, "out of bounds"
  end
  if path.dist_to(run.path, x, y) < C.PLACE_MARGIN then
    return false, "too close to path"
  end
  local towers = run.towers
  local min_d = C.TOWER_R * 2
  for i = 1, #towers do
    local t = towers[i]
    local dx, dy = t.x - x, t.y - y
    if dx * dx + dy * dy < min_d * min_d then
      return false, "overlaps a tower"
    end
  end
  if run.money < M.cost(run, kind) then
    return false, "not enough money"
  end
  return true, nil
end

function M.place(run, x, y, kind)
  local def = DEFS[kind]
  local t = {
    kind = kind, def = def, x = x, y = y,
    cooldown = 0, disabled_t = 0, aim = 0, flash = 0,
    color = pal.resolve(def.color),
    shape = def.shape,
  }
  run.towers[#run.towers + 1] = t
  run.money = run.money - M.cost(run, kind)
  fx.place_sfx()
  return t
end

function M.sell(run, t)
  local towers = run.towers
  for i = 1, #towers do
    if towers[i] == t then
      run.money = run.money + math.floor(M.cost(run, t.kind) * C.SELL_REFUND)
      table.remove(towers, i)
      fx.sell_sfx()
      return
    end
  end
end

function M.at(run, x, y)
  local towers = run.towers
  for i = 1, #towers do
    local t = towers[i]
    local dx, dy = t.x - x, t.y - y
    if dx * dx + dy * dy <= C.TOWER_R * C.TOWER_R then
      return t
    end
  end
  return nil
end

local function acquire(run, t, range)
  local r2 = range * range
  local list = run.enemies
  local best, best_key
  local policy = t.def.targeting
  for i = 1, list.n do
    local e = list[i]
    if not e.dead and can_hit(t.def, e) then
      local dx, dy = e.x - t.x, e.y - t.y
      if dx * dx + dy * dy <= r2 then
        local key
        if policy == "closest" then
          key = -(dx * dx + dy * dy)
        elseif policy == "strongest" then
          key = e.hp
        else
          key = e.d
        end
        if not best or key > best_key then best, best_key = e, key end
      end
    end
  end
  local b = run.boss
  if b and not b.dead and can_hit(t.def, b) then
    local dx, dy = b.x - t.x, b.y - t.y
    if dx * dx + dy * dy <= r2 then
      local key
      if policy == "closest" then key = -(dx * dx + dy * dy)
      elseif policy == "strongest" then key = b.hp
      else key = run.path.total_len end
      if not best or key > best_key then best, best_key = b, key end
    end
  end
  return best
end

function M.update(run, dt)
  local towers = run.towers
  local mods = run.mods
  for i = 1, #towers do
    local t = towers[i]
    if t.flash > 0 then t.flash = t.flash - dt end
    if t.disabled_t > 0 then
      t.disabled_t = t.disabled_t - dt
    else
      local def = t.def
      local range = def.range * mods.range_mult
      local target = acquire(run, t, range)
      if target then
        -- two-arg atan gives the heading (Lua 5.3+/Usagi 5.5)
        t.aim = math.atan(target.y - t.y, target.x - t.x)
      end
      t.cooldown = t.cooldown - dt
      if t.cooldown <= 0 and target then
        local dmg = def.damage * mods.dmg_mult
        if mods.crit_chance > 0 and run.rng:chance(mods.crit_chance) then
          dmg = dmg * 2
        end
        proj.spawn(run, t.x, t.y, target, {
          damage = dmg,
          speed = def.proj_speed * mods.proj_mult,
          radius = def.proj_r,
          color = t.color,
          splash_radius = (def.splash_radius or 0) * mods.splash_mult,
          slow_factor = def.slow_factor,
          slow_time = def.slow_time,
        })
        t.cooldown = 1 / (def.fire_rate * mods.rate_mult)
        t.flash = 0.06
        fx.shoot_sfx()
      end
    end
  end
end

function M.draw(run, t, show_range)
  local r = C.TOWER_R
  local disabled = t.disabled_t > 0
  local color = disabled and gfx.COLOR_DARK_GRAY or t.color
  if show_range then
    gfx.circ(t.x, t.y, t.def.range * run.mods.range_mult, pal.RANGE)
  end
  local body_rot = t.shape == "hex" and (usagi.elapsed * 0.6) or 0
  shape.line(t.shape, t.x, t.y, r + 1, gfx.COLOR_DARK_GRAY, body_rot)
  shape.fill(t.shape, t.x, t.y, r, color, body_rot)
  if not disabled then
    local bl = r + 4
    gfx.line_ex(t.x, t.y, t.x + math.cos(t.aim) * bl, t.y + math.sin(t.aim) * bl, 2, gfx.COLOR_WHITE)
    if t.flash > 0 then
      gfx.circ_fill(t.x + math.cos(t.aim) * bl, t.y + math.sin(t.aim) * bl, 2.5, gfx.COLOR_YELLOW)
    end
  end
  gfx.circ_fill(t.x, t.y, 2, gfx.COLOR_WHITE)
  if disabled then
    gfx.circ(t.x, t.y, r + 2, gfx.COLOR_RED)
  end
end

return M

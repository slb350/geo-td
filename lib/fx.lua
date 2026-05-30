-- Juice: thin wrappers over the engine's effect.* primitives, plus pooled
-- geometric burst particles and rising damage/bounty numbers. Particle and
-- number pools are module-local and transient (cleared per run); nothing
-- else references them, so pooling here is safe.

local fx = {}

local parts = { n = 0 }   -- {x,y,vx,vy,life,maxlife,size,color}
local nums  = { n = 0 }   -- {x,y,vy,life,maxlife,text,color}

local MAX_PARTS = 220
local shoot_cd = 0        -- throttle for the rapid-fire shoot sfx

function fx.clear()
  parts.n = 0
  nums.n = 0
end

function fx.burst(x, y, color, count)
  count = count or 6
  for _ = 1, count do
    if parts.n >= MAX_PARTS then break end
    parts.n = parts.n + 1
    local p = parts[parts.n]
    if not p then p = {}; parts[parts.n] = p end
    local a = math.random() * math.pi * 2
    local spd = 20 + math.random() * 60
    p.x, p.y = x, y
    p.vx, p.vy = math.cos(a) * spd, math.sin(a) * spd
    p.maxlife = 0.25 + math.random() * 0.35
    p.life = p.maxlife
    p.size = 1 + math.random() * 1.5
    p.color = color
  end
end

function fx.number(x, y, text, color)
  nums.n = nums.n + 1
  local d = nums[nums.n]
  if not d then d = {}; nums[nums.n] = d end
  d.x, d.y = x, y
  d.vy = -22
  d.maxlife = 0.7
  d.life = 0.7
  d.text = text
  d.color = color or gfx.COLOR_WHITE
end

function fx.update(dt)
  if shoot_cd > 0 then shoot_cd = shoot_cd - dt end
  local i = 1
  while i <= parts.n do
    local p = parts[i]
    p.life = p.life - dt
    if p.life <= 0 then
      parts[i] = parts[parts.n]; parts[parts.n] = p; parts.n = parts.n - 1
    else
      p.x = p.x + p.vx * dt
      p.y = p.y + p.vy * dt
      p.vx = p.vx * 0.90
      p.vy = p.vy * 0.90
      i = i + 1
    end
  end
  local j = 1
  while j <= nums.n do
    local d = nums[j]
    d.life = d.life - dt
    if d.life <= 0 then
      nums[j] = nums[nums.n]; nums[nums.n] = d; nums.n = nums.n - 1
    else
      d.y = d.y + d.vy * dt
      j = j + 1
    end
  end
end

function fx.draw()
  for i = 1, parts.n do
    local p = parts[i]
    gfx.circ_fill(p.x, p.y, p.size, p.color)
  end
  for j = 1, nums.n do
    local d = nums[j]
    local alpha = d.life / d.maxlife
    gfx.text_ex(d.text, d.x, d.y, 1, 0, d.color, alpha)
  end
end

-- Juice passthroughs (effect.* stacking: longer duration wins).
function fx.hit()        effect.screen_shake(0.06, 1.5) end
function fx.life_lost()  effect.flash(0.16, gfx.COLOR_RED); effect.screen_shake(0.22, 4); sfx.play("life") end
function fx.boss_hit()   effect.screen_shake(0.14, 2.5) end
function fx.boss_death() effect.hitstop(0.18); effect.screen_shake(0.5, 6); effect.flash(0.22, gfx.COLOR_WHITE); sfx.play("boss_die") end

-- Sound hooks. sfx.play no-ops on unknown names, so these are safe even before
-- the .wav assets exist. shoot is throttled (towers restart the clip otherwise).
function fx.shoot_sfx()
  if shoot_cd <= 0 then
    sfx.play_ex("shoot", 0.45, 0.9 + math.random() * 0.3, 0)
    shoot_cd = 0.05
  end
end
function fx.hit_sfx()     sfx.play_ex("hit", 0.4, 0.9 + math.random() * 0.4, 0) end
function fx.kill_sfx()    sfx.play("kill") end
function fx.place_sfx()   sfx.play("place") end
function fx.sell_sfx()    sfx.play("sell") end
function fx.wave_sfx()    sfx.play("wave") end
function fx.boss_sfx()    sfx.play("boss") end
function fx.upgrade_sfx() sfx.play("upgrade") end
function fx.click_sfx()   sfx.play("click") end
function fx.over_sfx()    sfx.play("over") end

return fx

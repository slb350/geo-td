-- Headless smoke test for the simulation layer. Stubs the Usagi engine globals
-- (gfx/usagi/effect with a tiny JSON reader) and drives the real lib/* logic
-- through several waves, the boss fight, splitter splits, powerups, and a
-- save/load roundtrip. Catches runtime errors (nil indexing, bad arithmetic,
-- pool bugs) that a syntax check can't. Run from the project root:
--     luajit tests/smoke.lua
-- This file is NOT loaded by the engine (it only reads main.lua + assets).

-- ---------------------------------------------------------------- JSON reader
local function parse_json(str)
  local pos = 1
  local value
  local function ws()
    while pos <= #str do
      local c = str:sub(pos, pos)
      if c == " " or c == "\n" or c == "\t" or c == "\r" then pos = pos + 1 else break end
    end
  end
  local function str_val()
    pos = pos + 1
    local buf = {}
    while pos <= #str do
      local c = str:sub(pos, pos)
      if c == '"' then pos = pos + 1; return table.concat(buf) end
      if c == "\\" then
        local n = str:sub(pos + 1, pos + 1)
        local map = { n = "\n", t = "\t", r = "\r", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
        buf[#buf + 1] = map[n] or n; pos = pos + 2
      else
        buf[#buf + 1] = c; pos = pos + 1
      end
    end
    error("json: unterminated string")
  end
  local function num_val()
    local s = pos
    while pos <= #str and str:sub(pos, pos):match("[%-%+%d%.eE]") do pos = pos + 1 end
    return tonumber(str:sub(s, pos - 1))
  end
  local function arr_val()
    pos = pos + 1; local t = {}; ws()
    if str:sub(pos, pos) == "]" then pos = pos + 1; return t end
    while true do
      t[#t + 1] = value(); ws()
      local c = str:sub(pos, pos)
      if c == "," then pos = pos + 1; ws()
      elseif c == "]" then pos = pos + 1; return t
      else error("json: expected , or ]") end
    end
  end
  local function obj_val()
    pos = pos + 1; local t = {}; ws()
    if str:sub(pos, pos) == "}" then pos = pos + 1; return t end
    while true do
      ws(); local k = str_val(); ws()
      assert(str:sub(pos, pos) == ":", "json: expected :"); pos = pos + 1; ws()
      t[k] = value(); ws()
      local c = str:sub(pos, pos)
      if c == "," then pos = pos + 1
      elseif c == "}" then pos = pos + 1; return t
      else error("json: expected , or }") end
    end
  end
  value = function()
    ws(); local c = str:sub(pos, pos)
    if c == '"' then return str_val()
    elseif c == "{" then return obj_val()
    elseif c == "[" then return arr_val()
    elseif c == "t" then pos = pos + 4; return true
    elseif c == "f" then pos = pos + 5; return false
    elseif c == "n" then pos = pos + 4; return nil
    else return num_val() end
  end
  return value()
end

-- --------------------------------------------------------------- engine stubs
gfx = {}
local PALETTE = {
  "BLACK", "DARK_BLUE", "DARK_PURPLE", "DARK_GREEN", "BROWN", "DARK_GRAY",
  "LIGHT_GRAY", "WHITE", "RED", "ORANGE", "YELLOW", "GREEN", "BLUE", "INDIGO",
  "PINK", "PEACH",
}
for i, name in ipairs(PALETTE) do gfx["COLOR_" .. name] = i end
local gfx_calls = {}
for _, fn in ipairs({
  "clear", "text", "text_ex", "rect", "rect_fill", "rect_ex", "circ", "circ_fill",
  "circ_ex", "line", "line_ex", "tri", "tri_fill", "px", "spr", "spr_ex",
  "shader_set", "shader_uniform",
}) do
  gfx[fn] = function(...)
    gfx_calls[#gfx_calls + 1] = { fn = fn, args = { ... } }
  end
end

local SAVE
usagi = {
  GAME_W = 480, GAME_H = 270, SPRITE_SIZE = 16, PLATFORM = "test", IS_DEV = true, elapsed = 0,
  measure_text = function(s) return #s * 4, 12 end,
  read_json = function(p)
    local f = assert(io.open("data/" .. p, "r"))
    local s = f:read("*a"); f:close()
    return parse_json(s)
  end,
  save = function(t) SAVE = t end,
  load = function() return SAVE end,
  dump = function() return "" end,
}
effect = { hitstop = function() end, screen_shake = function() end,
  flash = function() end, slow_mo = function() end, stop = function() end }
sfx = { play = function() end, play_ex = function() end }
music = { play = function() end, loop = function() end, stop = function() end,
  play_ex = function() end, mutate = function() end }

package.path = "./?.lua;" .. package.path

-- ---------------------------------------------------------------- the modules
local meta    = require("lib.meta")
local C       = require("lib.const")
local run_mod = require("lib.run")
local wave    = require("lib.wave")
local enemy   = require("lib.enemy")
local tower   = require("lib.tower")
local proj    = require("lib.projectile")
local boss    = require("lib.boss")
local powerup = require("lib.powerup")

local checks, fails = 0, 0
local function check(cond, msg)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    print("  FAIL: " .. msg)
  end
end

local function near(a, b)
  return math.abs(a - b) < 0.000001
end

-- First balance pass cut each tier-spike *component* (the part above the
-- per-wave baseline of 1.0) by 15%. Encode the derivation so the test verifies
-- the intent rather than mirroring the literal back at itself.
check(near(C.HP_TIER_MULT, 1 + (2.3 - 1) * 0.85), "hp tier-spike cut 15% (2.3 -> 2.105)")
check(near(C.BUDGET_TIER_MULT, 1 + (1.25 - 1) * 0.85), "budget tier-spike cut 15% (1.25 -> 1.2125)")
check(near(C.SPEED_TIER_ADD, 0.06 * 0.85), "speed tier-spike cut 15% (0.06 -> 0.051)")

-- ----------------------------------------------------------------- meta/save
local m = meta.default()
m.unlocks.tower_rail = true
meta.save(m)
local back = meta.load()
check(back ~= nil and back.currency == 0, "save/load roundtrip")
check(meta.finish_run(m, 7) == 7 * 2, "finish_run award = wave*2")
check(m.best_wave == 7, "best_wave recorded")

-- ----------------------------------------------------------------- run setup
local run = run_mod.new(m, 4242)
run.money = 99999
run.lives = 99999 -- keep alive so every wave runs regardless of balance
check(run.path.total_len > 0, "path has length")
check(run.enemies.n == 0 and run.projectiles.n == 0, "empty pools")

-- ----------------------------------------------------------------- placement
local function place(kind, x, y)
  local ok, why = tower.can_place(run, x, y, kind)
  check(ok, ("place %s at %d,%d (%s)"):format(kind, x, y, tostring(why)))
  if ok then tower.place(run, x, y, kind) end
end
place("pellet", 200, 150)
place("splash", 110, 95)
place("frost", 300, 40)
check(#run.towers == 3, "three towers placed")

-- placement rejection: on the path and out of bounds
check(not (tower.can_place(run, 150, 56, "pellet")), "reject on-path placement")
check(not (tower.can_place(run, 400, 100, "pellet")), "reject placement in HUD/out of field")

-- sell refund
local before_money = run.money
tower.sell(run, run.towers[#run.towers])
check(#run.towers == 2 and run.money > before_money, "sell refunds and removes")
place("frost", 300, 40)

-- ----------------------------------------------------------------- splitter
run.enemies.n = 0
local sp = enemy.spawn(run, "splitter", 1, 1, 10)
check(sp ~= nil and run.enemies.n == 1, "splitter spawned")
local money0 = run.money
enemy.damage(run, sp, 1e9)
check(sp.dead, "splitter killed")
check(run.money > money0, "kill granted bounty")
check(run.enemies.n == 3, "split added 2 children before cleanup")
enemy.update(run, 1 / 60)
check(run.enemies.n == 2, "dead splitter removed, 2 motes remain")

-- ----------------------------------------------------------------- shield
run.enemies.n = 0
local wd = enemy.spawn(run, "ward", 1, 1, 10)
check(wd.shield == 50 and wd.shield_max == 50, "ward starts at full shield")
local wd_hp = wd.hp
enemy.damage(run, wd, 30) -- under the shield pool
check(wd.shield == 20 and wd.hp == wd_hp, "shield absorbs before hp")
enemy.damage(run, wd, 40) -- 20 to shield, 20 overflow to hp
check(wd.shield == 0 and wd.hp == wd_hp - 20, "overflow damages hp")

-- ----------------------------------------------------------------- regen
run.enemies.n = 0
local md = enemy.spawn(run, "mender", 1, 1, 10)
enemy.damage(run, md, 20)
local md_low = md.hp
enemy.update(run, 0.5) -- regen 9/s over 0.5s
check(md.hp > md_low, "mender regenerates over time")

-- ----------------------------------------------------------------- flyers
run.enemies.n = 0
local wisp = enemy.spawn(run, "wisp", 1, 1, 0)
check(wisp.fly == true and wisp.fly_total > 0, "wisp is a flyer with a beeline length")
local wx0 = wisp.x
enemy.update(run, 0.2)
check(wisp.x ~= wx0, "flyer moves along its beeline")

-- air/ground targeting: splash (ground) ignores a flyer; pellet (air) hits it
run.towers = {}
run.enemies.n = 0
local fly = enemy.spawn(run, "wisp", 1, 1, wisp.fly_total * 0.5) -- mid-flight
run.money = 9999
local s_tower = tower.place(run, fly.x + 10, fly.y + 10, "splash")
local p_tower = tower.place(run, fly.x - 10, fly.y - 10, "pellet")
run.projectiles.n = 0
tower.update(run, 1.0) -- one big step so both towers fire if able
local hit_fly = false
for i = 1, run.projectiles.n do
  if run.projectiles[i].target == fly then hit_fly = true end
end
check(hit_fly, "an air-capable tower (pellet) targets the flyer")
-- splash (ground-only) must NOT have targeted the flyer
local splash_hit_fly = false
for i = 1, run.projectiles.n do
  local p = run.projectiles[i]
  if p.target == fly and p.splash > 0 then splash_hit_fly = true end
end
check(not splash_hit_fly, "a ground-only tower (splash) ignores the flyer")
-- restore a defensive set (incl. anti-air Rail) for the wave simulation
run.towers = {}
run.enemies.n = 0
run.projectiles.n = 0
run.money = 9999
tower.place(run, 200, 150, "pellet")
tower.place(run, 110, 95, "splash")
tower.place(run, 300, 40, "frost")
tower.place(run, 290, 150, "rail")

-- ----------------------------------------------------------------- powerups
local d0 = run.mods.dmg_mult
powerup.apply(run, { key = "dmg", rarity = 1 })
check(run.mods.dmg_mult > d0, "powerup card raised dmg_mult")
local d1 = run.mods.dmg_mult
powerup.apply(run, { key = "dmg", rarity = 3 })
check((run.mods.dmg_mult - d1) > (d1 - d0), "rare card scales stronger than common")

-- ----------------------------------------------------------------- wave sim
local DT = 1 / 60
local function sim_wave(n)
  run.enemies.n = 0
  run.projectiles.n = 0
  if wave.is_boss(n) then
    wave.boss_scale(run, n)
    boss.spawn(run, "prism", run.hp_scale)
  else
    run.boss = nil
    wave.start(run, n)
  end
  run.phase = "combat"
  local boss_wave = wave.is_boss(n)
  local peak_enemies = 0
  local frames = 0
  while true do
    frames = frames + 1
    local spawns_done = boss_wave or wave.update(run, DT)
    enemy.update(run, DT)
    if boss_wave then boss.update(run, DT) end
    tower.update(run, DT)
    proj.update(run, DT)
    if run.enemies.n > peak_enemies then peak_enemies = run.enemies.n end
    -- exercise the boss death + split path deterministically
    if boss_wave and frames >= 300 and run.boss and not run.boss.dead then
      boss.hurt(run, 1e9) -- repeated, to punch through any invuln window
    end
    local cleared = run.enemies.n == 0 and (not run.boss or run.boss.dead)
    if spawns_done and cleared then break end
    if frames > 30000 then
      check(false, "wave " .. n .. " never cleared (enemies=" .. run.enemies.n .. ")")
      break
    end
  end
  if boss_wave then
    check(run.boss ~= nil and run.boss.dead, "boss defeated in wave " .. n)
  end
  return frames, peak_enemies
end

for n = 1, 20 do
  local frames, peak = sim_wave(n)
  local label = wave.is_boss(n) and ("boss:" .. boss.for_wave(n)) or "norm"
  print(("  wave %2d (%-13s): cleared in %d frames, peak enemies %d")
    :format(n, label, frames, peak))
end

-- ------------------------------------------------------------- scene layer
-- Stub input + the global State/SwitchScene the scenes use, then drive each
-- scene's update/draw once. This is the layer the upgrade-draft crash hid in
-- (the lib-only tests above never touched scenes/).
local clicks = { left = false, mx = 0, my = 0 }
input = {
  KEY_1 = 1, KEY_2 = 2, KEY_3 = 3, KEY_S = 4, KEY_SPACE = 5, KEY_ENTER = 6,
  MOUSE_LEFT = 1, MOUSE_RIGHT = 2, MOUSE_MIDDLE = 3, BTN1 = 1,
  mouse = function() return clicks.mx, clicks.my end,
  mouse_pressed = function(b) return clicks.left and b == 1 end,
  mouse_released = function() return false end,
  mouse_held = function() return false end,
  key_pressed = function() return false end,
  key_held = function() return false end,
  key_released = function() return false end,
  pressed = function() return false end,
  held = function() return false end,
  released = function() return false end,
}
State = {
  meta = meta.default(), run = nil,
  ui = { selected = nil, sell_mode = false, hover_x = 0, hover_y = 0, hover_valid = false },
  summary = nil, current = nil, pending = nil,
}
function SwitchScene(k) State.pending = k end

local menu_s     = require("scenes.menu")
local game_s     = require("scenes.game")
local upgrade_s  = require("scenes.upgrade")
local gameover_s = require("scenes.gameover")

menu_s.update(1 / 60); menu_s.draw(1 / 60)
gfx_calls = {}
menu_s.draw(1 / 60)
for i = 1, #gfx_calls do
  local call = gfx_calls[i]
  if call.fn == "text" then
    local text, x, y = call.args[1], call.args[2], call.args[3]
    for j = 1, #meta.SHOP do
      local it = meta.SHOP[j]
      if text == it.name or text == it.desc or text == it.cost .. " bank" or text == "OWNED" then
        local box
        for k = i - 1, 1, -1 do
          local prior = gfx_calls[k]
          if prior.fn == "rect_fill" then
            local args = prior.args
            if args[1] <= x and x < args[1] + args[3] and args[2] <= y and y < args[2] + args[4] then
              box = args
              break
            end
          end
        end
        local _, h = usagi.measure_text(text)
        check(box ~= nil and y + h <= box[2] + box[4], text .. " fits inside menu unlock row")
      end
    end
  end
end

State.run = run_mod.new(State.meta, 9); State.run.money = 9999
game_s.init()
State.ui.selected = "pellet"
clicks.left, clicks.mx, clicks.my = true, 200, 150
game_s.update(1 / 60)
clicks.left = false
check(#State.run.towers >= 1, "game scene placed a tower via click")
game_s.update(1 / 60); game_s.draw(1 / 60)

State.pending = nil
upgrade_s.init()
check(State.run.draft and #State.run.draft == 3, "upgrade drafted 3 cards")
local pw0 = #State.run.powerups
-- lockout: a frame with the mouse up arms the scene; no choice yet
clicks.left = false
upgrade_s.update(1 / 60)
check(State.run.draft ~= nil and State.pending == nil, "upgrade ignores carried-over click (lockout)")
-- now a fresh click on card 1 chooses
clicks.left, clicks.mx, clicks.my = true, 104, 140
upgrade_s.update(1 / 60)
clicks.left = false
check(#State.run.powerups == pw0 + 1, "upgrade applied exactly one powerup on click")
check(State.pending == "game", "upgrade returns to game after a choice")
upgrade_s.draw(1 / 60)

State.run.final_wave = State.run.wave_index
gameover_s.init(); gameover_s.update(1 / 60); gameover_s.draw(1 / 60)
check(State.summary ~= nil, "gameover produced a summary")

-- ----------------------------------------------------------------- result
print(("smoke: %d checks, %d failures"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)

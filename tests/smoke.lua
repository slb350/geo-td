-- Headless smoke test for the simulation layer. Loads the engine-stub harness
-- (tests/harness.lua: fake gfx/usagi/effect/sfx/music + a tiny JSON reader) and
-- drives the real lib/* logic through several waves, the boss fight, splitter
-- splits, powerups, towers, the orbital strike, and a save/load roundtrip.
-- Catches runtime errors (nil indexing, bad arithmetic, pool bugs) that a syntax
-- check can't. Run from the project root:
--     luajit tests/smoke.lua
-- This file is NOT loaded by the engine (it only reads main.lua + assets).

package.path = "./?.lua;" .. package.path
local harness = require("tests.harness")  -- installs the fake engine globals

-- ---------------------------------------------------------------- the modules
local meta    = require("lib.meta")
local C       = require("lib.const")
local maps    = require("lib.maps")
local run_mod = require("lib.run")
local path    = require("lib.path")
local wave    = require("lib.wave")
local enemy   = require("lib.enemy")
local tower   = require("lib.tower")
local proj    = require("lib.projectile")
local boss    = require("lib.boss")
local powerup = require("lib.powerup")
local ui      = require("lib.ui")

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

-- ui.text_height returns the measured font line height, scaled, for stacked
-- text layouts. The mock reports a 12px line height like the real engine.
local _, mock_h = usagi.measure_text("Ag")
check(near(ui.text_height(), mock_h), "text_height = measured line height")
check(near(ui.text_height(2), mock_h * 2), "text_height scales by the given factor")

-- ----------------------------------------------------------------- meta/save
local m = meta.default()
m.unlocks.tower_rail = true
meta.save(m)
local back = meta.load()
check(back ~= nil and back.currency == 0, "save/load roundtrip")
check(meta.finish_run(m, 7) == 7 * 2, "finish_run award = wave*2")
check(m.best_wave == 7, "best_wave recorded")

-- Flak Cannon unlock: locked by default, listed in the shop, and back-filled
-- onto saves that predate it.
check(meta.default().unlocks.tower_flak == false, "flak cannon locked by default")
local flak_in_shop = false
for i = 1, #meta.SHOP do if meta.SHOP[i].id == "tower_flak" then flak_in_shop = true end end
check(flak_in_shop, "flak cannon listed in the unlock shop")
local legacy = meta.default(); legacy.unlocks.tower_flak = nil
meta.save(legacy)
check(meta.load().unlocks.tower_flak == false, "load back-fills a missing flak unlock")

-- ----------------------------------------------------------------- run setup
-- Pin the geometry to Serpentine: the placement coords and boss fixtures below
-- are tuned to that route. Layout variety is exercised separately just below.
local run = run_mod.new(m, 4242, "serpentine")
run.money = 99999
run.lives = 99999 -- keep alive so every wave runs regardless of balance
check(run.path_name == "serpentine", "explicit layout pin honored")
check(run.path.total_len > 0, "path has length")
check(run.enemies.n == 0 and run.projectiles.n == 0, "empty pools")

-- ------------------------------------------------------------- path layouts
-- Every shipped layout must be in-bounds, long enough to play, and leave room
-- to build; seed-derived selection must be deterministic and pick a real map.
check(#maps.ORDER >= 2, "multiple path layouts available")
local function in_field(x, y)
  return x >= 0 and x < C.FIELD_W and y >= 0 and y < C.FIELD_H
end
for _, name in ipairs(maps.ORDER) do
  local layout = maps.get(name)
  check(layout ~= nil, "layout '" .. name .. "' present")
  local r = run_mod.new(m, 1, name)
  check(r.path_name == name and r.map_name == layout.name, name .. " run carries its name")
  check(r.path.total_len > 100, name .. " has a substantial route")
  check(#layout.nodes >= 2, name .. " has >= 2 waypoints")
  local in_bounds = true
  for _, nd in ipairs(layout.nodes) do
    if not in_field(nd[1], nd[2]) then in_bounds = false end
  end
  check(in_bounds, name .. " stays in field bounds")
  local buildable = false
  for gx = 20, C.FIELD_W - 20, 16 do
    for gy = 20, C.FIELD_H - 20, 16 do
      if path.dist_to(r.path, gx, gy) > C.PLACE_MARGIN then buildable = true; break end
    end
    if buildable then break end
  end
  check(buildable, name .. " leaves room to build")
end
local function seed_map(s) return run_mod.new(m, s).path_name end
check(seed_map(20260530) == seed_map(20260530), "seed-derived map is deterministic")
local known = false
for _, name in ipairs(maps.ORDER) do
  if seed_map(7) == name then known = true end
end
check(known, "seed-derived map is one of the known layouts")

-- ---------------------------------------------------------- map progression
-- Each map unlocks the next harder one (maps.ORDER) by reaching UNLOCK_WAVE.
local pm = meta.default()
local second = maps.ORDER[2]
check(meta.is_map_unlocked(pm, maps.first), "first (easiest) map unlocked by default")
check(not meta.is_map_unlocked(pm, second), "next map locked initially")
meta.finish_run(pm, maps.UNLOCK_WAVE - 1, 0, maps.first)
check(not meta.is_map_unlocked(pm, second), "a sub-threshold finish does not unlock the next map")
local _, unlocked = meta.finish_run(pm, maps.UNLOCK_WAVE, 0, maps.first)
check(meta.is_map_unlocked(pm, second), "reaching the unlock wave unlocks the next map")
check(unlocked == second, "finish_run reports the newly unlocked map")
check(pm.map_best[maps.first] == maps.UNLOCK_WAVE, "per-map best wave recorded")
local _, again = meta.finish_run(pm, maps.UNLOCK_WAVE, 0, maps.first)
check(again == nil, "re-clearing an already-unlocked map reports no new unlock")
meta.save(pm)
check(meta.load().map_unlocked[second] == true, "unlocked maps survive save/load")

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

-- rail target priority: a frail flyer must outrank a higher-HP ground enemy
-- (with "strongest" alone the flyer is ignored), and the boss outranks both.
run.towers = {}
run.enemies.n = 0
run.projectiles.n = 0
run.money = 9999
tower.place(run, 290, 150, "rail")
local beefy = enemy.spawn(run, "ward", 50, 1, 10)
beefy.x, beefy.y, beefy.hp = 300, 150, 9999     -- highest HP in range
local frail_fly = enemy.spawn(run, "wisp", 1, 1, 5)
frail_fly.x, frail_fly.y = 280, 150
tower.update(run, 1.0)
local rail_hit_fly = false
for i = 1, run.projectiles.n do
  if run.projectiles[i].target == frail_fly then rail_hit_fly = true end
end
check(rail_hit_fly, "rail prioritises a flyer over a higher-HP ground enemy")

run.enemies.n = 0
run.projectiles.n = 0
run.towers[1].cooldown = 0                       -- rail fires slowly; let it shoot again
local fly2 = enemy.spawn(run, "wisp", 1, 1, 5)
fly2.x, fly2.y = 280, 150
wave.boss_scale(run, 5)
boss.spawn(run, "prism", run.hp_scale)
run.boss.x, run.boss.y = 300, 150
tower.update(run, 1.0)
local rail_hit_boss = false
for i = 1, run.projectiles.n do
  if run.projectiles[i].target == run.boss then rail_hit_boss = true end
end
check(rail_hit_boss, "rail prioritises the boss over a flyer")
run.boss = nil

-- anti-air Flak: targets a flyer in range while ignoring a ground enemy and a
-- (ground) boss sitting right next to it.
run.towers = {}
run.enemies.n = 0
run.projectiles.n = 0
run.money = 9999
tower.place(run, 200, 150, "flak")
local grnd = enemy.spawn(run, "hulk", 1, 1, 10); grnd.x, grnd.y = 208, 150
local airb = enemy.spawn(run, "wisp", 1, 1, 5);  airb.x, airb.y = 196, 150
wave.boss_scale(run, 5); boss.spawn(run, "prism", run.hp_scale); run.boss.x, run.boss.y = 204, 150
tower.update(run, 1.0)
local flak_air, flak_other = false, false
for i = 1, run.projectiles.n do
  local tg = run.projectiles[i].target
  if tg == airb then flak_air = true end
  if tg == grnd or tg == run.boss then flak_other = true end
end
check(flak_air, "flak targets the flyer")
check(not flak_other, "flak ignores ground enemies and the ground boss")
run.boss = nil

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

-- -------------------------------------------------------------- boss balance
local BALANCE_DT = 1 / 60

local function layout_cost(layout)
  local total = 0
  for i = 1, #layout do
    total = total + tower.DEFS[layout[i][1]].cost
  end
  return total
end

local function place_layout(r, layout)
  r.money = 99999
  for i = 1, #layout do
    local it = layout[i]
    local ok, why = tower.can_place(r, it[2], it[3], it[1])
    check(ok, ("boss fixture place %s at %d,%d (%s)"):format(it[1], it[2], it[3], tostring(why)))
    if ok then tower.place(r, it[2], it[3], it[1]) end
  end
  r.money = 0
end

local function sim_boss_fixture(n, kind, layout, mods)
  local r = run_mod.new(m, 1777 + n, "serpentine")
  r.lives = 99999
  for k, v in pairs(mods) do r.mods[k] = v end -- override mods for this fixture
  place_layout(r, layout)
  wave.boss_scale(r, n)
  boss.spawn(r, kind, r.hp_scale)
  local frames = 0
  while frames < 30000 do
    frames = frames + 1
    enemy.update(r, BALANCE_DT)
    boss.update(r, BALANCE_DT)
    tower.update(r, BALANCE_DT)
    proj.update(r, BALANCE_DT)
    local cleared = r.enemies.n == 0 and r.boss and r.boss.dead
    if cleared or r.lives < 99999 then break end
  end
  return r.lives == 99999 and r.bosses_killed > 0 and r.enemies.n == 0
end

local prism_layout = {
  { "pellet", 98, 98 }, { "pellet", 306, 130 }, { "pellet", 114, 146 },
  { "pellet", 210, 162 }, { "pellet", 290, 114 }, { "pellet", 194, 162 },
}
check(layout_cost(prism_layout) == 270, "prism fixture cost matches pre-boss income envelope")
local prism_ok = sim_boss_fixture(5, "prism", prism_layout, { dmg_mult = 1.18, rate_mult = 1.15 })
check(prism_ok, "wave 5 prism + splits clears with a broad six-pellet/two-common-DPS setup")

local bulwark_layout = {
  { "pellet", 322, 194 }, { "pellet", 290, 130 }, { "pellet", 290, 114 },
  { "pellet", 306, 114 }, { "pellet", 306, 130 },
  { "splash", 322, 130 }, { "splash", 274, 130 },
  { "frost", 322, 114 }, { "frost", 354, 114 },
}
check(layout_cost(bulwark_layout) == 525, "bulwark fixture cost fits normal pre-wave-10 income")
local bulwark_ok = sim_boss_fixture(10, "bulwark", bulwark_layout, { dmg_mult = 1.36, rate_mult = 1.30 })
check(bulwark_ok, "wave 10 bulwark + brutes clears with a non-rail mixed/four-common-DPS setup")

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

-- ----------------------------------------------------------------- orbital
-- The $500 orbital strike vaporizes every enemy on the field (no bounty, no
-- splits) but never touches the boss, and only fires mid-combat with funds.
run.phase = "combat"
run.boss = nil
run.enemies.n = 0
run.projectiles.n = 0
run.money = 1000
enemy.spawn(run, "wisp", 1, 1, 10)
enemy.spawn(run, "hulk", 1, 1, 12)
enemy.spawn(run, "splitter", 1, 1, 8)   -- would normally split on death
wave.boss_scale(run, 5); boss.spawn(run, "prism", run.hp_scale)
local orb_count, boss_hp0 = run.enemies.n, run.boss.hp
check(run_mod.can_orbital(run), "orbital available mid-combat with funds + targets")
check(run_mod.orbital_strike(run), "orbital strike fires")
check(run.money == 500, "orbital charged exactly $500 (no bounty refunded)")
local survivors = 0
for i = 1, run.enemies.n do if not run.enemies[i].dead then survivors = survivors + 1 end end
check(survivors == 0, "orbital killed every on-screen enemy")
check(run.enemies.n == orb_count, "orbital spawned no splitter children")
check(not run.boss.dead and run.boss.hp == boss_hp0, "orbital left the boss untouched")
-- gating: needs combat phase, the cost on hand, and a non-empty field
enemy.update(run, 1 / 60)                -- clear the vaporized pool
check(run.enemies.n == 0 and not run_mod.can_orbital(run), "orbital unavailable on an empty field")
enemy.spawn(run, "wisp", 1, 1, 10)
run.money = 499
check(not run_mod.can_orbital(run), "orbital unavailable under $500")
run.money = 1000; run.phase = "building"
check(not run_mod.can_orbital(run), "orbital unavailable outside combat")
check(not run_mod.orbital_strike(run), "orbital_strike no-ops when unavailable")
run.boss = nil; run.enemies.n = 0; run.projectiles.n = 0; run.phase = "building"

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
local select_s   = require("scenes.select")
local game_s     = require("scenes.game")
local upgrade_s  = require("scenes.upgrade")
-- the gameover scene is exercised by tests/smoke_report.lua (the report suite)

menu_s.update(1 / 60); menu_s.draw(1 / 60)
harness.reset_gfx()
menu_s.draw(1 / 60)
local gfx_calls = harness.gfx_calls()
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

-- map-select scene: a locked tile is inert; an unlocked tile launches its map.
State.run = nil
State.pending = nil
select_s.init()
select_s.draw(1 / 60)
local TW, TG, TILE_CY = 84, 6, 116
local sx0 = (C.GAME_W - (#maps.ORDER * TW + (#maps.ORDER - 1) * TG)) * 0.5
local function tile_cx(i) return sx0 + (i - 1) * (TW + TG) + TW * 0.5 end
clicks.left, clicks.mx, clicks.my = true, tile_cx(#maps.ORDER), TILE_CY  -- hardest = locked
select_s.update(1 / 60)
check(State.run == nil and State.pending == nil, "map-select ignores a locked map")
clicks.mx, clicks.my = tile_cx(1), TILE_CY                               -- easiest = unlocked
select_s.update(1 / 60)
clicks.left = false
check(State.run ~= nil and State.run.path_name == maps.ORDER[1], "map-select launches the chosen map")
check(State.pending == "game", "map-select switches to the game scene")
State.pending = nil

State.run = run_mod.new(State.meta, 9, "serpentine"); State.run.money = 9999
game_s.init()
State.ui.selected = "pellet"
clicks.left, clicks.mx, clicks.my = true, 200, 150
game_s.update(1 / 60)
clicks.left = false
check(#State.run.towers >= 1, "game scene placed a tower via click")
game_s.update(1 / 60); game_s.draw(1 / 60)
-- exercise the combat-phase HUD (the ORBITAL action button render path)
State.run.phase = "combat"; game_s.draw(1 / 60); State.run.phase = "building"

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

-- ------------------------------------------------------- report + stats (M1)
-- Report aggregation, damage/leak/spend instrumentation, and the gameover panel
-- live in tests/smoke_report.lua to keep this file under the LOC soft limit; it
-- shares these check counters and the scene globals (State/SwitchScene/input)
-- installed above.
require("tests.smoke_report").run(check, near)

-- ------------------------------------------------------ behavior cards (M2)
-- Pierce/ricochet chaining, brittle, splash rings, and flyer bursts live in
-- tests/smoke_cards.lua (same LOC-split rationale as the report suite).
require("tests.smoke_cards").run(check, near)

-- ----------------------------------------------------- per-tower modifiers (M3)
-- Effective-stat substrate, upgrades + geometry modules, and the inspect panel
-- live in tests/smoke_modifier.lua (same LOC-split rationale).
require("tests.smoke_modifier").run(check, near)

-- ------------------------------------------------------- enemy auras (M4)
-- Formation-aura buffs (shield/speed/regen/armor/stealth) + the kill-the-buffer
-- targeting puzzle live in tests/smoke_aura.lua (same LOC-split rationale).
require("tests.smoke_aura").run(check, near)

-- ----------------------------------------------------------------- result
print(("smoke: %d checks, %d failures"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)

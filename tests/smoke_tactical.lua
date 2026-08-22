-- Tactical UX + speed-control cases (V2-M1). Speed substeps, the wave threat
-- preview, per-tower targeting overrides, the call-next-wave-early action, and
-- the inspect/HUD additions. Run by smoke.lua via M.run(check, near) AFTER
-- smoke_core installs the scene globals (State / SwitchScene / input) -- this
-- suite drives scenes/game with simulated clicks (input._clicks) and keys
-- (input._keys).

local C = require("lib.const")
local harness = require("tests.harness")
local meta = require("lib.meta")
local run_mod = require("lib.run")
local enemy = require("lib.enemy")
local tower = require("lib.tower")
local boss = require("lib.boss")
local wave = require("lib.wave")
local speed = require("lib.speed")
local threat = require("lib.threat")
local inspect = require("lib.inspect")
local game_s = require("scenes.game")
local select_s = require("scenes.select")
local uilib = require("lib.ui")
local pal = require("lib.palette")

local M = {}

-- The acquired target of tower t's next shot (fire once, read the projectile).
local function fired_target(r, t)
  r.projectiles.n = 0
  t.cooldown = 0
  tower.update(r, 1 / 60)
  return r.projectiles.n >= 1 and r.projectiles[1].target or nil
end

local function sum_d(r)
  local s = 0
  for i = 1, r.enemies.n do
    s = s + r.enemies[i].d
  end
  return s
end

local function click_at(mx, my)
  input._clicks.left, input._clicks.mx, input._clicks.my = true, mx, my
end
local function release()
  input._clicks.left = false
end

function M.run(check, near)
  local m = meta.default()

  -- -------------------------------------------------------------- speed model
  check(speed.clamp(1) == 1 and speed.clamp(2) == 2, "speed clamp keeps valid values")
  check(speed.clamp(3) == 1 and speed.clamp(nil) == 1, "speed clamp coerces invalid to 1x")
  check(speed.cycle(1) == 2 and speed.cycle(2) == 1, "speed cycles 1x <-> 2x")
  check(speed.label(2) == "2x" and speed.label(1) == "1x", "speed label formats")

  -- ----------------------------------------------------------- threat preview
  local r = run_mod.new(m, 1, "serpentine")
  local t1 = threat.preview(r, 1)
  check(not t1.boss and t1.budget and t1.budget > 0, "threat: wave 1 is a normal wave with a budget")
  check(threat.preview(r, 7).tags.flyers, "threat: wave 7 pool includes flyers")
  check(threat.preview(r, 4).tags.splits, "threat: wave 4 pool includes splitters")
  local t11 = threat.preview(r, 11)
  check(t11.tags.armor and t11.tags.shield and t11.tags.regen, "threat: deep wave flags armor/shield/regen")
  check(t11.tags.aura and #t11.tag_list > 0, "threat: deep wave flags aura emitters, ordered tag list")
  check(threat.preview(r, 13).tags.stealth, "threat: the veil's stealth shows from wave 13")
  check(threat.preview(r, 7).budget > t1.budget, "threat: budget grows with the wave")
  local t5 = threat.preview(r, 5)
  check(t5.boss and t5.boss_kind == "prism" and t5.budget == nil, "threat: wave 5 is the Prism boss (no normal pool)")
  -- modes
  check(
    threat.preview(run_mod.new(m, 1, "serpentine", "boss_rush"), 1).boss,
    "threat: boss_rush flags wave 1 as a boss"
  )
  check(
    threat.preview(run_mod.new(m, 1, "serpentine", "flyer_swarm"), 1).tags.flyers,
    "threat: flyer_swarm flags flyers from wave 1"
  )
  -- route warning looks one wave past the previewed one; V2-M2 hosts events on
  -- ANY map (procedural transforms), so even no-variant serpentine flags one
  check(
    threat.preview(run_mod.new(m, 1, "zigzag"), 3).route_event,
    "threat: route event flagged before the cadence wave (variant map)"
  )
  check(threat.preview(r, 3).route_event, "threat: route event flagged on a no-variant map too")
  check(not threat.preview(r, 2).route_event, "threat: no route event off the cadence")

  -- ------------------------------------------------------- targeting override
  local rt = run_mod.new(m, 2, "serpentine")
  rt.money = 99999
  local pel = tower.place(rt, 200, 150, "pellet")
  rt.enemies.n = 0
  local a = enemy.spawn(rt, "hulk", 1, 1, 100)
  a.x, a.y, a.armor = 240, 150, 0 -- far along, dist 40
  local b = enemy.spawn(rt, "hulk", 1, 1, 10)
  b.x, b.y, b.armor = 210, 150, 0 -- near, dist 10
  check(fired_target(rt, pel) == a, "targeting default 'first' picks the furthest-along enemy")
  pel.targeting_override = "closest"
  check(fired_target(rt, pel) == b, "targeting override 'closest' picks the nearest enemy")
  pel.targeting_override = "strongest"
  b.hp = 5000
  check(fired_target(rt, pel) == b, "targeting override 'strongest' picks the highest-hp enemy")
  check(
    tower.DEFS.pellet.targeting == "first" and tower.DEFS.pellet.priority == nil,
    "targeting override never mutates the tower def"
  )

  -- focus overrides: prefer a target type regardless of progress/policy
  local ra = run_mod.new(m, 3, "serpentine")
  ra.money = 99999
  local pa = tower.place(ra, 200, 150, "pellet")
  ra.enemies.n = 0
  enemy.spawn(ra, "hulk", 1, 1, 100).x = 240 -- ground, far along
  local fly = enemy.spawn(ra, "wisp", 1, 1, 5)
  fly.x, fly.y = 210, 150
  pa.targeting_override = "air"
  check(fired_target(ra, pa) == fly, "targeting override 'air' focuses the flyer over a higher-progress ground enemy")
  ra.enemies.n = 0
  enemy.spawn(ra, "hulk", 1, 1, 100).x = 240
  wave.boss_scale(ra, 5)
  boss.spawn(ra, "prism", ra.hp_scale)
  ra.boss.x, ra.boss.y = 210, 150
  pa.targeting_override = "boss"
  check(fired_target(ra, pa) == ra.boss, "targeting override 'boss' focuses the boss")
  ra.boss = nil

  local pdef = tower.DEFS.pellet
  check(tower.cycle_targeting(pdef, nil) == "first", "targeting cycles auto -> first")
  check(tower.cycle_targeting(pdef, "boss") == false, "targeting cycle wraps boss -> auto")
  check(
    tower.targeting_label(false) == "auto" and tower.targeting_label("air") == "air",
    "targeting labels (auto + explicit)"
  )

  -- focus options are filtered to what a tower can actually hit
  local function offers(def, focus)
    for _, o in ipairs(tower.targeting_options(def)) do
      if o == focus then return true end
    end
    return false
  end
  check(offers(pdef, "air") and offers(pdef, "boss"), "an all-target tower offers air + boss focuses")
  check(not offers(tower.DEFS.frost, "air"), "a ground-only tower can't cycle to an 'air' focus")
  check(not offers(tower.DEFS.flak, "boss"), "an air-only tower can't cycle to a 'boss' focus")

  -- --------------------------------------------------------- call wave early
  local rc = run_mod.new(m, 4, "serpentine")
  rc.money = 100
  rc.phase = "combat"
  rc.wave_index = 2
  rc.enemies.n = 0
  enemy.spawn(rc, "mote", 1, 1, 10)
  enemy.spawn(rc, "mote", 1, 1, 20)
  check(run_mod.can_call_early(rc), "early call: combat + drained queue + few stragglers + no boss/route")
  rc.phase = "building"
  check(not run_mod.can_call_early(rc), "early call needs the combat phase")
  rc.phase = "combat"
  rc.enemies.n = 0
  check(not run_mod.can_call_early(rc), "early call needs stragglers on the field")
  for i = 1, 5 do
    enemy.spawn(rc, "mote", 1, 1, i * 3)
  end
  check(not run_mod.can_call_early(rc), "early call unavailable with too many enemies")
  rc.enemies.n = 2
  wave.boss_scale(rc, 5)
  boss.spawn(rc, "prism", rc.hp_scale)
  check(not run_mod.can_call_early(rc), "early call unavailable with a live boss")
  rc.boss = nil
  rc.spawn_queue.n, rc.spawn_queue.i = 5, 0
  check(not run_mod.can_call_early(rc), "early call unavailable while still spawning")
  rc.spawn_queue.n, rc.spawn_queue.i = 0, 0
  local money0, wi0 = rc.money, rc.wave_index
  check(run_mod.can_call_early(rc), "early call available once spawns drain")
  check(run_mod.call_early(rc), "call_early fires when available")
  check(rc.money == money0 + C.EARLY_CALL_BONUS, "call_early grants the money bonus")
  check(rc.wave_index == wi0 + 1, "call_early advances to the next wave")
  rc.phase = "building"
  check(not run_mod.call_early(rc), "call_early no-ops when unavailable")

  -- route gate (a variant map): no overlap when a route event is due next
  local rr = run_mod.new(m, 5, "zigzag")
  rr.phase = "combat"
  rr.enemies.n = 0
  enemy.spawn(rr, "mote", 1, 1, 10)
  rr.wave_index = 3 -- nxt = 4: route event due on a variant map
  check(not run_mod.can_call_early(rr), "early call blocked when a route event is due before the next wave")
  rr.wave_index = 1 -- nxt = 2: no route event
  check(run_mod.can_call_early(rr), "early call allowed when no route event is due")

  -- ------------------------------------------------- inspect panel additions
  local ri = run_mod.new(m, 6, "serpentine")
  ri.money = 99999
  local it = tower.place(ri, 200, 150, "pellet")
  harness.reset_gfx()
  inspect.draw(ri, it)
  local calls, rows = harness.gfx_calls(), 0
  for i = 1, #calls do
    local c = calls[i]
    if c.fn == "text" then
      local text, x, y = c.args[1], c.args[2], c.args[3]
      local w, h = usagi.measure_text(text)
      rows = rows + 1
      check(x >= C.HUD_X and x + w <= C.GAME_W, "inspect text fits the sidebar horizontally: " .. text)
      check(y >= 0 and y + h <= C.GAME_H, "inspect text fits vertically: " .. text)
    end
  end
  check(rows >= 5, "inspect panel renders its rows (incl. effective stats + targeting)")
  local act = inspect.button_at(ri, it, C.HUD_X + 10, C.GAME_H - 35)
  check(act and act.type == "targeting", "inspect targeting button hit-tests")

  -- --------------------------------------------------- HUD speed button click
  State.run = run_mod.new(State.meta, 7, "serpentine")
  State.run.money = 9999
  State.ui.speed = 1
  State.pending = nil
  click_at(C.HUD_X + C.HUD_W - 17, 11) -- center of the top-right speed toggle
  game_s.update(1 / 60)
  release()
  check(State.ui.speed == 2, "clicking the HUD speed button cycles to 2x")
  State.ui.speed = 1

  -- ------------------------------------------------ speed substep determinism
  local function combat_run(seed)
    local rr2 = run_mod.new(State.meta, seed, "serpentine")
    rr2.money = 99999
    rr2.lives = 9999
    tower.place(rr2, 200, 150, "pellet")
    tower.place(rr2, 110, 95, "splash")
    run_mod.begin_wave(rr2) -- wave 1 -> combat
    return rr2
  end
  State.pending = nil
  local rA = combat_run(2024)
  State.run = rA
  State.ui.speed = 1
  game_s.update(1 / 60)
  game_s.update(1 / 60)
  local enA, dA, moneyA = rA.enemies.n, sum_d(rA), rA.money
  local rB = combat_run(2024)
  State.run = rB
  State.ui.speed = 2
  game_s.update(1 / 60)
  check(
    rB.enemies.n == enA and near(sum_d(rB), dA) and rB.money == moneyA,
    "2x (one frame) matches 1x (two frames) exactly -- substeps stay deterministic"
  )
  State.ui.speed = 1
  State.pending = nil

  -- ----------------------------------------------- early call via SPACE (scene)
  State.run = run_mod.new(State.meta, 9, "serpentine")
  State.run.money = 50
  State.run.phase = "combat"
  State.run.wave_index = 1
  State.run.enemies.n = 0
  enemy.spawn(State.run, "mote", 1, 1, 10)
  State.pending = nil
  input._keys[input.KEY_SPACE] = true
  game_s.update(1 / 60)
  input._keys[input.KEY_SPACE] = false
  check(State.run.wave_index == 2, "SPACE in combat calls the next wave early")

  -- ----------------------------------------- build-phase threat render bounds
  State.run = run_mod.new(State.meta, 8, "serpentine")
  State.run.money = 9999
  State.run.wave_index = 11
  State.run.phase = "building" -- next wave has many tags
  State.ui.hover_x, State.ui.hover_y = 0, 0
  harness.reset_gfx()
  game_s.draw(1 / 60)
  local dcalls = harness.gfx_calls()
  for i = 1, #dcalls do
    local c = dcalls[i]
    if c.fn == "text" and c.args[2] < C.HUD_X then -- field-area text only
      local x, w = c.args[2], usagi.measure_text(c.args[1])
      check(x + w <= C.HUD_X, "build-phase field text stays out of the HUD: " .. c.args[1])
    end
  end

  -- the build-phase preview ANNOUNCES the next wave's affix by name (M5 fix): the
  -- affix was computed in threat.preview but not drawn, so it never reached the
  -- player before the wave. Pre-seed the (per-wave) cache and assert it renders.
  State.run = run_mod.new(State.meta, 8, "serpentine")
  State.run.money = 9999
  State.run.wave_index = 7
  State.run.phase = "building" -- next wave = 8
  State.run.threat_cache = { wave = 8, tp = { boss = false, tag_list = {}, affix = "Overclock", route_event = false } }
  harness.reset_gfx()
  game_s.draw(1 / 60)
  local announced = false
  for _, c in ipairs(harness.gfx_calls()) do
    if c.fn == "text" and type(c.args[1]) == "string" and c.args[1]:find("AFFIX: Overclock") then announced = true end
  end
  check(announced, "the build-phase preview announces the next wave's affix name")

  -- ------------------------------------------- off-canvas cursor (mouse_over)
  -- input.mouse() keeps reporting a CLAMPED position once the cursor leaves the
  -- window or sits on a letterbox bar, so without input.mouse_over() the field
  -- preview keeps drawing at that stuck edge position. Assert the ghost tower
  -- and the hovered-tower ring both go away, and come back, purely on that flag.
  local hr = run_mod.new(m, 4242, "serpentine")
  State.run = hr
  hr.phase = "building"
  hr.money = 500
  State.ui.selected = "pellet"
  State.ui.sell_mode = false
  State.ui.inspect = nil

  -- a spot on the field that is genuinely buildable, so the ghost has a reason to draw
  local gx, gy
  for x = 20, C.HUD_X - 20, 4 do
    for y = 20, C.GAME_H - 20, 4 do
      if tower.can_place(hr, x, y, "pellet") then
        gx, gy = x, y
        break
      end
    end
    if gx then break end
  end
  check(gx ~= nil, "found a buildable spot for the ghost-preview check")

  local function ghost_drawn(mx, my, over)
    input._clicks.mx, input._clicks.my, input._clicks.over = mx, my, over
    game_s.update(1 / 60)
    harness.reset_gfx()
    game_s.draw(1 / 60)
    for _, c in ipairs(harness.gfx_calls()) do
      -- draw_ghost's box: a rect of side 2*TOWER_R centred on the cursor
      if c.fn == "rect" and c.args[3] == C.TOWER_R * 2 and c.args[4] == C.TOWER_R * 2 then return true end
    end
    return false
  end

  check(ghost_drawn(gx, gy, true), "ghost tower previews while the cursor is over the game area")
  check(not ghost_drawn(gx, gy, false), "ghost tower is suppressed once the cursor leaves the game area")
  check(ghost_drawn(gx, gy, true), "ghost tower returns when the cursor comes back")

  -- hover_valid is the placement gate the click path reads, so it must drop too
  input._clicks.mx, input._clicks.my, input._clicks.over = gx, gy, false
  game_s.update(1 / 60)
  check(not State.ui.hover_valid, "hover_valid is false while the cursor is off the game area")
  input._clicks.over = true
  game_s.update(1 / 60)
  check(State.ui.hover_valid, "hover_valid returns once the cursor is back over the game area")

  -- the hovered-tower range ring keys off the same flag
  local ht = tower.place(hr, gx, gy, "pellet")
  check(ht ~= nil, "placed a tower for the hover-ring check")
  local function ring_drawn(over)
    input._clicks.mx, input._clicks.my, input._clicks.over = gx, gy, over
    State.ui.selected = nil -- so the ghost can't supply the draw calls
    game_s.update(1 / 60)
    harness.reset_gfx()
    game_s.draw(1 / 60)
    for _, c in ipairs(harness.gfx_calls()) do
      if c.fn == "circ" and near(c.args[1], gx) and near(c.args[2], gy) then return true end
    end
    return false
  end
  check(ring_drawn(true), "hovered tower shows its range ring while the cursor is over the field")
  check(not ring_drawn(false), "hovered tower ring is suppressed once the cursor leaves the field")

  State.ui.selected = nil
  input._clicks.over = true

  -- ui.hover_pos: the shared draw-time hover position. Off-canvas it must return
  -- a point that cannot land inside ANY ui rect, so highlight tests just fail.
  local full = { x = 0, y = 0, w = C.GAME_W, h = C.GAME_H }
  input._clicks.mx, input._clicks.my, input._clicks.over = 10, 10, true
  local hx, hy = uilib.hover_pos()
  check(hx == 10 and hy == 10, "ui.hover_pos reports the cursor while it is over the game area")
  check(uilib.in_rect(hx, hy, full), "an on-canvas hover position is inside the screen rect")
  input._clicks.over = false
  hx, hy = uilib.hover_pos()
  check(not uilib.in_rect(hx, hy, full), "an off-canvas hover position is outside every ui rect")
  input._clicks.over = true

  -- and the scene that uses it: a map tile must not light up on a clamped cursor
  local function tile_highlighted(over)
    input._clicks.mx, input._clicks.my, input._clicks.over = 10, 10, over
    harness.reset_gfx()
    select_s.init()
    select_s.draw(1 / 60)
    for _, c in ipairs(harness.gfx_calls()) do
      if c.fn == "rect" and c.args[5] == pal.HUD_SEL then return true end
    end
    return false
  end
  local lit_when_over = tile_highlighted(true)
  check(not tile_highlighted(false), "map tile does not highlight while the cursor is off the game area")
  if lit_when_over then check(tile_highlighted(true), "map tile highlights again once the cursor returns") end
  input._clicks.over = true

  -- cleanup for the suites that follow
  State.run = nil
  State.summary = nil
  State.pending = nil
  State.ui.speed = 1
  input._keys[input.KEY_SPACE] = false
  release()
end

return M

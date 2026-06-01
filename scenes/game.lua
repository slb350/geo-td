-- Gameplay scene: input handling (tower placement / sell / wave start), the
-- per-phase simulation (building -> combat -> upgrade), and rendering of the
-- field, entities, placement ghost, and HUD. Delegates all rules to lib/*.

local C = require("lib.const")
local pal = require("lib.palette")
local path = require("lib.path")
local enemy = require("lib.enemy")
local tower = require("lib.tower")
local proj = require("lib.projectile")
local ring = require("lib.ring")
local aura = require("lib.aura")
local wave = require("lib.wave")
local boss = require("lib.boss")
local fx = require("lib.fx")
local hud = require("lib.hud")
local field = require("lib.field")
local audio = require("lib.audio")
local run_lib = require("lib.run")
local inspect = require("lib.inspect")
local modifier = require("lib.modifier")
local loop = require("lib.loop")
local speed = require("lib.speed")
local threat = require("lib.threat")
local resource = require("lib.resource")
local contracts = require("lib.contracts")
local resonance = require("lib.resonance")
local affix = require("lib.affix")
local arena = require("lib.arena")

local M = {}

local function start_wave(run)
  local n = run.wave_index + 1
  State.ui.inspect = nil -- close the tower-inspect panel when combat starts
  fx.wave_sfx()
  audio.set(wave.is_boss_for(run, n) and "boss" or "combat")
  -- rules (economy + wave/boss spawn) live in run.begin_wave, shared with the
  -- headless sim so balance-affecting logic has exactly one implementation.
  run_lib.begin_wave(run)
end

function M.init()
  -- Run is created by the menu; just reset transient UI on (re)entry.
  if not State.run then
    SwitchScene("menu")
    return
  end
  State.ui.sell_mode = false
  -- Combat bed for the field/build/upgrade loop; boss waves swap to the boss
  -- track in start_wave. (No-op if it is already the current track.)
  audio.set("combat")
end

local function handle_field_click(run, ui, meta, mx, my)
  -- Building is allowed DURING a wave too (genre-standard). Placement/sell/inspect
  -- work in both phases; run_lib.record stamps a combat-phase action with the
  -- current frame so the headless sim/replay re-applies it at the same moment.
  if ui.sell_mode then
    local t = tower.at(run, mx, my)
    if t then
      if ui.inspect == t then ui.inspect = nil end
      local id = t.id
      if tower.sell(run, t) then run_lib.record(run, { sell = { tower = id } }) end -- replay log (M9)
    end
  elseif ui.selected then
    if tower.can_place(run, mx, my, ui.selected) then
      tower.place(run, mx, my, ui.selected)
      run_lib.record(run, { place = { kind = ui.selected, x = mx, y = my } }) -- replay log (M9)
    end
  else
    -- inspect a placed tower (or click empty space to close the panel)
    ui.inspect = tower.at(run, mx, my)
  end
end

local function handle_hud_click(run, ui, meta, mx, my)
  -- while inspecting, the sidebar is the inspect panel: clicks buy upgrades/modules
  if ui.inspect then
    local act = inspect.button_at(run, ui.inspect, mx, my)
    if act and act.type == "upgrade" then
      if modifier.buy_upgrade(run, ui.inspect, act.id) then
        fx.place_sfx()
        run_lib.record(run, { upgrade = { tower = ui.inspect.id, id = act.id } }) -- replay log (M9)
      end
    elseif act and act.type == "module" then
      if modifier.socket_module(run, ui.inspect, act.id) then
        fx.place_sfx()
        run_lib.record(run, { module = { tower = ui.inspect.id, id = act.id } }) -- replay log (M9)
      end
    elseif act and act.type == "reroll" then
      local ok, module_id = modifier.reroll_module(run, ui.inspect)
      if ok then
        fx.place_sfx()
        run_lib.record(run, { reroll = { tower = ui.inspect.id, id = module_id } }) -- replay log (M9)
      end
    elseif act and act.type == "targeting" then
      ui.inspect.targeting_override = tower.cycle_targeting(ui.inspect.def, ui.inspect.targeting_override)
      fx.click_sfx()
      run_lib.record(run, {
        targeting = {
          tower = ui.inspect.id,
          value = ui.inspect.targeting_override or false,
        },
      }) -- replay log (M9)
    end
    return
  end
  local act = hud.button_at(run, mx, my)
  if not act then return end
  if act.type == "speed" then
    ui.speed = speed.cycle(ui.speed or 1)
    fx.click_sfx()
  elseif act.type == "select" then
    if tower.available(meta, act.kind, run.mode) then
      ui.selected = act.kind
      ui.sell_mode = false
    end
  elseif act.type == "start" then
    if run.phase == "building" then start_wave(run) end
  elseif act.type == "orbital" then
    if run_lib.orbital_strike(run) then
      fx.orbital()
      run_lib.record(run, { orbital = true })
    end
  elseif act.type == "sell" then
    ui.sell_mode = not ui.sell_mode
    ui.selected = nil
  end
end

function M.update(dt)
  fx.update(dt)
  local run, ui, meta = State.run, State.ui, State.meta
  if not run then
    SwitchScene("menu")
    return
  end
  resonance.update(run) -- keep circuits fresh for the build-phase overlay + inspect

  local mx, my = input.mouse()
  ui.hover_x, ui.hover_y = mx, my
  ui.hover_valid = ui.selected ~= nil
    and not ui.sell_mode
    and mx < C.HUD_X
    and tower.can_place(run, mx, my, ui.selected)

  -- keyboard shortcuts
  if input.key_pressed(input.KEY_1) then
    ui.selected = "pellet"
    ui.sell_mode = false
    ui.inspect = nil
  end
  if input.key_pressed(input.KEY_2) then
    ui.selected = "splash"
    ui.sell_mode = false
    ui.inspect = nil
  end
  if input.key_pressed(input.KEY_3) and tower.available(meta, "frost", run.mode) then
    ui.selected = "frost"
    ui.sell_mode = false
    ui.inspect = nil
  end
  if input.key_pressed(input.KEY_4) and tower.available(meta, "rail", run.mode) then
    ui.selected = "rail"
    ui.sell_mode = false
    ui.inspect = nil
  end
  if input.key_pressed(input.KEY_5) and tower.available(meta, "flak", run.mode) then
    ui.selected = "flak"
    ui.sell_mode = false
    ui.inspect = nil
  end
  if input.KEY_6 and input.key_pressed(input.KEY_6) then
    ui.selected = "drill"
    ui.sell_mode = false
    ui.inspect = nil
  end
  if input.key_pressed(input.KEY_O) then
    if run_lib.orbital_strike(run) then
      fx.orbital()
      run_lib.record(run, { orbital = true })
    end
  end
  if input.KEY_D and input.key_pressed(input.KEY_D) then -- D: Discharge (spend charge)
    if run_lib.discharge(run) then
      fx.orbital()
      run_lib.record(run, { discharge = true })
    end
  end
  if input.key_pressed(input.KEY_S) then
    ui.sell_mode = not ui.sell_mode
    ui.selected = nil
    ui.inspect = nil
  end
  if input.KEY_F and input.key_pressed(input.KEY_F) then -- F: cycle combat speed
    ui.speed = speed.cycle(ui.speed or 1)
  end
  -- Space starts the wave while building, or calls the next wave early while in
  -- combat (when the field is nearly clear and no route event is due). Enter is
  -- NOT read here -- the engine reserves it for the built-in pause menu; the HUD
  -- action button is the mouse-driven equivalent.
  if input.key_pressed(input.KEY_SPACE) then
    if run.phase == "building" then
      start_wave(run)
    elseif run.phase == "combat" then
      local wave0, frame0 = run.wave_index, run.combat_frame or 0
      if run_lib.call_early(run) then
        run_lib.record(run, { call_early = true, wave = wave0, frame = frame0 })
        fx.wave_sfx()
      end
    end
  end

  -- mouse
  if input.mouse_pressed(input.MOUSE_LEFT) then
    if mx >= C.HUD_X then
      handle_hud_click(run, ui, meta, mx, my)
    else
      handle_field_click(run, ui, meta, mx, my)
    end
  end
  if input.mouse_pressed(input.MOUSE_RIGHT) then
    ui.selected = nil
    ui.sell_mode = false
    ui.inspect = nil
  end

  -- simulation. Combat advances in FIXED C.SIM_DT steps via an accumulator, so
  -- it is deterministic + frame-rate-independent; speed (1x/2x) multiplies how
  -- much real time feeds the accumulator each frame. Input/UI/fx above ran once.
  if run.phase == "combat" then
    run.sim_acc = (run.sim_acc or 0) + dt * speed.clamp(ui.speed or 1)
    local steps = 0
    while run.sim_acc >= C.SIM_DT and steps < C.MAX_SIM_STEPS do
      run.sim_acc = run.sim_acc - C.SIM_DT
      steps = steps + 1
      local spawns_done = loop.step(run, C.SIM_DT) -- canonical combat step (shared with the sim)
      run.combat_frame = (run.combat_frame or 0) + 1
      -- Death is decisive even on a frame the wave also clears: a fatal leak means
      -- the wave was NOT held, so no contract reward -- we fall through to gameover
      -- (the run.lives<=0 check below). Matches lib/sim's clear-vs-death ordering.
      if run.lives <= 0 then break end
      local cleared = run.enemies.n == 0 and (not run.boss or run.boss.dead)
      if spawns_done and cleared then
        run.phase = "building"
        run.draft = nil
        contracts.grant_reward(run) -- wave held: pay the contract, then clear it
        contracts.expire(run)
        affix.expire(run) -- clear the wave's affix (M5)
        SwitchScene("upgrade")
        break
      end
    end
  else
    -- build phase: only in-flight projectiles + lingering rings keep ticking
    proj.update(run, dt)
    ring.update(run, dt)
  end

  if run.lives <= 0 then
    run.final_wave = run.wave_index
    SwitchScene("gameover")
  end
end

local function draw_ghost(run, ui)
  local col = ui.hover_valid and pal.GHOST_OK or pal.GHOST_BAD
  local def = tower.DEFS[ui.selected]
  gfx.circ(ui.hover_x, ui.hover_y, def.range * run.mods.range_mult, col)
  gfx.rect(ui.hover_x - C.TOWER_R, ui.hover_y - C.TOWER_R, C.TOWER_R * 2, C.TOWER_R * 2, col)
end

-- Build-phase threat preview (M1): what the upcoming wave demands the player
-- counter, drawn top-left of the field. Pure data from lib/threat (no rng);
-- cached per wave so the draw frame doesn't rebuild it (the preview is constant
-- for the whole build phase).
local function draw_threat(run)
  local n = run.wave_index + 1
  local c = run.threat_cache
  if not c or c.wave ~= n then
    c = { wave = n, tp = threat.preview(run, n) }
    run.threat_cache = c
  end
  local tp = c.tp
  local y = 6
  if tp.boss then
    local def = boss.DEFS[tp.boss_kind]
    gfx.text("NEXT: BOSS " .. ((def and def.name) or tp.boss_kind), 6, y, gfx.COLOR_RED)
    y = y + 12
  else
    gfx.text("NEXT W" .. n, 6, y, pal.TEXT)
    y = y + 12
    if #tp.tag_list > 0 then
      local parts = {}
      for i = 1, #tp.tag_list do
        parts[i] = threat.TAG_LABEL[tp.tag_list[i]]
      end
      gfx.text(table.concat(parts, " "), 6, y, gfx.COLOR_ORANGE)
      y = y + 12
    end
    if tp.affix then -- announce the affix so it can be countered (M5)
      gfx.text("AFFIX: " .. tp.affix, 6, y, gfx.COLOR_YELLOW)
      y = y + 12
    end
  end
  if tp.route_event then gfx.text("route shift after this wave", 6, y, gfx.COLOR_PINK) end
end

-- Combat-phase label naming the boss's imminent telegraphed ability, clamped to
-- the field so it never spills into the HUD or off-screen.
local function draw_boss_label(run)
  local b = run.boss
  if not b or b.dead then return end
  local label = (b.shock_warn and "SHOCKWAVE") or (b.invuln_warn and "PHASING") or (b.spawn_warn and "ADDS")
  if not label then return end
  local w = usagi.measure_text(label)
  local lx = math.max(2, math.min(b.x - w * 0.5, C.HUD_X - w - 2))
  local ly = math.max(2, b.y - b.size - 18)
  gfx.text(label, lx, ly, gfx.COLOR_YELLOW)
end

-- Nearest live enemy within a small pick radius of (x, y), or nil.
local function enemy_at(run, x, y)
  local list = run.enemies
  local best, best_d2
  for i = 1, list.n do
    local e = list[i]
    if not e.dead then
      local r = (e.size or 4) + 3
      local dx, dy = e.x - x, e.y - y
      local d2 = dx * dx + dy * dy
      if d2 <= r * r and (not best_d2 or d2 < best_d2) then
        best, best_d2 = e, d2
      end
    end
  end
  return best
end

-- Hover tooltip naming an aura emitter's buff (the "kill the buffer" puzzle).
local function draw_aura_tooltip(run, ui)
  if ui.hover_x >= C.HUD_X then return end
  local e = enemy_at(run, ui.hover_x, ui.hover_y)
  if not (e and e.def.aura) then return end
  local label = e.def.aura.kind .. " aura"
  local w = usagi.measure_text(label)
  local lx = math.max(2, math.min(ui.hover_x + 6, C.HUD_X - w - 2))
  local ly = math.max(2, ui.hover_y - 10)
  gfx.rect_fill(lx - 1, ly - 1, w + 2, 9, pal.HUD_BG)
  gfx.text(label, lx, ly, gfx.COLOR_PINK)
end

function M.draw(dt)
  local run, ui = State.run, State.ui
  gfx.clear(pal.BG)
  field.draw(pal, usagi.elapsed)
  path.draw(run.path, pal, C.PATH_WIDTH, usagi.elapsed)
  resource.draw(run) -- resource prisms + extract radius (under towers)
  ring.draw(run) -- ground-layer splash rings, under towers/enemies

  for i = 1, #run.towers do
    tower.draw(run, run.towers[i], false)
  end
  -- range ring for the tower under the cursor
  local hovered = tower.at(run, ui.hover_x, ui.hover_y)
  if hovered then tower.draw(run, hovered, true) end

  aura.draw(run) -- faint formation-aura buff-zone rings, under the enemies
  affix.draw(run) -- affix rings/icons on affected enemies (M5)
  if run.boss then arena.draw(run) end -- arena link lines, under the enemies (M6)
  enemy.draw(run)
  if run.boss then boss.draw(run) end
  proj.draw(run)

  if ui.selected and not ui.sell_mode and ui.hover_x < C.HUD_X then draw_ghost(run, ui) end

  fx.draw()

  -- tactical overlays (M1)
  if run.phase == "building" then
    draw_threat(run)
    resonance.draw(run) -- module circuit links + active-proof markers (M4)
  else
    draw_boss_label(run)
  end
  draw_aura_tooltip(run, ui)

  -- field banner
  local banner
  if run.phase == "building" then
    banner = "BUILD  -  " .. run.map_name .. "  -  place towers, then START"
  elseif wave.is_boss_for(run, run.wave_index) then
    banner = "BOSS  -  wave " .. run.wave_index
  else
    banner = "WAVE " .. run.wave_index
    if run.wave_affix then banner = banner .. "   [" .. run.wave_affix.name .. "]" end -- affix (M5)
  end
  gfx.text(banner, 6, C.GAME_H - 14, pal.TEXT_DIM)
  if run.phase == "combat" and run_lib.can_call_early(run) then
    gfx.text("SPACE: call next wave early  +$" .. C.EARLY_CALL_BONUS, 6, C.GAME_H - 26, gfx.COLOR_GREEN)
  end
  if run.phase == "combat" and run_lib.can_discharge(run) then
    gfx.text("D: DISCHARGE  " .. math.floor(run.charge) .. " charge", 6, C.GAME_H - 38, gfx.COLOR_PEACH)
  end

  if ui.inspect then
    inspect.draw(run, ui.inspect)
  else
    hud.draw(run, State.meta, ui)
  end
end

return M

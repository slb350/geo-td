-- Gameplay scene: input handling (tower placement / sell / wave start), the
-- per-phase simulation (building -> combat -> upgrade), and rendering of the
-- field, entities, placement ghost, and HUD. Delegates all rules to lib/*.

local C    = require("lib.const")
local pal  = require("lib.palette")
local path = require("lib.path")
local enemy = require("lib.enemy")
local tower = require("lib.tower")
local proj  = require("lib.projectile")
local wave  = require("lib.wave")
local boss  = require("lib.boss")
local fx    = require("lib.fx")
local hud   = require("lib.hud")
local field = require("lib.field")

local M = {}

local function start_wave(run)
  local n = run.wave_index + 1
  run.phase = "combat"
  fx.wave_sfx()
  -- start-of-wave economy from upgrades
  local mods = run.mods
  if mods.interest > 0 then
    run.money = run.money + math.floor(run.money * mods.interest)
  end
  if mods.life_per_wave > 0 then
    run.lives = run.lives + mods.life_per_wave
  end
  if wave.is_boss(n) then
    wave.boss_scale(run, n)
    boss.spawn(run, boss.for_wave(n), run.hp_scale)
  else
    run.boss = nil
    wave.start(run, n)
  end
end

function M.init()
  -- Run is created by the menu; just reset transient UI on (re)entry.
  if not State.run then SwitchScene("menu"); return end
  State.ui.sell_mode = false
end

local function handle_field_click(run, ui, meta, mx, my)
  if ui.sell_mode then
    local t = tower.at(run, mx, my)
    if t then tower.sell(run, t) end
  elseif ui.selected then
    if tower.can_place(run, mx, my, ui.selected) then
      tower.place(run, mx, my, ui.selected)
    end
  end
end

local function handle_hud_click(run, ui, meta, mx, my)
  local act = hud.button_at(run, mx, my)
  if not act then return end
  if act.type == "select" then
    if tower.available(meta, act.kind) then
      ui.selected = act.kind
      ui.sell_mode = false
    end
  elseif act.type == "start" then
    if run.phase == "building" then start_wave(run) end
  elseif act.type == "sell" then
    ui.sell_mode = not ui.sell_mode
    ui.selected = nil
  end
end

function M.update(dt)
  fx.update(dt)
  local run, ui, meta = State.run, State.ui, State.meta
  if not run then SwitchScene("menu"); return end

  local mx, my = input.mouse()
  ui.hover_x, ui.hover_y = mx, my
  ui.hover_valid = ui.selected ~= nil and not ui.sell_mode and mx < C.HUD_X
    and tower.can_place(run, mx, my, ui.selected)

  -- keyboard shortcuts
  if input.key_pressed(input.KEY_1) then ui.selected = "pellet"; ui.sell_mode = false end
  if input.key_pressed(input.KEY_2) then ui.selected = "splash"; ui.sell_mode = false end
  if input.key_pressed(input.KEY_3) and tower.available(meta, "frost") then
    ui.selected = "frost"; ui.sell_mode = false
  end
  if input.key_pressed(input.KEY_S) then ui.sell_mode = not ui.sell_mode; ui.selected = nil end
  if (input.key_pressed(input.KEY_SPACE) or input.key_pressed(input.KEY_ENTER))
    and run.phase == "building" then
    start_wave(run)
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
    ui.selected = nil; ui.sell_mode = false
  end

  -- simulation
  if run.phase == "combat" then
    local boss_wave = wave.is_boss(run.wave_index)
    local spawns_done = boss_wave or wave.update(run, dt)
    enemy.update(run, dt)
    if boss_wave then boss.update(run, dt) end
    tower.update(run, dt)
    proj.update(run, dt)
    local cleared = run.enemies.n == 0 and (not run.boss or run.boss.dead)
    if spawns_done and cleared then
      run.phase = "building"
      run.draft = nil
      SwitchScene("upgrade")
    end
  else
    proj.update(run, dt)
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

function M.draw(dt)
  local run, ui = State.run, State.ui
  gfx.clear(pal.BG)
  field.draw(pal, usagi.elapsed)
  path.draw(run.path, pal, C.PATH_WIDTH, usagi.elapsed)

  for i = 1, #run.towers do
    tower.draw(run, run.towers[i], false)
  end
  -- range ring for the tower under the cursor
  local hovered = tower.at(run, ui.hover_x, ui.hover_y)
  if hovered then tower.draw(run, hovered, true) end

  enemy.draw(run)
  if run.boss then boss.draw(run) end
  proj.draw(run)

  if ui.selected and not ui.sell_mode and ui.hover_x < C.HUD_X then
    draw_ghost(run, ui)
  end

  fx.draw()

  -- field banner
  local banner
  if run.phase == "building" then
    banner = "BUILD  -  place towers, then START"
  elseif wave.is_boss(run.wave_index) then
    banner = "BOSS  -  wave " .. run.wave_index
  else
    banner = "WAVE " .. run.wave_index
  end
  gfx.text(banner, 6, C.GAME_H - 14, pal.TEXT_DIM)

  hud.draw(run, State.meta, ui)
end

return M

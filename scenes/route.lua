-- Between-wave route-mutation event (M7): on maps with route variants, the
-- player picks among predefined alternate polylines (forks / shortcuts) before
-- the next wave. Adopting a route auto-refunds any tower the new path
-- invalidates. The field is clear here, so the scalar-distance model is
-- preserved. An input lockout ignores a click carried over from the upgrade
-- screen (mirrors scenes/upgrade.lua).

local C       = require("lib.const")
local pal     = require("lib.palette")
local path    = require("lib.path")
local fx      = require("lib.fx")
local ui      = require("lib.ui")
local pathmut = require("lib.pathmut")

local M = {}

local TILE_W, TILE_H, GAP = 96, 96, 10
local ROW_Y, PREV_H, PAD = 70, 64, 6

-- Centered row of tiles, one per route option.
local function tiles(n)
  local out = {}
  local x0 = (C.GAME_W - (n * TILE_W + (n - 1) * GAP)) * 0.5
  for i = 1, n do
    out[i] = { x = x0 + (i - 1) * (TILE_W + GAP), y = ROW_Y, w = TILE_W, h = TILE_H }
  end
  return out
end

function M.init()
  if not State.run then SwitchScene("menu"); return end
  State.run.route_ready = false   -- require a fresh click before accepting a choice
  -- routes are fixed while this modal screen is shown (run.path only changes on
  -- choose, which exits), so compute them once here rather than every frame.
  State.run.route_options = pathmut.routes(State.run)
end

local function choose(run, i)
  local opt = run.route_options[i]
  if opt then
    pathmut.apply(run, opt.nodes)   -- swaps the route + auto-refunds invalid towers
    fx.click_sfx()
  end
  SwitchScene("game")
end

function M.update(dt)
  local run = State.run
  if not run then SwitchScene("menu"); return end
  if not run.route_ready then
    if not input.mouse_held(input.MOUSE_LEFT) then run.route_ready = true end
    return
  end
  if input.mouse_pressed(input.MOUSE_LEFT) then
    local mx, my = input.mouse()
    local ts = tiles(#run.route_options)
    for i = 1, #ts do
      if ui.in_rect(mx, my, ts[i]) then return choose(run, i) end
    end
  end
end

function M.draw(dt)
  gfx.clear(pal.BG)
  ui.center_text("ROUTE SHIFT", 24, gfx.COLOR_PINK, 2)
  ui.center_text("choose a route for the waves ahead", 52, pal.TEXT_DIM, 1)

  local routes = State.run.route_options or {}
  local ts = tiles(#routes)
  local mx, my = input.mouse()
  for i = 1, #routes do
    local t, opt = ts[i], routes[i]
    local hover = ui.in_rect(mx, my, t)
    gfx.rect_fill(t.x, t.y, t.w, t.h, pal.HUD_PANEL)
    gfx.rect(t.x, t.y, t.w, t.h, hover and pal.HUD_SEL or pal.PATH_EDGE)
    gfx.rect_fill(t.x + PAD, t.y + PAD, t.w - PAD * 2, PREV_H, pal.FIELD_BG)
    path.draw_preview(opt.nodes, t.x + PAD, t.y + PAD, t.w - PAD * 2, PREV_H,
      pal.PATH_CORE, pal.SPAWN, pal.CORE)
    local label = opt.current and (opt.label .. " (current)") or opt.label
    gfx.text(label, t.x + (t.w - usagi.measure_text(label)) * 0.5, t.y + t.h - 14,
      opt.current and pal.MONEY or pal.TEXT)
  end

  ui.center_text("a tower on a new route is refunded in full", C.GAME_H - 14, pal.TEXT_DIM, 1)
end

return M

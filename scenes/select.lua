-- Map select. Maps are shown easiest -> hardest (maps.ORDER); each is unlocked
-- by reaching wave >= maps.UNLOCK_WAVE on the previous one. Each tile shows a
-- mini path preview, difficulty pips, and the best wave reached. Click an
-- unlocked tile to start a run on it; right-click returns to the menu.

local C     = require("lib.const")
local pal   = require("lib.palette")
local run   = require("lib.run")
local meta  = require("lib.meta")
local maps  = require("lib.maps")
local fx    = require("lib.fx")
local ui    = require("lib.ui")
local audio = require("lib.audio")

local M = {}

local TILE_W, TILE_H, GAP = 84, 124, 6
local ROW_Y, PREV_H, PAD = 54, 60, 6

-- Static tile geometry (one per map, in difficulty order).
local tiles = {}
do
  local n = #maps.ORDER
  local x0 = (C.GAME_W - (n * TILE_W + (n - 1) * GAP)) * 0.5
  for i = 1, n do
    tiles[i] = { x = x0 + (i - 1) * (TILE_W + GAP), y = ROW_Y, w = TILE_W, h = TILE_H,
                 name = maps.ORDER[i] }
  end
end

function M.init()
  audio.set("menu")
end

local function start_map(name)
  local t = os.time and os.time() or 0
  local seed = t + State.meta.total_runs * 7919 + math.floor(usagi.elapsed * 1000)
  State.run = run.new(State.meta, seed, name)
  State.ui.selected = "pellet"
  State.ui.sell_mode = false
  fx.click_sfx()
  SwitchScene("game")
end

function M.update(dt)
  if input.mouse_pressed(input.MOUSE_RIGHT) then
    fx.click_sfx(); SwitchScene("menu"); return
  end
  if input.mouse_pressed(input.MOUSE_LEFT) then
    local mx, my = input.mouse()
    for i = 1, #tiles do
      if ui.in_rect(mx, my, tiles[i]) and meta.is_map_unlocked(State.meta, tiles[i].name) then
        start_map(tiles[i].name)
        return
      end
    end
  end
end

-- Text horizontally centered within a tile's column.
local function tile_text(t, text, y, col, scale)
  scale = scale or 1
  local w = usagi.measure_text(text) * scale
  gfx.text_ex(text, t.x + (t.w - w) * 0.5, y, scale, 0, col, 1)
end

-- Path polyline of `layout` fitted (aspect-preserving) into a box.
local function draw_preview(layout, bx, by, bw, bh, line_col, lit)
  local nodes = layout.nodes
  local s = math.min(bw / C.FIELD_W, bh / C.FIELD_H)
  local ox = bx + (bw - C.FIELD_W * s) * 0.5
  local oy = by + (bh - C.FIELD_H * s) * 0.5
  for i = 1, #nodes - 1 do
    gfx.line(ox + nodes[i][1] * s, oy + nodes[i][2] * s,
             ox + nodes[i + 1][1] * s, oy + nodes[i + 1][2] * s, line_col)
  end
  local a, b = nodes[1], nodes[#nodes]
  gfx.circ_fill(ox + a[1] * s, oy + a[2] * s, 1.5, lit and pal.SPAWN or gfx.COLOR_DARK_GRAY)
  gfx.circ_fill(ox + b[1] * s, oy + b[2] * s, 1.5, lit and pal.CORE or gfx.COLOR_DARK_GRAY)
end

-- Difficulty pips: `rank` of `total` filled, centered in the tile.
local function draw_pips(t, rank, total, lit)
  local pw, gap = 5, 2
  local x0 = t.x + (t.w - (total * pw + (total - 1) * gap)) * 0.5
  local y = t.y + 88
  for k = 1, total do
    local x = x0 + (k - 1) * (pw + gap)
    if k <= rank then
      gfx.rect_fill(x, y, pw, 4, lit and gfx.COLOR_ORANGE or gfx.COLOR_DARK_GRAY)
    else
      gfx.rect(x, y, pw, 4, gfx.COLOR_DARK_GRAY)
    end
  end
end

function M.draw(dt)
  gfx.clear(pal.BG)
  ui.center_text("SELECT MAP", 20, gfx.COLOR_WHITE, 2)

  local mx, my = input.mouse()
  local total = #maps.ORDER
  for i = 1, total do
    local t = tiles[i]
    local layout = maps.get(t.name)
    local lit = meta.is_map_unlocked(State.meta, t.name)
    local hover = lit and ui.in_rect(mx, my, t)

    gfx.rect_fill(t.x, t.y, t.w, t.h, pal.HUD_PANEL)
    gfx.rect(t.x, t.y, t.w, t.h,
      hover and pal.HUD_SEL or (lit and pal.PATH_EDGE or gfx.COLOR_DARK_GRAY))

    -- preview panel
    gfx.rect_fill(t.x + PAD, t.y + PAD, t.w - PAD * 2, PREV_H, pal.FIELD_BG)
    draw_preview(layout, t.x + PAD, t.y + PAD, t.w - PAD * 2, PREV_H,
      lit and pal.PATH_CORE or gfx.COLOR_DARK_GRAY, lit)

    tile_text(t, layout.name, t.y + 72, lit and pal.TEXT or pal.TEXT_DIM, 1)
    draw_pips(t, i, total, lit)

    -- status line: best wave / NEW / LOCKED
    local best = State.meta.map_best[t.name] or 0
    local status, scol
    if not lit then status, scol = "LOCKED", pal.BAD
    elseif best > 0 then status, scol = "best W" .. best, pal.GOOD
    else status, scol = "NEW", pal.MONEY end
    tile_text(t, status, t.y + 102, scol, 1)
  end

  ui.center_text("reach wave " .. maps.UNLOCK_WAVE .. " on a map to unlock the next",
    C.GAME_H - 28, pal.TEXT_DIM, 1)
  ui.center_text("click a map to play    -    right-click: back",
    C.GAME_H - 14, pal.TEXT_DIM, 1)
end

return M

-- Main menu: start a run, and spend meta-currency ("bank") on permanent
-- unlocks. Reads/writes the global State (State.meta, State.run, State.ui).

local C    = require("lib.const")
local pal  = require("lib.palette")
local run  = require("lib.run")
local meta = require("lib.meta")
local fx   = require("lib.fx")
local ui   = require("lib.ui")

local M = {}

local start_btn = { x = 190, y = 104, w = 100, h = 24 }

-- Shop rows, laid out from meta.SHOP.
local rows = {}
local SHOP_X, SHOP_Y = 96, 164
local SHOP_W, SHOP_PAD = 288, 4
local SHOP_TEXT_X_PAD = 8

-- Geometry depends only on the (constant) measured text height and the static
-- SHOP, so lay out once and cache. The cache is a file-scope local, so Usagi's
-- live-reload (which resets file-scope locals) re-measures on the next call.
local row_text_h
local function layout_rows()
  if row_text_h then return row_text_h end
  local text_h = ui.text_height()
  local row_h = text_h * 2 + SHOP_PAD * 2
  local y = SHOP_Y
  for i = 1, #meta.SHOP do
    local r = rows[i] or {}
    r.id, r.x, r.y, r.w, r.h = meta.SHOP[i].id, SHOP_X, y, SHOP_W, row_h
    rows[i] = r
    y = y + row_h + SHOP_PAD
  end
  row_text_h = text_h
  return row_text_h
end

local function start_run()
  local t = os.time and os.time() or 0
  local seed = t + State.meta.total_runs * 7919 + math.floor(usagi.elapsed * 1000)
  State.run = run.new(State.meta, seed)
  State.ui.selected = "pellet"
  State.ui.sell_mode = false
  fx.click_sfx()
  SwitchScene("game")
end

function M.update(dt)
  if input.key_pressed(input.KEY_SPACE) or input.key_pressed(input.KEY_ENTER)
    or input.pressed(input.BTN1) then
    start_run()
    return
  end
  if input.mouse_pressed(input.MOUSE_LEFT) then
    local mx, my = input.mouse()
    if ui.in_rect(mx, my, start_btn) then
      start_run()
      return
    end
    layout_rows()
    for i = 1, #rows do
      if ui.in_rect(mx, my, rows[i]) and meta.can_buy(State.meta, rows[i].id) then
        meta.buy(State.meta, rows[i].id)
      end
    end
  end
end

function M.draw(dt)
  local text_h = layout_rows()
  gfx.clear(pal.BG)
  ui.center_text("USAGI GEO TD", 34, gfx.COLOR_WHITE, 2)
  ui.center_text("a geometric tower defense", 64, pal.TEXT_DIM, 1)

  local m = State.meta
  ui.center_text("best wave " .. m.best_wave .. "    bank " .. m.currency, 84, pal.TEXT_DIM, 1)

  -- start button
  gfx.rect_fill(start_btn.x, start_btn.y, start_btn.w, start_btn.h, pal.GOOD)
  ui.center_text("START RUN", start_btn.y + 8, gfx.COLOR_BLACK, 1)

  ui.center_text("UNLOCKS", 148, pal.TEXT, 1)
  for i = 1, #meta.SHOP do
    local it = meta.SHOP[i]
    local r = rows[i]
    local owned = m.unlocks[it.id] == true
    local afford = m.currency >= it.cost
    local name_y = r.y + SHOP_PAD
    local desc_y = name_y + text_h
    gfx.rect_fill(r.x, r.y, r.w, r.h, pal.HUD_PANEL)
    -- cost / status, right-aligned on the name's line
    local tag = owned and "OWNED" or (it.cost .. " bank")
    local tag_col = owned and pal.GOOD or (afford and pal.MONEY or pal.TEXT_DIM)
    gfx.text(tag, r.x + r.w - usagi.measure_text(tag) - SHOP_TEXT_X_PAD, name_y, tag_col)
    -- name + description (left), kept clear of the cost column
    gfx.text(it.name, r.x + SHOP_TEXT_X_PAD, name_y, owned and pal.GOOD or pal.TEXT)
    gfx.text(it.desc, r.x + SHOP_TEXT_X_PAD, desc_y, pal.TEXT_DIM)
  end

  ui.center_text("click START or press Z / Space", C.GAME_H - text_h, pal.TEXT_DIM, 1)
end

return M

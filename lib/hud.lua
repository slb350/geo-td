-- HUD sidebar: run stats, the tower build palette, the Start-wave / Sell
-- buttons, and a contextual hint line. Owns its own button rects and exposes
-- button_at() for click hit-testing; the game scene owns selection state (ui).

local C     = require("lib.const")
local pal   = require("lib.palette")
local tower = require("lib.tower")

local M = {}

local PAD = 6
local BX = C.HUD_X + PAD
local BW = C.HUD_W - PAD * 2

-- Tower palette buttons (vertical list).
local btns = {}
do
  local y = 80
  for i = 1, #tower.ORDER do
    btns[i] = { kind = tower.ORDER[i], x = BX, y = y, w = BW, h = 24 }
    y = y + 28
  end
end
local start_btn = { x = BX, y = C.GAME_H - 46, w = BW, h = 18 }
local sell_btn  = { x = BX, y = C.GAME_H - 24, w = BW, h = 18 }

local function in_rect(px, py, r)
  return px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h
end

-- Greedy word-wrap to a pixel width, using the real font metrics.
local function wrap(text, max_w)
  local lines, cur = {}, ""
  for word in text:gmatch("%S+") do
    local trial = cur == "" and word or (cur .. " " .. word)
    if usagi.measure_text(trial) <= max_w then
      cur = trial
    else
      if cur ~= "" then lines[#lines + 1] = cur end
      cur = word
    end
  end
  if cur ~= "" then lines[#lines + 1] = cur end
  return lines
end

-- Returns an action for a sidebar click, or nil. Actions:
--   { type = "select", kind = <towerkind> }
--   { type = "start" }
--   { type = "sell" }
function M.button_at(run, mx, my)
  for i = 1, #btns do
    if in_rect(mx, my, btns[i]) then
      return { type = "select", kind = btns[i].kind }
    end
  end
  if in_rect(mx, my, start_btn) then return { type = "start" } end
  if in_rect(mx, my, sell_btn) then return { type = "sell" } end
  return nil
end

-- Mini geometric icon for a tower kind, centered at (cx, cy).
local function icon(kind, cx, cy, color)
  local r = 5
  local shape = tower.DEFS[kind].shape
  if shape == "diamond" then
    gfx.tri_fill(cx, cy - r, cx - r, cy, cx + r, cy, color)
    gfx.tri_fill(cx, cy + r, cx - r, cy, cx + r, cy, color)
  elseif shape == "hex" then
    local px, py
    for k = 0, 6 do
      local a = (k / 6) * math.pi * 2
      local nx, ny = cx + math.cos(a) * r, cy + math.sin(a) * r
      if k > 0 then gfx.tri_fill(cx, cy, px, py, nx, ny, color) end
      px, py = nx, ny
    end
  else
    gfx.rect_fill(cx - r, cy - r, r * 2, r * 2, color)
  end
end

function M.draw(run, meta, ui)
  -- panel
  gfx.rect_fill(C.HUD_X, 0, C.HUD_W, C.GAME_H, pal.HUD_BG)
  gfx.line(C.HUD_X, 0, C.HUD_X, C.GAME_H, pal.PATH_EDGE)

  -- stats
  gfx.text("WAVE " .. run.wave_index, BX, 8, pal.TEXT)
  gfx.text("$" .. run.money, BX, 26, pal.MONEY)
  gfx.text("LIVES " .. run.lives, BX, 42, pal.LIVES)
  gfx.text("SCORE " .. run.score, BX, 58, pal.TEXT_DIM)

  -- tower palette
  for i = 1, #btns do
    local b = btns[i]
    local kind = b.kind
    local def = tower.DEFS[kind]
    local avail = tower.available(meta, kind)
    local cost = tower.cost(run, kind)
    local afford = run.money >= cost
    local selected = (ui.selected == kind)

    gfx.rect_fill(b.x, b.y, b.w, b.h, pal.HUD_PANEL)
    if selected then
      gfx.rect_ex(b.x, b.y, b.w, b.h, 1, pal.HUD_SEL)
    end
    local body = avail and (afford and pal.resolve(def.color) or gfx.COLOR_DARK_GRAY) or gfx.COLOR_DARK_GRAY
    icon(kind, b.x + 12, b.y + b.h * 0.5, body)
    local name_col = avail and pal.TEXT or pal.TEXT_DIM
    gfx.text(def.name, b.x + 24, b.y + 3, name_col)
    if avail then
      gfx.text("$" .. cost, b.x + 24, b.y + 13, afford and pal.MONEY or pal.BAD)
    else
      gfx.text("LOCKED", b.x + 24, b.y + 13, pal.TEXT_DIM)
    end
  end

  -- hint / tooltip (wrapped to the sidebar width)
  local hint
  if ui.sell_mode then
    hint = "Sell: click a tower"
  elseif ui.selected then
    hint = tower.DEFS[ui.selected].desc
  else
    hint = "Pick a tower to build"
  end
  local hy = btns[#btns].y + btns[#btns].h + 6
  local lines = wrap(hint, BW)
  for i = 1, #lines do
    gfx.text(lines[i], BX, hy + (i - 1) * 11, pal.TEXT_DIM)
  end

  -- start-wave button (only while building)
  if run.phase == "building" then
    gfx.rect_fill(start_btn.x, start_btn.y, start_btn.w, start_btn.h, pal.GOOD)
    local label = "START WAVE " .. (run.wave_index + 1)
    gfx.text(label, start_btn.x + 4, start_btn.y + 5, gfx.COLOR_BLACK)
  else
    gfx.rect_fill(start_btn.x, start_btn.y, start_btn.w, start_btn.h, pal.HUD_PANEL)
    gfx.text("IN PROGRESS", start_btn.x + 4, start_btn.y + 5, pal.TEXT_DIM)
  end

  -- sell toggle
  local sell_bg = ui.sell_mode and pal.BAD or pal.HUD_PANEL
  gfx.rect_fill(sell_btn.x, sell_btn.y, sell_btn.w, sell_btn.h, sell_bg)
  gfx.text("SELL MODE", sell_btn.x + 4, sell_btn.y + 5, pal.TEXT)
end

return M

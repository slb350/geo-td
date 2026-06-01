-- HUD sidebar: run stats, the tower build palette, the Start-wave / Sell
-- buttons, and a contextual hint line. Owns its own button rects and exposes
-- button_at() for click hit-testing; the game scene owns selection state (ui).

local C = require("lib.const")
local pal = require("lib.palette")
local tower = require("lib.tower")
local shape = require("lib.shape")
local ui = require("lib.ui")
local run_lib = require("lib.run")
local speed = require("lib.speed")

local M = {}

local PAD = 6
local BX = C.HUD_X + PAD
local BW = C.HUD_W - PAD * 2

-- Speed toggle (M1), right-aligned on the WAVE stat line (combat + build phases).
local speed_btn = { x = C.HUD_X + C.HUD_W - PAD - 22, y = 6, w = 22, h = 13 }

-- Tower palette buttons (vertical list). Single-line rows (icon + name left,
-- cost right) keep the full 6-tower palette compact above the action buttons.
local btns = {}
do
  local y = 74
  for i = 1, #tower.ORDER do
    btns[i] = { kind = tower.ORDER[i], x = BX, y = y, w = BW, h = 16 }
    y = y + 17
  end
end
-- The action button doubles as START WAVE (building) and ORBITAL STRIKE (combat).
local action_btn = { x = BX, y = C.GAME_H - 46, w = BW, h = 18 }
local sell_btn = { x = BX, y = C.GAME_H - 24, w = BW, h = 18 }
-- Tooltip is capped to the lines that fit between the palette and the buttons.
local MAX_HINT_LINES = 2
-- Orbital action-button label (cost is constant, so build it once).
local ORBITAL_LABEL = "ORBITAL $" .. C.ORBITAL_COST

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

-- The hint text changes rarely, so cache the wrap result across frames.
local last_hint, last_lines
local function wrap_cached(text, max_w)
  if text ~= last_hint then
    last_hint, last_lines = text, wrap(text, max_w)
  end
  return last_lines
end

-- Returns an action for a sidebar click, or nil. Actions:
--   { type = "select", kind = <towerkind> }
--   { type = "start" }    -- the action button while building
--   { type = "orbital" }  -- the same button while in combat
--   { type = "sell" }
function M.button_at(run, mx, my)
  if ui.in_rect(mx, my, speed_btn) then return { type = "speed" } end
  for i = 1, #btns do
    if ui.in_rect(mx, my, btns[i]) then return { type = "select", kind = btns[i].kind } end
  end
  if ui.in_rect(mx, my, action_btn) then return { type = run.phase == "building" and "start" or "orbital" } end
  if ui.in_rect(mx, my, sell_btn) then return { type = "sell" } end
  return nil
end

-- Mini geometric icon for a tower kind, centered at (cx, cy).
local function icon(kind, cx, cy, color)
  shape.fill(tower.DEFS[kind].shape, cx, cy, 5, color)
end

function M.draw(run, meta, hud_ui)
  -- panel
  gfx.rect_fill(C.HUD_X, 0, C.HUD_W, C.GAME_H, pal.HUD_BG)
  gfx.line(C.HUD_X, 0, C.HUD_X, C.GAME_H, pal.PATH_EDGE)

  -- stats
  gfx.text("WAVE " .. run.wave_index, BX, 8, pal.TEXT)
  gfx.text("$" .. run.money, BX, 26, pal.MONEY)
  gfx.text("LIVES " .. run.lives, BX, 42, pal.LIVES)
  gfx.text("SCORE " .. run.score, BX, 58, pal.TEXT_DIM)
  -- charge (the second economy), right-aligned on the LIVES line
  local chg = "CHG " .. math.floor(run.charge)
  gfx.text(chg, BX + BW - usagi.measure_text(chg), 42, gfx.COLOR_PEACH)

  -- speed toggle: lit when faster than 1x
  local spd = speed.clamp(hud_ui.speed or 1)
  gfx.rect_fill(speed_btn.x, speed_btn.y, speed_btn.w, speed_btn.h, pal.HUD_PANEL)
  gfx.text(speed.label(spd), speed_btn.x + 4, speed_btn.y + 3, spd > 1 and pal.MONEY or pal.TEXT_DIM)

  -- tower palette
  for i = 1, #btns do
    local b = btns[i]
    local kind = b.kind
    local def = tower.DEFS[kind]
    local avail = tower.available(meta, kind, run.mode)
    local cost = tower.cost(run, kind)
    local afford = run.money >= cost
    local selected = (hud_ui.selected == kind)

    gfx.rect_fill(b.x, b.y, b.w, b.h, pal.HUD_PANEL)
    if selected then gfx.rect_ex(b.x, b.y, b.w, b.h, 1, pal.HUD_SEL) end
    local body = avail and (afford and pal.resolve(def.color) or gfx.COLOR_DARK_GRAY) or gfx.COLOR_DARK_GRAY
    icon(kind, b.x + 12, b.y + b.h * 0.5, body)
    -- one centered line: name on the left, cost (or LOCKED) right-aligned
    local ty = b.y + 4
    gfx.text(def.name, b.x + 24, ty, avail and pal.TEXT or pal.TEXT_DIM)
    local tag = avail and ("$" .. cost) or "LOCKED"
    local tag_col = avail and (afford and pal.MONEY or pal.BAD) or pal.TEXT_DIM
    gfx.text(tag, b.x + b.w - usagi.measure_text(tag) - 4, ty, tag_col)
  end

  -- hint / tooltip (wrapped to the sidebar width)
  local hint
  if hud_ui.sell_mode then
    hint = "Sell: click a tower"
  elseif hud_ui.selected then
    hint = tower.DEFS[hud_ui.selected].desc
  else
    hint = "Pick a tower to build"
  end
  local hy = btns[#btns].y + btns[#btns].h + 6
  local lines = wrap_cached(hint, BW)
  for i = 1, math.min(#lines, MAX_HINT_LINES) do
    gfx.text(lines[i], BX, hy + (i - 1) * 11, pal.TEXT_DIM)
  end

  -- action button: START WAVE while building, ORBITAL STRIKE while in combat.
  if run.phase == "building" then
    gfx.rect_fill(action_btn.x, action_btn.y, action_btn.w, action_btn.h, pal.GOOD)
    local label = "START WAVE " .. (run.wave_index + 1)
    gfx.text(label, action_btn.x + 4, action_btn.y + 5, gfx.COLOR_BLACK)
  else
    -- armed (orange) exactly when an orbital strike would fire right now
    local armed = run_lib.can_orbital(run)
    local bg = armed and gfx.COLOR_ORANGE or pal.HUD_PANEL
    gfx.rect_fill(action_btn.x, action_btn.y, action_btn.w, action_btn.h, bg)
    gfx.text(ORBITAL_LABEL, action_btn.x + 4, action_btn.y + 5, armed and gfx.COLOR_BLACK or pal.TEXT_DIM)
  end

  -- sell toggle
  local sell_bg = hud_ui.sell_mode and pal.BAD or pal.HUD_PANEL
  gfx.rect_fill(sell_btn.x, sell_btn.y, sell_btn.w, sell_btn.h, sell_bg)
  gfx.text("SELL MODE", sell_btn.x + 4, sell_btn.y + 5, pal.TEXT)
end

return M

-- Tower-inspect panel (M3): shown in the HUD sidebar when a placed tower is
-- clicked in the build phase. Lists the tower's leveled upgrades and its geometry
-- module socket with costs, and exposes button_at() for click hit-testing. The
-- game scene owns the inspected-tower state (ui.inspect); modifier.lua owns the
-- buy/socket rules. Compact UI: glyph-tuned offsets, not ui.text_height.

local C        = require("lib.const")
local pal      = require("lib.palette")
local ui       = require("lib.ui")
local shape    = require("lib.shape")
local modifier = require("lib.modifier")
local tower    = require("lib.tower")

local M = {}

local PAD = 6
local BX = C.HUD_X + PAD
local BW = C.HUD_W - PAD * 2

local EFF_Y = 36                              -- effective-stat line (M1)
local UP_Y, UP_H, UP_GAP = 52, 16, 3
local MOD_Y, MOD_H, MOD_GAP = 132, 15, 2
local tgt_btn = { x = BX, y = C.GAME_H - 40, w = BW, h = 14 }   -- targeting override (M1)

local function up_rect(i)  return { x = BX, y = UP_Y + (i - 1) * (UP_H + UP_GAP), w = BW, h = UP_H } end
local function mod_rect(i) return { x = BX, y = MOD_Y + (i - 1) * (MOD_H + MOD_GAP), w = BW, h = MOD_H } end

-- Returns the click action in the inspect panel, or nil:
--   { type = "upgrade",   id = <upgrade id> }
--   { type = "module",    id = <module id> }   (only while the socket is empty)
--   { type = "targeting" }                      (cycle the tower's targeting override)
function M.button_at(run, t, mx, my)
  local opts = modifier.upgrade_options(run, t)
  for i = 1, #opts do
    if ui.in_rect(mx, my, up_rect(i)) then return { type = "upgrade", id = opts[i].id } end
  end
  if not t.module then
    for i = 1, #modifier.MODULE_ORDER do
      if ui.in_rect(mx, my, mod_rect(i)) then
        return { type = "module", id = modifier.MODULE_ORDER[i] }
      end
    end
  end
  if ui.in_rect(mx, my, tgt_btn) then return { type = "targeting" } end
  return nil
end

function M.draw(run, t)
  gfx.rect_fill(C.HUD_X, 0, C.HUD_W, C.GAME_H, pal.HUD_BG)
  gfx.line(C.HUD_X, 0, C.HUD_X, C.GAME_H, pal.PATH_EDGE)
  gfx.text(t.def.name, BX, 8, t.color)
  gfx.text("$" .. run.money, BX, 22, pal.MONEY)

  -- effective stats: base folded through global mods, upgrades, and the module
  local eff = modifier.effective(run, t, t.eff)
  gfx.text(("%d dmg  %.1f/s  %d rng"):format(
    math.floor(eff.damage + 0.5), eff.fire_rate, math.floor(eff.range + 0.5)),
    BX, EFF_Y, pal.TEXT_DIM)

  -- leveled upgrades
  local opts = modifier.upgrade_options(run, t)
  for i = 1, #opts do
    local o, r = opts[i], up_rect(i)
    gfx.rect_fill(r.x, r.y, r.w, r.h, pal.HUD_PANEL)
    gfx.text(o.name, r.x + 3, r.y + 4, pal.TEXT)
    local tag = o.maxed and "MAX" or ("L" .. o.level .. " $" .. o.cost)
    local col = o.maxed and pal.GOOD or (o.afford and pal.MONEY or pal.BAD)
    gfx.text(tag, r.x + r.w - usagi.measure_text(tag) - 3, r.y + 4, col)
  end

  -- one geometry module socket
  if t.module then
    local mod = modifier.MODULES[t.module]
    gfx.text("MODULE", BX, MOD_Y - 12, pal.TEXT_DIM)
    shape.fill(mod.shape, BX + 6, MOD_Y + 6, 5, t.color)
    gfx.text(mod.name, BX + 16, MOD_Y, pal.TEXT)
    gfx.text(mod.desc, BX + 3, MOD_Y + 16, pal.TEXT_DIM)
  else
    gfx.text("MODULE $" .. C.MODULE_COST, BX, MOD_Y - 12, pal.TEXT_DIM)
    local afford = run.money >= C.MODULE_COST
    for i = 1, #modifier.MODULE_ORDER do
      local mod, r = modifier.MODULES[modifier.MODULE_ORDER[i]], mod_rect(i)
      gfx.rect_fill(r.x, r.y, r.w, r.h, pal.HUD_PANEL)
      shape.fill(mod.shape, r.x + 8, r.y + r.h * 0.5, 4, afford and t.color or gfx.COLOR_DARK_GRAY)
      gfx.text(mod.desc, r.x + 18, r.y + 4, afford and pal.TEXT or pal.TEXT_DIM)
    end
  end

  -- targeting override (M1): cycle the tower's acquisition policy/focus
  gfx.rect_fill(tgt_btn.x, tgt_btn.y, tgt_btn.w, tgt_btn.h, pal.HUD_PANEL)
  local ov = t.targeting_override
  gfx.text("TARGET: " .. tower.targeting_label(ov), tgt_btn.x + 3, tgt_btn.y + 3,
    ov and pal.MONEY or pal.TEXT)

  gfx.text("RMB: close", BX, C.GAME_H - 12, pal.TEXT_DIM)
end

return M

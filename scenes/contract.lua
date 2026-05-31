-- Wave-contract event scene (V2-M3): before some (non-boss) waves, sign one
-- risk/reward contract or decline. Signing arms run.active_contract for the next
-- wave; declining leaves it nil. An input lockout ignores a click carried over
-- from the prior between-wave screen (mirrors scenes/upgrade.lua). The draft + its
-- static layout/text are baked once in init so the per-frame redraw allocates
-- nothing and it survives a live reload.

local C         = require("lib.const")
local pal       = require("lib.palette")
local fx        = require("lib.fx")
local ui        = require("lib.ui")
local shape     = require("lib.shape")
local contracts = require("lib.contracts")

local M = {}

local TILE_W, TILE_H, GAP = 146, 120, 10
local ROW_Y = 62
local decline_btn = { x = (C.GAME_W - 120) * 0.5, y = ROW_Y + TILE_H + 14, w = 120, h = 18 }

local function tiles(n)
  local out = {}
  local x0 = (C.GAME_W - (n * TILE_W + (n - 1) * GAP)) * 0.5
  for i = 1, n do
    out[i] = { x = x0 + (i - 1) * (TILE_W + GAP), y = ROW_Y, w = TILE_W, h = TILE_H }
  end
  return out
end

local function risk_text(card)
  local k = card.risk
  if k.hp_mult then return ("+%d%% enemy HP"):format(math.floor((k.hp_mult - 1) * 100 + 0.5)) end
  if k.count_mult then return ("+%d%% enemies"):format(math.floor((k.count_mult - 1) * 100 + 0.5)) end
  if k.disable then return "a tower offline " .. k.disable .. "s" end
  if k.no_sell then return "no selling this wave" end
  return ""
end

local function reward_text(card)
  local r = card.reward
  if r.charge then return "+" .. r.charge .. " charge" end
  if r.money then return "+$" .. r.money end
  if r.bank_shard then return "+" .. r.bank_shard .. " bank shard" end
  if r.module_discount then return "-$" .. r.module_discount .. " next module" end
  return ""
end

function M.init()
  if not State.run then SwitchScene("menu"); return end
  local cards = contracts.draft(State.run)
  if #cards == 0 then SwitchScene("game"); return end
  State.run.contract_tiles = tiles(#cards)
  for i = 1, #cards do
    cards[i].risk_label = risk_text(cards[i])
    cards[i].reward_label = reward_text(cards[i])
  end
  State.run.contract_draft = cards
  State.run.contract_ready = false              -- require a fresh click first
end

local function finish(run)
  run.contract_draft = nil
  fx.click_sfx()
  SwitchScene("game")
end

function M.update(dt)
  local run = State.run
  if not run or not run.contract_draft then SwitchScene("game"); return end
  if not run.contract_ready then
    if not input.mouse_held(input.MOUSE_LEFT) then run.contract_ready = true end
    return
  end
  if input.mouse_pressed(input.MOUSE_LEFT) then
    local mx, my = input.mouse()
    local ts = run.contract_tiles
    for i = 1, #ts do
      if ui.in_rect(mx, my, ts[i]) then
        contracts.sign(run, run.contract_draft[i])
        return finish(run)
      end
    end
    if ui.in_rect(mx, my, decline_btn) then
      contracts.decline(run)
      return finish(run)
    end
  end
end

function M.draw(dt)
  gfx.clear(pal.BG)
  ui.center_text("CONTRACT", 22, gfx.COLOR_ORANGE, 2)
  ui.center_text("sign a risk for a reward, or decline", 46, pal.TEXT_DIM, 1)

  local cards = State.run.contract_draft or {}
  local ts = State.run.contract_tiles or {}
  local mx, my = input.mouse()
  for i = 1, #cards do
    local t, card = ts[i], cards[i]
    local hover = ui.in_rect(mx, my, t)
    gfx.rect_fill(t.x, t.y, t.w, t.h, pal.HUD_PANEL)
    gfx.rect(t.x, t.y, t.w, t.h, hover and pal.HUD_SEL or pal.PATH_EDGE)
    shape.fill(card.shape, t.x + 12, t.y + 12, 5, gfx.COLOR_ORANGE)
    gfx.text(card.name, t.x + 22, t.y + 8, gfx.COLOR_ORANGE)
    gfx.text("RISK", t.x + 8, t.y + 34, pal.TEXT_DIM)
    gfx.text(card.risk_label, t.x + 8, t.y + 46, pal.BAD)
    gfx.text("REWARD", t.x + 8, t.y + 66, pal.TEXT_DIM)
    gfx.text(card.reward_label, t.x + 8, t.y + 78, pal.GOOD)
    gfx.text(card.desc, t.x + 8, t.y + TILE_H - 16, pal.TEXT_DIM)
  end

  local dh = ui.in_rect(mx, my, decline_btn)
  gfx.rect_fill(decline_btn.x, decline_btn.y, decline_btn.w, decline_btn.h, pal.HUD_PANEL)
  gfx.rect(decline_btn.x, decline_btn.y, decline_btn.w, decline_btn.h, dh and pal.HUD_SEL or pal.PATH_EDGE)
  ui.center_text("DECLINE", decline_btn.y + 6, pal.TEXT, 1)

  ui.center_text("the reward is paid only if you clear the wave", C.GAME_H - 14, pal.TEXT_DIM, 1)
end

return M

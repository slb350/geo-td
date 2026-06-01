-- Route Draft 2.0 event scene (V2-M2): between waves, pick 1 of 3 geometric route
-- cards (two procedural transforms + a Hold). Each card shows a mini preview, its
-- reward/risk, and the refund it would trigger. Adopting a route auto-refunds any
-- tower it invalidates; the field is clear here, so the scalar-distance model is
-- preserved. An input lockout ignores a click carried over from the upgrade screen
-- (mirrors scenes/upgrade.lua). The draft + its static layout/text are stored on
-- the run (computed once in init), so the per-frame redraw allocates nothing and
-- it survives a live reload.

local C = require("lib.const")
local pal = require("lib.palette")
local path = require("lib.path")
local fx = require("lib.fx")
local ui = require("lib.ui")
local shape = require("lib.shape")
local routedraft = require("lib.routedraft")
local contracts = require("lib.contracts")
local run_lib = require("lib.run")

local M = {}

local TILE_W, TILE_H, GAP = 146, 150, 10
local ROW_Y, PREV_H, PAD = 56, 58, 6

local function tiles(n)
  local out = {}
  local x0 = (C.GAME_W - (n * TILE_W + (n - 1) * GAP)) * 0.5
  for i = 1, n do
    out[i] = { x = x0 + (i - 1) * (TILE_W + GAP), y = ROW_Y, w = TILE_W, h = TILE_H }
  end
  return out
end

-- "+$55  +18% wave  +flyers" -- the card's immediate reward and next-wave risk.
local function reward_risk_text(card)
  local parts = {}
  local r = card.reward
  if r and r.money and r.money > 0 then parts[#parts + 1] = "+$" .. r.money end
  local k = card.risk
  if k then
    if k.budget_mult and k.budget_mult > 1 then
      parts[#parts + 1] = ("+%d%% wave"):format(math.floor((k.budget_mult - 1) * 100 + 0.5))
    end
    if k.flyer_bias then parts[#parts + 1] = "+flyers" end
    if k.shield then parts[#parts + 1] = "+shield" end -- Prism (M2)
  end
  return table.concat(parts, "  ")
end

local function refund_text(card)
  if card.current then return "keeps your towers" end
  if card.refund == 0 then return "no towers displaced" end
  return ("refund %d ($%d)"):format(card.refund, card.refund_cost)
end

function M.init()
  if not State.run then
    SwitchScene("menu")
    return
  end
  local cards = routedraft.draft(State.run)
  -- a draft with only the Hold card is a non-event (no real choice); skip it so
  -- the player isn't shown a one-option screen (robust for future sparse maps)
  if #cards <= 1 then
    SwitchScene("game")
    return
  end
  -- bake the modal's static geometry + per-card text once (it redraws every frame
  -- while it waits for a choice)
  State.run.route_tiles = tiles(#cards)
  for i = 1, #cards do
    cards[i].rr_text = reward_risk_text(cards[i])
    cards[i].refund_label = refund_text(cards[i])
  end
  State.run.route_draft = cards
  State.run.route_ready = false -- require a fresh click first
end

local function choose(run, i)
  local card = run.route_draft and run.route_draft[i]
  if card then
    routedraft.apply(run, card) -- swap + refund + reward + risk
    run_lib.record(run, { route = { id = card.id } }) -- replay log (M9)
    fx.click_sfx()
  end
  run.route_draft = nil
  SwitchScene(contracts.pending(run) and "contract" or "game") -- contract may follow (M3)
end

function M.update(dt)
  local run = State.run
  if not run or not run.route_draft then
    SwitchScene("game")
    return
  end
  if not run.route_ready then
    if not input.mouse_held(input.MOUSE_LEFT) then run.route_ready = true end
    return
  end
  if input.mouse_pressed(input.MOUSE_LEFT) then
    local mx, my = input.mouse()
    local ts = run.route_tiles
    for i = 1, #ts do
      if ui.in_rect(mx, my, ts[i]) then return choose(run, i) end
    end
  end
end

function M.draw(dt)
  gfx.clear(pal.BG)
  ui.center_text("ROUTE SHIFT", 22, gfx.COLOR_PINK, 2)
  ui.center_text("choose a route for the waves ahead", 46, pal.TEXT_DIM, 1)

  local cards = State.run.route_draft or {}
  local ts = State.run.route_tiles or {}
  local mx, my = input.mouse()
  for i = 1, #cards do
    local t, card = ts[i], cards[i]
    local hover = ui.in_rect(mx, my, t)
    local accent = card.current and pal.MONEY or gfx.COLOR_PINK
    gfx.rect_fill(t.x, t.y, t.w, t.h, pal.HUD_PANEL)
    gfx.rect(t.x, t.y, t.w, t.h, hover and pal.HUD_SEL or pal.PATH_EDGE)

    -- title: shape icon + name
    shape.fill(card.shape, t.x + 12, t.y + 12, 5, accent)
    gfx.text(card.name, t.x + 22, t.y + 8, accent)

    -- mini route preview
    gfx.rect_fill(t.x + PAD, t.y + 22, t.w - PAD * 2, PREV_H, pal.FIELD_BG)
    path.draw_preview(card.nodes, t.x + PAD, t.y + 22, t.w - PAD * 2, PREV_H, pal.PATH_CORE, pal.SPAWN, pal.CORE)

    gfx.text(card.desc, t.x + PAD, t.y + 86, pal.TEXT_DIM)
    if card.rr_text ~= "" then gfx.text(card.rr_text, t.x + PAD, t.y + 108, pal.GOOD) end
    gfx.text(card.refund_label, t.x + PAD, t.y + 126, card.current and pal.MONEY or pal.TEXT_DIM)
  end

  ui.center_text("a tower on a new route is refunded in full", C.GAME_H - 14, pal.TEXT_DIM, 1)
end

return M

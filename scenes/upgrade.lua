-- Between-wave upgrade draft: pick 1 of 3 rarity-graded powerups. The draft is
-- stored on the run (deterministic from the run rng) so it survives live
-- reload. An input lockout ignores selections until the mouse has been released
-- since entering -- otherwise a build-click made as the wave ended would carry
-- over and instantly auto-pick a card.

local C       = require("lib.const")
local pal     = require("lib.palette")
local powerup = require("lib.powerup")
local fx      = require("lib.fx")
local ui      = require("lib.ui")
local pathmut = require("lib.pathmut")

local M = {}

local cards = {}
do
  local n, w, h, gap = 3, 124, 96, 12
  local total = n * w + (n - 1) * gap
  local x0 = (C.GAME_W - total) * 0.5
  for i = 1, n do
    cards[i] = { x = x0 + (i - 1) * (w + gap), y = 92, w = w, h = h }
  end
end

function M.init()
  local run = State.run
  if not run then SwitchScene("menu"); return end
  run.draft = powerup.draft(run.rng, 3)
  run.upgrade_ready = false -- require a fresh click before accepting a choice
end

local function choose(i)
  local run = State.run
  local card = run.draft and run.draft[i]
  if card then powerup.apply(run, card) end
  run.draft = nil
  fx.upgrade_sfx()
  -- a route-mutation event may intervene before the next wave (M7)
  SwitchScene(pathmut.pending(run) and "route" or "game")
end

function M.update(dt)
  local run = State.run
  if not run or not run.draft then SwitchScene("game"); return end
  -- lockout: wait for the mouse to be up before accepting input
  if not run.upgrade_ready then
    if not input.mouse_held(input.MOUSE_LEFT) then run.upgrade_ready = true end
    return
  end
  if input.key_pressed(input.KEY_1) then return choose(1) end
  if input.key_pressed(input.KEY_2) then return choose(2) end
  if input.key_pressed(input.KEY_3) then return choose(3) end
  if input.mouse_pressed(input.MOUSE_LEFT) then
    local mx, my = input.mouse()
    for i = 1, #cards do
      if run.draft[i] and ui.in_rect(mx, my, cards[i]) then
        return choose(i)
      end
    end
  end
end

function M.draw(dt)
  gfx.clear(pal.BG)
  ui.center_text("WAVE " .. State.run.wave_index .. " CLEARED", 38, gfx.COLOR_GREEN, 2)
  ui.center_text("choose an upgrade", 70, pal.TEXT_DIM, 1)

  local draft = State.run.draft or {}
  for i = 1, #cards do
    local r = cards[i]
    local card = draft[i]
    gfx.rect_fill(r.x, r.y, r.w, r.h, pal.HUD_PANEL)
    if card then
      local col = powerup.color(card)
      gfx.rect_ex(r.x, r.y, r.w, r.h, 2, col)
      gfx.text(powerup.rarity_name(card), r.x + 8, r.y + 8, col)
      gfx.text(powerup.DEFS[card.key].name, r.x + 8, r.y + 28, gfx.COLOR_WHITE)
      gfx.text(powerup.describe(card), r.x + 8, r.y + 48, pal.TEXT)
      gfx.text("[" .. i .. "]", r.x + 8, r.y + r.h - 16, pal.TEXT_DIM)
    end
  end
end

return M

-- Game over: award meta-currency for the run (once, in init), persist via
-- lib/meta, show the summary, and return to the menu on click/key.

local C    = require("lib.const")
local pal  = require("lib.palette")
local meta = require("lib.meta")
local fx   = require("lib.fx")
local ui   = require("lib.ui")

local M = {}

function M.init()
  local run = State.run
  if not run then SwitchScene("menu"); return end
  local wave_reached = run.final_wave or run.wave_index
  local award = meta.finish_run(State.meta, wave_reached, run.bosses_killed or 0)
  State.summary = {
    wave = wave_reached,
    score = run.score,
    kills = run.kills,
    award = award,
    bank = State.meta.currency,
  }
  effect.stop()
  fx.clear()
  fx.over_sfx()
end

function M.update(dt)
  if input.mouse_pressed(input.MOUSE_LEFT)
    or input.key_pressed(input.KEY_SPACE) or input.key_pressed(input.KEY_ENTER)
    or input.pressed(input.BTN1) then
    State.run = nil
    SwitchScene("menu")
  end
end

function M.draw(dt)
  gfx.clear(pal.BG)
  local s = State.summary or { wave = 0, score = 0, kills = 0, award = 0, bank = 0 }
  ui.center_text("RUN OVER", 44, gfx.COLOR_RED, 2)
  ui.center_text("reached wave " .. s.wave, 80, pal.TEXT, 1)
  ui.center_text("score " .. s.score .. "    kills " .. s.kills, 98, pal.TEXT_DIM, 1)
  ui.center_text("+" .. s.award .. " bank  (total " .. s.bank .. ")", 124, gfx.COLOR_YELLOW, 1)
  ui.center_text("click to return to menu", C.GAME_H - 16, pal.TEXT_DIM, 1)
end

return M

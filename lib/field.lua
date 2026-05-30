-- Animated play-field backdrop: a faint dotted grid over the base color, with
-- a slow scanning highlight line for a touch of life. Drawn before the path.

local C = require("lib.const")

local M = {}

local GRID = 24

function M.draw(pal, elapsed)
  gfx.rect_fill(0, 0, C.HUD_X, C.GAME_H, pal.FIELD_BG)
  -- grid dots
  for x = GRID, C.HUD_X - 1, GRID do
    for y = GRID, C.GAME_H - 1, GRID do
      gfx.px(x, y, gfx.COLOR_DARK_PURPLE)
    end
  end
  -- slow horizontal scan line
  local sy = (elapsed * 18) % (C.GAME_H + 40) - 20
  gfx.line(0, sy, C.HUD_X, sy, gfx.COLOR_DARK_PURPLE)
end

return M

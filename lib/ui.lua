-- Small shared UI helpers used by the scenes and HUD.

local M = {}

-- Point-in-rect hit test (half-open: left/top inside, right/bottom outside).
function M.in_rect(px, py, r)
  return px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h
end

-- Draw horizontally-centered text at row y. Integer scale stays crisp.
function M.center_text(text, y, color, scale)
  scale = scale or 1
  local w = usagi.measure_text(text) * scale
  gfx.text_ex(text, (usagi.GAME_W - w) * 0.5, y, scale, 0, color, 1)
end

return M

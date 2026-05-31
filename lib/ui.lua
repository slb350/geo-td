-- Small shared UI helpers used by the scenes and HUD.

local M = {}

-- Point-in-rect hit test (half-open: left/top inside, right/bottom outside).
function M.in_rect(px, py, r)
  return px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h
end

-- Measured line height of the bundled font (the `h` from measure_text, a font
-- metric independent of the string), optionally scaled. Use this for laying out
-- stacked text rows so vertical spacing tracks the real font instead of a magic
-- pixel offset. (Note: compact UI that packs tighter than a full line box still
-- hardcodes glyph-tuned offsets on purpose — see hud.lua / upgrade.lua.)
function M.text_height(scale)
  local _, h = usagi.measure_text("Ag")
  return h * (scale or 1)
end

-- Draw horizontally-centered text at row y. Integer scale stays crisp.
function M.center_text(text, y, color, scale)
  scale = scale or 1
  local w = usagi.measure_text(text) * scale
  gfx.text_ex(text, (usagi.GAME_W - w) * 0.5, y, scale, 0, color, 1)
end

return M

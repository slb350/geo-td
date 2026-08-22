-- Small shared UI helpers used by the scenes and HUD.

local M = {}

-- Point-in-rect hit test (half-open: left/top inside, right/bottom outside).
function M.in_rect(px, py, r)
  return px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h
end

-- Cursor position for DRAW-TIME hover highlighting. `input.mouse()` keeps
-- reporting a CLAMPED position once the cursor leaves the window or moves onto a
-- letterbox bar, which would light whichever widget sits at that clamped edge.
-- Off the drawn game area this returns a point far outside the screen, so the
-- callers' `in_rect` tests simply fail and no highlight is drawn -- no nil
-- handling needed at any call site.
-- Click paths do NOT need this: a click outside the window never reaches the game.
function M.hover_pos()
  if not input.mouse_over() then return -1e4, -1e4 end
  return input.mouse()
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

-- Greedy word-wrap to a pixel width using the real font metrics. Returns a list
-- of lines, each measuring <= max_w (a single word wider than max_w is kept whole
-- on its own line rather than split mid-glyph). Shared by the HUD tooltip and the
-- upgrade-draft cards so wrapped text never spills past its box.
function M.wrap(text, max_w)
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

-- Trim `text` to the longest prefix that fits `max_w` pixels (no ellipsis -- the
-- bundled font has no guaranteed glyph for one, and a monospace clip lands cleanly
-- on a char boundary). For single-line fields that must not overrun their box.
function M.truncate(text, max_w)
  local s = text
  while #s > 0 and usagi.measure_text(s) > max_w do
    s = s:sub(1, #s - 1)
  end
  return s
end

return M

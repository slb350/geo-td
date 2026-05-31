-- Animated play-field backdrop for the neon-geometric look. Layers, back to
-- front: a flat base, a slow parallax starfield, a "circuit" grid whose nodes
-- pulse along a travelling diagonal wave, a faint sweeping scan line, and one
-- large, very dim, slowly-rotating wireframe hexagon as an ambient motif.
-- Everything here is kept deliberately DIM so towers / enemies / path read
-- clearly on top of it (and so the CRT bloom pass only catches the foreground).
-- Drawn before the path.

local C = require("lib.const")

local M = {}

local W, H  = C.HUD_X, C.GAME_H
local GRID  = 24
local STARS = 52
local TWO_PI = math.pi * 2
local flr = math.floor

-- Stable pseudo-random fraction in [0,1) from an integer (the GLSL sin-hash).
local function hash(i)
  local x = math.sin(i * 12.9898 + 7.13) * 43758.5453
  return x - math.floor(x)
end

-- Per-star fields that never change (column, fall speed, drift origin, twinkle
-- rate) are baked once at load; the draw loop only animates drift + twinkle.
local STAR = {}
for i = 1, STARS do
  STAR[i] = { x = math.floor(hash(i) * W), speed = 4 + hash(i + 11) * 10,
              y0 = hash(i + 99) * H, rate = 1.5 + hash(i + 3) * 2 }
end

function M.draw(pal, elapsed)
  gfx.rect_fill(0, 0, W, H, pal.FIELD_BG)

  -- 1. parallax starfield: dim motes drifting down, the odd one twinkling.
  for i = 1, STARS do
    local s = STAR[i]
    local sy = (s.y0 + elapsed * s.speed) % H         -- nearer motes fall faster
    local tw = math.sin(elapsed * s.rate + i)
    local col = gfx.COLOR_DARK_PURPLE
    if tw > 0.93 then col = gfx.COLOR_LIGHT_GRAY
    elseif tw > 0.45 then col = gfx.COLOR_INDIGO end
    gfx.px(s.x, flr(sy), col)
  end

  -- 2. circuit grid: nodes brighten as a diagonal wave sweeps across them.
  for x = GRID, W - 1, GRID do
    for y = GRID, H - 1, GRID do
      if math.sin((x + y) * 0.018 - elapsed * 1.6) > 0.6 then
        gfx.px(x, y, gfx.COLOR_INDIGO)
      else
        gfx.px(x, y, gfx.COLOR_DARK_PURPLE)
      end
    end
  end

  -- 3. a faint diagonal scan line sweeping the field on a slow cycle.
  local sweep = (elapsed * 46) % (W + H) - H          -- x-intercept of the line
  gfx.line(sweep, 0, sweep + H, H, gfx.COLOR_DARK_PURPLE)

  -- 4. ambient motif: one big, very dim, slowly rotating hexagon ring.
  local cx, cy, r = W * 0.5, H * 0.5, 78
  local a = elapsed * 0.15
  local px0, py0
  for k = 0, 6 do
    local ang = a + k * (TWO_PI / 6)
    local x2 = cx + math.cos(ang) * r
    local y2 = cy + math.sin(ang) * r * 0.7           -- squashed to suit 16:9
    if k > 0 then gfx.line(px0, py0, x2, y2, gfx.COLOR_DARK_PURPLE) end
    px0, py0 = x2, y2
  end
end

return M

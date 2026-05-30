-- Shared geometric shape drawing for enemies, towers, and HUD icons.
-- Shapes are centered at (x, y) with circumradius r and optional rotation
-- (radians). Squares are axis-aligned (crisp); polygons can spin.

local M = {}

local TAU = math.pi * 2

-- Filled regular polygon as a triangle fan from the center.
local function poly_fill(x, y, r, sides, rot, color)
  local px, py
  for k = 0, sides do
    local a = rot + (k / sides) * TAU
    local nx, ny = x + math.cos(a) * r, y + math.sin(a) * r
    if k > 0 then gfx.tri_fill(x, y, px, py, nx, ny, color) end
    px, py = nx, ny
  end
end
M.poly_fill = poly_fill

-- Outlined regular polygon.
local function poly_line(x, y, r, sides, rot, color)
  local px, py
  for k = 0, sides do
    local a = rot + (k / sides) * TAU
    local nx, ny = x + math.cos(a) * r, y + math.sin(a) * r
    if k > 0 then gfx.line(px, py, nx, ny, color) end
    px, py = nx, ny
  end
end
M.poly_line = poly_line

-- Regular-polygon shapes, defined once: sides, radius multiplier, rotation offset.
local POLY = {
  diamond = { sides = 4, rmult = 1.2,  roff = 0 },
  tri     = { sides = 3, rmult = 1.25, roff = -math.pi / 2 },
  hex     = { sides = 6, rmult = 1.0,  roff = 0 },
  penta   = { sides = 5, rmult = 1.0,  roff = -math.pi / 2 },
}

function M.fill(kind, x, y, r, color, rot)
  rot = rot or 0
  if kind == "square" then
    gfx.rect_fill(x - r, y - r, r * 2, r * 2, color)
    return
  end
  local p = POLY[kind]
  if p then
    poly_fill(x, y, r * p.rmult, p.sides, rot + p.roff, color)
  else
    gfx.circ_fill(x, y, r, color)
  end
end

function M.line(kind, x, y, r, color, rot)
  rot = rot or 0
  if kind == "square" then
    gfx.rect(x - r, y - r, r * 2, r * 2, color)
    return
  end
  local p = POLY[kind]
  if p then
    poly_line(x, y, r * p.rmult, p.sides, rot + p.roff, color)
  else
    gfx.circ(x, y, r, color)
  end
end

return M

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

function M.fill(kind, x, y, r, color, rot)
  rot = rot or 0
  if kind == "circ" then
    gfx.circ_fill(x, y, r, color)
  elseif kind == "square" then
    gfx.rect_fill(x - r, y - r, r * 2, r * 2, color)
  elseif kind == "diamond" then
    poly_fill(x, y, r * 1.2, 4, rot, color)
  elseif kind == "tri" then
    poly_fill(x, y, r * 1.25, 3, rot - math.pi / 2, color)
  elseif kind == "hex" then
    poly_fill(x, y, r, 6, rot, color)
  elseif kind == "penta" then
    poly_fill(x, y, r, 5, rot - math.pi / 2, color)
  else
    gfx.circ_fill(x, y, r, color)
  end
end

function M.line(kind, x, y, r, color, rot)
  rot = rot or 0
  if kind == "circ" then
    gfx.circ(x, y, r, color)
  elseif kind == "square" then
    gfx.rect(x - r, y - r, r * 2, r * 2, color)
  elseif kind == "diamond" then
    poly_line(x, y, r * 1.2, 4, rot, color)
  elseif kind == "tri" then
    poly_line(x, y, r * 1.25, 3, rot - math.pi / 2, color)
  elseif kind == "hex" then
    poly_line(x, y, r, 6, rot, color)
  elseif kind == "penta" then
    poly_line(x, y, r, 5, rot - math.pi / 2, color)
  else
    gfx.circ(x, y, r, color)
  end
end

return M

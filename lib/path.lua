-- Fixed waypoint path. Enemies advance by a scalar distance `d` along the
-- polyline (smooth, and `d` doubles as progress for "closest to core"
-- targeting). Also provides the point-to-path distance used to validate
-- tower placement, and a draw routine.

local shape = require("lib.shape")

local M = {}

-- Build a path object from a list of {x, y} nodes.
function M.build(nodes)
  local segs, total = {}, 0
  for i = 1, #nodes - 1 do
    local a, b = nodes[i], nodes[i + 1]
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local len = math.sqrt(dx * dx + dy * dy)
    segs[i] = {
      ax = a[1], ay = a[2], bx = b[1], by = b[2],
      len = len, ux = dx / len, uy = dy / len,
    }
    total = total + len
  end
  return { nodes = nodes, segs = segs, total_len = total }
end

-- World position at distance `d` along the path. Clamps to the endpoints.
function M.point_at(path, d)
  local segs = path.segs
  if d <= 0 then return segs[1].ax, segs[1].ay end
  local rem = d
  for i = 1, #segs do
    local s = segs[i]
    if rem <= s.len then
      return s.ax + s.ux * rem, s.ay + s.uy * rem
    end
    rem = rem - s.len
  end
  local last = segs[#segs]
  return last.bx, last.by
end

-- Minimum distance from point (px, py) to the polyline. Used to keep towers
-- off the path during placement.
function M.dist_to(path, px, py)
  local best = math.huge
  local segs = path.segs
  for i = 1, #segs do
    local s = segs[i]
    local vx, vy = s.bx - s.ax, s.by - s.ay
    local wx, wy = px - s.ax, py - s.ay
    local denom = vx * vx + vy * vy
    local t = denom > 0 and (wx * vx + wy * vy) / denom or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local cx, cy = s.ax + vx * t, s.ay + vy * t
    local ddx, ddy = px - cx, py - cy
    local d2 = ddx * ddx + ddy * ddy
    if d2 < best then best = d2 end
  end
  return math.sqrt(best)
end

local flr = math.floor

-- Render the route as a neon tube (bloom-friendly glow edge, dark body, bright
-- centre-line) with travelling energy packets, pulsing corner nodes, and
-- animated spawn / core markers. `elapsed` drives the animation; pass usagi.elapsed.
function M.draw(path, pal, width, elapsed)
  elapsed = elapsed or 0
  local segs, nodes = path.segs, path.nodes
  local nseg = #segs

  -- lane in three passes: glow edge -> dark body -> bright centre tube
  for i = 1, nseg do
    local s = segs[i]
    gfx.line_ex(s.ax, s.ay, s.bx, s.by, width + 4, pal.PATH_EDGE)
  end
  for i = 1, nseg do
    local s = segs[i]
    gfx.line_ex(s.ax, s.ay, s.bx, s.by, width, pal.PATH)
  end
  -- soft joints so corners don't notch the body
  for i = 1, #nodes do
    local n = nodes[i]
    gfx.circ_fill(n[1], n[2], width * 0.5, pal.PATH)
  end
  local tube = math.max(2, width * 0.28)
  for i = 1, nseg do
    local s = segs[i]
    gfx.line_ex(s.ax, s.ay, s.bx, s.by, tube, pal.PATH_CORE)
  end

  local total = path.total_len

  -- faint flow dots: a steady drift that reads as "this way to the core"
  local spacing = 26
  local d = (elapsed * 34) % spacing
  while d < total do
    local x, y = M.point_at(path, d)
    gfx.px(flr(x), flr(y), pal.TEXT_DIM)
    d = d + spacing
  end

  -- a few bright energy packets sliding the full route (CRT bloom catches them)
  for p = 0, 2 do
    local pd = (elapsed * 80 + p * total / 3) % total
    local x, y = M.point_at(path, pd)
    gfx.circ_fill(x, y, 2, pal.PULSE)
    gfx.px(flr(x), flr(y), gfx.COLOR_WHITE)
  end

  -- pulsing rings on the interior corners
  for i = 2, #nodes - 1 do
    local n = nodes[i]
    gfx.circ(n[1], n[2], 2.5 + math.sin(elapsed * 4 + i) * 1.2, pal.PATH_EDGE)
  end

  -- spawn portal: pulsing rings + a slow rotating tri marker
  local first, last = nodes[1], nodes[#nodes]
  local sp = 5 + math.sin(elapsed * 5) * 1.4
  gfx.circ_fill(first[1], first[2], 3, pal.SPAWN)
  gfx.circ(first[1], first[2], sp, pal.SPAWN)
  gfx.circ(first[1], first[2], sp + 3, gfx.COLOR_ORANGE)
  shape.poly_line(first[1], first[2], 9, 3, elapsed * 1.5, gfx.COLOR_ORANGE)

  -- core: pulsing concentric rings + a counter-rotating square marker
  gfx.circ_fill(last[1], last[2], 3, pal.CORE)
  local pr = 7 + math.sin(elapsed * 4) * 2
  gfx.circ(last[1], last[2], pr, pal.CORE)
  gfx.circ(last[1], last[2], pr + 4, gfx.COLOR_DARK_GREEN)
  shape.poly_line(last[1], last[2], pr + 7, 4, -elapsed * 1.2, gfx.COLOR_DARK_GREEN)
end

return M

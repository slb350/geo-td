-- Route Draft 2.0 (V2-M2): turns the between-wave route event into a 3-card draft
-- of geometric route propositions, while preserving the single-polyline scalar-
-- distance model. Each non-Hold card is a PROCEDURAL transform of the current
-- route (loop = longer/more coverage, shortcut = shorter/cash now, braid = winding,
-- split = paired lanes that cross back into one, convergence = central choke);
-- the Hold card keeps the
-- current route for a small stipend. Card metadata (names/shapes/reward/risk/desc)
-- is data (data/route_events.json); the geometry transforms + validity rules live
-- here. Low-level swap + auto-refund stays in lib/pathmut.
--
-- Generated routes are validated against the same invariants a hand-authored
-- variant must satisfy (shared spawn+core, in bounds, sane segment count + edge
-- lengths, 65%-160% of the base length, and still buildable), so a drafted route
-- is interchangeable with the base and a route swap is always field-clear-safe.

local C = require("lib.const")
local path = require("lib.path")
local pathmut = require("lib.pathmut")
local rng = require("lib.rng")
local resource = require("lib.resource")

local DEFS = usagi.read_json("route_events.json")

local M = {}
M.DEFS = DEFS

-- Non-Hold cards, in a stable order; the Hold card is always appended last.
M.TYPE_ORDER = { "loop", "shortcut", "braid", "split", "convergence" }

local FIELD_W, FIELD_H = C.FIELD_W, C.FIELD_H
local LEN_LO, LEN_HI = 0.65, 1.60 -- total length band vs the base route
local poly_len = path.poly_len -- shared geometry primitives (lib/path)
local min_edge = path.min_edge

local function in_bounds(x, y)
  local m = C.MAP_BOUND_MARGIN
  return x >= m and x < FIELD_W - m and y >= m and y < FIELD_H - m
end

local function copy_nodes(nodes)
  local out = {}
  for i = 1, #nodes do
    out[i] = { nodes[i][1], nodes[i][2] }
  end
  return out
end

local function longest_seg(nodes)
  local li, llen = 1, -1
  for i = 1, #nodes - 1 do
    local a, b = nodes[i], nodes[i + 1]
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local d = dx * dx + dy * dy
    if d > llen then
      li, llen = i, d
    end
  end
  return li
end

-- Is the generated route interchangeable with the base? Shares spawn+core, stays
-- in bounds, keeps segment count + edge lengths sane, lands in the length band,
-- and leaves somewhere to build (same checks a hand-authored variant must pass).
function M.valid(base, nodes)
  if #nodes < 2 or (#nodes - 1) > C.MAP_MAX_SEGS then return false end
  local bs, bc, ns, nc = base[1], base[#base], nodes[1], nodes[#nodes]
  if ns[1] ~= bs[1] or ns[2] ~= bs[2] or nc[1] ~= bc[1] or nc[2] ~= bc[2] then return false end
  for i = 1, #nodes do
    if not in_bounds(nodes[i][1], nodes[i][2]) then return false end
  end
  if min_edge(nodes) < C.MAP_MIN_EDGE then return false end
  local len, base_len = poly_len(nodes), poly_len(base)
  if len <= C.MAP_MIN_LEN or len < base_len * LEN_LO or len > base_len * LEN_HI then return false end
  return path.has_buildable_spot(path.build(nodes))
end

-- --------------------------------------------------------------- transforms
-- Each returns a fresh node list (or nil if it can't act on this base). The
-- spawn + core nodes are never moved. Caller validates the result via M.valid.
local transforms = {}

-- Perpendicular-bump a point at parameter t along a segment, toward the field
-- centre (or away, if that side is out of bounds). Returns x, y or nil.
local function bump(a, b, t, dist, toward_center)
  local mx, my = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
  local dx, dy = b[1] - a[1], b[2] - a[2]
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1 then return nil end
  local px, py = -dy / len, dx / len -- perpendicular unit
  local cx, cy = FIELD_W * 0.5, FIELD_H * 0.5
  local side = (((cx - mx) * px + (cy - my) * py) >= 0) and 1 or -1
  if not toward_center then side = -side end
  local nx, ny = mx + px * dist * side, my + py * dist * side
  if in_bounds(nx, ny) then return nx, ny end
  nx, ny = mx - px * dist * side, my - py * dist * side -- try the other side
  if in_bounds(nx, ny) then return nx, ny end
  return nil
end

-- Loop: bump the midpoint of the longest segment outward -> a longer route.
function transforms.loop(base)
  local li = longest_seg(base)
  local nx, ny = bump(base[li], base[li + 1], 0.5, 38, true)
  if not nx then return nil end
  local out = copy_nodes(base)
  table.insert(out, li + 1, { nx, ny })
  return out
end

-- Braid: two opposite bumps on the longest segment -> an S-curve.
function transforms.braid(base)
  local li = longest_seg(base)
  local a, b = base[li], base[li + 1]
  local x1, y1 = bump(a, b, 1 / 3, 30, true)
  local x2, y2 = bump(a, b, 2 / 3, 30, false)
  if not (x1 and x2) then return nil end
  local out = copy_nodes(base)
  table.insert(out, li + 1, { x1, y1 })
  table.insert(out, li + 2, { x2, y2 })
  return out
end

-- Split: make a fork-like diamond on the longest segment, but still as one
-- scalar polyline: the route peels to one side, crosses to the other lane, then
-- rejoins. This gives the "split pressure" proposition without introducing
-- branch pathfinding or enemy remapping.
function transforms.split(base)
  local li = longest_seg(base)
  local a, b = base[li], base[li + 1]
  local x1, y1 = bump(a, b, 0.25, 28, true)
  local x2, y2 = bump(a, b, 0.50, 46, false)
  local x3, y3 = bump(a, b, 0.75, 28, true)
  if not (x1 and x2 and x3) then return nil end
  local out = copy_nodes(base)
  table.insert(out, li + 1, { x1, y1 })
  table.insert(out, li + 2, { x2, y2 })
  table.insert(out, li + 3, { x3, y3 })
  return out
end

-- Shortcut: drop the single interior node that shortens the route the most while
-- staying within the length band -> a shorter route.
function transforms.shortcut(base)
  if #base <= 3 then return nil end
  local base_len = poly_len(base)
  local best, best_len
  for i = 2, #base - 1 do
    local cand = copy_nodes(base)
    table.remove(cand, i)
    local len = poly_len(cand)
    if len >= base_len * LEN_LO and (not best_len or len < best_len) then
      best, best_len = cand, len
    end
  end
  return best
end

-- Convergence: pull every interior node a third of the way toward the field
-- centre -> a funnel through a central choke.
function transforms.convergence(base)
  if #base <= 3 then return nil end
  local cx, cy = FIELD_W * 0.5, FIELD_H * 0.5
  local out = copy_nodes(base)
  for i = 2, #out - 1 do
    out[i][1] = out[i][1] + (cx - out[i][1]) * 0.35
    out[i][2] = out[i][2] + (cy - out[i][2]) * 0.35
  end
  return out
end

M.transforms = transforms -- exposed so the suite can validate each in isolation

-- ------------------------------------------------------------------- draft
local function make_card(run, id, nodes, current)
  local def = DEFS[id]
  local refund, refund_cost = 0, 0
  if not current then
    refund, refund_cost = pathmut.refund_preview(run, nodes)
  end
  return {
    id = id,
    name = def.name,
    shape = def.shape,
    desc = def.desc,
    nodes = nodes,
    reward = def.reward,
    risk = def.risk,
    current = current or false,
    refund = refund,
    refund_cost = refund_cost,
  }
end

-- Draft the route-event cards for the current run: up to two valid transform
-- cards plus the always-present Hold card. Deterministic for a given run rng
-- state + current route (the only randomness is the run's seeded shuffle).
function M.draft(run)
  local base = run.path.nodes
  local pool = {}
  for i = 1, #M.TYPE_ORDER do
    local id = M.TYPE_ORDER[i] -- the transform name == the card id
    local nodes = transforms[id](base)
    if nodes and M.valid(base, nodes) then pool[#pool + 1] = make_card(run, id, nodes, false) end
  end
  -- Prism keeps the current route (no geometry change) but seeds a resource prism
  -- and shields the next wave -- a resource/risk proposition rather than a transform.
  pool[#pool + 1] = make_card(run, "prism", base, false)
  -- Shuffle then take up to two. A DERIVED rng (from the run + current wave) keeps
  -- the draft deterministic per (seed, map, wave) without perturbing later wave
  -- generation, and shuffles fairly even on a freshly seeded run (see rng.derive).
  rng.derive(run.seed, run.wave_index):shuffle(pool)
  local cards = {}
  for i = 1, math.min(2, #pool) do
    cards[#cards + 1] = pool[i]
  end
  cards[#cards + 1] = make_card(run, "null", base, true) -- Hold (keep current)
  return cards
end

-- Apply a chosen card: swap + auto-refund (unless Hold), grant the immediate
-- money reward, and arm the one-shot route-mod risk for the next wave. Returns
-- the number of towers refunded by the swap. Must run with a clear field.
function M.apply(run, card)
  local refunded = 0
  if card.id == "prism" then
    resource.add_node(run) -- seed a prism (no route swap); shield risk below
  elseif not card.current then
    refunded = pathmut.apply(run, card.nodes)
  end
  if card.reward and card.reward.money and card.reward.money > 0 then run.money = run.money + card.reward.money end
  local rm, risk = run.route_mods, card.risk
  if rm and risk then
    if risk.budget_mult then rm.next_budget_mult = risk.budget_mult end
    if risk.flyer_bias then rm.next_flyer_bias = true end
    if risk.shield then rm.next_shield = risk.shield end
  end
  return refunded
end

return M

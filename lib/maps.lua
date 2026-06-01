-- Map catalogue + difficulty / unlock order. Single source of truth for the
-- path layouts (loaded from data/paths.json) and the order maps are ranked and
-- unlocked in. ORDER is least -> most difficult, ranked empirically (a uniform
-- tower cordon, leaks summed over a fixed wave span across several seeds):
-- zigzag is the most forgiving, switchback demands the most coverage. Clearing
-- wave >= UNLOCK_WAVE on a map unlocks the next one in ORDER.

local C = require("lib.const")
local path = require("lib.path")

local M = {}

local DATA = usagi.read_json("paths.json")

M.ORDER = { "zigzag", "spiral", "serpentine", "chicane", "switchback" }
M.first = M.ORDER[1]
M.UNLOCK_WAVE = 20

function M.get(name)
  return DATA.layouts[name]
end
function M.exists(name)
  return DATA.layouts[name] ~= nil
end

-- Alternate route polylines for a map (the M7 path-mutation variants), or {} if
-- the map defines none. Each variant is a complete node-list (single polyline).
function M.variants(name)
  local lay = DATA.layouts[name]
  return (lay and lay.variants) or {}
end

function M.index(name)
  for i = 1, #M.ORDER do
    if M.ORDER[i] == name then return i end
  end
  return nil
end

-- The next (harder) map after `name`, or nil if it is already the last.
function M.next(name)
  local i = M.index(name)
  return i and M.ORDER[i + 1] or nil
end

-- Deterministic fallback pick from a seed (when no map is explicitly chosen).
function M.pick(seed)
  return M.ORDER[(math.floor(seed or 0) % #M.ORDER) + 1]
end

-- ---------------------------------------------------------------- validation
-- Absolute validity of a layout's node polyline (the invariants every hand-
-- authored map must satisfy, independent of any base route): two+ nodes, segment
-- count under the cap, all nodes inside the field margin, no near-zero edge, a
-- playable length, and somewhere to build. Returns ok, reason, metrics{segs,
-- length, min_edge, buildable}. Shared by tests + tools/map_lab so adding a map
-- is a validated JSON row, not guesswork. (Route VARIANTS are additionally checked
-- against their base by routedraft.valid -- the shared-endpoints + length-band part.)
function M.validate(nodes)
  local has_nodes = #nodes >= 2
  local metrics = {
    segs = math.max(0, #nodes - 1),
    length = path.poly_len(nodes),
    min_edge = has_nodes and path.min_edge(nodes) or 0,
    buildable = has_nodes and path.buildable_count(path.build(nodes)) or 0,
  }
  if not has_nodes then return false, "needs a spawn and a core node", metrics end
  if metrics.segs > C.MAP_MAX_SEGS then return false, "too many segments", metrics end
  local m = C.MAP_BOUND_MARGIN
  for i = 1, #nodes do
    local x, y = nodes[i][1], nodes[i][2]
    if x < m or x >= C.FIELD_W - m or y < m or y >= C.FIELD_H - m then
      return false, "node " .. i .. " out of bounds", metrics
    end
  end
  if metrics.min_edge < C.MAP_MIN_EDGE then return false, "an edge is too short", metrics end
  if metrics.length < C.MAP_MIN_LEN then return false, "route too short", metrics end
  if metrics.buildable <= 0 then return false, "no buildable area", metrics end
  return true, "ok", metrics
end

-- Do two routes share the same spawn + core node? The swap-safety invariant for a
-- hand-authored route variant (the scalar-distance model still starts/ends in the
-- same place). NOT the route-draft length band -- a variant may be a deliberate
-- shortcut, far shorter than the base, which is fine for a between-wave swap.
local function endpoints_match(a, b)
  return a[1][1] == b[1][1] and a[1][2] == b[1][2] and a[#a][1] == b[#b][1] and a[#a][2] == b[#b][2]
end

-- Validate a named layout and (if any) each of its route variants: the base by the
-- absolute invariants, each variant by the absolute invariants PLUS sharing the
-- base's spawn + core (so pathmut can swap it in safely). Returns ok, list of
-- {label, ok, reason, metrics}.
function M.validate_layout(name)
  local lay = DATA.layouts[name]
  local rows = {}
  if not lay then return false, rows end
  local base = lay.nodes
  local ok, reason, metrics = M.validate(base)
  rows[#rows + 1] = { label = name, ok = ok, reason = reason, metrics = metrics }
  local all_ok = ok
  local variants = lay.variants or {}
  for i = 1, #variants do
    local vok, vreason, vmetrics = M.validate(variants[i])
    if vok and not endpoints_match(base, variants[i]) then
      vok, vreason = false, "variant endpoints differ from base"
    end
    rows[#rows + 1] = { label = name .. "#variant" .. i, ok = vok, reason = vreason, metrics = vmetrics }
    all_ok = all_ok and vok
  end
  return all_ok, rows
end

return M

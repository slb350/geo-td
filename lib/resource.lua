-- Resource nodes + the charge economy (V2-M3). A few resource prisms are seeded
-- on each run's field; a Drill (a support tower with targets:"none") placed within
-- DRILL_RANGE of a prism extracts `charge` during COMBAT only (no idle farming in
-- the build phase). Charge is the second in-run economy -- it fuels the Discharge
-- active ability (lib/run), separate from money (which buys towers).
--
-- Node placement uses a DERIVED rng (rng.derive), so it is deterministic per seed
-- yet never consumes the run's main rng -- the wave-generation sequence (and the
-- balance baselines) are unaffected by adding resource nodes.

local C = require("lib.const")
local path = require("lib.path")
local rng = require("lib.rng")

local M = {}

-- Seed the run's resource prisms: spread-out off-path field cells, picked
-- deterministically. Called once from run.new.
function M.spawn_nodes(run)
  local r = rng.derive(run.seed, 7777)
  local cands = {}
  for gx = 30, C.FIELD_W - 30, 18 do
    for gy = 30, C.FIELD_H - 30, 18 do
      if path.dist_to(run.path, gx, gy) > C.PLACE_MARGIN + 12 then cands[#cands + 1] = { x = gx, y = gy } end
    end
  end
  local nodes = {}
  for _ = 1, C.RESOURCE_NODES do
    if #cands == 0 then break end
    local pick = cands[r:int(1, #cands)]
    nodes[#nodes + 1] = { x = pick.x, y = pick.y }
    local kept = {} -- drop nearby cells so prisms spread out
    for i = 1, #cands do
      local c = cands[i]
      local dx, dy = c.x - pick.x, c.y - pick.y
      if dx * dx + dy * dy > 80 * 80 then kept[#kept + 1] = c end
    end
    cands = kept
  end
  run.resource_nodes = nodes
end

-- Add one more resource prism (the M2 Prism route card). Deterministic per
-- (seed, wave), off-path, and spread from the existing nodes. Returns the node, or
-- nil if no spot is free.
function M.add_node(run)
  local r = rng.derive(run.seed, 7000 + run.wave_index)
  local nodes = run.resource_nodes
  local cands = {}
  for gx = 30, C.FIELD_W - 30, 18 do
    for gy = 30, C.FIELD_H - 30, 18 do
      if path.dist_to(run.path, gx, gy) > C.PLACE_MARGIN + 12 then
        local ok = true
        for i = 1, #nodes do
          local dx, dy = nodes[i].x - gx, nodes[i].y - gy
          if dx * dx + dy * dy < 60 * 60 then
            ok = false
            break
          end
        end
        if ok then cands[#cands + 1] = { x = gx, y = gy } end
      end
    end
  end
  if #cands == 0 then return nil end
  local node = cands[r:int(1, #cands)]
  nodes[#nodes + 1] = node
  return node
end

-- Is (x, y) within extraction range of a resource prism? (The Drill placement
-- rule, on top of the normal tower placement checks.)
function M.near_node(run, x, y)
  local nodes = run.resource_nodes
  local r2 = C.DRILL_RANGE * C.DRILL_RANGE
  for i = 1, #nodes do
    local n = nodes[i]
    local dx, dy = n.x - x, n.y - y
    if dx * dx + dy * dy <= r2 then return true end
  end
  return false
end

-- Generate charge from each active Drill (a support tower still adjacent to a
-- prism). Combat-only, so charge can't be idle-farmed during the build phase.
function M.update(run, dt)
  local towers = run.towers
  local gen = 0
  for i = 1, #towers do
    local t = towers[i]
    -- a blacked-out Drill (disabled_t > 0, e.g. a Blackout contract) extracts nothing
    if t.def.role == "support" and t.disabled_t <= 0 and M.near_node(run, t.x, t.y) then
      gen = gen + C.DRILL_RATE * dt
    end
  end
  if gen > 0 then run.charge = run.charge + gen end
end

-- Draw the resource prisms (a slow-rotating diamond + pulse). Dim so the CRT
-- bloom lifts them; brighter when a Drill is tapping the node.
function M.draw(run)
  local nodes = run.resource_nodes
  local t = usagi.elapsed
  for i = 1, #nodes do
    local n = nodes[i]
    local tapped = false
    for j = 1, #run.towers do
      local tw = run.towers[j]
      if tw.def.role == "support" then
        local dx, dy = tw.x - n.x, tw.y - n.y
        if dx * dx + dy * dy <= C.DRILL_RANGE * C.DRILL_RANGE then
          tapped = true
          break
        end
      end
    end
    local col = tapped and gfx.COLOR_YELLOW or gfx.COLOR_DARK_GREEN
    local pr = 4 + math.sin(t * 3 + i) * 1.2
    gfx.circ(n.x, n.y, C.DRILL_RANGE, gfx.COLOR_DARK_PURPLE) -- faint extract radius
    gfx.circ_fill(n.x, n.y, 2, col)
    gfx.circ(n.x, n.y, pr, col)
  end
end

return M

-- Path-mutation events (M7): between-wave route changes for route agency while
-- preserving the single-polyline scalar-distance model. A swap only happens via
-- the route-event screen, which runs BETWEEN waves with the field clear, so no
-- live enemy's `d` is ever remapped -- the next wave simply runs the new
-- polyline. Variants are predefined complete polylines per map (data/paths.json),
-- each sharing the spawn + core node with the base route.

local C     = require("lib.const")
local maps  = require("lib.maps")
local path  = require("lib.path")
local tower = require("lib.tower")
local wave  = require("lib.wave")

local M = {}

-- Is a route choice offered immediately before wave `w`? On any map, on an
-- event-cadence wave, and never before a boss wave -- including mode-driven boss
-- waves (Boss Rush makes EVERY wave a boss). V2-M2 generates the route options
-- procedurally from the current route (lib/routedraft), so a map no longer needs
-- predefined variants to host an event; a degenerate draft (only Hold) is skipped
-- by the route scene.
function M.pending_for(run, w)
  return w % C.ROUTE_EVENT_EVERY == 0 and not wave.is_boss_for(run, w)
end

-- Is a route choice offered before the NEXT wave (the upgrade->route->game hop)?
function M.pending(run)
  return M.pending_for(run, run.wave_index + 1)
end

-- Route options for the choice screen: the base route, then each variant. Each
-- is flagged `current` if it is the run's active polyline.
function M.routes(run)
  local all = { maps.get(run.path_name).nodes }
  local vars = maps.variants(run.path_name)
  for i = 1, #vars do all[#all + 1] = vars[i] end
  local out = {}
  for i = 1, #all do
    out[i] = {
      label = (i == 1) and "Origin" or ("Route " .. i),
      nodes = all[i],
      current = all[i] == run.path.nodes,
    }
  end
  return out
end

-- Dry run of apply's auto-refund: how many towers the route `nodes` would
-- invalidate, and the total investment that would be returned. Read-only, for the
-- route-draft card previews (the player sees the cost before committing).
function M.refund_preview(run, nodes)
  local p = path.build(nodes)
  local count, total = 0, 0
  for i = 1, #run.towers do
    local t = run.towers[i]
    if path.dist_to(p, t.x, t.y) < C.PLACE_MARGIN then
      count = count + 1
      total = total + (t.invested or tower.cost(run, t.kind))
    end
  end
  return count, total
end

-- Adopt `nodes` as the run's route. Towers now on / too close to the new path
-- are auto-refunded at full value -- their whole investment (base cost + every
-- upgrade + module via t.invested), since the route change forced them out, not
-- the player. Returns the number of towers refunded. Must be called between
-- waves (field clear).
function M.apply(run, nodes)
  -- enforce the field-clear precondition: swapping the polyline with live
  -- enemies on it would strand their scalar `d`. The scene flow only reaches
  -- here between waves, but assert so any future misuse fails loud, not silent.
  assert(run.enemies.n == 0 and (not run.boss or run.boss.dead),
    "pathmut.apply requires a clear field (route swaps happen between waves)")
  run.path = path.build(nodes)
  local kept, refunded = {}, 0
  for i = 1, #run.towers do
    local t = run.towers[i]
    if path.dist_to(run.path, t.x, t.y) < C.PLACE_MARGIN then
      run.money = run.money + (t.invested or tower.cost(run, t.kind))
      refunded = refunded + 1
    else
      kept[#kept + 1] = t
    end
  end
  run.towers = kept
  return refunded
end

return M

-- Resource node + charge cases (V2-M3): node seeding (deterministic, off-path,
-- and NOT consuming the run's main rng), Drill placement (only near a prism) +
-- non-attacking behavior, combat-only charge generation that stops on sell, and
-- the Discharge ability. Run by smoke.lua via M.run(check, near).

local C        = require("lib.const")
local meta     = require("lib.meta")
local run_mod  = require("lib.run")
local path     = require("lib.path")
local tower    = require("lib.tower")
local enemy    = require("lib.enemy")
local wave     = require("lib.wave")
local resource = require("lib.resource")
local helpers  = require("tests.helpers")

local M = {}

function M.run(check, near)
  local m = meta.default()

  -- ------------------------------------------------------------ node seeding
  local r = run_mod.new(m, 4242, "serpentine")
  check(#r.resource_nodes == C.RESOURCE_NODES, "run seeds RESOURCE_NODES resource prisms")
  for i = 1, #r.resource_nodes do
    local n = r.resource_nodes[i]
    check(helpers.in_field(n.x, n.y), "resource node " .. i .. " is in field bounds")
    check(path.dist_to(r.path, n.x, n.y) > C.PLACE_MARGIN, "resource node " .. i .. " is off the path")
  end
  local r2 = run_mod.new(m, 4242, "serpentine")
  check(r2.resource_nodes[1].x == r.resource_nodes[1].x and r2.resource_nodes[1].y == r.resource_nodes[1].y,
    "resource nodes are deterministic for a seed")
  -- node seeding uses a derived rng, so the main wave rng is untouched
  local ra, rb = run_mod.new(m, 99, "serpentine"), run_mod.new(m, 99, "serpentine")
  check(wave.start(ra, 1) == wave.start(rb, 1), "node seeding leaves wave generation deterministic")

  -- --------------------------------------------------------------- near_node
  local node = r.resource_nodes[1]
  check(resource.near_node(r, node.x, node.y), "near_node is true at a prism")
  check(not resource.near_node(r, node.x + 200, node.y + 200), "near_node is false far from any prism")

  -- --------------------------------------------------------- Drill placement
  local rp = run_mod.new(m, 4242, "serpentine"); rp.money = 99999
  local nd = rp.resource_nodes[1]
  check(tower.can_place(rp, nd.x, nd.y, "drill"), "a Drill can be placed at a prism")
  -- an off-path spot far from every prism rejects the Drill but takes a pellet
  local fx, fy
  for gx = 16, C.FIELD_W - 16, 12 do
    for gy = 16, C.FIELD_H - 16, 12 do
      if path.dist_to(rp.path, gx, gy) > C.PLACE_MARGIN + 4 and not resource.near_node(rp, gx, gy) then
        fx, fy = gx, gy; break
      end
    end
    if fx then break end
  end
  check(fx ~= nil, "found an off-path spot away from every prism")
  check(not tower.can_place(rp, fx, fy, "drill"), "a Drill is rejected away from any prism")
  check((tower.can_place(rp, fx, fy, "pellet")), "but a normal tower places there fine")

  -- ------------------------------------------------- Drill is non-attacking
  local rd = run_mod.new(m, 4242, "serpentine"); rd.money = 99999
  local n0 = rd.resource_nodes[1]
  local drill = tower.place(rd, n0.x, n0.y, "drill")
  rd.enemies.n = 0
  enemy.spawn(rd, "hulk", 1, 1, 10).x = n0.x       -- an enemy right on top of the Drill
  rd.projectiles.n = 0
  drill.cooldown = 0
  tower.update(rd, 1 / 60)
  check(rd.projectiles.n == 0, "a Drill never acquires or fires")

  -- ----------------------------------------------------- charge generation
  rd.charge = 0
  resource.update(rd, 1.0)
  check(near(rd.charge, C.DRILL_RATE), "a Drill generates DRILL_RATE charge per combat second")
  tower.sell(rd, drill)
  local c0 = rd.charge
  resource.update(rd, 1.0)
  check(rd.charge == c0, "a sold Drill generates no more charge")

  -- a Drill placed away from a node (forced) generates nothing
  local re = run_mod.new(m, 5, "serpentine")
  re.charge = 0
  local stray = tower.place(re, re.resource_nodes[1].x, re.resource_nodes[1].y, "drill")
  stray.x, stray.y = 250, 150                       -- move it off the node
  resource.update(re, 1.0)
  check(re.charge == 0, "a Drill not adjacent to a prism generates nothing")

  -- a blacked-out Drill (a Blackout contract can disable it) extracts nothing, and
  -- its disable ticks down via tower.update like any tower -- not stuck forever
  local rbk = run_mod.new(m, 5, "serpentine"); rbk.money = 99999
  local bk = rbk.resource_nodes[1]
  local bdrill = tower.place(rbk, bk.x, bk.y, "drill")
  bdrill.disabled_t = 8; rbk.charge = 0
  resource.update(rbk, 1.0)
  check(rbk.charge == 0, "a blacked-out Drill generates no charge")
  tower.update(rbk, 1.0)
  check(near(bdrill.disabled_t, 7), "a support tower's disable ticks down (not stuck forever)")
  bdrill.disabled_t = 0
  resource.update(rbk, 1.0)
  check(near(rbk.charge, C.DRILL_RATE), "once the disable clears, the Drill extracts again")

  -- ------------------------------------------------------------- Discharge
  local rdis = run_mod.new(m, 1, "serpentine")
  rdis.phase = "combat"; rdis.charge = 50
  rdis.enemies.n = 0
  local e1 = enemy.spawn(rdis, "hulk", 1, 1, 10); e1.armor, e1.shield, e1.shield_max = 0, 0, 0
  local hp0 = e1.hp
  check(run_mod.can_discharge(rdis), "discharge available: combat + charge + a target")
  check(run_mod.discharge(rdis), "discharge fires")
  check(rdis.charge == 0, "discharge spends ALL charge")
  check(near(hp0 - e1.hp, 50 * C.DISCHARGE_FACTOR), "discharge deals charge * DISCHARGE_FACTOR to an enemy")
  check(not run_mod.can_discharge(rdis), "discharge unavailable with no charge")
  rdis.charge = C.DISCHARGE_MIN - 1
  check(not run_mod.can_discharge(rdis), "discharge unavailable under DISCHARGE_MIN")
  rdis.charge = 50; rdis.phase = "building"
  check(not run_mod.can_discharge(rdis), "discharge unavailable outside combat")
  check(not run_mod.discharge(rdis), "discharge no-ops when unavailable")
end

return M

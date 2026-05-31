-- M7 path-mutation events: route-variant data validity, the between-wave pending
-- check, route options, applying a route (swap + full-value auto-refund of
-- invalidated towers), and the route-event scene. Run by smoke.lua. Drives the
-- route scene via the global input stub installed by smoke.lua's scene section.

local C       = require("lib.const")
local meta    = require("lib.meta")
local run_mod = require("lib.run")
local maps    = require("lib.maps")
local path    = require("lib.path")
local tower   = require("lib.tower")
local pathmut  = require("lib.pathmut")
local modifier = require("lib.modifier")
local route    = require("scenes.route")
local helpers  = require("tests.helpers")

local M = {}

local in_field = helpers.in_field

function M.run(check, near)
  local m = meta.default()

  -- variant data: present on some maps, absent on others (serpentine is pinned)
  check(#maps.variants("zigzag") == 2, "zigzag defines two route variants")
  check(#maps.variants("serpentine") == 0, "serpentine defines no variants (pinned for fixtures)")

  -- every variant is a valid single polyline: in-bounds, substantial, and shares
  -- its base route's spawn + core node
  for _, name in ipairs(maps.ORDER) do
    local base = maps.get(name).nodes
    local vars = maps.variants(name)
    for vi = 1, #vars do
      local v = vars[vi]
      local vp = path.build(v)
      check(vp.total_len > 100, name .. " variant " .. vi .. " has a substantial route")
      local inb = true
      for k = 1, #v do if not in_field(v[k][1], v[k][2]) then inb = false end end
      check(inb, name .. " variant " .. vi .. " stays in field bounds")
      check(v[1][1] == base[1][1] and v[1][2] == base[1][2]
        and v[#v][1] == base[#base][1] and v[#v][2] == base[#base][2],
        name .. " variant " .. vi .. " shares the base spawn + core")
      -- buildable: at least one off-route spot exists (parity with base-layout validation)
      local buildable = false
      for gx = 20, C.FIELD_W - 20, 16 do
        for gy = 20, C.FIELD_H - 20, 16 do
          if path.dist_to(vp, gx, gy) > C.PLACE_MARGIN then buildable = true; break end
        end
        if buildable then break end
      end
      check(buildable, name .. " variant " .. vi .. " leaves room to build")
    end
  end

  -- pending: event-cadence wave on a variant map, never a boss wave or off-map
  do
    local r = run_mod.new(m, 1, "zigzag")
    r.wave_index = 3; check(pathmut.pending(r), "route event pending before wave 4 (zigzag)")
    r.wave_index = 4; check(not pathmut.pending(r), "no route event before a boss wave (5)")
    r.wave_index = 5; check(not pathmut.pending(r), "no route event before wave 6 (off cadence)")
    local rs = run_mod.new(m, 1, "serpentine"); rs.wave_index = 3
    check(not pathmut.pending(rs), "no route event on a map without variants")
    -- Boss Rush makes every wave a boss, so a route event must never be offered
    local rbr = run_mod.new(m, 1, "zigzag", "boss_rush"); rbr.wave_index = 3
    check(not pathmut.pending(rbr), "no route event in Boss Rush (every wave is a boss)")
  end

  -- routes: base + variants, the active route flagged current on a fresh run
  do
    local r = run_mod.new(m, 1, "zigzag")
    local routes = pathmut.routes(r)
    check(#routes == 3, "zigzag offers 3 routes (origin + 2 variants)")
    check(routes[1].current and not routes[2].current, "the active route is flagged current")
  end

  -- apply: the run adopts the chosen polyline
  do
    local r = run_mod.new(m, 1, "zigzag")
    local v1 = maps.variants("zigzag")[1]
    pathmut.apply(r, v1)
    check(r.path.nodes == v1, "apply adopts the chosen route's polyline")
    check(pathmut.routes(r)[2].current, "the adopted variant is now flagged current")
  end

  -- auto-refund: a tower the new route runs over is refunded at full value
  do
    local r = run_mod.new(m, 1, "zigzag"); r.money = 99999
    local v1 = maps.variants("zigzag")[1]
    tower.place(r, 186, 72, "pellet")             -- midpoint of v1's first segment
    local off = tower.place(r, 300, 40, "pellet")  -- clear of every v1 segment
    check(path.dist_to(r.path, 186, 72) >= C.PLACE_MARGIN, "the on-tower is OFF the base route (a valid placement)")
    local cost, before = tower.cost(r, "pellet"), r.money
    local refunded = pathmut.apply(r, v1)
    check(refunded == 1, "exactly the tower on the new route is refunded")
    check(r.money == before + cost, "the refund returns full tower value")
    check(#r.towers == 1 and r.towers[1] == off, "the off-route tower is kept, the on-route one removed")
  end

  -- auto-refund returns the WHOLE investment: base cost + upgrades + module
  do
    local r = run_mod.new(m, 1, "zigzag"); r.money = 99999
    local v1 = maps.variants("zigzag")[1]
    local t = tower.place(r, 186, 72, "pellet")   -- on v1
    local base = tower.cost(r, "pellet")
    local after_place = r.money
    modifier.buy_upgrade(r, t, "dmg")
    modifier.socket_module(r, t, "triangle")
    local extra = after_place - r.money            -- upgrade + module spend
    check(t.invested == base + extra, "a tower tracks its full investment (base + upgrades + module)")
    local before = r.money
    pathmut.apply(r, v1)
    check(r.money == before + base + extra, "auto-refund returns the tower's full investment, not just base cost")
  end

  -- the refund honors cost_mult: it returns exactly what the tower cost to place
  do
    local r = run_mod.new(m, 1, "zigzag"); r.money = 99999; r.mods.cost_mult = 0.5
    local v1 = maps.variants("zigzag")[1]
    local paid = tower.cost(r, "pellet")           -- discounted cost
    tower.place(r, 186, 72, "pellet")
    local before = r.money
    pathmut.apply(r, v1)
    check(r.money == before + paid, "the refund returns the cost_mult-discounted price actually paid")
  end

  -- route-event scene: lockout, then a click adopts a route and returns to game
  do
    State.run = run_mod.new(State.meta, 7, "zigzag")
    State.pending = nil
    local v1 = maps.variants("zigzag")[1]
    local real_mp, real_mh, real_mo = input.mouse_pressed, input.mouse_held, input.mouse
    input.mouse_held = function() return false end
    input.mouse_pressed = function() return false end
    input.mouse = function() return 0, 0 end
    route.init()
    route.update(1 / 60)                          -- mouse up -> lockout clears
    check(State.run.route_ready, "route scene arms after the mouse is released")
    input.mouse_pressed = function(b) return b == 1 end
    input.mouse = function() return 240, 118 end  -- center of the 2nd route tile
    route.update(1 / 60)
    input.mouse_pressed, input.mouse_held, input.mouse = real_mp, real_mh, real_mo
    check(State.run.path.nodes == v1, "clicking a route tile adopts that route")
    check(State.pending == "game", "the route scene returns to the game scene")
    route.draw(1 / 60)                            -- render path (must not error)
    State.run = nil; State.pending = nil
  end
end

return M

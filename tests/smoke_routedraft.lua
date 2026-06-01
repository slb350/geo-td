-- Route Draft 2.0 cases (V2-M2): the procedural route transforms + validity gate,
-- the deterministic 3-card draft (always offering Hold), applying a card (swap +
-- auto-refund + immediate reward + one-shot next-wave risk), route-mod consumption
-- by wave.start, and the route-event scene end to end. Run by smoke.lua via
-- M.run(check, near) AFTER smoke_core installs the scene globals.

local C          = require("lib.const")
local meta       = require("lib.meta")
local run_mod    = require("lib.run")
local maps       = require("lib.maps")
local path       = require("lib.path")
local tower      = require("lib.tower")
local wave       = require("lib.wave")
local routedraft = require("lib.routedraft")
local route_s    = require("scenes.route")
local helpers    = require("tests.helpers")

local M = {}

local in_field = helpers.in_field

-- Independent check that a generated route passes the same invariants a hand-
-- authored variant must (the existing variant validation sweep).
local function passes_variant_sweep(base, nodes)
  local p = path.build(nodes)
  if p.total_len <= 100 then return false end
  for k = 1, #nodes do if not in_field(nodes[k][1], nodes[k][2]) then return false end end
  if nodes[1][1] ~= base[1][1] or nodes[1][2] ~= base[1][2]
    or nodes[#nodes][1] ~= base[#base][1] or nodes[#nodes][2] ~= base[#base][2] then return false end
  return path.has_buildable_spot(p)
end

function M.run(check, near)
  local m = meta.default()

  -- ----------------------------------------------- transforms + validity gate
  -- Every transform that fires on a real map base produces a route that passes
  -- BOTH routedraft.valid and the independent variant sweep; the drafted cards
  -- (already validated) are valid too.
  for _, name in ipairs(maps.ORDER) do
    local base = maps.get(name).nodes
    for _, id in ipairs(routedraft.TYPE_ORDER) do
      local nodes = routedraft.transforms[id](base)
      if nodes then
        check(routedraft.valid(base, nodes), name .. " transform '" .. id .. "' yields a valid route")
        check(passes_variant_sweep(base, nodes), name .. " transform '" .. id .. "' passes the variant sweep")
      end
    end
    local cards = routedraft.draft(run_mod.new(m, 1, name))
    check(#cards >= 1, name .. ": draft offers at least the Hold card")
    for i = 1, #cards do
      if not cards[i].current then
        check(routedraft.valid(base, cards[i].nodes), name .. " drafted card '" .. cards[i].id .. "' is valid")
      end
    end
  end

  -- all four transforms are available + valid on a rich base, and the shuffle is
  -- fair across seeds (loop is no longer starved by the PRNG small-seed warmup)
  do
    local base = maps.get("zigzag").nodes
    for _, id in ipairs(routedraft.TYPE_ORDER) do
      local nodes = routedraft.transforms[id](base)
      check(nodes and routedraft.valid(base, nodes), "zigzag transform '" .. id .. "' is available + valid")
    end
    local seen = {}
    for s = 1, 20 do
      for _, c in ipairs(routedraft.draft(run_mod.new(m, s, "zigzag"))) do seen[c.id] = true end
    end
    check(seen.loop and seen.shortcut and seen.braid and seen.convergence,
      "all four transform cards can be drafted (fair shuffle)")
  end

  -- valid() rejects malformed routes
  do
    local base = maps.get("zigzag").nodes
    local bad_end = { { base[1][1], base[1][2] }, { 50, 50 }, { 999, 999 } }   -- core moved + OOB
    check(not routedraft.valid(base, bad_end), "valid() rejects a route that moves the core / leaves bounds")
    local two = { { base[1][1], base[1][2] }, { base[#base][1], base[#base][2] } }
    check(not routedraft.valid(base, two), "valid() rejects a 2-node straight line (too short vs base)")
  end

  -- ------------------------------------------------------- draft composition
  do
    local r = run_mod.new(m, 7, "zigzag")
    local cards = routedraft.draft(r)
    check(#cards >= 2 and #cards <= 3, "draft offers up to three cards")
    local hold = cards[#cards]
    check(hold.id == "null" and hold.current and hold.nodes == r.path.nodes,
      "the last card is Hold: current route, no swap")
    -- determinism: two identical runs draft the same cards
    local r2 = run_mod.new(m, 7, "zigzag")
    local cards2 = routedraft.draft(r2)
    local same = (#cards == #cards2)
    for i = 1, #cards do if cards[i].id ~= cards2[i].id then same = false end end
    check(same, "draft is deterministic for the same seed/map/route")
  end

  -- ----------------------------------------------------------- apply a card
  do
    local r = run_mod.new(m, 7, "zigzag"); r.money = 1000
    local cards = routedraft.draft(r)
    -- find a non-current TRANSFORM card (loop/shortcut/braid/convergence -- skip
    -- Prism, which keeps the route rather than swapping it)
    local card
    for i = 1, #cards do
      if not cards[i].current and cards[i].id ~= "prism" then card = cards[i]; break end
    end
    check(card ~= nil, "draft offers at least one route-changing card on zigzag")
    local before_money = r.money
    routedraft.apply(r, card)
    check(r.path.nodes == card.nodes, "apply adopts the chosen route's polyline")
    local expected = before_money + ((card.reward and card.reward.money) or 0)
    check(r.money == expected, "apply grants the card's immediate money reward")
    if card.risk and card.risk.budget_mult then
      check(near(r.route_mods.next_budget_mult, card.risk.budget_mult),
        "apply arms the next-wave budget risk")
    end
    if card.risk and card.risk.flyer_bias then
      check(r.route_mods.next_flyer_bias == true, "apply arms the next-wave flyer risk")
    end
  end

  -- Hold never changes the route, grants its stipend, arms no risk
  do
    local r = run_mod.new(m, 7, "zigzag"); r.money = 0
    local before_path = r.path.nodes
    local hold = routedraft.draft(r)
    local card = hold[#hold]
    routedraft.apply(r, card)
    check(r.path.nodes == before_path, "Hold keeps the current route unchanged")
    check(r.money == (card.reward and card.reward.money or 0), "Hold grants its stipend")
    check(r.route_mods.next_budget_mult == 1 and r.route_mods.next_flyer_bias == false,
      "Hold arms no next-wave risk")
  end

  -- Prism: keeps the route, seeds a resource prism, arms a next-wave shield (M2)
  do
    -- the Prism card is offered across seeds
    local seen_prism = false
    for s = 1, 20 do
      for _, c in ipairs(routedraft.draft(run_mod.new(m, s, "zigzag"))) do
        if c.id == "prism" then seen_prism = true end
      end
    end
    check(seen_prism, "the Prism card can be drafted")

    local r = run_mod.new(m, 1, "serpentine"); r.money = 100
    local nodes0, before_path = #r.resource_nodes, r.path.nodes
    local prism = { id = "prism", nodes = r.path.nodes, current = false,
                    reward = { money = 0 }, risk = { shield = 6 } }
    routedraft.apply(r, prism)
    check(#r.resource_nodes == nodes0 + 1, "Prism seeds an extra resource prism")
    check(r.path.nodes == before_path, "Prism keeps the current route (no swap)")
    check(r.route_mods.next_shield == 6, "Prism arms a next-wave shield risk")

    -- wave.start consumes the shield; the drip shields each spawned enemy
    wave.start(r, 3)
    check(r.wave_shield == 6, "wave.start consumes the shield into the wave")
    check(r.route_mods.next_shield == 0, "the shield risk is one-shot (consumed)")
    r.spawn_timer, r.spawn_interval = 0, 0.5
    wave.update(r, 1.0)
    local shielded = false
    for i = 1, r.enemies.n do if r.enemies[i].shield_max >= 6 then shielded = true end end
    check(shielded, "Prism's shield buff lands on the wave's enemies")
  end

  -- ------------------------------------------------ route_mods consumed once
  do
    local r = run_mod.new(m, 2, "zigzag")
    r.route_mods.next_budget_mult = 2.0          -- a big risk to make the effect obvious
    local boosted = wave.start(r, 3)             -- consumes the mod
    check(r.route_mods.next_budget_mult == 1, "wave.start resets the budget risk after consuming it")
    local r2 = run_mod.new(m, 2, "zigzag")
    local plain = wave.start(r2, 3)
    check(boosted > plain, "the one-shot budget risk produced a heavier wave")
    -- flyer bias is one-shot too
    local rf = run_mod.new(m, 2, "zigzag")
    rf.route_mods.next_flyer_bias = true
    wave.start(rf, 7)                             -- wave 7 has flyers in the pool
    check(rf.route_mods.next_flyer_bias == false, "wave.start resets the flyer risk after consuming it")
  end

  -- applying a route-changing card with live enemies must assert (field-clear)
  do
    local r = run_mod.new(m, 7, "zigzag"); r.money = 1000
    local cards = routedraft.draft(r)
    local card
    for i = 1, #cards do if not cards[i].current then card = cards[i]; break end end
    r.enemies.n = 1; r.enemies[1] = { dead = false }
    local ok = pcall(routedraft.apply, r, card)
    check(not ok, "applying a route swap with live enemies asserts (field must be clear)")
  end

  -- --------------------------------------------------- route-event scene
  do
    State.run = run_mod.new(State.meta, 7, "zigzag")
    State.pending = nil
    local real_mp, real_mh, real_mo = input.mouse_pressed, input.mouse_held, input.mouse
    input.mouse_held = function() return false end
    input.mouse_pressed = function() return false end
    input.mouse = function() return 0, 0 end
    route_s.init()
    check(State.run.route_draft and #State.run.route_draft >= 2, "route scene drafts its cards on init")
    route_s.update(1 / 60)                        -- mouse up -> lockout clears
    check(State.run.route_ready, "route scene arms after the mouse is released")
    route_s.draw(1 / 60)                          -- render cards (must not error)
    -- click the first card's center
    local n = #State.run.route_draft
    local TW, GAP = 146, 10
    local x0 = (C.GAME_W - (n * TW + (n - 1) * GAP)) * 0.5
    input.mouse_pressed = function(b) return b == 1 end
    input.mouse = function() return x0 + TW * 0.5, 56 + 75 end
    route_s.update(1 / 60)
    input.mouse_pressed, input.mouse_held, input.mouse = real_mp, real_mh, real_mo
    check(State.run.route_draft == nil and State.pending == "game",
      "clicking a route card applies it and returns to the game scene")
    State.run = nil; State.pending = nil
  end
end

return M

-- Tower resonance cases (V2-M4): named proofs + matching circuits forming from
-- nearby geometry modules, the dirty-flag recompute (place/sell/socket), the fold
-- into modifier.effective as the LAST layer, resonance behaviour reaching the
-- firing path, default-run inertness, and the inspect layout. Run by smoke.lua via
-- M.run(check, near).

local C         = require("lib.const")
local harness   = require("tests.harness")
local meta      = require("lib.meta")
local run_mod   = require("lib.run")
local tower     = require("lib.tower")
local modifier  = require("lib.modifier")
local resonance = require("lib.resonance")
local inspect   = require("lib.inspect")
local helpers   = require("tests.helpers")

local M = {}

local function names_of(res)
  local set = {}
  if res then for i = 1, #res.names do set[res.names[i]] = true end end
  return set
end

function M.run(check, near)
  local m = meta.default()

  -- ----------------------------------------- named proof (Delta Chain) forms
  local r = helpers.fresh(m, 1)
  local pel = tower.place(r, 200, 150, "pellet")            -- beneficiary (no module)
  local a   = tower.place(r, 215, 150, "pellet"); modifier.socket_module(r, a, "triangle")
  local b   = tower.place(r, 200, 165, "pellet"); modifier.socket_module(r, b, "hex")
  resonance.update(r)
  check(pel.resonance ~= nil, "Delta Chain forms on a pellet with triangle + hex modules nearby")
  check(pel.resonance.ricochet == 1 and near(pel.resonance.crit, 0.25), "Delta Chain grants crit + ricochet")
  check(names_of(pel.resonance)["Delta Chain"], "the active proof is named Delta Chain")

  -- it folds into effective stats (pellet has no module of its own, so the crit +
  -- ricochet come purely from resonance)
  local eff = modifier.effective(r, pel, pel.eff)
  check(eff.ricochet == 1 and near(eff.crit, 0.25), "resonance crit + ricochet fold into effective stats")

  -- ------------------------------------------------------- dirty-flag triggers
  r.resonance_dirty = false
  local c = tower.place(r, 110, 95, "splash")
  check(r.resonance_dirty == true, "placing a tower marks resonance dirty")
  r.resonance_dirty = false
  modifier.socket_module(r, c, "diamond")
  check(r.resonance_dirty == true, "socketing a module marks resonance dirty")
  r.resonance_dirty = false
  tower.sell(r, c)
  check(r.resonance_dirty == true, "selling a tower marks resonance dirty")

  -- removing the triangle clears the dependent proof
  tower.sell(r, a)
  resonance.update(r)
  check(pel.resonance == nil, "removing the triangle clears the dependent Delta Chain")

  -- --------------------------------------------- matching circuit (Triad)
  local rc = helpers.fresh(m, 2)
  local t1 = tower.place(rc, 200, 150, "pellet"); modifier.socket_module(rc, t1, "triangle")
  local t2 = tower.place(rc, 215, 150, "pellet"); modifier.socket_module(rc, t2, "triangle")
  local t3 = tower.place(rc, 200, 165, "pellet"); modifier.socket_module(rc, t3, "triangle")
  resonance.update(rc)
  check(t1.resonance and near(t1.resonance.crit, 0.3), "three triangles form the Triad circuit (crit)")
  check(near(t1.resonance.pierce, 1), "Triad's crit surge also pierces (a behaviour, not just a number)")
  check(names_of(t1.resonance)["Triad"], "Triad named proof is active")

  -- -------------------------------------- behaviour reaches the firing path
  local rf = helpers.fresh(m, 5)
  local fpel = tower.place(rf, 200, 150, "pellet")
  tower.place(rf, 215, 150, "pellet"); modifier.socket_module(rf, rf.towers[2], "triangle")
  tower.place(rf, 200, 165, "pellet"); modifier.socket_module(rf, rf.towers[3], "hex")
  rf.enemies.n = 0
  helpers.dummy(rf, 205, 150)
  rf.projectiles.n = 0
  fpel.cooldown = 0
  tower.update(rf, 1 / 60)                                   -- recomputes resonance + fires
  check(rf.projectiles.n >= 1, "the Delta-Chain pellet fired")
  check(rf.projectiles[1].chain >= 1, "its shot carries the resonance ricochet (chain >= 1)")

  -- ----------------------------------- order: resonance multiplies LAST
  local rg = helpers.fresh(m, 4)
  local flak = tower.place(rg, 200, 150, "flak")
  tower.place(rg, 215, 150, "pellet"); modifier.socket_module(rg, rg.towers[2], "triangle")
  tower.place(rg, 200, 165, "pellet"); modifier.socket_module(rg, rg.towers[3], "circle")
  resonance.update(rg)
  check(flak.resonance and near(flak.resonance.dmg, 0.5), "Green Vector grants the flak +damage")
  check(near(flak.resonance.ricochet, 1), "Green Vector also chains the flak's shots (a behaviour)")
  rg.mods.dmg_mult = 2
  local ge = modifier.effective(rg, flak, flak.eff)
  check(near(ge.damage, tower.DEFS.flak.damage * 2 * 1.5),
    "resonance dmg multiplies AFTER global + upgrade + module (folded last)")

  -- --------------------------------------------- default run is inert
  local rd = helpers.fresh(m, 3)
  tower.place(rd, 200, 150, "pellet"); tower.place(rd, 215, 150, "pellet")
  resonance.update(rd)
  check(rd.towers[1].resonance == nil and rd.towers[2].resonance == nil,
    "no modules -> no resonance (default behaviour byte-identical)")

  -- ------------------------------------------------ inspect layout fit
  harness.reset_gfx()
  inspect.draw(rc, t1)                                       -- t1 has the Triad proof
  local calls, saw_res = harness.gfx_calls(), false
  for i = 1, #calls do
    local cc = calls[i]
    if cc.fn == "text" then
      local text, x, y = cc.args[1], cc.args[2], cc.args[3]
      local w, h = usagi.measure_text(text)
      check(x >= C.HUD_X and x + w <= C.GAME_W, "inspect text fits the sidebar: " .. text)
      check(y >= 0 and y + h <= C.GAME_H, "inspect text fits vertically: " .. text)
      if text:sub(1, 4) == "RES:" then saw_res = true end
    end
  end
  check(saw_res, "the inspect panel shows the active resonance")
end

return M

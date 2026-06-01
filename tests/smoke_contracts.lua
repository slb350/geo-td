-- Wave-contract cases (V2-M3): the offer cadence (never a boss wave), the
-- min-wave-gated deterministic draft, sign/decline, arming the wave-scoped risk
-- (blackout + no-sell), the hp/count risk read by wave.start, granting the reward
-- only on clear + expiry, the module discount, and the run-report/meta payout. Run
-- by smoke.lua via M.run(check, near) AFTER smoke_core installs the scene globals.

local C = require("lib.const")
local meta = require("lib.meta")
local run_mod = require("lib.run")
local tower = require("lib.tower")
local wave = require("lib.wave")
local modifier = require("lib.modifier")
local report = require("lib.report")
local contracts = require("lib.contracts")
local contract_s = require("scenes.contract")
local game_s = require("scenes.game")

local M = {}

function M.run(check, near)
  local m = meta.default()

  -- ----------------------------------------------------------- offer cadence
  local r = run_mod.new(m, 1, "serpentine")
  r.wave_index = 2
  check(contracts.pending(r), "contract pending before wave 3 (cadence)")
  r.wave_index = 3
  check(not contracts.pending(r), "no contract before wave 4 (off cadence)")
  r.wave_index = 14
  check(not contracts.pending(r), "no contract before a boss wave (15)")

  -- --------------------------------------------------------------- the draft
  local rd = run_mod.new(m, 7, "serpentine")
  rd.wave_index = 2 -- next wave = 3
  local d3 = contracts.draft(rd)
  check(#d3 >= 1 and #d3 <= 3, "draft at wave 3 offers cards (capped at 3)")
  local has_blackout = false
  for _, c in ipairs(d3) do
    if c.id == "blackout" then has_blackout = true end
  end
  check(not has_blackout, "a contract is not offered before its min_wave")
  -- deterministic for seed/wave
  local rda, rdb = run_mod.new(m, 7, "serpentine"), run_mod.new(m, 7, "serpentine")
  rda.wave_index, rdb.wave_index = 5, 5
  local a, b = contracts.draft(rda), contracts.draft(rdb)
  local same = (#a == #b)
  for i = 1, #a do
    if a[i].id ~= b[i].id then same = false end
  end
  check(same, "contract draft is deterministic for seed/wave")

  -- --------------------------------------------------------- sign / decline
  local rs = run_mod.new(m, 1, "serpentine")
  rs.wave_index = 5
  local cards = contracts.draft(rs)
  contracts.sign(rs, cards[1])
  check(rs.active_contract == cards[1], "sign sets the active contract")
  check(#rs.contract_history == 1, "sign records the contract history")
  local rdec = run_mod.new(m, 1, "serpentine")
  contracts.decline(rdec)
  check(rdec.active_contract == nil, "decline leaves no active contract")

  -- ------------------------------------------------- arm: blackout + no-sell
  local rb = run_mod.new(m, 1, "serpentine")
  rb.money = 99999
  rb.wave_index = 5
  rb.active_contract = { id = "blackout", risk = { disable = 8 }, reward = { bank_shard = 1 } }
  local bt = tower.place(rb, 200, 150, "pellet")
  contracts.arm(rb)
  check(bt.disabled_t == 8, "blackout disables a tower for the wave's opening seconds")

  local rn = run_mod.new(m, 1, "serpentine")
  rn.money = 99999
  rn.wave_index = 5
  rn.active_contract = { id = "nosell", risk = { no_sell = true }, reward = { module_discount = 30 } }
  contracts.arm(rn)
  check(rn.no_sell == true, "no-sell contract sets the no-sell flag")
  local nt = tower.place(rn, 200, 150, "pellet")
  local kept = #rn.towers
  tower.sell(rn, nt)
  check(#rn.towers == kept, "no-sell blocks selling a tower")

  -- ----------------------------------------------- wave.start risk channels
  local rh0 = run_mod.new(m, 1, "serpentine")
  wave.start(rh0, 3)
  local rh = run_mod.new(m, 1, "serpentine")
  rh.active_contract = { risk = { hp_mult = 1.5 } }
  wave.start(rh, 3)
  check(near(rh.hp_scale, rh0.hp_scale * 1.5), "Enrage spikes the wave's hp_scale")
  local rc0 = run_mod.new(m, 2, "serpentine")
  local base_n = wave.start(rc0, 3)
  local rc = run_mod.new(m, 2, "serpentine")
  rc.active_contract = { risk = { count_mult = 2.0 } }
  local boosted_n = wave.start(rc, 3)
  check(boosted_n > base_n, "Swarm spikes the wave's enemy count")

  -- -------------------------------------------------- grant_reward + expire
  local rr = run_mod.new(m, 1, "serpentine")
  rr.active_contract = { reward = { charge = 18 } }
  contracts.grant_reward(rr)
  check(rr.charge == 18, "grant_reward pays charge")
  rr.active_contract = { reward = { money = 60 } }
  local mb = rr.money
  contracts.grant_reward(rr)
  check(rr.money == mb + 60, "grant_reward pays money")
  rr.active_contract = { reward = { bank_shard = 1 } }
  contracts.grant_reward(rr)
  check(rr.bank_shards == 1, "grant_reward pays bank shards")
  rr.active_contract = { reward = { module_discount = 30 } }
  contracts.grant_reward(rr)
  check(rr.module_discount == 30, "grant_reward grants a module discount")
  rr.no_sell = true
  contracts.expire(rr)
  check(rr.active_contract == nil and rr.no_sell == false, "expire clears the contract + no-sell flag")

  -- ----------------------------------------------------- the module discount
  local rmd = run_mod.new(m, 1, "serpentine")
  rmd.money = 99999
  local mt = tower.place(rmd, 200, 150, "pellet")
  rmd.module_discount = 30
  check(modifier.module_cost(rmd) == C.MODULE_COST - 30, "module_discount lowers the socket cost")
  local before = rmd.money
  modifier.socket_module(rmd, mt, "triangle")
  check(rmd.money == before - (C.MODULE_COST - 30), "socketing charges the discounted cost")
  check(rmd.module_discount == 0, "the module discount is one-shot (consumed)")

  -- ------------------------------------------------------- report + payout
  local rrep = run_mod.new(m, 1, "serpentine")
  rrep.contract_history = { "enrage", "swarm" }
  rrep.bank_shards = 2
  local rep = report.build(rrep)
  check(rep.contracts == 2 and rep.bank_shards == 2, "report carries contracts signed + bank shards")
  local pm = meta.default()
  local award = meta.finish_run(pm, 5, 0, nil, 3)
  check(award == 5 * C.META_PER_WAVE, "finish_run award is wave bonus (shards are a separate currency now)")
  check(pm.bank_shards == 3, "finish_run banks shards as the premium currency (M7)")

  -- --------------------------------------------------------- contract scene
  do
    State.run = run_mod.new(State.meta, 7, "serpentine")
    State.run.wave_index = 5
    State.pending = nil
    local real_mp, real_mh, real_mo = input.mouse_pressed, input.mouse_held, input.mouse
    input.mouse_held = function()
      return false
    end
    input.mouse_pressed = function()
      return false
    end
    input.mouse = function()
      return 0, 0
    end
    contract_s.init()
    check(State.run.contract_draft and #State.run.contract_draft >= 1, "contract scene drafts on init")
    contract_s.update(1 / 60)
    check(State.run.contract_ready, "contract scene arms after the mouse is released")
    contract_s.draw(1 / 60)
    local n = #State.run.contract_draft
    local TW, GAP = 146, 10
    local x0 = (C.GAME_W - (n * TW + (n - 1) * GAP)) * 0.5
    input.mouse_pressed = function(button)
      return button == 1
    end
    input.mouse = function()
      return x0 + TW * 0.5, 62 + 40
    end
    contract_s.update(1 / 60)
    input.mouse_pressed, input.mouse_held, input.mouse = real_mp, real_mh, real_mo
    check(
      State.run.active_contract ~= nil and State.pending == "game",
      "signing a contract card returns to the game scene"
    )
    State.run = nil
    State.pending = nil
  end

  -- reward is NOT paid when the run dies on the same frame the field clears
  do
    State.run = run_mod.new(State.meta, 1, "serpentine")
    State.run.phase = "combat"
    State.run.wave_index = 3
    State.run.active_contract = { id = "enrage", risk = {}, reward = { charge = 18 } }
    State.run.charge = 0
    State.run.lives = 0 -- already fatally leaked
    State.run.enemies.n = 0 -- field clear this frame
    State.run.spawn_queue.n, State.run.spawn_queue.i = 0, 0
    State.run.sim_acc = 0
    State.ui.speed = 1
    State.pending = nil
    game_s.update(1 / 60)
    check(State.run.charge == 0, "no contract reward when the run dies on the clearing frame")
    check(State.pending == "gameover", "a dead run routes to gameover, not the reward path")
    State.run = nil
    State.pending = nil
  end
end

return M

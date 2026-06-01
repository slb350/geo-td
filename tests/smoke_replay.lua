-- Replay-metadata cases (V2-M9): a run snapshot is deterministic (same run+report
-- -> identical metadata), its share code recreates the seed/map/mode, a non-standard
-- mode is carried, and format produces a human-readable bug-report block. Run by
-- smoke.lua via M.run(check, near).

local meta = require("lib.meta")
local run_mod = require("lib.run")
local report = require("lib.report")
local replay = require("lib.replay")
local share = require("lib.share")
local sim = require("lib.sim")
local path = require("lib.path")
local C = require("lib.const")
local game_s = require("scenes.game")
local route_s = require("scenes.route")
local contract_s = require("scenes.contract")
local gameover_s = require("scenes.gameover")
local tower = require("lib.tower")
local modifier = require("lib.modifier")
local helpers = require("tests.helpers")

local M = {}

-- Silence the mouse so a scene's init/update sees no click; returns the originals
-- to hand back to restore_mouse. The test then arms a positioned click as needed.
local function mock_quiet_mouse()
  local saved = { input.mouse_pressed, input.mouse_held, input.mouse }
  input.mouse_held = function()
    return false
  end
  input.mouse_pressed = function()
    return false
  end
  input.mouse = function()
    return 0, 0
  end
  return saved
end

local function restore_mouse(saved)
  input.mouse_pressed, input.mouse_held, input.mouse = saved[1], saved[2], saved[3]
end

function M.run(check, near)
  local m = meta.default()

  -- ------------------------------------------------------ deterministic snapshot
  local r = run_mod.new(m, 4242, "serpentine")
  r.final_wave = 17
  r.bosses_killed = 3
  r.kills = 120
  r.score = 1800
  r.arena_kills = 6
  r.contract_history = { "enrage" }
  r.affix_history = { "overclock", "fracture" }
  local rep = report.build(r)
  local a = replay.snapshot(r, rep)
  local b = replay.snapshot(r, rep)
  check(
    a.seed == 4242 and a.map == "serpentine" and a.mode == "standard",
    "snapshot carries the run's seed/map/mode ids"
  )
  check(
    a.wave == 17 and a.bosses == 3 and a.score == 1800 and a.arena_kills == 6 and a.contracts == 1 and a.affixes == 2,
    "snapshot carries the report stats"
  )
  check(
    a.seed == b.seed and a.share == b.share and a.wave == b.wave and a.mode == b.mode,
    "snapshot is deterministic for the same run + report"
  )

  -- ------------------------------------------------- the share code recreates it
  local cfg = share.decode(a.share)
  check(
    cfg ~= nil and cfg.seed == 4242 and cfg.map == "serpentine" and cfg.mode == "standard",
    "the snapshot share code decodes back to the run config"
  )

  -- --------------------------------------------------------- a challenge mode
  local rc = run_mod.new(m, 7, "chicane", "no_rail")
  rc.final_wave = 10
  local repc = report.build(rc)
  local sc = replay.snapshot(rc, repc)
  check(sc.mode == "no_rail" and sc.mode_name == "No Rail", "snapshot carries a challenge mode id + name")
  check(share.decode(sc.share).mode == "no_rail", "the challenge-mode share code round-trips")

  -- ------------------------------------------------------------- format block
  local txt = replay.format(a)
  check(
    type(txt) == "string" and txt:find("GTD2") and txt:find("4242") and txt:find("serpentine") and txt:find("wave 17"),
    "format produces a human-readable seed/map/mode/wave block"
  )

  -- ------------------------------------------- snapshot carries the build plan + ids
  local rl = run_mod.new(m, 7, "serpentine")
  rl.log = { { wave = 1, place = { kind = "pellet", x = 100, y = 80 } } }
  rl.contract_history = { "enrage" }
  rl.affix_history = { "overclock" }
  local sl = replay.snapshot(rl, report.build(rl))
  check(
    sl.plan ~= rl.log and #sl.plan == 1 and sl.plan[1].place.kind == "pellet",
    "snapshot carries a copied recorded build plan"
  )
  check(
    type(sl.summary) == "table"
      and sl.summary.wave == report.build(rl).wave
      and sl.summary.score == report.build(rl).score,
    "snapshot carries a replay-verifiable summary block"
  )
  check(
    sl.contract_ids[1] == "enrage" and sl.affix_ids[1] == "overclock",
    "snapshot carries the decision ids (not just counts)"
  )

  -- ------------------------------------------------ verify replays the plan via sim
  local all_places = helpers.map_cordon(m, "serpentine", { step = 70, wave = 1 })
  local plan = {}
  for i = 1, 3 do
    plan[i] = all_places[i]
  end
  local probe = sim.run({ seed = 1234, map = "serpentine", mode = "standard", waves = 30, plan = plan })
  local F = probe.final_wave
  local snap = { seed = 1234, map = "serpentine", mode = "standard", wave = F, plan = plan }
  local v = replay.verify(snap)
  check(v.reproduced and v.actual_wave == F, "verify replays the plan and reproduces the final wave")
  check(replay.verify(snap).actual_wave == v.actual_wave, "verify is deterministic")
  local bad = { seed = 1234, map = "serpentine", mode = "standard", wave = F + 5, plan = plan }
  check(not replay.verify(bad).reproduced, "verify rejects a tampered final wave")

  probe.run.log = plan
  local full = replay.snapshot(probe.run, report.build(probe.run))
  local vf = replay.verify(full)
  check(vf.reproduced and vf.summary_matches, "verify compares the replayed summary, not only the wave")
  local tampered = replay.snapshot(probe.run, report.build(probe.run))
  if tampered.summary then
    tampered.summary.score = tampered.summary.score + 1
    tampered.score = tampered.score + 1
    local vt = replay.verify(tampered)
    check(not vt.reproduced and vt.mismatches and vt.mismatches.score, "verify rejects a tampered replay summary score")
  else
    check(false, "verify rejects a tampered replay summary score")
  end

  -- ------------------------------------- sim can replay non-build decisions too
  do
    local replay_plan = helpers.map_cordon(m, "zigzag", { step = 40, wave = 1 })
    replay_plan[#replay_plan + 1] = { wave = 2, targeting = { tower = 1, value = "closest" } }
    replay_plan[#replay_plan + 1] = { wave = 3, contract = { decline = true } }
    replay_plan[#replay_plan + 1] = { wave = 4, route = { id = "null" } }
    local sr = sim.run({ seed = 7, map = "zigzag", waves = 4, money = 99999, plan = replay_plan })
    check(#sr.errors == 0, "sim replays targeting, contract, and route decisions")
    local first = sim.tower_by_id(sr.run, 1)
    check(first and first.targeting_override == "closest", "sim applies targeting override decisions")
  end

  -- ------------------------------------- the game scene records a placement to the log
  do
    State.meta = meta.default()
    State.run = run_mod.new(State.meta, 8, "serpentine")
    State.run.money = 9999
    State.run.phase = "building"
    State.run.wave_index = 2 -- building for wave 3
    State.ui.selected = "pellet"
    State.ui.sell_mode = false
    State.ui.inspect = nil
    local bx, by
    for gx = 16, C.HUD_X - 16, 8 do
      for gy = 16, C.GAME_H - 16, 8 do
        if path.dist_to(State.run.path, gx, gy) > C.PLACE_MARGIN + 4 then
          bx, by = gx, gy
          break
        end
      end
      if bx then break end
    end
    local before = #State.run.log
    input._clicks.left, input._clicks.mx, input._clicks.my = true, bx, by
    game_s.update(1 / 60)
    input._clicks.left = false
    check(#State.run.log == before + 1, "the game scene records a placement to the replay log")
    local last = State.run.log[#State.run.log]
    check(last.place and last.place.kind == "pellet", "the recorded action is the placement")
    check(last.wave == 3, "the placement is stamped with the upcoming wave (build phase)")
    State.run = nil
    State.ui.selected = nil
  end

  -- ------------------------------ combat field clicks do not mutate build state
  do
    State.meta = meta.default()
    State.run = run_mod.new(State.meta, 9, "serpentine")
    State.run.money = 9999
    State.run.phase = "combat"
    State.run.wave_index = 3
    State.ui.selected = "pellet"
    State.ui.sell_mode = false
    State.ui.inspect = nil
    local bx, by
    for gx = 16, C.HUD_X - 16, 8 do
      for gy = 16, C.GAME_H - 16, 8 do
        if path.dist_to(State.run.path, gx, gy) > C.PLACE_MARGIN + 4 then
          bx, by = gx, gy
          break
        end
      end
      if bx then break end
    end
    local towers_before, log_before = #State.run.towers, #State.run.log
    input._clicks.left, input._clicks.mx, input._clicks.my = true, bx, by
    game_s.update(1 / 60)
    input._clicks.left = false
    check(#State.run.towers == towers_before, "combat field clicks do not place selected towers")
    check(#State.run.log == log_before, "combat field clicks do not record build actions")
    State.run = nil
    State.ui.selected = nil
  end

  -- ---------------------------------- scenes record interactive decisions
  do
    State.meta = meta.default()
    State.run = run_mod.new(State.meta, 11, "serpentine")
    State.run.money = 9999
    local t = tower.place(State.run, 160, 70, "pellet")
    State.run.phase = "building"
    State.run.wave_index = 1
    State.ui.inspect = t
    local before = #State.run.log
    -- targeting button in the inspect panel
    input._clicks.left, input._clicks.mx, input._clicks.my = true, C.HUD_X + 10, C.GAME_H - 35
    game_s.update(0)
    input._clicks.left = false
    local act = State.run.log[#State.run.log]
    check(
      #State.run.log == before + 1 and act.targeting and act.targeting.tower == t.id,
      "the game scene records targeting override changes"
    )

    -- module reroll through the inspect panel
    modifier.socket_module(State.run, t, "triangle")
    State.run.charge = C.MODULE_REROLL_COST or 0
    before = #State.run.log
    input._clicks.left, input._clicks.mx, input._clicks.my = true, C.HUD_X + 10, 168
    game_s.update(0)
    input._clicks.left = false
    act = State.run.log[#State.run.log]
    check(
      #State.run.log == before + 1 and act.reroll and act.reroll.tower == t.id,
      "the game scene records module-reroll decisions"
    )

    -- active ability timings are stamped with the current combat wave/frame
    State.ui.inspect = nil
    State.run.phase = "combat"
    State.run.wave_index = 2
    State.run.combat_frame = 17
    State.run.money = 1000
    State.run.enemies.n = 0
    local e = require("lib.enemy").spawn(State.run, "mote", 1, 1, 10)
    e.x, e.y = 180, 90
    before = #State.run.log
    input._keys[input.KEY_O] = true
    game_s.update(0)
    input._keys[input.KEY_O] = false
    act = State.run.log[#State.run.log]
    check(
      #State.run.log == before + 1 and act.orbital and act.wave == 2 and act.frame == 17,
      "orbital replay entries carry combat wave/frame timing"
    )

    State.run.phase = "combat"
    State.run.wave_index = 3
    State.run.combat_frame = 5
    State.run.charge = 50
    State.run.enemies.n = 0
    e = require("lib.enemy").spawn(State.run, "hulk", 1, 1, 10)
    e.x, e.y = 180, 90
    before = #State.run.log
    input._keys[input.KEY_D] = true
    game_s.update(0)
    input._keys[input.KEY_D] = false
    act = State.run.log[#State.run.log]
    check(
      #State.run.log == before + 1 and act.discharge and act.wave == 3 and act.frame == 5,
      "discharge replay entries carry combat wave/frame timing"
    )

    State.run.phase = "combat"
    State.run.wave_index = 1
    State.run.combat_frame = 23
    State.run.boss = nil
    State.run.spawn_queue.n = 0
    State.run.spawn_queue.i = 0
    State.run.enemies.n = 1
    State.run.enemies[1] = { dead = false, x = 50, y = 50, size = 3 }
    before = #State.run.log
    input._keys[input.KEY_SPACE] = true
    game_s.update(0)
    input._keys[input.KEY_SPACE] = false
    act = State.run.log[#State.run.log]
    check(
      #State.run.log == before + 1 and act.call_early and act.wave == 1 and act.frame == 23,
      "call-early replay entries carry the original combat wave/frame"
    )
    State.run = nil
    State.ui.inspect = nil
  end

  -- route/contract/gameover scenes record full replay metadata
  do
    State.meta = meta.default()
    State.run = run_mod.new(State.meta, 7, "zigzag")
    State.pending = nil
    local saved = mock_quiet_mouse()
    route_s.init()
    route_s.update(0)
    local n = #State.run.route_draft
    local x0 = (C.GAME_W - (n * 146 + (n - 1) * 10)) * 0.5
    local before = #State.run.log
    input.mouse_pressed = function(button)
      return button == 1
    end
    input.mouse = function()
      return x0 + 73, 56 + 75
    end
    route_s.update(0)
    restore_mouse(saved)
    local act = State.run.log[#State.run.log]
    check(#State.run.log == before + 1 and act.route and act.route.id, "route scene records the chosen route card id")

    State.run = run_mod.new(State.meta, 9, "serpentine")
    State.run.wave_index = 2
    saved = mock_quiet_mouse()
    contract_s.init()
    contract_s.update(0)
    before = #State.run.log
    input.mouse_pressed = function(button)
      return button == 1
    end
    input.mouse = function()
      return C.GAME_W * 0.5, 62 + 60
    end
    contract_s.update(0)
    restore_mouse(saved)
    act = State.run.log[#State.run.log]
    check(
      #State.run.log == before + 1 and act.contract and act.contract.id,
      "contract scene records the signed contract id"
    )

    State.run.final_wave = State.run.wave_index
    gameover_s.init()
    check(
      State.summary and State.summary.replay and State.summary.share == State.summary.replay.share,
      "gameover retains the full replay snapshot, not only the share code"
    )
    State.run = nil
    State.pending = nil
  end
end

return M

-- Replay-metadata cases (V2-M9): a run snapshot is deterministic (same run+report
-- -> identical metadata), its share code recreates the seed/map/mode, a non-standard
-- mode is carried, and format produces a human-readable bug-report block. Run by
-- smoke.lua via M.run(check, near).

local meta    = require("lib.meta")
local run_mod = require("lib.run")
local report  = require("lib.report")
local replay  = require("lib.replay")
local share   = require("lib.share")
local sim     = require("lib.sim")
local path    = require("lib.path")
local C       = require("lib.const")
local game_s  = require("scenes.game")

local M = {}

function M.run(check, near)
  local m = meta.default()

  -- ------------------------------------------------------ deterministic snapshot
  local r = run_mod.new(m, 4242, "serpentine")
  r.final_wave = 17; r.bosses_killed = 3; r.kills = 120; r.score = 1800
  r.arena_kills = 6; r.contract_history = { "enrage" }; r.affix_history = { "overclock", "fracture" }
  local rep = report.build(r)
  local a = replay.snapshot(r, rep)
  local b = replay.snapshot(r, rep)
  check(a.seed == 4242 and a.map == "serpentine" and a.mode == "standard",
    "snapshot carries the run's seed/map/mode ids")
  check(a.wave == 17 and a.bosses == 3 and a.score == 1800 and a.arena_kills == 6
    and a.contracts == 1 and a.affixes == 2, "snapshot carries the report stats")
  check(a.seed == b.seed and a.share == b.share and a.wave == b.wave and a.mode == b.mode,
    "snapshot is deterministic for the same run + report")

  -- ------------------------------------------------- the share code recreates it
  local cfg = share.decode(a.share)
  check(cfg ~= nil and cfg.seed == 4242 and cfg.map == "serpentine" and cfg.mode == "standard",
    "the snapshot share code decodes back to the run config")

  -- --------------------------------------------------------- a challenge mode
  local rc = run_mod.new(m, 7, "chicane", "no_rail")
  rc.final_wave = 10
  local repc = report.build(rc)
  local sc = replay.snapshot(rc, repc)
  check(sc.mode == "no_rail" and sc.mode_name == "No Rail", "snapshot carries a challenge mode id + name")
  check(share.decode(sc.share).mode == "no_rail", "the challenge-mode share code round-trips")

  -- ------------------------------------------------------------- format block
  local txt = replay.format(a)
  check(type(txt) == "string" and txt:find("GTD2") and txt:find("4242")
    and txt:find("serpentine") and txt:find("wave 17"),
    "format produces a human-readable seed/map/mode/wave block")

  -- ------------------------------------------- snapshot carries the build plan + ids
  local rl = run_mod.new(m, 7, "serpentine")
  rl.log = { { wave = 1, place = { kind = "pellet", x = 100, y = 80 } } }
  rl.contract_history = { "enrage" }; rl.affix_history = { "overclock" }
  local sl = replay.snapshot(rl, report.build(rl))
  check(sl.plan == rl.log and #sl.plan == 1, "snapshot carries the recorded build plan")
  check(sl.contract_ids[1] == "enrage" and sl.affix_ids[1] == "overclock",
    "snapshot carries the decision ids (not just counts)")

  -- ------------------------------------------------ verify replays the plan via sim
  local plan = {
    { wave = 1, place = { kind = "pellet", x = 96,  y = 92 } },
    { wave = 1, place = { kind = "pellet", x = 150, y = 70 } },
    { wave = 2, place = { kind = "pellet", x = 210, y = 120 } },
    { wave = 3, place = { kind = "pellet", x = 120, y = 150 } },
  }
  local probe = sim.run({ seed = 1234, map = "serpentine", mode = "standard", waves = 30, plan = plan })
  local F = probe.final_wave
  local snap = { seed = 1234, map = "serpentine", mode = "standard", wave = F, plan = plan }
  local v = replay.verify(snap)
  check(v.reproduced and v.actual_wave == F, "verify replays the plan and reproduces the final wave")
  check(replay.verify(snap).actual_wave == v.actual_wave, "verify is deterministic")
  local bad = { seed = 1234, map = "serpentine", mode = "standard", wave = F + 5, plan = plan }
  check(not replay.verify(bad).reproduced, "verify rejects a tampered final wave")

  -- ------------------------------------- the game scene records a placement to the log
  do
    State.meta = meta.default()
    State.run = run_mod.new(State.meta, 8, "serpentine"); State.run.money = 9999
    State.run.phase = "building"; State.run.wave_index = 2        -- building for wave 3
    State.ui.selected = "pellet"; State.ui.sell_mode = false; State.ui.inspect = nil
    local bx, by
    for gx = 16, C.HUD_X - 16, 8 do
      for gy = 16, C.GAME_H - 16, 8 do
        if path.dist_to(State.run.path, gx, gy) > C.PLACE_MARGIN + 4 then bx, by = gx, gy; break end
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
    State.run = nil; State.ui.selected = nil
  end
end

return M

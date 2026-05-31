-- Replay-metadata cases (V2-M9): a run snapshot is deterministic (same run+report
-- -> identical metadata), its share code recreates the seed/map/mode, a non-standard
-- mode is carried, and format produces a human-readable bug-report block. Run by
-- smoke.lua via M.run(check, near).

local meta    = require("lib.meta")
local run_mod = require("lib.run")
local report  = require("lib.report")
local replay  = require("lib.replay")
local share   = require("lib.share")

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
end

return M

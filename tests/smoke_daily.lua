-- Daily-challenge + meta-contract cases (V2-M7): daily determinism (stable per
-- day, varies across days, valid map/mode), the contract board (generic report
-- predicate, deterministic ORDER fill skipping completed goals, evaluate paying
-- shards + badge and refilling), the gameover integration (a finished run
-- completes a board goal end to end), and the menu Contracts/Daily panels
-- (render + PLAY DAILY launch). Run by smoke.lua AFTER smoke_core.

local meta = require("lib.meta")
local run_mod = require("lib.run")
local maps = require("lib.maps")
local modes = require("lib.modes")
local daily = require("lib.daily")
local mc = require("lib.metacontract")
local menu_s = require("scenes.menu")
local gameover_s = require("scenes.gameover")

local M = {}

function M.run(check, near)
  -- ------------------------------------------------------------------- daily
  local d1, d1b = daily.for_day(20000), daily.for_day(20000)
  check(
    d1.map == d1b.map and d1.mode == d1b.mode and d1.seed == d1b.seed,
    "the daily challenge is stable for a given day"
  )
  local d2 = daily.for_day(20001)
  check(d2.seed ~= d1.seed, "a different day yields a different seed")
  check(maps.get(d1.map) ~= nil, "the daily picks a real map")
  check(modes.get(d1.mode).id == d1.mode, "the daily picks a real mode")
  check(type(daily.today()) == "number", "daily.today returns a day index")

  -- ------------------------------------------------------ meta-contract check
  check(mc.check(mc.DEFS.first_blood, { wave = 8 }), "gte goal met at the threshold")
  check(not mc.check(mc.DEFS.first_blood, { wave = 7 }), "gte goal unmet below the threshold")
  check(mc.check(mc.DEFS.chicane_climb, { wave = 12, map = "Chicane" }), "a multi-condition goal needs all conditions")
  check(not mc.check(mc.DEFS.chicane_climb, { wave = 12, map = "Zigzag" }), "a wrong map fails the eq condition")
  check(mc.check(mc.DEFS.lattice_seen, { final_boss = true }), "a boolean eq goal matches true")
  check(not mc.check(mc.DEFS.lattice_seen, { final_boss = false }), "a boolean eq goal rejects false")

  -- -------------------------------------------------------- board refresh fill
  local m = meta.default()
  mc.refresh(m)
  check(#m.contract_board == mc.BOARD_SIZE, "refresh fills the board to BOARD_SIZE")
  check(m.contract_board[1] == mc.ORDER[1], "the board fills deterministically in ORDER")
  local m2 = meta.default()
  m2.completed_contracts = { [mc.ORDER[1]] = true }
  mc.refresh(m2)
  check(#m2.contract_board == mc.BOARD_SIZE, "the board still fills to size around a completed goal")
  local skipped = true
  for i = 1, #m2.contract_board do
    if m2.contract_board[i] == mc.ORDER[1] then skipped = false end
  end
  check(skipped, "a completed goal is not re-offered on the board")

  -- ------------------------------------------------------------ board evaluate
  local me = meta.default()
  mc.refresh(me) -- board = first_blood, boss_trio, centurion
  local rep = {
    wave = 8,
    bosses_killed = 0,
    score = 0,
    contracts = 0,
    affixes = 0,
    arena_kills = 0,
    final_boss = false,
    map = "Serpentine",
  }
  local done = mc.evaluate(me, rep)
  local got_first = false
  for i = 1, #done do
    if done[i] == "first_blood" then got_first = true end
  end
  check(#done == 1 and got_first, "evaluate completes exactly the satisfied goal (first_blood)")
  check(me.completed_contracts.first_blood == true, "evaluate marks the goal completed")
  check(me.bank_shards == mc.DEFS.first_blood.shards, "evaluate pays the goal's shards")
  check(me.badges.veteran == true, "evaluate awards the goal's badge")
  check(#me.contract_board == mc.BOARD_SIZE, "evaluate refills the board to size")
  local left = true
  for i = 1, #me.contract_board do
    if me.contract_board[i] == "first_blood" then left = false end
  end
  check(left, "a completed goal leaves the board")

  -- --------------------------------------------------- gameover integration
  do
    State.meta = meta.default()
    mc.refresh(State.meta)
    State.run = run_mod.new(State.meta, 1, "serpentine")
    State.run.final_wave = 8 -- report wave = 8 -> first_blood
    State.pending = nil
    gameover_s.init()
    check(State.summary ~= nil, "gameover builds a run summary")
    local surfaced = false
    for i = 1, #(State.summary.contracts_done or {}) do
      if State.summary.contracts_done[i] == mc.DEFS.first_blood.name then surfaced = true end
    end
    check(surfaced, "gameover surfaces a completed meta-contract")
    check(State.meta.badges.veteran == true, "gameover persists the earned badge")
    check(State.meta.completed_contracts.first_blood == true, "gameover marks the goal completed in meta")
    gameover_s.draw(1 / 60) -- renders the completed-goal line
    State.run = nil
    State.summary = nil
    State.pending = nil
  end

  -- ------------------------------------------------- menu Contracts/Daily panels
  State.meta = meta.default()
  mc.refresh(State.meta)
  State.ui.menu_tab = "contracts"
  menu_s.draw(1 / 60) -- the board renders without error
  State.ui.menu_tab = "daily"
  menu_s.draw(1 / 60)
  local drows = menu_s.tab_rows("daily")
  check(#drows == 1, "the daily tab exposes a single launch button")
  check(drows[1].y + drows[1].h <= 94 + 150, "the PLAY DAILY button sits inside the panel")
  State.run = nil
  State.pending = nil
  local b = drows[1]
  input._clicks.left, input._clicks.mx, input._clicks.my = true, b.x + b.w * 0.5, b.y + b.h * 0.5
  menu_s.update(1 / 60)
  input._clicks.left = false
  check(State.run ~= nil and State.pending == "game", "PLAY DAILY launches a run on the daily seed")
  State.run = nil
  State.pending = nil
  State.ui.menu_tab = "shop"
end

return M

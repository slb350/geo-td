-- Mastery + save-migration cases (V2-M7): the buy gate (missing bank / missing
-- shards / already-owned / unknown id), the two-currency deduction, the derived
-- apply fold into a run (money/lives/mods, with One Life respecting its lives
-- override), default-run inertness, the v1->v2 save migration (no data loss) +
-- unknown-version fallback, and the menu Mastery panel (layout fit + buy-on-click).
-- Run by smoke.lua via M.run(check, near) AFTER smoke_core installs the scene globals.

local C = require("lib.const")
local meta = require("lib.meta")
local run_mod = require("lib.run")
local mastery = require("lib.mastery")
local menu_s = require("scenes.menu")

local M = {}

function M.run(check, near)
  -- ----------------------------------------------------------------- buy gate
  check(#mastery.ORDER == 6, "six mastery nodes")
  local mb = meta.default()
  check(not mastery.can_buy(mb, "builder_economy"), "no bank -> cannot buy a node")
  mb.currency = 20
  check(mastery.can_buy(mb, "builder_economy"), "enough bank -> a non-premium node is buyable")
  check(mastery.buy(mb, "builder_economy"), "buy succeeds")
  check(mb.currency == 0 and mastery.owned(mb, "builder_economy"), "buy deducts bank + flags owned")
  check(not mastery.can_buy(mb, "builder_economy"), "an owned node cannot be re-bought")
  check(not mastery.buy(mb, "builder_economy"), "buying an owned node fails")
  check(not mastery.can_buy(meta.default(), "no_such_node"), "an unknown node id is not buyable")

  -- premium node: needs BOTH bank and shards
  local mp = meta.default()
  mp.currency = 100
  check(not mastery.can_buy(mp, "arsenal_precision"), "a premium node rejects missing shards")
  mp.bank_shards = 3
  check(mastery.can_buy(mp, "arsenal_precision"), "a premium node is buyable once shards are held")
  mastery.buy(mp, "arsenal_precision")
  check(mp.currency == 64 and mp.bank_shards == 0, "a premium buy deducts both bank and shards")

  -- ------------------------------------------------------------- apply: fold
  local base = run_mod.new(meta.default(), 1, "serpentine")
  check(
    near(base.mods.dmg_mult, 1)
      and base.mods.crit_chance == 0
      and near(base.mods.bounty_mult, 1)
      and base.mods.interest == 0,
    "a default run carries no mastery effects (balance-neutral)"
  )
  check(base.money == C.START_MONEY, "default run starts at base money")

  local function owned_run(id, mode_id)
    local mm = meta.default()
    mm.mastery = { [id] = true }
    return run_mod.new(mm, 1, "serpentine", mode_id)
  end
  check(owned_run("builder_economy").money == C.START_MONEY + 30, "Surveyor adds +30 start money")
  check(near(owned_run("builder_interest").mods.interest, 0.02), "Investor adds +2% interest")
  check(near(owned_run("arsenal_caliber").mods.dmg_mult, 1.06), "Caliber adds +6% damage")
  check(near(owned_run("arsenal_precision").mods.crit_chance, 0.05), "Precision adds +5% crit")
  check(near(owned_run("survival_salvage").mods.bounty_mult, 1.1), "Salvage adds +10% bounty")
  check(owned_run("survival_bulwark").lives == C.START_LIVES + 5, "Bulwark adds +5 start lives")
  check(
    owned_run("survival_bulwark", "one_life").lives == 1,
    "One Life's fixed lives override ignores the Bulwark bonus"
  )

  -- ---------------------------------------------------- v1 -> v2 save migration
  local v1 = {
    version = 1,
    currency = 50,
    best_wave = 9,
    total_runs = 4,
    unlocks = { tower_rail = true, tower_flak = false, start_bonus = false },
    map_unlocked = { zigzag = true, spiral = true },
    map_best = { zigzag = 22 },
  }
  meta.save(v1)
  local up = meta.load()
  check(up.version == 2, "a v1 save migrates to v2")
  check(
    up.currency == 50 and up.best_wave == 9 and up.total_runs == 4,
    "migration preserves currency / best wave / run count"
  )
  check(up.unlocks.tower_rail == true and up.map_best.zigzag == 22, "migration preserves unlocks + per-map bests")
  check(
    up.bank_shards == 0
      and type(up.mastery) == "table"
      and type(up.badges) == "table"
      and type(up.contract_board) == "table"
      and type(up.completed_contracts) == "table"
      and type(up.daily) == "table",
    "migration backfills every v2 field"
  )
  meta.save({ version = 99, currency = 999 })
  check(meta.load().currency == 0, "an unknown future save version falls back to default")
  -- a truncated/corrupted v2 save (right version, missing core fields) is backfilled,
  -- not crashed: finish_run's arithmetic must not hit a nil currency/best_wave/total_runs.
  meta.save({ version = 2 })
  local fixed = meta.load()
  check(
    fixed.currency == 0 and fixed.best_wave == 0 and fixed.total_runs == 0,
    "a partial v2 save backfills the core fields"
  )
  local ok = pcall(meta.finish_run, fixed, 6, 0, nil, 0)
  check(ok and fixed.currency == 6 * C.META_PER_WAVE, "finish_run survives a backfilled partial save")

  -- --------------------------------------------------------- menu Mastery panel
  State.meta = meta.default()
  State.meta.currency = 100
  State.ui.menu_tab = "mastery"
  local rows = menu_s.tab_rows("mastery")
  check(#rows == #mastery.ORDER, "the mastery tab lays out one row per node")
  local last = rows[#rows]
  check(last.y + last.h <= 94 + 150, "every mastery row stays inside the content panel")
  local r1 = rows[1] -- builder_economy (bank 20)
  input._clicks.left, input._clicks.mx, input._clicks.my = true, r1.x + r1.w * 0.5, r1.y + r1.h * 0.5
  menu_s.update(1 / 60)
  input._clicks.left = false
  check(mastery.owned(State.meta, "builder_economy"), "clicking a mastery row buys the node")
  check(State.meta.currency == 80, "the menu buy deducts the bank cost")
  menu_s.draw(1 / 60) -- the mastery panel renders without error
  State.meta = meta.default() -- leave a clean meta for later suites
end

return M

-- Headless smoke runner. Loads the engine-stub harness (tests/harness.lua: fake
-- gfx/usagi/effect/sfx/music + a tiny JSON reader) and drives every test suite
-- against the real lib/* + scenes/* logic under plain LuaJIT, catching runtime
-- errors (nil indexing, bad arithmetic, pool bugs) a syntax check can't. Run from
-- the project root:
--     luajit tests/smoke.lua
-- This file is NOT loaded by the engine (it only reads main.lua + assets).
--
-- Each suite is a module exposing run(check, near) and shares these check
-- counters. smoke_core runs FIRST: it carries the broad baseline cases and
-- installs the scene globals (State / SwitchScene / input) the later suites reuse.

package.path = "./?.lua;" .. package.path
require("tests.harness")  -- installs the fake engine globals (before any lib loads)

local checks, fails = 0, 0
local function check(cond, msg)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    print("  FAIL: " .. msg)
  end
end

local function near(a, b)
  return math.abs(a - b) < 0.000001
end

-- Suites in dependency order. smoke_core first (baseline + scene globals); the
-- balance-lab suites (sim driver + balance fixtures) are the V2-M0 additions.
require("tests.smoke_core").run(check, near)
require("tests.smoke_report").run(check, near)
require("tests.smoke_cards").run(check, near)
require("tests.smoke_modifier").run(check, near)
require("tests.smoke_aura").run(check, near)
require("tests.smoke_telegraph").run(check, near)
require("tests.smoke_modes").run(check, near)
require("tests.smoke_pathmut").run(check, near)
require("tests.smoke_routedraft").run(check, near)
require("tests.smoke_resource").run(check, near)
require("tests.smoke_contracts").run(check, near)
require("tests.smoke_resonance").run(check, near)
require("tests.smoke_affix").run(check, near)
require("tests.smoke_arena").run(check, near)
require("tests.smoke_tactical").run(check, near)
require("tests.smoke_mastery").run(check, near)
require("tests.smoke_daily").run(check, near)
require("tests.smoke_share").run(check, near)
require("tests.smoke_sim").run(check, near)
require("tests.smoke_balance").run(check, near)

print(("smoke: %d checks, %d failures"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)

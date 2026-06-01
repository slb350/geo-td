-- Production performance gates (V2-M9): assert the explicit budgets the roadmap
-- calls out beyond peak enemies/projectiles -- draw-call count in the headless
-- harness and max sim-step wall time in the benchmark driver.

local C       = require("lib.const")
local meta    = require("lib.meta")
local sim     = require("lib.sim")
local helpers = require("tests.helpers")
local harness = require("tests.harness")
local game_s  = require("scenes.game")

local M = {}

function M.run(check, near)
  local m = meta.default()
  local plan = helpers.map_cordon(m, "zigzag", { step = 30, wave = 1 })
  local result = sim.run({
    seed = 1234, map = "zigzag", mode = "standard", waves = 8,
    money = 99999, meta = m, plan = plan, affixes = false,
  })

  local step_budget = C.PERF_MAX_SIM_STEP or 0
  check(step_budget > 0, "perf: max sim-step budget is configured")
  check(type(result.max_step_time) == "number" and result.max_step_time >= 0,
    "perf: sim reports max per-step wall time")
  check(step_budget > 0 and result.max_step_time <= step_budget,
    "perf: max sim step stays within budget")

  State.meta = m
  State.run = result.run
  State.ui = {
    selected = nil, sell_mode = false, inspect = nil, hover_x = 0, hover_y = 0,
    hover_valid = false, speed = 1,
  }
  harness.reset_gfx()
  game_s.draw(1 / 60)
  local calls = #harness.gfx_calls()
  local draw_budget = C.PERF_MAX_DRAW_CALLS or 0
  check(draw_budget > 0, "perf: draw-call budget is configured")
  check(calls > 0 and draw_budget > 0 and calls <= draw_budget,
    "perf: draw-call count stays within harness budget")
  State.run = nil
end

return M

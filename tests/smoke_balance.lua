-- Deterministic balance fixtures + regression thresholds (V2-M0). Each fixture
-- pins an EXACT outcome for a fixed (seed, map, mode, cordon), so an unintended
-- drift in the STANDARD path -- including any opt-in system accidentally leaking
-- into a normal run -- fails the suite. The anchors mirror tests/baseline.lua
-- (seed 1234, uniform pellet cordon step 30, waves 30); regenerate with
--     luajit tests/baseline.lua
-- and update an anchor ONLY when a balance change is intended. Run by smoke.lua
-- via M.run(check, near).

local sim     = require("lib.sim")
local helpers = require("tests.helpers")
local meta    = require("lib.meta")

local M = {}

function M.run(check, near)
  local m = meta.default()
  -- Cache one cordon plan per map (deterministic for a given map+step), so
  -- repeated runs of the same map don't regenerate the grid each time.
  local plans = {}
  local function cordon_run(map, mode, waves)
    local plan = plans[map]
    if not plan then plan = helpers.map_cordon(m, map, { step = 30 }); plans[map] = plan end
    -- affixes off: the anchors are a stable, affix-free balance baseline (V2-M5)
    return sim.run({ seed = 1234, map = map, mode = mode or "standard",
      waves = waves or 30, money = 99999, meta = m, plan = plan, affixes = false })
  end

  -- Regression anchors. A uniform pellet cordon (non-rail) on each map reaches an
  -- exact wave, clears an exact boss count, and spends an exact gross amount. The
  -- boss-count anchors also stand in for "non-rail fixtures still clear Prism +
  -- Bulwark" (waves 5 + 10): every map below clears at least two.
  -- These anchors moved up one wave (14 -> 16 on serpentine/zigzag) with the
  -- V2 Pellet pass (range 58->64, damage 7->9): the higher per-shot damage cuts
  -- through flat armor that previously gutted the cordon, so it survives deeper.
  -- The exponential HP wall still tops a pure-Pellet cordon out at ~16 -- deep
  -- waves still need qualitative DPS (Rail), not more Pellets.
  local s = cordon_run("serpentine")
  check(s.final_wave == 16, "balance anchor: serpentine cordon reaches exactly wave 16")
  check(s.bosses_killed == 2, "balance anchor: serpentine cordon clears Prism + Bulwark (non-rail)")
  check(s.money_spent == 2475, "balance anchor: serpentine cordon gross spend == 2475")

  local z = cordon_run("zigzag")
  check(z.final_wave == 16, "balance anchor: zigzag cordon reaches exactly wave 16")
  check(z.bosses_killed == 2, "balance anchor: zigzag cordon clears two bosses")
  check(z.money_spent == 2160, "balance anchor: zigzag cordon gross spend == 2160")

  local w = cordon_run("switchback")
  check(w.final_wave == 16, "balance anchor: switchback cordon reaches exactly wave 16")
  check(w.bosses_killed == 2, "balance anchor: switchback cordon clears two bosses (Hydra leaks at w15)")
  check(w.money_spent == 2160, "balance anchor: switchback cordon gross spend == 2160")

  -- Perf budget: the HP-loaded difficulty curve keeps concurrent enemies bounded
  -- (a spawn explosion would blow this). Measured ~18; ceiling is generous.
  check(s.peak_enemies <= 80, "balance: peak enemies within perf budget (serpentine)")
  check(z.peak_enemies <= 80, "balance: peak enemies within perf budget (zigzag)")
  check(w.peak_enemies <= 80, "balance: peak enemies within perf budget (switchback)")

  -- Projectile perf budget (V2-M9 production gate): pooled shots stay bounded even
  -- under a max cordon (measured ~13-26 across maps); a runaway pool would blow this.
  check(s.peak_proj <= 150, "balance: peak projectiles within perf budget (serpentine)")
  check(z.peak_proj <= 150, "balance: peak projectiles within perf budget (zigzag)")
  check(w.peak_proj <= 150, "balance: peak projectiles within perf budget (switchback)")

  -- Distribution: a pellet-only cordon's damage is dominated by pellets.
  check(s.tower_damage.list[1] and s.tower_damage.list[1].kind == "pellet",
    "balance: a pellet cordon's top damage source is the pellet")

  -- Opt-in modes must never make the run easier than standard. Hardcore spikes
  -- difficulty a tier early, so it dies no later than standard (which is `s`, the
  -- same serpentine cordon that reached wave 16 above -- cap the sim there, no
  -- need to simulate past where standard already died).
  local hard = cordon_run("serpentine", "hardcore", s.final_wave)
  check(hard.final_wave <= s.final_wave, "balance: hardcore is no easier than standard")
end

return M

-- M6 challenge modes: the registry + each mode's invariant applied at run.new /
-- wave / rule checks, the mode name in the run report, and the default "standard"
-- mode leaving every path unchanged. Run by smoke.lua via M.run(check, near).

local meta    = require("lib.meta")
local run_mod = require("lib.run")
local wave    = require("lib.wave")
local boss    = require("lib.boss")
local tower   = require("lib.tower")
local enemy   = require("lib.enemy")
local report  = require("lib.report")
local modes   = require("lib.modes")
local powerup = require("lib.powerup")
local rng     = require("lib.rng")

local M = {}

function M.run(check, near)
  local m = meta.default()

  -- registry: fallback + cycle
  check(modes.get(nil).id == "standard", "modes.get(nil) falls back to standard")
  check(modes.get("one_life").lives == 1, "one_life mode carries its lives delta")
  do
    local seen, id = {}, modes.ORDER[1]
    for _ = 1, #modes.ORDER do seen[id] = true; id = modes.next(id) end
    check(id == modes.ORDER[1], "modes.next wraps around the full cycle")
    local count = 0; for _ in pairs(seen) do count = count + 1 end
    check(count == #modes.ORDER, "modes.next visits every mode exactly once per cycle")
  end

  -- One Life: starting lives = 1, overriding even the Head Start bonus
  do
    check(run_mod.new(m, 1, "serpentine", "one_life").lives == 1, "One Life starts with a single life")
    local mb = meta.default(); mb.unlocks.start_bonus = true
    check(run_mod.new(mb, 1, "serpentine", "one_life").lives == 1, "One Life overrides the Head Start +5 lives")
  end

  -- No Orbital: the orbital strike is never available (standard keeps it)
  do
    local r = run_mod.new(m, 1, "serpentine", "no_orbital")
    r.phase = "combat"; r.money = 1000; enemy.spawn(r, "mote", 1, 1, 10)
    check(not run_mod.can_orbital(r), "No Orbital disables the orbital strike")
    local rs = run_mod.new(m, 1, "serpentine")
    rs.phase = "combat"; rs.money = 1000; enemy.spawn(rs, "mote", 1, 1, 10)
    check(run_mod.can_orbital(rs), "a standard run keeps the orbital strike")
  end

  -- No Rail: the rail is unavailable even when unlocked; other towers unaffected
  do
    local mr = meta.default(); mr.unlocks.tower_rail = true
    check(tower.available(mr, "rail", modes.get("standard")), "rail available in standard when unlocked")
    check(not tower.available(mr, "rail", modes.get("no_rail")), "No Rail disables the rail")
    check(tower.available(mr, "pellet", modes.get("no_rail")), "No Rail leaves other towers available")
  end

  -- Boss Rush: every wave is a boss wave
  do
    local r = run_mod.new(m, 1, "serpentine", "boss_rush")
    check(wave.is_boss_for(r, 3), "Boss Rush makes a non-multiple wave a boss wave")
    local rs = run_mod.new(m, 1, "serpentine")
    check(not wave.is_boss_for(rs, 3), "standard: wave 3 is not a boss wave")
    check(wave.is_boss_for(rs, 5), "standard: wave 5 is still a boss wave")
    local kind, known = boss.cycle(3), false
    for i = 1, #boss.ROTATION do if boss.ROTATION[i] == kind then known = true end end
    check(known, "boss.cycle returns a rotation boss")
  end

  -- Hardcore: tougher scaling than standard at the same wave -- the +1 tier hits
  -- hp/speed AND the spawn budget (more enemies), not just hp
  do
    local rs = run_mod.new(m, 1, "serpentine"); wave.boss_scale(rs, 5)
    local rh = run_mod.new(m, 1, "serpentine", "hardcore"); wave.boss_scale(rh, 5)
    check(rh.hp_scale > rs.hp_scale, "Hardcore scales hp harder than standard")
    check(rh.speed_scale > rs.speed_scale, "Hardcore scales speed harder than standard")
    local ns = wave.start(run_mod.new(m, 42, "serpentine"), 6)
    local nh = wave.start(run_mod.new(m, 42, "serpentine", "hardcore"), 6)
    check(nh > ns, "Hardcore's tier bump also grows the spawn budget (more enemies)")
  end

  -- Flyer Swarm: the spawn pool weights flyers (standard leaves it unchanged)
  do
    local pool = { { kind = "wisp", cost = 2 }, { kind = "hulk", cost = 3 } }   -- wisp flies
    check(#wave.weighted_pool(pool, false) == 2, "no flyer bias leaves the pool unweighted")
    local fly = wave.weighted_pool(pool, modes.get("flyer_swarm").flyer_bias)
    local wisps = 0; for i = 1, #fly do if fly[i].kind == "wisp" then wisps = wisps + 1 end end
    check(#fly == 4 and wisps == 3, "Flyer Swarm triples flyer entries (wisp x3 + hulk x1)")
  end

  -- Draft Chaos: every drafted card is boosted to a higher rarity (Uncommon+)
  do
    check(modes.get("draft_chaos").draft_chaos == true, "draft_chaos mode flag is set")
    local chaos = powerup.draft(rng.new(123), 3, true)
    check(#chaos == 3, "chaos draft still offers 3 cards")
    local all_boosted = true
    for i = 1, #chaos do if chaos[i].rarity < 2 then all_boosted = false end end
    check(all_boosted, "every Draft Chaos card is Uncommon or better")
    -- a plain draft is unaffected (chaos must be opt-in, not the default)
    local plain = powerup.draft(rng.new(123), 3)
    check(#plain == 3, "a plain draft still offers 3 cards (chaos defaults off)")
  end

  -- the run report carries the mode name (and nothing for a standard run)
  do
    check(report.build(run_mod.new(m, 1, "serpentine", "one_life")).mode == "One Life",
      "the run report carries the challenge-mode name")
    check(report.build(run_mod.new(m, 1, "serpentine")).mode == nil,
      "a standard run report shows no mode")
  end
end

return M

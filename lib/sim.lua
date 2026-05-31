-- Headless run driver for the balance lab (V2-M0). Replays a scripted build plan
-- through a real run -- the SAME lib systems the game scene drives, stepped at the
-- same fixed dt and starting each wave through run.begin_wave -- and returns the
-- structured metrics in lib/metrics. Deterministic: identical
-- (seed, map, mode, plan) always yields identical metrics, because the only
-- randomness is the run's seeded rng.
--
-- It is a measurement tool, not the game: it has no UI, applies build actions
-- directly during each build phase (a `place` still goes through tower.can_place,
-- so an unaffordable or on-path action is rejected and recorded rather than
-- thrown), and does not drive interactive route-mutation events (those are
-- between-wave player choices; a later milestone can extend the driver).

local meta_m   = require("lib.meta")
local run_mod  = require("lib.run")
local wave     = require("lib.wave")
local tower    = require("lib.tower")
local modifier = require("lib.modifier")
local powerup  = require("lib.powerup")
local loop     = require("lib.loop")
local metrics  = require("lib.metrics")

local M = {}

local DT = metrics.DT          -- the game's fixed combat step (1/60)
local FRAME_CAP = 30000        -- ~500s stall guard, matching the smoke runner

-- Resolve a plan action's `tower` reference to a placed tower by its STABLE id.
-- run.tower_seq assigns ids 1, 2, 3, ... in placement order, so `tower = 1` is
-- "the first tower placed" -- matching the roadmap's positional examples -- but,
-- unlike a live-array index, it can't be silently shifted onto the wrong tower by
-- a sell earlier in the same build phase. A sold tower's id simply resolves to nil.
function M.tower_by_id(run, id)
  local towers = run.towers
  for i = 1, #towers do
    if towers[i].id == id then return towers[i] end
  end
  return nil
end
local tower_by_id = M.tower_by_id

-- Apply one build-plan action during a build phase. Returns nil on success or a
-- short error string (recorded by the caller, never thrown -- a bad plan still
-- produces a full metrics table). A `tower` field is the stable tower id (see
-- tower_by_id), not a live-array position.
local function apply_action(run, a)
  if a.place then
    local p = a.place
    local ok, why = tower.can_place(run, p.x, p.y, p.kind)
    if not ok then
      return ("place %s @%d,%d: %s"):format(p.kind, p.x, p.y, tostring(why))
    end
    tower.place(run, p.x, p.y, p.kind)
  elseif a.upgrade then
    local t = tower_by_id(run, a.upgrade.tower)
    if not t then return "upgrade: no tower id " .. tostring(a.upgrade.tower) end
    if not modifier.buy_upgrade(run, t, a.upgrade.id) then
      return ("upgrade %s on id %s: rejected"):format(tostring(a.upgrade.id), tostring(a.upgrade.tower))
    end
  elseif a.module then
    local t = tower_by_id(run, a.module.tower)
    if not t then return "module: no tower id " .. tostring(a.module.tower) end
    if not modifier.socket_module(run, t, a.module.id) then
      return ("module %s on id %s: rejected"):format(tostring(a.module.id), tostring(a.module.tower))
    end
  elseif a.sell then
    local t = tower_by_id(run, a.sell.tower)
    if not t then return "sell: no tower id " .. tostring(a.sell.tower) end
    tower.sell(run, t)
  elseif a.powerup then
    -- balance abstraction: apply a chosen card directly (bypasses the random
    -- 3-card draft) so a plan can pin a build's modifiers deterministically.
    powerup.apply(run, { key = a.powerup.key, rarity = a.powerup.rarity or 1 })
  else
    return "unknown action"
  end
  return nil
end

-- opts: seed, map (layout name), mode (mode id), waves (default 20), plan (array
-- of build actions, each with a `wave` and one of place/upgrade/module/sell/
-- powerup), and optional meta / money / lives overrides for fixtures.
function M.run(opts)
  opts = opts or {}
  local mt = opts.meta or meta_m.default()
  local run = run_mod.new(mt, opts.seed or 1, opts.map, opts.mode)
  if opts.money then run.money = opts.money end
  if opts.lives then run.lives = opts.lives end
  local waves = opts.waves or 20

  -- bucket plan actions by the wave whose build phase they belong to
  local plan_by_wave = {}
  local plan = opts.plan or {}
  for i = 1, #plan do
    local w = plan[i].wave or 1
    local bucket = plan_by_wave[w]
    if not bucket then bucket = {}; plan_by_wave[w] = bucket end
    bucket[#bucket + 1] = plan[i]
  end

  local records, errors = {}, {}
  local survived, final_wave = true, 0

  for n = 1, waves do
    -- BUILD phase: apply this wave's scripted actions
    run.phase = "building"
    local actions = plan_by_wave[n]
    if actions then
      for i = 1, #actions do
        local err = apply_action(run, actions[i])
        if err then errors[#errors + 1] = { wave = n, err = err } end
      end
    end

    -- start the wave through the shared, presentation-free path
    local boss_wave = wave.is_boss_for(run, n)
    local leaks_before = run.leaked
    run_mod.begin_wave(run)
    final_wave = n

    -- COMBAT phase: step until the field clears or the run dies
    local frames, peak_e, peak_p = 0, 0, 0
    while true do
      frames = frames + 1
      local spawns_done = loop.step(run, DT)   -- canonical combat step (shared with the game)
      if run.enemies.n > peak_e then peak_e = run.enemies.n end
      if run.projectiles.n > peak_p then peak_p = run.projectiles.n end
      -- Death is decisive even on a frame the wave also clears: a fatal leak
      -- means the wave was NOT held, and the real game routes to gameover (the
      -- lives<=0 transition overrides the wave-clear one that same frame), so the
      -- wave counts as not-cleared (waves_cleared = final_wave - 1) here too.
      if run.lives <= 0 then survived = false; break end
      local cleared = run.enemies.n == 0 and (not run.boss or run.boss.dead)
      if spawns_done and cleared then break end
      if frames >= FRAME_CAP then
        errors[#errors + 1] = { wave = n, err = "stall: wave never cleared" }
        survived = false
        break
      end
    end

    records[#records + 1] = {
      wave = n, frames = frames, peak_enemies = peak_e, peak_proj = peak_p,
      leaks = run.leaked - leaks_before, money_after = run.money, boss = boss_wave,
    }
    if not survived then break end
  end

  local roll = metrics.rollup(records)
  return {
    survived = survived,
    final_wave = final_wave,
    waves_cleared = survived and final_wave or math.max(0, final_wave - 1),
    leaks = run.leaked,
    kills = run.kills,
    score = run.score,
    bosses_killed = run.bosses_killed,
    money = run.money,
    money_spent = run.money_spent,
    peak_enemies = roll.peak_enemies,
    peak_proj = roll.peak_proj,
    total_frames = roll.total_frames,
    money_curve = roll.money_curve,
    boss_seconds = roll.boss_seconds,
    tower_damage = metrics.tower_damage(run),
    -- the headless driver does not trigger interactive route-mutation events, so
    -- no towers are force-refunded; the field is here for forward-compatibility
    -- and so the baseline table can carry the column.
    route_refunds = 0,
    records = records,
    errors = errors,
    run = run,
  }
end

return M

-- Procedural wave director. Generates a spawn queue from (run rng, wave index)
-- with a budget that grows per wave, drip-spawns it on a pacing timer, and
-- scales enemy hp/speed. Every Nth wave is a boss wave (handled by the game
-- scene + lib/boss).

local C     = require("lib.const")
local enemy = require("lib.enemy")
local affix = require("lib.affix")
local rng   = require("lib.rng")

local M = {}

function M.is_boss(n)
  return n % C.BOSS_EVERY == 0
end

-- Boss-wave decision including the run's mode (Boss Rush makes every wave a boss).
function M.is_boss_for(run, n)
  return run.mode.boss_rush == true or M.is_boss(n)
end

-- Optionally weight a spawn pool toward flyers. `flyer_bias` is a boolean (the
-- Flyer Swarm mode OR a one-shot route-draft risk both set it). Returns the pool
-- unchanged when false. Public so it is unit-testable.
function M.weighted_pool(pool, flyer_bias)
  if not flyer_bias then return pool end
  local out = {}
  for i = 1, #pool do
    out[#out + 1] = pool[i]
    if enemy.DEFS[pool[i].kind].fly then          -- triple a flyer's pick weight
      out[#out + 1] = pool[i]
      out[#out + 1] = pool[i]
    end
  end
  return out
end

-- Enemy kinds unlocked by wave n, with their budget costs (deterministic order).
-- Public so the threat preview (lib/threat) can read the pool without duplicating
-- the unlock rule or consuming the run's rng.
function M.pool_for(n)
  local pool = {}
  for kind, def in pairs(enemy.DEFS) do
    if (def.unlock_wave or 1) <= n then
      pool[#pool + 1] = { kind = kind, cost = def.cost or 1 }
    end
  end
  table.sort(pool, function(a, b) return a.kind < b.kind end)
  return pool
end
local pool_for = M.pool_for

-- Tier index: 0 for waves 1..TIER_STEP, 1 for the next block, etc.
function M.tier(n)
  return math.floor((n - 1) / C.TIER_STEP)
end

-- Apply wave-n difficulty scaling to the run (shared by normal + boss waves).
-- Effective tier including the run's mode. Hardcore spikes one tier early, and
-- ALL three tier-driven stats (hp, budget, speed) use this so the bump is applied
-- consistently -- a "tier" means the whole tier, not just hp/speed.
local function eff_tier(run, n)
  return M.tier(n) + (run.mode.hardcore and 1 or 0)
end

-- Spawn budget for wave n (drives the enemy count), including the run's mode.
-- Public so the threat preview can size the incoming wave without consuming rng.
function M.budget_for(run, n)
  return C.BASE_BUDGET * (C.BUDGET_GROWTH ^ (n - 1)) * (C.BUDGET_TIER_MULT ^ eff_tier(run, n))
end

local function set_scaling(run, n)
  local tier = eff_tier(run, n)
  run.wave_index = n
  run.hp_scale = (C.HP_GROWTH ^ (n - 1)) * (C.HP_TIER_MULT ^ tier)
  run.speed_scale = (C.SPEED_GROWTH ^ (n - 1)) * (1 + tier * C.SPEED_TIER_ADD)
  run.spawn_interval = math.max(C.SPAWN_MIN, C.SPAWN_INTERVAL * (0.985 ^ (n - 1)))
end

local function mirrored_queue(run, n, pool)
  local flyer, ground = {}, {}
  for i = 1, #pool do
    if enemy.DEFS[pool[i].kind].fly then flyer[#flyer + 1] = pool[i].kind
    else ground[#ground + 1] = pool[i].kind end
  end
  if #flyer == 0 or #ground == 0 then return end
  local r = rng.derive(run.seed, n * 71 + 23)
  local q = run.spawn_queue
  for i = 1, q.n - 1, 2 do
    q[i] = ground[r:int(1, #ground)]
    q[i + 1] = flyer[r:int(1, #flyer)]
  end
end

-- Boss wave: scale difficulty and clear the spawn queue (the boss is spawned
-- by the game scene; phase-2 adds come from lib/boss).
function M.boss_scale(run, n)
  set_scaling(run, n)
  local q = run.spawn_queue
  q.n, q.i = 0, 0
end

-- Begin wave n: scale difficulty and build the spawn queue. Returns spawn count.
-- One-shot route-draft risks (V2-M2) are folded in here and then consumed, so a
-- Shortcut/Convergence budget spike or a Braid flyer flood affects exactly the
-- wave that follows the route choice.
function M.start(run, n)
  set_scaling(run, n)
  run.spawn_timer = 0.3

  -- a signed wave contract (V2-M3) can spike enemy HP and count for this wave;
  -- it persists until wave clear (so the reward can be granted), unlike route_mods.
  local ac = run.active_contract
  if ac and ac.risk.hp_mult then run.hp_scale = run.hp_scale * ac.risk.hp_mult end

  local q = run.spawn_queue
  q.n, q.i = 0, 0
  local rm = run.route_mods
  local budget = M.budget_for(run, n)
    * ((rm and rm.next_budget_mult) or 1)
    * ((ac and ac.risk.count_mult) or 1)
  local flyer_bias = (run.mode and run.mode.flyer_bias) or (rm and rm.next_flyer_bias) or false
  local pool = M.weighted_pool(pool_for(n), flyer_bias)
  while budget > 0 and q.n < 200 do
    local pick = pool[run.rng:int(1, #pool)]
    q.n = q.n + 1
    q[q.n] = pick.kind
    budget = budget - pick.cost
  end
  if run.wave_affix and run.wave_affix.mirror_pairs then mirrored_queue(run, n, pool) end
  run.wave_shield = (rm and rm.next_shield) or 0                     -- Prism shield buff (M2)
  if rm then rm.next_budget_mult, rm.next_flyer_bias, rm.next_shield = 1, false, 0 end   -- consume once
  return q.n
end

-- Drip-spawn from the queue. Returns true once the queue is exhausted.
function M.update(run, dt)
  local q = run.spawn_queue
  if q.i >= q.n then return true end
  run.spawn_timer = run.spawn_timer - dt
  if run.spawn_timer <= 0 then
    q.i = q.i + 1
    local e = enemy.spawn(run, q[q.i], run.hp_scale, run.speed_scale, 0)
    affix.apply_spawn(run, e, q.i, q.n)        -- spawn-time affix (derived fields) (M5)
    if run.wave_shield and run.wave_shield > 0 then   -- Prism route card's shield buff (M2)
      e.shield_max = e.shield_max + run.wave_shield
      e.shield = e.shield + run.wave_shield
    end
    run.spawn_timer = run.spawn_interval
  end
  return q.i >= q.n
end

return M

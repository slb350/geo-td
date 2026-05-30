-- Procedural wave director. Generates a spawn queue from (run rng, wave index)
-- with a budget that grows per wave, drip-spawns it on a pacing timer, and
-- scales enemy hp/speed. Every Nth wave is a boss wave (handled by the game
-- scene + lib/boss).

local C     = require("lib.const")
local enemy = require("lib.enemy")

local M = {}

function M.is_boss(n)
  return n % C.BOSS_EVERY == 0
end

-- Enemy kinds unlocked by wave n, with their budget costs (deterministic order).
local function pool_for(n)
  local pool = {}
  for kind, def in pairs(enemy.DEFS) do
    if (def.unlock_wave or 1) <= n then
      pool[#pool + 1] = { kind = kind, cost = def.cost or 1 }
    end
  end
  table.sort(pool, function(a, b) return a.kind < b.kind end)
  return pool
end

-- Tier index: 0 for waves 1..TIER_STEP, 1 for the next block, etc.
function M.tier(n)
  return math.floor((n - 1) / C.TIER_STEP)
end

-- Apply wave-n difficulty scaling to the run (shared by normal + boss waves).
local function set_scaling(run, n)
  local tier = M.tier(n)
  run.wave_index = n
  run.hp_scale = (C.HP_GROWTH ^ (n - 1)) * (C.HP_TIER_MULT ^ tier)
  run.speed_scale = (C.SPEED_GROWTH ^ (n - 1)) * (1 + tier * C.SPEED_TIER_ADD)
  run.spawn_interval = math.max(C.SPAWN_MIN, C.SPAWN_INTERVAL * (0.985 ^ (n - 1)))
end

-- Boss wave: scale difficulty and clear the spawn queue (the boss is spawned
-- by the game scene; phase-2 adds come from lib/boss).
function M.boss_scale(run, n)
  set_scaling(run, n)
  local q = run.spawn_queue
  q.n, q.i = 0, 0
end

-- Begin wave n: scale difficulty and build the spawn queue. Returns spawn count.
function M.start(run, n)
  set_scaling(run, n)
  run.spawn_timer = 0.3

  local q = run.spawn_queue
  q.n, q.i = 0, 0
  local budget = C.BASE_BUDGET * (C.BUDGET_GROWTH ^ (n - 1)) * (C.BUDGET_TIER_MULT ^ M.tier(n))
  local pool = pool_for(n)
  while budget > 0 and q.n < 200 do
    local pick = pool[run.rng:int(1, #pool)]
    q.n = q.n + 1
    q[q.n] = pick.kind
    budget = budget - pick.cost
  end
  return q.n
end

-- Drip-spawn from the queue. Returns true once the queue is exhausted.
function M.update(run, dt)
  local q = run.spawn_queue
  if q.i >= q.n then return true end
  run.spawn_timer = run.spawn_timer - dt
  if run.spawn_timer <= 0 then
    q.i = q.i + 1
    enemy.spawn(run, q[q.i], run.hp_scale, run.speed_scale, 0)
    run.spawn_timer = run.spawn_interval
  end
  return q.i >= q.n
end

return M

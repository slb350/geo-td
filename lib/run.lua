-- Builds a fresh run: economy, modifiers, entity pools, and the path. Applies
-- meta unlocks (start bonus) at creation. A "run" is the whole roguelike climb;
-- it lives at State.run and is nil between runs.

local C     = require("lib.const")
local path  = require("lib.path")
local rng   = require("lib.rng")
local fx    = require("lib.fx")
local maps  = require("lib.maps")
local enemy = require("lib.enemy")
local modes = require("lib.modes")
local wave  = require("lib.wave")
local boss  = require("lib.boss")
local resource = require("lib.resource")
local contracts = require("lib.contracts")
local affix = require("lib.affix")

local M = {}

function M.new(meta, seed, path_name, mode_id)
  local mode = modes.get(mode_id)
  local money, lives = C.START_MONEY, C.START_LIVES
  if meta.unlocks.start_bonus then
    money = money + 50
    lives = lives + 5
  end
  if mode.lives then lives = mode.lives end   -- a challenge mode may override (e.g. One Life)
  fx.clear()
  -- an explicit map (map-select / tests) if it names a real layout, else a
  -- seed-derived fallback so any run still gets a valid map.
  local key = (path_name and maps.exists(path_name)) and path_name or maps.pick(seed)
  local layout = maps.get(key)
  local run = {
    seed = seed,
    rng = rng.new(seed),
    path = path.build(layout.nodes),
    path_name = key,
    map_name = layout.name,
    mode = mode,           -- challenge-mode config deltas (M6); standard = no-op
    wave_index = 0,
    phase = "building",  -- building | combat | upgrade
    money = money,
    lives = lives,
    score = 0,
    kills = 0,
    leaked = 0,            -- enemies + bosses that reached the core (report stat)
    money_spent = 0,       -- gross spend on towers + orbital strikes (report stat)
    bursting = false,      -- re-entrancy guard for the flyer-death burst (M2)
    hp_scale = 1,
    speed_scale = 1,
    towers = {},
    tower_seq = 0,         -- monotonic id source for placed towers
    tower_stats = {},      -- [id] = { kind, damage } -- applied damage per tower
    enemies = { n = 0 },
    projectiles = { n = 0 },
    rings = { n = 0 },     -- lingering splash damage zones (M2 "Aftershock" card)
    boss = nil,
    bosses_killed = 0,
    arena_kills = 0,       -- boss-arena objects destroyed (M6 report stat)
    final_boss_reached = false,  -- the wave-25 Lattice was reached (M6)
    spawn_queue = { n = 0, i = 0 },
    spawn_timer = 0,
    spawn_interval = C.SPAWN_INTERVAL,
    powerups = {},
    -- One-shot route-draft risks (V2-M2), consumed by the next wave.start and
    -- then reset.
    route_mods = { next_budget_mult = 1, next_flyer_bias = false, resources = {} },
    -- Resource + contract economy (V2-M3). charge is the second in-run currency
    -- (Drills fill it, Discharge spends it). resource_nodes are seeded below.
    -- active_contract is the signed wave contract (or nil); its risk hits the next
    -- wave and its reward lands on wave clear. bank_shards convert to meta at
    -- run end; module_discount is a one-shot socket discount; no_sell gates selling.
    charge = 0,
    resource_nodes = {},
    active_contract = nil,
    contract_history = {},
    bank_shards = 0,
    module_discount = 0,
    no_sell = false,
    resonance_dirty = true,    -- recompute tower resonance on the next touch (M4)
    -- Enemy affixes (V2-M5). wave_affix is the current wave's resolved affix row
    -- (or nil); affix_history lists ids for the report; no_affixes lets the balance
    -- sim opt out; the null-field timer suppresses resonance for its duration.
    wave_affix = nil,
    affix_history = {},
    affix_timer = 0,
    affix_null_active = false,
    no_affixes = false,
    mods = {
      dmg_mult = 1, rate_mult = 1, range_mult = 1, bounty_mult = 1, cost_mult = 1,
      proj_mult = 1, splash_mult = 1, crit_chance = 0, interest = 0, life_per_wave = 0,
      -- behavior draft cards (M2): pierce/ricochet are extra-hit counts; brittle,
      -- ring, flyer_burst are scaled fractions. 0 = card not taken.
      pierce = 0, ricochet = 0, brittle = 0, ring = 0, flyer_burst = 0,
    },
  }
  resource.spawn_nodes(run)
  return run
end

-- Advance the run into the next wave's combat: apply start-of-wave economy
-- (interest, life-per-wave) then spawn the wave or its boss. This is the
-- presentation-free core of the game scene's start_wave -- the scene wraps it
-- with sfx/audio/UI, and the headless sim (lib/sim) drives it directly, so the
-- two can never drift on the rules that affect balance. Returns the wave number.
function M.begin_wave(run)
  local n = run.wave_index + 1
  run.phase = "combat"
  run.sim_acc = 0            -- fresh fixed-timestep accumulator for this wave (M1)
  local mods = run.mods
  if mods.interest > 0 then
    run.money = run.money + math.floor(run.money * mods.interest)
  end
  if mods.life_per_wave > 0 then
    run.lives = run.lives + mods.life_per_wave
  end
  if wave.is_boss_for(run, n) then
    wave.boss_scale(run, n)
    local kind = run.mode.boss_rush and boss.cycle(n) or boss.for_wave(n)
    boss.spawn(run, kind, run.hp_scale)
  else
    run.boss = nil
    wave.start(run, n)
    contracts.arm(run)        -- blackout / no-sell, once the wave + towers are set
  end
  affix.choose(run, n)        -- pick/clear this wave's affix (nil on boss waves) (M5)
  return n
end

-- Credit applied damage to a tower's run-level stat entry (seeded at placement,
-- kept through a sell). Shared by projectile hits and splash rings so the M1
-- run-report attribution stays in one place. A nil/no-op amount credits nothing.
function M.credit_damage(run, tower_id, applied)
  if not applied or applied <= 0 or not tower_id then return end
  local s = run.tower_stats[tower_id]
  if s then s.damage = s.damage + applied end
end

function M.alive(run)
  return run.lives > 0
end

-- True when the field is clear of enemies and the boss (wave fully resolved).
function M.field_clear(run)
  if run.enemies.n > 0 then return false end
  if run.boss and not run.boss.dead then return false end
  return true
end

-- Can the next wave be "called early"? Only mid-combat, once the current wave's
-- spawn queue is drained, with a small handful of stragglers left and no live
-- boss, and -- crucially -- with NO route event due before the next wave (a route
-- swap needs a clear field, so overlapping waves would be unsafe). The route check
-- mirrors pathmut.pending_for's cadence inline, because run can't require pathmut
-- (pathmut -> tower -> projectile -> run would cycle); both read the same
-- C.ROUTE_EVENT_EVERY + wave.is_boss_for sources.
function M.can_call_early(run)
  if run.phase ~= "combat" then return false end
  local q = run.spawn_queue
  if q.i < q.n then return false end                       -- still spawning this wave
  if run.enemies.n == 0 or run.enemies.n > C.EARLY_CALL_MAX then return false end
  if run.boss and not run.boss.dead then return false end  -- finish the boss first
  local nxt = run.wave_index + 1
  if nxt % C.ROUTE_EVENT_EVERY == 0 and not wave.is_boss_for(run, nxt) then
    return false                                            -- a route event must intervene first
  end
  return true
end

-- Start the next wave early, overlapping the current stragglers, for a money
-- bonus. A no-op unless can_call_early. The overlapped pair resolves into a
-- single between-wave break, so the bonus also stands in for the skipped draft.
function M.call_early(run)
  if not M.can_call_early(run) then return false end
  run.money = run.money + C.EARLY_CALL_BONUS
  M.begin_wave(run)
  return true
end

-- Orbital strike availability: only mid-combat, with the cost on hand, and only
-- when there is actually something on the field to nuke (so the button greys
-- out rather than burning $500 on an empty screen).
function M.can_orbital(run)
  if run.mode.no_orbital then return false end   -- "No Orbital" challenge mode
  return run.phase == "combat" and run.money >= C.ORBITAL_COST and run.enemies.n > 0
end

-- Spend ORBITAL_COST to vaporize every enemy currently on the field. This is a
-- pure clear -- no bounty, no score, and no splitter children -- so the screen
-- truly empties and the cost stays a real money sink. The boss is in run.boss,
-- not run.enemies, so it is untouched.
function M.orbital_strike(run)
  if not M.can_orbital(run) then return false end
  run.money = run.money - C.ORBITAL_COST
  run.money_spent = run.money_spent + C.ORBITAL_COST
  local list = run.enemies
  for i = 1, list.n do
    enemy.vaporize(list[i])
  end
  return true
end

-- Discharge availability: mid-combat, with enough charge banked, and something on
-- the field to hit. The charge economy's active sink (separate from money/orbital).
function M.can_discharge(run)
  return run.phase == "combat" and run.charge >= C.DISCHARGE_MIN
    and (run.enemies.n > 0 or (run.boss and not run.boss.dead))
end

-- Spend ALL banked charge for a field-wide damage burst: every enemy and the boss
-- take charge * DISCHARGE_FACTOR. Unlike the orbital, this is real damage (kills
-- pay bounty + split), so a bigger bank hits harder. Returns true if it fired.
function M.discharge(run)
  if not M.can_discharge(run) then return false end
  local dmg = run.charge * C.DISCHARGE_FACTOR
  run.charge = 0
  local list = run.enemies
  local n = list.n                       -- snapshot: a kill may split-spawn
  for i = 1, n do
    if not list[i].dead then enemy.damage(run, list[i], dmg) end
  end
  if run.boss and not run.boss.dead then boss.hurt(run, dmg) end
  return true
end

return M

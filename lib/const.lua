-- Shared constants: screen geometry, HUD layout, and gameplay tuning.
-- Pure data, no engine state. Tweak freely during balancing.

local C = {}

-- Screen
C.GAME_W = 480
C.GAME_H = 270

-- Play field (left) vs HUD sidebar (right)
C.HUD_W   = 108
C.HUD_X   = C.GAME_W - C.HUD_W   -- 372
C.FIELD_W = C.HUD_X              -- play field is [0, 372)
C.FIELD_H = C.GAME_H

-- Path & placement
C.PATH_WIDTH   = 10   -- drawn thickness of the route
C.PLACE_MARGIN = 13   -- min distance (px) from path centerline to allow a tower
C.TOWER_R      = 7    -- tower footprint radius (overlap checks + drawing)

-- Economy
C.START_MONEY  = 150
C.START_LIVES  = 20
C.SELL_REFUND  = 0.6

-- Orbital strike: a pricey panic button that vaporizes every enemy on the field
-- (bosses are immune). A deliberate late-game money sink for flyer swarms.
C.ORBITAL_COST = 500

-- Waves / difficulty scaling
C.BOSS_EVERY      = 5      -- every Nth wave is a boss
C.FINAL_BOSS_EVERY = 25    -- every Nth wave is the final-act boss (The Lattice) (M6)
C.BASE_BUDGET     = 6      -- enemy "spawn budget" at wave 1
C.BUDGET_GROWTH   = 1.18   -- budget *= this per wave
C.HP_GROWTH       = 1.15   -- enemy hp scales by wave
C.SPEED_GROWTH    = 1.012  -- enemy speed creeps up per wave
C.SPAWN_INTERVAL  = 0.65   -- base seconds between spawns
C.SPAWN_MIN       = 0.18   -- floor on spawn interval at high waves
C.BOSS_SPLIT_HP_MULT = 0.6 -- default hp scale for boss death-spawned adds
C.BOSS_ADD_HP_MULT   = 0.6 -- hp scale for boss continuous / phase-2 adds

-- Compounding difficulty tiers: every TIER_STEP waves the multipliers stack on
-- top of the per-wave growth, so deep runs spike hard. HP carries most of the
-- load (cheaper than raw enemy count for perf).
C.TIER_STEP        = 10
C.HP_TIER_MULT     = 2.105  -- enemy hp x this per tier
C.BUDGET_TIER_MULT = 1.2125 -- enemy count budget x this per tier
C.SPEED_TIER_ADD   = 0.051  -- +5.1% enemy speed per tier

-- Meta progression
C.META_PER_WAVE = 2        -- meta-currency awarded per wave reached

-- Behavior draft cards (M2). Pierce/ricochet "chain" a shot to extra targets;
-- ring is a lingering splash zone; flyer_burst is an on-death AoE for flyers.
C.CHAIN_RANGE    = 60      -- max px a pierce/ricochet shot hops to its next target
C.RING_TICKS     = 3       -- damage ticks a splash ring deals before it fades
C.RING_INTERVAL  = 0.2     -- seconds between ring ticks
C.FLYER_BURST_R  = 42      -- radius (px) of a flyer's on-death burst

-- Per-tower modifiers (M3). Upgrades are leveled numeric lines (data in
-- data/upgrades.json); a geometry module is a one-per-tower qualitative socket.
C.MODULE_COST    = 60      -- in-run cost to socket a geometry module on a tower

-- Boss telegraphs (M5): the warning window shown in the last N seconds before a
-- shockwave / invuln / add-spawn fires. Purely a lead-in -- the effect still
-- fires on the boss's existing cadence, so balance is unchanged.
C.BOSS_TELEGRAPH = 0.9

-- Path-mutation events (M7): on maps with route variants, a between-wave route
-- choice is offered before every Nth wave (skipping boss waves). The swap only
-- happens with the field clear, so the single-polyline scalar-distance model is
-- preserved (no live enemy's `d` is ever remapped).
C.ROUTE_EVENT_EVERY = 4

-- Fixed combat timestep (V2-M1). The game advances combat in fixed C.SIM_DT
-- increments via an accumulator, decoupled from the variable render dt (Usagi's
-- _update dt is real frame time, clamped to a 30fps floor). This makes combat
-- deterministic and frame-rate-independent, and makes the 1x/2x speed toggle
-- exactly a step-count multiplier. The headless sim uses the same step (via
-- lib/metrics.DT), so balance numbers match real play. MAX_SIM_STEPS caps the
-- per-frame catch-up so a frame-time spike can't spiral.
C.SIM_DT        = 1 / 60
C.MAX_SIM_STEPS = 8

-- Tactical UX (V2-M1). "Call next wave early": once the current wave's spawn
-- queue is drained and only a handful of stragglers remain, the player may start
-- the next wave early (overlapping them) for a small money bonus -- a reward for
-- the risk and for skipping this wave's upgrade draft.
C.EARLY_CALL_MAX   = 4   -- max stragglers left for an early call to be offered
C.EARLY_CALL_BONUS = 20  -- money granted for calling the next wave early

-- Resource nodes + charge (V2-M3). A Drill (support tower) within DRILL_RANGE of a
-- resource prism generates charge during combat. Charge fuels the Discharge
-- ability: spend it all for a field-wide damage burst (charge * DISCHARGE_FACTOR).
C.RESOURCE_NODES   = 2     -- prisms seeded per run
C.DRILL_RANGE      = 32    -- max px from a prism for a Drill to extract
C.DRILL_RATE       = 6     -- charge per second per active Drill (combat only)
C.DISCHARGE_MIN    = 24    -- minimum charge to fire a Discharge
C.DISCHARGE_FACTOR = 0.9   -- damage dealt to every enemy/boss = charge spent * this

-- Enemy affixes (V2-M5). From a per-affix min_wave a qualifying (non-boss) wave
-- may carry one affix, picked by a derived roll (doesn't consume the run rng, so
-- the spawn SEQUENCE is unchanged -- only the affix effects differ; the balance
-- sim disables affixes for stable baselines). Affixes apply DERIVED enemy fields
-- or wave-level flags, never base-def mutation.
C.AFFIX_CHANCE = 0.7    -- chance a qualifying wave actually gets an affix

-- Wave contracts (V2-M3). An optional risk/reward signed before some waves (never
-- a boss wave). The risk applies to that one wave; the reward is granted only on
-- wave clear (not on death).
C.CONTRACT_EVERY   = 3     -- a contract is offered before every Nth wave
C.BANK_SHARD_VALUE = 5     -- meta-currency per bank shard earned from contracts

return C

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

-- Waves / difficulty scaling
C.BOSS_EVERY      = 5      -- every Nth wave is a boss
C.BASE_BUDGET     = 6      -- enemy "spawn budget" at wave 1
C.BUDGET_GROWTH   = 1.18   -- budget *= this per wave
C.HP_GROWTH       = 1.15   -- enemy hp scales by wave
C.SPEED_GROWTH    = 1.012  -- enemy speed creeps up per wave
C.SPAWN_INTERVAL  = 0.65   -- base seconds between spawns
C.SPAWN_MIN       = 0.18   -- floor on spawn interval at high waves

-- Compounding difficulty tiers: every TIER_STEP waves the multipliers stack on
-- top of the per-wave growth, so deep runs spike hard. HP carries most of the
-- load (cheaper than raw enemy count for perf).
C.TIER_STEP        = 10
C.HP_TIER_MULT     = 2.3    -- enemy hp x this per tier
C.BUDGET_TIER_MULT = 1.25   -- enemy count budget x this per tier
C.SPEED_TIER_ADD   = 0.06   -- +6% enemy speed per tier

-- Meta progression
C.META_PER_WAVE = 2        -- meta-currency awarded per wave reached

return C

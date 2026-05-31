-- Daily challenge (V2-M7): a deterministic local daily generated purely from the
-- date -- no online dependency. The day index keys a derived PRNG (rng.derive, the
-- same main-rng-safe primitive the route/contract drafts use) that picks the map,
-- a curated challenge mode, and the run seed. Same day -> same challenge anywhere;
-- a different day -> a different one. Verifiable from seed/map/mode in the report.

local rng   = require("lib.rng")
local maps  = require("lib.maps")

local M = {}

-- Curated mode pool for dailies: the standard climb plus the modes that change the
-- texture of a run without being purely punishing. (Order is stable so the pick is
-- reproducible; ids must exist in lib/modes.)
M.MODES = { "standard", "hardcore", "flyer_swarm", "no_orbital", "boss_rush", "draft_chaos" }

-- Whole-day index from the wall clock (UTC days since the epoch). Tests pass an
-- explicit day to for_day, so this is the only impure surface and it is trivial.
function M.today()
  return math.floor((os.time and os.time() or 0) / 86400)
end

-- The deterministic daily challenge for a given whole-day index.
function M.for_day(day)
  local r = rng.derive(day, 0xDA17)        -- warmed, day-keyed PRNG
  local map  = maps.ORDER[r:int(1, #maps.ORDER)]
  local mode = M.MODES[r:int(1, #M.MODES)]
  local seed = day * 100003 + r:int(1, 1000000)
  return { day = day, map = map, mode = mode, seed = seed }
end

return M

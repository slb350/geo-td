-- Combat simulation speed (V2-M1). Speed is a SUBSTEP COUNT, not a dt scale: at
-- 2x the game runs the canonical loop.step twice per frame with the same fixed
-- dt, so the simulation stays bit-for-bit deterministic (advancing the same total
-- number of fixed steps yields the same state regardless of speed). Only combat
-- is sped up -- input, UI, music, and fx always run once per real frame.

local M = {}

-- Allowed speeds, in cycle order. Room to add 3x/4x later without touching callers.
M.VALUES = { 1, 2 }

-- Coerce any value to a valid speed (default 1) -- guards a live-reloaded or
-- save-restored speed that is no longer in VALUES.
function M.clamp(v)
  for i = 1, #M.VALUES do
    if M.VALUES[i] == v then return v end
  end
  return M.VALUES[1]
end

-- The next speed in the ring (1x -> 2x -> 1x).
function M.cycle(v)
  for i = 1, #M.VALUES do
    if M.VALUES[i] == v then return M.VALUES[i % #M.VALUES + 1] end
  end
  return M.VALUES[1]
end

-- Display label, e.g. "2x".
function M.label(v)
  return M.clamp(v) .. "x"
end

return M

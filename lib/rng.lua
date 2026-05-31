-- Tiny seeded PRNG (Park-Miller minimal standard) for reproducible runs.
-- Kept separate from Lua's global math.random so seeding wave generation
-- never disturbs incidental randomness elsewhere.

local M = {}
M.__index = M

local MODULUS = 2147483647 -- 2^31 - 1

function M.new(seed)
  seed = math.floor(seed or 1) % MODULUS
  if seed <= 0 then seed = seed + MODULUS - 1 end
  return setmetatable({ state = seed }, M)
end

-- Float in [0, 1).
function M:next()
  self.state = (self.state * 16807) % MODULUS
  return (self.state - 1) / (MODULUS - 1)
end

-- Float in [lo, hi).
function M:range(lo, hi)
  return lo + (hi - lo) * self:next()
end

-- Integer in [lo, hi] inclusive.
function M:int(lo, hi)
  return lo + math.floor(self:next() * (hi - lo + 1))
end

-- Pick a random element from a 1..n array.
function M:pick(arr)
  return arr[self:int(1, #arr)]
end

-- True with probability p.
function M:chance(p)
  return self:next() < p
end

-- A fresh local rng derived from a base seed + an extra mixer, warmed past the
-- Park-Miller small-seed correlation (the first output is tiny for small seeds).
-- For deterministic one-shot lotteries (e.g. the route-draft shuffle) that must
-- NOT consume a run's main rng and so can't perturb later wave generation.
function M.derive(base, extra)
  local r = M.new(base * 131 + (extra or 0) + 17)
  r:next(); r:next(); r:next()
  return r
end

return M

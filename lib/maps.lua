-- Map catalogue + difficulty / unlock order. Single source of truth for the
-- path layouts (loaded from data/paths.json) and the order maps are ranked and
-- unlocked in. ORDER is least -> most difficult, ranked empirically (a uniform
-- tower cordon, leaks summed over a fixed wave span across several seeds):
-- zigzag is the most forgiving, switchback demands the most coverage. Clearing
-- wave >= UNLOCK_WAVE on a map unlocks the next one in ORDER.

local M = {}

local DATA = usagi.read_json("paths.json")

M.ORDER = { "zigzag", "spiral", "serpentine", "chicane", "switchback" }
M.first = M.ORDER[1]
M.UNLOCK_WAVE = 20

function M.get(name) return DATA.layouts[name] end
function M.exists(name) return DATA.layouts[name] ~= nil end

function M.index(name)
  for i = 1, #M.ORDER do
    if M.ORDER[i] == name then return i end
  end
  return nil
end

-- The next (harder) map after `name`, or nil if it is already the last.
function M.next(name)
  local i = M.index(name)
  return i and M.ORDER[i + 1] or nil
end

-- Deterministic fallback pick from a seed (when no map is explicitly chosen).
function M.pick(seed)
  return M.ORDER[(math.floor(seed or 0) % #M.ORDER) + 1]
end

return M

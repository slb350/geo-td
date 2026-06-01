-- Share codes (V2-M8): a deterministic, human-readable ASCII string that captures
-- a run configuration (seed + map + mode + optional tag) so a specific run -- a
-- daily, a fixed-seed challenge -- can be recreated or verified offline. No online
-- service. Format (fields joined by '-'):
--
--   GTD2-1-<SEED36>-<MAP>-<MODE>[-<TAG>]
--
-- GTD2 = game/version marker, 1 = share schema version, SEED36 = the run seed in
-- base-36 (uppercase, compact), MAP/MODE = the uppercased layout/mode ids (ids use
-- '_' not '-', so they never collide with the field separator), TAG = an optional
-- free marker (e.g. "D20235" for a daily's day index). decode round-trips encode
-- and fails GRACEFULLY (nil, reason) on a bad marker/schema/seed/map/mode.

local maps = require("lib.maps")
local modes = require("lib.modes")

local M = {}

M.MARKER = "GTD2"
M.SCHEMA = 1

local DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

local function to36(n)
  n = math.floor(n or 0)
  if n <= 0 then return "0" end
  local s = ""
  while n > 0 do
    local d = n % 36
    s = DIGITS:sub(d + 1, d + 1) .. s -- prepend (seeds are <= ~7 digits)
    n = math.floor(n / 36)
  end
  return s
end

local function from36(s)
  if type(s) ~= "string" or #s == 0 then return nil end
  local n = 0
  for i = 1, #s do
    local d = DIGITS:find(s:sub(i, i), 1, true)
    if not d then return nil end
    n = n * 36 + (d - 1)
  end
  return n
end

local function split_dash(str)
  local out = {}
  for piece in (str .. "-"):gmatch("([^%-]*)%-") do
    out[#out + 1] = piece
  end
  return out
end

-- A mode id is valid iff modes.get round-trips it (get falls back to standard for
-- an unknown id, so a mismatch means the id was not real).
local function known_mode(id)
  return modes.get(id).id == id
end

-- Encode a run config -> share code. cfg = { seed, map, mode?, tag? }.
function M.encode(cfg)
  local parts = {
    M.MARKER,
    tostring(M.SCHEMA),
    to36(cfg.seed),
    string.upper(cfg.map),
    string.upper(cfg.mode or modes.DEFAULT),
  }
  if cfg.tag then parts[#parts + 1] = string.upper(cfg.tag) end
  return table.concat(parts, "-")
end

-- Decode a share code -> cfg { seed, map, mode, tag? }, or nil + reason.
function M.decode(str)
  if type(str) ~= "string" then return nil, "not a string" end
  local f = split_dash(string.upper(str))
  if #f < 5 then return nil, "too few fields" end
  if f[1] ~= M.MARKER then return nil, "bad marker" end
  if tonumber(f[2]) ~= M.SCHEMA then return nil, "unsupported schema" end
  local seed = from36(f[3])
  if not seed then return nil, "bad seed" end
  local map = string.lower(f[4])
  if not maps.exists(map) then return nil, "unknown map" end
  local mode = string.lower(f[5])
  if not known_mode(mode) then return nil, "unknown mode" end
  return { seed = seed, map = map, mode = mode, tag = f[6] }
end

return M

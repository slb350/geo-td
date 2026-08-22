-- Engine-config contract (usagi 1.3.0+): config lives in main.lua frontmatter,
-- not the deprecated `_config()` (see main.lua's header for why not usagi.conf).
--
-- The engine parses that block before any Lua runs, so it can't `require` a
-- constant -- which costs the old guarantee that the resolution was
-- single-sourced from lib/const. These checks restore it from the other side:
-- parse main.lua as the engine does, then assert it agrees with lib/const and
-- pins `game_id` (the save-data key backing every live player's save).

local C = require("lib.const")

local M = {}

-- Parse main.lua's frontmatter the way the engine does (format spec: USAGI.md
-- section "Configuration" -- re-verify this mirrors it after a `usagi update`):
-- read the leading comment
-- block until the first line that is not a `--` comment, keeping only the lines
-- that carry a `key = value` (comment lines without `=` are prose and ignored).
local function read_frontmatter(src)
  local out, n = {}, 0
  -- The trailing sentinel makes the last line match even without a final
  -- newline. Capture-then-newline rather than `gmatch("[^\n]*")`, which yields
  -- an empty string between lines in Lua 5.1 and would end the block at line 1.
  for line in (src .. "\n"):gmatch("([^\n]*)\n") do
    line = line:gsub("\r$", "")
    if not line:match("^%-%-") then break end -- first non-comment line ends it
    local k, v = line:match("^%-%-%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k then
      out[k] = v
      n = n + 1
    end
  end
  return out, n
end

function M.run(check, _near)
  local fh = io.open("main.lua", "r")
  check(fh ~= nil, "main.lua is readable")
  if not fh then return end
  local src = fh:read("*a")
  fh:close()

  local conf, n = read_frontmatter(src)

  -- The save key. Changing this orphans every existing player's save.
  check(conf.game_id == "com.brandon.usagigeotd", "frontmatter pins the live save-data game_id")
  check(conf.name == "usagi-geo-td", "frontmatter sets the game name")

  -- The drift guard that removing `_config()` would otherwise have cost us.
  check(tonumber(conf.game_width) == C.GAME_W, "frontmatter game_width matches C.GAME_W")
  check(tonumber(conf.game_height) == C.GAME_H, "frontmatter game_height matches C.GAME_H")

  -- `gif_length` (seconds) sets F9 capture length for trailer clips. Unknown and
  -- malformed keys are BOTH silent in the engine, so this suite is the only
  -- place a typo'd key surfaces.
  check(tonumber(conf.gif_length) == 12, "frontmatter sets the F9 gif capture length")

  -- Pin the exact key SET, not just a count: a prose line that happens to carry
  -- an `=` would otherwise be absorbed as live config with no engine warning.
  local EXPECTED = { name = true, game_id = true, game_width = true, game_height = true, gif_length = true }
  local extra = {}
  for k in pairs(conf) do
    if not EXPECTED[k] then extra[#extra + 1] = k end
  end
  table.sort(extra)
  check(#extra == 0, "frontmatter declares no unexpected config keys, found: " .. table.concat(extra, ","))
  local missing = {}
  for k in pairs(EXPECTED) do
    if conf[k] == nil then missing[#missing + 1] = k end
  end
  table.sort(missing)
  check(#missing == 0, "frontmatter declares every expected config key, missing: " .. table.concat(missing, ","))
  check(n == 5, "frontmatter block declares exactly 5 config keys, got " .. n)

  -- `_config()` is deprecated upstream; the engine logs a warning when present,
  -- and it silently loses to frontmatter anyway.
  check(not src:match("function%s+_config"), "main.lua defines no deprecated _config()")

  -- A usagi.conf would be a second source for the same fields -- it loses to
  -- frontmatter (the engine warns about the double-set) and, worse, it is the
  -- source that does NOT survive `usagi export`.
  local conf_file = io.open("usagi.conf", "r")
  if conf_file then conf_file:close() end
  check(conf_file == nil, "no usagi.conf shadowing the frontmatter (export drops it)")
end

return M

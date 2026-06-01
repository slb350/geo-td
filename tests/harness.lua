-- Headless test harness: fakes the Usagi engine globals (gfx/usagi/effect/sfx/
-- music) with a tiny JSON reader, so the real lib/* logic can run under plain
-- LuaJIT with no window or assets. Required first by tests/smoke.lua (before any
-- lib module loads, since modules read JSON at require time).
--
-- gfx draw calls are recorded so layout tests can assert geometry: reset_gfx()
-- swaps the record table and gfx_calls() returns it. The stubs, reset, and
-- accessor all close over the one `gfx_calls` upvalue, so a reset is visible to
-- the stubs immediately.

local M = {}

-- ---------------------------------------------------------------- JSON reader
local function parse_json(str)
  local pos = 1
  local value
  local function ws()
    while pos <= #str do
      local c = str:sub(pos, pos)
      if c == " " or c == "\n" or c == "\t" or c == "\r" then
        pos = pos + 1
      else
        break
      end
    end
  end
  local function str_val()
    pos = pos + 1
    local buf = {}
    while pos <= #str do
      local c = str:sub(pos, pos)
      if c == '"' then
        pos = pos + 1
        return table.concat(buf)
      end
      if c == "\\" then
        local n = str:sub(pos + 1, pos + 1)
        local map = { n = "\n", t = "\t", r = "\r", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
        buf[#buf + 1] = map[n] or n
        pos = pos + 2
      else
        buf[#buf + 1] = c
        pos = pos + 1
      end
    end
    error("json: unterminated string")
  end
  local function num_val()
    local s = pos
    while pos <= #str and str:sub(pos, pos):match("[%-%+%d%.eE]") do
      pos = pos + 1
    end
    return tonumber(str:sub(s, pos - 1))
  end
  local function arr_val()
    pos = pos + 1
    local t = {}
    ws()
    if str:sub(pos, pos) == "]" then
      pos = pos + 1
      return t
    end
    while true do
      t[#t + 1] = value()
      ws()
      local c = str:sub(pos, pos)
      if c == "," then
        pos = pos + 1
        ws()
      elseif c == "]" then
        pos = pos + 1
        return t
      else
        error("json: expected , or ]")
      end
    end
  end
  local function obj_val()
    pos = pos + 1
    local t = {}
    ws()
    if str:sub(pos, pos) == "}" then
      pos = pos + 1
      return t
    end
    while true do
      ws()
      local k = str_val()
      ws()
      assert(str:sub(pos, pos) == ":", "json: expected :")
      pos = pos + 1
      ws()
      t[k] = value()
      ws()
      local c = str:sub(pos, pos)
      if c == "," then
        pos = pos + 1
      elseif c == "}" then
        pos = pos + 1
        return t
      else
        error("json: expected , or }")
      end
    end
  end
  value = function()
    ws()
    local c = str:sub(pos, pos)
    if c == '"' then
      return str_val()
    elseif c == "{" then
      return obj_val()
    elseif c == "[" then
      return arr_val()
    elseif c == "t" then
      pos = pos + 4
      return true
    elseif c == "f" then
      pos = pos + 5
      return false
    elseif c == "n" then
      pos = pos + 4
      return nil
    else
      return num_val()
    end
  end
  return value()
end
M.parse_json = parse_json

-- --------------------------------------------------------------- engine stubs
gfx = {}
local PALETTE = {
  "BLACK",
  "DARK_BLUE",
  "DARK_PURPLE",
  "DARK_GREEN",
  "BROWN",
  "DARK_GRAY",
  "LIGHT_GRAY",
  "WHITE",
  "RED",
  "ORANGE",
  "YELLOW",
  "GREEN",
  "BLUE",
  "INDIGO",
  "PINK",
  "PEACH",
}
for i, name in ipairs(PALETTE) do
  gfx["COLOR_" .. name] = i
end
local gfx_calls = {}
for _, fn in ipairs({
  "clear",
  "text",
  "text_ex",
  "rect",
  "rect_fill",
  "rect_ex",
  "circ",
  "circ_fill",
  "circ_ex",
  "line",
  "line_ex",
  "tri",
  "tri_fill",
  "px",
  "spr",
  "spr_ex",
  "shader_set",
  "shader_uniform",
}) do
  gfx[fn] = function(...)
    gfx_calls[#gfx_calls + 1] = { fn = fn, args = { ... } }
  end
end
-- Reset/read the recorded draw calls (used by the menu layout fit-check).
function M.reset_gfx()
  gfx_calls = {}
end
function M.gfx_calls()
  return gfx_calls
end

local SAVE
usagi = {
  GAME_W = 480,
  GAME_H = 270,
  SPRITE_SIZE = 16,
  PLATFORM = "test",
  IS_DEV = true,
  elapsed = 0,
  -- The bundled monogram font renders MONOSPACE at runtime: every glyph
  -- (letters, digits, punctuation, space) advances exactly 6px, with a 12px
  -- line height. Verified against the real engine via `usagi.measure_text`.
  -- Keep this matched to the engine so the layout-fit asserts catch real
  -- overflow instead of passing on an understated width.
  measure_text = function(s)
    return #s * 6, 12
  end,
  read_json = function(p)
    local f = assert(io.open("data/" .. p, "r"))
    local s = f:read("*a")
    f:close()
    return parse_json(s)
  end,
  save = function(t)
    SAVE = t
  end,
  load = function()
    return SAVE
  end,
  dump = function()
    return ""
  end,
}
effect = {
  hitstop = function() end,
  screen_shake = function() end,
  flash = function() end,
  slow_mo = function() end,
  stop = function() end,
}
sfx = { play = function() end, play_ex = function() end }
music = {
  play = function() end,
  loop = function() end,
  stop = function() end,
  play_ex = function() end,
  mutate = function() end,
}

return M

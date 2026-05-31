-- usagi-geo-td — geometric roguelike tower defense.
-- Entry point + scene dispatcher. All mutable state lives in the single
-- capitalized global `State`, assigned only in `_init` (survives live reload).
-- Scenes are modules exposing init/update/draw; `SwitchScene` swaps them on
-- the next frame. See docs/DESIGN.md for the architecture.

local menu     = require("scenes.menu")
local select   = require("scenes.select")
local game     = require("scenes.game")
local upgrade  = require("scenes.upgrade")
local route    = require("scenes.route")
local gameover = require("scenes.gameover")
local meta     = require("lib.meta")

local SCENES = {
  menu = menu,
  select = select,
  game = game,
  upgrade = upgrade,
  route = route,
  gameover = gameover,
}

function _config()
  return {
    name = "usagi-geo-td",
    game_id = "com.brandon.usagigeotd",
    game_width = 480,
    game_height = 270,
  }
end

-- Request a scene change; applied at the top of the next _update.
function SwitchScene(key)
  State.pending = key
end

function _init()
  State = {
    meta = meta.load(),
    run = nil,
    ui = { selected = nil, sell_mode = false, hover_x = 0, hover_y = 0, hover_valid = false, inspect = nil, mode = "standard" },
    summary = nil,
    current = nil,
    pending = nil,
    crt = true,
  }
  -- Background music is scene-driven (menu / combat / boss) via lib/audio,
  -- which each scene calls from its init/update -- nothing to start here.
  -- CRT / neon-glow post-process, with a pause-menu toggle.
  gfx.shader_set("crt")
  usagi.menu_item("CRT filter", function()
    State.crt = not State.crt
    gfx.shader_set(State.crt and "crt" or nil)
    return true -- keep the pause menu open
  end)
  SwitchScene("menu")
end

function _update(dt)
  if State.pending then
    local cur = State.current and SCENES[State.current]
    if cur and cur.close then cur.close() end
    State.current = State.pending
    State.pending = nil
    local nxt = SCENES[State.current]
    if nxt and nxt.init then nxt.init() end
  end
  local s = SCENES[State.current]
  if s and s.update then s.update(dt) end
end

function _draw(dt)
  if State.crt then
    gfx.shader_uniform("u_resolution", { usagi.GAME_W, usagi.GAME_H })
  end
  local s = SCENES[State.current]
  if s and s.draw then
    s.draw(dt)
  else
    gfx.clear(gfx.COLOR_BLACK)
  end
end

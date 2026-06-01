-- usagi-geo-td — geometric roguelike tower defense.
-- Entry point + scene dispatcher. All mutable state lives in the single
-- capitalized global `State`, assigned only in `_init` (survives live reload).
-- Scenes are modules exposing init/update/draw; `SwitchScene` swaps them on
-- the next frame. See docs/DESIGN.md for the architecture.

local menu = require("scenes.menu")
local select = require("scenes.select")
local game = require("scenes.game")
local upgrade = require("scenes.upgrade")
local route = require("scenes.route")
local contract = require("scenes.contract")
local gameover = require("scenes.gameover")
local meta = require("lib.meta")
local settings = require("lib.settings")
local pal = require("lib.palette")
local C = require("lib.const")

local SCENES = {
  menu = menu,
  select = select,
  game = game,
  upgrade = upgrade,
  route = route,
  contract = contract,
  gameover = gameover,
}

function _config()
  -- Resolution is single-sourced from lib.const (the game-layout source of truth)
  -- so _config and the C.GAME_* the HUD/field math read can't drift apart.
  return {
    name = "usagi-geo-td",
    game_id = "com.brandon.usagigeotd",
    game_width = C.GAME_W,
    game_height = C.GAME_H,
  }
end

-- Request a scene change; applied at the top of the next _update.
function SwitchScene(key)
  State.pending = key
end

function _init()
  local m = meta.load()
  State = {
    meta = m,
    settings = m.settings, -- M9: live settings (a reference into the meta save)
    run = nil,
    ui = {
      selected = nil,
      sell_mode = false,
      hover_x = 0,
      hover_y = 0,
      hover_valid = false,
      inspect = nil,
      mode = "standard",
      speed = 1,
    },
    summary = nil,
    current = nil,
    pending = nil,
    crt = m.settings.crt,
  }
  -- Background music is scene-driven (menu / combat / boss) via lib/audio,
  -- which each scene calls from its init/update -- nothing to start here.
  -- Apply persisted accessibility/comfort settings (M9): the high-contrast palette
  -- and the CRT / neon-glow post-process. Each pause-menu toggle flips the setting,
  -- applies it, and persists (settings live in the meta save).
  pal.set_contrast(State.settings.high_contrast)
  gfx.shader_set(State.crt and "crt" or nil)
  -- Pause-menu quick toggles for the in-combat-relevant settings (the engine caps
  -- these at 3; the full set lives on the menu Options tab). Clear first so a live
  -- reload re-registers cleanly instead of accumulating past the cap.
  if usagi.clear_menu_items then usagi.clear_menu_items() end
  usagi.menu_item("CRT filter", function()
    settings.toggle(State.settings, "crt")
    State.crt = State.settings.crt
    gfx.shader_set(State.crt and "crt" or nil)
    meta.save(State.meta)
    return true -- keep the pause menu open
  end)
  usagi.menu_item("High contrast", function()
    settings.toggle(State.settings, "high_contrast")
    pal.set_contrast(State.settings.high_contrast)
    meta.save(State.meta)
    return true
  end)
  usagi.menu_item("Screen shake", function()
    settings.toggle(State.settings, "shake")
    meta.save(State.meta)
    return true
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
  if State.crt then gfx.shader_uniform("u_resolution", { usagi.GAME_W, usagi.GAME_H }) end
  local s = SCENES[State.current]
  if s and s.draw then
    s.draw(dt)
  else
    gfx.clear(gfx.COLOR_BLACK)
  end
end

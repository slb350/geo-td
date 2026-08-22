-- name = usagi-geo-td
-- game_id = com.brandon.usagigeotd
-- game_width = 480
-- game_height = 270
--
-- Engine config frontmatter (usagi 1.3.0+), replacing the deprecated `_config()`.
-- Must stay on the very first lines: the engine reads this comment block until
-- the first non-comment line and takes only the lines with an `=`.
-- `game_id` is the save-data key -- changing it orphans every live player's save.
-- `game_width`/`game_height` must match C.GAME_W/C.GAME_H in lib/const.lua.
-- Why frontmatter and not usagi.conf (it does not survive export): docs/EXPORT.md.
--
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

local SCENES = {
  menu = menu,
  select = select,
  game = game,
  upgrade = upgrade,
  route = route,
  contract = contract,
  gameover = gameover,
}

-- Request a scene change; applied at the top of the next _update.
function SwitchScene(key)
  State.pending = key
end

function _init()
  local m = meta.load()
  -- One-time probe: does the save backend actually persist? On web a browser can
  -- block localStorage (privacy mode / Safari / Brave / extensions) and the engine
  -- swallows the write error, so saving silently no-ops. The menu surfaces this so
  -- a player isn't unknowingly losing unlocks/bank between sessions.
  local save_broken = not meta.persists(m)
  State = {
    meta = m,
    save_broken = save_broken,
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

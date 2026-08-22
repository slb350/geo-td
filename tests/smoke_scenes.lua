-- Scene-layer cases for the smoke suite: the map-select/game/upgrade/menu
-- scenes driven through update/draw with simulated input. Split out of
-- tests/smoke_core.lua to keep both files under the LOC limit.
--
-- Runs SECOND, right after smoke_core: it installs the shared scene globals
-- (State / SwitchScene / input) that every later suite reuses, so it must stay
-- ahead of them in tests/smoke.lua.

local harness = require("tests.harness") -- installs the fake engine globals

local meta = require("lib.meta")
local C = require("lib.const")
local maps = require("lib.maps")
local run_mod = require("lib.run")

local M = {}

-- The last rect_fill drawn before call index `idx` that contains point (x, y) --
-- i.e. the box a subsequent text call sits inside. Shared by the layout-fit
-- asserts (menu unlock rows, upgrade-draft cards) to prove drawn text fits its box.
local function find_enclosing_box(calls, idx, x, y)
  for k = idx - 1, 1, -1 do
    local prior = calls[k]
    if prior.fn == "rect_fill" then
      local a = prior.args
      if a[1] <= x and x < a[1] + a[3] and a[2] <= y and y < a[2] + a[4] then return a end
    end
  end
end

function M.run(check, near)
  -- ------------------------------------------------------------- scene layer
  -- Stub input + the global State/SwitchScene the scenes use, then drive each
  -- scene's update/draw once. This is the layer the upgrade-draft crash hid in
  -- (the lib-only tests above never touched scenes/).
  -- `over` backs input.mouse_over(): true = cursor is over the drawn game area.
  -- Defaults true so every pre-existing hover assert behaves as it always did.
  local clicks = { left = false, mx = 0, my = 0, over = true }
  input = {
    KEY_1 = 1,
    KEY_2 = 2,
    KEY_3 = 3,
    KEY_4 = 7,
    KEY_5 = 8,
    KEY_6 = 11,
    KEY_S = 4,
    KEY_O = 9,
    KEY_F = 10,
    KEY_D = 12,
    KEY_SPACE = 5,
    KEY_ENTER = 6,
    MOUSE_LEFT = 1,
    MOUSE_RIGHT = 2,
    MOUSE_MIDDLE = 3,
    BTN1 = 1,
    _keys = {}, -- settable simulated key-press state (tests toggle entries)
    _clicks = clicks, -- shared click state, so later suites can drive HUD clicks
    mouse = function()
      return clicks.mx, clicks.my
    end,
    mouse_over = function()
      return clicks.over
    end,
    mouse_pressed = function(b)
      return clicks.left and b == 1
    end,
    mouse_released = function()
      return false
    end,
    mouse_held = function()
      return false
    end,
    key_pressed = function(k)
      return k ~= nil and input._keys[k] == true
    end,
    key_held = function()
      return false
    end,
    key_released = function()
      return false
    end,
    pressed = function()
      return false
    end,
    held = function()
      return false
    end,
    released = function()
      return false
    end,
  }
  State = {
    meta = meta.default(),
    run = nil,
    ui = { selected = nil, sell_mode = false, hover_x = 0, hover_y = 0, hover_valid = false, speed = 1 },
    summary = nil,
    current = nil,
    pending = nil,
  }
  function SwitchScene(k)
    State.pending = k
  end

  local menu_s = require("scenes.menu")
  local select_s = require("scenes.select")
  local game_s = require("scenes.game")
  local upgrade_s = require("scenes.upgrade")
  -- the gameover scene is exercised by tests/smoke_report.lua (the report suite)

  menu_s.update(1 / 60)
  menu_s.draw(1 / 60)
  harness.reset_gfx()
  menu_s.draw(1 / 60)
  local gfx_calls = harness.gfx_calls()
  for i = 1, #gfx_calls do
    local call = gfx_calls[i]
    if call.fn == "text" then
      local text, x, y = call.args[1], call.args[2], call.args[3]
      for j = 1, #meta.SHOP do
        local it = meta.SHOP[j]
        if text == it.name or text == it.desc or text == it.cost .. " bank" or text == "OWNED" then
          local box = find_enclosing_box(gfx_calls, i, x, y)
          local _, h = usagi.measure_text(text)
          check(box ~= nil and y + h <= box[2] + box[4], text .. " fits inside menu unlock row")
        end
      end
    end
  end

  -- map-select scene: a locked tile is inert; an unlocked tile launches its map.
  State.run = nil
  State.pending = nil
  select_s.init()
  select_s.draw(1 / 60)
  local TW, TG, TILE_CY = 84, 6, 116
  local sx0 = (C.GAME_W - (#maps.ORDER * TW + (#maps.ORDER - 1) * TG)) * 0.5
  local function tile_cx(i)
    return sx0 + (i - 1) * (TW + TG) + TW * 0.5
  end
  clicks.left, clicks.mx, clicks.my = true, tile_cx(#maps.ORDER), TILE_CY -- hardest = locked
  select_s.update(1 / 60)
  check(State.run == nil and State.pending == nil, "map-select ignores a locked map")
  clicks.mx, clicks.my = tile_cx(1), TILE_CY -- easiest = unlocked
  select_s.update(1 / 60)
  clicks.left = false
  check(State.run ~= nil and State.run.path_name == maps.ORDER[1], "map-select launches the chosen map")
  check(State.pending == "game", "map-select switches to the game scene")
  State.pending = nil

  State.run = run_mod.new(State.meta, 9, "serpentine")
  State.run.money = 9999
  game_s.init()
  State.ui.selected = "pellet"
  clicks.left, clicks.mx, clicks.my = true, 200, 150
  game_s.update(1 / 60)
  clicks.left = false
  check(#State.run.towers >= 1, "game scene placed a tower via click")
  game_s.update(1 / 60)
  game_s.draw(1 / 60)
  -- exercise the combat-phase HUD (the ORBITAL action button render path)
  State.run.phase = "combat"
  game_s.draw(1 / 60)
  State.run.phase = "building"

  State.pending = nil
  upgrade_s.init()
  check(State.run.draft and #State.run.draft == 3, "upgrade drafted 3 cards")
  local pw0 = #State.run.powerups
  -- lockout: a frame with the mouse up arms the scene; no choice yet
  clicks.left = false
  upgrade_s.update(1 / 60)
  check(State.run.draft ~= nil and State.pending == nil, "upgrade ignores carried-over click (lockout)")
  -- now a fresh click on card 1 chooses
  clicks.left, clicks.mx, clicks.my = true, 104, 140
  upgrade_s.update(1 / 60)
  clicks.left = false
  check(#State.run.powerups == pw0 + 1, "upgrade applied exactly one powerup on click")
  check(State.pending == "game", "upgrade returns to game after a choice")
  upgrade_s.draw(1 / 60)

  -- layout fit: force the worst-case longest descriptions and assert every drawn
  -- line stays inside its card box (regression: long effect text spilled out).
  State.run.draft = {
    { key = "ring", rarity = 2 }, -- "splash leaves a dmg ring" (the widest)
    { key = "pierce", rarity = 3 }, -- "shots pierce +1 enemy"
    { key = "airburst", rarity = 2 }, -- "flyers burst on death"
  }
  harness.reset_gfx()
  upgrade_s.draw(1 / 60)
  local up_calls, up_rows = harness.gfx_calls(), 0
  for i = 1, #up_calls do
    local call = up_calls[i]
    if call.fn == "text" then
      local text, x, y = call.args[1], call.args[2], call.args[3]
      local box = find_enclosing_box(up_calls, i, x, y)
      local w, h = usagi.measure_text(text)
      up_rows = up_rows + 1
      check(box ~= nil and x + w <= box[1] + box[3], "upgrade card text fits horizontally: " .. text)
      check(box ~= nil and y + h <= box[2] + box[4], "upgrade card text fits vertically: " .. text)
    end
  end
  check(up_rows >= 9, "upgrade scene renders the three cards' text rows")
end

return M

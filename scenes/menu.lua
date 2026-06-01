-- Main menu (V2-M7): start a run and spend meta progression across four tabbed
-- panels -- Shop (the original permanent unlocks), Mastery (a small permanent
-- buff tree), Contracts (the meta-contract goal board), and Daily (today's
-- deterministic challenge). Reads/writes the global State (State.meta, State.ui).
-- A panel's clickable rows are laid out by M.tab_rows so the update hit-test and
-- the draw share one geometry (and tests can target a row precisely).

local C       = require("lib.const")
local pal     = require("lib.palette")
local meta    = require("lib.meta")
local fx      = require("lib.fx")
local ui      = require("lib.ui")
local audio   = require("lib.audio")
local mastery = require("lib.mastery")
local mcontract = require("lib.metacontract")
local daily   = require("lib.daily")
local maps    = require("lib.maps")
local modes   = require("lib.modes")
local share   = require("lib.share")
local settings = require("lib.settings")
local select_s = require("scenes.select")

local M = {}

local start_btn = { x = 190, y = 46, w = 100, h = 18 }

-- Tab bar + content panel geometry (static, so file-scope constants).
local TABS = {
  { id = "shop",      name = "SHOP" },
  { id = "mastery",   name = "MASTERY" },
  { id = "contracts", name = "CONTRACTS" },
  { id = "daily",     name = "DAILY" },
  { id = "options",   name = "OPTIONS" },
}
local TAB_Y, TAB_H, TAB_GAP = 70, 16, 6
local PANEL = { x = 40, y = 94, w = 400, h = 150 }
local TAB_X0 = PANEL.x
local TAB_W = (PANEL.w - (#TABS - 1) * TAB_GAP) / #TABS

local function tab_rect(i)
  return { x = TAB_X0 + (i - 1) * (TAB_W + TAB_GAP), y = TAB_Y, w = TAB_W, h = TAB_H }
end

local function active_tab()
  return State.ui.menu_tab or "shop"
end

-- Clickable rows for a tab: each { x, y, w, h, id } where id is the action key
-- (a shop/mastery node id, or "daily"). Shop/Mastery are buy-rows; Daily is one
-- launch button; Contracts is read-only (no rows). The geometry is static (it
-- depends only on the constant panel + content lengths), so lay each tab out once
-- and cache -- the cache is a file-scope local, so live-reload re-measures.
local rows_cache = {}
function M.tab_rows(tab)
  if rows_cache[tab] then return rows_cache[tab] end
  local rows = {}
  if tab == "shop" then
    local rh = 30
    for i = 1, #meta.SHOP do
      rows[i] = { x = PANEL.x, y = PANEL.y + 6 + (i - 1) * (rh + 2), w = PANEL.w, h = rh,
                  id = meta.SHOP[i].id }
    end
  elseif tab == "mastery" then
    local rh = 22                       -- single text line per node (6 fit the panel)
    for i = 1, #mastery.ORDER do
      rows[i] = { x = PANEL.x, y = PANEL.y + (i - 1) * rh, w = PANEL.w, h = rh,
                  id = mastery.ORDER[i] }
    end
  elseif tab == "daily" then
    rows[1] = { x = (C.GAME_W - 140) * 0.5, y = PANEL.y + PANEL.h - 28, w = 140, h = 20, id = "daily" }
  elseif tab == "options" then
    local rh = 22
    for i = 1, #settings.DEFS do
      rows[i] = { x = PANEL.x, y = PANEL.y + (i - 1) * rh, w = PANEL.w, h = rh, id = settings.DEFS[i].id }
    end
  end
  rows_cache[tab] = rows
  return rows
end

-- Today's daily challenge + its share code, memoized so the 60fps menu redraw
-- doesn't re-roll the daily (os.time + a derived rng) or rebuild the share string
-- every frame. Invalidated on each menu (re)entry by M.init so they track the date,
-- and on live-reload (file-scope locals).
local daily_cache, daily_code_cache
local function todays_daily()
  daily_cache = daily_cache or daily.for_day(daily.today())
  return daily_cache
end
local function todays_code()
  if not daily_code_cache then
    local d = todays_daily()
    daily_code_cache = share.encode({ seed = d.seed, map = d.map, mode = d.mode, tag = "D" .. d.day })
  end
  return daily_code_cache
end

function M.init()
  audio.set("menu")
  State.ui.menu_tab = State.ui.menu_tab or "shop"
  mcontract.refresh(State.meta)   -- ensure the contract board is populated for display
  daily_cache, daily_code_cache = nil, nil   -- re-roll today's daily on (re)entering the menu
end

local function open_select()
  fx.click_sfx()
  SwitchScene("select")
end

-- Act on a click inside a buy-row for the active tab.
local function click_row(tab, id)
  if tab == "shop" then
    if meta.can_buy(State.meta, id) then meta.buy(State.meta, id) end
  elseif tab == "mastery" then
    if mastery.can_buy(State.meta, id) then
      mastery.buy(State.meta, id)
      meta.save(State.meta)
    end
  elseif tab == "daily" and id == "daily" then
    local d = todays_daily()
    select_s.start_map(d.map, d.mode, d.seed)
  elseif tab == "options" then
    for i = 1, #settings.DEFS do
      local def = settings.DEFS[i]
      if def.id == id then
        settings.apply(State.settings, def)
        if id == "crt" then
          State.crt = State.settings.crt
          gfx.shader_set(State.crt and "crt" or nil)
        elseif id == "high_contrast" then
          pal.set_contrast(State.settings.high_contrast)
        end
        meta.save(State.meta)
        return
      end
    end
  end
end

function M.update(dt)
  -- Space or BTN1 (default keyboard Z / gamepad primary) plays. Enter is NOT
  -- read: the engine reserves Esc / P / Enter / Start for its built-in pause menu.
  if input.key_pressed(input.KEY_SPACE) or input.pressed(input.BTN1) then
    open_select()
    return
  end
  if not input.mouse_pressed(input.MOUSE_LEFT) then return end
  local mx, my = input.mouse()
  if ui.in_rect(mx, my, start_btn) then open_select(); return end
  for i = 1, #TABS do
    if ui.in_rect(mx, my, tab_rect(i)) then
      State.ui.menu_tab = TABS[i].id
      fx.click_sfx()
      return
    end
  end
  local tab = active_tab()
  local rows = M.tab_rows(tab)
  for i = 1, #rows do
    if ui.in_rect(mx, my, rows[i]) then click_row(tab, rows[i].id); return end
  end
end

-- ----------------------------------------------------------------- panel draws
local text_h = nil
local function th() text_h = text_h or ui.text_height(); return text_h end

local function draw_shop(rows)
  local m = State.meta
  for i = 1, #meta.SHOP do
    local it, r = meta.SHOP[i], rows[i]
    local owned = m.unlocks[it.id] == true
    local afford = m.currency >= it.cost
    gfx.rect_fill(r.x, r.y, r.w, r.h, pal.HUD_PANEL)
    local tag = owned and "OWNED" or (it.cost .. " bank")
    local tag_col = owned and pal.GOOD or (afford and pal.MONEY or pal.TEXT_DIM)
    gfx.text(tag, r.x + r.w - usagi.measure_text(tag) - 8, r.y + 4, tag_col)
    gfx.text(it.name, r.x + 8, r.y + 4, owned and pal.GOOD or pal.TEXT)
    gfx.text(it.desc, r.x + 8, r.y + 4 + th(), pal.TEXT_DIM)
  end
end

local function mastery_tag(d, owned)
  if owned then return "OWNED" end
  local s = d.cost .. "b"
  if d.shards then s = s .. " +" .. d.shards .. "s" end
  return s
end

local function draw_mastery(rows)
  local m = State.meta
  for i = 1, #mastery.ORDER do
    local id = mastery.ORDER[i]
    local d, r = mastery.DEFS[id], rows[i]
    local owned = mastery.owned(m, id)
    local buyable = mastery.can_buy(m, id)
    gfx.rect_fill(r.x, r.y, r.w, r.h - 2, pal.HUD_PANEL)
    local tag = mastery_tag(d, owned)
    local tag_col = owned and pal.GOOD or (buyable and pal.MONEY or pal.TEXT_DIM)
    gfx.text(tag, r.x + r.w - usagi.measure_text(tag) - 8, r.y + 5, tag_col)
    local name = d.track .. ": " .. d.name
    gfx.text(name, r.x + 8, r.y + 5, owned and pal.GOOD or pal.TEXT)
    gfx.text(d.desc, r.x + 16 + usagi.measure_text(name), r.y + 5, pal.TEXT_DIM)
  end
end

local function draw_contracts()
  local m = State.meta
  local board = m.contract_board or {}
  local badges, done = 0, 0
  for _ in pairs(m.badges or {}) do badges = badges + 1 end
  for _ in pairs(m.completed_contracts or {}) do done = done + 1 end
  gfx.text("badges " .. badges .. "    completed " .. done .. "/" .. #mcontract.ORDER,
    PANEL.x + 8, PANEL.y, pal.TEXT_DIM)
  local rh = 38
  for i = 1, #board do
    local d = mcontract.DEFS[board[i]]
    local y = PANEL.y + 16 + (i - 1) * rh
    gfx.rect_fill(PANEL.x, y, PANEL.w, rh - 4, pal.HUD_PANEL)
    gfx.text(d.name, PANEL.x + 8, y + 4, pal.TEXT)
    local tag = "+" .. d.shards .. " shards"
    gfx.text(tag, PANEL.x + PANEL.w - usagi.measure_text(tag) - 8, y + 4, gfx.COLOR_PINK)
    gfx.text(d.desc, PANEL.x + 8, y + 4 + th(), pal.TEXT_DIM)
  end
end

local function draw_daily(rows)
  local d = todays_daily()
  local layout = maps.get(d.map)
  local mode = modes.get(d.mode)
  ui.center_text("TODAY'S CHALLENGE", PANEL.y + 8, pal.TEXT, 1)
  ui.center_text(layout.name .. "   -   " .. mode.name, PANEL.y + 30, gfx.COLOR_ORANGE, 1)
  ui.center_text(mode.desc, PANEL.y + 46, pal.TEXT_DIM, 1)
  -- the deterministic share code (recreates this exact daily from seed/map/mode)
  ui.center_text(todays_code(), PANEL.y + 66, pal.MONEY, 1)
  local b = rows[1]
  local mx, my = input.mouse()
  local hov = ui.in_rect(mx, my, b)
  gfx.rect_fill(b.x, b.y, b.w, b.h, pal.GOOD)
  gfx.rect(b.x, b.y, b.w, b.h, hov and pal.HUD_SEL or pal.PATH_EDGE)
  ui.center_text("PLAY DAILY", b.y + 6, gfx.COLOR_BLACK, 1)
end

local function draw_options(rows)
  local s = State.settings or settings.defaults()
  for i = 1, #settings.DEFS do
    local def, r = settings.DEFS[i], rows[i]
    local val = s[def.id]
    gfx.rect_fill(r.x, r.y, r.w, r.h - 2, pal.HUD_PANEL)
    gfx.text(def.name, r.x + 8, r.y + 5, pal.TEXT)
    local label, col
    if def.kind == "volume" then
      label, col = math.floor((val or 0) * 100 + 0.5) .. "%", pal.MONEY
    else
      label, col = (val and "ON" or "OFF"), (val and pal.GOOD or pal.TEXT_DIM)
    end
    gfx.text(label, r.x + r.w - usagi.measure_text(label) - 8, r.y + 5, col)
  end
  ui.center_text("keys:  1-6 towers   S sell   O orbital   D discharge   SPACE wave",
    PANEL.y + 134, pal.TEXT_DIM, 1)
end

function M.draw(dt)
  gfx.clear(pal.BG)
  ui.center_text("USAGI GEO TD", 12, gfx.COLOR_WHITE, 2)

  local m = State.meta
  ui.center_text("best wave " .. m.best_wave .. "    bank " .. m.currency
    .. "    shards " .. (m.bank_shards or 0), 32, pal.TEXT_DIM, 1)

  gfx.rect_fill(start_btn.x, start_btn.y, start_btn.w, start_btn.h, pal.GOOD)
  ui.center_text("SELECT MAP", start_btn.y + 5, gfx.COLOR_BLACK, 1)

  -- tab bar
  local tab = active_tab()
  for i = 1, #TABS do
    local r = tab_rect(i)
    local on = TABS[i].id == tab
    gfx.rect_fill(r.x, r.y, r.w, r.h, on and pal.HUD_SEL or pal.HUD_PANEL)
    gfx.text_ex(TABS[i].name, r.x + (r.w - usagi.measure_text(TABS[i].name)) * 0.5, r.y + 4,
      1, 0, on and gfx.COLOR_WHITE or pal.TEXT_DIM, 1)
  end

  local rows = M.tab_rows(tab)
  if tab == "shop" then draw_shop(rows)
  elseif tab == "mastery" then draw_mastery(rows)
  elseif tab == "contracts" then draw_contracts()
  elseif tab == "daily" then draw_daily(rows)
  elseif tab == "options" then draw_options(rows) end

  ui.center_text("press Z / Space to play", C.GAME_H - 10, pal.TEXT_DIM, 1)
end

return M

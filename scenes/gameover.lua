-- Game over: award meta-currency for the run (once, in init), persist via
-- lib/meta, then show a run-report stat sheet (lib/report aggregates the run's
-- instrumented counters). Returns to the menu on click/key.

local C      = require("lib.const")
local pal    = require("lib.palette")
local meta   = require("lib.meta")
local maps   = require("lib.maps")
local fx     = require("lib.fx")
local ui     = require("lib.ui")
local audio  = require("lib.audio")
local report = require("lib.report")
local tower  = require("lib.tower")
local metacontract = require("lib.metacontract")
local replay = require("lib.replay")

local M = {}

-- Label / value columns for the centered stat sheet.
local LX, VX = 150, 250

function M.init()
  audio.set("menu")
  local run = State.run
  if not run then SwitchScene("menu"); return end
  local stats = report.build(run)
  local award, unlocked = meta.finish_run(State.meta, stats.wave, stats.bosses_killed,
    run.path_name, stats.bank_shards)
  -- M7: score the run against the meta-contract board (reads the report stats),
  -- paying shards + badges and refilling the board. Persist the result.
  local done = metacontract.evaluate(State.meta, stats)
  meta.save(State.meta)
  stats.award = award
  stats.bank = State.meta.currency
  stats.shards_total = State.meta.bank_shards
  stats.contracts_done = {}
  for i = 1, #done do stats.contracts_done[i] = metacontract.DEFS[done[i]].name end
  stats.unlocked = unlocked and maps.get(unlocked).name or nil
  stats.replay = replay.snapshot(run, stats)         -- full replay/verifier snapshot (M9)
  stats.share = stats.replay.share                   -- shareable run code (M9)
  State.summary = stats
  effect.stop()
  fx.clear()
  fx.over_sfx()
end

function M.update(dt)
  if input.mouse_pressed(input.MOUSE_LEFT)
    or input.key_pressed(input.KEY_SPACE) or input.key_pressed(input.KEY_ENTER)
    or input.pressed(input.BTN1) then
    State.run = nil
    SwitchScene("menu")
  end
end

local function row(y, label, value, color)
  gfx.text(label, LX, y, pal.TEXT_DIM)
  gfx.text(value, VX, y, color or pal.TEXT)
end

function M.draw(dt)
  gfx.clear(pal.BG)
  local s = State.summary
  if not s then
    ui.center_text("RUN OVER", 120, gfx.COLOR_RED, 2)
    return
  end

  ui.center_text("RUN OVER", 24, gfx.COLOR_RED, 2)
  local sub = "wave " .. s.wave
  if s.map then sub = sub .. "  on  " .. s.map end
  if s.mode then sub = sub .. "  -  " .. s.mode end   -- challenge mode (M6), if any
  ui.center_text(sub, 52, pal.TEXT, 1)

  local y = 74
  row(y, "bosses", tostring(s.bosses_killed)); y = y + 15
  row(y, "kills", tostring(s.kills)); y = y + 15
  row(y, "leaked", tostring(s.leaked), gfx.COLOR_RED); y = y + 15
  row(y, "spent", "$" .. s.money_spent, gfx.COLOR_YELLOW); y = y + 15
  row(y, "score", tostring(s.score)); y = y + 15

  -- top tower: color swatch + name + applied damage (or "none")
  gfx.text("top tower", LX, y, pal.TEXT_DIM)
  if s.top_tower then
    local def = tower.DEFS[s.top_tower.kind]
    gfx.rect_fill(VX, y, 6, 6, pal.resolve(def.color))
    gfx.text(def.name .. "  " .. math.floor(s.top_tower.damage + 0.5), VX + 10, y, pal.TEXT)
  else
    gfx.text("none", VX, y, pal.TEXT_DIM)
  end
  y = y + 15
  row(y, "favorite", s.favorite_name or "none"); y = y + 15
  if s.contracts and s.contracts > 0 then
    row(y, "contracts", s.contracts .. "  (" .. s.bank_shards .. " shards)", gfx.COLOR_ORANGE); y = y + 15
  end

  ui.center_text("+" .. s.award .. " bank   (total " .. s.bank .. ")", y + 6, gfx.COLOR_YELLOW, 1)
  local ny = y + 18
  if s.unlocked then
    ui.center_text("NEW MAP UNLOCKED  -  " .. s.unlocked, ny, gfx.COLOR_GREEN, 1); ny = ny + 14
  end
  -- M7: meta-contracts completed by this run (shards + badges earned)
  if s.contracts_done and #s.contracts_done > 0 then
    ui.center_text("CONTRACT  -  " .. table.concat(s.contracts_done, ", "), ny, gfx.COLOR_PINK, 1)
  end
  if s.share then ui.center_text(s.share, C.GAME_H - 26, pal.TEXT_DIM, 1) end   -- shareable run code (M9)
  ui.center_text("click to return to menu", C.GAME_H - 14, pal.TEXT_DIM, 1)
end

return M

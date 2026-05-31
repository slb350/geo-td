-- Map-lab + share-code cases (V2-M8): the absolute layout validator over every
-- shipped map and route variant (bounds / endpoints / length / buildability), the
-- validator's rejection of malformed layouts, and the share-code round-trip +
-- graceful failure on a bad marker/schema/seed/map/mode. Run by smoke.lua via
-- M.run(check, near); pure (no scene globals needed).

local C     = require("lib.const")
local maps  = require("lib.maps")
local share = require("lib.share")
local modes = require("lib.modes")
local daily = require("lib.daily")

local M = {}

function M.run(check, near)
  -- ----------------------------------------------- every map + variant validates
  for i = 1, #maps.ORDER do
    local name = maps.ORDER[i]
    local ok, rows = maps.validate_layout(name)
    check(ok, name .. " layout + all variants pass validation")
    check(#rows >= 1 and rows[1].label == name, name .. " validation reports the base row")
    for r = 1, #rows do
      local mt = rows[r].metrics
      check(mt.segs >= 1 and mt.length > C.MAP_MIN_LEN and mt.buildable > 0,
        rows[r].label .. " reports sane metrics")
    end
  end

  -- --------------------------------------------------- validator rejects bad data
  local good = maps.get("serpentine").nodes
  check((maps.validate(good)), "a real layout validates")
  check(not (maps.validate({ { 10, 10 } })), "a single-node layout is rejected")
  check(not (maps.validate({ { 10, 10 }, { 9999, 10 } })), "an out-of-bounds node is rejected")
  check(not (maps.validate({ { 10, 10 }, { 20, 20 } })), "a too-short route is rejected")
  check(not (maps.validate({ { 10, 10 }, { 15, 12 }, { 300, 240 } })), "a near-zero edge is rejected")
  do
    local _, reason = maps.validate({ { 10, 10 }, { 9999, 10 } })
    check(type(reason) == "string" and reason:find("bounds"), "the rejection names the bounds failure")
  end

  -- ------------------------------------------------------- share-code round-trip
  local function roundtrip(cfg, label)
    local code = share.encode(cfg)
    check(type(code) == "string" and code:find("^GTD2%-1%-"), label .. ": code carries marker + schema")
    local back, err = share.decode(code)
    check(back ~= nil, label .. ": decodes (" .. tostring(err) .. ")")
    if back then
      check(back.seed == cfg.seed, label .. ": seed round-trips")
      check(back.map == cfg.map, label .. ": map round-trips")
      check(back.mode == (cfg.mode or modes.DEFAULT), label .. ": mode round-trips")
      check(back.tag == (cfg.tag and cfg.tag:upper() or nil), label .. ": tag round-trips")
    end
  end
  roundtrip({ seed = 1234, map = "serpentine", mode = "hardcore" }, "basic")
  roundtrip({ seed = 1, map = "zigzag" }, "default mode")
  roundtrip({ seed = 2600000000, map = "switchback", mode = "boss_rush", tag = "D20235" }, "big seed + tag")

  -- case-insensitive decode (a user may type lowercase)
  do
    local back = share.decode("gtd2-1-ya-chicane-no_rail")
    check(back ~= nil and back.map == "chicane" and back.mode == "no_rail", "decode is case-insensitive")
  end

  -- --------------------------------------------------------- graceful failures
  check((share.decode("NOPE-1-YA-ZIGZAG-STANDARD")) == nil, "a bad marker is rejected")
  check((share.decode("GTD2-9-YA-ZIGZAG-STANDARD")) == nil, "an unsupported schema is rejected")
  check((share.decode("GTD2-1-YA-NOTAMAP-STANDARD")) == nil, "an unknown map is rejected")
  check((share.decode("GTD2-1-YA-ZIGZAG-NOTAMODE")) == nil, "an unknown mode is rejected")
  check((share.decode("GTD2-1--ZIGZAG-STANDARD")) == nil, "an empty seed is rejected")
  check((share.decode("GTD2-1")) == nil, "a truncated code is rejected")
  check((share.decode(12345)) == nil, "a non-string is rejected")
  do
    local _, reason = share.decode("GTD2-1-YA-NOTAMAP-STANDARD")
    check(reason == "unknown map", "the failure reason names the unknown map")
  end

  -- ----------------------------------------------- a daily encodes + decodes back
  do
    local dly = daily.for_day(20235)
    local code = share.encode({ seed = dly.seed, map = dly.map, mode = dly.mode, tag = "D" .. dly.day })
    local back = share.decode(code)
    check(back ~= nil and back.seed == dly.seed and back.map == dly.map and back.mode == dly.mode,
      "a daily's share code recreates its seed/map/mode")
    check(back.tag == "D20235", "the daily share code carries the day tag")
  end
end

return M

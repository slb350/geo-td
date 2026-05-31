-- Map lab (V2-M8): a headless validator + preview generator for the map catalogue.
-- It checks every shipped layout (and each route variant) against the shared map
-- invariants (lib/maps.validate -- bounds, segment count, edge lengths, length,
-- buildable area) and prints a preview table: difficulty rank, segments, length,
-- buildable-cell estimate, variant count, and pass/fail. Adding a map then means
-- "drop a JSON row, run map_lab, see PASS" instead of guesswork. Also demonstrates
-- the deterministic share code for each map. Run from the project root:
--
--     luajit tools/map_lab.lua
--
-- Not part of the smoke suite (a reporting tool); the same maps.validate sweep is
-- asserted in tests/smoke_share.lua.

package.path = "./?.lua;" .. package.path
require("tests.harness")   -- installs the fake engine globals (read_json etc.)

local maps  = require("lib.maps")
local share = require("lib.share")
local modes = require("lib.modes")

print("map lab | layout + variant validation | share codes")
print(("%-22s %-4s %-4s %-6s %-5s %-5s %s")
  :format("layout", "rank", "segs", "len", "build", "vars", "status"))

local all_ok = true
for i = 1, #maps.ORDER do
  local name = maps.ORDER[i]
  local layout = maps.get(name)
  local ok, rows = maps.validate_layout(name)
  all_ok = all_ok and ok
  local nvars = #(layout.variants or {})
  for r = 1, #rows do
    local row, m = rows[r], rows[r].metrics
    local rank = (r == 1) and tostring(i) or ""
    local vars = (r == 1) and tostring(nvars) or ""
    print(("%-22s %-4s %-4d %-6d %-5d %-5s %s")
      :format(row.label, rank, m.segs, math.floor(m.length + 0.5), m.buildable, vars,
        row.ok and "PASS" or ("FAIL: " .. row.reason)))
  end
  -- a sample share code for this map on the standard mode (seed 1)
  print(("    share: %s"):format(share.encode({ seed = 1, map = name, mode = modes.DEFAULT })))
end

print(all_ok and "all layouts + variants valid" or "VALIDATION FAILURES ABOVE")
os.exit(all_ok and 0 or 1)

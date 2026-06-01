-- Lingering splash damage rings (M2 "Aftershock" card): a splash impact can
-- leave a ground ring that ticks area damage a few times before fading. Pooled
-- like projectiles (nothing references a ring), and credited to the firing
-- tower via run.credit_damage so the M1 run-report attribution stays accurate.
-- Lifetime is tick-count based (not a wall clock), so every ring deals exactly
-- C.RING_TICKS pulses regardless of frame timing.

local C       = require("lib.const")
local enemy   = require("lib.enemy")
local run_lib = require("lib.run")

local M = {}

-- opts: radius, damage (per tick), tower_id
function M.spawn(run, x, y, opts)
  local list = run.rings
  list.n = list.n + 1
  local r = list[list.n]
  if not r then r = {}; list[list.n] = r end
  r.x, r.y = x, y
  r.radius = opts.radius
  r.damage = opts.damage
  r.tower_id = opts.tower_id
  r.ticks = opts.ticks or C.RING_TICKS    -- Diamond Wake resonance passes an extra tick
  r.ticks0 = r.ticks                      -- starting count: normalizes the visual fade
  r.timer = C.RING_INTERVAL
  return r
end

local function tick(run, r)
  local r2 = r.radius * r.radius
  local list = run.enemies
  local n = list.n   -- a tick may split-spawn; only hit enemies present now
  for i = 1, n do
    local e = list[i]
    if not e.dead then
      local dx, dy = e.x - r.x, e.y - r.y
      if dx * dx + dy * dy <= r2 then
        local _, applied = enemy.damage(run, e, r.damage)
        run_lib.credit_damage(run, r.tower_id, applied)
      end
    end
  end
end

function M.update(run, dt)
  local list = run.rings
  local i = 1
  while i <= list.n do
    local r = list[i]
    r.timer = r.timer - dt
    if r.timer <= 0 then
      tick(run, r)
      r.ticks = r.ticks - 1
      r.timer = r.timer + C.RING_INTERVAL
    end
    if r.ticks <= 0 then
      list[i] = list[list.n]; list[list.n] = r; list.n = list.n - 1
    else
      i = i + 1
    end
  end
end

function M.draw(run)
  local list = run.rings
  for i = 1, list.n do
    local r = list[i]
    -- dim, bloom-friendly pulse: a fading ring that shrinks as it spends ticks.
    -- Normalized against the ring's OWN starting ticks so a Diamond Wake ring (4
    -- ticks) still fades 1->0 instead of overshooting its damage radius.
    local frac = r.ticks / r.ticks0
    gfx.circ(r.x, r.y, r.radius * (0.6 + 0.4 * frac), gfx.COLOR_ORANGE)
    gfx.circ(r.x, r.y, r.radius * 0.5 * frac, gfx.COLOR_YELLOW)
  end
end

return M
